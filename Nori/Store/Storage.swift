import Foundation
import SwiftData

/// Owns the SwiftData container. History lives in
/// `~/Library/Application Support/Nori/History.store`; tests and `--in-memory` use RAM.
@MainActor
final class Storage {
    static let shared = Storage()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let storeURL: URL?

    init(inMemory: Bool = Storage.shouldUseInMemoryStore) {
        let schema = Schema([ClipItem.self, ClipContent.self])
        do {
            if inMemory {
                storeURL = nil
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [configuration])
            } else {
                let directory = URL.applicationSupportDirectory.appending(path: "Nori", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appending(path: "History.store")
                storeURL = url
                let configuration = ModelConfiguration(schema: schema, url: url)
                container = try ModelContainer(for: schema, configurations: [configuration])
            }
        } catch {
            fatalError("Nori cannot open its history database: \(error)")
        }
        context.autosaveEnabled = false
    }

    /// Size of the on-disk store, for the Storage settings pane.
    var storeSizeDescription: String {
        guard let storeURL else { return "In memory" }
        var total: Int64 = 0
        let candidates = [storeURL, storeURL.appendingPathExtension("wal"), storeURL.appendingPathExtension("shm")]
        for url in candidates {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        let external = storeURL.deletingLastPathComponent().appending(path: ".History_SUPPORT/_EXTERNAL_DATA")
        if let enumerator = FileManager.default.enumerator(at: external, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in enumerator {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    nonisolated static var shouldUseInMemoryStore: Bool {
        CommandLine.arguments.contains("--in-memory")
            || ProcessInfo.processInfo.environment["NORI_IN_MEMORY"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
