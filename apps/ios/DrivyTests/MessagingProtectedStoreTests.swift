import XCTest
import CryptoKit
import Security
@testable import Drivy

final class MessagingProtectedStoreTests: XCTestCase {
    func testMutationJournalSurvivesReopeningWithoutBeingErasedByDraftWrites() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2, apiBaseURL: "https://example.invalid/")
        let first = try MessagingProtectedStore(scope: scope), second = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await first.purge(scope: scope) }
        let key = MessagingMutationKey(conversationID: UUID(), messageID: UUID(), kind: .reaction("👍"))
        var pending = MessagingPendingMutation(id: UUID(), desired: .active(false), startedAt: Date(), status: .uncertain)
        pending.transmitting = .active(true)
        let entry = MessagingStoredMutation(key: key, value: pending)
        try await first.putMutation(entry, replacing: nil, scope: scope)
        try await second.saveDraft("synthetic-private-draft", conversationID: key.conversationID, scope: scope)
        let reopened = try MessagingProtectedStore(scope: scope)
        let restored = try await reopened.mutationEntries(scope: scope)
        XCTAssertEqual(restored, [entry])
        let draft = try await reopened.loadDraft(conversationID: key.conversationID, scope: scope)
        XCTAssertEqual(draft, "synthetic-private-draft")
        let bytes = try Data(contentsOf: mutationSnapshotFile(scope))
        XCTAssertNil(bytes.range(of: Data(key.messageID.uuidString.utf8)))
        XCTAssertNil(bytes.range(of: Data("transmitting".utf8)))
        XCTAssertNil(bytes.range(of: Data("👍".utf8)))
    }

    func testStaleMutationWriterAndAcknowledgementCannotEraseNewerChoice() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2, apiBaseURL: "https://example.invalid/")
        let first = try MessagingProtectedStore(scope: scope), second = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await first.purge(scope: scope) }
        let key = MessagingMutationKey(conversationID: UUID(), messageID: UUID(), kind: .pin)
        let original = MessagingPendingMutation(id: UUID(), desired: .active(true), startedAt: Date(), status: .sending)
        try await first.putMutation(.init(key: key, value: original), replacing: nil, scope: scope)
        var latest = original; latest.clock = UUID(); latest.desired = .active(false)
        try await second.putMutation(.init(key: key, value: latest), replacing: original.clock, scope: scope)
        try await first.removeMutation(key, id: original.id, clock: original.clock, scope: scope)
        do {
            try await first.putMutation(.init(key: key, value: original), replacing: original.clock, scope: scope)
            XCTFail("Une ancienne instance ne peut écraser le dernier choix")
        } catch MessagingFailure.stateConflict {}
        let restored = try await first.mutationEntries(scope: scope)
        XCTAssertEqual(restored.first?.value, latest)
        try await second.removeMutation(key, id: latest.id, clock: latest.clock, scope: scope)
        do {
            try await first.putMutation(.init(key: key, value: original), replacing: original.clock, scope: scope)
            XCTFail("Une réponse ancienne ne ressuscite pas l'intention")
        } catch MessagingFailure.stateConflict {}
    }

    func testMutationJournalRejectsOtherContextAndCorruptionWithoutReplacingBytes() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2, apiBaseURL: "https://example.invalid/")
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let entry = MessagingStoredMutation(key: .init(conversationID: UUID(), messageID: UUID(), kind: .vote),
            value: .init(id: UUID(), desired: .options(["choice-1"]), startedAt: Date(), status: .offline))
        try await store.putMutation(entry, replacing: nil, scope: scope)
        for other in [
            MessagingScope(accountID: UUID(), schoolID: scope.schoolID, accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: UUID(), accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID, accessEpoch: 3, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID, accessEpoch: scope.accessEpoch, apiBaseURL: "https://other.example.invalid/")
        ] {
            do { _ = try await store.mutationEntries(scope: other); XCTFail("Périmètre différent accepté") }
            catch MessagingFailure.contextChanged {}
            let isolated = try MessagingProtectedStore(scope: other)
            let empty = try await isolated.mutationEntries(scope: other)
            XCTAssertTrue(empty.isEmpty)
        }
        let file = try mutationSnapshotFile(scope)
        var damaged = try Data(contentsOf: file); damaged[damaged.count - 1] ^= 1
        try damaged.write(to: file)
        do { _ = try await store.mutationEntries(scope: scope); XCTFail("Journal corrompu accepté") }
        catch MessagingFailure.protectionUnavailable {}
        do { try await store.putMutation(entry, replacing: entry.value.clock, scope: scope); XCTFail("Journal corrompu remplacé") }
        catch MessagingFailure.protectionUnavailable {}
        XCTAssertEqual(try Data(contentsOf: file), damaged)
    }

    private func mutationSnapshotFile(_ scope: MessagingScope) throws -> URL {
        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        let fingerprint = SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
        return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("MessagingProtected")
            .appendingPathComponent(fingerprint + "-mutations.sealed")
    }

    func testDraftAndOutboxPersistAsSealedSnapshotAndRejectOtherScope() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 7,
                                   apiBaseURL: "https://example.invalid/")
        let store = try MessagingProtectedStore(scope: scope)
        let conversation = UUID()
        let pending = MessagingPending(clientMessageID: UUID(), conversationID: conversation,
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY:1", keyID: "fixture", payload: Data([9, 8, 7]), expectedMembersEpoch: 13),
            recoveryContent: Data("synthetic-recovery-private".utf8))
        try await store.saveDraft("synthetic-draft-private", conversationID: conversation, scope: scope)
        try await store.put(pending, scope: scope)
        let restarted = try MessagingProtectedStore(scope: scope)
        let draft = try await restarted.loadDraft(conversationID: conversation, scope: scope)
        let queued = try await restarted.entries(scope: scope)
        XCTAssertEqual(draft, "synthetic-draft-private")
        XCTAssertEqual(queued.map(\.clientMessageID), [pending.clientMessageID])
        XCTAssertEqual(queued.first?.ciphertext.expectedMembersEpoch, 13)
        XCTAssertEqual(queued.first?.recoveryContent, pending.recoveryContent)
        for replacement in [
            MessagingPending(clientMessageID: pending.clientMessageID, conversationID: conversation,
                ciphertext: MessagingCiphertext(scheme: "TEST_ONLY:1", keyID: "fixture", payload: Data([9, 8, 7]), expectedMembersEpoch: 14),
                recoveryContent: pending.recoveryContent),
            MessagingPending(clientMessageID: pending.clientMessageID, conversationID: conversation,
                ciphertext: pending.ciphertext, recoveryContent: Data("autre contenu".utf8))
        ] {
            do {
                try await restarted.put(replacement, scope: scope)
                XCTFail("Une intention durable ne change ni d'époque ni de contenu")
            } catch MessagingFailure.invalidResponse {}
        }
        let unchanged = try await restarted.entries(scope: scope)
        XCTAssertEqual(unchanged.first?.ciphertext, pending.ciphertext)
        XCTAssertEqual(unchanged.first?.recoveryContent, pending.recoveryContent)

        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        let fingerprint = SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("MessagingProtected")
        let bytes = try Data(contentsOf: directory.appendingPathComponent(fingerprint + ".sealed"))
        XCTAssertFalse(bytes.range(of: Data("synthetic-draft-private".utf8)) != nil)
        XCTAssertNil(bytes.range(of: Data("synthetic-recovery-private".utf8)))

        let other = MessagingScope(accountID: UUID(), schoolID: scope.schoolID,
                                   accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL)
        do {
            _ = try await restarted.loadDraft(conversationID: conversation, scope: other)
            XCTFail("Le stockage ne peut changer de compte")
        } catch MessagingFailure.contextChanged { }
        try await restarted.purge(scope: scope)
    }

    func testConcurrentInstancesDoNotLosePendingEntries() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                   apiBaseURL: "https://example.invalid/")
        let first = try MessagingProtectedStore(scope: scope)
        let second = try MessagingProtectedStore(scope: scope)
        let entries = (0..<20).map { _ in MessagingPending(clientMessageID: UUID(), conversationID: UUID(),
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY:1", keyID: "fixture", payload: Data([7]))) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask { try await (index.isMultiple(of: 2) ? first : second).put(entry, scope: scope) }
            }
            try await group.waitForAll()
        }
        let persisted = try await first.entries(scope: scope)
        XCTAssertEqual(Set(persisted.map(\.clientMessageID)), Set(entries.map(\.clientMessageID)))
        try await first.purge(scope: scope)
    }

    func testNoStorageWithoutScopeAPIAndEpoch() throws {
        XCTAssertThrowsError(try MessagingProtectedStore(scope: MessagingScope(
            accountID: UUID(), schoolID: UUID(), accessEpoch: 0, apiBaseURL: "")))
    }

    func testReportPersistsExactEnvelopeAndRejectsEveryOtherScope() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 3, apiBaseURL: "https://example.invalid/")
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let report = reportFixture()
        _ = try await store.prepareReport(report, scope: scope)
        let reopened = try MessagingProtectedStore(scope: scope)
        let restored = try await reopened.pendingReport(conversationID: report.conversationID, scope: scope)
        XCTAssertTrue(restored == report, "L'identifiant, la sélection et les octets doivent survivre à la réouverture.")
        let bytes = try Data(contentsOf: reportSnapshotFile(scope))
        XCTAssertNil(bytes.range(of: report.items[0].ciphertext.payload), "Même les enveloppes E2EE restent scellées au repos.")
        XCTAssertNil(bytes.range(of: Data(report.clientReportID.uuidString.utf8)))
        for other in [
            MessagingScope(accountID: UUID(), schoolID: scope.schoolID, accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: UUID(), accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID, accessEpoch: 4, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID, accessEpoch: scope.accessEpoch, apiBaseURL: "https://other.invalid/")
        ] {
            do {
                _ = try await reopened.pendingReport(conversationID: report.conversationID, scope: other)
                XCTFail("Un autre contexte ne doit pas relire cette intention.")
            } catch MessagingFailure.contextChanged {}
            let otherStore = try MessagingProtectedStore(scope: other)
            let foreign = try await otherStore.pendingReport(conversationID: report.conversationID, scope: other)
            XCTAssertTrue(foreign == nil)
        }
    }

    func testReportSelectionReplacementSurvivesStaleAcknowledgement() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: "https://example.invalid/")
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let first = reportFixture()
        _ = try await store.prepareReport(first, scope: scope)
        let sameSelection = MessagingPendingReport(clientReportID: UUID(), conversationID: first.conversationID,
            items: [MessagingReportItem(messageID: first.items[0].messageID,
                ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "different", payload: Data([7])))])
        let reused = try await store.prepareReport(sameSelection, scope: scope)
        XCTAssertTrue(reused == first, "Une autre instance ne doit pas remplacer les octets d'une même intention.")
        let changedSelection = MessagingPendingReport(clientReportID: UUID(), conversationID: first.conversationID,
                                                      items: reportFixture().items)
        _ = try await store.prepareReport(changedSelection, scope: scope)
        try await store.removeReport(conversationID: first.conversationID, clientReportID: first.clientReportID, scope: scope)
        let reopened = try MessagingProtectedStore(scope: scope)
        let retained = try await reopened.pendingReport(conversationID: first.conversationID, scope: scope)
        XCTAssertTrue(retained == changedSelection, "Un ancien ACK ne doit pas effacer la nouvelle sélection.")
        try await reopened.removeReport(conversationID: first.conversationID, clientReportID: changedSelection.clientReportID, scope: scope)
        let removed = try await store.pendingReport(conversationID: first.conversationID, scope: scope)
        XCTAssertTrue(removed == nil)
    }

    func testConcurrentReportPreparationReturnsSingleDurableIntention() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: "https://example.invalid/")
        let firstStore = try MessagingProtectedStore(scope: scope)
        let secondStore = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await firstStore.purge(scope: scope) }
        let candidate = reportFixture()
        let other = MessagingPendingReport(clientReportID: UUID(), conversationID: candidate.conversationID, items: candidate.items)
        async let first = firstStore.prepareReport(candidate, scope: scope)
        async let second = secondStore.prepareReport(other, scope: scope)
        let (a, b) = try await (first, second)
        XCTAssertTrue(a == b)
        let durable = try await secondStore.pendingReport(conversationID: candidate.conversationID, scope: scope)
        XCTAssertTrue(durable == a)
    }

    func testLegacySealedSnapshotWithoutReportsKeepsDraftAndOutbox() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: "https://example.invalid/")
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let conversation = UUID()
        try await store.saveDraft("SYNTHETIC_LEGACY_DRAFT", conversationID: conversation, scope: scope)
        let pending = MessagingPending(clientMessageID: UUID(), conversationID: conversation,
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "legacy", payload: Data([1])))
        struct LegacySnapshot: Codable {
            let scopeFingerprint: String
            let pending: [MessagingPending]
            let drafts: [UUID: String]
        }
        let fingerprint = reportFingerprint(scope)
        let legacy = LegacySnapshot(scopeFingerprint: fingerprint, pending: [pending], drafts: [conversation: "SYNTHETIC_LEGACY_DRAFT"])
        let sealed = try AES.GCM.seal(JSONEncoder().encode(legacy), using: reportFixtureStorageKey(), authenticating: Data(fingerprint.utf8))
        try XCTUnwrap(sealed.combined).write(to: reportSnapshotFile(scope), options: [.atomic])
        let reopened = try MessagingProtectedStore(scope: scope)
        let before = try await reopened.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertTrue(before == nil)
        _ = try await reopened.prepareReport(reportFixture(), scope: scope)
        let draft = try await reopened.loadDraft(conversationID: conversation, scope: scope)
        let queue = try await reopened.entries(scope: scope)
        XCTAssertEqual(draft, "SYNTHETIC_LEGACY_DRAFT")
        XCTAssertTrue(queue.first?.clientMessageID == pending.clientMessageID)
    }

    func testCorruptReportSnapshotFailsClosedWithoutReplacement() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: "https://example.invalid/")
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let report = reportFixture()
        _ = try await store.prepareReport(report, scope: scope)
        let corrupt = Data([0, 1, 2])
        let file = try reportSnapshotFile(scope)
        try corrupt.write(to: file, options: [.atomic])
        let reopened = try MessagingProtectedStore(scope: scope)
        do {
            _ = try await reopened.prepareReport(reportFixture(), scope: scope)
            XCTFail("Ne jamais remplacer un snapshot illisible par une intention neuve.")
        } catch MessagingFailure.protectionUnavailable {}
        XCTAssertTrue(try Data(contentsOf: file) == corrupt)
    }

    private func reportFixture() -> MessagingPendingReport {
        MessagingPendingReport(clientReportID: UUID(), conversationID: UUID(), items: [
            MessagingReportItem(messageID: UUID(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "admins",
                payload: Data("SYNTHETIC_OPAQUE_REPORT_ENVELOPE".utf8)))
        ])
    }

    private func reportFingerprint(_ scope: MessagingScope) -> String {
        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        return SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func reportSnapshotFile(_ scope: MessagingScope) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("MessagingProtected").appendingPathComponent(reportFingerprint(scope) + ".sealed")
    }

    /// Test fixture only: writes an authentic pre-upgrade snapshot, never prints Keychain bytes.
    private func reportFixtureStorageKey() throws -> SymmetricKey {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ch.drivy.messaging.local.v1", kSecAttrAccount as String: "protected-snapshot-key",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw MessagingFailure.protectionUnavailable
        }
        return SymmetricKey(data: data)
    }
}
