import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts
import Testing
@testable import Nori

/// Records every closure the model fires so tests can assert on the exact `Action` it resolved.
@MainActor
final class ActionRecorder {
    var performed: [(clip: ClipRow, action: ActionGrammar.Action)] = []
    var copiedText: [String] = []
    var opened: [ClipRow] = []
    var revealed: [ClipRow] = []
    var closeCount = 0
    var settingsCount = 0
    var focusSearchCount = 0
    var togglePauseCount = 0

    var lastPerformed: (clip: ClipRow, action: ActionGrammar.Action)? { performed.last }

    func actions(closingModel model: PanelModel) -> PanelActions {
        var actions = PanelActions()
        actions.perform = { [unowned self] clip, action in performed.append((clip, action)) }
        actions.copyText = { [unowned self] text in copiedText.append(text) }
        actions.open = { [unowned self] clip in opened.append(clip) }
        actions.reveal = { [unowned self] clip in revealed.append(clip) }
        actions.openSettings = { [unowned self] in settingsCount += 1 }
        actions.focusSearch = { [unowned self] in focusSearchCount += 1 }
        actions.togglePause = { [unowned self] in togglePauseCount += 1 }
        // The real controller calls `panelDidClose` when the window goes away; mirror that.
        actions.close = { [unowned self, unowned model] in
            closeCount += 1
            model.panelDidClose()
        }
        return actions
    }
}

/// A `PanelModel` over the shared in-memory store, a fresh vault and throw-away settings.
///
/// Suites using it must be `.serialized` because `Storage.shared` is process-wide.
@MainActor
final class PanelHarness {
    let store: HistoryStore
    let vault: SensitiveVault
    let settings: NoriSettings
    let model: PanelModel
    let recorder: ActionRecorder
    let suiteName: String

    init() {
        suiteName = "tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        settings = NoriSettings(defaults: defaults)
        store = HistoryStore(context: Storage.shared.context)
        store.load()
        store.clear(includingPinned: true)
        vault = SensitiveVault()
        recorder = ActionRecorder()
        model = PanelModel(history: store, vault: vault, settings: settings)
        model.actions = recorder.actions(closingModel: model)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// The capabilities the model resolves with right now (Accessibility trust is read from the OS).
    var caps: ActionGrammar.Capabilities { .init(accessibilityTrusted: model.accessibilityTrusted) }

    func expected(_ base: ActionGrammar.Base, _ bits: ActionGrammar.Bits) -> ActionGrammar.Action {
        ActionGrammar.resolve(base, bits, caps)
    }

    /// Ingest plain-text drafts, oldest first, so `titles.last` becomes row 1.
    @discardableResult
    func seed(_ titles: [String], startingAt start: Date = .now.addingTimeInterval(-600)) -> [UUID] {
        titles.enumerated().map { offset, title in
            store.ingest(TestDrafts.text(title), now: start.addingTimeInterval(Double(offset) * 60))
        }
    }

    func open() {
        model.panelWillOpen()
    }

    var visibleTitles: [String] { model.rows.map(\.row.title) }
    var selectedTitle: String? { model.selectedClip?.title }

    @discardableResult
    func send(_ event: NSEvent) -> Bool { model.handle(event: event) }
}

enum TestDrafts {
    static func text(_ text: String, app: String? = nil) -> ClipDraft {
        var draft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.utf8PlainText, data: Data(text.utf8))])!
        draft.sourceBundleID = app
        return draft
    }

    static func sensitive(_ text: String) -> SensitiveDraft {
        let draft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.utf8PlainText, data: Data(text.utf8))])!
        let match = SecretDetector.detect(in: text) ?? .cardNumber
        return SensitiveDraft(match: match, mask: SecretDetector.mask(text), draft: draft)
    }
}

/// Synthesized key events, matched on key code like the real local monitor.
enum Keys {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let arrowUp: UInt16 = 126
    static let arrowDown: UInt16 = 125
    static let tab: UInt16 = 48
    static let delete: UInt16 = 51
    static let home: UInt16 = 115
    static let end: UInt16 = 119
    static let space: UInt16 = 49
    static let v: UInt16 = UInt16(kVK_ANSI_V)

    static func press(_ keyCode: UInt16, _ characters: String = "", flags: NSEvent.ModifierFlags = [], isARepeat: Bool = false) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: isARepeat, keyCode: keyCode
        )!
    }

    /// A `.flagsChanged` event carrying the modifiers that are (still) held.
    static func flags(_ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 0
        )!
    }

    /// ⌘ + letter, as the monitor sees it (`charactersIgnoringModifiers` is the bare letter).
    static func command(_ letter: String, extra: NSEvent.ModifierFlags = []) -> NSEvent {
        press(0, letter, flags: NSEvent.ModifierFlags.command.union(extra))
    }

    static func control(_ letter: String) -> NSEvent {
        press(0, letter, flags: [.control])
    }

    /// The panel hotkey as currently configured (⌘⇧V by default), pressed again while the panel is open.
    @MainActor
    static func hotkey() -> NSEvent {
        let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
        let keyCode = shortcut.map { UInt16($0.carbonKeyCode) } ?? v
        let modifiers = shortcut?.modifiers.intersection(.deviceIndependentFlagsMask) ?? [.command, .shift]
        return press(keyCode, "v", flags: modifiers, isARepeat: true)
    }

    @MainActor
    static var hotkeyModifiers: NSEvent.ModifierFlags {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.modifiers.intersection(.deviceIndependentFlagsMask) ?? [.command, .shift]
    }
}
