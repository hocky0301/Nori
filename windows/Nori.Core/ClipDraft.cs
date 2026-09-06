namespace Nori.Core;

/// <summary>One clipboard representation: a format name and its bytes.</summary>
public sealed class ClipContent(string format, byte[] data) : IEquatable<ClipContent>
{
    public string Format { get; } = format;
    public byte[] Data { get; } = data;

    public bool Equals(ClipContent? other) =>
        other is not null && string.Equals(Format, other.Format, StringComparison.Ordinal) && Data.AsSpan().SequenceEqual(other.Data);

    public override bool Equals(object? obj) => Equals(obj as ClipContent);

    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(Format);
        hash.AddBytes(Data);
        return hash.ToHashCode();
    }

    public override string ToString() => $"{Format} ({Data.Length} bytes)";
}

/// <summary>
/// A fully-classified, storage-independent description of one clipboard capture. It is a plain
/// value built from a <see cref="ClipboardSnapshot"/>, compared in tests, and only turned into a
/// stored item when the history store decides to keep it.
/// </summary>
public sealed class ClipDraft
{
    public const int MaxTitleLength = 1_000;
    public const int MaxSearchTextLength = 10_000;

    public ClipDraft(IReadOnlyList<ClipContent> contents, string contentHash, ClipKind kind = ClipKind.Text)
    {
        Contents = contents;
        ContentHash = contentHash;
        Kind = kind;
    }

    public ClipKind Kind { get; set; }

    /// <summary>Preview text (whitespace-trimmed, at most <see cref="MaxTitleLength"/> characters).</summary>
    public string Title { get; set; } = string.Empty;

    /// <summary>Text used by search (at most <see cref="MaxSearchTextLength"/> characters).</summary>
    public string SearchText { get; set; } = string.Empty;

    /// <summary>Every clipboard representation worth restoring later, in clipboard order.</summary>
    public IReadOnlyList<ClipContent> Contents { get; set; }

    /// <summary>Executable name (e.g. <c>chrome.exe</c>) / display name of the app that owned the clipboard.</summary>
    public string? SourceApp { get; set; }
    public string? SourceAppName { get; set; }
    public string? SourceAppPath { get; set; }

    /// <summary>SHA-256 over the stable representations; identical hashes mean "the same copy".</summary>
    public string ContentHash { get; set; }

    /// <summary>RTF with real formatting (more than one attribute run) was present.</summary>
    public bool IsRichText { get; set; }

    /// <summary>Plain text was cut at the size cap.</summary>
    public bool IsTruncated { get; set; }

    public Uri? LinkUrl { get; set; }
    public string? ColorHex { get; set; }
    public IReadOnlyList<string> FilePaths { get; set; } = [];
    public (int Width, int Height)? ImagePixelSize { get; set; }

    /// <summary>Small PNG (≤ 224 px on the long side) for image cards; null for other kinds.</summary>
    public byte[]? Thumbnail { get; set; }

    public int CharacterCount { get; set; }
    public int LineCount { get; set; }

    public int ByteCount => Contents.Sum(c => c.Data.Length);

    public byte[]? Data(string format) =>
        Contents.FirstOrDefault(c => ClipboardFormats.Is(c.Format, format))?.Data;

    public string? PlainText
    {
        get
        {
            var data = Data(ClipboardFormats.UnicodeText);
            return data is null ? null : System.Text.Encoding.UTF8.GetString(data);
        }
    }

    public static ClipContent Text(string text) => new(ClipboardFormats.UnicodeText, System.Text.Encoding.UTF8.GetBytes(text));
    public static ClipContent File(string path) => new(ClipboardFormats.FileDrop, System.Text.Encoding.UTF8.GetBytes(path));
}

/// <summary>Secret-looking text: kept in memory only, masked, and forgotten after a while.</summary>
public sealed record SensitiveDraft(SecretDetector.Match Match, string Mask, ClipDraft Draft);
