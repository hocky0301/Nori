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
        appName: String? = "TextEdit",
        changeCount: Int = 1
    ) -> PasteboardSnapshot {
        let built = items.map { PasteboardSnapshot.Item(representations: $0.map { ($0.0, $0.1) }) }
        let declaredTypes = declared ?? Set(built.flatMap(\.types))
        return PasteboardSnapshot(changeCount: changeCount, declaredTypes: declaredTypes, items: built,
                                  sourceBundleID: app, sourceAppName: appName)
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
        #expect(draft.lineCount == 1)
        #expect(draft.sourceBundleID == "com.apple.TextEdit")
        #expect(draft.sourceAppName == "TextEdit")
        #expect(draft.contents.count == 1)
        #expect(!draft.isRichText)
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

    @Test func codeFromEditorNeedsLessEvidence() throws {
        let source = "let a = 1\nlet b = 2\n"
        #expect(try draft(ClipClassifier.classify(snapshot([[text(source)]], app: "com.apple.dt.Xcode"))).kind == .code)
        #expect(try draft(ClipClassifier.classify(snapshot([[text(source)]], app: "com.apple.Notes"))).kind == .text)
    }

    @Test func richTextIsAFlagOnText() throws {
        let attributed = NSMutableAttributedString(string: "Bold and plain")
        attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: NSRange(location: 0, length: 4))
        let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let draft = try draft(ClipClassifier.classify(snapshot([[text("Bold and plain"), (PasteboardType.rtf, rtf)]])))
        #expect(draft.kind == .text)
        #expect(draft.isRichText)
        #expect(draft.title == "Bold and plain")
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText, PasteboardType.rtf])
    }

    @Test func uniformRTFIsNotRich() throws {
        let attributed = NSAttributedString(string: "just text", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let draft = try draft(ClipClassifier.classify(snapshot([[text("just text"), (PasteboardType.rtf, rtf)]])))
        #expect(!draft.isRichText)
    }

    @Test func imageKeepsPNGOnlyAndThumbnail() throws {
        let png = try #require(TestImages.png(width: 300, height: 120))
        let tiff = try #require(NSImage(data: png)?.tiffRepresentation)
        let draft = try draft(ClipClassifier.classify(snapshot([[(PasteboardType.tiff, tiff), (PasteboardType.png, png), text("alt text")]])))
        #expect(draft.kind == .image)
        #expect(draft.imagePixelSize == CGSize(width: 300, height: 120))
        #expect(draft.title == "Image 300×120")
        #expect(draft.searchText == "alt text")
        #expect(draft.contents.map(\.type) == [PasteboardType.png, PasteboardType.utf8PlainText])
        let thumbnail = try #require(draft.thumbnail)
        let size = try #require(ImageNormalizer.pixelSize(of: thumbnail))
        #expect(size.width <= 224 && size.height <= 224)
    }

    @Test func tiffOnlyIsTranscodedToPNG() throws {
        let png = try #require(TestImages.png(width: 40, height: 30))
        let tiff = try #require(NSImage(data: png)?.tiffRepresentation)
        let draft = try draft(ClipClassifier.classify(snapshot([[(PasteboardType.tiff, tiff)]])))
        #expect(draft.contents.map(\.type) == [PasteboardType.png])
        #expect(draft.imagePixelSize == CGSize(width: 40, height: 30))
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

    @Test func concealedLeavesAGhostEvenWhenOnlyDeclared() {
        let snap = snapshot([[text("hunter2")]], declared: [PasteboardType.utf8PlainText, PasteboardType.concealed], appName: "1Password")
        #expect(ClipClassifier.classify(snap) == .ghost(.concealed(appName: "1Password")))
    }

    @Test func transientAndAutoGeneratedAreIgnored() {
        for type in [PasteboardType.transient, PasteboardType.autoGenerated] {
            let snap = snapshot([[text("x"), (type, Data())]])
            #expect(ClipClassifier.classify(snap) == .rejected(.ephemeral(type)))
        }
    }

    @Test func ignoredCustomTypes() {
        let snap = snapshot([[text("secret"), ("com.agilebits.onepassword", Data())]])
        #expect(ClipClassifier.classify(snap) == .rejected(.ignoredType("com.agilebits.onepassword")))
    }

    @Test func ignoredAppsIncludePasswordManagersByDefault() {
        let snap = snapshot([[text("pw")]], app: "com.apple.keychainaccess")
        #expect(ClipClassifier.classify(snap) == .rejected(.ignoredApp("com.apple.keychainaccess")))
    }

    @Test func ignoreRegexp() {
        var policy = CapturePolicy()
        policy.ignoreRegexps = ["^order-[0-9]{6}$"]
        #expect(ClipClassifier.classify(snapshot([[text("order-123456")]]), policy: policy) == .rejected(.matchedIgnoreRegexp))
        #expect(ClipClassifier.classify(snapshot([[text("order-12")]]), policy: policy) != .rejected(.matchedIgnoreRegexp))
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

    @Test func policyCanDisableImagesFilesAndText() throws {
        var policy = CapturePolicy()
        policy.captureImages = false
        policy.captureFiles = false
        let png = try #require(TestImages.png(width: 2, height: 2))
        let snap = snapshot([[(PasteboardType.png, png), (PasteboardType.rtf, Data([1])), text("caption")]])
        let draft = try draft(ClipClassifier.classify(snap, policy: policy))
        #expect(draft.kind == .text)
        #expect(draft.contents.map(\.type) == [PasteboardType.rtf, PasteboardType.utf8PlainText])

        policy.captureText = false
        #expect(ClipClassifier.classify(snapshot([[text("caption")]]), policy: policy) == .rejected(.nothingToStore))
    }

    @Test func oversizedImageLeavesAGhost() throws {
        var policy = CapturePolicy()
        policy.maxImageBytes = 4
        let png = try #require(TestImages.png(width: 2, height: 2))
        let outcome = ClipClassifier.classify(snapshot([[(PasteboardType.png, png), text("alt")]]), policy: policy)
        #expect(outcome == .ghost(.imageTooLarge(bytes: png.count)))
    }

    @Test func oversizedOtherRepresentationIsDroppedButClipKept() throws {
        var policy = CapturePolicy()
        policy.maxOtherRepresentationBytes = 4
        let snap = snapshot([[text("tiny"), ("com.apple.WebKit.custom-pasteboard-data", Data(repeating: 0, count: 10)), ("com.example.big", Data(repeating: 0, count: 10))]])
        let draft = try draft(ClipClassifier.classify(snap, policy: policy))
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText])
    }

    @Test func hugeTextIsTruncated() throws {
        var policy = CapturePolicy()
        policy.maxTextBytes = 16
        let snap = snapshot([[text(String(repeating: "a", count: 100)), (PasteboardType.rtf, Data([1]))]])
        let draft = try draft(ClipClassifier.classify(snap, policy: policy))
        #expect(draft.isTruncated)
        #expect(draft.characterCount == 16)
        #expect(draft.contents.map(\.type) == [PasteboardType.utf8PlainText])
    }

    @Test func secretsGoToTheVault() throws {
        let outcome = ClipClassifier.classify(snapshot([[text("AKIAIOSFODNN7EXAMPLE")]]))
        guard case let .sensitive(sensitive) = outcome else {
            Issue.record("expected sensitive, got \(outcome)")
            return
        }
        #expect(sensitive.match == .awsAccessKey)
        #expect(sensitive.mask.hasSuffix("MPLE"))
        #expect(!sensitive.mask.contains("AKIA"))

        var policy = CapturePolicy()
        policy.maskSensitive = false
        #expect(try draft(ClipClassifier.classify(snapshot([[text("AKIAIOSFODNN7EXAMPLE")]]), policy: policy)).kind == .text)
    }

    @Test func hashIgnoresCustomTypesButNotContent() {
        let a = [ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data("x".utf8)),
                 ClipDraft.Content(type: "com.example.custom", data: Data([9]))]
        let b = [ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data("x".utf8))]
        let c = [ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data("y".utf8))]
        #expect(ClipClassifier.contentHash(of: a) == ClipClassifier.contentHash(of: b))
        #expect(ClipClassifier.contentHash(of: a) != ClipClassifier.contentHash(of: c))
    }

    @Test func universalClipboardIsFlaggedAndCanBeDisabled() throws {
        let snap = snapshot([[text("from iPhone")]], declared: [PasteboardType.utf8PlainText, PasteboardType.universalClipboard])
        let draft = try draft(ClipClassifier.classify(snap))
        #expect(draft.isFromUniversalClipboard)
        #expect(draft.sourceAppName == "iPhone or iPad")
        var policy = CapturePolicy()
        policy.captureUniversalClipboard = false
        #expect(ClipClassifier.classify(snap, policy: policy) == .rejected(.universalClipboardDisabled))
    }

    @Test func longTextIsTruncatedForTitleAndSearch() throws {
        let long = String(repeating: "a", count: 20_000)
        let draft = try draft(ClipClassifier.classify(snapshot([[text(long)]])))
        #expect(draft.title.count == ClipDraft.maxTitleLength)
        #expect(draft.searchText.count == ClipDraft.maxSearchTextLength)
        #expect(draft.characterCount == 20_000)
    }
}
