import XCTest
@testable import Drivy

final class MessagingCoreTests: XCTestCase {
    private let school = UUID()
    private let account = UUID()

    func testDefaultProtectionRefusesPlaintextAndDoesNotCreateOutboxEntry() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: UnavailableMessagingService(),
            currentScope: { scope })
        do {
            _ = try await coordinator.enqueue(text: "secret", conversationID: UUID(), currentScope: scope)
            XCTFail("Un chiffrement absent doit bloquer l'envoi")
        } catch MessagingFailure.protectionUnavailable { }
    }

    func testChangeOfAccountOrSchoolFailsClosed() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: UnavailableMessagingService(),
            currentScope: { scope })
        for changed in [MessagingScope(accountID: UUID(), schoolID: school, accessEpoch: 1),
                        MessagingScope(accountID: account, schoolID: UUID(), accessEpoch: 1),
                        MessagingScope(accountID: account, schoolID: school, accessEpoch: 2)] {
            do {
                _ = try await coordinator.enqueue(text: "secret", conversationID: UUID(), currentScope: changed)
                XCTFail("Le changement de contexte doit bloquer")
            } catch MessagingFailure.contextChanged { }
        }
    }

    func testRetryKeepsIdentityAfterLostResponseAndOnlyAcceptsMatchingAck() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let service = ResponseLostService()
        let outbox = MemoryCiphertextOutbox()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        let entry = try await coordinator.enqueue(text: "bonjour", conversationID: UUID(), currentScope: scope)
        if case .failed = await coordinator.retry(entry, currentScope: scope) {} else { XCTFail("Première réponse perdue") }
        let queuedAfterLoss = try await outbox.entries(scope: scope)
        XCTAssertEqual(queuedAfterLoss.count, 1)
        if case .accepted(let ack) = await coordinator.retry(entry, currentScope: scope) {
            XCTAssertEqual(ack.clientMessageID, entry.clientMessageID)
        } else { XCTFail("Second essai confirmé") }
        let queuedAfterAck = try await outbox.entries(scope: scope)
        let receivedIDs = await service.ids()
        XCTAssertEqual(queuedAfterAck.count, 0)
        XCTAssertEqual(receivedIDs, [entry.clientMessageID, entry.clientMessageID])
    }
    func testWrongSenderAcknowledgementKeepsOutboxPending() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: WrongSenderService(),
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        let entry = try await coordinator.enqueue(text: "fixture", conversationID: UUID(), currentScope: scope)
        if case .failed(.invalidResponse) = await coordinator.retry(entry, currentScope: scope) {}
        else { XCTFail("Un accusé attribué à un autre compte doit être refusé") }
        let pending = try await outbox.entries(scope: scope)
        XCTAssertEqual(pending.map(\.clientMessageID), [entry.clientMessageID])
    }

    func testOversizedEncryptedEnvelopeNeverEntersOutbox() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: UnavailableMessagingService(),
            cryptography: OversizedSyntheticCipher(), outbox: outbox, currentScope: { scope })
        do {
            _ = try await coordinator.enqueue(text: String(repeating: "x", count: 16_000),
                conversationID: UUID(), currentScope: scope)
            XCTFail("L'enveloppe trop grande ne doit pas être enregistrée")
        } catch MessagingFailure.invalidResponse { }
        let pending = try await outbox.entries(scope: scope)
        XCTAssertTrue(pending.isEmpty)
    }

    func testResumeLimitsAttemptsToTwentyWithoutReencryptingOrChangingIDs() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let service = CountingUnavailableService()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        for _ in 0..<25 {
            let entry = MessagingPending(clientMessageID: UUID(), conversationID: UUID(),
                ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1, 2, 3])))
            try await outbox.put(entry, scope: scope)
        }
        let results = await coordinator.flushPending(currentScope: scope)
        XCTAssertEqual(results.count, 20)
        let sent = await service.sentIDs()
        XCTAssertEqual(sent.count, 20)
        let pending = try await outbox.entries(scope: scope)
        XCTAssertEqual(pending.count, 25)
        XCTAssertTrue(Set(sent).isSubset(of: Set(pending.map(\.clientMessageID))))
    }

    func testResumeStopsAtFirstAccessRevocation() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let service = RevokedService()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        for _ in 0..<3 {
            try await outbox.put(MessagingPending(clientMessageID: UUID(), conversationID: UUID(),
                ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1]))), scope: scope)
        }
        let results = await coordinator.flushPending(currentScope: scope)
        XCTAssertEqual(results.count, 1)
        let attempts = await service.attemptCount()
        let pending = try await outbox.entries(scope: scope)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(pending.count, 3)
    }

    @MainActor func testOutOfOrderReadStateNeverRestoresOldMuteOrLowersProgress() {
        let oldMute = Date(timeIntervalSince1970: 1_000)
        let previous = MessagingReadState(lastReadSequence: 9, mutedUntil: nil, version: 5)
        let stale = MessagingReadState(lastReadSequence: 3, mutedUntil: oldMute, version: 4)
        let ignored = MessagingWorkspace.mergedReadState(previous: previous, incoming: stale)
        XCTAssertEqual(ignored.version, 5)
        XCTAssertEqual(ignored.lastReadSequence, 9)
        XCTAssertNil(ignored.mutedUntil)
        let latest = MessagingReadState(lastReadSequence: 8, mutedUntil: oldMute, version: 6)
        let merged = MessagingWorkspace.mergedReadState(previous: ignored, incoming: latest)
        XCTAssertEqual(merged.version, 6)
        XCTAssertEqual(merged.lastReadSequence, 9)
        XCTAssertEqual(merged.mutedUntil, oldMute)
    }
}

private actor RevokedService: MessagingService {
    private var attempts = 0
    func attemptCount() -> Int { attempts }
    func conversations(scope: MessagingScope, cursor: String?) throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) throws -> MessagingAcknowledgement {
        attempts += 1
        throw MessagingFailure.accessChanged
    }
}

private struct OversizedSyntheticCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data(repeating: 1, count: 9_001))
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { Data() }
}

private actor CountingUnavailableService: MessagingService {
    private var sent: [UUID] = []
    func sentIDs() -> [UUID] { sent }
    func conversations(scope: MessagingScope, cursor: String?) throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) throws -> MessagingAcknowledgement {
        sent.append(pending.clientMessageID)
        throw MessagingFailure.unavailable
    }
}

private actor WrongSenderService: MessagingService {
    func conversations(scope: MessagingScope, cursor: String?) throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) throws -> MessagingAcknowledgement {
        MessagingAcknowledgement(clientMessageID: pending.clientMessageID, serverMessageID: UUID(),
            conversationID: pending.conversationID, schoolID: scope.schoolID, acceptedAt: Date(), senderID: UUID())
    }
}

/// Substituts exclusivement synthétiques : ne constituent ni chiffrement ni stockage de production.
private struct SyntheticCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1, 2, 3]))
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { Data() }
}

private actor MemoryCiphertextOutbox: MessagingProtectedOutbox {
    private var entriesByID: [UUID: MessagingPending] = [:]
    func put(_ entry: MessagingPending, scope: MessagingScope) throws { entriesByID[entry.clientMessageID] = entry }
    func entries(scope: MessagingScope) throws -> [MessagingPending] { Array(entriesByID.values) }
    func remove(clientMessageID: UUID, scope: MessagingScope) throws { entriesByID.removeValue(forKey: clientMessageID) }
}

private actor ResponseLostService: MessagingService {
    private var received: [UUID] = []
    func ids() -> [UUID] { received }
    func conversations(scope: MessagingScope, cursor: String?) throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) throws -> MessagingAcknowledgement {
        received.append(pending.clientMessageID)
        if received.count == 1 { throw MessagingFailure.unavailable }
        return MessagingAcknowledgement(clientMessageID: pending.clientMessageID, serverMessageID: UUID(),
            conversationID: pending.conversationID, schoolID: scope.schoolID, acceptedAt: Date(),
            senderID: scope.accountID)
    }
}
