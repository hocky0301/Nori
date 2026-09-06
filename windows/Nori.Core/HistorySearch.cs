using System.Globalization;

namespace Nori.Core;

/// <summary>A highlighted run in a title: UTF-16 offset and length.</summary>
public readonly record struct TextRange(int Start, int Length)
{
    public int End => Start + Length;
}

/// <summary>
/// Search over the history: case- and diacritic-insensitive substring first, then an in-order
/// subsequence match for typo-tolerant "fuzzy" hits.
/// </summary>
public static class HistorySearch
{
    public sealed record Match(double Score, IReadOnlyList<TextRange> TitleRanges);

    private static readonly CompareInfo Compare = CultureInfo.InvariantCulture.CompareInfo;
    private const CompareOptions Options = CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace | CompareOptions.IgnoreKanaType | CompareOptions.IgnoreWidth;

    public static Match? Find(string query, string title, string searchText)
    {
        var needle = query.Trim();
        if (needle.Length == 0) return new Match(0, []);

        // 1. Every whitespace-separated term must appear somewhere (in title or full text).
        var terms = needle.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        var ranges = new List<TextRange>();
        var allTermsFound = true;
        var bonus = 0.0;
        foreach (var term in terms)
        {
            if (IndexOf(title, term) is { } range)
            {
                ranges.Add(range);
                if (range.Start == 0) bonus -= 0.1;
            }
            else if (IndexOf(searchText, term) is not null)
            {
                bonus += 0.2;
            }
            else
            {
                allTermsFound = false;
                break;
            }
        }
        if (allTermsFound)
        {
            return new Match(1 + bonus + title.Length / 100_000.0, MergeRanges(ranges));
        }

        // 2. Fuzzy: characters of the query appear in order in the title.
        if (needle.Length is < 2 or > 32) return null;
        return SubsequenceMatch(needle, title.Length > 300 ? title[..300] : title);
    }

    /// <summary>Culture-insensitive, accent-insensitive substring search that reports the matched run.</summary>
    public static TextRange? IndexOf(string haystack, string needle)
    {
        if (haystack.Length == 0 || needle.Length == 0) return null;
        var index = Compare.IndexOf(haystack.AsSpan(), needle.AsSpan(), Options, out var length);
        if (index < 0) return null;
        return new TextRange(index, Math.Max(length, 1));
    }

    private static Match? SubsequenceMatch(string needle, string haystack)
    {
        var needleChars = needle.Select(char.ToLowerInvariant).ToArray();
        var ranges = new List<TextRange>();
        var needleIndex = 0;
        var gapPenalty = 0.0;
        var lastMatchOffset = -1;
        for (var offset = 0; offset < haystack.Length && needleIndex < needleChars.Length; offset++)
        {
            if (char.ToLowerInvariant(haystack[offset]) != needleChars[needleIndex]) continue;
            ranges.Add(new TextRange(offset, 1));
            if (lastMatchOffset >= 0) gapPenalty += offset - lastMatchOffset - 1;
            lastMatchOffset = offset;
            needleIndex++;
        }
        if (needleIndex != needleChars.Length) return null;
        var score = 5 + gapPenalty / Math.Max(haystack.Length, 1) * 10 + gapPenalty * 0.01;
        return new Match(score, MergeRanges(ranges));
    }

    public static IReadOnlyList<TextRange> MergeRanges(IEnumerable<TextRange> ranges)
    {
        var merged = new List<TextRange>();
        foreach (var range in ranges.OrderBy(r => r.Start))
        {
            if (merged.Count > 0 && range.Start <= merged[^1].End)
            {
                var last = merged[^1];
                merged[^1] = new TextRange(last.Start, Math.Max(last.End, range.End) - last.Start);
            }
            else
            {
                merged.Add(range);
            }
        }
        return merged;
    }
}
