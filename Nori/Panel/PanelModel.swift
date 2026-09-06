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

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            selectionIsPristine = false
            recompute(resetSelection: true)
            expandedID = nil
        }
    }
    var filter: PanelFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            selectionIsPristine = false
            recompute(resetSelection: true)
            expandedID = nil
            if filter == .all, isOpen, !ghosts.isEmpty { ghostsWereShown = true }
        }
    }
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
    /// Incremented when the search field should take focus and select its text (⌘F).
    private(set) var focusSearchRequest = 0
    func requestSearchFocus() { focusSearchRequest += 1 }
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
    /// True until the user moves the selection after an open, so a capture that lands a moment
    /// after the hotkey (the open-time poll classifies asynchronously) still becomes row 1.
    @ObservationIgnored private var selectionIsPristine = false
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

    /// Hotkey modifier glyphs for the cycle-mode hint, in the macOS order ("⌃⌥⇧⌘").
    var hotkeyModifierGlyphs: String {
        let modifiers = KeyboardShortcuts.getShortcut(for: .togglePanel)?.modifiers ?? [.shift, .command]
        var glyphs = ""
        if modifiers.contains(.control) { glyphs += "⌃" }
        if modifiers.contains(.option) { glyphs += "⌥" }
        if modifiers.contains(.shift) { glyphs += "⇧" }
        if modifiers.contains(.command) { glyphs += "⌘" }
        return glyphs
    }

    var hintChips: [HintBarModel.Chip] {
        HintBarModel.chips(.init(
            bits: modifierBits,
            accessibilityTrusted: accessibilityTrusted,
            cycleMode: isCycling,
            hotkeyModifiers: hotkeyModifierGlyphs,
            selectedKind: selectedClip?.kind,
            hasSelection: selectedRow != nil,
            isSensitive: selectedClip?.isSensitive == true,
            query: query.trimmingCharacters(in: .whitespaces)
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
        if resetSelection || selectedRow == nil || (selectionIsPristine && !isSearching) {
            let first = rows.first { !$0.row.isGhost }?.id
            if resetSelection || selectedID != first {
                selectedID = first
                scrollRequest += 1
            }
        }
        if let expandedID, !rows.contains(where: { $0.id == expandedID }) {
            self.expandedID = nil
        }
    }

    // MARK: Panel lifecycle

    /// `viaHotkey` is true only when the global hotkey opened the panel (its modifiers are still
    /// held), which is the only way into cycle mode; every other open makes the hotkey a plain toggle.
    func panelWillOpen(preserveState: Bool = false, viaHotkey: Bool = false) {
        isOpen = true
        if !preserveState {
            query = ""
            filter = .all
            expandedID = nil
            selectionIsPristine = true
            recompute(resetSelection: true)
        }
        modifierBits = ActionGrammar.Bits(modifierFlags: NSEvent.modifierFlags)
        toast = nil
        ghostsWereShown = !ghosts.isEmpty && filter == .all
        KeyboardShortcuts.disable(.togglePanel)
        cycleState = settings.cycleModeEnabled && viaHotkey ? .opening : .idle
        isCycling = false
    }

    /// `willReopen` is set for the close that precedes a keep-open reopen: the ghost rows on
    /// screen a moment ago stay until the panel really goes away.
    func panelDidClose(willReopen: Bool = false) {
        isOpen = false
        cycleState = .idle
        isCycling = false
        isClearConfirmationVisible = false
        if ghostsWereShown, !willReopen {
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
        if isOpen, filter == .all { ghostsWereShown = true }
        recompute(resetSelection: false)
    }

    // MARK: Selection

    func select(id: UUID?, scroll: Bool = true) {
        guard selectedID != id else { return }
        selectionIsPristine = false
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
        let action = resolve(base, bits)
        guard let targetID, let clip = rows.first(where: { $0.id == targetID })?.row, !clip.isGhost else {
            // No matches for a typed query: ↩ pastes the query itself as plain text.
            if !query.isEmpty, id == nil {
                actions.pasteTypedText(query, action)
                if action.keepOpen, !action.isPaste { showToast(String(localized: "Copied")) }
            }
            return
        }
        actions.perform(clip, action)
        if action.keepOpen, !action.isPaste {
            showToast(String(localized: "Copied"))
        }
    }

    /// The grammar's answer for the live Accessibility state; a paste that degraded to a copy
    /// arms the once-a-day drift banner.
    private func resolve(_ base: ActionGrammar.Base, _ bits: ActionGrammar.Bits) -> ActionGrammar.Action {
        let action = ActionGrammar.resolve(base, bits, .init(accessibilityTrusted: accessibilityTrusted))
        let wouldPaste = ActionGrammar.resolve(base, bits, .init(accessibilityTrusted: true)).isPaste
        if wouldPaste, !action.isPaste {
            settings.pasteBlockedByAccessibility = true
        }
        return action
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
        showToast(String(localized: "Deleted · ⌘Z to undo"))
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
        let removed = history.clear(includingPinned: includingPinned) + vault.entries.count
        vault.removeAll()
        if settings.clearSystemClipboardOnClear {
            actions.clearSystemClipboard()
        }
        isClearConfirmationVisible = false
        recompute(resetSelection: true)
        showToast(String(inflected: "Cleared ^[\(removed) clip](inflect: true)"))
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

    // MARK: UI helpers

    /// "⇧⌘V" — the live hotkey, for the empty state.
    var hotkeyDisplay: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "⇧⌘V"
    }

    /// When capture resumes: nil = capturing, `.distantFuture` = until resumed.
    var pausedUntil: Date? { isPaused ? settings.pausedUntil : nil }

    /// "Expires in 8m" for sensitive cards.
    static func expiresText(_ date: Date, now: Date = .now) -> String {
        let seconds = max(date.timeIntervalSince(now), 0)
        if seconds < 60 { return String(localized: "Expires in <1m") }
        let minutes = Int((seconds / 60).rounded(.up))
        return String(localized: "Expires in \(minutes)m")
    }

    func showClearConfirmation() {
        isClearConfirmationVisible = true
    }

    #if DEBUG
    /// Lets the debug bridge screenshot the ⌘ / ⇧ / ⌥ hint-bar states without a hand on the keyboard.
    func debugSetModifierBits(_ bits: ActionGrammar.Bits) {
        modifierBits = bits
    }
    #endif

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
        case (.delete, [.command, .shift]), (.delete, [.command, .shift, .option]):
            // Both chords land on the confirmation; the sheet reads ⌥ live and only ↩ commits.
            isClearConfirmationVisible = true
            return true
        default: break
        }

        guard flags.contains(.command) || flags.contains(.control) else { return false }
        let char = key.characters.lowercased()

        // The number row is matched on key code: ⇧ changes the character ("%" for ⇧5 on US,
        // "&é\"'(" without ⇧ on AZERTY), and the keypad counts too.
        if flags.contains(.command), !flags.contains(.control), let number = key.number {
            if let row = rows.first(where: { $0.number == number }) {
                select(id: row.id)
                perform(.number(number), bits: ActionGrammar.Bits(modifierFlags: flags), on: row.id)
            }
            return true
        }

        // ⌘C with a text selection in the search field or an expanded preview: native copy wins.
        if char == "c", flags == [.command], hasTextSelection() { return false }

        switch (char, flags) {
        case ("n", [.control]), ("j", [.control]): moveSelection(by: 1); return true
        case ("p", [.control]): moveSelection(by: -1); return true
        case ("k", [.control]) where selectedID != nil && selectedID != firstSelectableID: moveSelection(by: -1); return true
        case ("p", [.command]): togglePinSelected(); return true
        case ("y", [.command]): toggleExpanded(); return true
        case ("o", [.command]): openSelected(); return true
        case ("r", [.command]): revealSelected(); return true
        case ("c", [.command]):
            // Alias of ⌘↩; never a fallback that copies the typed query.
            if selectedRow != nil { perform(.returnKey, bits: [.copyOnly]) }
            return true
        case ("z", [.command]): undoDelete(); return true
        case (",", [.command]): actions.openSettings(); return true
        case ("f", [.command]): requestSearchFocus(); return true
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

    private func hasTextSelection() -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return textView.selectedRange().length > 0
    }

    /// The first card (ghost rows are never selectable), for ⌃K's "unless row 1 is selected".
    private var firstSelectableID: UUID? { rows.first { !$0.row.isGhost }?.id }
}

/// Closures the coordinator plugs in so the model never touches AppKit windows directly.
struct PanelActions {
    var perform: (ClipRow, ActionGrammar.Action) -> Void = { _, _ in }
    /// No-match ↩: the typed query goes through the same paste path as a clip.
    var pasteTypedText: (String, ActionGrammar.Action) -> Void = { _, _ in }
    var open: (ClipRow) -> Void = { _ in }
    var reveal: (ClipRow) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var togglePause: () -> Void = {}
    /// "Clearing history also clears the system clipboard".
    var clearSystemClipboard: () -> Void = {}
    var enablePasting: () -> Void = {}
    var close: () -> Void = {}
    // Search-row menu (additive, wired by the coordinator).
    var pauseCapture: (Date) -> Void = { _ in }
    var resumeCapture: () -> Void = {}
    var skipNextCopy: () -> Void = {}
    var openAbout: () -> Void = {}
}

/// Key codes we care about, decoded once.
struct PanelKey {
    enum Special { case escape, `return`, up, down, left, right, tab, delete, forwardDelete, home, end, pageUp, pageDown, space }

    let keyCode: UInt16
    let characters: String

    /// 1…9 for the number row (kVK_ANSI_1…9) and the keypad, independent of layout and ⇧.
    var number: Int? {
        switch keyCode {
        case 18, 83: 1
        case 19, 84: 2
        case 20, 85: 3
        case 21, 86: 4
        case 23, 87: 5
        case 22, 88: 6
        case 26, 89: 7
        case 28, 91: 8
        case 25, 92: 9
        default: nil
        }
    }

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
