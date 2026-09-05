import Foundation
import Observation

/// Secrets live here, never in SwiftData: masked in the list, pasteable, gone after ten minutes.
@MainActor
@Observable
final class SensitiveVault {
    struct Entry: Sendable {
        let id: UUID
        let match: SecretDetector.Match
        let mask: String
        let draft: ClipDraft
        let capturedAt: Date
        var expiresAt: Date
    }

    static let lifetime: TimeInterval = 10 * 60

    private(set) var entries: [Entry] = []
    private(set) var version = 0
    private var sweepTimer: Timer?

    init() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    var rows: [ClipRow] {
        entries.map { entry in
            ClipRow(
                id: entry.id, source: .sensitive, kind: entry.draft.kind,
                title: entry.mask, searchText: "",
                sourceBundleID: entry.draft.sourceBundleID, sourceAppName: entry.draft.sourceAppName,
                isFromUniversalClipboard: entry.draft.isFromUniversalClipboard,
                firstCopiedAt: entry.capturedAt, lastCopiedAt: entry.capturedAt, copyCount: 1, pinnedAt: nil,
                byteCount: entry.draft.byteCount, characterCount: entry.draft.characterCount,
                lineCount: entry.draft.lineCount, isRichText: false, isTruncated: false,
                linkURL: nil, colorHex: nil, fileURLs: [], imagePixelSize: nil, thumbnail: nil,
                expiresAt: entry.expiresAt, ghostReason: nil
            )
        }
    }

    /// Add a secret, or extend the life of an identical one.
    @discardableResult
    func add(_ sensitive: SensitiveDraft, now: Date = .now) -> UUID {
        if let index = entries.firstIndex(where: { $0.draft.contentHash == sensitive.draft.contentHash }) {
            entries[index].expiresAt = now.addingTimeInterval(Self.lifetime)
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            version += 1
            return entry.id
        }
        let entry = Entry(id: UUID(), match: sensitive.match, mask: sensitive.mask, draft: sensitive.draft,
                          capturedAt: now, expiresAt: now.addingTimeInterval(Self.lifetime))
        entries.insert(entry, at: 0)
        version += 1
        return entry.id
    }

    func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Pasting a secret keeps it around for another ten minutes.
    func touch(id: UUID, now: Date = .now) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].expiresAt = now.addingTimeInterval(Self.lifetime)
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        version += 1
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        version += 1
    }

    func removeAll() {
        entries.removeAll()
        version += 1
    }

    func sweep(now: Date = .now) {
        let before = entries.count
        entries.removeAll { $0.expiresAt <= now }
        if entries.count != before { version += 1 }
    }
}
