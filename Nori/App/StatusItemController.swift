import AppKit
import KeyboardShortcuts

/// The menu bar icon. Left click toggles the panel, right click shows the menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private unowned let coordinator: AppCoordinator

    var button: NSStatusBarButton? { statusItem.button }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.behavior = []
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Nori")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
    }

    func refresh() {
        statusItem.isVisible = coordinator.settings.showMenuBarIcon
        statusItem.button?.appearsDisabled = coordinator.settings.isPaused
        statusItem.button?.toolTip = coordinator.settings.isPaused ? "Nori (paused)" : "Nori"
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRightClick {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if event.modifierFlags.contains(.option) {
            coordinator.setPaused(!coordinator.settings.isPaused)
        } else {
            coordinator.panelController.toggle(position: .statusItem)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "Open Nori", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
            open.setShortcut(shortcut)
        }
        menu.addItem(open)

        let pause = NSMenuItem(
            title: coordinator.settings.isPaused ? "Resume Capturing" : "Pause Capturing",
            action: #selector(togglePause), keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        let skip = NSMenuItem(title: "Ignore Next Copy", action: #selector(skipNext), keyEquivalent: "")
        skip.target = self
        skip.state = coordinator.monitor.skipNextChange ? .on : .off
        menu.addItem(skip)

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let about = NSMenuItem(title: "About Nori", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Nori", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func openPanel() { coordinator.panelController.open(position: .statusItem) }
    @objc private func togglePause() { coordinator.setPaused(!coordinator.settings.isPaused) }
    @objc private func skipNext() { coordinator.monitor.skipNextChange.toggle() }
    @objc private func openSettings() { coordinator.openSettings() }
    @objc private func openAbout() { coordinator.openSettings(tab: .about) }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items are kept. Hold ⌥ while clicking Clear to remove pinned items too."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            let includePinned = NSEvent.modifierFlags.contains(.option)
            coordinator.history.clear(includingPinned: includePinned)
        }
    }
}
