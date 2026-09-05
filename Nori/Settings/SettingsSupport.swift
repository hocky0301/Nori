import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts
import UniformTypeIdentifiers

/// Pure helpers behind the settings and onboarding UI, kept separate so they can be unit-tested.
enum SettingsSupport {
    /// "12.4 MB · 342 clips · 3 pinned"
    static func storageSummary(bytes: Int64, count: Int, pinned: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        let size = formatter.string(fromByteCount: bytes)
        return "\(size) · \(count) \(count == 1 ? "clip" : "clips") · \(pinned) pinned"
    }

    /// Whether `pattern` compiles as an `NSRegularExpression` (the engine `CapturePolicy` uses).
    /// An empty entry is a row still being typed, not an error; the policy skips it.
    static func isValidRegex(_ pattern: String) -> Bool {
        pattern.isEmpty || (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// The printable character a shortcut would type into a text field, or nil when it types nothing.
    ///
    /// ⌘ chords never insert text; ⌃ chords yield control characters. Only ⌥/⇧ chords (or bare keys)
    /// reach the field, which is the case the onboarding warning is about.
    static func typedCharacter(for shortcut: KeyboardShortcuts.Shortcut) -> String? {
        let modifiers = shortcut.modifiers
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.function) {
            return nil
        }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        let modifierState = UInt32((shortcut.carbonModifiers >> 8) & 0xFF)
        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var buffer = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, UInt16(shortcut.carbonKeyCode), UInt16(kUCKeyActionDown), modifierState,
                UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState, buffer.count, &length, &buffer
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: buffer, count: length)
            let printable = text.unicodeScalars.allSatisfy { !$0.properties.generalCategory.isControlLike && !$0.properties.isWhitespace }
            return printable && !text.isEmpty ? text : nil
        }
    }

    /// The app icon and display name for a bundle id, when the app is installed.
    struct InstalledApp {
        let bundleID: String
        let name: String
        let icon: NSImage
    }

    static func installedApp(bundleID: String) -> InstalledApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return InstalledApp(bundleID: bundleID, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
    }
}

private extension Unicode.GeneralCategory {
    var isControlLike: Bool {
        switch self {
        case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned: true
        default: false
        }
    }
}

/// Tracks whether ⌥ is held, so "Clear History…" can become "Clear Including Pinned…" live.
@MainActor
@Observable
final class OptionKeyMonitor {
    private(set) var isOptionHeld = NSEvent.modifierFlags.contains(.option)
    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        isOptionHeld = NSEvent.modifierFlags.contains(.option)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.contains(.option)
            MainActor.assumeIsolated { self?.isOptionHeld = held }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// An `NSOpenPanel` limited to application bundles in the usual app folders; hands back the bundle id.
@MainActor
enum AppPicker {
    nonisolated static let allowedFolders: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL.homeDirectory.appending(path: "Applications"),
    ]

    static func pick(from window: NSWindow?, completion: @escaping @MainActor (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.message = "Nori won't remember anything copied in the app you choose."
        panel.prompt = "Ignore App"
        panel.directoryURL = allowedFolders[0]
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.delegate = Delegate.shared

        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            completion(Bundle(url: url)?.bundleIdentifier)
        }
        if let window {
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            finish(panel.runModal())
        }
    }

    @MainActor
    private final class Delegate: NSObject, NSOpenSavePanelDelegate {
        static let shared = Delegate()

        nonisolated func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
            let path = url.standardizedFileURL.path
            let insideAllowed = AppPicker.allowedFolders.contains { path.hasPrefix($0.standardizedFileURL.path) }
            guard insideAllowed else { return false }
            if url.pathExtension == "app" { return true }
            // Folders inside /Applications stay navigable.
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}
