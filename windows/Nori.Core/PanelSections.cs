using System.Globalization;

namespace Nori.Core;

public enum SectionKind
{
    Pinned,
    Today,
    Yesterday,
    Earlier,
    Results,
}

/// <summary>
/// Groups rows into PINNED / TODAY / YESTERDAY / EARLIER (or RESULTS while searching) and
/// assigns the positional Ctrl+1–9 numbers.
/// </summary>
public static class PanelSections
{
    public sealed record Section(SectionKind Kind, IReadOnlyList<Row> Rows);

    /// <param name="Clip">The clip.</param>
    /// <param name="TitleRanges">Highlight ranges in <c>Row.Title</c> for the current query.</param>
    /// <param name="Number">Ctrl+1–9, positional over the visible list; null past nine or for ghost rows.</param>
    public sealed record Row(ClipRow Clip, IReadOnlyList<TextRange> TitleRanges, int? Number)
    {
        public Guid Id => Clip.Id;
    }

    public static IReadOnlyList<Section> Build(
        IReadOnlyList<ClipRow> history,
        IReadOnlyList<ClipRow> sensitive,
        IReadOnlyList<ClipRow> ghosts,
        PanelFilter filter,
        string query,
        DateTimeOffset now,
        TimeZoneInfo? timeZone = null)
    {
        timeZone ??= TimeZoneInfo.Local;
        var searching = query.Trim().Length > 0;

        var scored = new List<(Row Row, double Score)>();
        foreach (var row in history.Concat(sensitive))
        {
            if (!filter.Matches(row.Kind)) continue;
            if (row.IsSensitive && searching) continue; // secrets are never indexed
            var match = HistorySearch.Find(query, row.Title, row.SearchText);
            if (match is null) continue;
            scored.Add((new Row(row, match.TitleRanges, null), match.Score));
        }

        var sections = new List<(SectionKind Kind, List<Row> Rows)>();
        if (searching)
        {
            var ordered = scored
                .Select((entry, index) => (entry, index))
                .OrderBy(x => x.entry.Score)
                .ThenBy(x => x.index)
                .Select(x => x.entry.Row)
                .ToList();
            if (ordered.Count > 0) sections.Add((SectionKind.Results, ordered));
        }
        else
        {
            var pinned = scored.Select(s => s.Row).Where(r => r.Clip.IsPinned)
                .OrderBy(r => r.Clip.PinnedAt ?? DateTimeOffset.MinValue).ToList();
            var unpinned = scored.Select(s => s.Row).Where(r => !r.Clip.IsPinned)
                .OrderByDescending(r => r.Clip.LastCopiedAt).ToList();

            if (pinned.Count > 0) sections.Add((SectionKind.Pinned, pinned));

            var today = filter == PanelFilter.All ? ghosts.Select(g => new Row(g, [], null)).ToList() : [];
            var yesterday = new List<Row>();
            var earlier = new List<Row>();
            var todayDate = LocalDate(now, timeZone);
            foreach (var row in unpinned)
            {
                var day = LocalDate(row.Clip.LastCopiedAt, timeZone);
                if (day == todayDate) today.Add(row);
                else if (day == todayDate.AddDays(-1)) yesterday.Add(row);
                else earlier.Add(row);
            }
            if (today.Count > 0) sections.Add((SectionKind.Today, today));
            if (yesterday.Count > 0) sections.Add((SectionKind.Yesterday, yesterday));
            if (earlier.Count > 0) sections.Add((SectionKind.Earlier, earlier));
        }

        // Numbers are positional over the visible list; ghost rows are skipped.
        var number = 1;
        var result = new List<Section>();
        foreach (var (kind, rows) in sections)
        {
            var numbered = new List<Row>(rows.Count);
            foreach (var row in rows)
            {
                if (!row.Clip.IsGhost && number <= 9)
                {
                    numbered.Add(row with { Number = number });
                    number++;
                }
                else
                {
                    numbered.Add(row);
                }
            }
            result.Add(new Section(kind, numbered));
        }
        return result;
    }

    public static DateOnly LocalDate(DateTimeOffset moment, TimeZoneInfo timeZone) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(moment, timeZone).DateTime);

    /// <summary>Relative time for the meta column: "now", "2m", "1h", "1d", "Sep 3".</summary>
    public static string RelativeTime(DateTimeOffset date, DateTimeOffset now, CultureInfo? culture = null, TimeZoneInfo? timeZone = null)
    {
        culture ??= CultureInfo.InvariantCulture;
        timeZone ??= TimeZoneInfo.Local;
        var seconds = (now - date).TotalSeconds;
        if (seconds < 60) return "now";
        if (seconds < 3_600) return $"{(int)(seconds / 60)}m";
        if (seconds < 86_400) return $"{(int)(seconds / 3_600)}h";
        if (seconds < 7 * 86_400) return $"{(int)(seconds / 86_400)}d";
        var local = TimeZoneInfo.ConvertTime(date, timeZone);
        var localNow = TimeZoneInfo.ConvertTime(now, timeZone);
        var sameYear = local.Year == localNow.Year;
        var japanese = culture.TwoLetterISOLanguageName == "ja";
        var format = (japanese, sameYear) switch
        {
            (true, true) => "M月d日",
            (true, false) => "yyyy年M月d日",
            (false, true) => "MMM d",
            (false, false) => "MMM d yyyy",
        };
        return local.ToString(format, culture);
    }

    /// <summary>"Sep 3, 14:02" for the expanded meta strip.</summary>
    public static string AbsoluteTime(DateTimeOffset date, CultureInfo? culture = null, TimeZoneInfo? timeZone = null)
    {
        culture ??= CultureInfo.InvariantCulture;
        timeZone ??= TimeZoneInfo.Local;
        var local = TimeZoneInfo.ConvertTime(date, timeZone);
        var format = culture.TwoLetterISOLanguageName == "ja" ? "M月d日 HH:mm" : "MMM d, HH:mm";
        return local.ToString(format, culture);
    }
}
