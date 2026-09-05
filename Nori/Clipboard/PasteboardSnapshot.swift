import AppKit

/// A value copy of everything on the general pasteboard at one `changeCount`.
///
/// Reading the pasteboard has to happen on the main thread, but everything after
/// that (classification, hashing, ignore rules) works on this Sendable snapshot.
struct PasteboardSnapshot: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        /// Pasteboard types in declaration order, mapped to their bytes (nil when the app refused to provide data).
        var representations: [(type: String, data: Data?)]

        var types: [String] { representations.map(\.type) }

        func data(for type: String) -> Data? {
            representations.first(where: { $0.type == type })?.data ?? nil
        }

        func string(for type: String) -> String? {
            data(for: type).flatMap { String(data: $0, encoding: .utf8) }
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.representations.map(\.type) == rhs.representations.map(\.type)
                && lhs.representations.map(\.data) == rhs.representations.map(\.data)
        }
    }

    var changeCount: Int
    /// Pasteboard-level types (a superset of every item's types; some apps declare types they never put on an item).
    var declaredTypes: Set<String>
    var items: [Item]
    var sourceBundleID: String?
    var capturedAt: Date

    init(changeCount: Int, declaredTypes: Set<String>, items: [Item], sourceBundleID: String?, capturedAt: Date = .now) {
        self.changeCount = changeCount
        self.declaredTypes = declaredTypes
        self.items = items
        self.sourceBundleID = sourceBundleID
        self.capturedAt = capturedAt
    }

    /// Snapshot the general pasteboard. Must run on the main actor because `NSPasteboard` is not thread-safe.
    @MainActor
    static func capture(from pasteboard: NSPasteboard = .general, sourceBundleID: String?) -> PasteboardSnapshot {
        let items: [Item] = (pasteboard.pasteboardItems ?? []).map { item in
            Item(representations: item.types.map { ($0.rawValue, item.data(forType: $0)) })
        }
        return PasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            declaredTypes: Set((pasteboard.types ?? []).map(\.rawValue)),
            items: items,
            sourceBundleID: sourceBundleID
        )
    }

    var hasNoriMarker: Bool { declaredTypes.contains(PasteboardType.noriItem) }

    /// The UUID Nori wrote when it restored an item, if this change came from Nori itself.
    var noriItemID: UUID? {
        for item in items {
            if let text = item.string(for: PasteboardType.noriItem), let id = UUID(uuidString: text) {
                return id
            }
        }
        return nil
    }
}
