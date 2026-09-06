import AppKit
import KeyboardShortcuts
import OSLog
import SwiftUI

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))
}

/// Wires the pieces together: storage → history → monitor → panel → status item.
@MainActor
final class AppCoordinator {
    let settings = NoriSettings.shared
    let storage = Storage.shared
    let history: HistoryStore
    let vault = SensitiveVault()
    let monitor = ClipboardMonitor()
    let model: PanelModel
    private(set) var panelController: PanelController!
    private var statusItem: StatusItemController!
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var pauseTimer: Timer?
    private var expiryTimer: Timer?
    /// Set while the onboarding window listens for the hotkey itself (step 1), so the chord
    /// shows "That's it" instead of toggling the panel underneath the welcome window.
    var suppressesHotkeyToggle = false
    #if DEBUG
    private var debugBridge: DebugBridge?
    #endif
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "app")

    init() {
        history = HistoryStore(context: storage.context)
        model = PanelModel(history: history, vault: vault, settings: settings)
    }

    func start() {
        history.maxItems = settings.maxItems
        history.expireAfterDays = settings.expireAfterDays
        history.load()

        monitor.policy = settings.capturePolicy
        monitor.pausedUntil = settings.pausedUntil
        monitor.onEvent = { [weak self] event in self?.handle(event) }
        monitor.start(interval: settings.pollInterval)
        schedulePauseExpiry()

        panelController = PanelController(settings: settings, rootView: PanelRootView(model: model))
        model.actions = PanelActions(coordinator: self)
        panelController.onWillOpen = { [weak self] preserving, viaHotkey in
            guard let self else { return }
            // A copy made a moment before the hotkey must be in the list. Classification is
            // asynchronous, so the model keeps row 1 selected until the user moves the selection.
            monitor.poll()
            model.panelWillOpen(preserveState: preserving, viaHotkey: viaHotkey)
            showAccessibilityBannerIfNeeded()
        }
        panelController.onDidClose = { [weak self] willReopen in self?.model.panelDidClose(willReopen: willReopen) }
        panelController.keyHandler = { [weak self] event in self?.model.handle(event: event) ?? false }

        statusItem = StatusItemController(coordinator: self)
        panelController.statusButton = statusItem.button

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            guard let self, !suppressesHotkeyToggle else { return }
            togglePanel(viaHotkey: true)
        }

        let expiry = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.history.expireOldItems() }
        }
        RunLoop.main.add(expiry, forMode: .common)
        expiryTimer = expiry

        observeSettings()
        #if DEBUG
        debugBridge = DebugBridge(coordinator: self)
        #endif

        if storage.recoveredFromCorruption {
            model.showToast(String(localized: "History could not be opened and was reset"))
        }
        if !settings.hasCompletedOnboarding, !CommandLine.arguments.contains("--in-memory") {
            showOnboarding()
        }
        logger.info("Nori started with \(self.history.count) items")
    }

    private func handle(_ event: ClipboardMonitor.Event) {
        switch event {
        case let .captured(draft, date):
            let id = history.ingest(draft, now: date)
            if draft.kind == .image, settings.ocrImages {
                ImageTextRecognizer.recognize(
                    itemID: id,
                    imageData: draft.data(for: PasteboardType.png),
                    // A re-copy of an image that was already read, or an item evicted meanwhile, is skipped.
                    isStillWanted: { [weak self] id in
                        guard let row = self?.history.row(id: id) else { return false }
                        return row.copyCount == 1 || row.searchText.isEmpty
                    },
                    completion: { [weak self] id, text in self?.history.updateSearchText(id: id, text: text) }
                )
            }
        case let .sensitive(sensitive, date):
            vault.add(sensitive, now: date)
        case let .ghost(reason, date):
            if settings.showGhostRows {
                model.addGhost(reason, at: date)
            } else {
                settings.recordNotSaved(on: date)
            }
        case let .promoted(id, date):
            if history.item(id: id) != nil {
                history.touch(id: id, now: date)
            } else if vault.entry(id: id) != nil {
                vault.touch(id: id, now: date)
            }
        case .rejected:
            break
        }
    }

    /// `viaHotkey` is true only from the global hotkey handler; it is what arms cycle mode.
    func togglePanel(viaHotkey: Bool = false) {
        panelController.toggle(viaHotkey: viaHotkey)
    }

    func openSettings(tab: SettingsTab = .general) {
        panelController.close(reason: "settings")
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(coordinator: self)
        }
        settingsWindow?.show(tab: tab)
    }

    func showOnboarding() {
        panelController.close(reason: "onboarding")
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController(coordinator: self)
        }
        onboardingWindow?.show()
    }

    /// Onboarding opened at a given step (1…3); used by the debug bridge for screenshots.
    func showOnboarding(step: Int) {
        panelController.close(reason: "onboarding")
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController(coordinator: self)
        }
        onboardingWindow?.show(step: step)
    }

    /// Settings and onboarding are Nori's only regular windows. Once the last of them closes,
    /// go back to being a menu bar app and hand activation to the app the user came from
    /// (`NSApp.windows` cannot be scanned for this: it also holds the status bar window).
    func regularWindowWillClose(_ closing: NSWindow?) {
        let others = [settingsWindow?.window, onboardingWindow?.window]
            .compactMap { $0 }
            .filter { $0 !== closing && $0.isVisible }
        guard others.isEmpty else { return }
        NSApp.setActivationPolicy(.accessory)
        // Without this Nori stays the active app with no windows, and the next paste's ⌘V goes nowhere.
        NSApp.hide(nil)
    }

    func willTerminate() {
        if settings.clearOnQuit {
            history.clear(includingPinned: false)
        }
        vault.removeAll()
    }

    // MARK: Actions used by the panel and status item

    /// Copy (and optionally paste) a clip according to the resolved grammar action.
    func perform(_ action: ActionGrammar.Action, on clip: ClipRow) {
        let contents: [ClipDraft.Content]
        if clip.isSensitive, let entry = vault.entry(id: clip.id) {
            contents = entry.draft.contents
            vault.touch(id: clip.id)
        } else {
            contents = history.contents(id: clip.id)
            history.touch(id: clip.id)
        }
        guard !contents.isEmpty else { return }

        ClipboardWriter.write(contents: contents, id: clip.id, sourceBundleID: clip.sourceBundleID, plainTextOnly: action.plain)
        monitor.markCurrentAsSeen()
        finish(action, reason: "paste")
    }

    /// No matches for the typed query: ↩ pastes the query itself as plain text. The write carries
    /// no Nori marker, so the next poll captures it as a brand-new text clip.
    func pasteTypedText(_ text: String, action: ActionGrammar.Action) {
        ClipboardWriter.write(string: text)
        finish(action, reason: "typed text")
    }

    /// Close (unless copy + keep open) and, for a paste, post ⌘V once the panel is really gone.
    private func finish(_ action: ActionGrammar.Action, reason: String) {
        let keepOpen = action.keepOpen
        guard action.isPaste else {
            if !keepOpen { panelController.close(reason: "copy") }
            return
        }
        // The panel orders out synchronously here, so it has resigned key before the keystroke is
        // posted on the next run-loop turn; otherwise ⌘V lands in Nori's own search field.
        panelController.close(reason: reason, immediately: true, willReopen: keepOpen) { [weak self] in
            DispatchQueue.main.async {
                Paster.sendPasteKeystroke()
                guard keepOpen else { return }
                // The key-up has been posted; give the target app a moment to take the paste.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    self?.panelController.reopenPreservingState()
                }
            }
        }
    }

    /// "Clearing history also clears the system clipboard".
    func clearSystemClipboard() {
        NSPasteboard.general.clearContents()
        monitor.markCurrentAsSeen()
    }

    func enablePasting() {
        Paster.requestTrust()
        Paster.openAccessibilitySettings()
    }

    func togglePause() {
        if monitor.isPaused { resumeCapture() } else { pauseCapture(until: .distantFuture) }
    }

    func pauseCapture(until date: Date) {
        settings.pausedUntil = date
        monitor.pausedUntil = date
        schedulePauseExpiry()
        statusItem.refresh()
    }

    func resumeCapture() {
        settings.pausedUntil = nil
        monitor.pausedUntil = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        statusItem.refresh()
    }

    private func schedulePauseExpiry() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        guard let until = settings.pausedUntil, until != .distantFuture else { return }
        if until <= .now {
            resumeCapture()
            return
        }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeCapture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    private func showAccessibilityBannerIfNeeded() {
        guard settings.pasteBlockedByAccessibility, settings.accessibilityGrantedOnce, !Paster.isTrusted else {
            model.showsAccessibilityBanner = false
            return
        }
        if let last = settings.accessibilityBannerLastShownAt, Calendar.current.isDateInToday(last) {
            return
        }
        settings.accessibilityBannerLastShownAt = .now
        settings.pasteBlockedByAccessibility = false
        model.showsAccessibilityBanner = true
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.pollInterval
            _ = settings.ignoredApps
            _ = settings.ignoredTypes
            _ = settings.ignoreRegexps
            _ = settings.captureText
            _ = settings.captureImages
            _ = settings.captureFiles
            _ = settings.captureUniversalClipboard
            _ = settings.maskSensitive
            _ = settings.maxImageMegabytes
            _ = settings.maxItems
            _ = settings.expireAfterDays
            _ = settings.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                monitor.policy = settings.capturePolicy
                monitor.start(interval: settings.pollInterval)
                history.maxItems = settings.maxItems
                history.expireAfterDays = settings.expireAfterDays
                history.expireOldItems()
                statusItem.refresh()
                observeSettings()
            }
        }
    }
}

extension PanelActions {
    @MainActor
    init(coordinator: AppCoordinator) {
        self.init()
        perform = { [unowned coordinator] clip, action in coordinator.perform(action, on: clip) }
        pasteTypedText = { [unowned coordinator] text, action in coordinator.pasteTypedText(text, action: action) }
        open = { clip in ItemOpener.open(clip, contents: { AppCoordinatorRegistry.shared?.history.contents(id: clip.id) ?? [] }) }
        reveal = { clip in ItemOpener.reveal(clip) }
        openSettings = { [unowned coordinator] in coordinator.openSettings() }
        togglePause = { [unowned coordinator] in coordinator.togglePause() }
        enablePasting = { [unowned coordinator] in coordinator.enablePasting() }
        close = { [unowned coordinator] in coordinator.panelController.close(reason: "model") }
        pauseCapture = { [unowned coordinator] until in coordinator.pauseCapture(until: until) }
        resumeCapture = { [unowned coordinator] in coordinator.resumeCapture() }
        skipNextCopy = { [unowned coordinator] in coordinator.monitor.skipNextChange.toggle() }
        openAbout = { [unowned coordinator] in coordinator.openSettings(tab: .about) }
        clearSystemClipboard = { [unowned coordinator] in coordinator.clearSystemClipboard() }
        AppCoordinatorRegistry.shared = coordinator
    }
}

/// Lets loosely coupled helpers reach the coordinator without threading it everywhere.
@MainActor
enum AppCoordinatorRegistry {
    static weak var shared: AppCoordinator?
}
