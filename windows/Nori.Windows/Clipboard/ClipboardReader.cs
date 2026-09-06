using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Media.Imaging;
using Nori.Core;

namespace Nori.Windows.Clipboard;

/// <summary>
/// Freezes the system clipboard into a <see cref="ClipboardSnapshot"/>. Runs on the UI thread
/// (OLE clipboard access is STA-bound) and retries because another app may still hold the clipboard
/// open for a few milliseconds after WM_CLIPBOARDUPDATE.
/// </summary>
internal static class ClipboardReader
{
    private const int MaxRawBytes = 12 * 1024 * 1024;

    public static ClipboardSnapshot? Read(SourceApps apps, IClock clock)
    {
        var data = GetDataObjectWithRetry();
        if (data is null) return null;

        string[] formats;
        try
        {
            formats = data.GetFormats(autoConvert: false) ?? [];
        }
        catch (Exception e) when (e is COMException or ExternalException)
        {
            Log.Warn($"clipboard formats could not be listed: {e.Message}");
            return null;
        }

        var declared = new HashSet<string>(formats, StringComparer.OrdinalIgnoreCase);
        var representations = new List<(string Format, byte[]? Data)>();
        var canIncludeInHistory = true;
        var hasPng = false;

        foreach (var format in formats)
        {
            if (ClipboardFormats.Is(format, ClipboardFormats.CanIncludeInHistory))
            {
                var dword = ReadBytes(data, format);
                if (dword is { Length: >= 4 } && BitConverter.ToUInt32(dword, 0) == 0) canIncludeInHistory = false;
                continue;
            }
            if (ClipboardFormats.Is(format, ClipboardFormats.ExcludeFromMonitoring))
            {
                continue; // presence is enough; the classifier reads it from the declared formats
            }
            if (ClipboardFormats.Is(format, ClipboardFormats.UnicodeText))
            {
                representations.Add((ClipboardFormats.UnicodeText, ReadString(data, DataFormats.UnicodeText)));
            }
            else if (ClipboardFormats.Is(format, ClipboardFormats.Html))
            {
                representations.Add((ClipboardFormats.Html, ReadString(data, DataFormats.Html)));
            }
            else if (ClipboardFormats.Is(format, ClipboardFormats.Rtf))
            {
                representations.Add((ClipboardFormats.Rtf, ReadString(data, DataFormats.Rtf)));
            }
            else if (ClipboardFormats.Is(format, ClipboardFormats.FileDrop))
            {
                foreach (var path in ReadFiles(data))
                {
                    representations.Add((ClipboardFormats.FileDrop, Encoding.UTF8.GetBytes(path)));
                }
            }
            else if (ClipboardFormats.Is(format, ClipboardFormats.Png))
            {
                var png = ReadBytes(data, format);
                if (png is not null && PngHeaderNormalizer.PngSize(png) is not null)
                {
                    representations.Add((ClipboardFormats.Png, png));
                    hasPng = true;
                }
            }
            else if (ClipboardFormats.Is(format, ClipboardFormats.Dib) || ClipboardFormats.Is(format, ClipboardFormats.Bitmap) || ClipboardFormats.Is(format, "Format17"))
            {
                // Converted below to one PNG when no real PNG is present.
            }
            else if (ClipboardFormats.Is(format, ClipboardFormats.NoriItem))
            {
                representations.Add((ClipboardFormats.NoriItem, ReadBytes(data, format)));
            }
            else if (format.StartsWith("Format", StringComparison.Ordinal) || ClipboardFormats.MetadataFormats.Contains(format))
            {
                representations.Add((format, null)); // declared only; dropped by the classifier
            }
            else
            {
                representations.Add((format, ReadBytes(data, format)));
            }
        }

        if (!hasPng && formats.Any(f => f is "Bitmap" or "DeviceIndependentBitmap" or "Format17"))
        {
            var png = ReadBitmapAsPng(data);
            if (png is not null)
            {
                representations.Insert(0, (ClipboardFormats.Png, png));
                declared.Add(ClipboardFormats.Png);
            }
        }

        var app = apps.Current();
        var item = new ClipboardSnapshot.Item(representations);
        return new ClipboardSnapshot(declared, [item], app.ExeName, app.DisplayName, app.Path, clock.Now, canIncludeInHistory);
    }

    private static IDataObject? GetDataObjectWithRetry()
    {
        for (var attempt = 0; attempt < 6; attempt++)
        {
            try
            {
                return System.Windows.Clipboard.GetDataObject();
            }
            catch (Exception e) when (e is COMException or ExternalException)
            {
                Thread.Sleep(20 * (attempt + 1));
            }
        }
        Log.Warn("clipboard stayed locked; change skipped");
        return null;
    }

    private static byte[]? ReadString(IDataObject data, string format)
    {
        try
        {
            return data.GetData(format, autoConvert: false) switch
            {
                string s => Encoding.UTF8.GetBytes(s),
                MemoryStream stream => stream.ToArray(),
                _ => null,
            };
        }
        catch (Exception e) when (e is COMException or ExternalException or InvalidOperationException or NotSupportedException)
        {
            return null;
        }
    }

    private static byte[]? ReadBytes(IDataObject data, string format)
    {
        try
        {
            var value = data.GetData(format, autoConvert: false);
            switch (value)
            {
                case MemoryStream stream:
                    if (stream.Length > MaxRawBytes) return null;
                    return stream.ToArray();
                case byte[] bytes:
                    return bytes;
                case string s:
                    return Encoding.UTF8.GetBytes(s);
                default:
                    return null;
            }
        }
        catch (Exception e) when (e is COMException or ExternalException or InvalidOperationException or NotSupportedException or System.Runtime.Serialization.SerializationException)
        {
            return null;
        }
    }

    private static IEnumerable<string> ReadFiles(IDataObject data)
    {
        try
        {
            return data.GetData(DataFormats.FileDrop, autoConvert: false) is string[] paths
                ? paths.Where(p => !string.IsNullOrWhiteSpace(p))
                : [];
        }
        catch (Exception e) when (e is COMException or ExternalException or InvalidOperationException)
        {
            return [];
        }
    }

    /// <summary>Lets WPF convert CF_DIB / CF_BITMAP to a BitmapSource, then encodes PNG.</summary>
    private static byte[]? ReadBitmapAsPng(IDataObject data)
    {
        try
        {
            if (data.GetData(DataFormats.Bitmap, autoConvert: true) is BitmapSource source)
            {
                return WpfImageNormalizer.EncodePng(source);
            }
        }
        catch (Exception e) when (e is COMException or ExternalException or InvalidOperationException or NotSupportedException)
        {
            Log.Warn($"bitmap could not be read: {e.Message}");
        }
        return null;
    }
}
