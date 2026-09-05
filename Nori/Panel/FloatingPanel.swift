import AppKit
import OSLog
import SwiftUI

/// A borderless, non-activating panel: it becomes key so the search field gets keystrokes,
/// but the app that was frontmost stays active, so ⌘V lands in the right place afterwards.
final class FloatingPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above Spotlight and browser autofill popups (which use level 999).
        level = .screenSaver
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        minSize = NSSize(width: 420, height: 320)
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        Logger(subsystem: "io.github.hocky0301.Nori", category: "panel")
            .notice("resignKey; new key=\(String(describing: NSApp.keyWindow), privacy: .public) active=\(NSApp.isActive) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?", privacy: .public) event=\(String(describing: NSApp.currentEvent?.type.rawValue), privacy: .public)")
        onResignKey?()
    }

    /// Escape and ⌘W are routed here by AppKit when no responder handled them.
    override func cancelOperation(_ sender: Any?) {
        onResignKey?()
    }
}
