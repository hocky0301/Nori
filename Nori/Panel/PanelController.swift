import AppKit
import Observation
import OSLog
import QuartzCore
import SwiftUI

/// Shows and hides the history panel, positions it, animates it, and forwards keyboard events.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private(set) var isVisible = false
    var onWillOpen: ((_ preservingState: Bool, _ viaHotkey: Bool) -> Void)?
    /// `willReopen` is true for the close that precedes a keep-open reopen.
    var onDidClose: ((_ willReopen: Bool) -> Void)?
    /// Return true to swallow the event.
    var keyHandler: ((NSEvent) -> Bool)?
    var statusButton: NSStatusBarButton?

    let panel: FloatingPanel
    private let settings: NoriSettings
    private var localMonitor: Any?
    private var lastFrame: NSRect?
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "panel")

    init<Content: View>(settings: NoriSettings, rootView: Content) {
        self.settings = settings
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: PanelPlacement.width, height: PanelPlacement.maxHeight))
        super.init()
        let hosting = NSHostingView(rootView: rootView.ignoresSafeArea())
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        panel.contentView = hosting
        panel.delegate = self
        panel.onResignKey = { [weak self] in self?.close(reason: "resignKey") }
    }

    /// `viaHotkey`: the global hotkey opened the panel (its modifiers are held), which is what
    /// arms cycle mode; a status-item click or a menu item never does.
    func toggle(position: NoriSettings.PanelPosition? = nil, viaHotkey: Bool = false) {
        if isVisible { close(reason: "toggle") } else { open(position: position, viaHotkey: viaHotkey) }
    }

    func open(position: NoriSettings.PanelPosition? = nil, preservingState: Bool = false, frame: NSRect? = nil, viaHotkey: Bool = false) {
        guard !isVisible else { return }
        // Nori hides itself after a Settings or onboarding window closes so the previous app gets
        // activation back; a hidden app's windows stay hidden, so unhide (without activating) first.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        let frame = frame ?? PanelPlacement.frame(position: position ?? settings.panelPosition, statusButton: statusButton)
        panel.setFrame(frame, display: false)
        lastFrame = frame
        onWillOpen?(preservingState, viaHotkey)
        installMonitor()
        animateIn()
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        statusButton?.isHighlighted = true
        logger.debug("opened panel at \(frame.origin.x),\(frame.origin.y)")
    }

    /// Hide the panel. `immediately` skips the fade and orders the window out before returning,
    /// so the panel has resigned key when `completion` runs — required before a synthetic ⌘V is
    /// posted, or the keystroke lands on Nori's own search field. `willReopen` marks the close
    /// that precedes a keep-open reopen.
    func close(reason: String = "request", immediately: Bool = false, willReopen: Bool = false, completion: (@MainActor () -> Void)? = nil) {
        guard isVisible else { completion?(); return }
        logger.debug("closing panel (\(reason, privacy: .public))")
        isVisible = false
        removeMonitor()
        statusButton?.isHighlighted = false
        onDidClose?(willReopen)
        if immediately {
            panel.contentView?.layer?.removeAllAnimations()
            panel.orderOut(nil)
            completion?()
            return
        }
        animateOut { [weak self] in
            if let self, !isVisible { panel.orderOut(nil) }
            completion?()
        }
    }

    /// Re-open at the same place with search, filter and selection intact (⌥ = keep open).
    func reopenPreservingState() {
        open(preservingState: true, frame: lastFrame)
    }

    // MARK: Animation

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func animateIn() {
        guard let layer = panel.contentView?.layer else { return }
        layer.removeAllAnimations()
        layer.opacity = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = reduceMotion ? 0.12 : 0.16
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "appear-opacity")
        if !reduceMotion {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.97
            scale.toValue = 1
            scale.duration = 0.16
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(scale, forKey: "appear-scale")
        }
    }

    private func animateOut(completion: @escaping @MainActor () -> Void) {
        guard let layer = panel.contentView?.layer else { completion(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { completion() }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.1
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "dismiss-opacity")
        CATransaction.commit()
    }

    // MARK: Keyboard

    private func installMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // Local monitors always run on the main thread.
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isVisible, event.window === self.panel else { return false }
                return self.keyHandler?(event) == true
            }
            return handled ? nil : event
        }
    }

    private func removeMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
