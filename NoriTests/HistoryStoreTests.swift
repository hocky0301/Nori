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
        #expect(store.items.map(\.title) == ["two", "one"])
    }

    @Test func duplicatesBumpInsteadOfInserting() throws {
        let store = try makeStore()
        store.ingest(textDraft("same"), now: Date(timeIntervalSince1970: 1))
        store.ingest(textDraft("other"), now: Date(timeIntervalSince1970: 2))
        let again = store.ingest(textDraft("same", app: "com.apple.Safari"), now: Date(timeIntervalSince1970: 3))
        #expect(store.items.count == 2)
        #expect(store.items.first?.id == again.id)
        #expect(again.copyCount == 2)
        #expect(again.sourceBundleID == "com.apple.Safari")
        #expect(again.firstCopiedAt == Date(timeIntervalSince1970: 1))
        #expect(again.lastCopiedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func limitDropsOldestUnpinned() throws {
        let store = try makeStore()
        store.maxItems = 3
        for i in 0..<5 {
            store.ingest(textDraft("item \(i)"), now: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        #expect(store.items.map(\.title) == ["item 4", "item 3", "item 2"])
    }

    @Test func pinnedItemsSurviveLimitAndClear() throws {
        let store = try makeStore()
        store.maxItems = 2
        let keep = store.ingest(textDraft("keep"), now: Date(timeIntervalSince1970: 0))
        store.togglePin(keep)
        for i in 1...4 {
            store.ingest(textDraft("item \(i)"), now: Date(timeIntervalSince1970: TimeInterval(i)))
        }
        #expect(store.items.contains { $0.id == keep.id })
        #expect(store.unpinnedItems.count == 2)

        store.clear(includingPinned: false)
        #expect(store.items.map(\.title) == ["keep"])
        store.clear(includingPinned: true)
        #expect(store.items.isEmpty)
    }

    @Test func deleteAndPersistence() throws {
        let store = try makeStore()
        let a = store.ingest(textDraft("a"))
        store.ingest(textDraft("b"))
        store.delete(a)
        #expect(store.items.map(\.title) == ["b"])
        store.load()
        #expect(store.items.map(\.title) == ["b"])
    }

    @Test func touchMovesToTop() throws {
        let store = try makeStore()
        let a = store.ingest(textDraft("a"), now: Date(timeIntervalSince1970: 1))
        store.ingest(textDraft("b"), now: Date(timeIntervalSince1970: 2))
        store.touch(a, now: Date(timeIntervalSince1970: 3))
        #expect(store.items.first?.id == a.id)
        #expect(a.copyCount == 2)
    }
}
