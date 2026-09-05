import Foundation

/// Everything a card needs, as a Sendable value. Built by `HistoryStore` from `ClipItem`,
/// by `SensitiveVault` for masked secrets, and by the panel for ghost rows.
struct ClipRow: Identifiable, Hashable, Sendable {
    enum Source: Sendable { case history, sensitive, ghost }

    let id: UUID
    let source: Source
    let kind: ClipKind
    let title: String
    let searchText: String
    let sourceBundleID: String?
    let sourceAppName: String?
    let isFromUniversalClipboard: Bool
    let firstCopiedAt: Date
    let lastCopiedAt: Date
    let copyCount: Int
    let pinnedAt: Date?
    let byteCount: Int
    let characterCount: Int
    let lineCount: Int
    let isRichText: Bool
    let isTruncated: Bool
    let linkURL: URL?
    let colorHex: String?
    let fileURLs: [URL]
    let imagePixelSize: CGSize?
    let thumbnail: Data?
    /// Sensitive rows only: when the in-memory copy disappears.
    let expiresAt: Date?
    /// Ghost rows only: the human-readable reason nothing was saved.
    let ghostReason: String?

    var isPinned: Bool { pinnedAt != nil }
    var isSensitive: Bool { source == .sensitive }
    var isGhost: Bool { source == .ghost }

    /// First non-empty line with runs of whitespace collapsed — what the card's title line shows.
    var displayTitle: String {
        let firstLine = title.split(whereSeparator: \.isNewline).first.map(String.init) ?? title
        return firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The first two lines, leading whitespace preserved (code cards).
    var codeLines: [String] {
        let expanded = title.replacingOccurrences(of: "\t", with: "    ")
        let lines = expanded.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let firstNonEmpty = lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? 0
        return Array(lines[firstNonEmpty...].prefix(2))
    }

    var linkHost: String? {
        guard let host = linkURL?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Path + query of a link, or nil when it is just the root.
    var linkPathAndQuery: String? {
        guard let url = linkURL else { return nil }
        var path = url.path(percentEncoded: false)
        if let query = url.query(percentEncoded: false), !query.isEmpty { path += "?" + query }
        return path == "/" || path.isEmpty ? nil : path
    }

    static func ghost(reason: String, at date: Date) -> ClipRow {
        ClipRow(
            id: UUID(), source: .ghost, kind: .text, title: reason, searchText: "", sourceBundleID: nil,
            sourceAppName: nil, isFromUniversalClipboard: false, firstCopiedAt: date, lastCopiedAt: date,
            copyCount: 0, pinnedAt: nil, byteCount: 0, characterCount: 0, lineCount: 0, isRichText: false,
            isTruncated: false, linkURL: nil, colorHex: nil, fileURLs: [], imagePixelSize: nil, thumbnail: nil,
            expiresAt: nil, ghostReason: reason
        )
    }
}
