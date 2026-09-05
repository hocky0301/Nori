import Foundation
import SwiftData

/// One entry in the clipboard history, persisted with SwiftData.
///
/// Large payloads live in `ClipContent` rows (external storage), so listing and
/// searching the history never has to load image bytes.
@Model
final class ClipItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var searchText: String
    var contentHash: String
    var sourceBundleID: String?
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var copyCount: Int
    /// Non-nil when pinned. Pinned items are ordered by this date.
    var pinnedAt: Date?
    var byteCount: Int
    var characterCount: Int
    var lineCount: Int
    var isFromUniversalClipboard: Bool

    var linkURLString: String?
    var colorHex: String?
    var fileURLStrings: [String]
    var imageWidth: Int?
    var imageHeight: Int?

    @Relationship(deleteRule: .cascade, inverse: \ClipContent.item)
    var contents: [ClipContent]

    init(draft: ClipDraft, now: Date = .now) {
        id = UUID()
        kindRaw = draft.kind.rawValue
        title = draft.title
        searchText = draft.searchText
        contentHash = draft.contentHash
        sourceBundleID = draft.sourceBundleID
        firstCopiedAt = now
        lastCopiedAt = now
        copyCount = 1
        pinnedAt = nil
        byteCount = draft.byteCount
        characterCount = draft.characterCount
        lineCount = draft.lineCount
        isFromUniversalClipboard = draft.isFromUniversalClipboard
        linkURLString = draft.linkURL?.absoluteString
        colorHex = draft.colorHex
        fileURLStrings = draft.fileURLs.map(\.absoluteString)
        if let size = draft.imagePixelSize {
            imageWidth = Int(size.width)
            imageHeight = Int(size.height)
        }
        // Relationships are attached after the item is inserted into a context (see HistoryStore.ingest);
        // wiring them up in init trips a SwiftData assertion.
        contents = []
    }

    var kind: ClipKind {
        get { ClipKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var isPinned: Bool { pinnedAt != nil }

    var linkURL: URL? { linkURLString.flatMap(URL.init(string:)) }

    var fileURLs: [URL] { fileURLStrings.compactMap(URL.init(string:)) }

    var imagePixelSize: CGSize? {
        guard let imageWidth, let imageHeight else { return nil }
        return CGSize(width: imageWidth, height: imageHeight)
    }

    func data(for type: String) -> Data? {
        contents.first(where: { $0.type == type })?.data
    }

    func data(forAny types: [String]) -> Data? {
        for type in types {
            if let data = data(for: type) { return data }
        }
        return nil
    }

    /// Best plain-text representation, used for "paste as plain text" and previews.
    var plainText: String? {
        if let data = data(for: PasteboardType.utf8PlainText), let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let data = data(for: PasteboardType.rtf),
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributed.string
        }
        if let data = data(for: PasteboardType.html),
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }

    var imageData: Data? { data(forAny: PasteboardType.imageTypes) }
}

@Model
final class ClipContent {
    var type: String
    @Attribute(.externalStorage) var data: Data
    var item: ClipItem?

    init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}
