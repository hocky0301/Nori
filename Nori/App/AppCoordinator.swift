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
        panelController.onWillOpen = { [weak self] preserving in
            guard let self else { return }
            monitor.poll()  // a copy made a moment before the hotkey must be in the list
            model.panelWillOpen(preserveState: preserving)
            showAccessibilityBannerIfNeeded()
        }
        panelController.onDidClose = { [weak self] in self?.model.panelDidClose() }
        panelController.keyHandler = { [weak self] event in self?.model.handle(event: event) ?? false }

        statusItem = StatusItemController(coordinator: self)
        panelController.statusButton = statusItem.button

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
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
            model.showToast("History could not be opened and was reset")
        }
        if !settings.hasCompletedOnboarding, !CommandLine.arguments.contains("--in-memory") {
            showOnboarding()
        }
        logger.info("Nori started with \(self.history.count) items")
    }

    private func handle(_ event: ClipboardMonitor.Event) {
        switch event {
        case let .captured(draft):
            let id = history.ingest(draft)
            if draft.kind == .image, settings.ocrImages {
                ImageTextRecognizer.recognize(itemID: id, imageData: draft.data(for: PasteboardType.png)) { [weak self] id, text in
                    self?.history.updateSearchText(id: id, text: text)
                }
            }
        case let .sensitive(sensitive):
            vault.add(sensitive)
        case let .ghost(reason, date):
            if settings.showGhostRows {
                model.addGhost(reason, at: date)
            } else {
                settings.recordNotSaved(on: date)
            }
        case let .promoted(id):
            if history.item(id: id) != nil {
                history.touch(id: id)
            } else if vault.entry(id: id) != nil {
                vault.touch(id: id)
            }
        case .rejected:
            break
        }
    }

    func togglePanel() {
        panelController.toggle()
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

        let keepOpen = action.keepOpen
        if action.isPaste || !keepOpen {
            panelController.close(reason: action.isPaste ? "paste" : "copy")
        }
        ClipboardWriter.write(contents: contents, id: clip.id, sourceBundleID: clip.sourceBundleID, plainTextOnly: action.plain)
        monitor.markCurrentAsSeen()

        guard action.isPaste else { return }
        // The panel must have resigned key before ⌘V is posted, or the keystroke lands on Nori itself.
        DispatchQueue.main.async { [weak self] in
            Paster.sendPasteKeystroke()
            if keepOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    self?.panelController.reopenPreservingState()
                }
            }
        }
    }

    func copyTypedText(_ text: String) {
        panelController.close(reason: "typed text")
        ClipboardWriter.write(string: text)
        // Captured as a brand-new text clip on the next poll.
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
        copyText = { [unowned coordinator] text in coordinator.copyTypedText(text) }
        open = { clip in ItemOpener.open(clip, contents: { AppCoordinatorRegistry.shared?.history.contents(id: clip.id) ?? [] }) }
        reveal = { clip in ItemOpener.reveal(clip) }
        openSettings = { [unowned coordinator] in coordinator.openSettings() }
        togglePause = { [unowned coordinator] in coordinator.togglePause() }
        enablePasting = { [unowned coordinator] in coordinator.enablePasting() }
        close = { [unowned coordinator] in coordinator.panelController.close(reason: "model") }
        AppCoordinatorRegistry.shared = coordinator
    }
}

/// Lets loosely coupled helpers reach the coordinator without threading it everywhere.
@MainActor
enum AppCoordinatorRegistry {
    static weak var shared: AppCoordinator?
}
