using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Nori.Core;
using Nori.Windows.Clipboard;
using Nori.Windows.Resources;

namespace Nori.Windows.Panel;

/// <summary>What a card needs from the controller.</summary>
internal sealed class CardCallbacks
{
    public required Action<ClipRow, MouseButtonEventArgs> Click { get; init; }
    public required Action<ClipRow> Hover { get; init; }
    public required Func<ClipRow, ContextMenu?> ContextMenu { get; init; }
    public required Action<ClipRow> Open { get; init; }
    public required Action<ClipRow> Reveal { get; init; }
    public required Func<Guid, IReadOnlyList<ClipContent>> Contents { get; init; }
    public double Scale { get; init; } = 1;
}

/// <summary>Per-kind card anatomy (well, title block, meta column) and the inline expanded preview.</summary>
internal sealed class CardFactory
{
    private readonly Theme _theme;
    private readonly IClock _clock;
    private readonly NoriSettings _settings;
    private readonly SourceApps _apps;
    private readonly Dictionary<Guid, BitmapSource?> _thumbnails = [];
    private readonly Dictionary<string, BitmapSource?> _fileIcons = new(StringComparer.OrdinalIgnoreCase);

    public CardFactory(Theme theme, IClock clock, NoriSettings settings, SourceApps apps)
    {
        _theme = theme;
        _clock = clock;
        _settings = settings;
        _apps = apps;
    }

    public CultureInfo Culture => Strings.Culture;

    /// <summary>Stashed on <see cref="Border.Tag"/> so the view can update selection and keycaps in place.</summary>
    public sealed class Parts
    {
        public required ClipRow Row { get; init; }
        public Border? Keycap { get; init; }
        public bool Expanded { get; init; }
    }

    public Border Build(PanelSections.Row entry, string query, bool selected, bool expanded, bool controlHeld, CardCallbacks callbacks)
    {
        var row = entry.Clip;
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Ui.WellGap) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Ui.MetaGap) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Ui.MetaWidth) });

        var well = Well(row);
        well.VerticalAlignment = VerticalAlignment.Top;
        Grid.SetColumn(well, 0);
        header.Children.Add(well);

        var titleBlock = TitleBlock(row, query);
        titleBlock.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(titleBlock, 2);
        header.Children.Add(titleBlock);

        var (meta, keycap) = Meta(row, entry.Number, controlHeld);
        Grid.SetColumn(meta, 4);
        header.Children.Add(meta);

        FrameworkElement content = header;
        if (expanded)
        {
            var stack = new StackPanel();
            stack.Children.Add(header);
            var preview = Expanded(row, callbacks);
            preview.Margin = new Thickness(0, 10, 0, 0);
            stack.Children.Add(preview);
            content = stack;
        }

        var card = new Border
        {
            Child = content,
            CornerRadius = new CornerRadius(Ui.CardRadius),
            Padding = new Thickness(Ui.CardPadH, Ui.CardPadV, Ui.CardPadH, Ui.CardPadV),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 0, Ui.CardGap),
            Tag = new Parts { Row = row, Keycap = keycap, Expanded = expanded },
            Cursor = Cursors.Arrow,
            SnapsToDevicePixels = true,
        };
        ApplySelection(card, selected);

        card.MouseEnter += (_, _) => callbacks.Hover(row);
        card.MouseLeftButtonUp += (_, e) => callbacks.Click(row, e);
        card.MouseRightButtonUp += (_, e) =>
        {
            var menu = callbacks.ContextMenu(row);
            if (menu is null) return;
            menu.PlacementTarget = card;
            menu.IsOpen = true;
            e.Handled = true;
        };
        return card;
    }

    public void ApplySelection(Border card, bool selected)
    {
        var parts = card.Tag as Parts;
        var expanded = parts?.Expanded == true;
        if (selected)
        {
            card.Background = _theme.CardSelectedFill;
            card.BorderBrush = _theme.CardSelectedStroke;
        }
        else if (expanded)
        {
            card.Background = _theme.CardExpandedFill;
            card.BorderBrush = _theme.CardExpandedStroke;
        }
        else
        {
            card.Background = _theme.CardFill;
            card.BorderBrush = Theme.Transparent;
        }
    }

    public Border Ghost(ClipRow row)
    {
        var text = Ui.Text(Ui.GhostText(row.GhostReason), 11, _theme.Secondary);
        text.HorizontalAlignment = HorizontalAlignment.Center;
        var stripes = new DrawingBrush
        {
            TileMode = TileMode.Tile,
            Viewport = new Rect(0, 0, 8, 8),
            ViewportUnits = BrushMappingMode.Absolute,
            Drawing = new GeometryDrawing(_theme.GhostStripe, null, new LineGeometry(new Point(0, 8), new Point(8, 0)))
            {
                Pen = new Pen(_theme.GhostStripe, 2),
            },
        };
        stripes.Freeze();
        var stripeLayer = new Border { Background = stripes, CornerRadius = new CornerRadius(Ui.GhostRadius) };
        var grid = new Grid();
        grid.Children.Add(stripeLayer);
        grid.Children.Add(text);
        return new Border
        {
            Child = grid,
            Height = 32,
            Background = _theme.GhostFill,
            CornerRadius = new CornerRadius(Ui.GhostRadius),
            Margin = new Thickness(0, 0, 0, Ui.CardGap),
            Tag = new Parts { Row = row },
        };
    }

    // MARK: - Well

    private FrameworkElement Well(ClipRow row)
    {
        if (row.IsSensitive) return GlyphWell(Ui.GlyphLock, _theme.KindTint(row.Kind, sensitive: true));
        switch (row.Kind)
        {
            case ClipKind.Color when row.ColorHex is { } hex && KindDetector.Channels(hex) is { } c:
            {
                var checker = Checkerboard();
                var swatch = new Border
                {
                    Width = Ui.WellSize,
                    Height = Ui.WellSize,
                    CornerRadius = new CornerRadius(Ui.WellRadius),
                    Background = checker,
                    BorderBrush = _theme.WellStroke,
                    BorderThickness = new Thickness(1),
                    Child = new Border
                    {
                        CornerRadius = new CornerRadius(Ui.WellRadius - 1),
                        Background = new SolidColorBrush(Color.FromArgb((byte)c.A, (byte)c.R, (byte)c.G, (byte)c.B)),
                    },
                };
                return swatch;
            }
            case ClipKind.Image:
            {
                var thumb = Thumbnail(row);
                var border = new Border
                {
                    Width = Ui.ThumbSize,
                    Height = Ui.ThumbSize,
                    CornerRadius = new CornerRadius(Ui.ThumbRadius),
                    BorderBrush = _theme.WellStroke,
                    BorderThickness = new Thickness(1),
                    Background = _theme.CardFill,
                    ClipToBounds = true,
                };
                if (thumb is not null)
                {
                    var image = new Image { Source = thumb, Stretch = Stretch.UniformToFill, Width = Ui.ThumbSize - 2, Height = Ui.ThumbSize - 2 };
                    RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
                    border.Child = new Border { CornerRadius = new CornerRadius(Ui.ThumbRadius - 1), Child = image, ClipToBounds = true };
                }
                else
                {
                    border.Child = Ui.Glyph(Ui.GlyphPhoto, 20, Theme.Solid(_theme.KindTint(ClipKind.Image)));
                }
                return border;
            }
            case ClipKind.File:
            {
                var icon = row.FilePaths.Count > 0 ? FileIcon(row.FilePaths[0]) : null;
                var grid = new Grid { Width = Ui.WellSize, Height = Ui.WellSize };
                if (icon is not null)
                {
                    var image = new Image { Source = icon, Width = Ui.WellSize, Height = Ui.WellSize, Stretch = Stretch.Uniform };
                    RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
                    grid.Children.Add(image);
                }
                else
                {
                    grid.Children.Add(GlyphWell(Ui.GlyphDocument, _theme.KindTint(ClipKind.File)));
                }
                if (row.FilePaths.Count > 1)
                {
                    var badge = new Border
                    {
                        Background = _theme.AccentBrush,
                        CornerRadius = new CornerRadius(6),
                        Padding = new Thickness(3, 0, 3, 0),
                        HorizontalAlignment = HorizontalAlignment.Right,
                        VerticalAlignment = VerticalAlignment.Bottom,
                        Child = Ui.Text($"+{row.FilePaths.Count - 1}", 9, Brushes.White, FontWeights.SemiBold),
                    };
                    grid.Children.Add(badge);
                }
                return grid;
            }
            case ClipKind.Link:
                return GlyphWell(Ui.GlyphLink, _theme.KindTint(ClipKind.Link));
            case ClipKind.Code:
                return GlyphWell(Ui.GlyphCode, _theme.KindTint(ClipKind.Code));
            default:
                return GlyphWell(Ui.GlyphText, _theme.KindTint(ClipKind.Text));
        }
    }

    private Border GlyphWell(string glyph, Color tint) => new()
    {
        Width = Ui.WellSize,
        Height = Ui.WellSize,
        CornerRadius = new CornerRadius(Ui.WellRadius),
        Background = Theme.Solid(tint, 0.12),
        Child = Ui.Glyph(glyph, 14, Theme.Solid(tint)),
    };

    private static DrawingBrush Checkerboard()
    {
        var group = new DrawingGroup();
        group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(0xE6, 0xE6, 0xE6)), null, new RectangleGeometry(new Rect(0, 0, 8, 8))));
        group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(0xC8, 0xC8, 0xC8)), null, new RectangleGeometry(new Rect(0, 0, 4, 4))));
        group.Children.Add(new GeometryDrawing(new SolidColorBrush(Color.FromRgb(0xC8, 0xC8, 0xC8)), null, new RectangleGeometry(new Rect(4, 4, 4, 4))));
        var brush = new DrawingBrush(group) { TileMode = TileMode.Tile, Viewport = new Rect(0, 0, 8, 8), ViewportUnits = BrushMappingMode.Absolute };
        brush.Freeze();
        return brush;
    }

    private BitmapSource? Thumbnail(ClipRow row)
    {
        if (_thumbnails.TryGetValue(row.Id, out var cached)) return cached;
        BitmapSource? source = null;
        if (row.Thumbnail is { Length: > 0 })
        {
            try
            {
                source = WpfImageNormalizer.Decode(row.Thumbnail);
            }
            catch (Exception e) when (e is NotSupportedException or FileFormatException or ArgumentException)
            {
                source = null;
            }
        }
        _thumbnails[row.Id] = source;
        return source;
    }

    private BitmapSource? FileIcon(string path)
    {
        if (_fileIcons.TryGetValue(path, out var cached)) return cached;
        var icon = Native.Shell32.IconFor(path, large: true);
        _fileIcons[path] = icon;
        return icon;
    }

    // MARK: - Title block

    private FrameworkElement TitleBlock(ClipRow row, string query)
    {
        var stack = new StackPanel();
        if (row.IsSensitive)
        {
            var line = new StackPanel { Orientation = Orientation.Horizontal };
            line.Children.Add(Ui.Text(row.Title, 13, _theme.Primary, family: Theme.MonoFont));
            var expiry = row.ExpiresAt is { } at ? Strings.Format("Card_ExpiresIn", Ui.ExpiryText(at, _clock.Now)) : string.Empty;
            line.Children.Add(Ui.Text(" · " + expiry, 12, _theme.Secondary));
            stack.Children.Add(line);
            return stack;
        }
        switch (row.Kind)
        {
            case ClipKind.Link:
            {
                var host = row.LinkHost ?? row.DisplayTitle;
                var title = Ui.Text(host, 13, _theme.Primary, FontWeights.SemiBold);
                Ui.HighlightedText(title, host, query, _theme);
                stack.Children.Add(title);
                var path = row.LinkPathAndQuery;
                if (row.IsMailto) path = row.Title;
                if (!string.IsNullOrEmpty(path))
                {
                    var caption = Ui.Text(path, 12, _theme.Secondary);
                    caption.TextTrimming = TextTrimming.CharacterEllipsis;
                    stack.Children.Add(caption);
                }
                break;
            }
            case ClipKind.Code:
            {
                var lines = row.CodeLines;
                foreach (var line in lines.Take(2))
                {
                    var block = Ui.Text(line.Length == 0 ? " " : line, 12, _theme.Primary, family: Theme.MonoFont);
                    Ui.HighlightedText(block, line.Length == 0 ? " " : line, query, _theme);
                    stack.Children.Add(block);
                }
                if (lines.Count == 1) stack.Children.Add(Ui.Text(" ", 12, _theme.Primary, family: Theme.MonoFont));
                break;
            }
            case ClipKind.Color:
            {
                var line = new StackPanel { Orientation = Orientation.Horizontal };
                var hex = row.ColorHex ?? row.DisplayTitle;
                line.Children.Add(Ui.Text(hex, 13, _theme.Primary, family: Theme.MonoFont));
                line.Children.Add(Ui.Text("   " + KindDetector.RgbText(hex), 12, _theme.Secondary));
                stack.Children.Add(line);
                break;
            }
            case ClipKind.Image:
            {
                stack.Children.Add(Ui.Text(ImageCaption(row), 13, _theme.Primary));
                break;
            }
            case ClipKind.File:
            {
                var names = row.FileNames;
                var title = names.Count == 1 ? names[0] : Strings.Format("Card_Files", names.Count);
                var block = Ui.Text(title, 13, _theme.Primary);
                Ui.HighlightedText(block, title, query, _theme);
                stack.Children.Add(block);
                if (row.FilePaths.Count > 0)
                {
                    var folder = ClipClassifier.ParentFolder(row.FilePaths[0]);
                    var type = Native.Shell32.TypeName(row.FilePaths[0]);
                    var caption = type is null ? folder : $"{folder} · {type}";
                    stack.Children.Add(Ui.Text(caption, 12, _theme.Secondary));
                }
                break;
            }
            default:
            {
                var title = row.DisplayTitle;
                var block = Ui.Text(title, 13, _theme.Primary);
                Ui.HighlightedText(block, title, query, _theme);
                stack.Children.Add(block);
                if (row.LineCount > 1 || row.IsRichText)
                {
                    var caption = $"{Strings.Format("Card_Lines", row.LineCount)} · {Strings.Format("Card_Chars", row.CharacterCount.ToString("N0", Culture))}";
                    if (row.IsRichText) caption += " · " + Strings.Get("Card_RichText");
                    stack.Children.Add(Ui.Text(caption, 12, _theme.Secondary));
                }
                break;
            }
        }
        return stack;
    }

    private string ImageCaption(ClipRow row)
    {
        var (w, h) = row.ImagePixelSize ?? (0, 0);
        return Strings.Format("Card_ImageCaption", w.ToString("N0", Culture), h.ToString("N0", Culture), ByteSize.Format(row.ByteCount));
    }

    // MARK: - Meta column

    private (FrameworkElement Panel, Border? Keycap) Meta(ClipRow row, int? number, bool controlHeld)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Height = 20 };
        if (_settings.ShowAppIcons)
        {
            var icon = _apps.Icon(row.SourceAppPath);
            FrameworkElement element = icon is not null
                ? new Image { Source = icon, Width = 16, Height = 16 }
                : Ui.Glyph(Ui.GlyphApp, 13, _theme.Tertiary);
            element.Margin = new Thickness(0, 0, Ui.MetaGap, 0);
            element.VerticalAlignment = VerticalAlignment.Center;
            element.ToolTip = row.SourceAppName ?? row.SourceApp;
            panel.Children.Add(element);
        }
        var time = Ui.Text(PanelSections.RelativeTime(row.LastCopiedAt, _clock.Now, Culture), 11, _theme.Secondary, FontWeights.Medium);
        panel.Children.Add(time);
        Border? keycap = null;
        if (number is { } n)
        {
            keycap = Ui.Keycap(_theme, $"Ctrl+{n}", controlHeld ? 1 : 0.5);
            keycap.Margin = new Thickness(Ui.MetaGap, 0, 0, 0);
            panel.Children.Add(keycap);
        }
        if (row.IsPinned)
        {
            var star = Ui.Glyph(Ui.GlyphStar, 10, _theme.Star);
            star.Margin = new Thickness(Ui.MetaGap, 0, 0, 0);
            panel.Children.Add(star);
        }
        return (panel, keycap);
    }

    // MARK: - Expanded preview

    private FrameworkElement Expanded(ClipRow row, CardCallbacks callbacks)
    {
        var stack = new StackPanel();
        switch (row.Kind)
        {
            case ClipKind.Link:
            {
                var url = Ui.Text(row.Title, 12, _theme.Primary, family: Theme.MonoFont);
                url.TextWrapping = TextWrapping.Wrap;
                stack.Children.Add(url);
                var open = Ui.FlatButton(_theme, $"{Strings.Get("Expanded_Open")}  Ctrl+O", () => callbacks.Open(row));
                open.HorizontalAlignment = HorizontalAlignment.Left;
                open.Margin = new Thickness(0, 8, 0, 0);
                stack.Children.Add(open);
                break;
            }
            case ClipKind.Color when row.ColorHex is { } hex && KindDetector.Channels(hex) is { } c:
            {
                var line = new StackPanel { Orientation = Orientation.Horizontal };
                line.Children.Add(new Border
                {
                    Width = 88,
                    Height = 88,
                    CornerRadius = new CornerRadius(12),
                    Background = Checkerboard(),
                    BorderBrush = _theme.WellStroke,
                    BorderThickness = new Thickness(1),
                    Child = new Border { CornerRadius = new CornerRadius(11), Background = new SolidColorBrush(Color.FromArgb((byte)c.A, (byte)c.R, (byte)c.G, (byte)c.B)) },
                });
                var values = new StackPanel { Margin = new Thickness(16, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
                foreach (var text in new[] { hex, KindDetector.RgbText(hex), KindDetector.HslText(hex) })
                {
                    values.Children.Add(Ui.Text(text, 12, _theme.Primary, family: Theme.MonoFont));
                }
                line.Children.Add(values);
                stack.Children.Add(line);
                break;
            }
            case ClipKind.Image:
            {
                var source = ExpandedImage(row, callbacks);
                if (source is not null)
                {
                    var image = new Image { Source = source, Stretch = Stretch.Uniform, MaxHeight = 220, HorizontalAlignment = HorizontalAlignment.Left };
                    RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
                    stack.Children.Add(new Border { CornerRadius = new CornerRadius(8), ClipToBounds = true, Child = image, HorizontalAlignment = HorizontalAlignment.Left });
                }
                var caption = Ui.Text(ImageCaption(row), 12, _theme.Secondary);
                caption.Margin = new Thickness(0, 6, 0, 0);
                stack.Children.Add(caption);
                break;
            }
            case ClipKind.File:
            {
                foreach (var path in row.FilePaths)
                {
                    var line = Ui.Text(path, 12, _theme.Primary, family: Theme.MonoFont);
                    line.TextWrapping = TextWrapping.Wrap;
                    stack.Children.Add(line);
                }
                var reveal = Ui.FlatButton(_theme, $"{Strings.Get("Expanded_Reveal")}  Ctrl+R", () => callbacks.Reveal(row));
                reveal.HorizontalAlignment = HorizontalAlignment.Left;
                reveal.Margin = new Thickness(0, 8, 0, 0);
                stack.Children.Add(reveal);
                break;
            }
            default:
            {
                var full = row.Kind == ClipKind.Text || row.Kind == ClipKind.Code ? FullText(row, callbacks) : row.Title;
                var truncated = full.Length > 10_000;
                if (truncated) full = full[..10_000] + "…";
                var box = new TextBox
                {
                    Text = full,
                    IsReadOnly = true,
                    IsReadOnlyCaretVisible = false,
                    BorderThickness = new Thickness(0),
                    Background = Theme.Transparent,
                    Foreground = _theme.Primary,
                    FontFamily = row.Kind == ClipKind.Code ? Theme.MonoFont : Theme.UiFont,
                    FontSize = row.Kind == ClipKind.Code ? 12 : 13,
                    TextWrapping = row.Kind == ClipKind.Code ? TextWrapping.NoWrap : TextWrapping.Wrap,
                    VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                    HorizontalScrollBarVisibility = row.Kind == ClipKind.Code ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled,
                    MaxHeight = 200,
                    Padding = new Thickness(0),
                    Focusable = false,
                };
                stack.Children.Add(box);
                if (truncated) stack.Children.Add(Ui.Text(Strings.Get("Card_Truncated"), 11, _theme.Secondary));
                break;
            }
        }

        var app = row.SourceAppName ?? row.SourceApp ?? Strings.Get("Source_Unknown");
        var meta = Strings.Format("Card_Meta", app,
            PanelSections.AbsoluteTime(row.FirstCopiedAt, Culture),
            PanelSections.AbsoluteTime(row.LastCopiedAt, Culture),
            row.CopyCount);
        var metaBlock = Ui.Text(meta, 11, _theme.Secondary);
        metaBlock.Margin = new Thickness(0, 10, 0, 0);
        metaBlock.Height = 16;
        stack.Children.Add(metaBlock);
        return stack;
    }

    private static string FullText(ClipRow row, CardCallbacks callbacks)
    {
        try
        {
            var contents = callbacks.Contents(row.Id);
            var text = contents.FirstOrDefault(c => ClipboardFormats.Is(c.Format, ClipboardFormats.UnicodeText))?.Data;
            if (text is not null) return System.Text.Encoding.UTF8.GetString(text).TrimEnd('\0');
        }
        catch (Exception e)
        {
            Log.Warn($"contents could not be loaded for preview: {e.Message}");
        }
        return row.Title;
    }

    private static BitmapSource? ExpandedImage(ClipRow row, CardCallbacks callbacks)
    {
        try
        {
            var png = callbacks.Contents(row.Id).FirstOrDefault(c => ClipboardFormats.Is(c.Format, ClipboardFormats.Png))?.Data ?? row.Thumbnail;
            if (png is null) return null;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = (int)Math.Round(536 * callbacks.Scale);
            image.StreamSource = new MemoryStream(png);
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch (Exception e) when (e is NotSupportedException or FileFormatException or ArgumentException or IOException)
        {
            Log.Warn($"image preview failed: {e.Message}");
            return null;
        }
    }
}
