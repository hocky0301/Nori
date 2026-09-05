import Foundation

/// The chips above the list. `text` folds plain and rich text together.
enum PanelFilter: String, CaseIterable, Identifiable, Sendable {
    case all, text, code, link, image, file, color, pinned

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .code: "Code"
        case .link: "Links"
        case .image: "Images"
        case .file: "Files"
        case .color: "Colors"
        case .pinned: "Pinned"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .text: ClipKind.text.symbolName
        case .code: ClipKind.code.symbolName
        case .link: ClipKind.link.symbolName
        case .image: ClipKind.image.symbolName
        case .file: ClipKind.file.symbolName
        case .color: ClipKind.color.symbolName
        case .pinned: "pin"
        }
    }

    func matches(kind: ClipKind, isPinned: Bool) -> Bool {
        switch self {
        case .all: true
        case .text: kind == .text || kind == .richText
        case .code: kind == .code
        case .link: kind == .link
        case .image: kind == .image
        case .file: kind == .file
        case .color: kind == .color
        case .pinned: isPinned
        }
    }

    var next: PanelFilter {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var previous: PanelFilter {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }
}
