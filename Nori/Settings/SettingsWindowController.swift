import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, privacy, storage, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .privacy: "Privacy"
        case .storage: "Storage"
        case .about: "About"
        }
    }
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .privacy: "hand.raised"
        case .storage: "internaldrive"
        case .about: "info.circle"
        }
    }
}

/// A regular titled window hosting the SwiftUI settings UI.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel

    init(coordinator: AppCoordinator) {
        model = SettingsModel(coordinator: coordinator)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Nori Settings"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
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
        NSApp.setActivationPolicy(.accessory)
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
