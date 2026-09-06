import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Nori

/// Card highlights mapped from the model's match ranges, file captions without disk access,
/// prepared text previews, and the clear-confirmation counts.
@Suite("Panel UI fixes")
struct PanelUIFixesTests {
    private func row(_ title: String, kind: ClipKind = .text, files: [URL] = []) -> ClipRow {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return ClipRow(
            id: UUID(), source: .history, kind: kind, title: title, searchText: title, sourceBundleID: nil,
            sourceAppName: nil, isFromUniversalClipboard: false, firstCopiedAt: now, lastCopiedAt: now,
            copyCount: 1, pinnedAt: nil, byteCount: title.utf8.count, characterCount: title.count, lineCount: 1,
            isRichText: false, isTruncated: false, linkURL: nil, colorHex: nil, fileURLs: files,
            imagePixelSize: nil, thumbnail: nil, expiresAt: nil, ghostReason: nil
        )
    }

    private func highlighted(_ mapped: HighlightedText.Mapped) -> [String] {
        mapped.ranges.map { String(mapped.text[$0]) }
    }

    // MARK: Highlights (F32)

    @Test func displayTitleMappingMatchesClipRow() {
        let titles = [
            "Meeting   notes\t\tfor   today\nsecond line", "  leading and trailing  ", "one\r\ntwo", "single",
            "a\u{2028}b", "\nsecond", "\n\n  third  \nx", "", "\n", "   \nfoo", "tab\there", "日本語　の　テキスト",
        ]
        for title in titles {
            #expect(HighlightedText.displayTitle(title, ranges: []).text == row(title).displayTitle, "\(title.debugDescription)")
        }
    }

    @Test func codeLinesMappingMatchesClipRow() {
        let sources = ["\n   \n\tif x {\n\t\treturn\n\t}\n", "  indented\nsecond\nthird", "only", "first\n", "", "  \n\t", "a\r\nb\r\nc"]
        for source in sources {
            #expect(HighlightedText.codeLines(source, ranges: []).text == row(source, kind: .code).codeLines.joined(separator: "\n"), "\(source.debugDescription)")
        }
    }

    @Test func substringHitsSurviveWhitespaceCollapsing() {
        let title = "  Swift   and   swiftui\nsecond swift line"
        let match = HistorySearch.match(query: "swift", title: title, searchText: title)!
        let mapped = HighlightedText.displayTitle(title, ranges: match.titleRanges)
        #expect(mapped.text == "Swift and swiftui")
        #expect(highlighted(mapped) == ["Swift"], "only the first hit is a model range; the collapsed text keeps it in place")
    }

    @Test func fuzzyHitsHighlightTheMatchedCharacters() {
        let title = "struct ContentView: View { .swiftUI }"
        let match = HistorySearch.match(query: "swft", title: title, searchText: title)!
        #expect(match.score >= 5, "a fuzzy hit, not a substring")
        let mapped = HighlightedText.displayTitle(title, ranges: match.titleRanges)
        #expect(highlighted(mapped).joined() == "swft")
    }

    @Test func hitsOnLaterLinesMapToNothingOnTheFirstLine() {
        let title = "Agenda\nbring the roadmap\nand the numbers"
        let match = HistorySearch.match(query: "roadmap", title: title, searchText: title)!
        #expect(!match.titleRanges.isEmpty)
        let mapped = HighlightedText.displayTitle(title, ranges: match.titleRanges)
        #expect(mapped.text == "Agenda")
        #expect(mapped.ranges.isEmpty, "the card then says “Matches content” instead of showing nothing")
    }

    @Test func codeHighlightsFollowTabExpansion() {
        let title = "\tlet x = 1\n\treturn x"
        let match = HistorySearch.match(query: "return", title: title, searchText: title)!
        let mapped = HighlightedText.codeLines(title, ranges: match.titleRanges)
        #expect(mapped.text == "    let x = 1\n    return x")
        #expect(highlighted(mapped) == ["return"])
    }

    @Test func substringDisplayCarriesRangesAndFallsBackWhenAbsent() {
        let title = "https://www.example.com/docs/Swift"
        let match = HistorySearch.match(query: "example", title: title, searchText: title)!
        let host = HighlightedText.substring("example.com", of: title, ranges: match.titleRanges)
        #expect(host.map(highlighted) == ["example"])
        #expect(HighlightedText.substring("#FF6B35", of: "#ff6b35", ranges: []) == nil)
        #expect(highlighted(.init(text: "#FF6B35", ranges: HighlightedText.queryRanges(in: "#FF6B35", query: "ff6b"))) == ["FF6B"])
    }

    // MARK: File cards (F18)

    @Test func fileTypeDescriptionComesFromTheExtensionAlone() {
        #expect(FileCaption.typeDescription(for: URL(fileURLWithPath: "/nowhere/at/all/report.pdf")) == "PDF document")
        #expect(FileCaption.typeDescription(for: URL(fileURLWithPath: "/nowhere/at/all/folder", isDirectory: true)) == UTType.folder.localizedDescription)
        #expect(FileCaption.typeDescription(for: URL(fileURLWithPath: "/nowhere/at/all/README")) == nil)
        #expect(FileCaption.typeDescription(for: URL(fileURLWithPath: "/nowhere/at/all/data.zzqx")) == "ZZQX")
        #expect(FileCaption.contentType(for: URL(fileURLWithPath: "/nowhere/Xcode.app", isDirectory: true)) == .applicationBundle)
        #expect(FileCaption.contentType(for: URL(fileURLWithPath: "/nowhere/Xcode.app", isDirectory: false)).conforms(to: .application))
        #expect(FileCaption.typeDescription(for: URL(fileURLWithPath: "/nowhere/odd.zzqx", isDirectory: true)) == UTType.folder.localizedDescription)
    }

    @Test func fileDetailUsesTheGivenDescriptionOnlyForSingleFiles() {
        let one = row("report.pdf", kind: .file, files: [URL(fileURLWithPath: "/Volumes/gone/report.pdf")])
        #expect(FileCaption.detail(for: one, typeDescription: "PDF document") == "/Volumes/gone · PDF document")
        #expect(FileCaption.detail(for: one, typeDescription: nil) == "/Volumes/gone")
        let two = row("a.pdf\nb.pdf", kind: .file, files: [URL(fileURLWithPath: "/Volumes/gone/a.pdf"), URL(fileURLWithPath: "/Volumes/gone/b.pdf")])
        #expect(FileCaption.detail(for: two, typeDescription: "PDF document") == "/Volumes/gone")
    }

    @Test @MainActor func fileIconCacheServesTypeIconsWithoutResolvingThePath() async {
        let cache = AppIconCache()
        let url = URL(fileURLWithPath: "/nowhere/at/all/report.pdf")
        #expect(cache.cachedFileIcon(path: url.path) == nil)
        #expect(cache.typeIcon(for: url).size.width > 0)
        #expect(cache.typeDescription(for: url) == "PDF document")
        let icon = await cache.fileIcon(path: url.path)
        #expect(cache.cachedFileIcon(path: url.path) === icon)
    }

    // MARK: Text previews (F17) and file previews (F34)

    @Test func preparedTextExpandsTabsTruncatesAndCapsHeight() {
        let short = TextPreview.prepare(text: "a\tb", monospaced: false, width: 500)
        #expect(short.shown == "a    b")
        #expect(!short.truncated)
        #expect(short.height > 0 && short.height <= PanelMetrics.previewMaxHeight)

        let long = TextPreview.prepare(text: String(repeating: "x\n", count: 20_000), monospaced: true, width: 500)
        #expect(long.truncated)
        #expect(long.shown.count == SelectableTextView.maxCharacters + 1)
        #expect(long.shown.hasSuffix("…"))
        #expect(long.height == PanelMetrics.previewMaxHeight - 18)

        let utf8 = TextPreview.prepare(.utf8(Data("héllo".utf8)), monospaced: false, width: 500)
        #expect(utf8.shown == "héllo")
    }

    @Test func placeholderAndFileListHeightsStayUnderTheCap() {
        #expect(TextPreview.placeholderHeight(lineCount: 1, monospaced: false) == 20)
        #expect(TextPreview.placeholderHeight(lineCount: 500, monospaced: true) == PanelMetrics.previewMaxHeight)
        #expect(FilePreview.height(forMeasured: nil, count: 1) == 15)
        #expect(FilePreview.height(forMeasured: nil, count: 3) == 51)
        #expect(FilePreview.height(forMeasured: nil, count: 40) == FilePreview.listMaxHeight)
        #expect(FilePreview.height(forMeasured: 900, count: 40) == FilePreview.listMaxHeight)
        #expect(FilePreview.listMaxHeight + 26 + 8 <= PanelMetrics.previewMaxHeight)
    }

    // MARK: Clear confirmation (F33, F36)

    @Test func clearConfirmationCountsTheVaultAndPluralises() {
        #expect(ClearConfirmation.removedCount(count: 0, pinnedCount: 2, sensitiveCount: 0, includePinned: false) == 0)
        #expect(ClearConfirmation.removedCount(count: 0, pinnedCount: 2, sensitiveCount: 2, includePinned: false) == 2)
        #expect(ClearConfirmation.removedCount(count: 3, pinnedCount: 2, sensitiveCount: 1, includePinned: true) == 6)

        #expect(ClearConfirmation.message(count: 0, pinnedCount: 0, sensitiveCount: 1, includePinned: false) == "1 clip will be removed. This can't be undone.")
        #expect(ClearConfirmation.message(count: 2, pinnedCount: 1, sensitiveCount: 1, includePinned: false) == "3 clips will be removed. Pinned clips are kept.")
        #expect(ClearConfirmation.message(count: 1, pinnedCount: 1, sensitiveCount: 0, includePinned: true) == "1 clip and 1 pinned clip will be removed. This can't be undone.")
        #expect(ClearConfirmation.message(count: 4, pinnedCount: 2, sensitiveCount: 0, includePinned: true) == "4 clips and 2 pinned clips will be removed. This can't be undone.")
    }

    @Test func inflectedStringsAgreeWithTheirCount() {
        #expect(String(inflected: "^[\(1) clip](inflect: true)") == "1 clip")
        #expect(String(inflected: "^[\(0) clip](inflect: true)") == "0 clips")
        #expect(SettingsSupport.storageSummary(bytes: 0, count: 2, pinned: 1) == "0 bytes · 2 clips · 1 pinned")
    }
}

@Suite("Search focus request", .serialized)
@MainActor
struct SearchFocusRequestTests {
    @Test func requestBumpsTheCounterTheViewObserves() {
        let harness = PanelHarness()
        let before = harness.model.focusSearchRequest
        harness.model.requestSearchFocus()
        harness.model.requestSearchFocus()
        #expect(harness.model.focusSearchRequest == before + 2)
    }
}
