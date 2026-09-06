import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The 28×28 leading well: 12 % tint fill + the kind's symbol at 100 %.
struct CardWell: View {
    let symbol: String
    let tint: Color

    @Environment(\.panelTheme) private var theme

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: PanelMetrics.wellSize, height: PanelMetrics.wellSize)
            .background(tint.opacity(theme.wellTintOpacity), in: RoundedRectangle(cornerRadius: PanelMetrics.Radius.well, style: .continuous))
    }
}

/// Per-kind card anatomy (§3.3): well + title block, from a `ClipRow` value.
struct CardContent: View {
    let row: ClipRow
    /// Matched runs in `row.title` for the current query (from the model, never re-searched here).
    let titleRanges: [Range<String.Index>]
    let query: String

    init(row: ClipRow, titleRanges: [Range<String.Index>] = [], query: String = "") {
        self.row = row
        self.titleRanges = titleRanges
        self.query = query
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The row matched only through its full text (a later line, OCR text, host or app name) —
    /// nothing on the card lights up, so say why it is listed.
    private var matchesContentOnly: Bool {
        isSearching && !row.isSensitive && row.kind != .image
            && primaryMatch.ranges.isEmpty && (secondaryMatch?.ranges.isEmpty ?? true)
    }

    /// The card's first line with the model's matched runs mapped onto it.
    private var primaryMatch: HighlightedText.Mapped {
        switch row.kind {
        case .text: HighlightedText.displayTitle(row.title, ranges: titleRanges)
        case .code: HighlightedText.codeLines(row.title, ranges: titleRanges)
        case .link: mapped(row.linkHost ?? row.displayTitle)
        case .color: mapped(row.colorHex.flatMap(ColorValue.init(hex:))?.hexString ?? row.displayTitle)
        case .image: HighlightedText.Mapped(text: ImageCaption.text(for: row), ranges: [])
        case .file: mapped(FileCaption.name(for: row))
        }
    }

    /// The link's path line, when there is one.
    private var secondaryMatch: HighlightedText.Mapped? {
        guard row.kind == .link, let path = row.linkPathAndQuery else { return nil }
        return mapped(path)
    }

    /// `display` with the model's ranges when it occurs inside the title; otherwise (a normalized
    /// color, a decoded link path) a substring search over the displayed text.
    private func mapped(_ display: String) -> HighlightedText.Mapped {
        guard isSearching else { return HighlightedText.Mapped(text: display, ranges: []) }
        if let mapped = HighlightedText.substring(display, of: row.title, ranges: titleRanges) {
            return mapped
        }
        return HighlightedText.Mapped(text: display, ranges: HighlightedText.queryRanges(in: display, query: query))
    }

    var body: some View {
        HStack(alignment: .center, spacing: PanelMetrics.wellGap) {
            well
            VStack(alignment: .leading, spacing: 2) {
                titleBlock
                if matchesContentOnly, row.kind != .text {
                    contentMatchCaption
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contentMatchCaption: some View {
        Text("Matches content")
            .font(.cardSecondary)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    // MARK: Well

    @ViewBuilder
    private var well: some View {
        if row.isSensitive {
            CardWell(symbol: "lock.shield", tint: .red)
        } else {
            switch row.kind {
            case .text:
                CardWell(symbol: "text.alignleft", tint: .secondary)
            case .link:
                CardWell(symbol: "link", tint: .blue)
            case .code:
                CardWell(symbol: "chevron.left.forwardslash.chevron.right", tint: .indigo)
            case .color:
                if let value = row.colorHex.flatMap(ColorValue.init(hex:)) {
                    ColorSwatch(value: value, size: PanelMetrics.wellSize, radius: PanelMetrics.Radius.well)
                } else {
                    CardWell(symbol: "paintpalette", tint: .orange)
                }
            case .image:
                ImageThumbnail(data: row.thumbnail)
            case .file:
                FileWell(urls: row.fileURLs)
            }
        }
    }

    // MARK: Title block

    @ViewBuilder
    private var titleBlock: some View {
        if row.isSensitive {
            sensitiveTitle
        } else {
            switch row.kind {
            case .text: textTitle
            case .link: linkTitle
            case .code: codeTitle
            case .color: colorTitle
            case .image: imageTitle
            case .file: fileTitle
            }
        }
    }

    private var textCaption: String? {
        var parts: [String] = []
        if row.lineCount > 1 { parts.append(String(localized: "\(row.lineCount) lines")) }
        if row.lineCount > 1 || row.isRichText { parts.append(String(localized: "\(row.characterCount.formatted()) chars")) }
        if row.isRichText { parts.append(String(localized: "Rich text")) }
        if row.isTruncated { parts.append(String(localized: "Truncated")) }
        if matchesContentOnly { parts.append(String(localized: "Matches content")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var textTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            MatchText(primaryMatch)
                .font(.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(textCaption == nil ? 2 : 1)
                .truncationMode(.tail)
            if let caption = textCaption {
                Text(caption)
                    .font(.cardSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var linkTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            MatchText(primaryMatch)
                .font(.linkHost)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let secondaryMatch {
                MatchText(secondaryMatch)
                    .font(.cardSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var codeTitle: some View {
        MatchText(primaryMatch)
            .font(.code)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var colorTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            let value = row.colorHex.flatMap(ColorValue.init(hex:))
            MatchText(primaryMatch)
                .font(.colorHex)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let value {
                Text(value.rgbString)
                    .font(.cardSecondary)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var imageTitle: some View {
        Text(ImageCaption.text(for: row))
            .font(.cardTitle)
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var fileTitle: some View {
        let typeDescription = row.fileURLs.first.flatMap { AppIconCache.shared.typeDescription(for: $0) }
        return VStack(alignment: .leading, spacing: 2) {
            MatchText(primaryMatch)
                .font(.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail = FileCaption.detail(for: row, typeDescription: typeDescription) {
                Text(detail)
                    .font(.cardSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var sensitiveTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.title)
                .font(.colorHex)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let expiresAt = row.expiresAt {
                Text(verbatim: "· \(PanelModel.expiresText(expiresAt))")
                    .font(.cardSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// 56×56 aspect-fill thumbnail with a hairline; `photo` fallback when the thumbnail is missing.
struct ImageThumbnail: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                CardWell(symbol: "photo", tint: .teal)
                    .frame(width: PanelMetrics.thumbSize, height: PanelMetrics.thumbSize)
            }
        }
        .frame(width: PanelMetrics.thumbSize, height: PanelMetrics.thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.Radius.thumb, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PanelMetrics.Radius.thumb, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }
}

/// The real Finder icon; 2+ files show the first icon with a "+n" badge.
///
/// Rendering never stats the path: a cached icon is used when there is one, otherwise the type's
/// generic icon shows while the Finder icon is resolved in the background.
struct FileWell: View {
    let urls: [URL]

    @State private var resolvedIcon: NSImage?

    private var path: String? { urls.first?.path(percentEncoded: false) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let first = urls.first, let path {
                Image(nsImage: resolvedIcon ?? AppIconCache.shared.cachedFileIcon(path: path) ?? AppIconCache.shared.typeIcon(for: first))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: PanelMetrics.wellSize, height: PanelMetrics.wellSize)
            } else {
                CardWell(symbol: "doc", tint: .secondary)
            }
            if urls.count > 1 {
                Text(verbatim: "+\(urls.count - 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(height: 12)
                    .background(Color.secondary, in: Capsule())
                    .offset(x: 4, y: 3)
            }
        }
        .frame(width: PanelMetrics.wellSize, height: PanelMetrics.wellSize)
        .task(id: path) {
            guard let path else { return }
            let icon = await AppIconCache.shared.fileIcon(path: path)
            if !Task.isCancelled { resolvedIcon = icon }
        }
    }
}

enum ImageCaption {
    /// "1440 × 900 · PNG · 412 KB"
    static func text(for row: ClipRow) -> String {
        var parts: [String] = []
        if let size = row.imagePixelSize {
            parts.append("\(Int(size.width)) × \(Int(size.height))")
        }
        parts.append("PNG")
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(row.byteCount), countStyle: .file))
        return parts.joined(separator: " · ")
    }
}

enum FileCaption {
    static func name(for row: ClipRow) -> String {
        if row.fileURLs.count > 1 { return String(localized: "\(row.fileURLs.count) files") }
        if let first = row.fileURLs.first { return first.lastPathComponent }
        return row.displayTitle
    }

    /// "~/Downloads · PDF document"
    static func detail(for row: ClipRow) -> String? {
        detail(for: row, typeDescription: row.fileURLs.first.flatMap(typeDescription(for:)))
    }

    /// `typeDescription` is the first file's type, looked up by the caller (cached in `AppIconCache`).
    static func detail(for row: ClipRow, typeDescription: String?) -> String? {
        guard let first = row.fileURLs.first else { return nil }
        var parts = [homeRelative(first.deletingLastPathComponent())]
        if row.fileURLs.count == 1, let description = typeDescription {
            parts.append(description)
        }
        return parts.joined(separator: " · ")
    }

    static func homeRelative(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == trimmedHome || path == trimmedHome + "/" { return "~" }
        if path.hasPrefix(trimmedHome + "/") { return "~" + path.dropFirst(trimmedHome.count) }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The type a path implies — from its extension (or trailing slash) only, so a card can be drawn
    /// while the volume the file lives on is unreachable.
    static func contentType(for url: URL) -> UTType {
        let ext = url.pathExtension
        if url.hasDirectoryPath {
            // A directory with a known package extension ("Xcode.app" → Application), else a folder.
            guard !ext.isEmpty, let package = UTType(filenameExtension: ext, conformingTo: .package), !package.isDynamic else {
                return .folder
            }
            return package
        }
        return ext.isEmpty ? .data : UTType(filenameExtension: ext) ?? .data
    }

    /// "PDF document", "Folder", or the bare extension for types the system has no name for.
    static func typeDescription(for url: URL) -> String? {
        let ext = url.pathExtension
        if ext.isEmpty, !url.hasDirectoryPath { return nil }
        return contentType(for: url).localizedDescription ?? ext.uppercased()
    }
}
