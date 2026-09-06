import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, capture, privacy, look, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .capture: String(localized: "Capture")
        case .privacy: String(localized: "Privacy")
        case .look: String(localized: "Look")
        case .about: String(localized: "About")
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
///
/// The tabs live in an `NSTabViewController` with the `.toolbar` style so the window gets the
/// System Settings look (toolbar tabs, window resizes to the selected pane); each pane is SwiftUI.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    private let tabController: SettingsTabViewController

    init(coordinator: AppCoordinator) {
        model = SettingsModel(coordinator: coordinator)
        tabController = SettingsTabViewController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsRootView.width, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Nori Settings")
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.contentViewController = tabController
        window.center()
        super.init(window: window)
        window.delegate = self
        model.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(tab: SettingsTab) {
        model.selectedTab = tab
        tabController.select(tab)
        model.isWindowVisible = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.isWindowVisible = false
        model.coordinator.regularWindowWillClose(window)
    }
}

/// Toolbar-style tabs; keeps `SettingsModel.selectedTab` in sync with the toolbar selection.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    private let model: SettingsModel

    init(model: SettingsModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []
        canPropagateSelectedChildViewControllerTitle = true
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: SettingsRootView(model: model, tab: tab))
            hosting.sizingOptions = [.preferredContentSize]
            hosting.title = tab.title
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func select(_ tab: SettingsTab) {
        guard let index = SettingsTab.allCases.firstIndex(of: tab), index != selectedTabViewItemIndex else { return }
        selectedTabViewItemIndex = index
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        let index = selectedTabViewItemIndex
        guard SettingsTab.allCases.indices.contains(index) else { return }
        let tab = SettingsTab.allCases[index]
        if model.selectedTab != tab { model.selectedTab = tab }
        view.window?.title = String(localized: "Nori Settings — \(tab.title)")
    }
}

@MainActor
@Observable
final class SettingsModel {
    var selectedTab: SettingsTab = .general
    /// Panes only poll (Accessibility trust, storage size) while the window is on screen.
    var isWindowVisible = false
    /// The hosting window, for sheets (app picker, alerts).
    @ObservationIgnored weak var window: NSWindow?
    unowned let coordinator: AppCoordinator
    var settings: NoriSettings { coordinator.settings }
    var history: HistoryStore { coordinator.history }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// "12.4 MB · 342 clips · 3 pinned"
    var storageSummary: String {
        SettingsSupport.storageSummary(
            bytes: coordinator.storage.storeSizeBytes,
            count: history.count,
            pinned: history.pinnedCount
        )
    }

    func clearHistory(includingPinned: Bool) {
        coordinator.model.clearHistory(includingPinned: includingPinned)
    }

    func showOnboarding() {
        settings.hasCompletedOnboarding = false
        coordinator.showOnboarding()
    }
}
