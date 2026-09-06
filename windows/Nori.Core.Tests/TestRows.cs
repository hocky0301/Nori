using Nori.Core;

namespace Nori.Core.Tests;

/// <summary>Row and draft fixtures shared by the panel, vault and store suites.</summary>
internal static class TestRows
{
    public static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000); // 2027-01-15 08:00 UTC
    public static readonly TimeZoneInfo Utc = TimeZoneInfo.Utc;

    public static ClipRow Row(string title, ClipKind kind = ClipKind.Text, DateTimeOffset? at = null, DateTimeOffset? pinnedAt = null,
        string? link = null, RowSource source = RowSource.History)
    {
        var time = at ?? T0;
        return new ClipRow
        {
            Id = Guid.NewGuid(),
            Source = source,
            Kind = kind,
            Title = title,
            SearchText = title.ToLowerInvariant(),
            FirstCopiedAt = time,
            LastCopiedAt = time,
            CopyCount = 1,
            PinnedAt = pinnedAt,
            ByteCount = title.Length,
            CharacterCount = title.Length,
            LineCount = 1,
            LinkUrl = link is null ? null : new Uri(link),
            ExpiresAt = source == RowSource.Sensitive ? time : null,
        };
    }

    public static ClipDraft TextDraft(string text, string? app = "notepad.exe")
    {
        var draft = ClipClassifier.MakeDraft([ClipDraft.Text(text)], app)!;
        draft.SourceApp = app;
        return draft;
    }

    public static SensitiveDraft Sensitive(string text)
    {
        var draft = TextDraft(text);
        var match = SecretDetector.Detect(text) ?? SecretDetector.Match.CardNumber;
        return new SensitiveDraft(match, SecretDetector.Mask(text), draft);
    }
}
