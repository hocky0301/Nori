import AppKit
import SwiftUI

/// Inline expand (§3.5): the card grows in place; every kind ends with the same meta strip.
struct ExpandedPreview: View {
    let model: PanelModel
    let row: ClipRow

    @Environment(\.panelTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
                .padding(.top, 8)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            metaStrip
        }
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .text, .code:
            TextPreview(model: model, row: row)
        case .link:
            LinkPreview(model: model, row: row)
        case .color:
            ColorPreview(row: row)
        case .image:
            ImagePreview(model: model, row: row)
        case .file:
            FilePreview(model: model, row: row)
        }
    }

    private var metaStrip: some View {
        Text(Self.metaText(for: row))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(height: 16)
    }

    /// "Safari · first copied Sep 3, 14:02 · last Sep 5, 09:41 · copied 3×"
    static func metaText(for row: ClipRow) -> String {
        var parts: [String] = []
        if row.isFromUniversalClipboard {
            parts.append("iPhone or iPad")
        } else if let app = row.sourceAppName, !app.isEmpty {
            parts.append(app)
        } else if let bundleID = row.sourceBundleID, let app = AppIconCache.shared.appName(bundleID: bundleID) {
            parts.append(app)
        }
        parts.append("first copied \(stamp(row.firstCopiedAt))")
        parts.append("last \(stamp(row.lastCopiedAt))")
        parts.append("copied \(row.copyCount)×")
        return parts.joined(separator: " · ")
    }

    /// "Sep 3, 14:02"
    private static func stamp(_ date: Date) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
        return "\(day), \(time)"
    }
}

// MARK: - Text / code

struct TextPreview: View {
    let model: PanelModel
    let row: ClipRow

    private var monospaced: Bool { row.kind == .code }

    private var fullText: String {
        (model.history.plainText(id: row.id) ?? row.title).replacingOccurrences(of: "\t", with: "    ")
    }

    var body: some View {
        let text = fullText
        let truncated = text.count > SelectableTextView.maxCharacters
        let shown = truncated ? String(text.prefix(SelectableTextView.maxCharacters)) + "…" : text
        let height = min(
            SelectableTextView.measuredHeight(of: shown, monospaced: monospaced, width: PanelMetrics.cardContentWidth - 4),
            PanelMetrics.previewMaxHeight - (truncated ? 18 : 0)
        )
        VStack(alignment: .leading, spacing: 4) {
            SelectableTextView(text: shown, monospaced: monospaced)
                .frame(height: height)
            if truncated {
                Text("Showing first \(SelectableTextView.maxCharacters.formatted()) characters")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Link

struct LinkPreview: View {
    let model: PanelModel
    let row: ClipRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.linkURL?.absoluteString ?? row.title)
                .font(.code)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            PreviewActionButton(title: "Open", key: "⌘O") { model.actions.open(row) }
        }
    }
}

// MARK: - Color

struct ColorPreview: View {
    let row: ClipRow

    var body: some View {
        if let value = row.colorHex.flatMap(ColorValue.init(hex:)) {
            HStack(alignment: .center, spacing: 16) {
                ColorSwatch(value: value, size: 88, radius: 12)
                VStack(alignment: .leading, spacing: 6) {
                    Text(value.hexString)
                    Text(value.rgbString)
                    Text(value.hslString)
                }
                .font(.code)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            }
        } else {
            Text(row.title).font(.code)
        }
    }
}

// MARK: - Image

struct ImagePreview: View {
    let model: PanelModel
    let row: ClipRow

    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else if let thumb = row.thumbnail, let nsImage = NSImage(data: thumb) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(height: 80)
                }
            }
            .frame(maxWidth: PanelMetrics.cardContentWidth, maxHeight: 150, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.Radius.thumb, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PanelMetrics.Radius.thumb, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
            Text(ImageCaption.text(for: row))
                .font(.cardSecondary)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .task(id: row.id) {
            if let cached = PreviewImageCache.shared.image(for: row.id) {
                image = cached
                return
            }
            guard let data = model.history.imageData(id: row.id) else { return }
            let scale = Int((NSScreen.main?.backingScaleFactor ?? 2).rounded(.up))
            let maxPixels = Int(PanelMetrics.cardContentWidth) * scale
            let decoded = await Task.detached(priority: .userInitiated) {
                ImageNormalizer.decode(data, maxPixelSize: maxPixels)
            }.value
            guard let decoded, !Task.isCancelled else { return }
            PreviewImageCache.shared.store(decoded, for: row.id)
            image = decoded
        }
    }
}

// MARK: - File

struct FilePreview: View {
    let model: PanelModel
    let row: ClipRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(row.fileURLs.prefix(12).enumerated()), id: \.offset) { _, url in
                    Text(FileCaption.homeRelative(url))
                        .font(.code)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if row.fileURLs.count > 12 {
                    Text("and \(row.fileURLs.count - 12) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .textSelection(.enabled)
            PreviewActionButton(title: "Reveal in Finder", key: "⌘R") { model.actions.reveal(row) }
        }
    }
}

// MARK: - Shared

/// "Open ⌘O" / "Reveal in Finder ⌘R": a flat button with its chord printed inside.
struct PreviewActionButton: View {
    let title: String
    let key: String
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.panelTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Keycap(text: key)
            }
            .padding(.leading, 10)
            .padding(.trailing, 5)
            .frame(height: 26)
            .background(
                Color.primary.opacity(hovered ? 0.12 : 0.08),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
    }
}
