import Foundation
import Testing
@testable import Nori

/// Secrets live in memory only, masked, and are forgotten ten minutes after the last use.
@Suite("SensitiveVault")
@MainActor
struct SensitiveVaultTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let card = "4111 1111 1111 1111"
    private let awsKey = "AKIAIOSFODNN7EXAMPLE"

    @Test func addProducesAMaskedRowWithExpiry() throws {
        let vault = SensitiveVault()
        let id = vault.add(TestDrafts.sensitive(card), now: t0)
        #expect(vault.entries.count == 1)
        #expect(vault.version == 1)
        let entry = try #require(vault.entry(id: id))
        #expect(entry.match == .cardNumber)
        #expect(entry.capturedAt == t0)
        #expect(entry.expiresAt == t0.addingTimeInterval(SensitiveVault.lifetime))
        #expect(SensitiveVault.lifetime == 600)

        let row = try #require(vault.rows.first)
        #expect(row.id == id)
        #expect(row.isSensitive)
        #expect(row.title == "•••• •••• •••• 1111")
        #expect(!row.title.contains("4111"))
        #expect(row.searchText.isEmpty, "secrets are never indexed")
        #expect(row.expiresAt == entry.expiresAt)
        #expect(row.pinnedAt == nil)
        #expect(row.lastCopiedAt == t0)
    }

    @Test func identicalHashReAddExtendsExpiryAndMovesToTop() throws {
        let vault = SensitiveVault()
        let first = vault.add(TestDrafts.sensitive(card), now: t0)
        let second = vault.add(TestDrafts.sensitive(awsKey), now: t0.addingTimeInterval(1))
        #expect(vault.rows.map(\.id) == [second, first])

        let again = vault.add(TestDrafts.sensitive(card), now: t0.addingTimeInterval(300))
        #expect(again == first, "same content is the same entry")
        #expect(vault.entries.count == 2)
        #expect(vault.rows.map(\.id) == [first, second])
        let entry = try #require(vault.entry(id: first))
        #expect(entry.expiresAt == t0.addingTimeInterval(300 + SensitiveVault.lifetime))
        #expect(entry.capturedAt == t0, "the original capture date survives")
        #expect(vault.version == 3)
    }

    @Test func touchExtendsExpiryAndMovesToTop() throws {
        let vault = SensitiveVault()
        let first = vault.add(TestDrafts.sensitive(card), now: t0)
        let second = vault.add(TestDrafts.sensitive(awsKey), now: t0.addingTimeInterval(1))
        vault.touch(id: first, now: t0.addingTimeInterval(500))
        #expect(vault.rows.map(\.id) == [first, second])
        #expect(vault.entry(id: first)?.expiresAt == t0.addingTimeInterval(500 + SensitiveVault.lifetime))
        let version = vault.version
        vault.touch(id: UUID(), now: t0)
        #expect(vault.version == version, "touching an unknown id is a no-op")
    }

    @Test func sweepDropsOnlyExpiredEntries() {
        let vault = SensitiveVault()
        let old = vault.add(TestDrafts.sensitive(card), now: t0)
        let fresh = vault.add(TestDrafts.sensitive(awsKey), now: t0.addingTimeInterval(400))
        let version = vault.version

        vault.sweep(now: t0.addingTimeInterval(599))
        #expect(vault.entries.count == 2)
        #expect(vault.version == version, "nothing changed, nothing published")

        vault.sweep(now: t0.addingTimeInterval(600))
        #expect(vault.rows.map(\.id) == [fresh], "expiry is inclusive: expiresAt <= now")
        #expect(vault.entry(id: old) == nil)
        #expect(vault.version == version + 1)

        vault.sweep(now: t0.addingTimeInterval(1_000))
        #expect(vault.entries.isEmpty)
    }

    @Test func touchKeepsAnEntryAliveAcrossASweep() {
        let vault = SensitiveVault()
        let id = vault.add(TestDrafts.sensitive(card), now: t0)
        vault.touch(id: id, now: t0.addingTimeInterval(590))
        vault.sweep(now: t0.addingTimeInterval(700))
        #expect(vault.entries.count == 1)
        vault.sweep(now: t0.addingTimeInterval(590 + 600))
        #expect(vault.entries.isEmpty)
    }

    @Test func removeAndRemoveAll() {
        let vault = SensitiveVault()
        let a = vault.add(TestDrafts.sensitive(card), now: t0)
        let b = vault.add(TestDrafts.sensitive(awsKey), now: t0)
        vault.remove(id: a)
        #expect(vault.rows.map(\.id) == [b])
        #expect(vault.entry(id: a) == nil)
        let version = vault.version
        vault.removeAll()
        #expect(vault.entries.isEmpty)
        #expect(vault.rows.isEmpty)
        #expect(vault.version == version + 1)
    }

    @Test func rowsCarryTheDraftMetadata() throws {
        let vault = SensitiveVault()
        var sensitive = TestDrafts.sensitive(awsKey)
        sensitive.draft.sourceBundleID = "com.apple.Terminal"
        sensitive.draft.sourceAppName = "Terminal"
        vault.add(sensitive, now: t0)
        let row = try #require(vault.rows.first)
        #expect(row.sourceBundleID == "com.apple.Terminal")
        #expect(row.sourceAppName == "Terminal")
        #expect(row.characterCount == awsKey.count)
        #expect(row.byteCount == awsKey.utf8.count)
        #expect(row.copyCount == 1)
        #expect(row.title.hasSuffix("MPLE"))
    }
}
