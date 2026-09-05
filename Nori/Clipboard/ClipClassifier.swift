import CryptoKit
import Foundation
import ImageIO

/// Turns a raw `PasteboardSnapshot` into a classified `ClipDraft`, or explains why not.
///
/// This is the heart of capture correctness. It is pure and synchronous so every rule
/// can be unit-tested with hand-built snapshots.
enum ClipClassifier {
    static func classify(_ snapshot: PasteboardSnapshot, policy: CapturePolicy = .default) -> CaptureOutcome {
        if snapshot.hasNoriMarker {
            return .rejected(.fromNori(snapshot.noriItemID))
        }

        // Pasteboard-level types include types that are not on any item (see Maccy #241),
        // which is exactly what we want for privacy markers: honour them wherever they appear.
        if let privateType = snapshot.declaredTypes.first(where: { PasteboardType.privacyTypes.contains($0) }) {
            return .rejected(.privateOrTransient(privateType))
        }
        if let ignored = snapshot.declaredTypes.first(where: { policy.ignoredTypes.contains($0) }) {
            return .rejected(.ignoredType(ignored))
        }
        if let bundleID = snapshot.sourceBundleID {
            let listed = policy.ignoredApps.contains(bundleID)
            if policy.recordOnlyListedApps ? !listed : listed {
                return .rejected(.ignoredApp(bundleID))
            }
        }

        let regexps = policy.ignoreRegexps.compactMap { try? NSRegularExpression(pattern: $0) }

        // Some apps (BBEdit, Edge, Word) put several items on the pasteboard for one copy.
        // Merge every representation into one draft, first item first, so a single history
        // entry restores exactly what the app wrote.
        var merged: [ClipDraft.Content] = []
        var seenTypes: Set<String> = []
        var matchedRegexp = false

        for item in snapshot.items {
            if let text = item.string(for: PasteboardType.utf8PlainText),
               !regexps.isEmpty,
               regexps.contains(where: { $0.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }) {
                matchedRegexp = true
                continue
            }

            var types = item.types.filter { type in
                !PasteboardType.metadataTypes.contains(type)
                    && !PasteboardType.ignoredPrefixes.contains(where: { type.hasPrefix($0) })
            }
            // Word bookmarks: keeping these makes Word paste a hyperlink to itself instead of the text.
            if PasteboardType.microsoftLinkTypes.isSubset(of: Set(types)) {
                types.removeAll { PasteboardType.microsoftLinkTypes.contains($0) || $0 == PasteboardType.pdf }
            }
            if !policy.captureImages {
                types.removeAll { PasteboardType.imageTypes.contains($0) }
            }
            if !policy.captureFiles {
                types.removeAll { $0 == PasteboardType.fileURL }
            }
            if !policy.captureRichText {
                types.removeAll { $0 == PasteboardType.rtf || $0 == PasteboardType.html }
            }

            for type in types {
                // One pasteboard item per file when several files are copied: keep every URL.
                let repeatable = type == PasteboardType.fileURL
                guard repeatable || !seenTypes.contains(type) else { continue }
                guard let data = item.data(for: type), data.count <= policy.maxRepresentationBytes else { continue }
                seenTypes.insert(type)
                merged.append(ClipDraft.Content(type: type, data: data))
            }
        }

        if merged.isEmpty {
            return .rejected(matchedRegexp ? .matchedIgnoreRegexp : .nothingToStore)
        }

        let isUniversal = snapshot.declaredTypes.contains(PasteboardType.universalClipboard)
        guard var draft = makeDraft(contents: merged, isUniversalClipboard: isUniversal) else {
            return .rejected(.nothingToStore)
        }
        draft.sourceBundleID = snapshot.sourceBundleID
        return .captured(draft)
    }

    // MARK: - Classification

    static func makeDraft(contents: [ClipDraft.Content], isUniversalClipboard: Bool = false) -> ClipDraft? {
        let types = Set(contents.map(\.type))
        func data(_ type: String) -> Data? { contents.first(where: { $0.type == type })?.data }

        let fileURLs = contents
            .filter { $0.type == PasteboardType.fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil, isAbsolute: true) }

        var imageData = PasteboardType.imageTypes.lazy.compactMap(data).first
        var contents = contents
        // Universal Clipboard delivers images from iOS as a temporary JPEG file plus a file URL.
        if imageData == nil, isUniversalClipboard, let url = fileURLs.first,
           ["jpeg", "jpg", "png", "heic"].contains(url.pathExtension.lowercased()),
           let bytes = try? Data(contentsOf: url) {
            imageData = bytes
            let type = url.pathExtension.lowercased() == "png" ? PasteboardType.png : PasteboardType.jpeg
            contents.append(ClipDraft.Content(type: type, data: bytes))
        }

        let plain = data(PasteboardType.utf8PlainText).flatMap { String(data: $0, encoding: .utf8) }
        let rich = richTextString(rtf: data(PasteboardType.rtf), html: data(PasteboardType.html))
        let text = (plain?.isEmpty == false ? plain : rich) ?? ""

        var draft = ClipDraft(
            kind: .text,
            title: "",
            searchText: "",
            contents: contents,
            sourceBundleID: nil,
            contentHash: contentHash(of: contents),
            isFromUniversalClipboard: isUniversalClipboard,
            linkURL: nil,
            colorHex: nil,
            fileURLs: [],
            imagePixelSize: nil,
            characterCount: 0,
            lineCount: 0
        )

        if !fileURLs.isEmpty, !(isUniversalClipboard && imageData != nil) {
            draft.kind = .file
            draft.fileURLs = fileURLs
            let names = fileURLs.map(\.lastPathComponent)
            draft.title = names.joined(separator: "\n")
            draft.searchText = fileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            draft.characterCount = draft.title.count
            draft.lineCount = names.count
            return draft
        }

        if let imageData {
            draft.kind = .image
            draft.imagePixelSize = pixelSize(of: imageData)
            if let size = draft.imagePixelSize {
                draft.title = "Image \(Int(size.width))×\(Int(size.height))"
            } else {
                draft.title = "Image"
            }
            // Browsers put the page text / alt text next to the bitmap; keep it searchable.
            draft.searchText = String(text.prefix(ClipDraft.maxSearchTextLength))
            return draft
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        draft.characterCount = text.count
        draft.lineCount = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        draft.searchText = String(text.prefix(ClipDraft.maxSearchTextLength))
        draft.title = String(trimmed.prefix(ClipDraft.maxTitleLength))

        if let url = KindDetector.link(in: trimmed) {
            draft.kind = .link
            draft.linkURL = url
            draft.title = url.absoluteString
        } else if let hex = KindDetector.color(in: trimmed) {
            draft.kind = .color
            draft.colorHex = hex
            draft.title = trimmed
        } else if KindDetector.looksLikeCode(text) {
            draft.kind = .code
        } else if types.contains(PasteboardType.rtf) || types.contains(PasteboardType.html), plain?.isEmpty != false || isMeaningfullyRich(rtf: data(PasteboardType.rtf)) {
            draft.kind = .richText
        } else {
            draft.kind = .text
        }
        return draft
    }

    /// RTF whose only formatting is the default font is really plain text (Terminal, TextEdit in plain mode).
    static func isMeaningfullyRich(rtf: Data?) -> Bool {
        guard let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) else { return false }
        var runs = 0
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { _, _, _ in runs += 1 }
        if runs > 1 { return true }
        let attrs = attributed.length > 0 ? attributed.attributes(at: 0, effectiveRange: nil) : [:]
        return attrs[.link] != nil || attrs[.underlineStyle] != nil || attrs[.strikethroughStyle] != nil
            || attrs[.backgroundColor] != nil
    }

    static func richTextString(rtf: Data?, html: Data?) -> String? {
        if let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil), !attributed.string.isEmpty {
            return attributed.string
        }
        if let html, let attributed = NSAttributedString(html: html, documentAttributes: nil), !attributed.string.isEmpty {
            return attributed.string
        }
        return nil
    }

    static func pixelSize(of imageData: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Hash of the representations that identify a copy. Two copies of the same text from
    /// different apps (which add different custom types) still collide, which is what users expect.
    static func contentHash(of contents: [ClipDraft.Content]) -> String {
        let stable = contents.filter { PasteboardType.stableTypes.contains($0.type) }
        let hashed = (stable.isEmpty ? contents : stable).sorted { $0.type < $1.type }
        var hasher = SHA256()
        for content in hashed {
            hasher.update(data: Data(content.type.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: content.data)
            hasher.update(data: Data([0xFF]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
