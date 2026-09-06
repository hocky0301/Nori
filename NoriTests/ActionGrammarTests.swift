import Testing
@testable import Nori

@Suite("ActionGrammar")
struct ActionGrammarTests {
    @Test func truthTable() {
        let trusted = ActionGrammar.Capabilities(accessibilityTrusted: true)
        let untrusted = ActionGrammar.Capabilities(accessibilityTrusted: false)
        for bits in ActionGrammar.Bits.all {
            let plain = bits.contains(.plain)
            let keepOpen = bits.contains(.keepOpen)
            for base in [ActionGrammar.Base.returnKey, .click] {
                let expected: ActionGrammar.Action = bits.contains(.copyOnly)
                    ? .copy(plain: plain, keepOpen: keepOpen) : .paste(plain: plain, keepOpen: keepOpen)
                #expect(ActionGrammar.resolve(base, bits, trusted) == expected, "\(base) \(bits)")
                #expect(ActionGrammar.resolve(base, bits, untrusted) == .copy(plain: plain, keepOpen: keepOpen), "\(base) \(bits) untrusted")
            }
            // The number row is triggered by ⌘, so ⌘ never means copy-only there.
            #expect(ActionGrammar.resolve(.number(3), bits, trusted) == .paste(plain: plain, keepOpen: keepOpen))
            #expect(ActionGrammar.resolve(.number(3), bits, untrusted) == .copy(plain: plain, keepOpen: keepOpen))
        }
    }

    @Test func verbs() {
        #expect(ActionGrammar.verb(for: .paste(plain: false, keepOpen: false)) == "Paste")
        #expect(ActionGrammar.verb(for: .paste(plain: true, keepOpen: true)) == "Paste plain, keep open")
        #expect(ActionGrammar.verb(for: .copy(plain: true, keepOpen: false)) == "Copy as plain text")
    }
}

@Suite("HintBarModel")
struct HintBarModelTests {
    private func chips(
        _ bits: ActionGrammar.Bits, trusted: Bool = true, cycle: Bool = false, kind: ClipKind? = .text,
        hasSelection: Bool = true, sensitive: Bool = false, query: String = ""
    ) -> [String] {
        HintBarModel.chips(.init(bits: bits, accessibilityTrusted: trusted, cycleMode: cycle,
                                 hotkeyModifiers: "⇧⌘", selectedKind: kind, hasSelection: hasSelection,
                                 isSensitive: sensitive, query: query))
            .map { "\($0.key) \($0.verb)" }
    }

    @Test func restingState() {
        #expect(chips([]) == ["↩ Paste", "⇧↩ Plain", "Space Preview", "⌘P Pin", "⌘⌫ Delete"])
    }

    @Test func commandHeldShowsOpenOnlyForOpenableKinds() {
        #expect(chips([.copyOnly], kind: .text) == ["⌘1–9 Paste item", "⌘↩ Copy", "⌘P Pin", "⌘Y Preview", "⌘⌫ Delete", "⌘⇧⌫ Clear…"])
        #expect(chips([.copyOnly], kind: .file).contains("⌘O Open"))
        #expect(chips([.copyOnly], kind: .file).contains("⌘R Reveal"))
        #expect(chips([.copyOnly], kind: .link).contains("⌘O Open"))
        #expect(!chips([.copyOnly], kind: .link).contains("⌘R Reveal"))
    }

    @Test func shiftAndOption() {
        #expect(chips([.plain]) == ["⇧↩ Paste as plain text", "⇧-click Same", "⇧⌘1–9 Paste item as plain text"])
        #expect(chips([.keepOpen]) == ["⌥↩ Paste and keep Nori open", "⌥-click Same", "⌥⌘1–9 Paste item, keep open"])
        #expect(chips([.plain, .copyOnly]) == ["⇧⌘↩ Copy as plain text", "⇧⌘1–9 Paste item as plain text"])
        #expect(chips([.keepOpen, .copyOnly]) == ["⌥⌘↩ Copy, keep open", "⌥⌘1–9 Paste item, keep open"])
        #expect(chips([.plain, .keepOpen]).first == "⌥⇧↩ Paste plain, keep open")
    }

    @Test func untrustedTurnsPasteIntoCopy() {
        let resting = HintBarModel.chips(.init(bits: [], accessibilityTrusted: false, cycleMode: false,
                                               hotkeyModifiers: "⇧⌘", selectedKind: .text, hasSelection: true))
        #expect(resting.first?.isWarning == true)
        #expect(resting.first?.verb.hasPrefix("Copy") == true)
        #expect(chips([.plain], trusted: false).first == "⇧↩ Copy as plain text")
    }

    @Test func cycleMode() {
        #expect(chips([.copyOnly, .plain], cycle: true) == ["Release ⇧⌘ to paste", "↑↓ Move", "Esc Cancel"])
        #expect(chips([.copyOnly, .plain], trusted: false, cycle: true).first == "Release ⇧⌘ to copy")
    }

    @Test func noSelectionPrintsOnlyWhatWorks() {
        #expect(chips([], kind: nil, hasSelection: false).isEmpty)
        #expect(chips([.copyOnly], kind: nil, hasSelection: false).isEmpty)
        #expect(chips([], kind: nil, hasSelection: false, query: "swift") == ["↩ Paste “swift” as text", "⌃U Clear"])
        #expect(chips([], trusted: false, kind: nil, hasSelection: false, query: "swift").first == "↩ Copy “swift” as text")
        #expect(chips([.keepOpen], kind: nil, hasSelection: false, query: "swift") == ["↩ Paste “swift” as text", "⌃U Clear"])
    }

    @Test func sensitiveRowsHaveNoPreviewPinOrKeepOpen() {
        #expect(chips([], sensitive: true) == ["↩ Paste", "⇧↩ Plain", "⌘⌫ Delete"])
        #expect(chips([.copyOnly], sensitive: true) == ["⌘1–9 Paste item", "⌘↩ Copy", "⌘⌫ Delete", "⌘⇧⌫ Clear…"])
        #expect(chips([.keepOpen], sensitive: true) == ["⌥⌘1–9 Paste item, keep open"])
        #expect(chips([.keepOpen, .copyOnly], sensitive: true) == ["⌥⌘1–9 Paste item, keep open"])
        #expect(chips([.plain, .keepOpen], sensitive: true) == ["⌥⇧⌘1–9 Paste plain, keep open (item)"])
        #expect(chips([.plain], sensitive: true) == chips([.plain]))
    }
}
