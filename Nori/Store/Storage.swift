import Foundation
import OSLog
import SwiftData

/// Owns the SwiftData container. History lives in
/// `~/Library/Application Support/Nori/History.store`; tests and `--in-memory` use RAM.
@MainActor
final class Storage {
    static let shared = Storage()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let storeURL: URL?
    /// Set when the on-disk store could not be opened and was moved aside.
    private(set) var recoveredFromCorruption = false

    private static let logger = Logger(subsystem: "io.github.hocky0301.Nori", category: "storage")

    init(inMemory: Bool = Storage.shouldUseInMemoryStore) {
        let schema = Schema([ClipItem.self, ClipContent.self])
        if inMemory {
            storeURL = nil
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Nori cannot create its in-memory database: \(error)")
            }
        } else {
            let directory = URL.applicationSupportDirectory.appending(path: "Nori", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "History.store")
            storeURL = url
            do {
                container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
            } catch {
                // A corrupt or incompatible store must never take the app down: move it aside and start fresh.
                Self.logger.error("history store failed to open, moving aside: \(error.localizedDescription, privacy: .public)")
                Self.moveAside(url)
                do {
                    container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
                    recoveredFromCorruption = true
                } catch {
                    fatalError("Nori cannot open its history database: \(error)")
                }
            }
        }
        context.autosaveEnabled = false
    }

    private static func moveAside(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let target = URL(fileURLWithPath: url.path + ".broken-\(stamp)" + suffix)
            try? FileManager.default.moveItem(at: source, to: target)
        }
    }

    /// Size of the on-disk store, for the settings window.
    var storeSizeBytes: Int64 {
        guard let storeURL else { return 0 }
        var total: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(size) }
        }
        let external = storeURL.deletingLastPathComponent().appending(path: ".History_SUPPORT/_EXTERNAL_DATA")
        if let enumerator = FileManager.default.enumerator(at: external, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in enumerator {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(size) }
            }
        }
        return total
    }

    nonisolated static var shouldUseInMemoryStore: Bool {
        CommandLine.arguments.contains("--in-memory")
            || ProcessInfo.processInfo.environment["NORI_IN_MEMORY"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
