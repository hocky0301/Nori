using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Nori.Windows.Native;

/// <summary>shell32.dll: the icon Explorer shows for a file or executable.</summary>
internal static class Shell32
{
    public const uint SHGFI_ICON = 0x000000100;
    public const uint SHGFI_LARGEICON = 0x000000000;
    public const uint SHGFI_SMALLICON = 0x000000001;
    public const uint SHGFI_USEFILEATTRIBUTES = 0x000000010;
    public const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct SHFILEINFO
    {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string szTypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SHGetFileInfoW(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbFileInfo, uint uFlags);

    /// <summary>
    /// The shell icon for a path as a frozen WPF bitmap, or null. When the file does not exist the icon
    /// for its extension is used, so file cards still render after the file moved.
    /// </summary>
    public static BitmapSource? IconFor(string path, bool large)
    {
        var info = new SHFILEINFO();
        var flags = SHGFI_ICON | (large ? SHGFI_LARGEICON : SHGFI_SMALLICON);
        if (!File.Exists(path) && !Directory.Exists(path)) flags |= SHGFI_USEFILEATTRIBUTES;
        IntPtr result;
        try
        {
            result = SHGetFileInfoW(path, FILE_ATTRIBUTE_NORMAL, ref info, (uint)Marshal.SizeOf<SHFILEINFO>(), flags);
        }
        catch (Exception)
        {
            return null;
        }
        if (result == IntPtr.Zero || info.hIcon == IntPtr.Zero) return null;
        try
        {
            var bitmap = Imaging.CreateBitmapSourceFromHIcon(info.hIcon, System.Windows.Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            bitmap.Freeze();
            return bitmap;
        }
        catch (Exception)
        {
            return null;
        }
        finally
        {
            User32.DestroyIcon(info.hIcon);
        }
    }

    /// <summary>The shell's type description ("PDF Document", "Application").</summary>
    public static string? TypeName(string path)
    {
        var info = new SHFILEINFO();
        const uint SHGFI_TYPENAME = 0x000000400;
        var flags = SHGFI_TYPENAME | (File.Exists(path) || Directory.Exists(path) ? 0 : SHGFI_USEFILEATTRIBUTES);
        try
        {
            var result = SHGetFileInfoW(path, FILE_ATTRIBUTE_NORMAL, ref info, (uint)Marshal.SizeOf<SHFILEINFO>(), flags);
            return result == IntPtr.Zero || string.IsNullOrWhiteSpace(info.szTypeName) ? null : info.szTypeName;
        }
        catch (Exception)
        {
            return null;
        }
    }
}

/// <summary>shcore.dll: per-monitor DPI, needed to place the panel on the monitor under the cursor.</summary>
internal static class Shcore
{
    public const int MDT_EFFECTIVE_DPI = 0;

    [DllImport("shcore.dll")]
    public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    /// <summary>Scale factor (1.0 at 96 DPI) of a monitor, falling back to the system DPI.</summary>
    public static double ScaleFor(IntPtr monitor)
    {
        try
        {
            if (monitor != IntPtr.Zero && GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, out var dpiX, out _) == 0 && dpiX > 0)
            {
                return dpiX / 96.0;
            }
        }
        catch (DllNotFoundException)
        {
        }
        catch (EntryPointNotFoundException)
        {
        }
        try
        {
            return User32.GetDpiForSystem() / 96.0;
        }
        catch (EntryPointNotFoundException)
        {
            return 1.0;
        }
    }
}
