namespace Nori.Core;

/// <summary>
/// Secrets live here, never in the database: masked in the list, pasteable, gone after ten minutes.
/// The app runs <see cref="Sweep"/> on a timer; Core keeps the logic clock-driven so it is testable.
/// </summary>
public sealed class SensitiveVault
{
    public sealed class Entry
    {
        public required Guid Id { get; init; }
        public required SecretDetector.Match Match { get; init; }
        public required string Mask { get; init; }
        public required ClipDraft Draft { get; init; }
        public required DateTimeOffset CapturedAt { get; init; }
        public DateTimeOffset ExpiresAt { get; set; }
    }

    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);

    private readonly List<Entry> _entries = [];

    public IReadOnlyList<Entry> Entries => _entries;

    /// <summary>Bumped on every visible change so observers can refresh cheaply.</summary>
    public int Version { get; private set; }

    public IReadOnlyList<ClipRow> Rows => _entries.Select(entry => new ClipRow
    {
        Id = entry.Id,
        Source = RowSource.Sensitive,
        Kind = entry.Draft.Kind,
        Title = entry.Mask,
        SearchText = string.Empty,
        SourceApp = entry.Draft.SourceApp,
        SourceAppName = entry.Draft.SourceAppName,
        SourceAppPath = entry.Draft.SourceAppPath,
        FirstCopiedAt = entry.CapturedAt,
        LastCopiedAt = entry.CapturedAt,
        CopyCount = 1,
        PinnedAt = null,
        ByteCount = entry.Draft.ByteCount,
        CharacterCount = entry.Draft.CharacterCount,
        LineCount = entry.Draft.LineCount,
        ExpiresAt = entry.ExpiresAt,
    }).ToList();

    /// <summary>Add a secret, or extend the life of an identical one.</summary>
    public Guid Add(SensitiveDraft sensitive, DateTimeOffset now)
    {
        var index = _entries.FindIndex(e => e.Draft.ContentHash == sensitive.Draft.ContentHash);
        if (index >= 0)
        {
            var existing = _entries[index];
            existing.ExpiresAt = now + Lifetime;
            _entries.RemoveAt(index);
            _entries.Insert(0, existing);
            Version++;
            return existing.Id;
        }
        var entry = new Entry
        {
            Id = Guid.NewGuid(),
            Match = sensitive.Match,
            Mask = sensitive.Mask,
            Draft = sensitive.Draft,
            CapturedAt = now,
            ExpiresAt = now + Lifetime,
        };
        _entries.Insert(0, entry);
        Version++;
        return entry.Id;
    }

    public Entry? Find(Guid id) => _entries.FirstOrDefault(e => e.Id == id);

    /// <summary>Pasting a secret keeps it around for another ten minutes.</summary>
    public void Touch(Guid id, DateTimeOffset now)
    {
        var index = _entries.FindIndex(e => e.Id == id);
        if (index < 0) return;
        var entry = _entries[index];
        entry.ExpiresAt = now + Lifetime;
        _entries.RemoveAt(index);
        _entries.Insert(0, entry);
        Version++;
    }

    public void Remove(Guid id)
    {
        _entries.RemoveAll(e => e.Id == id);
        Version++;
    }

    public void RemoveAll()
    {
        _entries.Clear();
        Version++;
    }

    /// <summary>Drops expired entries; expiry is inclusive (<c>ExpiresAt &lt;= now</c>).</summary>
    public void Sweep(DateTimeOffset now)
    {
        var removed = _entries.RemoveAll(e => e.ExpiresAt <= now);
        if (removed > 0) Version++;
    }
}
