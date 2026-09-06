using System.Diagnostics;
using System.IO;
using System.Windows.Media.Imaging;
using Nori.Windows.Native;

namespace Nori.Windows.Clipboard;

/// <summary>Executable name, display name and path of the process that owns the clipboard.</summary>
internal sealed record SourceApp(string? ExeName, string? DisplayName, string? Path);

/// <summary>
/// Resolves the clipboard owner to an app (GetClipboardOwner → process image) and caches the
/// display names and icons per executable so the list never touches the shell while scrolling.
/// </summary>
internal sealed class SourceApps
{
    private readonly Dictionary<string, string?> _names = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, BitmapSource?> _icons = new(StringComparer.OrdinalIgnoreCase);

    public SourceApp Current()
    {
        try
        {
            var owner = User32.GetClipboardOwner();
            if (owner == IntPtr.Zero) return new SourceApp(null, null, null);
            User32.GetWindowThreadProcessId(owner, out var pid);
            var path = Kernel32.ProcessImagePath(pid);
            if (path is null) return new SourceApp(null, null, null);
            var exe = System.IO.Path.GetFileName(path);
            return new SourceApp(exe, DisplayName(path), path);
        }
        catch (Exception e)
        {
            Log.Warn($"clipboard owner could not be resolved: {e.Message}");
            return new SourceApp(null, null, null);
        }
    }

    /// <summary>"Google Chrome" for chrome.exe: the file description, else the product name, else the file name.</summary>
    public string? DisplayName(string path)
    {
        if (_names.TryGetValue(path, out var cached)) return cached;
        string? name = null;
        try
        {
            if (File.Exists(path))
            {
                var info = FileVersionInfo.GetVersionInfo(path);
                name = FirstNonEmpty(info.FileDescription, info.ProductName);
            }
        }
        catch (Exception)
        {
            name = null;
        }
        name ??= System.IO.Path.GetFileNameWithoutExtension(path);
        _names[path] = name;
        return name;
    }

    /// <summary>The app's own icon (16 px), cached per executable path; null when it cannot be read.</summary>
    public BitmapSource? Icon(string? path)
    {
        if (string.IsNullOrEmpty(path)) return null;
        if (_icons.TryGetValue(path, out var cached)) return cached;
        var icon = Shell32.IconFor(path, large: false);
        _icons[path] = icon;
        return icon;
    }

    private static string? FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(v => !string.IsNullOrWhiteSpace(v))?.Trim();
}
