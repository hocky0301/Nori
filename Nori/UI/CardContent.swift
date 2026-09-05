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
    let query: String

    var body: some View {
        HStack(alignment: .center, spacing: PanelMetrics.wellGap) {
            well
            titleBlock
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var textTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            MatchText(text: row.displayTitle, query: query)
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
            MatchText(text: row.linkHost ?? row.displayTitle, query: query)
                .font(.linkHost)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let path = row.linkPathAndQuery {
                MatchText(text: path, query: query)
                    .font(.cardSecondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var codeTitle: some View {
        MatchText(text: row.codeLines.joined(separator: "\n"), query: query)
            .font(.code)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var colorTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            let value = row.colorHex.flatMap(ColorValue.init(hex:))
            MatchText(text: value?.hexString ?? row.displayTitle, query: query)
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
        VStack(alignment: .leading, spacing: 2) {
            MatchText(text: FileCaption.name(for: row), query: query)
                .font(.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail = FileCaption.detail(for: row) {
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
struct FileWell: View {
    let urls: [URL]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let first = urls.first {
                Image(nsImage: AppIconCache.shared.fileIcon(path: first.path(percentEncoded: false)))
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
        guard let first = row.fileURLs.first else { return nil }
        var parts = [homeRelative(first.deletingLastPathComponent())]
        if row.fileURLs.count == 1, let description = typeDescription(for: first) {
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

    static func typeDescription(for url: URL) -> String? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.localizedDescription ?? type.preferredFilenameExtension?.uppercased()
        }
        let ext = url.pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return nil }
        return type.localizedDescription ?? ext.uppercased()
    }
}
