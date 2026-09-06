namespace Nori.Core;

/// <summary>One persisted clip: the row metadata plus its representations (loaded on demand by the repository).</summary>
public sealed record StoredClip
{
    public required Guid Id { get; init; }
    public required ClipKind Kind { get; init; }
    public required string Title { get; init; }
    public required string SearchText { get; init; }
    public required string ContentHash { get; init; }
    public string? SourceApp { get; init; }
    public string? SourceAppName { get; init; }
    public string? SourceAppPath { get; init; }
    public required DateTimeOffset FirstCopiedAt { get; init; }
    public required DateTimeOffset LastCopiedAt { get; init; }
    public int CopyCount { get; init; } = 1;
    public DateTimeOffset? PinnedAt { get; init; }
    public bool IsRichText { get; init; }
    public bool IsTruncated { get; init; }
    public int LineCount { get; init; }
    public int CharacterCount { get; init; }
    public int ByteCount { get; init; }
    public Uri? LinkUrl { get; init; }
    public string? ColorHex { get; init; }
    public IReadOnlyList<string> FilePaths { get; init; } = [];
    public (int Width, int Height)? ImagePixelSize { get; init; }
    public byte[]? Thumbnail { get; init; }

    public bool IsPinned => PinnedAt is not null;

    public ClipRow ToRow() => new()
    {
        Id = Id,
        Source = RowSource.History,
        Kind = Kind,
        Title = Title,
        SearchText = SearchText,
        SourceApp = SourceApp,
        SourceAppName = SourceAppName,
        SourceAppPath = SourceAppPath,
        FirstCopiedAt = FirstCopiedAt,
        LastCopiedAt = LastCopiedAt,
        CopyCount = CopyCount,
        PinnedAt = PinnedAt,
        ByteCount = ByteCount,
        CharacterCount = CharacterCount,
        LineCount = LineCount,
        IsRichText = IsRichText,
        IsTruncated = IsTruncated,
        LinkUrl = LinkUrl,
        ColorHex = ColorHex,
        FilePaths = FilePaths,
        ImagePixelSize = ImagePixelSize,
        Thumbnail = Thumbnail,
    };

    public static StoredClip FromDraft(ClipDraft draft, Guid id, DateTimeOffset now) => new()
    {
        Id = id,
        Kind = draft.Kind,
        Title = draft.Title,
        SearchText = draft.SearchText,
        ContentHash = draft.ContentHash,
        SourceApp = draft.SourceApp,
        SourceAppName = draft.SourceAppName,
        SourceAppPath = draft.SourceAppPath,
        FirstCopiedAt = now,
        LastCopiedAt = now,
        CopyCount = 1,
        PinnedAt = null,
        IsRichText = draft.IsRichText,
        IsTruncated = draft.IsTruncated,
        LineCount = draft.LineCount,
        CharacterCount = draft.CharacterCount,
        ByteCount = draft.ByteCount,
        LinkUrl = draft.LinkUrl,
        ColorHex = draft.ColorHex,
        FilePaths = draft.FilePaths,
        ImagePixelSize = draft.ImagePixelSize,
        Thumbnail = draft.Thumbnail,
    };
}

/// <summary>Persistence behind <see cref="HistoryStore"/>: SQLite in the app, a list in tests.</summary>
public interface IClipRepository
{
    IReadOnlyList<StoredClip> LoadAll();
    void Insert(StoredClip clip, IReadOnlyList<ClipContent> contents);
    void Update(StoredClip clip);
    void Delete(IReadOnlyList<Guid> ids);
    IReadOnlyList<ClipContent> Contents(Guid id);
    /// <summary>Approximate bytes on disk (for the Privacy tab).</summary>
    long StorageBytes();
}

public sealed class InMemoryClipRepository : IClipRepository
{
    private readonly Dictionary<Guid, (StoredClip Clip, IReadOnlyList<ClipContent> Contents)> _rows = [];

    public IReadOnlyList<StoredClip> LoadAll() => _rows.Values.Select(r => r.Clip).ToList();

    public void Insert(StoredClip clip, IReadOnlyList<ClipContent> contents) => _rows[clip.Id] = (clip, contents);

    public void Update(StoredClip clip)
    {
        if (_rows.TryGetValue(clip.Id, out var existing)) _rows[clip.Id] = (clip, existing.Contents);
    }

    public void Delete(IReadOnlyList<Guid> ids)
    {
        foreach (var id in ids) _rows.Remove(id);
    }

    public IReadOnlyList<ClipContent> Contents(Guid id) => _rows.TryGetValue(id, out var row) ? row.Contents : [];

    public long StorageBytes() => _rows.Values.Sum(r => (long)r.Clip.ByteCount);
}

/// <summary>What a delete leaves behind so Ctrl+Z can put the clip back exactly where it was.</summary>
public sealed record DeleteRecord(StoredClip Clip, IReadOnlyList<ClipContent> Contents);

/// <summary>Single-level undo with a time window (the toast's four seconds).</summary>
public sealed class UndoBuffer
{
    public static readonly TimeSpan Window = TimeSpan.FromSeconds(4);
    private DeleteRecord? _record;
    private DateTimeOffset _at;

    public void Remember(DeleteRecord record, DateTimeOffset now)
    {
        _record = record;
        _at = now;
    }

    /// <summary>The record if it is still inside the window; it is consumed either way.</summary>
    public DeleteRecord? Take(DateTimeOffset now)
    {
        var record = _record;
        _record = null;
        return record is not null && now - _at <= Window ? record : null;
    }

    public bool HasPending => _record is not null;
}

/// <summary>
/// The history: dedup by content hash, item cap (pinned exempt), age expiry, delete/restore, pins.
/// Rows are kept in memory newest-first; the repository is the durable copy.
/// </summary>
public sealed class HistoryStore
{
    private readonly IClipRepository _repository;
    private readonly List<StoredClip> _clips = [];

    public HistoryStore(IClipRepository repository)
    {
        _repository = repository;
    }

    public int MaxItems { get; set; } = 500;

    /// <summary>0 = never.</summary>
    public int ExpireAfterDays { get; set; }

    public int Version { get; private set; }

    public IReadOnlyList<ClipRow> Rows => _clips.Select(c => c.ToRow()).ToList();

    public IReadOnlyList<StoredClip> Clips => _clips;

    public int Count => _clips.Count;
    public int PinnedCount => _clips.Count(c => c.IsPinned);

    public void Load()
    {
        _clips.Clear();
        _clips.AddRange(_repository.LoadAll().OrderByDescending(c => c.LastCopiedAt));
        Version++;
    }

    public ClipRow? Row(Guid id) => Clip(id)?.ToRow();

    public StoredClip? Clip(Guid id) => _clips.FirstOrDefault(c => c.Id == id);

    public StoredClip? ClipByHash(string hash) => _clips.FirstOrDefault(c => c.ContentHash == hash);

    public IReadOnlyList<ClipContent> Contents(Guid id) => _repository.Contents(id);

    /// <summary>Insert a new clip or bump an identical one; returns the id of the row that now represents it.</summary>
    public Guid Ingest(ClipDraft draft, DateTimeOffset now)
    {
        var existingIndex = _clips.FindIndex(c => c.ContentHash == draft.ContentHash);
        if (existingIndex >= 0)
        {
            var existing = _clips[existingIndex];
            var bumped = existing with
            {
                LastCopiedAt = now,
                CopyCount = existing.CopyCount + 1,
                SourceApp = draft.SourceApp ?? existing.SourceApp,
                SourceAppName = draft.SourceAppName ?? existing.SourceAppName,
                SourceAppPath = draft.SourceAppPath ?? existing.SourceAppPath,
            };
            _clips.RemoveAt(existingIndex);
            _clips.Insert(0, bumped);
            _repository.Update(bumped);
            Version++;
            return bumped.Id;
        }

        var clip = StoredClip.FromDraft(draft, Guid.NewGuid(), now);
        _clips.Insert(0, clip);
        _repository.Insert(clip, draft.Contents);
        EnforceLimit();
        Version++;
        return clip.Id;
    }

    /// <summary>Nori pasted this clip: it moves to the top like a fresh copy.</summary>
    public void Touch(Guid id, DateTimeOffset now)
    {
        var index = _clips.FindIndex(c => c.Id == id);
        if (index < 0) return;
        var clip = _clips[index] with { LastCopiedAt = now, CopyCount = _clips[index].CopyCount + 1 };
        _clips.RemoveAt(index);
        _clips.Insert(0, clip);
        _repository.Update(clip);
        Version++;
    }

    public void TogglePin(Guid id, DateTimeOffset now)
    {
        var index = _clips.FindIndex(c => c.Id == id);
        if (index < 0) return;
        var clip = _clips[index] with { PinnedAt = _clips[index].IsPinned ? null : now };
        _clips[index] = clip;
        _repository.Update(clip);
        EnforceLimit();
        Version++;
    }

    public DeleteRecord? Delete(Guid id)
    {
        var index = _clips.FindIndex(c => c.Id == id);
        if (index < 0) return null;
        var clip = _clips[index];
        var contents = _repository.Contents(id);
        _clips.RemoveAt(index);
        _repository.Delete([id]);
        Version++;
        return new DeleteRecord(clip, contents);
    }

    /// <summary>Put a deleted clip back with its dates, pin and position.</summary>
    public Guid Restore(DeleteRecord record)
    {
        var clip = record.Clip;
        var insertAt = _clips.FindIndex(c => c.LastCopiedAt <= clip.LastCopiedAt);
        _clips.Insert(insertAt < 0 ? _clips.Count : insertAt, clip);
        _repository.Insert(clip, record.Contents);
        Version++;
        return clip.Id;
    }

    /// <summary>Removes unpinned (or all) clips; returns how many went.</summary>
    public int Clear(bool includingPinned)
    {
        var doomed = _clips.Where(c => includingPinned || !c.IsPinned).Select(c => c.Id).ToList();
        if (doomed.Count == 0) return 0;
        _clips.RemoveAll(c => doomed.Contains(c.Id));
        _repository.Delete(doomed);
        Version++;
        return doomed.Count;
    }

    /// <summary>Age expiry; pinned clips are exempt.</summary>
    public int ExpireOldItems(DateTimeOffset now)
    {
        if (ExpireAfterDays <= 0) return 0;
        var cutoff = now.AddDays(-ExpireAfterDays);
        var doomed = _clips.Where(c => !c.IsPinned && c.LastCopiedAt < cutoff).Select(c => c.Id).ToList();
        if (doomed.Count == 0) return 0;
        _clips.RemoveAll(c => doomed.Contains(c.Id));
        _repository.Delete(doomed);
        Version++;
        return doomed.Count;
    }

    public long StorageBytes() => _repository.StorageBytes();

    private void EnforceLimit()
    {
        var unpinned = _clips.Where(c => !c.IsPinned).OrderByDescending(c => c.LastCopiedAt).ToList();
        if (unpinned.Count <= MaxItems) return;
        var doomed = unpinned.Skip(MaxItems).Select(c => c.Id).ToList();
        _clips.RemoveAll(c => doomed.Contains(c.Id));
        _repository.Delete(doomed);
    }
}
