import Foundation
import SwiftUI
import Testing
@testable import Nori

@Suite("Panel UI helpers")
struct PanelUIHelperTests {
    @Test func colorValueParsesHexAndFormats() {
        let value = ColorValue(hex: "#FF6B35")
        #expect(value?.hexString == "#FF6B35")
        #expect(value?.rgbString == "rgb(255, 107, 53)")
        #expect(value?.hslString == "hsl(16, 100%, 60%)")
        #expect(value?.hasAlpha == false)

        let translucent = ColorValue(hex: "#00FF0080")
        #expect(translucent?.hasAlpha == true)
        #expect(translucent?.rgbString == "rgba(0, 255, 0, 0.50)")
        #expect(translucent?.hslString == "hsla(120, 100%, 50%, 0.50)")

        #expect(ColorValue(hex: "#ABC")?.hexString == "#AABBCC")
        #expect(ColorValue(hex: "nope") == nil)
    }

    @Test func homeRelativePaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(FileCaption.homeRelative(home.appending(path: "Downloads")) == "~/Downloads")
        #expect(FileCaption.homeRelative(home) == "~")
        #expect(FileCaption.homeRelative(URL(fileURLWithPath: "/Applications")) == "/Applications")
    }

    @Test func highlightTintsEveryMatchedRun() {
        let attributed = HighlightedText.attributed("Swift and swiftui", query: "swift", highlight: .red)
        let tinted = attributed.runs.filter { $0.backgroundColor != nil }
        #expect(tinted.count == 2)
        #expect(tinted.map { String(attributed[$0.range].characters) } == ["Swift", "swift"])
        let untouched = HighlightedText.attributed("plain", query: "", highlight: .red)
        #expect(untouched.runs.allSatisfy { $0.backgroundColor == nil })
    }

    @Test @MainActor func pauseCountdownAndExpiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SearchRow.countdown(until: now.addingTimeInterval(28 * 60 + 12), now: now) == "28:12")
        #expect(SearchRow.countdown(until: now.addingTimeInterval(-5), now: now) == "00:00")
        #expect(PanelModel.expiresText(now.addingTimeInterval(8 * 60), now: now) == "Expires in 8m")
        #expect(PanelModel.expiresText(now.addingTimeInterval(30), now: now) == "Expires in <1m")
    }

    @Test @MainActor func metaStripText() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let row = ClipRow(id: UUID(), source: .history, kind: .text, title: "x", searchText: "x", sourceBundleID: nil,
                          sourceAppName: "Safari", isFromUniversalClipboard: false, firstCopiedAt: first,
                          lastCopiedAt: first.addingTimeInterval(3600), copyCount: 3, pinnedAt: nil, byteCount: 1,
                          characterCount: 1, lineCount: 1, isRichText: false, isTruncated: false, linkURL: nil,
                          colorHex: nil, fileURLs: [], imagePixelSize: nil, thumbnail: nil, expiresAt: nil, ghostReason: nil)
        let text = ExpandedPreview.metaText(for: row)
        #expect(text.hasPrefix("Safari · first copied "))
        #expect(text.hasSuffix(" · copied 3×"))
        #expect(text.contains(" · last "))
    }
}
