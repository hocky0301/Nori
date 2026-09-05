import Foundation

/// The user-facing category of a clipboard item.
///
/// Nori classifies every capture into one kind so the UI can render a tailored card
/// (a link shows its host, a color shows a swatch, an image shows a thumbnail, …)
/// and so the user can filter the history by kind.
enum ClipKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case text
    case code
    case richText
    case link
    case color
    case image
    case file

    var id: String { rawValue }

    /// SF Symbol used in badges and filter chips.
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .richText: "textformat"
        case .link: "link"
        case .color: "paintpalette"
        case .image: "photo"
        case .file: "doc"
        }
    }

    /// Short human label.
    var displayName: String {
        switch self {
        case .text: "Text"
        case .code: "Code"
        case .richText: "Rich Text"
        case .link: "Link"
        case .color: "Color"
        case .image: "Image"
        case .file: "File"
        }
    }

    /// Whether the item carries a textual payload that can be pasted as plain text.
    var isTextual: Bool {
        switch self {
        case .text, .code, .richText, .link, .color: true
        case .image, .file: false
        }
    }
}
