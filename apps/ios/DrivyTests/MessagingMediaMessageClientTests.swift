import XCTest
@testable import Drivy

/// #97 — capacite additive `MessagingMediaMessageSending` du client, avec transport injecte.
///
/// Ces tests sont ecrits avant l'implementation et ne compilent pas sur Windows.
/// Aucune preuve d'execution Swift n'est revendiquee ici.
@MainActor
final class MessagingMediaMessageClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.invalid/")!

    private func makeScope(account: UUID = UUID(), school: UUID = UUID()) -> MessagingScope {
        MessagingScope(accountID: account, schoolID: school, accessEpoch: 3, apiBaseURL: baseURL.absoluteString)
    }

    private func makePending(conversation: UUID = UUID(), intent: UUID = UUID(),
                             poll: MessagingPollDraftMeta? = nil) -> MessagingPending {
        MessagingPending(clientMessageID: intent, conversationID: conversation,
            ciphertext: MessagingCiphertext(scheme: "megolm.v1", keyID: "fixture", payload: Data([1, 2, 3]),
                                            expectedMembersEpoch: 3),
            mentionPersonIDs: [UUID()], poll: poll)
    }

    private func acknowledgement(scope: MessagingScope, pending: MessagingPending,
                                 media: MessagingMessageMediaReference?) -> MessagingAcknowledgementDTO {
        MessagingAcknowledgementDTO(clientMessageId: pending.clientMessageID, serverMessageId: UUID(),
            conversationId: pending.conversationID, schoolId: scope.schoolID, acceptedAt: Date(),
            senderId: scope.accountID, media: media)
    }

    private func mediaReference(_ intent: MessagingMediaMessageIntent, deleted: Bool = false) throws
        -> MessagingMessageMediaReference {
        try MessagingMessageMediaReference(mediaID: intent.mediaID, byteSize: intent.byteSize, deleted: deleted)
    }

    func testClientMediaSendAcceptsAMatchingAcknowledgement() async throws {
        let scope = makeScope()
        let pending = makePending()
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1_234)
        let ack = acknowledgement(scope: scope, pending: pending, media: try mediaReference(media))
        let transport = InjectedMediaMessageTransport(ack: ack)
        let client = MessagingAPIClient(transport: transport)

        let result = try await client.sendMedia(scope: scope, pending: pending, media: media)

        XCTAssertEqual(result.clientMessageID, pending.clientMessageID)
        XCTAssertEqual(result.serverMessageID, ack.serverMessageId)
        XCTAssertEqual(result.conversationID, pending.conversationID)
        XCTAssertEqual(result.schoolID, scope.schoolID)
        XCTAssertEqual(result.senderID, scope.accountID)
        let calls = await transport.mediaCallCount()
        XCTAssertEqual(calls, 1)
    }

    func testClientRejectsAnAcknowledgementWithoutMedia() async throws {
        let scope = makeScope()
        let pending = makePending()
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1_234)
        let transport = InjectedMediaMessageTransport(ack: acknowledgement(scope: scope, pending: pending, media: nil))
        let client = MessagingAPIClient(transport: transport)

        do {
            _ = try await client.sendMedia(scope: scope, pending: pending, media: media)
            XCTFail("Un recu sans media ne peut pas acquitter un envoi media")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testClientRejectsAnotherMediaOrAnotherSize() async throws {
        let scope = makeScope()
        let pending = makePending()
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1_234)
        let other = try MessagingMessageMediaReference(mediaID: UUID(), byteSize: 1_234, deleted: false)
        let wrongSize = try MessagingMessageMediaReference(mediaID: media.mediaID, byteSize: 1_235, deleted: false)

        for reference in [other, wrongSize] {
            let transport = InjectedMediaMessageTransport(
                ack: acknowledgement(scope: scope, pending: pending, media: reference))
            let client = MessagingAPIClient(transport: transport)
            do {
                _ = try await client.sendMedia(scope: scope, pending: pending, media: media)
                XCTFail("Un media ou une taille differents ne peuvent pas acquitter l'envoi")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, .invalidResponse)
            }
        }
    }

    func testClientRejectsAnAcknowledgementWithAWrongContext() async throws {
        let scope = makeScope()
        let pending = makePending()
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1_234)
        let reference = try mediaReference(media)
        let variants: [MessagingAcknowledgementDTO] = [
            MessagingAcknowledgementDTO(clientMessageId: UUID(), serverMessageId: UUID(),
                conversationId: pending.conversationID, schoolId: scope.schoolID, acceptedAt: Date(),
                senderId: scope.accountID, media: reference),
            MessagingAcknowledgementDTO(clientMessageId: pending.clientMessageID, serverMessageId: UUID(),
                conversationId: UUID(), schoolId: scope.schoolID, acceptedAt: Date(),
                senderId: scope.accountID, media: reference),
            MessagingAcknowledgementDTO(clientMessageId: pending.clientMessageID, serverMessageId: UUID(),
                conversationId: pending.conversationID, schoolId: UUID(), acceptedAt: Date(),
                senderId: scope.accountID, media: reference),
            MessagingAcknowledgementDTO(clientMessageId: pending.clientMessageID, serverMessageId: UUID(),
                conversationId: pending.conversationID, schoolId: scope.schoolID, acceptedAt: Date(),
                senderId: UUID(), media: reference)
        ]
        for ack in variants {
            let client = MessagingAPIClient(transport: InjectedMediaMessageTransport(ack: ack))
            do {
                _ = try await client.sendMedia(scope: scope, pending: pending, media: media)
                XCTFail("Un accusé hors contexte ne peut pas etre accepte par le client")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, .invalidResponse)
            }
        }
    }

    func testClientRefusesPollAndMediaBeforeCallingTheInjectedTransport() async throws {
        let scope = makeScope()
        let pending = makePending(poll: MessagingPollDraftMeta(allowsMultiple: false, optionIDs: ["o1", "o2"]))
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1_234)
        let transport = InjectedMediaMessageTransport(
            ack: acknowledgement(scope: scope, pending: pending, media: try mediaReference(media)))
        let client = MessagingAPIClient(transport: transport)

        do {
            _ = try await client.sendMedia(scope: scope, pending: pending, media: media)
            XCTFail("Un sondage et un media ne peuvent pas coexister")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .invalidIntent)
        }
        let calls = await transport.mediaCallCount()
        XCTAssertEqual(calls, 0)
    }

    func testClientPassesTheSamePendingIdentifiersAndCiphertextToTheTransport() async throws {
        let scope = makeScope()
        let pending = makePending()
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1_234)
        let transport = InjectedMediaMessageTransport(
            ack: acknowledgement(scope: scope, pending: pending, media: try mediaReference(media)))
        let client = MessagingAPIClient(transport: transport)

        _ = try await client.sendMedia(scope: scope, pending: pending, media: media)

        let calls = await transport.capturedCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].0.clientMessageID, pending.clientMessageID)
        XCTAssertEqual(calls[0].0.conversationID, pending.conversationID)
        XCTAssertEqual(calls[0].0.ciphertext, pending.ciphertext)
        XCTAssertEqual(calls[0].0.mentionPersonIDs, pending.mentionPersonIDs)
        XCTAssertEqual(calls[0].0.replyToMessageID, pending.replyToMessageID)
        XCTAssertEqual(calls[0].0.poll, pending.poll)
        XCTAssertEqual(calls[0].1, media)
    }

    func testClientKeepsTheServerDeletedFactWithoutRefusingTheAcknowledgement() async throws {
        let scope = makeScope()
        let pending = makePending()
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1_234)
        let tombstone = try MessagingMessageMediaReference(mediaID: media.mediaID, byteSize: media.byteSize,
                                                           deleted: true)
        let transport = InjectedMediaMessageTransport(
            ack: acknowledgement(scope: scope, pending: pending, media: tombstone))
        let client = MessagingAPIClient(transport: transport)

        let result = try await client.sendMedia(scope: scope, pending: pending, media: media)
        XCTAssertEqual(result.clientMessageID, pending.clientMessageID)
    }

    func testOrdinarySendStillAcceptsAnAcknowledgementWithoutMedia() async throws {
        let scope = makeScope()
        let pending = makePending()
        let transport = InjectedMediaMessageTransport(
            ack: acknowledgement(scope: scope, pending: pending, media: nil))
        let client = MessagingAPIClient(transport: transport)

        let result = try await client.send(scope: scope, pending: pending)
        XCTAssertEqual(result.clientMessageID, pending.clientMessageID)
        let calls = await transport.mediaCallCount()
        XCTAssertEqual(calls, 0, "L'envoi ordinaire n'emprunte pas la capacite media")
    }
}

private actor InjectedMediaMessageTransport: MessagingAPITransport {
    private let ack: MessagingAcknowledgementDTO
    private var captured: [(MessagingPending, MessagingMediaMessageIntent)] = []

    init(ack: MessagingAcknowledgementDTO) { self.ack = ack }

    func conversations(scope: MessagingScope, cursor: String?) async throws
        -> MessagingPageDTO<MessagingConversationDTO> {
        throw MessagingFailure.unavailable
    }

    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws
        -> MessagingPageDTO<MessagingMessageDTO> {
        throw MessagingFailure.unavailable
    }

    func send(scope: MessagingScope, conversationID: UUID, body: MessagingSendDTO) async throws
        -> MessagingAcknowledgementDTO {
        ack
    }

    func sendMedia(scope: MessagingScope, pending: MessagingPending, media: MessagingMediaMessageIntent) async throws
        -> MessagingAcknowledgementDTO {
        captured.append((pending, media))
        return ack
    }

    func mediaCallCount() -> Int { captured.count }
    func capturedCalls() -> [(MessagingPending, MessagingMediaMessageIntent)] { captured }
}
