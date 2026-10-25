import XCTest
@testable import Drivy

final class MessagingCoreTests: XCTestCase {
    private let school = UUID()
    private let account = UUID()

    func testEnqueuePersistsEncryptionEpochAndRecoveryContent() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: UnavailableMessagingService(),
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        let entry = try await coordinator.enqueue(text: "contenu à conserver", conversationID: UUID(), currentScope: scope)
        XCTAssertEqual(entry.ciphertext.expectedMembersEpoch, 7)
        XCTAssertEqual(entry.recoveryContent, Data("contenu à conserver".utf8))
        let restored = try JSONDecoder().decode(MessagingPending.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(restored.ciphertext.expectedMembersEpoch, 7)
        XCTAssertEqual(restored.recoveryContent, entry.recoveryContent)
    }

    func testLegacyPendingWithoutEpochOrRecoveryStillDecodes() throws {
        let raw = """
        {"clientMessageID":"\(UUID())","conversationID":"\(UUID())","ciphertext":{"scheme":"TEST_ONLY","keyId":"fixture","payload":"AQID"}}
        """
        let entry = try JSONDecoder().decode(MessagingPending.self, from: Data(raw.utf8))
        XCTAssertNil(entry.ciphertext.expectedMembersEpoch)
        XCTAssertNil(entry.recoveryContent)
        XCTAssertEqual(entry.ciphertext.payload, Data([1, 2, 3]))
    }

    func testStaleMembersEpochKeepsOriginalEnvelopeAndProtectedRecoveryContent() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let service = StaleEpochService()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        let content = MessagingPlainContent(text: "à renvoyer volontairement")
        let entry = try await coordinator.enqueue(content: content, conversationID: UUID(), currentScope: scope)
        for _ in 0..<2 {
            if case .failed(.membersChanged) = await coordinator.retry(entry, currentScope: scope) {} else {
                XCTFail("Une époque périmée ne doit jamais être présentée comme un succès")
            }
        }
        let remaining = try await outbox.entries(scope: scope)
        XCTAssertEqual(remaining.map(\.clientMessageID), [entry.clientMessageID])
        XCTAssertEqual(remaining.first?.ciphertext, entry.ciphertext)
        XCTAssertEqual(remaining.first?.recoveryContent, try content.encoded())
        let sent = await service.sentEpochs()
        XCTAssertEqual(sent, [7, 7])
    }

    func testNewEnqueueWithoutEncryptionEpochFailsBeforePersistence() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: UnavailableMessagingService(),
            cryptography: MissingEpochCipher(), outbox: outbox, currentScope: { scope })
        do {
            _ = try await coordinator.enqueue(text: "à conserver", conversationID: UUID(), currentScope: scope)
            XCTFail("Une nouvelle enveloppe exige l'époque utilisée pour chiffrer")
        } catch MessagingFailure.protectionUnavailable {}
        let pending = try await outbox.entries(scope: scope)
        XCTAssertTrue(pending.isEmpty)
    }

    @MainActor
    func testAutomaticEpochFailureIsScopedToItsConversation() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let first = UUID(), other = UUID()
        let store = MemoryCiphertextOutbox()
        let workspace = MessagingWorkspace(scope: scope, service: StaleEpochService(),
            cryptography: SyntheticCipher(), outbox: store, currentScope: { scope })
        _ = try await workspace.outbox.enqueue(text: "conservé", conversationID: first, currentScope: scope)
        await workspace.refreshVisible(conversationID: other)
        XCTAssertNil(workspace.error)
        await workspace.refreshVisible(conversationID: first)
        XCTAssertEqual(workspace.error, .membersChanged)
        await workspace.loadMessages(other)
        XCTAssertNil(workspace.error)
        let pending = try await store.entries(scope: scope)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.recoveryContent, Data("conservé".utf8))
    }

    @MainActor
    func testLateEpochFailureAfterAccountChangeIsNotReinjected() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let context = OutboxCurrentScope(scope)
        let service = SuspendedAcknowledgementService(failure: .membersChanged)
        let store = MemoryCiphertextOutbox()
        let workspace = MessagingWorkspace(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: store, currentScope: { context.value })
        let conversation = UUID()
        _ = try await workspace.outbox.enqueue(text: "conservé", conversationID: conversation, currentScope: scope)
        let refresh = Task { await workspace.refreshVisible(conversationID: conversation) }
        await service.waitUntilSending()
        context.value = nil
        await service.releaseResponse()
        await refresh.value
        XCTAssertEqual(workspace.error, .contextChanged)
        let pending = try await store.entries(scope: scope)
        XCTAssertEqual(pending.count, 1)
    }

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

    func testInaccessiblePrivateThreadDoesNotDiscardOrBlockGeneralMessage() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let outbox = MemoryCiphertextOutbox()
        let privateID = UUID(), generalID = UUID()
        let service = OneInaccessibleThreadService(inaccessibleID: privateID)
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        let first = MessagingPending(clientMessageID: UUID(), conversationID: privateID,
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1])))
        let second = MessagingPending(clientMessageID: UUID(), conversationID: generalID,
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([2])))
        try await outbox.put(first, scope: scope)
        try await outbox.put(second, scope: scope)
        let results = await coordinator.flushPending(currentScope: scope)
        XCTAssertEqual(results.count, 2)
        let remaining = try await outbox.entries(scope: scope)
        XCTAssertEqual(remaining.map(\.clientMessageID), [first.clientMessageID])
    }

    func testConcurrentRetryDoesNotSendTwiceWhileFirstResponseIsPending() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let service = SuspendedAcknowledgementService()
        let outbox = MemoryCiphertextOutbox()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { scope })
        let entry = try await coordinator.enqueue(text: "fixture", conversationID: UUID(), currentScope: scope)
        let first = Task { await coordinator.retry(entry, currentScope: scope) }
        await service.waitUntilSending()
        let second = await coordinator.retry(entry, currentScope: scope)
        if case .waiting = second {} else { XCTFail("Le second appui attend l'envoi en cours") }
        await service.releaseResponse()
        if case .accepted = await first.value {} else { XCTFail("Le premier accusé doit être accepté") }
        let count = await service.attemptCount()
        let remaining = try await outbox.entries(scope: scope)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(remaining.isEmpty)
    }

    @MainActor
    func testAccountChangesDuringSendRejectsLateAcknowledgementAndKeepsPending() async throws {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let context = OutboxCurrentScope(scope)
        let service = SuspendedAcknowledgementService()
        let outbox = MemoryCiphertextOutbox()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: outbox, currentScope: { context.value })
        let entry = try await coordinator.enqueue(text: "fixture", conversationID: UUID(), currentScope: scope)
        let pending = Task { await coordinator.retry(entry, currentScope: scope) }
        await service.waitUntilSending()
        context.value = MessagingScope(accountID: UUID(), schoolID: school, accessEpoch: 1)
        await service.releaseResponse()
        if case .failed(.contextChanged) = await pending.value {} else { XCTFail("Accusé d'un ancien compte refusé") }
        let remaining = try await outbox.entries(scope: scope)
        XCTAssertEqual(remaining.map(\.clientMessageID), [entry.clientMessageID])
    }

    func testUnavailableProtectedStorageNeverQueuesOrSends() async {
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1)
        let service = CountingUnavailableService()
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: SyntheticCipher(), outbox: UnavailableMessagingOutbox(), currentScope: { scope })
        do {
            _ = try await coordinator.enqueue(text: "fixture", conversationID: UUID(), currentScope: scope)
            XCTFail("Pas d'envoi avant écriture durable protégée")
        } catch MessagingFailure.protectionUnavailable {} catch { XCTFail("Erreur inattendue : \(error)") }
        let sent = await service.sentIDs()
        XCTAssertTrue(sent.isEmpty)
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

@MainActor
private final class OutboxCurrentScope {
    var value: MessagingScope?
    init(_ value: MessagingScope) { self.value = value }
}

private actor SuspendedAcknowledgementService: MessagingService {
    private let failure: MessagingFailure?
    init(failure: MessagingFailure? = nil) { self.failure = failure }
    private var attempts = 0
    private var started: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<Void, Never>?

    func waitUntilSending() async {
        if attempts > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func releaseResponse() { response?.resume(); response = nil }
    func attemptCount() -> Int { attempts }
    func conversations(scope: MessagingScope, cursor: String?) throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement {
        attempts += 1
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
        if let failure { throw failure }
        return MessagingAcknowledgement(clientMessageID: pending.clientMessageID, serverMessageID: UUID(),
            conversationID: pending.conversationID, schoolID: scope.schoolID, acceptedAt: Date(), senderID: scope.accountID)
    }
}

private actor OneInaccessibleThreadService: MessagingService {
    let inaccessibleID: UUID
    init(inaccessibleID: UUID) { self.inaccessibleID = inaccessibleID }
    func conversations(scope: MessagingScope, cursor: String?) throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) throws -> MessagingAcknowledgement {
        if pending.conversationID == inaccessibleID { throw MessagingFailure.conversationUnavailable }
        return MessagingAcknowledgement(clientMessageID: pending.clientMessageID, serverMessageID: UUID(),
            conversationID: pending.conversationID, schoolID: scope.schoolID, acceptedAt: Date(), senderID: scope.accountID)
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
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1, 2, 3]), expectedMembersEpoch: 7)
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { Data() }
}

private struct MissingEpochCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1, 2, 3]))
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { Data() }
}

private actor StaleEpochService: MessagingService {
    private var epochs: [Int?] = []
    func sentEpochs() -> [Int?] { epochs }
    func conversations(scope: MessagingScope, cursor: String?) throws -> MessagingPage<MessagingConversation> { MessagingPage(items: [], nextCursor: nil) }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) throws -> MessagingPage<MessagingWireMessage> { MessagingPage(items: [], nextCursor: nil) }
    func send(scope: MessagingScope, pending: MessagingPending) throws -> MessagingAcknowledgement {
        epochs.append(pending.ciphertext.expectedMembersEpoch)
        throw MessagingFailure.membersChanged
    }
}

private actor MemoryCiphertextOutbox: MessagingProtectedOutbox {
    private var entriesByID: [UUID: MessagingPending] = [:]
    private var insertionOrder: [UUID] = []
    func put(_ entry: MessagingPending, scope: MessagingScope) throws {
        if entriesByID[entry.clientMessageID] == nil { insertionOrder.append(entry.clientMessageID) }
        entriesByID[entry.clientMessageID] = entry
    }
    func entries(scope: MessagingScope) throws -> [MessagingPending] { insertionOrder.compactMap { entriesByID[$0] } }
    func remove(clientMessageID: UUID, scope: MessagingScope) throws {
        entriesByID.removeValue(forKey: clientMessageID)
        insertionOrder.removeAll { $0 == clientMessageID }
    }
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
