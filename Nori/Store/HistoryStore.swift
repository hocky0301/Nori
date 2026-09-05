import Foundation
import Observation
import OSLog
import SwiftData

/// The in-memory, observable view of the history, backed by SwiftData.
///
/// All mutation goes through here so ordering, de-duplication and the size limit
/// are enforced in one place.
@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [ClipItem] = []
    /// Bumped on every mutation; views that cache derived arrays key off it.
    private(set) var version = 0
    var maxItems: Int = 500 {
        didSet { if maxItems != oldValue { enforceLimit() } }
    }

    private let context: ModelContext
    private let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "history")

    init(context: ModelContext) {
        self.context = context
    }

    var pinnedItems: [ClipItem] {
        items.filter(\.isPinned).sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
    }

    var unpinnedItems: [ClipItem] {
        items.filter { !$0.isPinned }
    }

    func load() {
        var descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)])
        descriptor.includePendingChanges = true
        do {
            items = try context.fetch(descriptor)
        } catch {
            logger.error("fetch failed: \(error.localizedDescription)")
            items = []
        }
        enforceLimit()
        version += 1
    }

    func item(id: UUID) -> ClipItem? {
        items.first { $0.id == id }
    }

    /// Insert a new capture, or refresh the existing entry with identical content.
    @discardableResult
    func ingest(_ draft: ClipDraft, now: Date = .now) -> ClipItem {
        if let existing = items.first(where: { $0.contentHash == draft.contentHash }) {
            existing.lastCopiedAt = now
            existing.copyCount += 1
            if let bundle = draft.sourceBundleID { existing.sourceBundleID = bundle }
            moveToTop(existing)
            save()
            return existing
        }

        let item = ClipItem(draft: draft, now: now)
        context.insert(item)
        for content in draft.contents {
            let row = ClipContent(type: content.type, data: content.data)
            context.insert(row)
            row.item = item
        }
        items.insert(item, at: 0)
        enforceLimit()
        save()
        return item
    }

    /// Called when the user pasted an item through Nori: it becomes the most recent copy again.
    func touch(_ item: ClipItem, now: Date = .now) {
        item.lastCopiedAt = now
        item.copyCount += 1
        moveToTop(item)
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        context.delete(item)
        save()
    }

    func delete(ids: Set<UUID>) {
        let doomed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        doomed.forEach(context.delete)
        save()
    }

    /// Remove history. Pinned items survive unless `includingPinned` is set.
    func clear(includingPinned: Bool) {
        let doomed = includingPinned ? items : items.filter { !$0.isPinned }
        items.removeAll { item in doomed.contains { $0.id == item.id } }
        doomed.forEach(context.delete)
        save()
    }

    func togglePin(_ item: ClipItem, now: Date = .now) {
        item.pinnedAt = item.isPinned ? nil : now
        version += 1
        enforceLimit()
        save()
    }

    /// Update the searchable text of an item (used when OCR finishes for an image).
    func updateSearchText(id: UUID, text: String) {
        guard let item = item(id: id) else { return }
        item.searchText = String(text.prefix(ClipDraft.maxSearchTextLength))
        version += 1
        save()
    }

    var totalBytes: Int { items.reduce(0) { $0 + $1.byteCount } }

    // MARK: - Private

    private func moveToTop(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
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
        version += 1
        do {
            try context.save()
        } catch {
            logger.error("save failed: \(error.localizedDescription)")
        }
    }
}
