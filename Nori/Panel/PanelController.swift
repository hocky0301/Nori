import AppKit
import Observation
import OSLog
import SwiftUI

/// Shows and hides the history panel, positions it, and forwards keyboard events.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private(set) var isVisible = false
    var onWillOpen: (() -> Void)?
    var onDidClose: (() -> Void)?
    /// Return true to swallow the event.
    var keyHandler: ((NSEvent) -> Bool)?
    var statusButton: NSStatusBarButton?

    let panel: FloatingPanel
    private let settings: NoriSettings
    private var localMonitor: Any?
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "panel")

    init<Content: View>(settings: NoriSettings, rootView: Content) {
        self.settings = settings
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: settings.panelSize))
        super.init()
        let hosting = NSHostingView(rootView: rootView.ignoresSafeArea())
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.delegate = self
        panel.onResignKey = { [weak self] in self?.close() }
    }

    func toggle(position: NoriSettings.PanelPosition? = nil) {
        if isVisible { close() } else { open(position: position) }
    }

    func open(position: NoriSettings.PanelPosition? = nil) {
        guard !isVisible else { return }
        let size = settings.panelSize
        let origin = PanelPlacement.origin(
            for: size,
            position: position ?? settings.panelPosition,
            statusButton: statusButton,
            lastOrigin: settings.lastPanelOrigin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        onWillOpen?()
        installMonitor()
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        statusButton?.isHighlighted = true
    }

    func close() {
        guard isVisible else { return }
        isVisible = false
        removeMonitor()
        settings.lastPanelOrigin = panel.frame.origin
        panel.orderOut(nil)
        statusButton?.isHighlighted = false
        onDidClose?()
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

    // MARK: NSWindowDelegate

    func windowDidEndLiveResize(_ notification: Notification) {
        settings.panelSize = panel.frame.size
    }

    func windowDidMove(_ notification: Notification) {
        if isVisible { settings.lastPanelOrigin = panel.frame.origin }
    }
}
