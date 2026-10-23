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
