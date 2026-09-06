import CryptoKit
import Foundation

/// Turns a raw `PasteboardSnapshot` into a classified `ClipDraft`, a masked sensitive draft,
/// a ghost row, or a rejection.
///
/// This is the heart of capture correctness. It is pure and synchronous (run it off the main
/// actor) so every rule can be unit-tested with hand-built snapshots.
enum ClipClassifier {
    static func classify(_ snapshot: PasteboardSnapshot, policy: CapturePolicy = .default) -> CaptureOutcome {
        // 1. Nori's own write: the store bumps the existing item instead of re-capturing.
        if snapshot.hasNoriMarker {
            return .rejected(.fromNori(snapshot.noriItemID))
        }

        // 2. Privacy markers are honoured wherever they appear. Pasteboard-level types include
        //    types that are on no item (Maccy #241), so check the union.
        if snapshot.declaredTypes.contains(PasteboardType.concealed) {
            return .ghost(.concealed(appName: snapshot.sourceAppName))
        }
        if let ephemeral = snapshot.declaredTypes.first(where: { PasteboardType.ephemeralTypes.contains($0) }) {
            return .rejected(.ephemeral(ephemeral))
        }
        if let ignored = snapshot.declaredTypes.first(where: { policy.ignoredTypes.contains($0) }) {
            return .rejected(.ignoredType(ignored))
        }
        if let bundleID = snapshot.sourceBundleID, policy.ignoredApps.contains(bundleID) {
            return .rejected(.ignoredApp(bundleID))
        }
        let isUniversal = snapshot.declaredTypes.contains(PasteboardType.universalClipboard)
        if isUniversal, !policy.captureUniversalClipboard {
            return .rejected(.universalClipboardDisabled)
        }

        let regexps = policy.ignoreRegexps.compactMap { try? NSRegularExpression(pattern: $0) }

        // 3. Some apps (BBEdit, Edge, Word) put several items on the pasteboard for one copy.
        //    Merge every representation into one draft, first item first, so a single history
        //    entry restores exactly what the app wrote.
        var merged: [ClipDraft.Content] = []
        var seenTypes: Set<String> = []
        var matchedRegexp = false
        var imageTooLarge: Int?

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
            if !policy.captureText {
                types.removeAll { PasteboardType.textTypes.contains($0) }
            }
            if !policy.captureImages {
                types.removeAll { PasteboardType.imageTypes.contains($0) }
            }
            if !policy.captureFiles {
                types.removeAll { $0 == PasteboardType.fileURL }
            }

            for type in types {
                // One pasteboard item per file when several files are copied: keep every URL.
                let repeatable = type == PasteboardType.fileURL
                guard repeatable || !seenTypes.contains(type) else { continue }
                guard let data = item.data(for: type) else { continue }

                // 4. Size caps. Images too large leave a ghost; other giant blobs (30 MB WebKit
                //    custom data) are dropped without losing the clip.
                if PasteboardType.imageTypes.contains(type) {
                    if data.count > policy.maxImageBytes {
                        imageTooLarge = max(imageTooLarge ?? 0, data.count)
                        continue
                    }
                } else if type == PasteboardType.utf8PlainText {
                    // handled below (truncation)
                } else if type != PasteboardType.fileURL, data.count > policy.maxOtherRepresentationBytes {
                    // Includes RTF/HTML: a formatted spreadsheet range carries tens of MB of markup
                    // next to a few hundred KB of plain text, which is all that is worth keeping.
                    continue
                }
                seenTypes.insert(type)
                merged.append(ClipDraft.Content(type: type, data: data))
            }
        }

        if let imageTooLarge, !merged.contains(where: { PasteboardType.imageTypes.contains($0.type) }) {
            // The image was the point of the copy (browsers add the alt text next to it).
            let onlyText = merged.allSatisfy { PasteboardType.textTypes.contains($0.type) }
            if merged.isEmpty || onlyText {
                return .ghost(.imageTooLarge(bytes: imageTooLarge))
            }
        }

        if merged.isEmpty {
            return .rejected(matchedRegexp ? .matchedIgnoreRegexp : .nothingToStore)
        }

        // Universal Clipboard delivers images from iOS as a temporary JPEG file plus a file URL.
        // Read the bytes now and drop the URL: the file is gone soon, and its random path would
        // otherwise make every copy of the same photo a new history row.
        if isUniversal, !merged.contains(where: { PasteboardType.imageTypes.contains($0.type) }),
           let url = universalClipboardImageURL(in: merged) {
            let onDisk = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if onDisk > policy.maxImageBytes {
                return .ghost(.imageTooLarge(bytes: onDisk))
            }
            if let bytes = try? Data(contentsOf: url) {
                if bytes.count > policy.maxImageBytes {
                    return .ghost(.imageTooLarge(bytes: bytes.count))
                }
                let type = url.pathExtension.lowercased() == "png" ? PasteboardType.png : PasteboardType.jpeg
                merged.removeAll { $0.type == PasteboardType.fileURL }
                merged.append(ClipDraft.Content(type: type, data: bytes))
            }
        }

        var isTruncated = false
        if let index = merged.firstIndex(where: { $0.type == PasteboardType.utf8PlainText }),
           merged[index].data.count > policy.maxTextBytes {
            let cut = String(decoding: merged[index].data.prefix(policy.maxTextBytes), as: UTF8.self)
            merged[index] = ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data(cut.utf8))
            merged.removeAll { $0.type == PasteboardType.rtf || $0.type == PasteboardType.html }
            isTruncated = true
        }

        guard let built = build(contents: merged, isUniversalClipboard: isUniversal, sourceBundleID: snapshot.sourceBundleID) else {
            return .rejected(.nothingToStore)
        }
        var draft = built.draft
        draft.sourceBundleID = snapshot.sourceBundleID
        draft.sourceAppName = isUniversal ? "iPhone or iPad" : snapshot.sourceAppName
        draft.isTruncated = isTruncated

        // 5. Secrets never touch disk — also when the copy only carries RTF/HTML.
        if policy.maskSensitive, draft.kind.isTextual, let match = SecretDetector.detect(in: built.text) {
            return .sensitive(SensitiveDraft(match: match, mask: SecretDetector.mask(built.text), draft: draft))
        }
        return .captured(draft)
    }

    /// The temporary image file behind an iOS copy, when that is all the pasteboard holds.
    private static func universalClipboardImageURL(in contents: [ClipDraft.Content]) -> URL? {
        let urls = contents
            .filter { $0.type == PasteboardType.fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil, isAbsolute: true) }
        guard urls.count == 1, let url = urls.first,
              ["jpeg", "jpg", "png", "heic"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    // MARK: - Classification

    static func makeDraft(
        contents: [ClipDraft.Content],
        isUniversalClipboard: Bool = false,
        sourceBundleID: String? = nil
    ) -> ClipDraft? {
        build(contents: contents, isUniversalClipboard: isUniversalClipboard, sourceBundleID: sourceBundleID)?.draft
    }

    /// A draft plus the full text it was classified from (the draft only keeps a capped title
    /// and search text; secret detection needs all of it).
    struct Built {
        var draft: ClipDraft
        var text: String
    }

    static func build(
        contents: [ClipDraft.Content],
        isUniversalClipboard: Bool = false,
        sourceBundleID: String? = nil
    ) -> Built? {
        var contents = contents
        func data(_ type: String) -> Data? { contents.first(where: { $0.type == type })?.data }

        let fileURLs = contents
            .filter { $0.type == PasteboardType.fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil, isAbsolute: true) }

        // Images: PNG only, plus an inline thumbnail.
        var imageResult: ImageNormalizer.Result?
        if contents.contains(where: { PasteboardType.imageTypes.contains($0.type) }) {
            imageResult = ImageNormalizer.normalize(contents: contents)
            contents.removeAll { PasteboardType.imageTypes.contains($0.type) }
            if let imageResult {
                contents.insert(ClipDraft.Content(type: PasteboardType.png, data: imageResult.png), at: 0)
            }
        }

        // The rich-text fallback is decoded only when there is no plain text: browsers attach
        // HTML to nearly every copy, and decoding it just to throw it away is wasted work.
        let plain = data(PasteboardType.utf8PlainText).flatMap { String(data: $0, encoding: .utf8) }
        let text: String
        if let plain, !plain.isEmpty {
            text = plain
        } else {
            text = richTextString(rtf: data(PasteboardType.rtf), html: data(PasteboardType.html)) ?? ""
        }

        var draft = ClipDraft(contents: contents, contentHash: contentHash(of: contents), isFromUniversalClipboard: isUniversalClipboard)

        if !fileURLs.isEmpty {
            draft.kind = .file
            draft.fileURLs = fileURLs
            let names = fileURLs.map(\.lastPathComponent)
            draft.title = names.joined(separator: "\n")
            draft.searchText = fileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            draft.characterCount = draft.title.count
            draft.lineCount = names.count
            return Built(draft: draft, text: text)
        }

        if let imageResult {
            draft.kind = .image
            draft.imagePixelSize = imageResult.pixelSize
            draft.thumbnail = imageResult.thumbnail
            draft.title = "Image \(Int(imageResult.pixelSize.width))×\(Int(imageResult.pixelSize.height))"
            // Browsers put the page text / alt text next to the bitmap; keep it searchable.
            draft.searchText = String(text.prefix(ClipDraft.maxSearchTextLength))
            return Built(draft: draft, text: text)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        draft.characterCount = text.count
        draft.lineCount = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        draft.searchText = String(text.prefix(ClipDraft.maxSearchTextLength))
        draft.title = String(trimmed.prefix(ClipDraft.maxTitleLength))
        draft.isRichText = isMeaningfullyRich(rtf: data(PasteboardType.rtf))

        if let url = KindDetector.link(in: trimmed) {
            draft.kind = .link
            draft.linkURL = url
            draft.title = url.absoluteString
        } else if let hex = KindDetector.color(in: trimmed) {
            draft.kind = .color
            draft.colorHex = hex
            draft.title = trimmed
        } else if KindDetector.looksLikeCode(text, sourceBundleID: sourceBundleID, isRichText: draft.isRichText) {
            draft.kind = .code
        } else {
            draft.kind = .text
        }
        return Built(draft: draft, text: text)
    }

    /// RTF whose only formatting is the default font is really plain text (Terminal, TextEdit in plain mode).
    static func isMeaningfullyRich(rtf: Data?) -> Bool {
        guard let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil), attributed.length > 0 else {
            return false
        }
        var runs = 0
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { _, _, _ in runs += 1 }
        return runs > 1
    }

    /// Text for a copy without a plain-text representation. RTF decodes safely anywhere; HTML is
    /// reduced by a tag stripper because AppKit's HTML importer is WebKit-backed and must not run
    /// off the main thread (classification never does).
    static func richTextString(rtf: Data?, html: Data?) -> String? {
        if let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil), !attributed.string.isEmpty {
            return attributed.string
        }
        if let html, let text = HTMLText.plainText(from: html), !text.isEmpty {
            return text
        }
        return nil
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
            var length = UInt64(content.data.count).littleEndian
            withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
            hasher.update(data: content.data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// A small, thread-safe reduction of HTML to searchable text: scripts, styles and tags go,
/// block boundaries become line breaks, common entities are decoded.
enum HTMLText {
    private static let dropped = try! NSRegularExpression(
        pattern: #"<!--.*?-->|<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let breaks = try! NSRegularExpression(
        pattern: #"<\s*(br|/p|/div|/li|/tr|/h[1-6]|/blockquote|/pre|/section|/article)\b[^>]*>"#,
        options: [.caseInsensitive]
    )
    private static let tags = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let entities = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#)
    private static let spaces = try! NSRegularExpression(pattern: #"[ \t\x{00A0}]+"#)
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "hellip": "…", "mdash": "—", "ndash": "–", "copy": "©", "reg": "®", "trade": "™",
    ]

    static func plainText(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var text = replace(dropped, in: html, with: "")
        text = replace(breaks, in: text, with: "\n")
        text = replace(tags, in: text, with: "")
        text = decodeEntities(in: text)
        text = replace(spaces, in: text, with: " ")
        let lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        for line in lines where !(line.isEmpty && collapsed.last?.isEmpty == true) {
            collapsed.append(line)
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func decodeEntities(in text: String) -> String {
        let nsText = text as NSString
        var result = ""
        var cursor = 0
        for match in entities.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let body = nsText.substring(with: match.range(at: 1))
            let decoded: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                decoded = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if body.hasPrefix("#") {
                decoded = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = named[body.lowercased()]
            }
            result += decoded ?? nsText.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        result += nsText.substring(from: cursor)
        return result
    }
}
