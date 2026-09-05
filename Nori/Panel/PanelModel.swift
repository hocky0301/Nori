import AppKit
import KeyboardShortcuts
import Observation
import OSLog

/// Everything the panel shows and every key it understands, independent of SwiftUI.
@MainActor
@Observable
final class PanelModel {
    struct Row: Identifiable, Equatable {
        let item: ClipItem
        var titleRanges: [Range<String.Index>]
        var id: UUID { item.id }
        static func == (lhs: Row, rhs: Row) -> Bool { lhs.item.id == rhs.item.id && lhs.titleRanges == rhs.titleRanges }
    }

    let history: HistoryStore
    let settings: NoriSettings
    var actions = PanelActions()

    var query = "" { didSet { if query != oldValue { recompute(resetSelection: true) } } }
    var filter: PanelFilter = .all { didSet { if filter != oldValue { recompute(resetSelection: true) } } }
    private(set) var pinnedRows: [Row] = []
    private(set) var recentRows: [Row] = []
    var selectedID: UUID?
    var isPreviewVisible: Bool
    /// True while the user navigates with keys; hover is ignored so the mouse does not steal the selection.
    var isKeyboardNavigating = true
    var isOpen = false
    /// Incremented when the view should scroll to `selectedID`.
    private(set) var scrollRequest = 0
    /// Set when Enter was pressed but pasting is impossible; the view shows a hint.
    var lastNotice: String?

    @ObservationIgnored private var cycleState: CycleState = .idle
    @ObservationIgnored private var lastHistoryVersion = -1
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "panelmodel")

    private enum CycleState { case idle, opening, cycling }

    init(history: HistoryStore, settings: NoriSettings) {
        self.history = history
        self.settings = settings
        isPreviewVisible = settings.showPreviewPane
        observeHistory()
    }

    // MARK: Derived state

    var rows: [Row] { pinnedRows + recentRows }
    var isEmpty: Bool { rows.isEmpty }
    var selectedRow: Row? { rows.first { $0.id == selectedID } }
    var selectedItem: ClipItem? { selectedRow?.item }
    var selectedIndex: Int? { rows.firstIndex { $0.id == selectedID } }
    var totalCount: Int { history.items.count }

    /// The `⌘n` shortcut number shown next to the first nine unpinned rows, if any.
    func quickNumber(for row: Row) -> Int? {
        guard let index = recentRows.firstIndex(where: { $0.id == row.id }), index < 9 else { return nil }
        return index + 1
    }

    private func observeHistory() {
        withObservationTracking {
            _ = history.version
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                recompute(resetSelection: false)
                observeHistory()
            }
        }
    }

    func recompute(resetSelection: Bool) {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        var pinned: [(Row, Double)] = []
        var recent: [(Row, Double)] = []

        for item in history.items where filter.matches(kind: item.kind, isPinned: item.isPinned) {
            guard let match = HistorySearch.match(query: query, title: item.title, searchText: item.searchText) else { continue }
            let row = Row(item: item, titleRanges: match.titleRanges)
            if item.isPinned, !searching, filter != .pinned {
                pinned.append((row, match.score))
            } else {
                recent.append((row, match.score))
            }
        }

        pinnedRows = pinned.map(\.0).sorted { ($0.item.pinnedAt ?? .distantPast) > ($1.item.pinnedAt ?? .distantPast) }
        if searching {
            // Stable sort: better score first, then recency.
            recentRows = recent.enumerated()
                .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
                .map(\.element.0)
        } else if filter == .pinned {
            recentRows = recent.map(\.0).sorted { ($0.item.pinnedAt ?? .distantPast) > ($1.item.pinnedAt ?? .distantPast) }
        } else {
            recentRows = recent.map(\.0)
        }

        if resetSelection || selectedRow == nil {
            selectedID = (recentRows.first ?? pinnedRows.first)?.id
            scrollRequest += 1
        }
    }

    // MARK: Panel lifecycle

    func panelWillOpen() {
        isOpen = true
        query = ""
        filter = .all
        isKeyboardNavigating = true
        lastNotice = nil
        recompute(resetSelection: true)
        KeyboardShortcuts.disable(.togglePanel)
        cycleState = .opening
    }

    func panelDidClose() {
        isOpen = false
        cycleState = .idle
        KeyboardShortcuts.enable(.togglePanel)
    }

    // MARK: Selection

    func select(id: UUID?, scroll: Bool = true) {
        selectedID = id
        if scroll { scrollRequest += 1 }
    }

    func moveSelection(by delta: Int, wrap: Bool = false) {
        guard !rows.isEmpty else { return }
        isKeyboardNavigating = true
        let current = selectedIndex ?? (delta > 0 ? -1 : rows.count)
        var next = current + delta
        if wrap {
            next = (next + rows.count) % rows.count
        } else {
            next = min(max(next, 0), rows.count - 1)
        }
        select(id: rows[next].id)
    }

    func selectFirst() { isKeyboardNavigating = true; select(id: rows.first?.id) }
    func selectLast() { isKeyboardNavigating = true; select(id: rows.last?.id) }

    // MARK: Actions

    enum Action {
        case primary, secondary, plain, plainSecondary
    }

    /// Enter → paste (or copy when pasting is disabled); ⌥Enter → the other one; ⇧ adds "as plain text".
    func perform(_ action: Action, on item: ClipItem? = nil) {
        guard let item = item ?? selectedItem else {
            if !query.isEmpty {
                actions.copyText(query)
            }
            return
        }
        let pasteByDefault = settings.pasteOnSelect
        let plainByDefault = settings.plainTextByDefault
        let (paste, plain): (Bool, Bool) = switch action {
        case .primary: (pasteByDefault, plainByDefault)
        case .secondary: (!pasteByDefault, plainByDefault)
        case .plain: (pasteByDefault, !plainByDefault)
        case .plainSecondary: (!pasteByDefault, !plainByDefault)
        }
        actions.select(item, paste, plain)
    }

    func deleteSelected() {
        guard let item = selectedItem, let index = selectedIndex else { return }
        let nextID = rows[safe: index + 1]?.id ?? rows[safe: index - 1]?.id
        history.delete(item)
        recompute(resetSelection: false)
        select(id: nextID)
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        history.togglePin(item)
        recompute(resetSelection: false)
        select(id: item.id)
    }

    func openSelected() {
        guard let item = selectedItem else { return }
        actions.open(item)
    }

    func togglePreview() {
        isPreviewVisible.toggle()
        settings.showPreviewPane = isPreviewVisible
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
        let released = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty
        guard released else { return false }
        switch cycleState {
        case .cycling:
            cycleState = .idle
            perform(.primary)
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

        // While the Japanese/Chinese candidate window is open, arrows and Return belong to the IME.
        if hasMarkedText(), [.up, .down, .return, .escape].contains(key.special) { return false }

        // Hotkey pressed again while open: cycle to the next item (Maccy-style "hold and tap").
        if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel),
           shortcut.carbonKeyCode == Int(event.keyCode),
           shortcut.modifiers.intersection(.deviceIndependentFlagsMask) == flags {
            if cycleState == .opening || cycleState == .cycling {
                cycleState = .cycling
                moveSelection(by: 1, wrap: true)
            } else {
                close()
            }
            return true
        }

        switch (key.special, flags) {
        case (.escape, []):
            if !query.isEmpty { query = "" } else { close() }
            return true
        case (.return, []): perform(.primary); return true
        case (.return, [.option]): perform(.secondary); return true
        case (.return, [.shift]): perform(.plain); return true
        case (.return, [.option, .shift]): perform(.plainSecondary); return true
        case (.down, []), (.down, [.numericPad]): moveSelection(by: 1); return true
        case (.up, []), (.up, [.numericPad]): moveSelection(by: -1); return true
        case (.down, [.command]), (.down, [.option]), (.end, _), (.pageDown, _): selectLast(); return true
        case (.up, [.command]), (.up, [.option]), (.home, _), (.pageUp, _): selectFirst(); return true
        case (.tab, []): filter = filter.next; return true
        case (.tab, [.shift]): filter = filter.previous; return true
        case (.delete, [.command]), (.forwardDelete, [.command]): deleteSelected(); return true
        default: break
        }

        guard flags.contains(.command) || flags.contains(.control) else { return false }
        let char = key.characters.lowercased()

        if flags == [.command], let number = Int(char), (1...9).contains(number) {
            if let row = recentRows[safe: number - 1] {
                select(id: row.id)
                perform(.primary, on: row.item)
            }
            return true
        }
        if flags == [.command, .option], let number = Int(char), (1...9).contains(number) {
            if let row = recentRows[safe: number - 1] { select(id: row.id); perform(.secondary, on: row.item) }
            return true
        }

        switch (char, flags) {
        case ("n", [.control]), ("j", [.control]): moveSelection(by: 1); return true
        case ("p", [.control]), ("k", [.control]): moveSelection(by: -1); return true
        case ("p", [.command]): togglePinSelected(); return true
        case ("y", [.command]): togglePreview(); return true
        case ("o", [.command]): openSelected(); return true
        case ("c", [.command]):
            if let item = selectedItem { actions.select(item, false, settings.plainTextByDefault) }
            return true
        case (",", [.command]): actions.openSettings(); return true
        case ("f", [.command]): actions.focusSearch(); return true
        case ("w", [.command]): close(); return true
        case ("u", [.control]): query = ""; return true
        case ("1"..."8", [.command, .shift]):
            if let index = Int(char), let chip = PanelFilter.allCases[safe: index - 1] { filter = chip }
            return true
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
    var select: (ClipItem, _ paste: Bool, _ plainText: Bool) -> Void = { _, _, _ in }
    var copyText: (String) -> Void = { _ in }
    var open: (ClipItem) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var focusSearch: () -> Void = {}
    var close: () -> Void = {}
}

extension PanelActions {
    @MainActor
    init(coordinator: AppCoordinator) {
        self.init()
        select = { [unowned coordinator] item, paste, plain in coordinator.select(item, paste: paste, plainText: plain) }
        copyText = { [unowned coordinator] text in
            coordinator.panelController.close()
            ClipboardWriter.write(string: text)
        }
        open = { item in ItemOpener.open(item) }
        openSettings = { [unowned coordinator] in coordinator.openSettings() }
        close = { [unowned coordinator] in coordinator.panelController.close() }
    }
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
