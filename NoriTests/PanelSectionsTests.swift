import Foundation
import Testing
@testable import Nori

@Suite("PanelSections")
struct PanelSectionsTests {
    private func row(_ title: String, kind: ClipKind = .text, at: Date, pinnedAt: Date? = nil) -> ClipRow {
        ClipRow(id: UUID(), source: .history, kind: kind, title: title, searchText: title.lowercased(),
                sourceBundleID: nil, sourceAppName: nil, isFromUniversalClipboard: false, firstCopiedAt: at,
                lastCopiedAt: at, copyCount: 1, pinnedAt: pinnedAt, byteCount: 1, characterCount: title.count,
                lineCount: 1, isRichText: false, isTruncated: false, linkURL: nil, colorHex: nil, fileURLs: [],
                imagePixelSize: nil, thumbnail: nil, expiresAt: nil, ghostReason: nil)
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test func bucketsAndNumbers() {
        let history = [
            row("today 1", at: now.addingTimeInterval(-60)),
            row("today 2", at: now.addingTimeInterval(-3600)),
            row("yesterday", at: now.addingTimeInterval(-86_400)),
            row("earlier", at: now.addingTimeInterval(-5 * 86_400)),
            row("pinned late", at: now.addingTimeInterval(-9 * 86_400), pinnedAt: now.addingTimeInterval(-100)),
            row("pinned early", at: now.addingTimeInterval(-8 * 86_400), pinnedAt: now.addingTimeInterval(-200)),
        ]
        let ghost = ClipRow.ghost(reason: "Concealed item from 1Password wasn't saved", at: now)
        let sections = PanelSections.build(history: history, sensitive: [], ghosts: [ghost], filter: .all, query: "", now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["Pinned", "Today", "Yesterday", "Earlier"])
        #expect(sections[0].rows.map(\.row.title) == ["pinned early", "pinned late"])
        #expect(sections[0].rows.map(\.number) == [1, 2])
        #expect(sections[1].rows.map(\.row.title) == ["Concealed item from 1Password wasn't saved", "today 1", "today 2"])
        #expect(sections[1].rows.map(\.number) == [nil, 3, 4])
        #expect(sections[2].rows.first?.number == 5)
        #expect(sections[3].rows.first?.number == 6)
    }

    @Test func searchCollapsesIntoResultsAndSkipsSecrets() {
        let history = [row("swift data", at: now), row("rust", at: now.addingTimeInterval(-10)), row("Swift UI", at: now.addingTimeInterval(-20), pinnedAt: now)]
        let secret = ClipRow(id: UUID(), source: .sensitive, kind: .text, title: "•••• swift", searchText: "", sourceBundleID: nil,
                             sourceAppName: nil, isFromUniversalClipboard: false, firstCopiedAt: now, lastCopiedAt: now, copyCount: 1,
                             pinnedAt: nil, byteCount: 1, characterCount: 5, lineCount: 1, isRichText: false, isTruncated: false,
                             linkURL: nil, colorHex: nil, fileURLs: [], imagePixelSize: nil, thumbnail: nil, expiresAt: now, ghostReason: nil)
        let sections = PanelSections.build(history: history, sensitive: [secret], ghosts: [], filter: .all, query: "swift", now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["Results"])
        #expect(Set(sections[0].rows.map(\.row.title)) == ["swift data", "Swift UI"])
        #expect(sections[0].rows.allSatisfy { !$0.titleRanges.isEmpty })
    }

    @Test func filterAppliesToPinnedToo() {
        let history = [row("https://a.dev", kind: .link, at: now, pinnedAt: now), row("plain", at: now)]
        let sections = PanelSections.build(history: history, sensitive: [], ghosts: [], filter: .link, query: "", now: now, calendar: calendar)
        #expect(sections.map(\.title) == ["Pinned"])
        let none = PanelSections.build(history: history, sensitive: [], ghosts: [], filter: .image, query: "", now: now, calendar: calendar)
        #expect(none.isEmpty)
    }

    @Test func relativeTime() {
        #expect(PanelSections.relativeTime(now.addingTimeInterval(-5), now: now) == "now")
        #expect(PanelSections.relativeTime(now.addingTimeInterval(-120), now: now) == "2m")
        #expect(PanelSections.relativeTime(now.addingTimeInterval(-7200), now: now) == "2h")
        #expect(PanelSections.relativeTime(now.addingTimeInterval(-2 * 86_400), now: now) == "2d")
        #expect(PanelSections.relativeTime(now.addingTimeInterval(-30 * 86_400), now: now, calendar: calendar).contains("Dec"))
    }
}
