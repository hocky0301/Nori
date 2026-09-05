import Foundation

/// A fully-classified, storage-independent description of one clipboard capture.
///
/// `ClipDraft` is a plain value: it can be built from a `PasteboardSnapshot` on any
/// thread, compared in tests, and only turned into a SwiftData `ClipItem` when the
/// history store decides to keep it.
struct ClipDraft: Sendable, Equatable {
    struct Content: Sendable, Equatable {
        let type: String
        let data: Data
    }

    var kind: ClipKind
    /// Short preview shown in the list (whitespace-trimmed, at most `ClipDraft.maxTitleLength` characters).
    var title: String
    /// Text used by search (at most `ClipDraft.maxSearchTextLength` characters). Empty for images until OCR runs.
    var searchText: String
    /// Every pasteboard representation worth restoring later, in pasteboard order.
    var contents: [Content]
    /// Bundle identifier of the app that was frontmost when the copy happened.
    var sourceBundleID: String?
    /// SHA-256 over the stable representations; identical hashes mean "the same copy".
    var contentHash: String
    /// Whether the copy came through Universal Clipboard from another device.
    var isFromUniversalClipboard: Bool

    // Kind-specific denormalised metadata used by cards and previews.
    var linkURL: URL?
    var colorHex: String?
    var fileURLs: [URL]
    var imagePixelSize: CGSize?
    var characterCount: Int
    var lineCount: Int

    static let maxTitleLength = 1_000
    static let maxSearchTextLength = 10_000

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
}
