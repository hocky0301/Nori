import AppKit

/// Puts a history item back on the pasteboard.
@MainActor
enum ClipboardWriter {
    /// Restore every stored representation (or only plain text) and tag the change as Nori's own.
    @discardableResult
    static func write(_ item: ClipItem, plainTextOnly: Bool, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()

        var contents = item.contents.map { ($0.type, $0.data) }
        if plainTextOnly {
            if let text = item.plainText {
                contents = [(PasteboardType.utf8PlainText, Data(text.utf8))]
            }
            // Keep file URLs: "plain" files are still files.
            contents += item.contents.filter { $0.type == PasteboardType.fileURL }.map { ($0.type, $0.data) }
        }

        // File URLs must go through writeObjects so multi-file drags/pastes work in Finder.
        let fileItems: [NSPasteboardItem] = contents
            .filter { $0.0 == PasteboardType.fileURL }
            .map { type, data in
                let pasteItem = NSPasteboardItem()
                pasteItem.setData(data, forType: NSPasteboard.PasteboardType(type))
                return pasteItem
            }
        if !fileItems.isEmpty {
            pasteboard.writeObjects(fileItems)
        }
        for (type, data) in contents where type != PasteboardType.fileURL {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
        }

        pasteboard.setString(item.id.uuidString, forType: NSPasteboard.PasteboardType(PasteboardType.noriItem))
        pasteboard.setString(Bundle.main.bundleIdentifier ?? "Nori", forType: NSPasteboard.PasteboardType(PasteboardType.source))
        return pasteboard.changeCount
    }

    /// Put an arbitrary string on the pasteboard (used for "copy search text" and quick actions).
    @discardableResult
    static func write(string: String, to pasteboard: NSPasteboard = .general) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        return pasteboard.changeCount
    }
}
