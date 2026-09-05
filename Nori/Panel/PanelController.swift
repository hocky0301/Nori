import AppKit
import Observation
import OSLog
import QuartzCore
import SwiftUI

/// Shows and hides the history panel, positions it, animates it, and forwards keyboard events.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private(set) var isVisible = false
    var onWillOpen: ((_ preservingState: Bool) -> Void)?
    var onDidClose: (() -> Void)?
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

    func toggle(position: NoriSettings.PanelPosition? = nil) {
        if isVisible { close(reason: "toggle") } else { open(position: position) }
    }

    func open(position: NoriSettings.PanelPosition? = nil, preservingState: Bool = false, frame: NSRect? = nil) {
        guard !isVisible else { return }
        let frame = frame ?? PanelPlacement.frame(position: position ?? settings.panelPosition, statusButton: statusButton)
        panel.setFrame(frame, display: false)
        lastFrame = frame
        onWillOpen?(preservingState)
        installMonitor()
        animateIn()
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        statusButton?.isHighlighted = true
        logger.debug("opened panel at \(frame.origin.x),\(frame.origin.y)")
    }

    func close(reason: String = "request") {
        guard isVisible else { return }
        logger.debug("closing panel (\(reason, privacy: .public))")
        isVisible = false
        removeMonitor()
        statusButton?.isHighlighted = false
        onDidClose?()
        animateOut { [weak self] in
            guard let self, !isVisible else { return }
            panel.orderOut(nil)
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
