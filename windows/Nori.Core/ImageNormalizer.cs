using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace Nori.Core;

public sealed record ImageResult(byte[] Png, int Width, int Height, byte[]? Thumbnail);

/// <summary>
/// Turns whatever bitmap representations a copy carries into one PNG (plus an optional thumbnail).
/// The platform layer supplies a real decoder; Core ships a PNG-only implementation for tests.
/// </summary>
public interface IImageNormalizer
{
    ImageResult? Normalize(IReadOnlyList<ClipContent> contents);
}

/// <summary>Reads PNG dimensions from the IHDR chunk; no decoding, no thumbnail. Ignores DIB/Bitmap payloads.</summary>
public sealed class PngHeaderNormalizer : IImageNormalizer
{
    public static readonly PngHeaderNormalizer Instance = new();

    public const int ThumbnailMaxPixels = 224;

    public ImageResult? Normalize(IReadOnlyList<ClipContent> contents)
    {
        var png = contents.FirstOrDefault(c => ClipboardFormats.Is(c.Format, ClipboardFormats.Png))?.Data;
        if (png is null) return null;
        var size = PngSize(png);
        return size is null ? null : new ImageResult(png, size.Value.Width, size.Value.Height, null);
    }

    private static ReadOnlySpan<byte> PngSignature => [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    /// <summary>Width and height from the IHDR chunk, or null when the bytes are not a PNG.</summary>
    public static (int Width, int Height)? PngSize(ReadOnlySpan<byte> png)
    {
        if (png.Length < 24 || !png[..8].SequenceEqual(PngSignature)) return null;
        if (!png.Slice(12, 4).SequenceEqual("IHDR"u8)) return null;
        var width = BinaryPrimitives.ReadInt32BigEndian(png.Slice(16, 4));
        var height = BinaryPrimitives.ReadInt32BigEndian(png.Slice(20, 4));
        return width > 0 && height > 0 ? (width, height) : null;
    }

    /// <summary>A minimal valid PNG (RGB, one colour) for fixtures and tests.</summary>
    public static byte[] SolidPng(int width, int height, byte r = 0x5E, byte g = 0x5C, byte b = 0xE6)
    {
        var raw = new byte[(width * 3 + 1) * height];
        for (var y = 0; y < height; y++)
        {
            var row = y * (width * 3 + 1);
            raw[row] = 0; // filter: none
            for (var x = 0; x < width; x++)
            {
                raw[row + 1 + x * 3] = r;
                raw[row + 2 + x * 3] = g;
                raw[row + 3 + x * 3] = b;
            }
        }
        using var deflated = new MemoryStream();
        using (var z = new System.IO.Compression.ZLibStream(deflated, System.IO.Compression.CompressionLevel.Fastest, leaveOpen: true))
        {
            z.Write(raw);
        }
        using var png = new MemoryStream();
        png.Write(PngSignature);
        var ihdr = new byte[13];
        BinaryPrimitives.WriteInt32BigEndian(ihdr.AsSpan(0, 4), width);
        BinaryPrimitives.WriteInt32BigEndian(ihdr.AsSpan(4, 4), height);
        ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
        WriteChunk(png, "IHDR", ihdr);
        WriteChunk(png, "IDAT", deflated.ToArray());
        WriteChunk(png, "IEND", []);
        return png.ToArray();
    }

    private static void WriteChunk(Stream stream, string type, byte[] data)
    {
        Span<byte> length = stackalloc byte[4];
        BinaryPrimitives.WriteInt32BigEndian(length, data.Length);
        stream.Write(length);
        var typeBytes = Encoding.ASCII.GetBytes(type);
        stream.Write(typeBytes);
        stream.Write(data);
        var crc = Crc32(typeBytes, data);
        Span<byte> crcBytes = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(crcBytes, crc);
        stream.Write(crcBytes);
    }

    private static uint Crc32(byte[] a, byte[] b)
    {
        uint crc = 0xFFFFFFFF;
        foreach (var chunk in new[] { a, b })
        {
            foreach (var value in chunk)
            {
                crc ^= value;
                for (var i = 0; i < 8; i++)
                {
                    crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
                }
            }
        }
        return ~crc;
    }
}

/// <summary>
/// Hash of the representations that identify a copy. Two copies of the same text from different
/// apps (which add different custom formats) still collide, which is what users expect.
/// </summary>
public static class ContentHash
{
    public static string Of(IReadOnlyList<ClipContent> contents)
    {
        var stable = contents.Where(c => ClipboardFormats.StableFormats.Contains(c.Format)).ToList();
        var hashed = (stable.Count == 0 ? contents : stable).OrderBy(c => c.Format, StringComparer.Ordinal).ToList();
        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        Span<byte> length = stackalloc byte[8];
        foreach (var content in hashed)
        {
            sha.AppendData(Encoding.UTF8.GetBytes(content.Format));
            sha.AppendData([0]);
            BinaryPrimitives.WriteUInt64LittleEndian(length, (ulong)content.Data.Length);
            sha.AppendData(length);
            sha.AppendData(content.Data);
        }
        return Convert.ToHexStringLower(sha.GetHashAndReset());
    }
}
