using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Nori.Core;

namespace Nori.Windows.Clipboard;

/// <summary>
/// Decodes whatever bitmap the copy carried (PNG bytes, or a BitmapSource captured from CF_DIB)
/// with WPF's imaging stack, stores PNG only, and makes a ≤ 224 px thumbnail.
/// </summary>
internal sealed class WpfImageNormalizer : IImageNormalizer
{
    public static readonly WpfImageNormalizer Instance = new();

    public const int ThumbnailMaxPixels = 224;

    public ImageResult? Normalize(IReadOnlyList<ClipContent> contents)
    {
        var png = contents.FirstOrDefault(c => ClipboardFormats.Is(c.Format, ClipboardFormats.Png))?.Data;
        if (png is null) return null;
        try
        {
            var frame = Decode(png);
            if (frame is null) return null;
            // Re-encode only when the bytes were not a real PNG (some apps put junk in the "PNG" format).
            var bytes = PngHeaderNormalizer.PngSize(png) is null ? EncodePng(frame) : png;
            return new ImageResult(bytes, frame.PixelWidth, frame.PixelHeight, Thumbnail(frame));
        }
        catch (Exception e) when (e is NotSupportedException or FileFormatException or ArgumentException or InvalidOperationException)
        {
            Log.Warn($"image could not be decoded: {e.Message}");
            return null;
        }
    }

    public static BitmapSource? Decode(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        if (decoder.Frames.Count == 0) return null;
        var frame = decoder.Frames[0];
        frame.Freeze();
        return frame;
    }

    public static byte[] EncodePng(BitmapSource source)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var output = new MemoryStream();
        encoder.Save(output);
        return output.ToArray();
    }

    public static byte[]? Thumbnail(BitmapSource source)
    {
        var longest = Math.Max(source.PixelWidth, source.PixelHeight);
        if (longest <= 0) return null;
        var scale = Math.Min(1.0, (double)ThumbnailMaxPixels / longest);
        BitmapSource scaled = source;
        if (scale < 1)
        {
            var transformed = new TransformedBitmap(source, new ScaleTransform(scale, scale));
            transformed.Freeze();
            scaled = transformed;
        }
        return EncodePng(scaled);
    }
}
