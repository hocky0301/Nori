import Foundation

/// The single source of truth for what a key, click or number does.
///
/// Enter pastes. Modifiers are orthogonal bits: ⇧ = plain text, ⌥ = keep the panel open,
/// ⌘ = copy only. No preference can change this; the hint bar renders from the same function.
enum ActionGrammar {
    enum Base: Equatable, Sendable {
        case returnKey
        case click
        case number(Int)
    }

    struct Bits: OptionSet, Sendable, Hashable {
        let rawValue: Int
        static let plain = Bits(rawValue: 1 << 0)     // ⇧
        static let keepOpen = Bits(rawValue: 1 << 1)  // ⌥
        static let copyOnly = Bits(rawValue: 1 << 2)  // ⌘
        static let all: [Bits] = (0..<8).map { Bits(rawValue: $0) }
    }

    struct Capabilities: Sendable, Equatable {
        var accessibilityTrusted: Bool
    }

    enum Action: Equatable, Sendable {
        case paste(plain: Bool, keepOpen: Bool)
        case copy(plain: Bool, keepOpen: Bool)

        var isPaste: Bool { if case .paste = self { true } else { false } }
        var plain: Bool {
            switch self {
            case let .paste(plain, _), let .copy(plain, _): plain
            }
        }
        var keepOpen: Bool {
            switch self {
            case let .paste(_, keepOpen), let .copy(_, keepOpen): keepOpen
            }
        }
    }

    static func resolve(_ base: Base, _ bits: Bits, _ caps: Capabilities) -> Action {
        let plain = bits.contains(.plain)
        let keepOpen = bits.contains(.keepOpen)
        // ⌘ is the trigger of the number row, so it cannot also mean "copy only" there.
        let copyOnly: Bool = if case .number = base { false } else { bits.contains(.copyOnly) }
        if copyOnly || !caps.accessibilityTrusted {
            return .copy(plain: plain, keepOpen: keepOpen)
        }
        return .paste(plain: plain, keepOpen: keepOpen)
    }

    /// Verb for hint bars and menus.
    static func verb(for action: Action) -> String {
        switch action {
        case .paste(false, false): "Paste"
        case .paste(true, false): "Paste as plain text"
        case .paste(false, true): "Paste and keep Nori open"
        case .paste(true, true): "Paste plain, keep open"
        case .copy(false, false): "Copy"
        case .copy(true, false): "Copy as plain text"
        case .copy(false, true): "Copy, keep open"
        case .copy(true, true): "Copy plain, keep open"
        }
    }
}

#if canImport(AppKit)
import AppKit

extension ActionGrammar.Bits {
    /// Translate event modifiers into grammar bits.
    init(modifierFlags: NSEvent.ModifierFlags) {
        var bits: ActionGrammar.Bits = []
        if modifierFlags.contains(.shift) { bits.insert(.plain) }
        if modifierFlags.contains(.option) { bits.insert(.keepOpen) }
        if modifierFlags.contains(.command) { bits.insert(.copyOnly) }
        self = bits
    }

    /// Glyphs in the macOS order (⌃⌥⇧⌘) for keycaps.
    var glyphs: String {
        var result = ""
        if contains(.keepOpen) { result += "⌥" }
        if contains(.plain) { result += "⇧" }
        if contains(.copyOnly) { result += "⌘" }
        return result
    }
}
#endif
