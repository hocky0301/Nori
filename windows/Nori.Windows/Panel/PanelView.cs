using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Nori.Core;
using Nori.Windows.Resources;

namespace Nori.Windows.Panel;

internal sealed class PanelViewCallbacks
{
    public required Action<string> QueryChanged { get; init; }
    public required Action<PanelFilter> ChipClicked { get; init; }
    public required Func<ContextMenu> MenuRequested { get; init; }
    public required Func<HintBarModel.Input> HintInput { get; init; }
    public required CardCallbacks Cards { get; init; }
    public required Func<string?> PausedText { get; init; }
    public required Func<string> HotkeyText { get; init; }
    public required Action WarningChipClicked { get; init; }
}

/// <summary>
/// Builds the panel's visual tree from the <see cref="PanelModel"/>: search row, chips, sections
/// with cards, empty states, hint bar, toast and the clear-history overlay. Rebuilt wholesale when
/// the row set changes; selection and modifier changes are patched in place.
/// </summary>
internal sealed class PanelView
{
    private const int MaxRenderedRows = 300;

    private readonly Theme _theme;
    private readonly PanelModel _model;
    private readonly NoriSettings _settings;
    private readonly CardFactory _cards;
    private readonly PanelViewCallbacks _cb;

    private readonly Grid _root = new();
    private readonly TextBox _search;
    private readonly TextBlock _placeholder;
    private readonly TextBlock _pauseGlyph;
    private readonly StackPanel _chips = new() { Orientation = Orientation.Horizontal };
    private readonly ScrollViewer _scroller;
    private readonly StackPanel _list = new();
    private readonly Grid _listArea = new();
    private readonly StackPanel _hintBar = new() { Orientation = Orientation.Horizontal, Height = 28 };
    private readonly Border _hintRow;
    private readonly Border _toast;
    private readonly TextBlock _toastText;
    private readonly DispatcherTimer _toastTimer = new() { Interval = TimeSpan.FromSeconds(4) };
    private Border? _overlay;
    private readonly Dictionary<Guid, Border> _cardsById = [];
    private bool _suppressQueryEvents;

    public PanelView(Theme theme, PanelModel model, NoriSettings settings, CardFactory cards, PanelViewCallbacks callbacks)
    {
        _theme = theme;
        _model = model;
        _settings = settings;
        _cards = cards;
        _cb = callbacks;

        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        // Search row (36).
        _search = new TextBox
        {
            Background = Theme.Transparent,
            BorderThickness = new Thickness(0),
            FontSize = 14,
            FontFamily = Theme.UiFont,
            Foreground = theme.Primary,
            CaretBrush = theme.Primary,
            VerticalContentAlignment = VerticalAlignment.Center,
            Padding = new Thickness(0),
            Margin = new Thickness(0),
        };
        // The placeholder must exist before the handler can hide it.
        _placeholder = Ui.Text(Strings.Get("Search_Placeholder"), 14, theme.Tertiary);
        _search.TextChanged += (_, _) =>
        {
            _placeholder.Visibility = _search.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            if (!_suppressQueryEvents) _cb.QueryChanged(_search.Text);
        };
        _placeholder.IsHitTestVisible = false;
        _pauseGlyph = Ui.Glyph(Ui.GlyphPause, 12, theme.Warning);
        _pauseGlyph.Margin = new Thickness(8, 0, 0, 0);
        _pauseGlyph.Visibility = Visibility.Collapsed;

        var searchGrid = new Grid { Height = 36 };
        searchGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        searchGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        searchGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        searchGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var searchGlyph = Ui.Glyph(Ui.GlyphSearch, 13, theme.Secondary);
        searchGlyph.Margin = new Thickness(14, 0, 8, 0);
        Grid.SetColumn(searchGlyph, 0);
        searchGrid.Children.Add(searchGlyph);
        var fieldHost = new Grid();
        fieldHost.Children.Add(_placeholder);
        fieldHost.Children.Add(_search);
        Grid.SetColumn(fieldHost, 1);
        searchGrid.Children.Add(fieldHost);
        Grid.SetColumn(_pauseGlyph, 2);
        searchGrid.Children.Add(_pauseGlyph);
        var more = Ui.Glyph(Ui.GlyphMore, 16, theme.Secondary);
        more.Opacity = 0.5;
        more.Margin = new Thickness(10, 0, 12, 0);
        more.Cursor = Cursors.Hand;
        more.MouseEnter += (_, _) => more.Opacity = 1;
        more.MouseLeave += (_, _) => more.Opacity = 0.5;
        more.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            var menu = _cb.MenuRequested();
            menu.PlacementTarget = more;
            menu.IsOpen = true;
        };
        Grid.SetColumn(more, 3);
        searchGrid.Children.Add(more);
        var searchPill = new Border
        {
            Child = searchGrid,
            Background = theme.SearchFill,
            CornerRadius = new CornerRadius(Ui.SearchRadius),
            Margin = new Thickness(Ui.Inset, Ui.Inset, Ui.Inset, 0),
        };
        Grid.SetRow(searchPill, 0);
        _root.Children.Add(searchPill);

        // Chips (24).
        _chips.Height = 24;
        _chips.Margin = new Thickness(Ui.Inset, Ui.RowGap, Ui.Inset, 0);
        Grid.SetRow(_chips, 1);
        _root.Children.Add(_chips);

        // List.
        _scroller = new ScrollViewer
        {
            Content = _list,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
            PanningMode = PanningMode.VerticalOnly,
        };
        _listArea.Margin = new Thickness(Ui.Inset, 0, Ui.Inset, 0);
        _listArea.Children.Add(_scroller);
        _toastText = Ui.Text(string.Empty, 12, theme.Primary, FontWeights.Medium);
        _toast = new Border
        {
            Child = _toastText,
            Background = theme.ToastFill,
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(14, 6, 14, 6),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 0, 10),
            Visibility = Visibility.Collapsed,
            IsHitTestVisible = false,
        };
        _listArea.Children.Add(_toast);
        Grid.SetRow(_listArea, 2);
        _root.Children.Add(_listArea);
        _toastTimer.Tick += (_, _) => HideToast();

        // Hint bar (28) with a hairline above.
        var hintStack = new StackPanel { Margin = new Thickness(Ui.Inset, Ui.RowGap, Ui.Inset, Ui.Inset) };
        hintStack.Children.Add(new Border { Height = 1, Background = theme.Separator, Margin = new Thickness(0, 0, 0, 0) });
        hintStack.Children.Add(_hintBar);
        _hintRow = new Border { Child = hintStack };
        Grid.SetRow(_hintRow, 3);
        _root.Children.Add(_hintRow);
    }

    public FrameworkElement Root => _root;
    public TextBox SearchBox => _search;
    public bool SearchHasSelection => _search.SelectionLength > 0;

    public void FocusSearch()
    {
        _search.Focus();
        Keyboard.Focus(_search);
        _search.CaretIndex = _search.Text.Length;
    }

    public void SetQuery(string text)
    {
        _suppressQueryEvents = true;
        _search.Text = text;
        _search.CaretIndex = text.Length;
        _suppressQueryEvents = false;
    }

    public void SelectAllSearch() => _search.SelectAll();

    /// <summary>Full rebuild: chips, sections and cards, empty state, hint bar, pause placeholder.</summary>
    public void Rebuild()
    {
        UpdateSearchState();
        RebuildChips();
        RebuildList();
        RebuildHintBar();
    }

    public void UpdateSearchState()
    {
        var paused = _cb.PausedText();
        _pauseGlyph.Visibility = paused is null ? Visibility.Collapsed : Visibility.Visible;
        _placeholder.Text = paused ?? Strings.Get("Search_Placeholder");
    }

    private void RebuildChips()
    {
        _chips.Children.Clear();
        foreach (var filter in PanelFilterExtensions.AllFilters)
        {
            var selected = filter == _model.Filter;
            var count = filter == PanelFilter.All ? 1 : _model.CountFor(filter);
            var label = Ui.Text(Ui.FilterLabel(filter), 12, selected ? Brushes.White : _theme.Secondary, selected ? FontWeights.SemiBold : FontWeights.Medium);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            var chip = new Border
            {
                Child = label,
                Background = selected ? _theme.AccentBrush : Theme.Transparent,
                CornerRadius = new CornerRadius(Ui.ChipRadius),
                Padding = new Thickness(10, 0, 10, 0),
                Height = 24,
                Margin = new Thickness(0, 0, 4, 0),
                Opacity = count == 0 && !selected ? 0.35 : 1,
                Cursor = Cursors.Hand,
            };
            var captured = filter;
            chip.MouseLeftButtonUp += (_, e) =>
            {
                e.Handled = true;
                _cb.ChipClicked(captured);
            };
            if (!selected)
            {
                chip.MouseEnter += (_, _) => chip.Background = _theme.ChipHover;
                chip.MouseLeave += (_, _) => chip.Background = Theme.Transparent;
            }
            _chips.Children.Add(chip);
        }
    }

    private void RebuildList()
    {
        _list.Children.Clear();
        _cardsById.Clear();
        var empty = _model.EmptyState;
        if (empty != EmptyState.None)
        {
            _list.Children.Add(EmptyStateView(empty));
            return;
        }
        var rendered = 0;
        var controlHeld = _model.Modifiers.HasFlag(ActionGrammar.Bits.CopyOnly);
        foreach (var section in _model.Sections)
        {
            var header = Ui.Text(Ui.SectionLabel(section.Kind), 11, _theme.Secondary, FontWeights.SemiBold);
            header.Margin = new Thickness(2, Ui.SectionAbove - (rendered == 0 ? Ui.RowGap : 0), 0, Ui.SectionBelow);
            _list.Children.Add(header);
            foreach (var entry in section.Rows)
            {
                if (rendered++ >= MaxRenderedRows) break;
                if (entry.Clip.IsGhost)
                {
                    _list.Children.Add(_cards.Ghost(entry.Clip));
                    continue;
                }
                var selected = entry.Id == _model.SelectedId;
                var expanded = entry.Id == _model.ExpandedId;
                var card = _cards.Build(entry, _model.Query, selected, expanded, controlHeld, _cb.Cards);
                _cardsById[entry.Id] = card;
                _list.Children.Add(card);
            }
        }
        ScrollSelectedIntoView();
    }

    private FrameworkElement EmptyStateView(EmptyState state)
    {
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 80, 0, 0) };
        void Add(FrameworkElement element, double top)
        {
            element.HorizontalAlignment = HorizontalAlignment.Center;
            element.Margin = new Thickness(0, top, 0, 0);
            stack.Children.Add(element);
        }
        switch (state)
        {
            case EmptyState.NothingCopied:
                Add(Ui.Glyph(Ui.GlyphClipboard, 44, _theme.Tertiary), 0);
                Add(Ui.Text(Strings.Get("Empty_NothingTitle"), 15, _theme.Primary, FontWeights.SemiBold), 14);
                Add(Ui.Text(Strings.Get("Empty_NothingBody"), 13, _theme.Secondary), 6);
                var hotkeyLine = new StackPanel { Orientation = Orientation.Horizontal };
                hotkeyLine.Children.Add(Ui.Keycap(_theme, _cb.HotkeyText()));
                var opens = Ui.Text(Strings.Format("Empty_NothingHotkey", string.Empty).Trim(), 12, _theme.Secondary);
                opens.Margin = new Thickness(8, 0, 0, 0);
                hotkeyLine.Children.Add(opens);
                Add(hotkeyLine, 14);
                break;
            case EmptyState.NoMatches:
                Add(Ui.Glyph(Ui.GlyphSearch, 32, _theme.Tertiary), 0);
                Add(Ui.Text(Strings.Format("Empty_NoMatches", _model.Query.Trim()), 15, _theme.Primary, FontWeights.SemiBold), 12);
                Add(Ui.Text(Strings.Format("Empty_NoMatchesHint", _model.Query.Trim()), 12, _theme.Secondary), 6);
                break;
            default:
                Add(Ui.Glyph(Ui.GlyphClipboard, 32, _theme.Tertiary), 0);
                Add(Ui.Text(Ui.EmptyFilterLabel(_model.Filter), 15, _theme.Primary, FontWeights.SemiBold), 12);
                break;
        }
        return stack;
    }

    public void UpdateSelection()
    {
        foreach (var (id, card) in _cardsById)
        {
            _cards.ApplySelection(card, id == _model.SelectedId);
        }
        ScrollSelectedIntoView();
        RebuildHintBar();
    }

    public void UpdateModifiers()
    {
        var controlHeld = _model.Modifiers.HasFlag(ActionGrammar.Bits.CopyOnly);
        foreach (var card in _cardsById.Values)
        {
            if (card.Tag is CardFactory.Parts { Keycap: { } keycap }) keycap.Opacity = controlHeld ? 1 : 0.5;
        }
        RebuildHintBar();
    }

    public void ScrollSelectedIntoView()
    {
        if (_model.SelectedId is { } id && _cardsById.TryGetValue(id, out var card))
        {
            card.BringIntoView();
        }
    }

    private void RebuildHintBar()
    {
        _hintRow.Visibility = _settings.ShowHintBar ? Visibility.Visible : Visibility.Collapsed;
        _hintBar.Children.Clear();
        if (!_settings.ShowHintBar) return;
        var chips = HintBarModel.Chips(_cb.HintInput());
        var first = true;
        foreach (var chip in chips)
        {
            var item = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(first ? 0 : Ui.HintGap, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            first = false;
            if (chip.IsWarning)
            {
                var warning = Ui.Glyph(Ui.GlyphWarning, 11, _theme.Warning);
                warning.Margin = new Thickness(0, 0, 6, 0);
                item.Children.Add(warning);
                item.Cursor = Cursors.Hand;
                item.MouseLeftButtonUp += (_, e) =>
                {
                    e.Handled = true;
                    _cb.WarningChipClicked();
                };
            }
            item.Children.Add(Ui.Keycap(_theme, chip.Key));
            var verb = Ui.Text(Strings.Get(chip.VerbKey), 11, _theme.Secondary);
            verb.Margin = new Thickness(6, 0, 0, 0);
            item.Children.Add(verb);
            _hintBar.Children.Add(item);
        }
    }

    // MARK: - Toast and overlay

    public void ShowToast(string text)
    {
        _toastText.Text = text;
        _toast.Visibility = Visibility.Visible;
        _toastTimer.Stop();
        _toastTimer.Start();
    }

    public void HideToast()
    {
        _toastTimer.Stop();
        _toast.Visibility = Visibility.Collapsed;
    }

    public bool HasOverlay => _overlay is not null;

    /// <summary>The clear-history confirmation, drawn inside the panel so the window never deactivates.</summary>
    public void ShowClearOverlay(int unpinned, int pinned, Action<bool> confirm)
    {
        HideOverlay();
        var card = new StackPanel { Width = 360 };
        card.Children.Add(Ui.Text(Strings.Get("Clear_Title"), 15, _theme.Primary, FontWeights.SemiBold));
        var body = Ui.Text(Strings.Format("Clear_Body", unpinned), 13, _theme.Secondary);
        body.TextWrapping = TextWrapping.Wrap;
        body.Margin = new Thickness(0, 8, 0, 0);
        card.Children.Add(body);
        var includePinned = new CheckBox
        {
            Content = Strings.Get("Clear_IncludePinned"),
            Foreground = _theme.Primary,
            FontSize = 12,
            Margin = new Thickness(0, 12, 0, 0),
            IsEnabled = pinned > 0,
            Focusable = false,
        };
        includePinned.Checked += (_, _) => body.Text = Strings.Format("Clear_BodyPinned", unpinned + pinned);
        includePinned.Unchecked += (_, _) => body.Text = Strings.Format("Clear_Body", unpinned);
        card.Children.Add(includePinned);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        var cancel = Ui.FlatButton(_theme, Strings.Get("Dialog_Cancel"), HideOverlay);
        cancel.Margin = new Thickness(0, 0, 8, 0);
        buttons.Children.Add(cancel);
        buttons.Children.Add(Ui.FlatButton(_theme, Strings.Get("Clear_Confirm"), () =>
        {
            var pinnedToo = includePinned.IsChecked == true;
            HideOverlay();
            confirm(pinnedToo);
        }, accent: true));
        card.Children.Add(buttons);

        _overlay = new Border
        {
            Background = Theme.Solid(_theme.IsDark ? Colors.Black : Colors.White, 0.55),
            CornerRadius = new CornerRadius(Ui.PanelRadius),
            Child = new Border
            {
                Child = card,
                Background = _theme.PanelBackground,
                BorderBrush = _theme.PanelBorder,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(20),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        Grid.SetRowSpan(_overlay, 4);
        _root.Children.Add(_overlay);
    }

    public void HideOverlay()
    {
        if (_overlay is null) return;
        _root.Children.Remove(_overlay);
        _overlay = null;
        FocusSearch();
    }
}
