import Foundation
import Testing
@testable import Nori

@Suite("HistorySearch")
struct HistorySearchTests {
    @Test func emptyQueryMatchesEverything() {
        #expect(HistorySearch.match(query: "  ", title: "anything", searchText: "") != nil)
    }

    @Test func substringIsCaseAndDiacriticInsensitive() {
        let match = HistorySearch.match(query: "cafe", title: "Café au lait", searchText: "")
        #expect(match != nil)
        #expect(match?.titleRanges.count == 1)
        #expect(match.map { String("Café au lait"[$0.titleRanges[0]]) } == "Café")
    }

    @Test func multipleTermsMustAllAppear() {
        #expect(HistorySearch.match(query: "swift data", title: "SwiftData rocks", searchText: "") != nil)
        #expect(HistorySearch.match(query: "swift rust", title: "SwiftData rocks", searchText: "") == nil)
    }

    @Test func fullTextCountsButScoresLower() {
        let inTitle = HistorySearch.match(query: "needle", title: "needle first", searchText: "")!
        let inBody = HistorySearch.match(query: "needle", title: "some title", searchText: "deep in the needle body")!
        #expect(inBody.titleRanges.isEmpty)
        #expect(inTitle.score < inBody.score)
    }

    @Test func fuzzySubsequence() {
        let match = HistorySearch.match(query: "hstr", title: "HistoryStore", searchText: "")
        #expect(match != nil)
        #expect((match?.score ?? 0) > 1)
        #expect(HistorySearch.match(query: "xyz", title: "HistoryStore", searchText: "") == nil)
    }

    @Test func mergeOverlappingRanges() {
        let text = "abcdef"
        let a = text.startIndex..<text.index(text.startIndex, offsetBy: 3)
        let b = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 5)
        let merged = HistorySearch.mergeRanges([b, a])
        #expect(merged.count == 1)
        #expect(String(text[merged[0]]) == "abcde")
    }
}
