import AppKit

/// Kind-specific "open" behaviour: links open in the browser, files reveal in Finder, images open in Preview.
@MainActor
enum ItemOpener {
    static func open(_ item: ClipItem) {
        switch item.kind {
        case .link:
            if let url = item.linkURL { NSWorkspace.shared.open(url) }
        case .file:
            let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        case .image:
            guard let data = item.imageData else { return }
            let url = FileManager.default.temporaryDirectory.appending(path: "Nori-\(item.id.uuidString.prefix(8)).png")
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                NSWorkspace.shared.open(url)
            }
        case .text, .code, .richText, .color:
            if let text = item.plainText, let url = KindDetector.link(in: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    static func canOpen(_ item: ClipItem) -> Bool {
        switch item.kind {
        case .link, .file, .image: true
        default: false
        }
    }
}
