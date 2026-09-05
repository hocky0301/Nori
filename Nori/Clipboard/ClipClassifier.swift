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
                } else if PasteboardType.textTypes.contains(type) {
                    // handled below (truncation)
                } else if type != PasteboardType.fileURL, data.count > policy.maxOtherRepresentationBytes {
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

        var isTruncated = false
        if let index = merged.firstIndex(where: { $0.type == PasteboardType.utf8PlainText }),
           merged[index].data.count > policy.maxTextBytes {
            let cut = String(decoding: merged[index].data.prefix(policy.maxTextBytes), as: UTF8.self)
            merged[index] = ClipDraft.Content(type: PasteboardType.utf8PlainText, data: Data(cut.utf8))
            merged.removeAll { $0.type == PasteboardType.rtf || $0.type == PasteboardType.html }
            isTruncated = true
        }

        guard var draft = makeDraft(contents: merged, isUniversalClipboard: isUniversal, sourceBundleID: snapshot.sourceBundleID) else {
            return .rejected(.nothingToStore)
        }
        draft.sourceBundleID = snapshot.sourceBundleID
        draft.sourceAppName = isUniversal ? "iPhone or iPad" : snapshot.sourceAppName
        draft.isTruncated = isTruncated

        // 5. Secrets never touch disk.
        if policy.maskSensitive, draft.kind.isTextual, let text = draft.plainText, let match = SecretDetector.detect(in: text) {
            return .sensitive(SensitiveDraft(match: match, mask: SecretDetector.mask(text), draft: draft))
        }
        return .captured(draft)
    }

    // MARK: - Classification

    static func makeDraft(
        contents: [ClipDraft.Content],
        isUniversalClipboard: Bool = false,
        sourceBundleID: String? = nil
    ) -> ClipDraft? {
        var contents = contents
        func data(_ type: String) -> Data? { contents.first(where: { $0.type == type })?.data }

        let fileURLs = contents
            .filter { $0.type == PasteboardType.fileURL }
            .compactMap { URL(dataRepresentation: $0.data, relativeTo: nil, isAbsolute: true) }

        // Universal Clipboard delivers images from iOS as a temporary JPEG file plus a file URL.
        var universalImage = false
        if !contents.contains(where: { PasteboardType.imageTypes.contains($0.type) }),
           isUniversalClipboard, let url = fileURLs.first,
           ["jpeg", "jpg", "png", "heic"].contains(url.pathExtension.lowercased()),
           let bytes = try? Data(contentsOf: url) {
            let type = url.pathExtension.lowercased() == "png" ? PasteboardType.png : PasteboardType.jpeg
            contents.append(ClipDraft.Content(type: type, data: bytes))
            universalImage = true
        }

        // Images: PNG only, plus an inline thumbnail.
        var imageResult: ImageNormalizer.Result?
        if contents.contains(where: { PasteboardType.imageTypes.contains($0.type) }) {
            imageResult = ImageNormalizer.normalize(contents: contents)
            contents.removeAll { PasteboardType.imageTypes.contains($0.type) }
            if let imageResult {
                contents.insert(ClipDraft.Content(type: PasteboardType.png, data: imageResult.png), at: 0)
            }
        }

        let plain = data(PasteboardType.utf8PlainText).flatMap { String(data: $0, encoding: .utf8) }
        let rich = richTextString(rtf: data(PasteboardType.rtf), html: data(PasteboardType.html))
        let text = (plain?.isEmpty == false ? plain : rich) ?? ""

        var draft = ClipDraft(contents: contents, contentHash: contentHash(of: contents), isFromUniversalClipboard: isUniversalClipboard)

        if !fileURLs.isEmpty, !universalImage {
            draft.kind = .file
            draft.fileURLs = fileURLs
            let names = fileURLs.map(\.lastPathComponent)
            draft.title = names.joined(separator: "\n")
            draft.searchText = fileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            draft.characterCount = draft.title.count
            draft.lineCount = names.count
            return draft
        }

        if let imageResult {
            draft.kind = .image
            draft.imagePixelSize = imageResult.pixelSize
            draft.thumbnail = imageResult.thumbnail
            draft.title = "Image \(Int(imageResult.pixelSize.width))×\(Int(imageResult.pixelSize.height))"
            // Browsers put the page text / alt text next to the bitmap; keep it searchable.
            draft.searchText = String(text.prefix(ClipDraft.maxSearchTextLength))
            return draft
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
        return draft
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

    static func richTextString(rtf: Data?, html: Data?) -> String? {
        if let rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil), !attributed.string.isEmpty {
            return attributed.string
        }
        if let html, let attributed = NSAttributedString(html: html, documentAttributes: nil), !attributed.string.isEmpty {
            return attributed.string
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
