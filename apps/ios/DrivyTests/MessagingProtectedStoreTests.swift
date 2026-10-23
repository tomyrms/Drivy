import XCTest
import CryptoKit
@testable import Drivy

final class MessagingProtectedStoreTests: XCTestCase {
    func testDraftAndOutboxPersistAsSealedSnapshotAndRejectOtherScope() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 7,
                                   apiBaseURL: "https://example.invalid/")
        let store = try MessagingProtectedStore(scope: scope)
        let conversation = UUID()
        let pending = MessagingPending(clientMessageID: UUID(), conversationID: conversation,
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY:1", keyID: "fixture", payload: Data([9, 8, 7])))
        try await store.saveDraft("synthetic-draft-private", conversationID: conversation, scope: scope)
        try await store.put(pending, scope: scope)
        let restarted = try MessagingProtectedStore(scope: scope)
        let draft = try await restarted.loadDraft(conversationID: conversation, scope: scope)
        let queued = try await restarted.entries(scope: scope)
        XCTAssertEqual(draft, "synthetic-draft-private")
        XCTAssertEqual(queued.map(\.clientMessageID), [pending.clientMessageID])

        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        let fingerprint = SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("MessagingProtected")
        let bytes = try Data(contentsOf: directory.appendingPathComponent(fingerprint + ".sealed"))
        XCTAssertFalse(bytes.range(of: Data("synthetic-draft-private".utf8)) != nil)

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
}
