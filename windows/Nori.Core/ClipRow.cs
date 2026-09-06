namespace Nori.Core;

public enum RowSource
{
    History,
    Sensitive,
    Ghost,
}

/// <summary>
/// Everything a card needs, as an immutable value. Built by <see cref="HistoryStore"/> from stored
/// items, by <see cref="SensitiveVault"/> for masked secrets, and by the panel for ghost rows.
/// </summary>
public sealed record ClipRow
{
    public required Guid Id { get; init; }
    public required RowSource Source { get; init; }
    public required ClipKind Kind { get; init; }
    public required string Title { get; init; }
    public string SearchText { get; init; } = string.Empty;
    public string? SourceApp { get; init; }
    public string? SourceAppName { get; init; }
    public string? SourceAppPath { get; init; }
    public required DateTimeOffset FirstCopiedAt { get; init; }
    public required DateTimeOffset LastCopiedAt { get; init; }
    public int CopyCount { get; init; } = 1;
    public DateTimeOffset? PinnedAt { get; init; }
    public int ByteCount { get; init; }
    public int CharacterCount { get; init; }
    public int LineCount { get; init; }
    public bool IsRichText { get; init; }
    public bool IsTruncated { get; init; }
    public Uri? LinkUrl { get; init; }
    public string? ColorHex { get; init; }
    public IReadOnlyList<string> FilePaths { get; init; } = [];
    public (int Width, int Height)? ImagePixelSize { get; init; }
    public byte[]? Thumbnail { get; init; }

    /// <summary>Sensitive rows only: when the in-memory copy disappears.</summary>
    public DateTimeOffset? ExpiresAt { get; init; }

    /// <summary>Ghost rows only: why nothing was saved.</summary>
    public GhostReason? GhostReason { get; init; }

    public bool IsPinned => PinnedAt is not null;
    public bool IsSensitive => Source == RowSource.Sensitive;
    public bool IsGhost => Source == RowSource.Ghost;

    /// <summary>First non-empty line with runs of whitespace collapsed — what the card's title line shows.</summary>
    public string DisplayTitle
    {
        get
        {
            var firstLine = KindDetector.SplitLines(Title).FirstOrDefault(l => l.Trim().Length > 0) ?? Title;
            return string.Join(' ', firstLine.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        }
    }

    /// <summary>The first two lines, leading whitespace preserved (code cards).</summary>
    public IReadOnlyList<string> CodeLines
    {
        get
        {
            var expanded = Title.Replace("\t", "    ");
            var lines = KindDetector.SplitLines(expanded);
            var firstNonEmpty = lines.FindIndex(l => l.Trim(' ').Length > 0);
            if (firstNonEmpty < 0) firstNonEmpty = 0;
            return lines.Skip(firstNonEmpty).Take(2).ToList();
        }
    }

    /// <summary>mailto: links have no host to show (.NET parses the address domain as Host).</summary>
    public bool IsMailto => LinkUrl is not null && LinkUrl.Scheme.Equals("mailto", StringComparison.OrdinalIgnoreCase);

    public string? LinkHost
    {
        get
        {
            if (LinkUrl is null || IsMailto || string.IsNullOrEmpty(LinkUrl.Host)) return null;
            var host = LinkUrl.Host;
            return host.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? host[4..] : host;
        }
    }

    /// <summary>Path + query of a link, or null when it is just the root.</summary>
    public string? LinkPathAndQuery
    {
        get
        {
            if (LinkUrl is null || IsMailto || !LinkUrl.IsAbsoluteUri || string.IsNullOrEmpty(LinkUrl.Host)) return null;
            var path = Uri.UnescapeDataString(LinkUrl.AbsolutePath);
            var query = LinkUrl.Query;
            if (query.Length > 1) path += Uri.UnescapeDataString(query);
            return path is "/" or "" ? null : path;
        }
    }

    /// <summary>File names for file cards ("3 files" is rendered by the UI when there are several).</summary>
    public IReadOnlyList<string> FileNames => FilePaths.Select(ClipClassifier.FileName).ToList();

    public static ClipRow Ghost(GhostReason reason, DateTimeOffset at, string? appName = null) => new()
    {
        Id = Guid.NewGuid(),
        Source = RowSource.Ghost,
        Kind = ClipKind.Text,
        Title = reason switch
        {
            GhostReason.Concealed c => $"Concealed item from {c.AppName ?? appName ?? "an app"} wasn't saved",
            GhostReason.ImageTooLarge i => $"Image too large ({ByteSize.Format(i.Bytes)}) wasn't saved",
            _ => "Item wasn't saved",
        },
        FirstCopiedAt = at,
        LastCopiedAt = at,
        CopyCount = 0,
        GhostReason = reason,
    };
}

/// <summary>"412 KB" style sizes, matching the card captions.</summary>
public static class ByteSize
{
    public static string Format(long bytes)
    {
        if (bytes < 1000) return $"{bytes} B";
        if (bytes < 1000 * 1000) return $"{bytes / 1000.0:0} KB";
        if (bytes < 1000L * 1000 * 1000) return $"{bytes / 1_000_000.0:0.#} MB";
        return $"{bytes / 1_000_000_000.0:0.##} GB";
    }
}
