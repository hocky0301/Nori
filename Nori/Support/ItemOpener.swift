import AppKit

/// Kind-specific "open" behaviour: links open in the browser, files open with their app,
/// images are written to a temporary PNG and opened in Preview.
@MainActor
enum ItemOpener {
    static func open(_ clip: ClipRow, contents: () -> [ClipDraft.Content]) {
        switch clip.kind {
        case .link:
            if let url = clip.linkURL { NSWorkspace.shared.open(url) }
        case .file:
            let urls = clip.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            for url in urls { NSWorkspace.shared.open(url) }
        case .image:
            guard let png = contents().first(where: { $0.type == PasteboardType.png })?.data else { return }
            let url = FileManager.default.temporaryDirectory.appending(path: "Nori-\(clip.id.uuidString.prefix(8)).png")
            try? png.write(to: url)
            NSWorkspace.shared.open(url)
        case .text, .code, .color:
            break
        }
    }

    static func reveal(_ clip: ClipRow) {
        let urls = clip.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    static func canOpen(_ clip: ClipRow) -> Bool {
        switch clip.kind {
        case .link, .file, .image: true
        default: false
        }
    }
}
