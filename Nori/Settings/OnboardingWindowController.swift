import AppKit
import SwiftUI

/// State of the welcome flow, shared by the window controller (for debug stepping) and the view.
@MainActor
@Observable
final class OnboardingModel {
    static let stepCount = 3

    /// 1 = hotkey, 2 = Accessibility, 3 = login item. Always within 1…`stepCount`.
    private(set) var step = 1
    /// Polling and the temporary hotkey listener only run while the window is on screen.
    var isVisible = false
    /// Step 1: flipped by the temporary listener the moment the chord is pressed.
    var shortcutPressed = false
    /// Step 2: mirrors `Paster.isTrusted`, refreshed every second.
    var accessibilityTrusted = Paster.isTrusted
    /// Step 3: proposed ON so the choice is explicit; applied on Done.
    var startAtLogin = true

    var isFirstStep: Bool { step == 1 }
    var isLastStep: Bool { step == Self.stepCount }

    func go(to step: Int) { self.step = min(max(step, 1), Self.stepCount) }
    func next() { go(to: step + 1) }
    func back() { go(to: step - 1) }
}

/// The three-step welcome (hotkey → Accessibility → login item). Re-runnable from Settings.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let size = NSSize(width: 520, height: 440)

    unowned let coordinator: AppCoordinator
    let model = OnboardingModel()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to Nori")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.delegate = self
        let hosting = NSHostingView(rootView: OnboardingView(model: model, coordinator: coordinator, finish: { [weak self] in
            self?.finish()
        }))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(Self.size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(step: Int = 1) {
        model.go(to: step)
        model.shortcutPressed = false
        model.accessibilityTrusted = Paster.isTrusted
        model.startAtLogin = coordinator.settings.launchAtLogin || !coordinator.settings.hasCompletedOnboarding
        model.isVisible = true
        // The view listens for the chord itself; the app-wide toggle must not fire meanwhile.
        coordinator.suppressesHotkeyToggle = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        coordinator.settings.hasCompletedOnboarding = true
        if model.startAtLogin != coordinator.settings.launchAtLogin {
            coordinator.settings.launchAtLogin = model.startAtLogin
        }
        window?.close()
        // Seed a first clip so the very first ↩ does something.
        if coordinator.history.count == 0 {
            var draft = ClipClassifier.makeDraft(contents: [
                .init(type: PasteboardType.utf8PlainText, data: Data(String(localized: "Welcome to Nori 👋 Press ↩ to paste this.").utf8)),
            ])!
            draft.sourceAppName = "Nori"
            draft.sourceBundleID = Bundle.main.bundleIdentifier
            coordinator.history.ingest(draft)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.coordinator.panelController.open(position: .center)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.isVisible = false
        coordinator.suppressesHotkeyToggle = false
        if NSApp.windows.filter({ $0.isVisible && $0 !== window && !($0 is FloatingPanel) }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
