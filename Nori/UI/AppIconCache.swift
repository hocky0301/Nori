import AppKit

/// Icons for the meta column and file wells, looked up once per bundle id / path.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private var appIcons: [String: NSImage] = [:]
    private var fileIcons: [String: NSImage] = [:]
    private var missingApps: Set<String> = []

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

    private var appNames: [String: String] = [:]

    /// Localized app name for a bundle id ("Safari"), when the row carries only the identifier.
    func appName(bundleID: String) -> String? {
        if let name = appNames[bundleID] { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        appNames[bundleID] = name
        return name
    }

    func fileIcon(path: String) -> NSImage {
        if let icon = fileIcons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        if fileIcons.count > 200 { fileIcons.removeAll() }
        fileIcons[path] = icon
        return icon
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
