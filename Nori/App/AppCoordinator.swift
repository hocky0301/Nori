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
    let monitor = ClipboardMonitor()
    let model: PanelModel
    private(set) var panelController: PanelController!
    private var statusItem: StatusItemController!
    private var settingsWindow: SettingsWindowController?
    #if DEBUG
    private var debugBridge: DebugBridge?
    #endif
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "app")

    init() {
        history = HistoryStore(context: storage.context)
        model = PanelModel(history: history, settings: settings)
    }

    func start() {
        history.maxItems = settings.maxItems
        history.load()

        monitor.policy = settings.capturePolicy
        monitor.isPaused = settings.isPaused
        monitor.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case let .captured(draft, _):
                let item = history.ingest(draft)
                if draft.kind == .image, settings.ocrImages {
                    ImageTextRecognizer.recognize(itemID: item.id, imageData: draft.data(forAny: PasteboardType.imageTypes)) { [weak self] id, text in
                        self?.history.updateSearchText(id: id, text: text)
                    }
                }
            case let .rejected(reason, _):
                if case let .fromNori(id) = reason, let id, let item = history.item(id: id) {
                    history.touch(item)
                }
            }
        }
        monitor.start(interval: settings.pollInterval)

        panelController = PanelController(settings: settings, rootView: PanelRootView(model: model))
        model.actions = PanelActions(coordinator: self)
        panelController.onWillOpen = { [weak self] in self?.model.panelWillOpen() }
        panelController.onDidClose = { [weak self] in self?.model.panelDidClose() }
        panelController.keyHandler = { [weak self] event in self?.model.handle(event: event) ?? false }

        statusItem = StatusItemController(coordinator: self)
        panelController.statusButton = statusItem.button

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }

        observeSettings()
        #if DEBUG
        debugBridge = DebugBridge(coordinator: self)
        #endif
        logger.info("Nori started with \(self.history.items.count) items")
    }

    func togglePanel() {
        panelController.toggle()
    }

    func openSettings(tab: SettingsTab = .general) {
        panelController.close()
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(coordinator: self)
        }
        settingsWindow?.show(tab: tab)
    }

    func willTerminate() {
        if settings.clearOnQuit {
            history.clear(includingPinned: false)
        }
    }

    // MARK: Actions used by the panel and status item

    /// Copy (and optionally paste) an item, then close the panel.
    func select(_ item: ClipItem, paste: Bool, plainText: Bool) {
        panelController.close()
        ClipboardWriter.write(item, plainTextOnly: plainText)
        monitor.markCurrentAsSeen()
        history.touch(item)
        if paste {
            if Paster.isTrusted {
                // Give the previous app a beat to become key again before ⌘V arrives.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Paster.sendPasteKeystroke()
                }
            } else {
                Paster.requestTrust()
            }
        }
        if settings.playSounds { NSSound(named: "Pop")?.play() }
    }

    func setPaused(_ paused: Bool) {
        settings.isPaused = paused
        monitor.isPaused = paused
        statusItem.refresh()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.pollInterval
            _ = settings.ignoredApps
            _ = settings.ignoredTypes
            _ = settings.ignoreRegexps
            _ = settings.captureImages
            _ = settings.captureFiles
            _ = settings.captureRichText
            _ = settings.recordOnlyListedApps
            _ = settings.maxItems
            _ = settings.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                monitor.policy = settings.capturePolicy
                monitor.start(interval: settings.pollInterval)
                history.maxItems = settings.maxItems
                statusItem.refresh()
                observeSettings()
            }
        }
    }
}
