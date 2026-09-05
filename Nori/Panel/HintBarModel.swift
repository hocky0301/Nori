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
                Chip(key: String(localized: "Release \(input.hotkeyModifiers)"), verb: String(localized: "to paste")),
                Chip(key: "↑↓", verb: String(localized: "Move")),
                Chip(key: String(localized: "Esc"), verb: String(localized: "Cancel")),
            ]
        }

        let caps = ActionGrammar.Capabilities(accessibilityTrusted: input.accessibilityTrusted)
        let trusted = input.accessibilityTrusted
        var chips: [Chip] = []

        let bits = input.bits
        if bits.isEmpty {
            if trusted {
                chips.append(Chip(key: "↩", verb: String(localized: "Paste")))
            } else {
                chips.append(Chip(key: "↩", verb: String(localized: "Copy · Enable pasting →"), isWarning: true))
            }
            // Resting state stays short on purpose; ⌥ and ⌘ variants appear while those keys are held.
            chips.append(Chip(key: "⇧↩", verb: String(localized: "Plain")))
            chips.append(Chip(key: String(localized: "Space"), verb: String(localized: "Preview")))
            chips.append(Chip(key: "⌘P", verb: String(localized: "Pin")))
            chips.append(Chip(key: "⌘⌫", verb: String(localized: "Delete")))
        } else if bits == [.copyOnly] {
            chips.append(Chip(key: "⌘1–9", verb: trusted ? String(localized: "Paste item") : String(localized: "Copy item")))
            chips.append(Chip(key: "⌘↩", verb: String(localized: "Copy")))
            chips.append(Chip(key: "⌘P", verb: String(localized: "Pin")))
            chips.append(Chip(key: "⌘Y", verb: String(localized: "Preview")))
            if input.selectedKind == .link || input.selectedKind == .file || input.selectedKind == .image {
                chips.append(Chip(key: "⌘O", verb: String(localized: "Open")))
            }
            if input.selectedKind == .file {
                chips.append(Chip(key: "⌘R", verb: String(localized: "Reveal")))
            }
            chips.append(Chip(key: "⌘⌫", verb: String(localized: "Delete")))
            chips.append(Chip(key: "⌘⇧⌫", verb: String(localized: "Clear…")))
        } else if bits == [.plain] {
            chips.append(Chip(key: "⇧↩", verb: trusted ? String(localized: "Paste as plain text") : String(localized: "Copy as plain text")))
            chips.append(Chip(key: String(localized: "⇧-click"), verb: String(localized: "Same")))
            chips.append(Chip(key: "⇧⌘1–9", verb: trusted ? String(localized: "Paste item as plain text") : String(localized: "Copy item as plain text")))
        } else if bits == [.keepOpen] {
            chips.append(Chip(key: "⌥↩", verb: trusted ? String(localized: "Paste and keep Nori open") : String(localized: "Copy and keep Nori open")))
            chips.append(Chip(key: String(localized: "⌥-click"), verb: String(localized: "Same")))
            chips.append(Chip(key: "⌥⌘1–9", verb: trusted ? String(localized: "Paste item, keep open") : String(localized: "Copy item, keep open")))
        } else if bits == [.plain, .copyOnly] {
            chips.append(Chip(key: "⇧⌘↩", verb: String(localized: "Copy as plain text")))
            chips.append(Chip(key: "⇧⌘1–9", verb: trusted ? String(localized: "Paste item as plain text") : String(localized: "Copy item as plain text")))
        } else if bits == [.keepOpen, .copyOnly] {
            chips.append(Chip(key: "⌥⌘↩", verb: String(localized: "Copy, keep open")))
            chips.append(Chip(key: "⌥⌘1–9", verb: trusted ? String(localized: "Paste item, keep open") : String(localized: "Copy item, keep open")))
        } else {
            // ⇧⌥ with or without ⌘: show the stacked result.
            let action = ActionGrammar.resolve(.returnKey, bits, caps)
            chips.append(Chip(key: "\(bits.glyphs)↩", verb: ActionGrammar.verb(for: action)))
            let numberAction = ActionGrammar.resolve(.number(1), bits, caps)
            let numberVerb = ActionGrammar.verb(for: numberAction)
            chips.append(Chip(key: "\(bits.glyphs.replacingOccurrences(of: "⌘", with: ""))⌘1–9", verb: String(localized: "\(numberVerb) (item)")))
        }
        return chips
    }
}
