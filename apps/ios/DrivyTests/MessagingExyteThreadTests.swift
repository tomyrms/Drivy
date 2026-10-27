import XCTest
@testable import Drivy

/// Fil Exyte (#182) : projection indépendante du moteur d'affichage et composeur Drivy. Données synthétiques uniquement.
@MainActor
final class MessagingExyteThreadTests: XCTestCase {
    private let school = UUID(), account = UUID(), other = UUID(), conversation = UUID()
    private var scope: MessagingScope { MessagingScope(accountID: account, schoolID: school, accessEpoch: 1) }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    private func wire(_ sender: UUID, at offset: TimeInterval, sequence: Int) -> MessagingWireMessage {
        MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: sender,
            acceptedAt: start.addingTimeInterval(offset), ciphertext: nil, meta: MessagingMessageMeta(sequence: sequence))
    }

    private func pending(_ id: UUID = UUID()) -> MessagingPending {
        MessagingPending(clientMessageID: id, conversationID: conversation,
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("x".utf8), expectedMembersEpoch: 1))
    }

    private func items(_ messages: [MessagingWireMessage], pending: [MessagingPending] = [],
                       clientIDs: [UUID: UUID] = [:], dates: [UUID: Date] = [:]) -> [MessagingThreadItem] {
        MessagingThreadProjection.items(messages: messages, pending: pending, accountID: account, clientIDs: clientIDs,
                                        pendingDates: dates, now: start, calendar: calendar)
    }

    // MARK: Projection

    func testConfirmedMessageKeepsTheLocalIdentityOfItsSend() {
        let client = UUID()
        let sent = wire(account, at: 0, sequence: 1)
        let result = items([sent], clientIDs: [sent.id: client])
        XCTAssertEqual(result.map(\.id), [client.uuidString])
        XCTAssertEqual(result.first?.message?.id, sent.id)
    }

    func testAckAndReloadTogetherNeverProduceDuplicateIdentities() {
        let client = UUID()
        let sent = wire(account, at: 0, sequence: 1)
        // L'accusé est arrivé mais la bulle locale est encore transmise : la version serveur l'emporte.
        let result = items([sent], pending: [pending(client)], clientIDs: [sent.id: client])
        XCTAssertEqual(result.count, 1)
        XCTAssertNotNil(result.first?.message)
        XCTAssertEqual(Set(result.map(\.id)).count, result.count)
    }

    func testPendingStaysBelowNewerMessagesWithoutChangingTheirOrder() {
        let first = wire(other, at: 0, sequence: 1), second = wire(other, at: 3_600, sequence: 2)
        let queued = pending()
        // Mis en file hors connexion avant le second message reçu : il reste sous lui, daté au plus tôt de ce message.
        let result = items([first, second], pending: [queued], dates: [queued.clientMessageID: start.addingTimeInterval(60)])
        XCTAssertEqual(result.map(\.id), [first.id.uuidString, second.id.uuidString, queued.clientMessageID.uuidString])
        XCTAssertEqual(result.last?.date, second.acceptedAt)
        XCTAssertEqual(result.last?.senderID, account)
    }

    func testServerOrderIsKeptEvenWhenDatesDisagree() {
        let later = wire(other, at: 120, sequence: 1), earlier = wire(other, at: 60, sequence: 2)
        XCTAssertEqual(items([later, earlier]).map(\.id), [later.id.uuidString, earlier.id.uuidString])
    }

    func testGroupsFollowAuthorFiveMinutesAndDay() {
        let a = wire(other, at: 0, sequence: 1)
        let b = wire(other, at: 120, sequence: 2)          // même auteur, 2 min : même groupe
        let c = wire(other, at: 120 + 301, sequence: 3)    // plus de 5 min : nouveau groupe
        let d = wire(account, at: 120 + 360, sequence: 4)  // autre auteur
        let e = wire(account, at: 86_400 * 2, sequence: 5) // autre jour
        let result = items([a, b, c, d, e])
        XCTAssertEqual(result.map(\.startsGroup), [true, false, true, true, true])
        XCTAssertEqual(result.map(\.endsGroup), [false, true, true, true, true])
    }

    func testOnlyAcceptedSendsMapToTheirServerMessage() {
        let accepted = UUID(), server = UUID(), refused = UUID()
        let map = MessagingThreadProjection.clientIDs([accepted: .accepted(serverMessageID: server),
                                                       refused: .failed(.accessChanged), UUID(): .sending])
        XCTAssertEqual(map, [server: accepted])
    }

    // MARK: Composeur

    private func composer(outbox: any MessagingProtectedOutbox = ComposerMemoryOutbox()) async -> MessagingComposerModel {
        let scope = scope
        let workspace = MessagingWorkspace(scope: scope, cryptography: ComposerReadyCipher(), outbox: outbox,
                                           drafts: ComposerMemoryDrafts(), currentScope: { scope })
        let model = MessagingComposerModel(workspace: workspace, conversationID: conversation)
        await model.load()
        return model
    }

    func testFailedProtectionKeepsTextMentionsAndReply() async {
        let model = await composer(outbox: ComposerFailingOutbox())
        let quoted = wire(other, at: 0, sequence: 1)
        model.draft = "Bonjour @Alice"
        model.insertMention(MessagingContact(id: other, displayName: "Alice"))
        model.reply(to: quoted)
        let mentions = model.selectedMentions
        let sent = await model.sendText()
        XCTAssertFalse(sent)
        XCTAssertEqual(model.draft, "Bonjour @Alice ")
        XCTAssertEqual(model.selectedMentions, mentions)
        XCTAssertEqual(model.replyTo?.id, quoted.id)
        XCTAssertNotNil(model.deliveryLabel)
        XCTAssertTrue(model.queued.isEmpty)
    }

    func testProtectedSendClearsTheSubmittedTextAndPlacesTheBubble() async throws {
        let model = await composer()
        model.draft = "À demain"
        let sent = await model.sendText()
        XCTAssertTrue(sent)
        XCTAssertEqual(model.draft, "")
        let entry = try XCTUnwrap(model.queued.first)
        XCTAssertNotNil(model.queuedDates[entry.clientMessageID])
        XCTAssertNil(model.deliveryLabel)
    }

    func testRemovedMentionTextDropsTheMention() async {
        let model = await composer()
        model.draft = "@Al"
        model.insertMention(MessagingContact(id: other, displayName: "Alice"))
        XCTAssertEqual(model.selectedMentions.map(\.personID), [other])
        model.draft = "Bonjour"
        XCTAssertTrue(model.selectedMentions.isEmpty)
    }

    func testPollNeverCarriesTheMentionsOfTheTextDraft() async throws {
        let model = await composer()
        model.draft = "@Al"
        model.insertMention(MessagingContact(id: other, displayName: "Alice"))
        let poll = try XCTUnwrap(MessagingPollRules.validated(question: "Quand ?", options: ["Lundi", "Mardi"]))
        let sent = await model.send(MessagingPlainContent(poll: poll))
        XCTAssertTrue(sent)
        XCTAssertEqual(model.queued.first?.mentionPersonIDs, [])
        // Le brouillon texte et sa mention restent pour le message suivant.
        XCTAssertEqual(model.draft, "@Alice ")
        XCTAssertEqual(model.selectedMentions.map(\.personID), [other])
    }
}

private struct ComposerReadyCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: plaintext, expectedMembersEpoch: 1)
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { ciphertext.payload }
}

private actor ComposerMemoryOutbox: MessagingProtectedOutbox {
    private var stored: [MessagingPending] = []
    func put(_ entry: MessagingPending, scope: MessagingScope) async throws { stored.append(entry) }
    func entries(scope: MessagingScope) async throws -> [MessagingPending] { stored }
    func remove(clientMessageID: UUID, scope: MessagingScope) async throws { stored.removeAll { $0.clientMessageID == clientMessageID } }
}

/// Stockage protégé indisponible au moment d'écrire : rien ne doit être retiré du composeur.
private actor ComposerFailingOutbox: MessagingProtectedOutbox {
    func put(_ entry: MessagingPending, scope: MessagingScope) async throws { throw MessagingFailure.protectionUnavailable }
    func entries(scope: MessagingScope) async throws -> [MessagingPending] { [] }
    func remove(clientMessageID: UUID, scope: MessagingScope) async throws {}
}

private actor ComposerMemoryDrafts: MessagingProtectedDrafts {
    private var drafts: [UUID: String] = [:]
    func loadDraft(conversationID: UUID, scope: MessagingScope) async throws -> String { drafts[conversationID] ?? "" }
    func saveDraft(_ text: String, conversationID: UUID, scope: MessagingScope) async throws { drafts[conversationID] = text }
}
