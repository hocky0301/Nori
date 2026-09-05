import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, capture, privacy, look, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .privacy: "Privacy"
        case .look: "Look"
        case .about: "About"
        }
    }
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .capture: "tray.and.arrow.down"
        case .privacy: "lock.shield"
        case .look: "paintpalette"
        case .about: "info.circle"
        }
    }
}

/// A regular titled window hosting the SwiftUI settings UI. Opening it is the only time Nori activates.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel

    init(coordinator: AppCoordinator) {
        model = SettingsModel(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nori Settings"
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsRootView(model: model))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(tab: SettingsTab) {
        model.selectedTab = tab
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a pure menu bar app once the last regular window goes away.
        if NSApp.windows.filter({ $0.isVisible && $0 !== window && !($0 is FloatingPanel) }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
@Observable
final class SettingsModel {
    var selectedTab: SettingsTab = .general
    unowned let coordinator: AppCoordinator
    var settings: NoriSettings { coordinator.settings }
    var history: HistoryStore { coordinator.history }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }
}
