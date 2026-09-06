using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using Nori.Core;

namespace Nori.Windows;

/// <summary>
/// Semantic brushes for the panel, resolved once per theme. Light and dark differ only in the
/// opacity steps (see the product spec's color roles); kind tints live in the wells only.
/// </summary>
internal sealed class Theme
{
    public bool IsDark { get; }
    public Color Accent { get; }

    public Theme(bool isDark, Color? accent = null)
    {
        IsDark = isDark;
        Accent = accent ?? Color.FromRgb(0x5E, 0x5C, 0xE6);
        var primary = isDark ? Colors.White : Color.FromRgb(0x1D, 0x1D, 0x1F);
        Primary = Solid(primary);
        Secondary = Solid(primary, isDark ? 0.62 : 0.58);
        Tertiary = Solid(primary, isDark ? 0.38 : 0.34);
        PanelBackground = Solid(isDark ? Color.FromRgb(0x20, 0x20, 0x24) : Color.FromRgb(0xF5, 0xF5, 0xF7));
        PanelTint = Solid(isDark ? Color.FromRgb(0x20, 0x20, 0x24) : Color.FromRgb(0xF5, 0xF5, 0xF7), 0.72);
        PanelBorder = Solid(primary, isDark ? 0.14 : 0.10);
        CardFill = Solid(primary, isDark ? 0.06 : 0.04);
        CardExpandedFill = Solid(primary, isDark ? 0.08 : 0.06);
        CardSelectedFill = Solid(Accent, isDark ? 0.28 : 0.22);
        CardSelectedStroke = Solid(Accent, isDark ? 0.40 : 0.35);
        CardExpandedStroke = Solid(Accent, isDark ? 0.35 : 0.30);
        SearchFill = Solid(primary, isDark ? 0.08 : 0.06);
        KeycapFill = Solid(primary, isDark ? 0.10 : 0.08);
        KeycapStroke = Solid(primary, isDark ? 0.14 : 0.12);
        ToastFill = Solid(isDark ? Color.FromRgb(0x3A, 0x3A, 0x40) : Color.FromRgb(0xE4, 0xE4, 0xE8));
        ChipHover = Solid(primary, 0.06);
        Separator = Solid(primary, isDark ? 0.16 : 0.12);
        MatchHighlight = Solid(Accent, isDark ? 0.35 : 0.25);
        GhostFill = Solid(primary, isDark ? 0.05 : 0.04);
        GhostStripe = Solid(primary, 0.05);
        WellStroke = Solid(primary, 0.10);
        AccentBrush = Solid(Accent);
        Star = Solid(Color.FromRgb(0xF5, 0xB3, 0x01));
        Warning = Solid(Color.FromRgb(0xE0, 0xA0, 0x00));
        WindowBackground = Solid(isDark ? Color.FromRgb(0x1F, 0x1F, 0x23) : Color.FromRgb(0xFA, 0xFA, 0xFB));
        ControlFill = Solid(primary, isDark ? 0.08 : 0.05);
    }

    public SolidColorBrush Primary { get; }
    public SolidColorBrush Secondary { get; }
    public SolidColorBrush Tertiary { get; }
    public SolidColorBrush PanelBackground { get; }
    public SolidColorBrush PanelTint { get; }
    public SolidColorBrush PanelBorder { get; }
    public SolidColorBrush CardFill { get; }
    public SolidColorBrush CardExpandedFill { get; }
    public SolidColorBrush CardSelectedFill { get; }
    public SolidColorBrush CardSelectedStroke { get; }
    public SolidColorBrush CardExpandedStroke { get; }
    public SolidColorBrush SearchFill { get; }
    public SolidColorBrush KeycapFill { get; }
    public SolidColorBrush KeycapStroke { get; }
    public SolidColorBrush ToastFill { get; }
    public SolidColorBrush ChipHover { get; }
    public SolidColorBrush Separator { get; }
    public SolidColorBrush MatchHighlight { get; }
    public SolidColorBrush GhostFill { get; }
    public SolidColorBrush GhostStripe { get; }
    public SolidColorBrush WellStroke { get; }
    public SolidColorBrush AccentBrush { get; }
    public SolidColorBrush Star { get; }
    public SolidColorBrush Warning { get; }
    public SolidColorBrush WindowBackground { get; }
    public SolidColorBrush ControlFill { get; }

    public static readonly Brush Transparent = Brushes.Transparent;

    /// <summary>Kind tint for the well (text is neutral, link blue, code indigo, image teal, sensitive red).</summary>
    public Color KindTint(ClipKind kind, bool sensitive = false)
    {
        if (sensitive) return Color.FromRgb(0xE5, 0x3E, 0x3E);
        return kind switch
        {
            ClipKind.Link => Color.FromRgb(0x2F, 0x7C, 0xF6),
            ClipKind.Code => Color.FromRgb(0x5E, 0x5C, 0xE6),
            ClipKind.Image => Color.FromRgb(0x2A, 0xA1, 0x98),
            _ => IsDark ? Color.FromRgb(0xB0, 0xB0, 0xB8) : Color.FromRgb(0x6E, 0x6E, 0x73),
        };
    }

    public static SolidColorBrush Solid(Color color, double opacity = 1)
    {
        var brush = new SolidColorBrush(Color.FromArgb((byte)Math.Round(255 * opacity), color.R, color.G, color.B));
        brush.Freeze();
        return brush;
    }

    public static readonly FontFamily UiFont = new("Segoe UI Variable Text, Segoe UI, Yu Gothic UI, Meiryo UI, sans-serif");
    public static readonly FontFamily MonoFont = new("Cascadia Mono, Consolas, Courier New, monospace");

    // MARK: - System state

    /// <summary>Reads AppsUseLightTheme; dark when the value is 0 or the key is missing on a dark-defaulted system.</summary>
    public static bool SystemPrefersDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// <summary>The DWM colorization (accent) color, or null when unavailable.</summary>
    public static Color? SystemAccent()
    {
        try
        {
            if (Native.DwmApi.DwmGetColorizationColor(out var argb, out _) == 0)
            {
                var color = Color.FromRgb((byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);
                // Very light or very dark accents make the selection unreadable; keep the brand color then.
                var luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B;
                return luminance is > 40 and < 210 ? color : null;
            }
        }
        catch (Exception)
        {
        }
        return null;
    }

    public static bool ReduceMotion => !SystemParameters.ClientAreaAnimation;
}
