using System.Globalization;
using Nori.Core;
using Xunit;
using static Nori.Core.Tests.TestRows;

namespace Nori.Core.Tests;

public class PanelSectionsTests
{
    [Fact]
    public void BucketsAndNumbers()
    {
        var history = new[]
        {
            Row("today 1", at: T0.AddSeconds(-60)),
            Row("today 2", at: T0.AddHours(-1)),
            Row("yesterday", at: T0.AddDays(-1)),
            Row("earlier", at: T0.AddDays(-5)),
            Row("pinned late", at: T0.AddDays(-9), pinnedAt: T0.AddSeconds(-100)),
            Row("pinned early", at: T0.AddDays(-8), pinnedAt: T0.AddSeconds(-200)),
        };
        var ghost = ClipRow.Ghost(new GhostReason.Concealed("1Password"), T0);
        var sections = PanelSections.Build(history, [], [ghost], PanelFilter.All, "", T0, Utc);
        Assert.Equal([SectionKind.Pinned, SectionKind.Today, SectionKind.Yesterday, SectionKind.Earlier], sections.Select(s => s.Kind));
        Assert.Equal(["pinned early", "pinned late"], sections[0].Rows.Select(r => r.Clip.Title));
        Assert.Equal([1, 2], sections[0].Rows.Select(r => r.Number));
        Assert.Equal(["Concealed item from 1Password wasn't saved", "today 1", "today 2"], sections[1].Rows.Select(r => r.Clip.Title));
        Assert.Equal([null, 3, 4], sections[1].Rows.Select(r => r.Number));
        Assert.Equal(5, sections[2].Rows[0].Number);
        Assert.Equal(6, sections[3].Rows[0].Number);
    }

    [Fact]
    public void NumbersStopAtNine()
    {
        var history = Enumerable.Range(0, 12).Select(i => Row($"row {i}", at: T0.AddSeconds(-i))).ToList();
        var sections = PanelSections.Build(history, [], [], PanelFilter.All, "", T0, Utc);
        var numbers = sections.Single().Rows.Select(r => r.Number).ToList();
        Assert.Equal([1, 2, 3, 4, 5, 6, 7, 8, 9, null, null, null], numbers);
    }

    [Fact]
    public void SearchCollapsesIntoResultsAndSkipsSecrets()
    {
        var history = new[] { Row("swift data"), Row("rust", at: T0.AddSeconds(-10)), Row("Swift UI", at: T0.AddSeconds(-20), pinnedAt: T0) };
        var secret = Row("•••• swift", source: RowSource.Sensitive) with { SearchText = "" };
        var sections = PanelSections.Build(history, [secret], [], PanelFilter.All, "swift", T0, Utc);
        Assert.Equal([SectionKind.Results], sections.Select(s => s.Kind));
        Assert.Equal(new HashSet<string> { "swift data", "Swift UI" }, sections[0].Rows.Select(r => r.Clip.Title).ToHashSet());
        Assert.All(sections[0].Rows, r => Assert.NotEmpty(r.TitleRanges));
    }

    [Fact]
    public void SecretsAppearInTodayWhenNotSearching()
    {
        var secret = Row("•••• 1111", source: RowSource.Sensitive) with { SearchText = "" };
        var sections = PanelSections.Build([Row("text", at: T0.AddSeconds(-5))], [secret], [], PanelFilter.All, "", T0, Utc);
        Assert.Equal([SectionKind.Today], sections.Select(s => s.Kind));
        Assert.Equal(["•••• 1111", "text"], sections[0].Rows.Select(r => r.Clip.Title));
        Assert.Equal([1, 2], sections[0].Rows.Select(r => r.Number));
    }

    [Fact]
    public void FilterAppliesToPinnedToo()
    {
        var history = new[] { Row("https://a.dev", ClipKind.Link, pinnedAt: T0), Row("plain") };
        var sections = PanelSections.Build(history, [], [], PanelFilter.Link, "", T0, Utc);
        Assert.Equal([SectionKind.Pinned], sections.Select(s => s.Kind));
        Assert.Empty(PanelSections.Build(history, [], [], PanelFilter.Image, "", T0, Utc));
    }

    [Fact]
    public void GhostRowsHideUnderAFilter()
    {
        var ghost = ClipRow.Ghost(new GhostReason.ImageTooLarge(48_000_000), T0);
        Assert.Equal("Image too large (48 MB) wasn't saved", ghost.Title);
        var all = PanelSections.Build([Row("x")], [], [ghost], PanelFilter.All, "", T0, Utc);
        Assert.Equal(2, all[0].Rows.Count);
        var filtered = PanelSections.Build([Row("x")], [], [ghost], PanelFilter.Text, "", T0, Utc);
        Assert.Single(filtered[0].Rows);
    }

    [Fact]
    public void DayBucketsFollowTheGivenTimeZone()
    {
        // 23:30 UTC on the 14th is "yesterday" in UTC at 03:00 on the 15th, but the same evening (18:30) in UTC-5.
        var now = new DateTimeOffset(2027, 1, 15, 3, 0, 0, TimeSpan.Zero);
        var row = Row("late night", at: new DateTimeOffset(2027, 1, 14, 23, 30, 0, TimeSpan.Zero));
        var utc = PanelSections.Build([row], [], [], PanelFilter.All, "", now, Utc);
        Assert.Equal(SectionKind.Yesterday, utc[0].Kind);
        var newYork = TimeZoneInfo.CreateCustomTimeZone("test-5", TimeSpan.FromHours(-5), "UTC-5", "UTC-5");
        var ny = PanelSections.Build([row], [], [], PanelFilter.All, "", now, newYork);
        Assert.Equal(SectionKind.Today, ny[0].Kind);
    }

    [Fact]
    public void RelativeTime()
    {
        Assert.Equal("now", PanelSections.RelativeTime(T0.AddSeconds(-5), T0));
        Assert.Equal("2m", PanelSections.RelativeTime(T0.AddSeconds(-120), T0));
        Assert.Equal("2h", PanelSections.RelativeTime(T0.AddSeconds(-7200), T0));
        Assert.Equal("2d", PanelSections.RelativeTime(T0.AddDays(-2), T0));
        Assert.Contains("Dec", PanelSections.RelativeTime(T0.AddDays(-30), T0, CultureInfo.InvariantCulture, Utc));
        Assert.Equal("Dec 16 2026", PanelSections.RelativeTime(T0.AddDays(-30), T0, CultureInfo.InvariantCulture, Utc));
        Assert.Equal("Jan 5", PanelSections.RelativeTime(T0.AddDays(-10), T0, CultureInfo.InvariantCulture, Utc));
        Assert.Equal("1月5日", PanelSections.RelativeTime(T0.AddDays(-10), T0, CultureInfo.GetCultureInfo("ja-JP"), Utc));
        Assert.Equal("Jan 15, 08:00", PanelSections.AbsoluteTime(T0, CultureInfo.InvariantCulture, Utc));
    }

    [Fact]
    public void ByteSizeCaptions()
    {
        Assert.Equal("412 KB", ByteSize.Format(412_000));
        Assert.Equal("48 MB", ByteSize.Format(48_000_000));
        Assert.Equal("999 B", ByteSize.Format(999));
        Assert.Equal("1.5 MB", ByteSize.Format(1_500_000));
    }
}
