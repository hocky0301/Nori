import AppKit
import SwiftUI

/// The three-step welcome (hotkey → Accessibility → login item). Re-runnable from Settings.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Nori"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(coordinator: coordinator, finish: { [weak self] in
            self?.finish()
        }))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        coordinator.settings.hasCompletedOnboarding = true
        window?.close()
        // Seed a first clip so the very first ↩ does something.
        if coordinator.history.count == 0 {
            var draft = ClipClassifier.makeDraft(contents: [
                .init(type: PasteboardType.utf8PlainText, data: Data("Welcome to Nori 👋 Press ↩ to paste this.".utf8)),
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
        if NSApp.windows.filter({ $0.isVisible && $0 !== window && !($0 is FloatingPanel) }).isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
