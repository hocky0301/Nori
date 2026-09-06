using System.Collections.Specialized;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using Nori.Core;

namespace Nori.Windows.Clipboard;

/// <summary>
/// Puts a clip back on the clipboard. Every write carries the <c>Nori.Item</c> marker so the
/// capture side promotes the existing item instead of recording a duplicate.
/// </summary>
internal static class ClipboardWriter
{
    public static bool Write(IReadOnlyList<ClipContent> contents, Guid itemId, bool plain)
    {
        var data = new DataObject();
        var files = new StringCollection();
        var hasPlainString = contents.Any(c => ClipboardFormats.Is(c.Format, ClipboardFormats.UnicodeText));
        // "Plain" without a plain string would paste nothing: keep the original formats then.
        var reduce = plain && hasPlainString;

        foreach (var content in contents)
        {
            var format = content.Format;
            if (reduce && !ClipboardFormats.Is(format, ClipboardFormats.UnicodeText) && !ClipboardFormats.Is(format, ClipboardFormats.FileDrop))
            {
                continue;
            }
            try
            {
                if (ClipboardFormats.Is(format, ClipboardFormats.UnicodeText))
                {
                    data.SetData(DataFormats.UnicodeText, Encoding.UTF8.GetString(content.Data));
                }
                else if (ClipboardFormats.Is(format, ClipboardFormats.Html))
                {
                    data.SetData(DataFormats.Html, Encoding.UTF8.GetString(content.Data));
                }
                else if (ClipboardFormats.Is(format, ClipboardFormats.Rtf))
                {
                    data.SetData(DataFormats.Rtf, Encoding.UTF8.GetString(content.Data));
                }
                else if (ClipboardFormats.Is(format, ClipboardFormats.FileDrop))
                {
                    files.Add(Encoding.UTF8.GetString(content.Data));
                }
                else if (ClipboardFormats.Is(format, ClipboardFormats.Png))
                {
                    data.SetData(ClipboardFormats.Png, new MemoryStream(content.Data));
                    // Apps that only understand CF_DIB / CF_BITMAP (Paint, Office) get a converted copy.
                    if (WpfImageNormalizer.Decode(content.Data) is { } bitmap) data.SetImage(bitmap);
                }
                else
                {
                    data.SetData(format, new MemoryStream(content.Data));
                }
            }
            catch (Exception e) when (e is COMException or ExternalException or ArgumentException or NotSupportedException)
            {
                Log.Warn($"format {format} could not be written: {e.Message}");
            }
        }
        if (files.Count > 0) data.SetFileDropList(files);
        data.SetData(ClipboardFormats.NoriItem, new MemoryStream(Encoding.UTF8.GetBytes(itemId.ToString())));
        return SetWithRetry(data);
    }

    /// <summary>Typed-text paste: the query as plain text, captured afterwards as a normal text clip.</summary>
    public static bool WriteText(string text)
    {
        var data = new DataObject();
        data.SetData(DataFormats.UnicodeText, text);
        return SetWithRetry(data);
    }

    private static bool SetWithRetry(DataObject data)
    {
        for (var attempt = 0; attempt < 6; attempt++)
        {
            try
            {
                System.Windows.Clipboard.SetDataObject(data, copy: true);
                return true;
            }
            catch (Exception e) when (e is COMException or ExternalException)
            {
                Thread.Sleep(20 * (attempt + 1));
            }
        }
        Log.Error("clipboard could not be written");
        return false;
    }
}
