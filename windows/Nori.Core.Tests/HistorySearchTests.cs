using Nori.Core;
using Xunit;

namespace Nori.Core.Tests;

public class HistorySearchTests
{
    private static string[] Highlighted(string title, HistorySearch.Match? match) =>
        match?.TitleRanges.Select(r => title.Substring(r.Start, r.Length)).ToArray() ?? [];

    [Fact]
    public void EmptyQueryMatchesEverything()
    {
        var match = HistorySearch.Find("  ", "anything", "");
        Assert.NotNull(match);
        Assert.Equal(0, match.Score);
    }

    [Fact]
    public void SubstringIsCaseAndDiacriticInsensitive()
    {
        var match = HistorySearch.Find("cafe", "Café au lait", "");
        Assert.NotNull(match);
        Assert.Single(match.TitleRanges);
        Assert.Equal(["Café"], Highlighted("Café au lait", match));
    }

    [Fact]
    public void MultipleTermsMustAllAppear()
    {
        Assert.NotNull(HistorySearch.Find("swift data", "SwiftData rocks", ""));
        Assert.Null(HistorySearch.Find("swift rust", "SwiftData rocks", ""));
    }

    [Fact]
    public void FullTextCountsButScoresLower()
    {
        var inTitle = HistorySearch.Find("needle", "needle first", "")!;
        var inBody = HistorySearch.Find("needle", "some title", "deep in the needle body")!;
        Assert.Empty(inBody.TitleRanges);
        Assert.True(inTitle.Score < inBody.Score);
    }

    [Fact]
    public void FuzzySubsequence()
    {
        var match = HistorySearch.Find("hstr", "HistoryStore", "");
        Assert.NotNull(match);
        Assert.True(match.Score > 1);
        Assert.Null(HistorySearch.Find("xyz", "HistoryStore", ""));
    }

    [Fact]
    public void MergeOverlappingRanges()
    {
        var merged = HistorySearch.MergeRanges([new TextRange(2, 3), new TextRange(0, 3)]);
        Assert.Single(merged);
        Assert.Equal(new TextRange(0, 5), merged[0]);
    }

    [Fact]
    public void TermsMaySplitBetweenTitleAndBody()
    {
        const string title = "Meeting notes";
        const string body = "the panel must never steal focus";
        var match = HistorySearch.Find("notes focus", title, body);
        Assert.NotNull(match);
        Assert.Equal(["notes"], Highlighted(title, match));
        Assert.True(match.Score > 1);

        var titleOnly = HistorySearch.Find("meeting notes", title, body);
        Assert.NotNull(titleOnly);
        Assert.True(titleOnly.Score < match.Score);
        Assert.Equal(["Meeting", "notes"], Highlighted(title, titleOnly));
        Assert.Null(HistorySearch.Find("notes focus missing", title, body));
    }

    [Fact]
    public void PrefixHitsRankAboveInteriorHits()
    {
        var prefix = HistorySearch.Find("swift", "Swift concurrency", "")!;
        var interior = HistorySearch.Find("swift", "Notes on Swift", "")!;
        Assert.True(prefix.Score < interior.Score);
    }

    [Fact]
    public void FuzzyRanksBelowEverySubstringHit()
    {
        var substring = HistorySearch.Find("store", "a very long title that mentions the store at the very end of it", "")!;
        var body = HistorySearch.Find("store", "unrelated", "store")!;
        var fuzzy = HistorySearch.Find("hstr", "HistoryStore", "")!;
        Assert.True(substring.Score < body.Score);
        Assert.True(body.Score < fuzzy.Score);
        Assert.True(fuzzy.Score >= 5);
        Assert.Equal(["H", "st", "r"], Highlighted("HistoryStore", fuzzy));

        var tight = HistorySearch.Find("hist", "History", "")!;
        var scattered = HistorySearch.Find("hist", "hx ix sx tx", "")!;
        Assert.True(tight.Score < scattered.Score);
    }

    [Fact]
    public void FuzzyNeedsTwoToThirtyTwoCharacters()
    {
        Assert.NotNull(HistorySearch.Find("q", "quick", ""));
        Assert.Null(HistorySearch.Find("z", "quick", ""));
        Assert.NotNull(HistorySearch.Find("qk", "quick", ""));
        var longQuery = string.Concat(Enumerable.Repeat("ab", 17));
        Assert.Null(HistorySearch.Find(longQuery, string.Concat(Enumerable.Repeat("axb", 40)), ""));
    }

    [Fact]
    public void DiacriticsAreIgnoredInBothDirections()
    {
        Assert.Equal(["Résumé"], Highlighted("Résumé 2026", HistorySearch.Find("resume", "Résumé 2026", "")));
        Assert.Equal(["resume"], Highlighted("resume 2026", HistorySearch.Find("résumé", "resume 2026", "")));
        Assert.NotNull(HistorySearch.Find("ü", "Über", ""));
    }

    [Fact]
    public void CaseFoldingCoversNonAscii()
    {
        Assert.Equal(["école"], Highlighted("école normale", HistorySearch.Find("ÉCOLE", "école normale", "")));
    }

    [Fact]
    public void JapaneseWidthAndKanaAreFolded()
    {
        Assert.NotNull(HistorySearch.Find("ﾉﾘ", "ノリ 海苔", ""));
        Assert.NotNull(HistorySearch.Find("のり", "ノリ", ""));
    }

    [Fact]
    public void VeryLongTitlesStillMatchBySubstringButNotFuzzyPast300()
    {
        var title = string.Concat(Enumerable.Repeat("lorem ipsum ", 900)) + "needle";
        var match = HistorySearch.Find("needle", title, "");
        Assert.NotNull(match);
        Assert.Equal(["needle"], Highlighted(title, match));
        Assert.True(match.Score < 1.2);

        var shortMatch = HistorySearch.Find("needle", "needle", "")!;
        Assert.True(shortMatch.Score < match.Score);

        var lateOnly = new string('x', 400) + "abc";
        Assert.NotNull(HistorySearch.Find("abc", lateOnly, ""));
        Assert.Null(HistorySearch.Find("acb", lateOnly, ""));
        Assert.NotNull(HistorySearch.Find("ac", "abc" + new string('x', 400), ""));
    }

    [Fact]
    public void QueryWhitespaceIsTrimmedButInnerWhitespaceSplitsTerms()
    {
        var match = HistorySearch.Find("  swift\tdata  ", "SwiftData", "");
        Assert.Equal(["SwiftData"], Highlighted("SwiftData", match));
        Assert.Equal(0, HistorySearch.Find(" \t ", "x", "")?.Score);
    }
}
