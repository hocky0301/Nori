import Foundation

/// What the hint bar shows for the current modifier state. Pure, so it is tested as a table
/// and can never disagree with `ActionGrammar`.
enum HintBarModel {
    struct Chip: Equatable, Sendable {
        var key: String
        var verb: String
        /// True for the "enable pasting" chip that opens System Settings when clicked.
        var isWarning = false
    }

    struct Input: Sendable {
        var bits: ActionGrammar.Bits
        var accessibilityTrusted: Bool
        var cycleMode: Bool
        /// The hotkey's modifier glyphs (for cycle mode), e.g. "⇧⌘".
        var hotkeyModifiers: String
        var selectedKind: ClipKind?
        var hasSelection: Bool
    }

    static func chips(_ input: Input) -> [Chip] {
        if input.cycleMode {
            return [
                Chip(key: "Release \(input.hotkeyModifiers)", verb: "to paste"),
                Chip(key: "↑↓", verb: "Move"),
                Chip(key: "Esc", verb: "Cancel"),
            ]
        }

        let caps = ActionGrammar.Capabilities(accessibilityTrusted: input.accessibilityTrusted)
        let pasteWord = input.accessibilityTrusted ? "Paste" : "Copy"
        var chips: [Chip] = []

        let bits = input.bits
        if bits.isEmpty {
            if input.accessibilityTrusted {
                chips.append(Chip(key: "↩", verb: "Paste"))
            } else {
                chips.append(Chip(key: "↩", verb: "Copy · Enable pasting →", isWarning: true))
            }
            chips.append(Chip(key: "⇧↩", verb: "Plain"))
            chips.append(Chip(key: "⌥↩", verb: "Keep open"))
            chips.append(Chip(key: "⌘↩", verb: "Copy"))
            chips.append(Chip(key: "Space", verb: "Preview"))
            chips.append(Chip(key: "⌘P", verb: "Pin"))
            chips.append(Chip(key: "⌘⌫", verb: "Delete"))
        } else if bits == [.copyOnly] {
            chips.append(Chip(key: "⌘1–9", verb: "\(pasteWord) item"))
            chips.append(Chip(key: "⌘↩", verb: "Copy"))
            chips.append(Chip(key: "⌘P", verb: "Pin"))
            chips.append(Chip(key: "⌘Y", verb: "Preview"))
            if input.selectedKind == .link || input.selectedKind == .file || input.selectedKind == .image {
                chips.append(Chip(key: "⌘O", verb: "Open"))
            }
            if input.selectedKind == .file {
                chips.append(Chip(key: "⌘R", verb: "Reveal"))
            }
            chips.append(Chip(key: "⌘⌫", verb: "Delete"))
            chips.append(Chip(key: "⌘⇧⌫", verb: "Clear…"))
        } else if bits == [.plain] {
            chips.append(Chip(key: "⇧↩", verb: "\(pasteWord) as plain text"))
            chips.append(Chip(key: "⇧-click", verb: "Same"))
            chips.append(Chip(key: "⇧⌘1–9", verb: "\(pasteWord) item as plain text"))
        } else if bits == [.keepOpen] {
            chips.append(Chip(key: "⌥↩", verb: "\(pasteWord) and keep Nori open"))
            chips.append(Chip(key: "⌥-click", verb: "Same"))
            chips.append(Chip(key: "⌥⌘1–9", verb: "\(pasteWord) item, keep open"))
        } else if bits == [.plain, .copyOnly] {
            chips.append(Chip(key: "⇧⌘↩", verb: "Copy as plain text"))
            chips.append(Chip(key: "⇧⌘1–9", verb: "\(pasteWord) item as plain text"))
        } else if bits == [.keepOpen, .copyOnly] {
            chips.append(Chip(key: "⌥⌘↩", verb: "Copy, keep open"))
            chips.append(Chip(key: "⌥⌘1–9", verb: "\(pasteWord) item, keep open"))
        } else {
            // ⇧⌥ with or without ⌘: show the stacked result.
            let action = ActionGrammar.resolve(.returnKey, bits, caps)
            chips.append(Chip(key: "\(bits.glyphs)↩", verb: ActionGrammar.verb(for: action)))
            let numberAction = ActionGrammar.resolve(.number(1), bits, caps)
            chips.append(Chip(key: "\(bits.glyphs.replacingOccurrences(of: "⌘", with: ""))⌘1–9", verb: ActionGrammar.verb(for: numberAction) + " (item)"))
        }
        return chips
    }
}
