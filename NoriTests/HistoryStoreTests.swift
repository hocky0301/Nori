import Foundation
import SwiftData
import Testing
@testable import Nori

@Suite("HistoryStore", .serialized)
@MainActor
struct HistoryStoreTests {
    /// SwiftData traps when several containers for the same models live in one process,
    /// so tests share the app's in-memory container and start from an empty store.
    private func makeStore() throws -> HistoryStore {
        let store = HistoryStore(context: Storage.shared.context)
        store.load()
        store.clear(includingPinned: true)
        return store
    }

    private func textDraft(_ text: String, app: String = "com.apple.Notes") -> ClipDraft {
        var draft = ClipClassifier.makeDraft(contents: [.init(type: PasteboardType.utf8PlainText, data: Data(text.utf8))])!
        draft.sourceBundleID = app
        return draft
    }

    @Test func ingestOrdersNewestFirst() throws {
        let store = try makeStore()
        store.ingest(textDraft("one"), now: Date(timeIntervalSince1970: 1))
        store.ingest(textDraft("two"), now: Date(timeIntervalSince1970: 2))
        #expect(store.rows.map(\.title) == ["two", "one"])
    }

    @Test func duplicatesBumpInsteadOfInserting() throws {
        let store = try makeStore()
        let first = store.ingest(textDraft("same"), now: Date(timeIntervalSince1970: 1))
        store.ingest(textDraft("other"), now: Date(timeIntervalSince1970: 2))
        let again = store.ingest(textDraft("same", app: "com.apple.Safari"), now: Date(timeIntervalSince1970: 3))
        #expect(again == first)
        #expect(store.rows.count == 2)
        let row = try #require(store.row(id: again))
        #expect(store.rows.first?.id == again)
        #expect(row.copyCount == 2)
        #expect(row.sourceBundleID == "com.apple.Safari")
        #expect(row.firstCopiedAt == Date(timeIntervalSince1970: 1))
        #expect(row.lastCopiedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func limitDropsOldestUnpinned() throws {
        let store = try makeStore()
        store.maxItems = 3
        for i in 0..<5 {
            store.ingest(textDraft("item \(i)"), now: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        #expect(store.rows.map(\.title) == ["item 4", "item 3", "item 2"])
    }

    @Test func loweringTheLimitPersistsTheEvictions() throws {
        let store = try makeStore()
        for i in 0..<5 {
            store.ingest(textDraft("item \(i)"), now: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        store.maxItems = 2
        #expect(store.rows.map(\.title) == ["item 4", "item 3"])
        // A fresh context sees only what was saved.
        let fresh = ModelContext(Storage.shared.container)
        #expect(try fresh.fetchCount(FetchDescriptor<ClipItem>()) == 2)
    }

    @Test func unpinningAtTheLimitKeepsTheItem() throws {
        let store = try makeStore()
        store.maxItems = 2
        let old = store.ingest(textDraft("old"), now: Date(timeIntervalSince1970: 0))
        store.togglePin(id: old)
        store.ingest(textDraft("a"), now: Date(timeIntervalSince1970: 1))
        store.ingest(textDraft("b"), now: Date(timeIntervalSince1970: 2))
        store.togglePin(id: old)
        #expect(store.row(id: old)?.isPinned == false)
        #expect(store.rows.map(\.title) == ["b", "a", "old"], "the cap applies on the next capture, not now")
        store.ingest(textDraft("c"), now: Date(timeIntervalSince1970: 3))
        #expect(store.rows.map(\.title) == ["c", "b"])
    }

    @Test func restoreMergesIntoARowWithTheSameContent() throws {
        let store = try makeStore()
        let original = store.ingest(textDraft("same"), now: Date(timeIntervalSince1970: 1))
        store.togglePin(id: original, now: Date(timeIntervalSince1970: 2))
        let record = try #require(store.delete(id: original))
        // Re-copied within the undo window: a fresh row exists when ⌘Z arrives.
        let again = store.ingest(textDraft("same"), now: Date(timeIntervalSince1970: 5))
        let restored = store.restore(record)
        #expect(restored == again)
        #expect(store.rows.count == 1)
        let row = try #require(store.row(id: again))
        #expect(row.copyCount == 2)
        #expect(row.firstCopiedAt == Date(timeIntervalSince1970: 1))
        #expect(row.lastCopiedAt == Date(timeIntervalSince1970: 5))
        #expect(row.isPinned)
    }

    @Test func payloadsAreReadOnDemand() throws {
        let store = try makeStore()
        let id = store.ingest(textDraft("payload"), now: Date(timeIntervalSince1970: 1))
        #expect(store.contents(id: id).map(\.type) == [PasteboardType.utf8PlainText])
        #expect(store.plainText(id: id) == "payload")
        #expect(store.imageData(id: id) == nil)
        #expect(store.contents(id: UUID()).isEmpty)
        store.delete(id: id)
        #expect(store.contents(id: id).isEmpty)
        #expect(store.plainText(id: id) == nil)
    }

    @Test func pinnedItemsSurviveLimitAndClear() throws {
        let store = try makeStore()
        store.maxItems = 2
        let keep = store.ingest(textDraft("keep"), now: Date(timeIntervalSince1970: 0))
        store.togglePin(id: keep)
        for i in 1...4 {
            store.ingest(textDraft("item \(i)"), now: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        #expect(store.rows.contains { $0.id == keep })
        #expect(store.rows.filter { !$0.isPinned }.count == 2)

        #expect(store.clear(includingPinned: false) == 2)
        #expect(store.rows.map(\.title) == ["keep"])
        store.clear(includingPinned: true)
        #expect(store.rows.isEmpty)
    }

    @Test func deleteUndoAndPersistence() throws {
        let store = try makeStore()
        let a = store.ingest(textDraft("a"), now: Date(timeIntervalSince1970: 1))
        store.togglePin(id: a, now: Date(timeIntervalSince1970: 5))
        store.ingest(textDraft("b"), now: Date(timeIntervalSince1970: 2))
        let record = try #require(store.delete(id: a))
        #expect(store.rows.map(\.title) == ["b"])
        store.load()
        #expect(store.rows.map(\.title) == ["b"])

        let restored = store.restore(record)
        let row = try #require(store.row(id: restored))
        #expect(row.title == "a")
        #expect(row.isPinned)
        #expect(row.firstCopiedAt == Date(timeIntervalSince1970: 1))
        #expect(store.rows.map(\.title) == ["b", "a"])
    }

    @Test func touchMovesToTop() throws {
        let store = try makeStore()
        let a = store.ingest(textDraft("a"), now: Date(timeIntervalSince1970: 1))
        store.ingest(textDraft("b"), now: Date(timeIntervalSince1970: 2))
        store.touch(id: a, now: Date(timeIntervalSince1970: 3))
        #expect(store.rows.first?.id == a)
        #expect(store.row(id: a)?.copyCount == 2)
    }

    @Test func expiryDropsOldUnpinnedOnly() throws {
        let store = try makeStore()
        store.expireAfterDays = 7
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let old = store.ingest(textDraft("old"), now: now.addingTimeInterval(-10 * 86_400))
        let oldPinned = store.ingest(textDraft("old pinned"), now: now.addingTimeInterval(-10 * 86_400))
        store.togglePin(id: oldPinned, now: now)
        store.ingest(textDraft("fresh"), now: now.addingTimeInterval(-86_400))
        store.expireOldItems(now: now)
        #expect(store.row(id: old) == nil)
        #expect(store.rows.map(\.title).sorted() == ["fresh", "old pinned"])
    }
}
