using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Nori.Core;
using Nori.Windows.Resources;

namespace Nori.Windows.Panel;

/// <summary>Small factories for the flat controls the panel is made of (no XAML, no templates).</summary>
internal static class Ui
{
    public const double Inset = 12;
    public const double RowGap = 8;
    public const double CardGap = 4;
    public const double CardPadV = 10;
    public const double CardPadH = 12;
    public const double WellSize = 28;
    public const double ThumbSize = 56;
    public const double WellGap = 10;
    public const double MetaGap = 8;
    public const double MetaWidth = 128;
    public const double SectionAbove = 16;
    public const double SectionBelow = 6;
    public const double HintGap = 14;
    public const double PanelRadius = 22;
    public const double CardRadius = 12;
    public const double WellRadius = 7;
    public const double ThumbRadius = 8;
    public const double SearchRadius = 18;
    public const double ChipRadius = 12;
    public const double KeycapRadius = 5;
    public const double GhostRadius = 8;

    public static readonly FontFamily IconFont = new("Segoe MDL2 Assets, Segoe Fluent Icons, Segoe UI Symbol");

    // Segoe MDL2 Assets glyphs.
    public const string GlyphSearch = "\uE721";
    public const string GlyphMore = "\uE712";
    public const string GlyphPause = "\uE769";
    public const string GlyphText = "\uE8E4";      // AlignLeft
    public const string GlyphLink = "\uE71B";
    public const string GlyphCode = "\uE943";
    public const string GlyphPhoto = "\uE91B";
    public const string GlyphDocument = "\uE8A5";
    public const string GlyphLock = "\uE72E";
    public const string GlyphStar = "\uE735";
    public const string GlyphClipboard = "\uE77F";
    public const string GlyphWarning = "\uE7BA";
    public const string GlyphApp = "\uE7C3";       // generic app icon fallback (Page)
    public const string GlyphFolder = "\uE8B7";

    public static TextBlock Text(string text, double size, Brush foreground, FontWeight? weight = null, FontFamily? family = null)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            Foreground = foreground,
            FontFamily = family ?? Theme.UiFont,
            FontWeight = weight ?? FontWeights.Normal,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        TextOptions.SetTextFormattingMode(block, TextFormattingMode.Display);
        return block;
    }

    public static TextBlock Glyph(string glyph, double size, Brush foreground)
    {
        var block = new TextBlock
        {
            Text = glyph,
            FontSize = size,
            Foreground = foreground,
            FontFamily = IconFont,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        return block;
    }

    /// <summary>A keycap: 11 pt medium, 18 pt tall, min width 26, r=5.</summary>
    public static Border Keycap(Theme theme, string text, double opacity = 1)
    {
        var block = Text(text, 11, theme.Primary, FontWeights.Medium);
        block.HorizontalAlignment = HorizontalAlignment.Center;
        block.Margin = new Thickness(6, 0, 6, 0);
        return new Border
        {
            Child = block,
            Background = theme.KeycapFill,
            BorderBrush = theme.KeycapStroke,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(KeycapRadius),
            Height = 18,
            MinWidth = 26,
            Opacity = opacity,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// <summary>A flat, keyboard-neutral button (a Border that reacts to clicks), so the panel keeps its look.</summary>
    public static Border FlatButton(Theme theme, string text, Action onClick, bool accent = false)
    {
        var label = Text(text, 12, accent ? Brushes.White : theme.Primary, FontWeights.Medium);
        label.HorizontalAlignment = HorizontalAlignment.Center;
        var border = new Border
        {
            Child = label,
            Background = accent ? theme.AccentBrush : theme.KeycapFill,
            BorderBrush = accent ? Theme.Transparent : theme.KeycapStroke,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(6),
            Padding = new Thickness(12, 5, 12, 5),
            Cursor = Cursors.Hand,
            Focusable = false,
        };
        border.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            onClick();
        };
        border.MouseEnter += (_, _) => border.Opacity = 0.85;
        border.MouseLeave += (_, _) => border.Opacity = 1;
        return border;
    }

    public static string FilterLabel(PanelFilter filter) => filter switch
    {
        PanelFilter.Text => Strings.Get("Filter_Text"),
        PanelFilter.Link => Strings.Get("Filter_Links"),
        PanelFilter.Code => Strings.Get("Filter_Code"),
        PanelFilter.Color => Strings.Get("Filter_Colors"),
        PanelFilter.Image => Strings.Get("Filter_Images"),
        PanelFilter.File => Strings.Get("Filter_Files"),
        _ => Strings.Get("Filter_All"),
    };

    public static string SectionLabel(SectionKind kind) => kind switch
    {
        SectionKind.Pinned => Strings.Get("Section_Pinned"),
        SectionKind.Today => Strings.Get("Section_Today"),
        SectionKind.Yesterday => Strings.Get("Section_Yesterday"),
        SectionKind.Earlier => Strings.Get("Section_Earlier"),
        _ => Strings.Get("Section_Results"),
    };

    public static string EmptyFilterLabel(PanelFilter filter) => filter switch
    {
        PanelFilter.Link => Strings.Get("Empty_Filter_Link"),
        PanelFilter.Code => Strings.Get("Empty_Filter_Code"),
        PanelFilter.Color => Strings.Get("Empty_Filter_Color"),
        PanelFilter.Image => Strings.Get("Empty_Filter_Image"),
        PanelFilter.File => Strings.Get("Empty_Filter_File"),
        _ => Strings.Get("Empty_Filter_Text"),
    };

    public static string GhostText(GhostReason? reason) => reason switch
    {
        GhostReason.Concealed { AppName: { Length: > 0 } app } => Strings.Format("Card_Ghost_Concealed", app),
        GhostReason.Concealed => Strings.Get("Card_Ghost_ConcealedUnknown"),
        GhostReason.ImageTooLarge large => Strings.Format("Card_Ghost_ImageTooLarge", ByteSize.Format(large.Bytes)),
        _ => Strings.Get("Card_Ghost_ConcealedUnknown"),
    };

    /// <summary>"8m" style countdown for sensitive cards.</summary>
    public static string ExpiryText(DateTimeOffset expiresAt, DateTimeOffset now)
    {
        var remaining = expiresAt - now;
        if (remaining <= TimeSpan.Zero) return "0m";
        var minutes = (int)Math.Ceiling(remaining.TotalMinutes);
        return $"{minutes}m";
    }

    /// <summary>Adds runs to a TextBlock with the query terms highlighted (accent tint, never bold).</summary>
    public static void HighlightedText(TextBlock block, string text, string query, Theme theme)
    {
        block.Inlines.Clear();
        var ranges = new List<TextRange>();
        foreach (var term in query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
        {
            if (HistorySearch.IndexOf(text, term) is { } range) ranges.Add(range);
        }
        var merged = HistorySearch.MergeRanges(ranges);
        var cursor = 0;
        foreach (var range in merged)
        {
            if (range.Start > cursor) block.Inlines.Add(new System.Windows.Documents.Run(text[cursor..range.Start]));
            var end = Math.Min(text.Length, range.End);
            block.Inlines.Add(new System.Windows.Documents.Run(text[range.Start..end]) { Background = theme.MatchHighlight });
            cursor = end;
        }
        if (cursor < text.Length) block.Inlines.Add(new System.Windows.Documents.Run(text[cursor..]));
    }
}
