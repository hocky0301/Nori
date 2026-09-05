import AppKit
import KeyboardShortcuts

/// The menu bar icon. Left click toggles the panel, right click shows the menu.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private unowned let coordinator: AppCoordinator

    var button: NSStatusBarButton? { statusItem.button }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.behavior = []
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Nori")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
    }

    func refresh() {
        statusItem.isVisible = coordinator.settings.showMenuBarIcon
        statusItem.button?.appearsDisabled = coordinator.monitor.isPaused
        statusItem.button?.toolTip = coordinator.monitor.isPaused ? String(localized: "Nori — capture paused") : "Nori"
    }

    /// One short blink to acknowledge "skip next copy".
    func flash() {
        guard let button = statusItem.button else { return }
        button.appearsDisabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isRightClick = event.type == .rightMouseUp || flags.contains(.control)
        if isRightClick {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if flags.contains(.option) && flags.contains(.shift) {
            coordinator.monitor.skipNextChange = true
            flash()
        } else if flags.contains(.option) {
            coordinator.togglePause()
        } else {
            coordinator.panelController.toggle(position: .statusItem)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: String(localized: "Open Nori"), action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
            open.setShortcut(shortcut)
        }
        menu.addItem(open)
        menu.addItem(.separator())

        if coordinator.monitor.isPaused {
            let resume = NSMenuItem(title: String(localized: "Resume Capture"), action: #selector(resume), keyEquivalent: "")
            resume.target = self
            if let until = coordinator.settings.pausedUntil, until != .distantFuture {
                let minutes = max(Int(until.timeIntervalSinceNow / 60), 0)
                let remaining = String(localized: "Paused · \(minutes) min left")
                resume.toolTip = remaining
                let caption = NSMenuItem(title: remaining, action: nil, keyEquivalent: "")
                caption.isEnabled = false
                menu.addItem(resume)
                menu.addItem(caption)
            } else {
                menu.addItem(resume)
            }
        } else {
            let pause = NSMenuItem(title: String(localized: "Pause Capture"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (title, minutes) in [(String(localized: "For 5 Minutes"), 5), (String(localized: "For 30 Minutes"), 30)] {
                let item = NSMenuItem(title: title, action: #selector(pauseFor(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                submenu.addItem(item)
            }
            let untilResumed = NSMenuItem(title: String(localized: "Until I Resume"), action: #selector(pauseUntilResumed), keyEquivalent: "")
            untilResumed.target = self
            submenu.addItem(untilResumed)
            pause.submenu = submenu
            menu.addItem(pause)
        }

        let skip = NSMenuItem(title: String(localized: "Skip Next Copy"), action: #selector(skipNext), keyEquivalent: "")
        skip.target = self
        skip.state = coordinator.monitor.skipNextChange ? .on : .off
        menu.addItem(skip)

        let notSaved = coordinator.settings.notSavedToday()
        if notSaved > 0 {
            menu.addItem(.separator())
            let infoTitle = notSaved == 1 ? String(localized: "1 item not saved today") : String(localized: "\(notSaved) items not saved today")
            let info = NSMenuItem(title: infoTitle, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        menu.addItem(.separator())
        let clear = NSMenuItem(title: String(localized: "Clear History…"), action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let about = NSMenuItem(title: String(localized: "About Nori"), action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: String(localized: "Quit Nori"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func openPanel() { coordinator.panelController.open(position: .statusItem) }
    @objc private func resume() { coordinator.resumeCapture() }
    @objc private func pauseUntilResumed() { coordinator.pauseCapture(until: .distantFuture) }
    @objc private func pauseFor(_ sender: NSMenuItem) {
        coordinator.pauseCapture(until: .now.addingTimeInterval(TimeInterval(sender.tag * 60)))
    }
    @objc private func skipNext() { coordinator.monitor.skipNextChange.toggle(); flash() }
    @objc private func openSettings() { coordinator.openSettings() }
    @objc private func openAbout() { coordinator.openSettings(tab: .about) }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear clipboard history?")
        alert.informativeText = String(localized: "Pinned clips are kept. Hold ⌥ while clicking Clear to remove pinned clips too.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Clear"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            let includePinned = NSEvent.modifierFlags.contains(.option)
            coordinator.model.clearHistory(includingPinned: includePinned)
            if coordinator.settings.clearSystemClipboardOnClear {
                NSPasteboard.general.clearContents()
                coordinator.monitor.markCurrentAsSeen()
            }
        }
    }
}
