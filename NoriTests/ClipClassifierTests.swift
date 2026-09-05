import AppKit
import Foundation
import Testing
@testable import Nori

@Suite("ClipClassifier")
struct ClipClassifierTests {
    private func snapshot(
        _ items: [[(String, Data?)]],
        declared: Set<String>? = nil,
        app: String? = "com.apple.TextEdit",
        changeCount: Int = 1
    ) -> PasteboardSnapshot {
        let built = items.map { PasteboardSnapshot.Item(representations: $0.map { ($0.0, $0.1) }) }
        let declaredTypes = declared ?? Set(built.flatMap(\.types))
        return PasteboardSnapshot(changeCount: changeCount, declaredTypes: declaredTypes, items: built, sourceBundleID: app)
    }

    private func text(_ string: String) -> (String, Data?) {
        (PasteboardType.utf8PlainText, Data(string.utf8))
    }

    private func draft(_ outcome: CaptureOutcome) throws -> ClipDraft {
        guard case let .captured(draft) = outcome else {
            Issue.record("expected capture, got \(outcome)")
            throw CancellationError()
        }
        return draft
    }

    @Test func plainText() throws {
        let draft = try draft(ClipClassifier.classify(snapshot([[text("  Hello, Nori!\n")]])))
        #expect(draft.kind == .text)
        #expect(draft.title == "Hello, Nori!")
        #expect(draft.searchText == "  Hello, Nori!\n")
        #expect(draft.characterCount == 15)
        #expect(draft.lineCount == 2)
        #expect(draft.sourceBundleID == "com.apple.TextEdit")
        #expect(draft.contents.count == 1)
    }

    @Test func link() throws {
        let draft = try draft(ClipClassifier.classify(snapshot([[text("https://maccy.app/\n")]])))
        #expect(draft.kind == .link)
        #expect(draft.linkURL?.host() == "maccy.app")
    }

    @Test func color() throws {
        let draft = try draft(ClipClassifier.classify(snapshot([[text("#ff8800")]])))
        #expect(draft.kind == .color)
        #expect(draft.colorHex == "#FF8800")
    }

    @Test func code() throws {
        let source = "func hello() {\n    print(\"hi\")\n}\n"
        let draft = try draft(ClipClassifier.classify(snapshot([[text(source)]])))
        #expect(draft.kind == .code)
    }

    @Test func richTextWithFormatting() throws {
        let attributed = NSMutableAttributedString(string: "Bold and plain")
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: NSRange(location: 0, length: 4))
        let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let draft = try draft(ClipClassifier.classify(snapshot([[text("Bold and plain"), (PasteboardType.rtf, rtf)]])))
        #expect(draft.kind == .richText)
        #expect(draft.title == "Bold and plain")
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText, PasteboardType.rtf])
    }

    @Test func uniformRTFIsPlainText() throws {
        let attributed = NSAttributedString(string: "just text", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let draft = try draft(ClipClassifier.classify(snapshot([[text("just text"), (PasteboardType.rtf, rtf)]])))
        #expect(draft.kind == .text)
    }

    @Test func image() throws {
        let png = try #require(TestImages.png(width: 12, height: 7))
        let draft = try draft(ClipClassifier.classify(snapshot([[(PasteboardType.png, png), text("alt text")]])))
        #expect(draft.kind == .image)
        #expect(draft.imagePixelSize == CGSize(width: 12, height: 7))
        #expect(draft.title == "Image 12×7")
        #expect(draft.searchText == "alt text")
    }

    @Test func files() throws {
        let url = URL(fileURLWithPath: "/tmp/My File.txt")
        let other = URL(fileURLWithPath: "/tmp/other.pdf")
        let snap = snapshot([
            [(PasteboardType.fileURL, url.dataRepresentation), text("My File.txt")],
            [(PasteboardType.fileURL, other.dataRepresentation), text("other.pdf")],
        ])
        let draft = try draft(ClipClassifier.classify(snap))
        #expect(draft.kind == .file)
        #expect(draft.fileURLs.map(\.lastPathComponent) == ["My File.txt", "other.pdf"])
        #expect(draft.title == "My File.txt\nother.pdf")
        #expect(draft.lineCount == 2)
    }

    @Test func mergesMultipleItemsWithoutDuplicatingTypes() throws {
        let snap = snapshot([[text("one")], [text("two"), (PasteboardType.html, Data("<b>two</b>".utf8))]])
        let draft = try draft(ClipClassifier.classify(snap))
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText, PasteboardType.html])
        #expect(draft.title == "one")
    }

    @Test func whitespaceOnlyIsRejected() {
        #expect(ClipClassifier.classify(snapshot([[text("   \n\t")]])) == .rejected(.nothingToStore))
    }

    @Test func missingDataIsRejected() {
        #expect(ClipClassifier.classify(snapshot([[(PasteboardType.utf8PlainText, nil)]])) == .rejected(.nothingToStore))
    }

    @Test func concealedIsRejectedEvenWhenOnlyDeclared() {
        let snap = snapshot([[text("hunter2")]], declared: [PasteboardType.utf8PlainText, PasteboardType.concealed])
        #expect(ClipClassifier.classify(snap) == .rejected(.privateOrTransient(PasteboardType.concealed)))
    }

    @Test func transientAndAutoGeneratedAreRejected() {
        for type in [PasteboardType.transient, PasteboardType.autoGenerated] {
            let snap = snapshot([[text("x"), (type, Data())]])
            #expect(ClipClassifier.classify(snap) == .rejected(.privateOrTransient(type)))
        }
    }

    @Test func ignoredCustomTypes() {
        let snap = snapshot([[text("secret"), ("com.agilebits.onepassword", Data())]])
        #expect(ClipClassifier.classify(snap) == .rejected(.ignoredType("com.agilebits.onepassword")))
    }

    @Test func ignoredApps() {
        var policy = CapturePolicy()
        policy.ignoredApps = ["com.apple.keychainaccess"]
        let snap = snapshot([[text("pw")]], app: "com.apple.keychainaccess")
        #expect(ClipClassifier.classify(snap, policy: policy) == .rejected(.ignoredApp("com.apple.keychainaccess")))

        policy.recordOnlyListedApps = true
        #expect(ClipClassifier.classify(snapshot([[text("ok")]], app: "com.apple.keychainaccess"), policy: policy) != .rejected(.ignoredApp("com.apple.keychainaccess")))
        #expect(ClipClassifier.classify(snapshot([[text("no")]], app: "com.apple.Safari"), policy: policy) == .rejected(.ignoredApp("com.apple.Safari")))
    }

    @Test func ignoreRegexp() {
        var policy = CapturePolicy()
        policy.ignoreRegexps = ["^sk-[A-Za-z0-9]{10,}$"]
        #expect(ClipClassifier.classify(snapshot([[text("sk-abcdefghijklmnop")]]), policy: policy) == .rejected(.matchedIgnoreRegexp))
        #expect(ClipClassifier.classify(snapshot([[text("sk-short")]]), policy: policy) != .rejected(.matchedIgnoreRegexp))
    }

    @Test func fromNoriIsRejectedWithID() {
        let id = UUID()
        let snap = snapshot([[text("again"), (PasteboardType.noriItem, Data(id.uuidString.utf8))]])
        #expect(ClipClassifier.classify(snap) == .rejected(.fromNori(id)))
    }

    @Test func dropsDynamicAndMetadataTypes() throws {
        let snap = snapshot([[
            text("hello"),
            ("dyn.ah62d4rv4gu8y", Data([1])),
            ("com.microsoft.ole.source.abc", Data([2])),
            ("org.chromium.web-custom-data", Data([3])),
            ("com.apple.linkpresentation.metadata", Data([4])),
        ]])
        let draft = try draft(ClipClassifier.classify(snap))
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText])
    }

    @Test func stripsWordLinkTypes() throws {
        let snap = snapshot([[
            text("Heading 1"),
            ("com.microsoft.ObjectLink", Data([1])),
            ("com.microsoft.Link-Source", Data([2])),
            (PasteboardType.pdf, Data([3])),
            (PasteboardType.rtf, Data("{\\rtf1 Heading 1}".utf8)),
        ]])
        let draft = try draft(ClipClassifier.classify(snap))
        #expect(!draft.contents.contains { $0.type == "com.microsoft.ObjectLink" || $0.type == PasteboardType.pdf })
        #expect(draft.contents.contains { $0.type == PasteboardType.rtf })
    }

    @Test func policyCanDisableImagesFilesAndRichText() throws {
        var policy = CapturePolicy()
        policy.captureImages = false
        policy.captureFiles = false
        policy.captureRichText = false
        let png = try #require(TestImages.png(width: 2, height: 2))
        let snap = snapshot([[(PasteboardType.png, png), (PasteboardType.rtf, Data([1])), text("caption")]])
        let draft = try draft(ClipClassifier.classify(snap, policy: policy))
        #expect(draft.kind == .text)
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText])
    }

    @Test func oversizedRepresentationsAreDropped() throws {
        var policy = CapturePolicy()
        policy.maxRepresentationBytes = 4
        let snap = snapshot([[text("tiny"), (PasteboardType.tiff, Data(repeating: 0, count: 10))]])
        let draft = try draft(ClipClassifier.classify(snap, policy: policy))
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText])
    }

    @Test func hashIgnoresCustomTypesButNotContent() {
        let a = [ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data("x".utf8)),
                 ClipDraft.Content(type: "com.example.custom", data: Data([9]))]
        let b = [ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data("x".utf8))]
        let c = [ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data("y".utf8))]
        #expect(ClipClassifier.contentHash(of: a) == ClipClassifier.contentHash(of: b))
        #expect(ClipClassifier.contentHash(of: a) != ClipClassifier.contentHash(of: c))
    }

    @Test func universalClipboardIsFlagged() throws {
        let snap = snapshot([[text("from iPhone")]], declared: [PasteboardType.utf8PlainText, PasteboardType.universalClipboard])
        let draft = try draft(ClipClassifier.classify(snap))
        #expect(draft.isFromUniversalClipboard)
    }

    @Test func longTextIsTruncatedForTitleAndSearch() throws {
        let long = String(repeating: "a", count: 20_000)
        let draft = try draft(ClipClassifier.classify(snapshot([[text(long)]])))
        #expect(draft.title.count == ClipDraft.maxTitleLength)
        #expect(draft.searchText.count == ClipDraft.maxSearchTextLength)
        #expect(draft.characterCount == 20_000)
    }
}
