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
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above Spotlight and browser autofill popups (which use level 999).
        level = .screenSaver
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Escape and ⌘. are routed here by AppKit when no responder handled them.
    override func cancelOperation(_ sender: Any?) {
        onResignKey?()
    }
}
