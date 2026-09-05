import Foundation
import Observation
import OSLog
import SwiftData

/// The observable view of the persisted history, backed by SwiftData.
///
/// All mutation goes through here so ordering, de-duplication, the size limit and expiry
/// are enforced in one place. Views only ever see `[ClipRow]` values.
@MainActor
@Observable
final class HistoryStore {
    /// Newest first. Rebuilt on every mutation.
    private(set) var rows: [ClipRow] = []
    /// Bumped on every mutation.
    private(set) var version = 0
    var maxItems: Int = 500 {
        didSet { if maxItems != oldValue { enforceLimit(); publish() } }
    }
    /// 0 = never.
    var expireAfterDays: Int = 0

    /// A deleted item that can still be brought back with ⌘Z.
    struct UndoRecord {
        let draft: ClipDraft
        let firstCopiedAt: Date
        let lastCopiedAt: Date
        let copyCount: Int
        let pinnedAt: Date?
    }

    private var items: [ClipItem] = []
    private let context: ModelContext
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "history")

    init(context: ModelContext) {
        self.context = context
    }

    var count: Int { items.count }
    var pinnedCount: Int { items.filter(\.isPinned).count }
    var totalBytes: Int { items.reduce(0) { $0 + $1.byteCount } }

    func load() {
        var descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)])
        descriptor.includePendingChanges = true
        do {
            items = try context.fetch(descriptor)
        } catch {
            logger.error("fetch failed: \(error.localizedDescription)")
            items = []
        }
        expireOldItems()
        enforceLimit()
        save()
    }

    func item(id: UUID) -> ClipItem? {
        items.first { $0.id == id }
    }

    func row(id: UUID) -> ClipRow? {
        rows.first { $0.id == id }
    }

    /// Insert a new capture, or refresh the existing entry with identical content.
    @discardableResult
    func ingest(_ draft: ClipDraft, now: Date = .now) -> UUID {
        if let existing = items.first(where: { $0.contentHash == draft.contentHash }) {
            existing.lastCopiedAt = now
            existing.copyCount += 1
            if let bundle = draft.sourceBundleID {
                existing.sourceBundleID = bundle
                existing.sourceAppName = draft.sourceAppName
            }
            moveToTop(existing)
            save()
            return existing.id
        }

        let item = ClipItem(draft: draft, now: now)
        context.insert(item)
        attach(draft.contents, to: item)
        insertByRecency(item)
        enforceLimit()
        save()
        return item.id
    }

    /// Called when the user pasted an item through Nori: it becomes the most recent copy again.
    func touch(id: UUID, now: Date = .now) {
        guard let item = item(id: id) else { return }
        item.lastCopiedAt = now
        item.copyCount += 1
        moveToTop(item)
        save()
    }

    /// Remove an item; the returned record restores it with dates, count and pin intact.
    @discardableResult
    func delete(id: UUID) -> UndoRecord? {
        guard let item = item(id: id) else { return nil }
        var draft = ClipDraft(kind: item.kind, contents: item.draftContents, contentHash: item.contentHash,
                              isFromUniversalClipboard: item.isFromUniversalClipboard)
        draft.title = item.title
        draft.searchText = item.searchText
        draft.sourceBundleID = item.sourceBundleID
        draft.sourceAppName = item.sourceAppName
        draft.isRichText = item.isRichText
        draft.isTruncated = item.isTruncated
        draft.linkURL = item.linkURL
        draft.colorHex = item.colorHex
        draft.fileURLs = item.fileURLs
        draft.imagePixelSize = item.imagePixelSize
        draft.thumbnail = item.thumbnail
        draft.characterCount = item.characterCount
        draft.lineCount = item.lineCount
        let record = UndoRecord(draft: draft, firstCopiedAt: item.firstCopiedAt, lastCopiedAt: item.lastCopiedAt,
                                copyCount: item.copyCount, pinnedAt: item.pinnedAt)
        items.removeAll { $0.id == id }
        context.delete(item)
        save()
        return record
    }

    /// Bring back a deleted item exactly where it was.
    @discardableResult
    func restore(_ record: UndoRecord) -> UUID {
        let item = ClipItem(draft: record.draft, now: record.firstCopiedAt)
        item.lastCopiedAt = record.lastCopiedAt
        item.copyCount = record.copyCount
        item.pinnedAt = record.pinnedAt
        context.insert(item)
        attach(record.draft.contents, to: item)
        let index = items.firstIndex { $0.lastCopiedAt < record.lastCopiedAt } ?? items.count
        items.insert(item, at: index)
        save()
        return item.id
    }

    /// Remove history. Pinned items survive unless `includingPinned` is set.
    @discardableResult
    func clear(includingPinned: Bool) -> Int {
        let doomed = includingPinned ? items : items.filter { !$0.isPinned }
        let ids = Set(doomed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        doomed.forEach(context.delete)
        save()
        return doomed.count
    }

    func togglePin(id: UUID, now: Date = .now) {
        guard let item = item(id: id) else { return }
        item.pinnedAt = item.isPinned ? nil : now
        enforceLimit()
        save()
    }

    /// Update the searchable text of an item (used when OCR finishes for an image).
    func updateSearchText(id: UUID, text: String) {
        guard let item = item(id: id) else { return }
        item.searchText = String(text.prefix(ClipDraft.maxSearchTextLength))
        save()
    }

    // MARK: Full content (on demand)

    func contents(id: UUID) -> [ClipDraft.Content] {
        item(id: id)?.draftContents ?? []
    }

    func plainText(id: UUID) -> String? {
        item(id: id)?.plainText
    }

    func imageData(id: UUID) -> Data? {
        item(id: id)?.imageData
    }

    // MARK: Maintenance

    /// Drop unpinned items older than `expireAfterDays`.
    func expireOldItems(now: Date = .now) {
        guard expireAfterDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(expireAfterDays) * 86_400)
        let doomed = items.filter { !$0.isPinned && $0.lastCopiedAt < cutoff }
        guard !doomed.isEmpty else { return }
        let ids = Set(doomed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        doomed.forEach(context.delete)
        save()
    }

    // MARK: - Private

    private func attach(_ contents: [ClipDraft.Content], to item: ClipItem) {
        for content in contents {
            let row = ClipContent(type: content.type, data: content.data)
            context.insert(row)
            row.item = item
        }
    }

    private func moveToTop(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        insertByRecency(item)
    }

    /// Keep `items` sorted by `lastCopiedAt` (newest first) even when captures arrive with earlier timestamps.
    private func insertByRecency(_ item: ClipItem) {
        let index = items.firstIndex { $0.lastCopiedAt <= item.lastCopiedAt } ?? items.count
        items.insert(item, at: index)
    }

    private func enforceLimit() {
        let unpinned = items.filter { !$0.isPinned }
        guard unpinned.count > maxItems else { return }
        let overflow = unpinned[maxItems...]
        let overflowIDs = Set(overflow.map(\.id))
        items.removeAll { overflowIDs.contains($0.id) }
        overflow.forEach(context.delete)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            logger.error("save failed: \(error.localizedDescription)")
        }
        publish()
    }

    private func publish() {
        rows = items.map { $0.makeRow() }
        version += 1
    }
}
