using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Nori.Core;
using Nori.Windows.Clipboard;
using Nori.Windows.Native;
using Nori.Windows.Resources;

namespace Nori.Windows.Panel;

/// <summary>
/// Owns the panel: model, window and view, placement, the keyboard map, the paste pipeline and
/// every action a card can trigger. The window and view stay thin; decisions come from Core.
/// </summary>
internal sealed class PanelController
{
    private const int HoverGraceMs = 150;

    private readonly App _app;
    private readonly PanelModel _model;
    private readonly UndoBuffer _undo = new();
    private PanelWindow? _window;
    private PanelView? _view;
    private CardFactory? _cards;
    private Theme? _theme;
    private IntPtr _previousForeground;
    private PanelRect _lastRect;
    private double _lastScale = 1;
    private long _lastKeyTick;
    private bool _ignoreDeactivate;
    private bool _forceDark;

    public PanelController(App app)
    {
        _app = app;
        _model = new PanelModel(app.Clock);
    }

    public PanelModel Model => _model;
    public bool IsOpen => _window?.IsVisible == true;
    public PanelWindow? Window => _window;

    /// <summary>Screenshot state "dark" renders the dark palette regardless of the system setting.</summary>
    public void ForceDark() => _forceDark = true;

    // MARK: - Open / close

    public void Toggle(PanelPosition? position = null)
    {
        if (IsOpen) Close();
        else Open(position);
    }

    public void Open(PanelPosition? position = null)
    {
        if (IsOpen) return;
        _previousForeground = PasteService.RememberForeground();
        EnsureWindow();
        _model.Open();
        RefreshRows();
        _view!.SetQuery(string.Empty);
        _app.Capture.PanelOpened();
        var (rect, scale) = Placement(position ?? _app.Settings.PanelPosition);
        _lastRect = rect;
        _lastScale = scale;
        _ignoreDeactivate = true;
        try
        {
            _window!.ShowAt(rect, scale);
        }
        finally
        {
            _ignoreDeactivate = false;
        }
        _view.FocusSearch();
        _view.ScrollSelectedIntoView();
    }

    public void Close()
    {
        if (_window is null) return;
        _ignoreDeactivate = true;
        try
        {
            _window.HidePanel();
        }
        finally
        {
            _ignoreDeactivate = false;
        }
        FinishClose();
    }

    private void FinishClose()
    {
        _app.Capture.PanelClosed();
        _model.Collapse();
        _model.SetModifiers(ActionGrammar.Bits.None);
        _view?.HideToast();
        _view?.HideOverlay();
    }

    /// <summary>Rows changed while the panel is open (a new copy arrived, a secret expired).</summary>
    public void RowsChanged()
    {
        if (!IsOpen) return;
        RefreshRows();
    }

    public void PauseStateChanged() => _view?.UpdateSearchState();

    private void RefreshRows()
    {
        _model.SetRows(_app.History.Rows, _app.Vault.Rows, _app.Capture.Ghosts);
        _view?.Rebuild();
    }

    private Theme CurrentTheme()
    {
        var dark = _forceDark || Theme.SystemPrefersDark();
        var accent = _app.Options.IsScreenshotMode ? null : Theme.SystemAccent();
        return new Theme(dark, accent);
    }

    private void EnsureWindow()
    {
        var theme = CurrentTheme();
        var themeChanged = _theme is null || _theme.IsDark != theme.IsDark || _theme.Accent != theme.Accent;
        if (_window is null)
        {
            _window = new PanelWindow(theme, allowAcrylic: !_app.Options.IsScreenshotMode);
            _window.KeyPressed += OnKeyDown;
            _window.KeyReleased += OnKeyUp;
            _window.PanelDeactivated += OnDeactivated;
        }
        if (themeChanged || _view is null)
        {
            _theme = theme;
            _window.ApplyTheme(theme);
            _cards = new CardFactory(theme, _app.Clock, _app.Settings, _app.Apps);
            _view = new PanelView(theme, _model, _app.Settings, _cards, new PanelViewCallbacks
            {
                QueryChanged = OnQueryChanged,
                ChipClicked = filter => { _model.SetFilter(filter); _view!.Rebuild(); _view.FocusSearch(); },
                MenuRequested = BuildPanelMenu,
                HintInput = HintInput,
                PausedText = PausedText,
                HotkeyText = () => _app.Settings.Hotkey.DisplayText(),
                WarningChipClicked = () => { },
                Cards = new CardCallbacks
                {
                    Click = OnCardClick,
                    Hover = OnCardHover,
                    ContextMenu = BuildContextMenu,
                    Open = OpenRow,
                    Reveal = RevealRow,
                    Contents = id => _app.History.Contents(id),
                    Scale = _lastScale,
                },
            });
            _window.Body = _view.Root;
        }
    }

    private (PanelRect Physical, double Scale) Placement(PanelPosition position)
    {
        User32.POINT cursor;
        IntPtr monitor;
        if (_app.Options.IsScreenshotMode)
        {
            cursor = new User32.POINT { X = 0, Y = 0 };
            monitor = User32.MonitorFromPoint(cursor, User32.MONITOR_DEFAULTTOPRIMARY);
            position = PanelPosition.Center;
        }
        else
        {
            if (!User32.GetCursorPos(out cursor)) cursor = new User32.POINT { X = 0, Y = 0 };
            monitor = User32.MonitorFromPoint(cursor, User32.MONITOR_DEFAULTTONEAREST);
        }
        var work = User32.WorkArea(monitor);
        var scale = Shcore.ScaleFor(monitor);
        var workDip = new PanelRect(work.Left / scale, work.Top / scale, work.Width / scale, work.Height / scale);
        var rect = PanelPlacement.Compute(position, workDip, cursor.X / scale, cursor.Y / scale);
        var physical = new PanelRect(Math.Round(rect.X * scale), Math.Round(rect.Y * scale), Math.Round(rect.Width * scale), Math.Round(rect.Height * scale));
        return (physical, scale);
    }

    private void OnDeactivated()
    {
        if (_ignoreDeactivate || !IsOpen) return;
        Close();
    }

    private string? PausedText()
    {
        if (!_app.Capture.IsPaused) return null;
        var remaining = _app.Capture.PauseRemaining;
        return remaining is { } r ? Strings.Format("Search_PausedCountdown", $"{(int)r.TotalMinutes:00}:{r.Seconds:00}") : Strings.Get("Search_Paused");
    }

    private bool CanPaste => _app.Options.IsScreenshotMode || (_previousForeground != IntPtr.Zero && User32.IsWindow(_previousForeground));

    private HintBarModel.Input HintInput() => new(
        _model.Modifiers,
        CanPaste,
        CycleMode: false,
        _app.Settings.Hotkey.ModifierText(),
        _model.Selected?.Clip.Kind,
        _model.Selected is not null);

    // MARK: - Search

    private void OnQueryChanged(string text)
    {
        _model.SetQuery(text);
        _view?.Rebuild();
    }

    // MARK: - Keyboard

    private static ActionGrammar.Bits CurrentBits(Key? releasedKey = null)
    {
        bool Down(Key key) => key != releasedKey && Keyboard.IsKeyDown(key);
        var shift = Down(Key.LeftShift) || Down(Key.RightShift);
        var alt = Down(Key.LeftAlt) || Down(Key.RightAlt);
        var control = Down(Key.LeftCtrl) || Down(Key.RightCtrl);
        return ActionGrammar.FromModifiers(shift, alt, control);
    }

    private void SyncModifiers(ActionGrammar.Bits bits)
    {
        if (bits == _model.Modifiers) return;
        _model.SetModifiers(bits);
        _view?.UpdateModifiers();
    }

    private void OnKeyUp(KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        SyncModifiers(CurrentBits(key));
    }

    private void OnKeyDown(KeyEventArgs e)
    {
        if (_view is null) return;
        _lastKeyTick = Environment.TickCount64;
        if (e.Key == Key.ImeProcessed)
        {
            return; // an IME composition owns the keyboard; Enter confirms the conversion, never pastes
        }
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        SyncModifiers(CurrentBits());
        var modifiers = Keyboard.Modifiers;
        var control = modifiers.HasFlag(ModifierKeys.Control);
        var shift = modifiers.HasFlag(ModifierKeys.Shift);
        var alt = modifiers.HasFlag(ModifierKeys.Alt);
        var bits = ActionGrammar.FromModifiers(shift, alt, control);
        var searchEmpty = _view.SearchBox.Text.Length == 0;

        if (_view.HasOverlay)
        {
            if (key == Key.Escape)
            {
                _view.HideOverlay();
                e.Handled = true;
            }
            return;
        }

        switch (key)
        {
            case Key.Escape:
                Close();
                break;
            case Key.Enter or Key.Return:
                if (_model.ShouldPasteTypedText) PasteTypedText();
                else if (_model.Selected is { } selected) Perform(selected.Clip, ActionGrammar.Resolve(ActionGrammar.Base.Return, bits, new(CanPaste)));
                break;
            case >= Key.D1 and <= Key.D9 when control:
                Number(key - Key.D1 + 1, bits);
                break;
            case >= Key.NumPad1 and <= Key.NumPad9 when control:
                Number(key - Key.NumPad1 + 1, bits);
                break;
            case Key.Down when control:
            case Key.End when searchEmpty || control:
                _model.SelectLast();
                _view.UpdateSelection();
                break;
            case Key.Up when control:
            case Key.Home when searchEmpty || control:
                _model.SelectFirst();
                _view.UpdateSelection();
                break;
            case Key.Down:
                Move(1);
                break;
            case Key.Up:
                Move(-1);
                break;
            case Key.PageDown:
                Move(6);
                break;
            case Key.PageUp:
                Move(-6);
                break;
            case Key.Tab:
                if (shift) _model.PreviousFilter();
                else _model.NextFilter();
                _view.Rebuild();
                break;
            case Key.Space when searchEmpty && !control:
                ToggleExpand();
                break;
            case Key.Y when control:
                ToggleExpand();
                break;
            case Key.P when control && shift:
                _app.TogglePause();
                _view.UpdateSearchState();
                break;
            case Key.P when control:
                TogglePin();
                break;
            case Key.Delete when searchEmpty || control:
            case Key.Back when control && searchEmpty && !shift:
                DeleteSelected();
                break;
            case Key.Back when control && shift:
                RequestClear();
                break;
            case Key.Z when control && _undo.HasPending:
                Undo();
                break;
            case Key.O when control:
                if (_model.Selected is { } toOpen) OpenRow(toOpen.Clip);
                break;
            case Key.R when control:
                if (_model.Selected is { } toReveal) RevealRow(toReveal.Clip);
                break;
            case Key.C when control && !_view.SearchHasSelection:
                if (_model.Selected is { } toCopy) Perform(toCopy.Clip, ActionGrammar.Action.Copy(shift, alt));
                break;
            case Key.V when control:
                break; // people mash it; swallow
            case Key.F when control:
                _view.FocusSearch();
                _view.SelectAllSearch();
                break;
            case Key.U when control:
                _view.SetQuery(string.Empty);
                OnQueryChanged(string.Empty);
                break;
            case Key.OemComma when control:
                Close();
                _app.OpenSettings(0);
                break;
            default:
                return; // not ours: the search box gets it
        }
        e.Handled = true;
    }

    private void Move(int delta)
    {
        _model.MoveSelection(delta);
        _view!.UpdateSelection();
        if (_model.ExpandedId is null && _view is not null && _cardsWereExpanded) _view.Rebuild();
        _cardsWereExpanded = false;
    }

    private bool _cardsWereExpanded;

    private void ToggleExpand()
    {
        if (!_model.CanExpand) return;
        _model.ToggleExpand();
        _cardsWereExpanded = _model.IsExpanded;
        _view!.Rebuild();
    }

    private void Number(int number, ActionGrammar.Bits bits)
    {
        if (_model.RowForNumber(number) is { } row)
        {
            Perform(row.Clip, ActionGrammar.Resolve(new ActionGrammar.Base.Number(number), bits, new(CanPaste)));
        }
    }

    // MARK: - Mouse

    private void OnCardHover(ClipRow row)
    {
        if (Environment.TickCount64 - _lastKeyTick < HoverGraceMs) return;
        if (_model.SelectedId == row.Id) return;
        var wasExpanded = _model.ExpandedId is not null;
        _model.Select(row.Id);
        if (wasExpanded) _view!.Rebuild();
        else _view!.UpdateSelection();
    }

    private void OnCardClick(ClipRow row, MouseButtonEventArgs e)
    {
        e.Handled = true;
        _model.Select(row.Id);
        var bits = CurrentBits();
        Perform(row, ActionGrammar.Resolve(ActionGrammar.Base.Mouse, bits, new(CanPaste)));
    }

    // MARK: - Actions

    private IReadOnlyList<ClipContent>? ContentsFor(ClipRow row) =>
        row.IsSensitive ? _app.Vault.Find(row.Id)?.Draft.Contents : _app.History.Contents(row.Id);

    /// <summary>Write the clip, then copy-only or paste according to the resolved action.</summary>
    public void Perform(ClipRow row, ActionGrammar.Action action)
    {
        if (row.IsGhost) return;
        var contents = ContentsFor(row);
        if (contents is null || contents.Count == 0)
        {
            Log.Warn($"no contents for {row.Id}");
            return;
        }
        if (!ClipboardWriter.Write(contents, row.Id, action.Plain)) return;
        var now = _app.Clock.Now;
        if (row.IsSensitive) _app.Vault.Touch(row.Id, now);
        else _app.History.Touch(row.Id, now);

        if (action.IsCopy)
        {
            if (action.KeepOpen)
            {
                RefreshRows();
                _view?.ShowToast(Strings.Get("Toast_Copied"));
            }
            else
            {
                Close();
            }
            return;
        }
        PasteIntoPreviousApp(action.KeepOpen);
    }

    private void PasteTypedText()
    {
        var text = _model.Query;
        if (!ClipboardWriter.WriteText(text)) return;
        PasteIntoPreviousApp(keepOpen: false);
    }

    private void PasteIntoPreviousApp(bool keepOpen)
    {
        var target = _previousForeground;
        var rect = _lastRect;
        var scale = _lastScale;
        _ignoreDeactivate = true;
        try
        {
            _window?.HidePanel();
        }
        finally
        {
            _ignoreDeactivate = false;
        }
        if (!keepOpen) FinishClose();

        Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background, () =>
        {
            if (_app.Options.IsScreenshotMode)
            {
                Log.Info("paste suppressed in screenshot mode");
            }
            else if (PasteService.RestoreForeground(target))
            {
                PasteService.SendCtrlV();
            }
            else
            {
                Log.Warn("previous window could not be brought to the front; the clip is on the clipboard");
            }
            if (!keepOpen) return;
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(60) };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                RefreshRows();
                _ignoreDeactivate = true;
                try
                {
                    _window?.ShowAt(rect, scale);
                }
                finally
                {
                    _ignoreDeactivate = false;
                }
                _view?.FocusSearch();
            };
            timer.Start();
        });
    }

    private void TogglePin()
    {
        if (_model.Selected is not { } row || row.Clip.IsSensitive) return;
        _app.History.TogglePin(row.Id, _app.Clock.Now);
        RefreshRows();
    }

    private void DeleteSelected()
    {
        if (_model.Selected is not { } row) return;
        var next = _model.SelectionAfterRemoving(row.Id);
        if (row.Clip.IsSensitive)
        {
            _app.Vault.Remove(row.Id);
        }
        else if (_app.History.Delete(row.Id) is { } record)
        {
            _undo.Remember(record, _app.Clock.Now);
        }
        RefreshRows();
        _model.Select(next);
        _view!.UpdateSelection();
        if (!row.Clip.IsSensitive) _view.ShowToast(Strings.Get("Toast_Deleted"));
    }

    private void Undo()
    {
        if (_undo.Take(_app.Clock.Now) is not { } record) return;
        var id = _app.History.Restore(record);
        RefreshRows();
        _model.Select(id);
        _view!.UpdateSelection();
        _view.HideToast();
    }

    private void RequestClear()
    {
        var pinned = _app.History.PinnedCount;
        var unpinned = _app.History.Count - pinned;
        _view!.ShowClearOverlay(unpinned, pinned, includingPinned =>
        {
            var cleared = _app.ClearHistory(includingPinned);
            RefreshRows();
            _view.ShowToast(Strings.Format("Toast_Cleared", cleared));
        });
    }

    private void OpenRow(ClipRow row)
    {
        try
        {
            switch (row.Kind)
            {
                case ClipKind.Link when row.LinkUrl is { } url:
                    Process.Start(new ProcessStartInfo(url.OriginalString) { UseShellExecute = true });
                    break;
                case ClipKind.File when row.FilePaths.Count > 0:
                    Process.Start(new ProcessStartInfo(row.FilePaths[0]) { UseShellExecute = true });
                    break;
                case ClipKind.Image:
                {
                    var png = ContentsFor(row)?.FirstOrDefault(c => ClipboardFormats.Is(c.Format, ClipboardFormats.Png))?.Data;
                    if (png is null) return;
                    var path = Path.Combine(Path.GetTempPath(), $"Nori-{row.Id:N}.png");
                    File.WriteAllBytes(path, png);
                    Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
                    break;
                }
                default:
                    return;
            }
            Close();
        }
        catch (Exception e)
        {
            Log.Error("open failed", e);
        }
    }

    private void RevealRow(ClipRow row)
    {
        if (row.Kind != ClipKind.File || row.FilePaths.Count == 0) return;
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{row.FilePaths[0]}\"") { UseShellExecute = true });
            Close();
        }
        catch (Exception e)
        {
            Log.Error("reveal failed", e);
        }
    }

    // MARK: - Menus

    private ContextMenu? BuildContextMenu(ClipRow row)
    {
        if (row.IsGhost) return null;
        var menu = new ContextMenu();
        MenuItem Item(string key, string gesture, Action action, bool enabled = true)
        {
            var item = new MenuItem { Header = Strings.Get(key), InputGestureText = gesture, IsEnabled = enabled };
            item.Click += (_, _) => action();
            menu.Items.Add(item);
            return item;
        }
        var caps = new ActionGrammar.Capabilities(CanPaste);
        Item("Menu_Paste", "Enter", () => Perform(row, ActionGrammar.Resolve(ActionGrammar.Base.Return, ActionGrammar.Bits.None, caps)));
        Item("Menu_PastePlain", "Shift+Enter", () => Perform(row, ActionGrammar.Resolve(ActionGrammar.Base.Return, ActionGrammar.Bits.Plain, caps)));
        if (!row.IsSensitive) Item("Menu_PasteKeepOpen", "Alt+Enter", () => Perform(row, ActionGrammar.Resolve(ActionGrammar.Base.Return, ActionGrammar.Bits.KeepOpen, caps)));
        Item("Menu_Copy", "Ctrl+Enter", () => Perform(row, ActionGrammar.Action.Copy(false, false)));
        if (!row.IsSensitive)
        {
            menu.Items.Add(new Separator());
            Item("Menu_Preview", "Space", () => { _model.Select(row.Id); ToggleExpand(); });
            Item(row.IsPinned ? "Menu_Unpin" : "Menu_Pin", "Ctrl+P", () => { _model.Select(row.Id); TogglePin(); });
            if (row.Kind is ClipKind.Link or ClipKind.File or ClipKind.Image)
            {
                menu.Items.Add(new Separator());
                Item(row.Kind == ClipKind.Link ? "Menu_OpenInBrowser" : "Menu_Open", "Ctrl+O", () => OpenRow(row));
                if (row.Kind == ClipKind.File) Item("Menu_Reveal", "Ctrl+R", () => RevealRow(row));
            }
        }
        menu.Items.Add(new Separator());
        Item("Menu_Delete", "Del", () => { _model.Select(row.Id); DeleteSelected(); });
        return menu;
    }

    private ContextMenu BuildPanelMenu()
    {
        var menu = new ContextMenu();
        MenuItem Item(string text, Action action, string? gesture = null, bool enabled = true)
        {
            var item = new MenuItem { Header = text, IsEnabled = enabled };
            if (gesture is not null) item.InputGestureText = gesture;
            item.Click += (_, _) => action();
            return item;
        }
        if (_app.Capture.IsPaused)
        {
            menu.Items.Add(Item(Strings.Get("Tray_Resume"), () => { _app.Capture.Resume(); _view?.UpdateSearchState(); }));
        }
        else
        {
            var pause = new MenuItem { Header = Strings.Get("Tray_Pause") };
            pause.Items.Add(Item(Strings.Get("Tray_Pause5"), () => { _app.Capture.Pause(TimeSpan.FromMinutes(5)); _view?.UpdateSearchState(); }));
            pause.Items.Add(Item(Strings.Get("Tray_Pause30"), () => { _app.Capture.Pause(TimeSpan.FromMinutes(30)); _view?.UpdateSearchState(); }));
            pause.Items.Add(Item(Strings.Get("Tray_PauseUntilResume"), () => { _app.Capture.Pause(null); _view?.UpdateSearchState(); }));
            menu.Items.Add(pause);
        }
        menu.Items.Add(Item(Strings.Get("Tray_SkipNext"), () => _app.Capture.SkipNextCopy = true));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(Strings.Get("Tray_ClearHistory"), RequestClear, "Ctrl+Shift+Backspace"));
        menu.Items.Add(Item(Strings.Get("Tray_Settings"), () => { Close(); _app.OpenSettings(0); }, "Ctrl+,"));
        menu.Items.Add(Item(Strings.Get("Tray_About"), () => { Close(); _app.OpenSettings(4); }));
        return menu;
    }

    // MARK: - Screenshot support

    /// <summary>Opens the panel at the screen center and applies a <c>--state</c> preset.</summary>
    public void OpenForScreenshot(string state)
    {
        Open(PanelPosition.Center);
        if (_view is null) return;
        var parts = state.Split(':', 2);
        switch (parts[0])
        {
            case "search":
                var query = parts.Length > 1 ? parts[1] : "swift";
                _view.SetQuery(query);
                OnQueryChanged(query);
                break;
            case "filter":
                var filter = parts.Length > 1 && Enum.TryParse<PanelFilter>(parts[1], ignoreCase: true, out var parsed) ? parsed : PanelFilter.Code;
                _model.SetFilter(filter);
                _view.Rebuild();
                break;
            case "cmd":
                _model.SetModifiers(ActionGrammar.Bits.CopyOnly);
                _view.UpdateModifiers();
                break;
            case "shift":
                _model.SetModifiers(ActionGrammar.Bits.Plain);
                _view.UpdateModifiers();
                break;
            case "expanded":
                var number = parts.Length > 1 && int.TryParse(parts[1], out var n) ? n : 4;
                if (_model.RowForNumber(number) is { } row)
                {
                    _model.Select(row.Id);
                    ToggleExpand();
                }
                break;
            case "ghost":
                _app.Capture.AddGhost(new GhostReason.Concealed("1Password"), _app.Clock.Now);
                RefreshRows();
                break;
        }
    }

    public void RenderScreenshot(string path)
    {
        _window?.RenderPng(path, _lastScale);
    }
}
