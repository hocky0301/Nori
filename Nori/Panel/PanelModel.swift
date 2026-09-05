import AppKit
import KeyboardShortcuts
import Observation
import OSLog

/// Everything the panel shows and every key it understands, independent of SwiftUI.
@MainActor
@Observable
final class PanelModel {
    let history: HistoryStore
    let vault: SensitiveVault
    let settings: NoriSettings
    var actions = PanelActions()

    var query = "" { didSet { if query != oldValue { recompute(resetSelection: true); expandedID = nil } } }
    var filter: PanelFilter = .all { didSet { if filter != oldValue { recompute(resetSelection: true); expandedID = nil } } }
    private(set) var sections: [PanelSections.Section] = []
    var selectedID: UUID?
    /// The card showing its inline preview, if any.
    var expandedID: UUID?
    /// Current modifier bits, mirrored for the hint bar and keycaps.
    private(set) var modifierBits: ActionGrammar.Bits = []
    private(set) var isCycling = false
    var isOpen = false
    /// Incremented when the view should scroll to `selectedID`.
    private(set) var scrollRequest = 0
    /// Bottom toast text; nil when hidden.
    private(set) var toast: String?
    /// Ghost rows for copies that were deliberately not saved (max 5, newest first).
    private(set) var ghosts: [ClipRow] = []
    /// Shown once a day when pasting silently degraded to copying.
    var showsAccessibilityBanner = false
    /// Nori's own "Clear history?" confirmation, shown inside the panel.
    var isClearConfirmationVisible = false

    @ObservationIgnored private var cycleState: CycleState = .idle
    @ObservationIgnored private var lastKeyPressAt: Date = .distantPast
    @ObservationIgnored private var undoRecord: HistoryStore.UndoRecord?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var ghostsWereShown = false
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "panelmodel")

    private enum CycleState { case idle, opening, cycling }

    init(history: HistoryStore, vault: SensitiveVault, settings: NoriSettings) {
        self.history = history
        self.vault = vault
        self.settings = settings
        observeStores()
    }

    // MARK: Derived state

    var rows: [PanelSections.Row] { sections.flatMap(\.rows) }
    var isEmpty: Bool { rows.isEmpty }
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var selectedRow: PanelSections.Row? { rows.first { $0.id == selectedID } }
    var selectedClip: ClipRow? { selectedRow?.row }
    var selectedIndex: Int? { rows.firstIndex { $0.id == selectedID } }
    var historyIsEmpty: Bool { history.rows.isEmpty && vault.entries.isEmpty }
    var accessibilityTrusted: Bool { Paster.isTrusted }

    var isPaused: Bool {
        guard let until = settings.pausedUntil else { return false }
        return until > .now
    }

    /// Hotkey modifier glyphs for the cycle-mode hint ("⇧⌘").
    var hotkeyModifierGlyphs: String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) else { return "⇧⌘" }
        let glyphs = ActionGrammar.Bits(modifierFlags: shortcut.modifiers).glyphs
        return glyphs.isEmpty ? "⌃" : glyphs
    }

    var hintChips: [HintBarModel.Chip] {
        HintBarModel.chips(.init(
            bits: modifierBits,
            accessibilityTrusted: accessibilityTrusted,
            cycleMode: isCycling,
            hotkeyModifiers: hotkeyModifierGlyphs,
            selectedKind: selectedClip?.kind,
            hasSelection: selectedID != nil
        ))
    }

    /// Whether hover may move the selection (not right after a key press).
    var hoverSelectsRows: Bool { Date.now.timeIntervalSince(lastKeyPressAt) > 0.15 }

    func count(for filter: PanelFilter) -> Int {
        (history.rows + vault.rows).filter { filter.matches(kind: $0.kind) }.count
    }

    private func observeStores() {
        withObservationTracking {
            _ = history.version
            _ = vault.version
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                recompute(resetSelection: false)
                observeStores()
            }
        }
    }

    func recompute(resetSelection: Bool) {
        sections = PanelSections.build(
            history: history.rows, sensitive: vault.rows, ghosts: ghosts, filter: filter, query: query
        )
        if resetSelection || selectedRow == nil {
            selectedID = rows.first { !$0.row.isGhost }?.id
            scrollRequest += 1
        }
        if let expandedID, !rows.contains(where: { $0.id == expandedID }) {
            self.expandedID = nil
        }
    }

    // MARK: Panel lifecycle

    func panelWillOpen(preserveState: Bool = false) {
        isOpen = true
        if !preserveState {
            query = ""
            filter = .all
            expandedID = nil
            recompute(resetSelection: true)
        }
        modifierBits = ActionGrammar.Bits(modifierFlags: NSEvent.modifierFlags)
        toast = nil
        ghostsWereShown = !ghosts.isEmpty
        KeyboardShortcuts.disable(.togglePanel)
        cycleState = settings.cycleModeEnabled ? .opening : .idle
        isCycling = false
    }

    func panelDidClose() {
        isOpen = false
        cycleState = .idle
        isCycling = false
        isClearConfirmationVisible = false
        if ghostsWereShown {
            ghosts.removeAll()
            ghostsWereShown = false
        }
        KeyboardShortcuts.enable(.togglePanel)
    }

    // MARK: Ghost rows

    func addGhost(_ reason: GhostReason, at date: Date) {
        ghosts.insert(ClipRow.ghost(reason: reason.message, at: date), at: 0)
        if ghosts.count > 5 { ghosts.removeLast(ghosts.count - 5) }
        settings.recordNotSaved(on: date)
        recompute(resetSelection: false)
    }

    // MARK: Selection

    func select(id: UUID?, scroll: Bool = true) {
        guard selectedID != id else { return }
        selectedID = id
        if expandedID != nil, expandedID != id { expandedID = nil }
        if scroll { scrollRequest += 1 }
    }

    func hoverSelect(id: UUID) {
        guard hoverSelectsRows, rows.first(where: { $0.id == id })?.row.isGhost != true else { return }
        select(id: id, scroll: false)
    }

    func moveSelection(by delta: Int, wrap: Bool = false) {
        let selectable = rows.filter { !$0.row.isGhost }
        guard !selectable.isEmpty else { return }
        lastKeyPressAt = .now
        let current = selectable.firstIndex { $0.id == selectedID } ?? (delta > 0 ? -1 : selectable.count)
        var next = current + delta
        if wrap {
            next = (next + selectable.count) % selectable.count
        } else {
            next = min(max(next, 0), selectable.count - 1)
        }
        select(id: selectable[next].id)
    }

    func selectFirst() { lastKeyPressAt = .now; select(id: rows.first { !$0.row.isGhost }?.id) }
    func selectLast() { lastKeyPressAt = .now; select(id: rows.last { !$0.row.isGhost }?.id) }

    // MARK: Actions

    /// Enter / click / ⌘n resolved through the grammar.
    func perform(_ base: ActionGrammar.Base, bits: ActionGrammar.Bits, on id: UUID? = nil) {
        let targetID = id ?? selectedID
        guard let targetID, let clip = rows.first(where: { $0.id == targetID })?.row, !clip.isGhost else {
            if !query.isEmpty, id == nil {
                actions.copyText(query)
            }
            return
        }
        let action = ActionGrammar.resolve(base, bits, .init(accessibilityTrusted: accessibilityTrusted))
        if !action.isPaste, bits.contains(.copyOnly) == false, !accessibilityTrusted {
            settings.pasteBlockedByAccessibility = true
        }
        actions.perform(clip, action)
        if action.keepOpen, !action.isPaste {
            showToast("Copied")
        }
    }

    func deleteSelected() {
        guard let clip = selectedClip, let index = selectedIndex else { return }
        let nextID = rows[safe: index + 1]?.id ?? rows[safe: index - 1]?.id
        if clip.isSensitive {
            vault.remove(id: clip.id)
            undoRecord = nil
            recompute(resetSelection: false)
            select(id: nextID)
            return
        }
        undoRecord = history.delete(id: clip.id)
        recompute(resetSelection: false)
        select(id: nextID)
        showToast("Deleted · ⌘Z to undo")
    }

    func undoDelete() {
        guard let record = undoRecord else { return }
        undoRecord = nil
        let id = history.restore(record)
        recompute(resetSelection: false)
        select(id: id)
        toast = nil
    }

    func togglePinSelected() {
        guard let clip = selectedClip, !clip.isSensitive, !clip.isGhost else { return }
        history.togglePin(id: clip.id)
        recompute(resetSelection: false)
        select(id: clip.id)
    }

    func toggleExpanded() {
        guard let clip = selectedClip, !clip.isSensitive, !clip.isGhost else { return }
        expandedID = expandedID == clip.id ? nil : clip.id
        scrollRequest += 1
    }

    func openSelected() {
        guard let clip = selectedClip, !clip.isGhost else { return }
        actions.open(clip)
    }

    func revealSelected() {
        guard let clip = selectedClip, clip.kind == .file else { return }
        actions.reveal(clip)
    }

    func clearHistory(includingPinned: Bool) {
        let removed = history.clear(includingPinned: includingPinned)
        vault.removeAll()
        isClearConfirmationVisible = false
        recompute(resetSelection: true)
        showToast("Cleared \(removed) clips")
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
            self?.undoRecord = nil
        }
    }

    func close() { actions.close() }

    // MARK: Keyboard

    /// Route a key event. Returns true when the event was consumed.
    func handle(event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        default:
            return false
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        modifierBits = ActionGrammar.Bits(modifierFlags: flags)
        guard flags.isEmpty else { return false }
        switch cycleState {
        case .cycling:
            cycleState = .idle
            isCycling = false
            perform(.returnKey, bits: [])
            return true
        case .opening:
            cycleState = .idle
            return false
        case .idle:
            return false
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = PanelKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "")
        lastKeyPressAt = .now

        // While the Japanese/Chinese candidate window is open, every key belongs to the IME.
        if hasMarkedText() { return false }

        // Hotkey pressed again while open: cycle to the next item (hold the modifiers, tap the key).
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel),
           shortcut.carbonKeyCode == Int(event.keyCode),
           shortcut.modifiers.intersection(.deviceIndependentFlagsMask) == flags {
            if cycleState == .opening || cycleState == .cycling {
                cycleState = .cycling
                isCycling = true
                moveSelection(by: 1, wrap: true)
            } else {
                close()
            }
            return true
        }

        // In cycle mode the hotkey modifiers are still held, so ↑/↓ arrive with ⇧⌘ (or whatever the hotkey uses).
        if isCycling, key.special == .down { moveSelection(by: 1, wrap: true); return true }
        if isCycling, key.special == .up { moveSelection(by: -1, wrap: true); return true }

        if isClearConfirmationVisible {
            switch key.special {
            case .escape: isClearConfirmationVisible = false; return true
            case .return: clearHistory(includingPinned: flags.contains(.option)); return true
            default: return true
            }
        }

        switch (key.special, flags) {
        case (.escape, _):
            if cycleState == .cycling { cycleState = .idle; isCycling = false }
            close()
            return true
        case (.return, _):
            perform(.returnKey, bits: ActionGrammar.Bits(modifierFlags: flags))
            return true
        case (.down, []): moveSelection(by: 1); return true
        case (.up, []): moveSelection(by: -1); return true
        case (.down, [.command]), (.down, [.option]), (.end, _), (.pageDown, _): selectLast(); return true
        case (.up, [.command]), (.up, [.option]), (.home, _), (.pageUp, _): selectFirst(); return true
        case (.tab, []): filter = filter.next; return true
        case (.tab, [.shift]): filter = filter.previous; return true
        case (.space, []) where query.isEmpty: toggleExpanded(); return true
        case (.delete, [.command]), (.forwardDelete, [.command]): deleteSelected(); return true
        case (.delete, [.command, .shift]):
            isClearConfirmationVisible = true
            return true
        case (.delete, [.command, .shift, .option]):
            clearHistory(includingPinned: true)
            return true
        default: break
        }

        guard flags.contains(.command) || flags.contains(.control) else { return false }
        let char = key.characters.lowercased()

        if flags.contains(.command), !flags.contains(.control), let number = Int(char), (1...9).contains(number) {
            if let row = rows.first(where: { $0.number == number }) {
                select(id: row.id)
                perform(.number(number), bits: ActionGrammar.Bits(modifierFlags: flags), on: row.id)
            }
            return true
        }

        switch (char, flags) {
        case ("n", [.control]), ("j", [.control]): moveSelection(by: 1); return true
        case ("p", [.control]): moveSelection(by: -1); return true
        case ("k", [.control]) where selectedIndex != 0: moveSelection(by: -1); return true
        case ("p", [.command]): togglePinSelected(); return true
        case ("y", [.command]): toggleExpanded(); return true
        case ("o", [.command]): openSelected(); return true
        case ("r", [.command]): revealSelected(); return true
        case ("c", [.command]): perform(.returnKey, bits: [.copyOnly]); return true
        case ("z", [.command]): undoDelete(); return true
        case (",", [.command]): actions.openSettings(); return true
        case ("f", [.command]): actions.focusSearch(); return true
        case ("w", [.command]): close(); return true
        case ("v", [.command]): return true  // people mash ⌘V inside the panel; swallow it
        case ("u", [.control]): query = ""; return true
        case ("p", [.command, .shift]): actions.togglePause(); return true
        case ("q", [.command]): NSApp.terminate(nil); return true
        default:
            return false
        }
    }

    private func hasMarkedText() -> Bool {
        guard let client = NSApp.keyWindow?.firstResponder as? NSTextInputClient else { return false }
        return client.hasMarkedText()
    }
}

/// Closures the coordinator plugs in so the model never touches AppKit windows directly.
struct PanelActions {
    var perform: (ClipRow, ActionGrammar.Action) -> Void = { _, _ in }
    var copyText: (String) -> Void = { _ in }
    var open: (ClipRow) -> Void = { _ in }
    var reveal: (ClipRow) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var focusSearch: () -> Void = {}
    var togglePause: () -> Void = {}
    var enablePasting: () -> Void = {}
    var close: () -> Void = {}
}

/// Key codes we care about, decoded once.
struct PanelKey {
    enum Special { case escape, `return`, up, down, left, right, tab, delete, forwardDelete, home, end, pageUp, pageDown, space }

    let keyCode: UInt16
    let characters: String

    var special: Special? {
        switch keyCode {
        case 53: .escape
        case 36, 76: .return
        case 126: .up
        case 125: .down
        case 123: .left
        case 124: .right
        case 48: .tab
        case 51: .delete
        case 117: .forwardDelete
        case 115: .home
        case 119: .end
        case 116: .pageUp
        case 121: .pageDown
        case 49: .space
        default: nil
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
