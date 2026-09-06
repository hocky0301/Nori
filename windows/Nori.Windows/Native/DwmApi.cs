using System.Runtime.InteropServices;

namespace Nori.Windows.Native;

/// <summary>dwmapi.dll: Windows 11 backdrop, rounded corners and dark title-bar mode.</summary>
internal static class DwmApi
{
    public const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    public const int DWMWA_SYSTEMBACKDROP_TYPE = 38;

    public const int DWMWCP_ROUND = 2;
    public const int DWMSBT_NONE = 1;
    public const int DWMSBT_TRANSIENTWINDOW = 3; // acrylic

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS
    {
        public int cxLeftWidth;
        public int cxRightWidth;
        public int cyTopHeight;
        public int cyBottomHeight;
    }

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int dwAttribute, ref int pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS pMarInset);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetColorizationColor(out uint pcrColorization, [MarshalAs(UnmanagedType.Bool)] out bool pfOpaqueBlend);

    public static bool SetAttribute(IntPtr hwnd, int attribute, int value)
    {
        try
        {
            return DwmSetWindowAttribute(hwnd, attribute, ref value, sizeof(int)) == 0;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
        catch (EntryPointNotFoundException)
        {
            return false;
        }
    }

    /// <summary>Windows 11 22H2 (build 22621) introduced the system backdrop attribute.</summary>
    public static bool SupportsSystemBackdrop => Environment.OSVersion.Version.Build >= 22621;

    /// <summary>Windows 11 (build 22000) introduced rounded corners for top-level windows.</summary>
    public static bool SupportsRoundedCorners => Environment.OSVersion.Version.Build >= 22000;
}
