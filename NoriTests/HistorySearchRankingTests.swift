import Foundation
import Testing
@testable import Nori

/// Ranking and edge cases on top of `HistorySearchTests`.
@Suite("HistorySearchRanking")
struct HistorySearchRankingTests {
    private func highlighted(_ title: String, _ match: HistorySearch.Match?) -> [String] {
        match?.titleRanges.map { String(title[$0]) } ?? []
    }

    @Test func termsMaySplitBetweenTitleAndBody() throws {
        let title = "Meeting notes"
        let body = "the panel must never steal focus"
        let match = try #require(HistorySearch.match(query: "notes focus", title: title, searchText: body))
        #expect(highlighted(title, match) == ["notes"], "only the title hit is highlighted")
        #expect(match.score > 1, "a body hit costs a little")

        let titleOnly = try #require(HistorySearch.match(query: "meeting notes", title: title, searchText: body))
        #expect(titleOnly.score < match.score)
        #expect(highlighted(title, titleOnly) == ["Meeting", "notes"])
        #expect(HistorySearch.match(query: "notes focus missing", title: title, searchText: body) == nil)
    }

    @Test func prefixHitsRankAboveInteriorHits() throws {
        let prefix = try #require(HistorySearch.match(query: "swift", title: "Swift concurrency", searchText: ""))
        let interior = try #require(HistorySearch.match(query: "swift", title: "Notes on Swift", searchText: ""))
        #expect(prefix.score < interior.score)
    }

    @Test func fuzzyRanksBelowEverySubstringHit() throws {
        let substring = try #require(HistorySearch.match(query: "store", title: "a very long title that mentions the store at the very end of it", searchText: ""))
        let body = try #require(HistorySearch.match(query: "store", title: "unrelated", searchText: "store"))
        let fuzzy = try #require(HistorySearch.match(query: "hstr", title: "HistoryStore", searchText: ""))
        #expect(substring.score < body.score)
        #expect(body.score < fuzzy.score)
        #expect(fuzzy.score >= 5)
        #expect(highlighted("HistoryStore", fuzzy) == ["H", "st", "r"], "adjacent hits merge")

        // Tighter subsequences score better than scattered ones.
        let tight = try #require(HistorySearch.match(query: "hist", title: "History", searchText: ""))
        let scattered = try #require(HistorySearch.match(query: "hist", title: "hx ix sx tx", searchText: ""))
        #expect(tight.score < scattered.score)
    }

    @Test func fuzzyNeedsTwoToThirtyTwoCharacters() {
        #expect(HistorySearch.match(query: "q", title: "quick", searchText: "") != nil, "single char is a substring hit")
        #expect(HistorySearch.match(query: "z", title: "quick", searchText: "") == nil, "single char never goes fuzzy")
        #expect(HistorySearch.match(query: "qk", title: "quick", searchText: "") != nil)
        let long = String(repeating: "ab", count: 17)  // 34 chars
        #expect(HistorySearch.match(query: long, title: String(repeating: "axb", count: 40), searchText: "") == nil)
    }

    @Test func diacriticsAreIgnoredInBothDirections() throws {
        let plainQuery = try #require(HistorySearch.match(query: "resume", title: "Résumé 2026", searchText: ""))
        #expect(highlighted("Résumé 2026", plainQuery) == ["Résumé"])
        let accentedQuery = try #require(HistorySearch.match(query: "résumé", title: "resume 2026", searchText: ""))
        #expect(highlighted("resume 2026", accentedQuery) == ["resume"])
        #expect(HistorySearch.match(query: "ü", title: "Über", searchText: "") != nil)
    }

    @Test func caseFoldingCoversNonASCII() throws {
        let match = try #require(HistorySearch.match(query: "ÉCOLE", title: "école normale", searchText: ""))
        #expect(highlighted("école normale", match) == ["école"])
    }

    @Test func veryLongTitlesStillMatchBySubstringButNotFuzzyPast300() throws {
        let filler = String(repeating: "lorem ipsum ", count: 900)  // ~10 800 chars
        let title = filler + "needle"
        let match = try #require(HistorySearch.match(query: "needle", title: title, searchText: ""))
        #expect(highlighted(title, match) == ["needle"])
        #expect(match.score < 1.2, "length adds only a tiny tie-breaker")

        let shortTitle = "needle"
        let short = try #require(HistorySearch.match(query: "needle", title: shortTitle, searchText: ""))
        #expect(short.score < match.score, "shorter titles win ties")

        // The subsequence scan only looks at the first 300 characters.
        let lateOnly = String(repeating: "x", count: 400) + "abc"
        #expect(HistorySearch.match(query: "abc", title: lateOnly, searchText: "") != nil, "substring still finds it")
        #expect(HistorySearch.match(query: "acb", title: lateOnly, searchText: "") == nil, "fuzzy does not")
        let early = "abc" + String(repeating: "x", count: 400)
        #expect(HistorySearch.match(query: "ac", title: early, searchText: "") != nil)
    }

    @Test func queryWhitespaceIsTrimmedButInnerWhitespaceSplitsTerms() throws {
        let match = try #require(HistorySearch.match(query: "  swift\tdata  ", title: "SwiftData", searchText: ""))
        #expect(highlighted("SwiftData", match) == ["SwiftData"])
        #expect(HistorySearch.match(query: " \t ", title: "x", searchText: "")?.score == 0)
    }
}
