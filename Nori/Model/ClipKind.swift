import Foundation

/// The user-facing category of a clipboard item.
///
/// Nori classifies every capture into one kind so the UI can render a tailored card
/// (a link shows its host, a color shows a swatch, an image shows a thumbnail, …)
/// and so the user can filter the history by kind. Rich text is a flag on `.text`, not a kind.
enum ClipKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case text
    case link
    case code
    case color
    case image
    case file

    var id: String { rawValue }

    /// SF Symbol used in the card well and filter chips.
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var displayName: String {
        switch self {
        case .text: String(localized: "Text")
        case .link: String(localized: "Link")
        case .code: String(localized: "Code")
        case .color: String(localized: "Color")
        case .image: String(localized: "Image")
        case .file: String(localized: "File")
        }
    }

    /// Whether the item carries a textual payload that can be pasted as plain text.
    var isTextual: Bool {
        switch self {
        case .text, .code, .link, .color: true
        case .image, .file: false
        }
    }
}
