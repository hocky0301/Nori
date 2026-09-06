import AppKit
import UniformTypeIdentifiers

/// Icons for the meta column and file wells, looked up once per bundle id / path.
///
/// Nothing here touches the filesystem while a card renders: file icons are served from the cache
/// or resolved off the main thread (`fileIcon(path:)`), with a type icon derived from the file's
/// extension standing in until then.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var appIcons: [String: NSImage] = [:]
    private var missingApps: Set<String> = []
    private let fileIcons = NSCache<NSString, NSImage>()
    private var typeIcons: [String: NSImage] = [:]
    private var typeDescriptions: [String: String?] = [:]
    private var appNames: [String: String] = [:]

    init() {
        fileIcons.countLimit = 400
    }

    func appIcon(bundleID: String) -> NSImage? {
        if let icon = appIcons[bundleID] { return icon }
        guard !missingApps.contains(bundleID),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missingApps.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[bundleID] = icon
        return icon
    }

    /// Localized app name for a bundle id ("Safari"), when the row carries only the identifier.
    func appName(bundleID: String) -> String? {
        if let name = appNames[bundleID] { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        appNames[bundleID] = name
        return name
    }

    // MARK: File icons

    /// The Finder icon for `path` if it has been resolved before; never touches the disk.
    func cachedFileIcon(path: String) -> NSImage? {
        fileIcons.object(forKey: path as NSString)
    }

    /// The Finder icon for `path`, resolved off the main thread on a miss (an unreachable network
    /// volume must not stall the panel), then kept per path.
    func fileIcon(path: String) async -> NSImage {
        if let icon = cachedFileIcon(path: path) { return icon }
        let resolved = await Task.detached(priority: .userInitiated) {
            SendableImage(NSWorkspace.shared.icon(forFile: path))
        }.value
        fileIcons.setObject(resolved.image, forKey: path as NSString)
        return resolved.image
    }

    /// The generic icon for the file's type (from its extension only), shown until the real one arrives.
    func typeIcon(for url: URL) -> NSImage {
        let type = FileCaption.contentType(for: url)
        if let icon = typeIcons[type.identifier] { return icon }
        let icon = NSWorkspace.shared.icon(for: type)
        typeIcons[type.identifier] = icon
        return icon
    }

    /// `FileCaption.typeDescription(for:)`, looked up once per extension.
    func typeDescription(for url: URL) -> String? {
        let key = FileCaption.contentType(for: url).identifier
        if let cached = typeDescriptions[key] { return cached }
        let description = FileCaption.typeDescription(for: url)
        typeDescriptions[key] = description
        return description
    }

    /// An icon handed from the resolving task to the main actor. `NSImage` is not `Sendable`, but
    /// nothing mutates the icon once `NSWorkspace` has produced it.
    private struct SendableImage: @unchecked Sendable {
        let image: NSImage
        init(_ image: NSImage) { self.image = image }
    }
}

/// Downsampled decodes for expanded image cards. Emptied when the panel closes.
@MainActor
final class PreviewImageCache {
    static let shared = PreviewImageCache()
    private let cache = NSCache<NSUUID, CGImageBox>()

    final class CGImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    init() {
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for id: UUID) -> CGImage? {
        cache.object(forKey: id as NSUUID)?.image
    }

    func store(_ image: CGImage, for id: UUID) {
        cache.setObject(CGImageBox(image), forKey: id as NSUUID, cost: image.bytesPerRow * image.height)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Prepared text for expanded text/code cards, so re-expanding a row does not read its blob again.
/// Emptied when the panel closes.
@MainActor
final class PreviewTextCache {
    static let shared = PreviewTextCache()
    private let cache = NSCache<NSUUID, Box>()

    final class Box {
        let value: TextPreview.Prepared
        init(_ value: TextPreview.Prepared) { self.value = value }
    }

    init() {
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func prepared(for id: UUID) -> TextPreview.Prepared? {
        cache.object(forKey: id as NSUUID)?.value
    }

    func store(_ value: TextPreview.Prepared, for id: UUID) {
        cache.setObject(Box(value), forKey: id as NSUUID, cost: value.shown.utf8.count)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
