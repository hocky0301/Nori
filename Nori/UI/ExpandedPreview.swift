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
            parts.append(String(localized: "iPhone or iPad"))
        } else if let app = row.sourceAppName, !app.isEmpty {
            parts.append(app)
        } else if let bundleID = row.sourceBundleID, let app = AppIconCache.shared.appName(bundleID: bundleID) {
            parts.append(app)
        }
        parts.append(String(localized: "first copied \(stamp(row.firstCopiedAt))"))
        parts.append(String(localized: "last \(stamp(row.lastCopiedAt))"))
        parts.append(String(localized: "copied \(row.copyCount)×"))
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

/// The clip's text is read once per row in `.task(id:)` and prepared off the main thread —
/// a 2 MB clip or a large HTML representation never gets decoded, counted or measured inside `body`.
struct TextPreview: View {
    let model: PanelModel
    let row: ClipRow

    /// What the expanded card shows, ready to lay out.
    struct Prepared: Equatable, Sendable {
        var shown: String
        var truncated: Bool
        var height: CGFloat
    }

    /// The representation the store handed over; decoding happens off the main thread.
    enum Source: Sendable {
        case utf8(Data)
        case rtf(Data)
        case text(String)
    }

    @State private var prepared: Prepared?

    private var monospaced: Bool { row.kind == .code }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let prepared {
                SelectableTextView(text: prepared.shown, monospaced: monospaced)
                    .frame(height: prepared.height)
                if prepared.truncated {
                    Text("Showing first \(SelectableTextView.maxCharacters.formatted()) characters")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Color.clear
                    .frame(height: Self.placeholderHeight(lineCount: row.lineCount, monospaced: monospaced))
            }
        }
        .task(id: row.id) { await load() }
    }

    /// Roughly the height the text will take, from the line count the row already carries.
    nonisolated static func placeholderHeight(lineCount: Int, monospaced: Bool) -> CGFloat {
        let lineHeight: CGFloat = monospaced ? 15 : 16
        return min(CGFloat(max(lineCount, 1)) * lineHeight + 4, PanelMetrics.previewMaxHeight)
    }

    private func load() async {
        if let cached = PreviewTextCache.shared.prepared(for: row.id) {
            prepared = cached
            return
        }
        let source = loadSource()
        let monospaced = monospaced
        let result = await Task.detached(priority: .userInitiated) {
            Self.prepare(source, monospaced: monospaced, width: PanelMetrics.cardContentWidth - 4)
        }.value
        guard !Task.isCancelled else { return }
        PreviewTextCache.shared.store(result, for: row.id)
        prepared = result
    }

    /// The best plain-text representation, faulting only the blob that is needed.
    private func loadSource() -> Source {
        guard let item = model.history.item(id: row.id) else { return .text(row.title) }
        if let data = item.data(for: PasteboardType.utf8PlainText) { return .utf8(data) }
        if let data = item.data(for: PasteboardType.rtf) { return .rtf(data) }
        if let data = item.data(for: PasteboardType.html),
           // The HTML importer is WebKit-backed and main-thread only; it runs here, never in `body`.
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            return .text(attributed.string)
        }
        return .text(row.title)
    }

    /// Decode, truncate to `SelectableTextView.maxCharacters` and measure. Runs off the main thread.
    nonisolated static func prepare(_ source: Source, monospaced: Bool, width: CGFloat) -> Prepared {
        let text: String
        switch source {
        case let .utf8(data): text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        case let .rtf(data): text = NSAttributedString(rtf: data, documentAttributes: nil)?.string ?? ""
        case let .text(string): text = string
        }
        return prepare(text: text, monospaced: monospaced, width: width)
    }

    nonisolated static func prepare(text: String, monospaced: Bool, width: CGFloat) -> Prepared {
        let expanded = text.replacingOccurrences(of: "\t", with: "    ")
        // Compare by UTF-8 length first: a 2 MB clip is truncated without counting its graphemes.
        let truncated = expanded.utf8.count > SelectableTextView.maxCharacters
            && expanded.count > SelectableTextView.maxCharacters
        let shown = truncated ? String(expanded.prefix(SelectableTextView.maxCharacters)) + "…" : expanded
        let height = min(
            SelectableTextView.measuredHeight(of: shown, monospaced: monospaced, width: width),
            PanelMetrics.previewMaxHeight - (truncated ? 18 : 0)
        )
        return Prepared(shown: shown, truncated: truncated, height: height)
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

    /// The image scaled to fit 536 × 150 without upscaling, so the frame and border hug the picture.
    private var fittedSize: CGSize {
        let maxWidth = PanelMetrics.cardContentWidth
        let maxHeight: CGFloat = 150
        guard let size = row.imagePixelSize, size.width > 0, size.height > 0 else {
            return CGSize(width: 120, height: 80)
        }
        let scale = min(maxWidth / size.width, maxHeight / size.height, 1)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

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
            .frame(width: fittedSize.width, height: fittedSize.height)
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

/// Every path, one per line; the list scrolls inside the card once it would push the card past
/// `PanelMetrics.expandedCardMaxHeight`, so the expand-scroll projection stays an upper bound.
struct FilePreview: View {
    let model: PanelModel
    let row: ClipRow

    @State private var listHeight: CGFloat?

    /// Room for the path list: the preview cap minus the button and the gap above it.
    static let listMaxHeight = PanelMetrics.previewMaxHeight - 26 - 8
    private static let lineSpacing: CGFloat = 3
    private static let estimatedLineHeight: CGFloat = 15

    /// Until the list has been measured, the card grows to a line-count estimate.
    nonisolated static func height(forMeasured measured: CGFloat?, count: Int) -> CGFloat {
        let estimate = CGFloat(max(count, 1)) * estimatedLineHeight + CGFloat(max(count - 1, 0)) * lineSpacing
        return min(measured ?? estimate, listMaxHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Self.lineSpacing) {
                    ForEach(Array(row.fileURLs.enumerated()), id: \.offset) { _, url in
                        Text(FileCaption.homeRelative(url))
                            .font(.code)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: Self.height(forMeasured: listHeight, count: row.fileURLs.count))
            PreviewActionButton(title: "Reveal in Finder", key: "⌘R") { model.actions.reveal(row) }
        }
    }
}

// MARK: - Shared

/// "Open ⌘O" / "Reveal in Finder ⌘R": a flat button with its chord printed inside.
struct PreviewActionButton: View {
    let title: LocalizedStringKey
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
