import AppKit
import Foundation
import Testing
@testable import Nori

/// The view model's selection, key map and mutations (§5), independent of SwiftUI.
@Suite("PanelModel", .serialized)
@MainActor
struct PanelModelTests {
    /// Five text rows, newest first: one … five.
    private func makeHarness(titles: [String] = ["five", "four", "three", "two", "one"]) -> PanelHarness {
        let harness = PanelHarness()
        harness.seed(titles)
        harness.open()
        return harness
    }

    // MARK: Selection

    @Test func openingSelectsRowOneAndResetsSearchState() {
        let harness = makeHarness()
        harness.model.query = "thr"
        harness.model.filter = .code
        harness.open()
        #expect(harness.model.query.isEmpty)
        #expect(harness.model.filter == .all)
        #expect(harness.visibleTitles == ["one", "two", "three", "four", "five"])
        #expect(harness.selectedTitle == "one")
        #expect(harness.model.isOpen)
    }

    @Test func arrowsMoveAndClampAtBothEnds() {
        let harness = makeHarness()
        harness.send(Keys.press(Keys.arrowUp))
        #expect(harness.selectedTitle == "one")
        harness.send(Keys.press(Keys.arrowDown))
        harness.send(Keys.press(Keys.arrowDown))
        #expect(harness.selectedTitle == "three")
        for _ in 0..<10 { harness.send(Keys.press(Keys.arrowDown)) }
        #expect(harness.selectedTitle == "five")
        harness.send(Keys.press(Keys.arrowUp))
        #expect(harness.selectedTitle == "four")
    }

    @Test func emacsBindingsAndFirstLastJumps() {
        let harness = makeHarness()
        harness.send(Keys.control("n"))
        harness.send(Keys.control("j"))
        #expect(harness.selectedTitle == "three")
        harness.send(Keys.control("p"))
        #expect(harness.selectedTitle == "two")
        harness.send(Keys.control("k"))
        #expect(harness.selectedTitle == "one")
        // ⌃K on row 1 is left to the search field (kill to end of line).
        #expect(!harness.send(Keys.control("k")))

        harness.send(Keys.press(Keys.end))
        #expect(harness.selectedTitle == "five")
        harness.send(Keys.press(Keys.home))
        #expect(harness.selectedTitle == "one")
        harness.send(Keys.press(Keys.arrowDown, flags: [.command]))
        #expect(harness.selectedTitle == "five")
        harness.send(Keys.press(Keys.arrowUp, flags: [.option]))
        #expect(harness.selectedTitle == "one")
    }

    @Test func moveSelectionWrapsOnlyWhenAsked() {
        let harness = makeHarness()
        harness.model.moveSelection(by: -1, wrap: true)
        #expect(harness.selectedTitle == "five")
        harness.model.moveSelection(by: 1, wrap: true)
        #expect(harness.selectedTitle == "one")
        harness.model.moveSelection(by: -1)
        #expect(harness.selectedTitle == "one")
    }

    @Test func ghostRowsAreNeverSelected() {
        let harness = makeHarness(titles: ["b", "a"])
        harness.model.addGhost(.concealed(appName: "1Password"), at: .now)
        #expect(harness.model.rows.first?.row.isGhost == true)
        #expect(harness.selectedTitle == "a")

        harness.model.selectFirst()
        #expect(harness.selectedTitle == "a")
        harness.send(Keys.press(Keys.arrowUp))
        #expect(harness.selectedTitle == "a")
        harness.send(Keys.press(Keys.home))
        #expect(harness.selectedTitle == "a")
        harness.send(Keys.press(Keys.arrowDown))
        #expect(harness.selectedTitle == "b")
        harness.model.moveSelection(by: 1, wrap: true)
        #expect(harness.selectedTitle == "a")

        // A ghost is not a paste target either.
        let ghostID = harness.model.rows.first!.id
        harness.model.perform(.click, bits: [], on: ghostID)
        #expect(harness.recorder.performed.isEmpty)
        #expect(harness.model.rows.first { $0.row.isGhost }?.number == nil)
    }

    @Test func hoverIsIgnoredRightAfterAKeyPress() {
        let harness = makeHarness()
        harness.send(Keys.press(Keys.arrowDown))
        #expect(harness.selectedTitle == "two")
        let last = harness.model.rows.last!.id
        harness.model.hoverSelect(id: last)
        #expect(harness.selectedTitle == "two")
        #expect(!harness.model.hoverSelectsRows)
    }

    @Test func recomputeKeepsSelectionAcrossHistoryChanges() {
        let harness = makeHarness()
        harness.send(Keys.press(Keys.arrowDown))
        let selected = harness.model.selectedID
        #expect(harness.selectedTitle == "two")

        harness.store.ingest(TestDrafts.text("six"), now: .now)
        harness.model.recompute(resetSelection: false)
        #expect(harness.visibleTitles.first == "six")
        #expect(harness.model.selectedID == selected)
        #expect(harness.model.selectedIndex == 2)

        // When the selected row vanishes, selection falls back to the first selectable row.
        harness.store.delete(id: selected!)
        harness.model.recompute(resetSelection: false)
        #expect(harness.selectedTitle == "six")
    }

    // MARK: Actions through the grammar

    @Test func enterVariantsResolveThroughTheGrammar() {
        let harness = makeHarness()
        let cases: [(NSEvent.ModifierFlags, ActionGrammar.Bits)] = [
            ([], []),
            ([.shift], [.plain]),
            ([.option], [.keepOpen]),
            ([.command], [.copyOnly]),
            ([.shift, .option], [.plain, .keepOpen]),
            ([.shift, .option, .command], [.plain, .keepOpen, .copyOnly]),
        ]
        for (flags, bits) in cases {
            harness.recorder.performed.removeAll()
            #expect(harness.send(Keys.press(Keys.returnKey, "\r", flags: flags)))
            let performed = harness.recorder.lastPerformed
            #expect(performed?.clip.title == "one")
            #expect(performed?.action == harness.expected(.returnKey, bits), "flags \(flags.rawValue)")
        }
        // Keypad ⌤ is Enter too, and ⌘C aliases ⌘↩.
        harness.recorder.performed.removeAll()
        harness.send(Keys.press(Keys.keypadEnter, "\u{3}"))
        #expect(harness.recorder.lastPerformed?.action == harness.expected(.returnKey, []))
        harness.send(Keys.command("c"))
        #expect(harness.recorder.lastPerformed?.action == harness.expected(.returnKey, [.copyOnly]))
        #expect(harness.recorder.lastPerformed?.action.isPaste == false)
    }

    @Test func copyOnlyWithKeepOpenToasts() {
        let harness = makeHarness()
        harness.send(Keys.press(Keys.returnKey, "\r", flags: [.command, .option]))
        #expect(harness.model.toast == "Copied")
    }

    @Test func commandNumbersTargetTheNumberedRow() {
        let harness = makeHarness()
        #expect(harness.send(Keys.command("3")))
        var performed = harness.recorder.lastPerformed
        #expect(performed?.clip.title == "three")
        #expect(performed?.action == harness.expected(.number(3), [.copyOnly]))
        #expect(performed?.action == harness.expected(.returnKey, []), "⌘ is the trigger, not copy-only")
        #expect(harness.selectedTitle == "three")

        #expect(harness.send(Keys.command("5", extra: [.shift])))
        performed = harness.recorder.lastPerformed
        #expect(performed?.clip.title == "five")
        #expect(performed?.action == harness.expected(.number(5), [.plain, .copyOnly]))
        #expect(performed?.action.plain == true)

        harness.send(Keys.command("1", extra: [.option]))
        #expect(harness.recorder.lastPerformed?.action.keepOpen == true)

        // No ninth row: consumed, nothing performed.
        harness.recorder.performed.removeAll()
        #expect(harness.send(Keys.command("9")))
        #expect(harness.recorder.performed.isEmpty)
        // Digits without ⌘ belong to the search field.
        #expect(!harness.send(Keys.press(0, "2")))
    }

    @Test func numbersSkipGhostRows() {
        let harness = makeHarness(titles: ["b", "a"])
        harness.model.addGhost(.imageTooLarge(bytes: 48 * 1024 * 1024), at: .now)
        harness.send(Keys.command("1"))
        #expect(harness.recorder.lastPerformed?.clip.title == "a")
        harness.send(Keys.command("2"))
        #expect(harness.recorder.lastPerformed?.clip.title == "b")
    }

    @Test func performWithNoSelectionCopiesTheQuery() {
        let harness = makeHarness()
        harness.model.query = "zzz-nothing-matches"
        #expect(harness.model.isEmpty)
        #expect(harness.model.selectedID == nil)
        harness.send(Keys.press(Keys.returnKey, "\r"))
        #expect(harness.recorder.copiedText == ["zzz-nothing-matches"])
        #expect(harness.recorder.performed.isEmpty)

        // An explicit target that does not exist never falls back to the query.
        harness.model.perform(.click, bits: [], on: UUID())
        #expect(harness.recorder.copiedText.count == 1)
    }

    @Test func escapeClosesAndCommandWClosesToo() {
        let harness = makeHarness()
        #expect(harness.send(Keys.press(Keys.escape)))
        #expect(harness.recorder.closeCount == 1)
        #expect(!harness.model.isOpen)
        harness.open()
        harness.send(Keys.command("w"))
        #expect(harness.recorder.closeCount == 2)
    }

    @Test func otherCommandKeysReachTheirClosures() {
        let harness = makeHarness()
        harness.send(Keys.command(","))
        harness.send(Keys.command("f"))
        harness.send(Keys.command("p", extra: [.shift]))
        #expect(harness.recorder.settingsCount == 1)
        #expect(harness.recorder.focusSearchCount == 1)
        #expect(harness.recorder.togglePauseCount == 1)
        // ⌘V is swallowed; a bare letter is not ours.
        #expect(harness.send(Keys.command("v")))
        #expect(!harness.send(Keys.press(0, "x")))
        #expect(harness.recorder.performed.isEmpty)
    }

    // MARK: Filters and search

    @Test func tabCyclesFilters() {
        let harness = makeHarness()
        harness.send(Keys.press(Keys.tab))
        #expect(harness.model.filter == .text)
        harness.send(Keys.press(Keys.tab, flags: [.shift]))
        #expect(harness.model.filter == .all)
        harness.send(Keys.press(Keys.tab, flags: [.shift]))
        #expect(harness.model.filter == .file)
        #expect(harness.model.isEmpty)
        for _ in 0..<PanelFilter.allCases.count { harness.send(Keys.press(Keys.tab)) }
        #expect(harness.model.filter == .file)
    }

    @Test func filterCountsAndEmptyState() {
        let harness = makeHarness()
        harness.store.ingest(TestDrafts.text("https://example.com/x"), now: .now)
        harness.model.recompute(resetSelection: true)
        #expect(harness.model.count(for: .all) == 6)
        #expect(harness.model.count(for: .link) == 1)
        #expect(harness.model.count(for: .image) == 0)
        harness.model.filter = .link
        #expect(harness.visibleTitles == ["https://example.com/x"])
        #expect(harness.selectedTitle == "https://example.com/x")
    }

    @Test func controlUClearsTheQuery() {
        let harness = makeHarness()
        harness.model.query = "fo"
        #expect(harness.model.isSearching)
        #expect(harness.visibleTitles == ["four"])
        #expect(harness.model.sections.map(\.title) == ["Results"])
        #expect(harness.send(Keys.control("u")))
        #expect(harness.model.query.isEmpty)
        #expect(harness.visibleTitles.count == 5)
        #expect(harness.selectedTitle == "one")
    }

    // MARK: Delete / undo / pin / expand

    @Test func commandDeleteThenUndoRestoresPinAndDates() throws {
        let harness = PanelHarness()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let pinnedID = harness.store.ingest(TestDrafts.text("pinned"), now: first)
        harness.store.touch(id: pinnedID, now: first.addingTimeInterval(60))
        harness.store.togglePin(id: pinnedID, now: first.addingTimeInterval(120))
        harness.seed(["b", "a"])
        harness.open()
        #expect(harness.visibleTitles == ["pinned", "a", "b"])
        let original = try #require(harness.model.selectedClip)
        #expect(original.title == "pinned")

        #expect(harness.send(Keys.press(Keys.delete, flags: [.command])))
        #expect(harness.visibleTitles == ["a", "b"])
        #expect(harness.selectedTitle == "a")
        #expect(harness.model.toast == "Deleted · ⌘Z to undo")

        #expect(harness.send(Keys.command("z")))
        #expect(harness.visibleTitles == ["pinned", "a", "b"])
        let restored = try #require(harness.model.selectedClip)
        #expect(restored.title == "pinned")
        #expect(restored.isPinned)
        #expect(restored.pinnedAt == original.pinnedAt)
        #expect(restored.firstCopiedAt == original.firstCopiedAt)
        #expect(restored.lastCopiedAt == original.lastCopiedAt)
        #expect(restored.copyCount == 2)
        #expect(harness.model.toast == nil)

        // Single-level buffer: a second ⌘Z is a no-op.
        harness.send(Keys.command("z"))
        #expect(harness.visibleTitles == ["pinned", "a", "b"])
    }

    @Test func deleteAtTheEndSelectsThePreviousRow() {
        let harness = makeHarness(titles: ["c", "b", "a"])
        harness.model.selectLast()
        harness.send(Keys.press(Keys.delete, flags: [.command]))
        #expect(harness.visibleTitles == ["a", "b"])
        #expect(harness.selectedTitle == "b")
    }

    @Test func deletingASensitiveRowHasNoUndo() {
        let harness = makeHarness(titles: ["a"])
        harness.vault.add(TestDrafts.sensitive("4111 1111 1111 1111"), now: .now)
        harness.model.recompute(resetSelection: true)
        harness.model.select(id: harness.vault.rows[0].id)
        #expect(harness.model.selectedClip?.isSensitive == true)
        harness.send(Keys.press(Keys.delete, flags: [.command]))
        #expect(harness.vault.entries.isEmpty)
        #expect(harness.model.toast == nil)
        harness.send(Keys.command("z"))
        #expect(harness.vault.entries.isEmpty)
        #expect(harness.visibleTitles == ["a"])
    }

    @Test func commandPPinsAndUnpinsButNeverASecret() {
        let harness = makeHarness(titles: ["b", "a"])
        harness.send(Keys.press(Keys.arrowDown))
        #expect(harness.selectedTitle == "b")
        #expect(harness.send(Keys.command("p")))
        #expect(harness.model.sections.map(\.title) == ["Pinned", "Today"])
        #expect(harness.visibleTitles == ["b", "a"])
        #expect(harness.model.selectedClip?.isPinned == true)
        #expect(harness.selectedTitle == "b")
        harness.send(Keys.command("p"))
        #expect(harness.model.selectedClip?.isPinned == false)
        #expect(harness.visibleTitles == ["a", "b"])

        harness.vault.add(TestDrafts.sensitive("AKIAIOSFODNN7EXAMPLE"), now: .now)
        harness.model.recompute(resetSelection: false)
        let secret = harness.vault.rows[0]
        harness.model.select(id: secret.id)
        let version = harness.store.version
        harness.send(Keys.command("p"))
        #expect(harness.store.version == version)
        #expect(harness.model.selectedClip?.isPinned == false)
        #expect(harness.model.sections.map(\.title) == ["Today"])
    }

    @Test func spaceTogglesPreviewOnlyWithAnEmptyQueryAndCommandYAlways() {
        let harness = makeHarness()
        let first = harness.model.selectedID
        #expect(harness.send(Keys.press(Keys.space, " ")))
        #expect(harness.model.expandedID == first)
        harness.send(Keys.press(Keys.space, " "))
        #expect(harness.model.expandedID == nil)

        harness.model.query = "one"
        #expect(harness.model.selectedID == first)
        #expect(!harness.send(Keys.press(Keys.space, " ")), "Space types into a non-empty search field")
        #expect(harness.model.expandedID == nil)
        #expect(harness.send(Keys.command("y")))
        #expect(harness.model.expandedID == first)

        // Moving the selection or editing the query collapses the preview.
        harness.model.query = "on"
        #expect(harness.model.expandedID == nil)
        harness.send(Keys.command("y"))
        harness.model.query = ""
        harness.send(Keys.press(Keys.arrowDown))
        #expect(harness.model.expandedID == nil)
    }

    @Test func secretsAndGhostsNeverExpand() {
        let harness = makeHarness(titles: ["a"])
        harness.vault.add(TestDrafts.sensitive("4111 1111 1111 1111"), now: .now)
        harness.model.recompute(resetSelection: true)
        harness.model.select(id: harness.vault.rows[0].id)
        harness.send(Keys.command("y"))
        #expect(harness.model.expandedID == nil)
    }

    // MARK: Ghosts, clear, toast

    @Test func addGhostCapsAtFiveAndCountsNotSaved() {
        let harness = makeHarness(titles: ["a"])
        let now = Date.now
        for index in 0..<7 {
            harness.model.addGhost(.concealed(appName: "App \(index)"), at: now.addingTimeInterval(Double(index)))
        }
        #expect(harness.model.ghosts.count == 5)
        #expect(harness.model.ghosts.first?.ghostReason == "Concealed item from App 6 wasn't saved")
        #expect(harness.model.ghosts.last?.ghostReason == "Concealed item from App 2 wasn't saved")
        #expect(harness.settings.notSavedCount == 7)
        #expect(harness.settings.notSavedToday(now: now) == 7)
        #expect(harness.model.rows.filter(\.row.isGhost).count == 5)
        #expect(harness.selectedTitle == "a")

        // Ghosts only live in the All filter and vanish once the panel that showed them closes.
        harness.model.filter = .text
        #expect(harness.model.rows.filter(\.row.isGhost).isEmpty)
        harness.model.filter = .all
        harness.open()
        harness.model.panelDidClose()
        #expect(harness.model.ghosts.isEmpty)
    }

    @Test func clearHistoryToastsTheCount() {
        let harness = makeHarness()
        let pinnedID = harness.model.rows[1].id
        harness.store.togglePin(id: pinnedID)
        harness.vault.add(TestDrafts.sensitive("4111 1111 1111 1111"), now: .now)
        harness.model.recompute(resetSelection: true)
        #expect(harness.model.rows.count == 6)

        #expect(harness.send(Keys.press(Keys.delete, flags: [.command, .shift])))
        #expect(harness.model.isClearConfirmationVisible)
        // Any other key is swallowed by the sheet; Esc dismisses it.
        let selectedBefore = harness.model.selectedID
        #expect(harness.send(Keys.press(Keys.arrowDown)))
        #expect(harness.model.selectedID == selectedBefore)
        harness.send(Keys.press(Keys.escape))
        #expect(!harness.model.isClearConfirmationVisible)
        #expect(harness.recorder.closeCount == 0)

        harness.send(Keys.press(Keys.delete, flags: [.command, .shift]))
        harness.send(Keys.press(Keys.returnKey, "\r"))
        #expect(harness.model.toast == "Cleared 4 clips")
        #expect(harness.visibleTitles == ["two"])
        #expect(harness.vault.entries.isEmpty, "clearing history empties the vault too")
        #expect(!harness.model.isClearConfirmationVisible)

        harness.send(Keys.press(Keys.delete, flags: [.command, .shift, .option]))
        #expect(harness.model.toast == "Cleared 1 clips")
        #expect(harness.model.isEmpty)
        #expect(harness.model.historyIsEmpty)
    }

    @Test func hintChipsFollowModifiersAndSelection() {
        let harness = makeHarness()
        harness.store.ingest(TestDrafts.text("https://nori.example/docs"), now: .now)
        harness.model.recompute(resetSelection: true)
        #expect(harness.model.selectedClip?.kind == .link)
        harness.send(Keys.flags([.command]))
        #expect(harness.model.hintChips.contains(.init(key: "⌘O", verb: "Open")))
        harness.send(Keys.flags([]))
        #expect(harness.model.hintChips.first?.key == "↩")
        harness.send(Keys.command("o"))
        #expect(harness.recorder.opened.map(\.title) == ["https://nori.example/docs"])
        harness.send(Keys.command("r"))
        #expect(harness.recorder.revealed.isEmpty, "⌘R is files only")
    }
}
