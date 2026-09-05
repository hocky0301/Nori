import Foundation

/// The chips above the list. Pinned is a section, not a filter.
enum PanelFilter: String, CaseIterable, Identifiable, Sendable {
    case all, text, link, code, color, image, file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .link: "Links"
        case .code: "Code"
        case .color: "Colors"
        case .image: "Images"
        case .file: "Files"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .text: ClipKind.text.symbolName
        case .link: ClipKind.link.symbolName
        case .code: ClipKind.code.symbolName
        case .color: ClipKind.color.symbolName
        case .image: ClipKind.image.symbolName
        case .file: ClipKind.file.symbolName
        }
    }

    var kind: ClipKind? {
        switch self {
        case .all: nil
        case .text: .text
        case .link: .link
        case .code: .code
        case .color: .color
        case .image: .image
        case .file: .file
        }
    }

    func matches(kind: ClipKind) -> Bool {
        self.kind == nil || self.kind == kind
    }

    var emptyMessage: String {
        switch self {
        case .all: "Nothing copied yet"
        case .text: "No text yet"
        case .link: "No links yet"
        case .code: "No code yet"
        case .color: "No colors yet"
        case .image: "No images yet"
        case .file: "No files yet"
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
