namespace Nori.Core;

public enum PanelPosition
{
    Cursor = 0,
    Center = 1,
    Tray = 2,
}

/// <summary>A rectangle in device-independent pixels (top-left origin, like WPF).</summary>
public readonly record struct PanelRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

/// <summary>Where the panel goes and how tall it is. Pure geometry so the WPF window only applies the result.</summary>
public static class PanelPlacement
{
    public const double Width = 560;
    public const double MinHeight = 320;
    public const double MaxHeight = 620;
    public const double HeightFactor = 0.75;
    public const double TrayMargin = 12;

    /// <summary>clamp(floor(workArea.Height × 0.75), 320, 620), computed once per open.</summary>
    public static double Height(PanelRect workArea) =>
        Math.Clamp(Math.Floor(workArea.Height * HeightFactor), MinHeight, MaxHeight);

    public static PanelRect Compute(PanelPosition position, PanelRect workArea, double cursorX, double cursorY)
    {
        var height = Height(workArea);
        double x, y;
        switch (position)
        {
            case PanelPosition.Center:
                x = workArea.X + (workArea.Width - Width) / 2;
                y = workArea.Y + Math.Floor(workArea.Height * 0.22);
                break;
            case PanelPosition.Tray:
                x = workArea.Right - Width - TrayMargin;
                y = workArea.Bottom - height - TrayMargin;
                break;
            default:
                x = cursorX;
                y = cursorY;
                break;
        }
        return Clamp(new PanelRect(x, y, Width, height), workArea);
    }

    /// <summary>Keeps the whole panel inside the work area (a panel narrower than the area never overflows).</summary>
    public static PanelRect Clamp(PanelRect panel, PanelRect workArea)
    {
        var x = Math.Max(workArea.X, Math.Min(panel.X, workArea.Right - panel.Width));
        var y = Math.Max(workArea.Y, Math.Min(panel.Y, workArea.Bottom - panel.Height));
        return panel with { X = x, Y = y };
    }
}
