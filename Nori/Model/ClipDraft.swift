import Foundation

/// A fully-classified, storage-independent description of one clipboard capture.
///
/// `ClipDraft` is a plain value: it is built off the main thread from a `PasteboardSnapshot`,
/// compared in tests, and only turned into a SwiftData `ClipItem` when the history store
/// decides to keep it.
struct ClipDraft: Sendable, Equatable {
    struct Content: Sendable, Equatable {
        let type: String
        let data: Data
    }

    var kind: ClipKind
    /// Preview text (whitespace-trimmed, at most `ClipDraft.maxTitleLength` characters).
    var title: String
    /// Text used by search (at most `ClipDraft.maxSearchTextLength` characters).
    var searchText: String
    /// Every pasteboard representation worth restoring later, in pasteboard order.
    var contents: [Content]
    /// Bundle identifier / localized name of the app that was frontmost when the copy happened.
    var sourceBundleID: String?
    var sourceAppName: String?
    /// SHA-256 over the stable representations; identical hashes mean "the same copy".
    var contentHash: String
    /// Whether the copy came through Universal Clipboard from another device.
    var isFromUniversalClipboard: Bool
    /// RTF with real formatting (more than one attribute run) was present.
    var isRichText: Bool
    /// Plain text was cut at the size cap.
    var isTruncated: Bool

    // Kind-specific denormalised metadata used by cards and previews.
    var linkURL: URL?
    var colorHex: String?
    var fileURLs: [URL]
    var imagePixelSize: CGSize?
    /// Small PNG (≤ 224 px on the long side) for image cards; nil for other kinds.
    var thumbnail: Data?
    var characterCount: Int
    var lineCount: Int

    static let maxTitleLength = 1_000
    static let maxSearchTextLength = 10_000

    init(kind: ClipKind = .text, contents: [Content], contentHash: String, isFromUniversalClipboard: Bool = false) {
        self.kind = kind
        self.title = ""
        self.searchText = ""
        self.contents = contents
        self.contentHash = contentHash
        self.isFromUniversalClipboard = isFromUniversalClipboard
        self.isRichText = false
        self.isTruncated = false
        self.fileURLs = []
        self.characterCount = 0
        self.lineCount = 0
    }

    var byteCount: Int { contents.reduce(0) { $0 + $1.data.count } }

    func data(for type: String) -> Data? {
        contents.first(where: { $0.type == type })?.data
    }

    func data(forAny types: [String]) -> Data? {
        for type in types {
            if let data = data(for: type) { return data }
        }
        return nil
    }

    var plainText: String? {
        data(for: PasteboardType.utf8PlainText).flatMap { String(data: $0, encoding: .utf8) }
    }
}
