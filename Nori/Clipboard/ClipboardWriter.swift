import AppKit

/// Puts a history item back on the pasteboard.
@MainActor
enum ClipboardWriter {
    /// Restore every stored representation (or only plain text) and tag the change as Nori's own.
    @discardableResult
    static func write(
        contents: [ClipDraft.Content],
        id: UUID,
        sourceBundleID: String?,
        plainTextOnly: Bool,
        to pasteboard: NSPasteboard = .general
    ) -> Int {
        pasteboard.clearContents()

        var contents = contents
        if plainTextOnly, let plain = contents.first(where: { $0.type == PasteboardType.utf8PlainText }) {
            // "Plain" files are still files (Maccy #962).
            contents = [plain] + contents.filter { $0.type == PasteboardType.fileURL }
        }

        // File URLs must go through writeObjects so multi-file pastes work in Finder.
        let fileItems: [NSPasteboardItem] = contents
            .filter { $0.type == PasteboardType.fileURL }
            .map { content in
                let pasteItem = NSPasteboardItem()
                pasteItem.setData(content.data, forType: NSPasteboard.PasteboardType(content.type))
                return pasteItem
            }
        if !fileItems.isEmpty {
            pasteboard.writeObjects(fileItems)
        }
        for content in contents where content.type != PasteboardType.fileURL {
            pasteboard.setData(content.data, forType: NSPasteboard.PasteboardType(content.type))
        }

        pasteboard.setString(id.uuidString, forType: NSPasteboard.PasteboardType(PasteboardType.noriItem))
        pasteboard.setString(sourceBundleID ?? Bundle.main.bundleIdentifier ?? "Nori",
                             forType: NSPasteboard.PasteboardType(PasteboardType.source))
        return pasteboard.changeCount
    }

    /// Put typed search text on the pasteboard as a brand-new plain-text clip.
    @discardableResult
    static func write(string: String, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        return pasteboard.changeCount
    }
}
