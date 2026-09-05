import Foundation
import Testing
@testable import Nori

/// The derived strings a card shows, computed from `ClipRow`.
@Suite("ClipRow")
struct ClipRowTests {
    private func row(_ title: String, kind: ClipKind = .text, link: String? = nil, source: ClipRow.Source = .history) -> ClipRow {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return ClipRow(
            id: UUID(), source: source, kind: kind, title: title, searchText: title, sourceBundleID: nil,
            sourceAppName: nil, isFromUniversalClipboard: false, firstCopiedAt: now, lastCopiedAt: now,
            copyCount: 1, pinnedAt: nil, byteCount: title.utf8.count, characterCount: title.count, lineCount: 1,
            isRichText: false, isTruncated: false, linkURL: link.flatMap(URL.init(string:)), colorHex: nil,
            fileURLs: [], imagePixelSize: nil, thumbnail: nil, expiresAt: nil, ghostReason: nil
        )
    }

    // MARK: displayTitle

    @Test func displayTitleTakesTheFirstLineAndCollapsesWhitespace() {
        #expect(row("Meeting   notes\t\tfor   today\nsecond line").displayTitle == "Meeting notes for today")
        #expect(row("  leading and trailing  ").displayTitle == "leading and trailing")
        #expect(row("one\r\ntwo").displayTitle == "one")
        #expect(row("single").displayTitle == "single")
        #expect(row("a\u{2028}b").displayTitle == "a", "Unicode line separators count as newlines")
    }

    @Test func displayTitleSkipsLeadingBlankLines() {
        // Titles are trimmed at capture time, but a pathological leading newline is still skipped.
        #expect(row("\nsecond").displayTitle == "second")
        #expect(row("\n\n  third  \nx").displayTitle == "third")
        #expect(row("").displayTitle == "")
    }

    // MARK: codeLines

    @Test func codeLinesExpandTabsAndSkipLeadingBlankLines() {
        let source = "\n   \n\tif x {\n\t\treturn\n\t}\n"
        #expect(row(source, kind: .code).codeLines == ["    if x {", "        return"])
    }

    @Test func codeLinesKeepLeadingSpacesAndStopAtTwo() {
        #expect(row("  indented\nsecond\nthird", kind: .code).codeLines == ["  indented", "second"])
        #expect(row("only", kind: .code).codeLines == ["only"])
        #expect(row("first\n", kind: .code).codeLines == ["first", ""], "a trailing newline yields an empty second line")
    }

    @Test func codeLinesOfBlankTextAreTheOriginalLines() {
        #expect(row("", kind: .code).codeLines == [""])
        #expect(row("  \n\t", kind: .code).codeLines == ["  ", "    "], "nothing to skip to, so the first two lines are returned")
    }

    // MARK: links

    @Test func linkHostStripsWWWOnly() {
        #expect(row("x", kind: .link, link: "https://www.apple.com/design/").linkHost == "apple.com")
        #expect(row("x", kind: .link, link: "https://developer.apple.com/").linkHost == "developer.apple.com")
        #expect(row("x", kind: .link, link: "https://www2.example.org/").linkHost == "www2.example.org", "only the literal www. prefix goes")
        #expect(row("x", kind: .link, link: "mailto:someone@example.com").linkHost == nil)
        #expect(row("plain").linkHost == nil)
    }

    @Test func linkPathAndQueryIsNilForTheRoot() {
        #expect(row("x", kind: .link, link: "https://apple.com").linkPathAndQuery == nil)
        #expect(row("x", kind: .link, link: "https://apple.com/").linkPathAndQuery == nil)
        #expect(row("x", kind: .link, link: "https://apple.com/?").linkPathAndQuery == nil, "an empty query is ignored")
        #expect(row("plain").linkPathAndQuery == nil)
    }

    @Test func linkPathAndQueryKeepsPathAndQueryDecoded() {
        #expect(row("x", kind: .link, link: "https://developer.apple.com/design/human-interface-guidelines/liquid-glass").linkPathAndQuery
                == "/design/human-interface-guidelines/liquid-glass")
        #expect(row("x", kind: .link, link: "https://example.com/search?q=swift%20data&page=2").linkPathAndQuery == "/search?q=swift data&page=2")
        #expect(row("x", kind: .link, link: "https://example.com/?q=1").linkPathAndQuery == "/?q=1", "a root with a query is not the root")
        #expect(row("x", kind: .link, link: "https://example.com/a%2Fb").linkPathAndQuery == "/a/b")
        #expect(row("x", kind: .link, link: "https://example.com/docs#section").linkPathAndQuery == "/docs", "fragments are not shown")
    }

    // MARK: flags

    @Test func sourceFlags() {
        #expect(row("x").isPinned == false)
        #expect(row("x", source: .sensitive).isSensitive)
        #expect(!row("x", source: .sensitive).isGhost)
        let ghost = ClipRow.ghost(reason: "Concealed item from 1Password wasn't saved", at: .now)
        #expect(ghost.isGhost)
        #expect(ghost.ghostReason == ghost.title)
        #expect(ghost.kind == .text)
        #expect(ghost.searchText.isEmpty)
        #expect(ghost.copyCount == 0)
        #expect(ClipRow.ghost(reason: "a", at: .now).id != ClipRow.ghost(reason: "a", at: .now).id)
    }
}
