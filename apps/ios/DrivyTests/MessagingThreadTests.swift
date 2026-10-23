import XCTest
@testable import Drivy

/// Messagerie v2 (#65) : écrits, non exécutés ici (#84). Aucune donnée réelle, chiffrement synthétique uniquement.
@MainActor
final class MessagingThreadTests: XCTestCase {
    private let school = UUID(), account = UUID(), conversation = UUID()
    private let baseURL = URL(string: "https://api.example.invalid/")!
    private var scope: MessagingScope { MessagingScope(accountID: account, schoolID: school, accessEpoch: 1, apiBaseURL: baseURL.absoluteString) }

    private func envelope(_ data: String) -> Data {
        Data(#"{"data":\#(data),"context":{"schoolId":"\#(school.uuidString)","actorPersonId":"\#(account.uuidString)","accessEpoch":1}}"#.utf8)
    }

    private func transport(_ responder: @escaping @Sendable (URLRequest) throws -> Data) -> MessagingHTTPTransport {
        let scope = scope
        return MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: ThreadRecordingHTTP { request in
                SchoolHTTPResponse(data: try responder(request), status: 200, url: request.url!, contentType: "application/json")
            }, currentScope: { scope })
    }

    // MARK: Modèles

    func testPollRulesTrimDropEmptyAndRejectDuplicates() {
        XCTAssertNil(MessagingPollRules.validated(question: " ", options: ["A", "B"]))
        XCTAssertNil(MessagingPollRules.validated(question: "Q", options: ["A", ""]))
        XCTAssertNil(MessagingPollRules.validated(question: "Q", options: ["Oui", "oui"]))
        let poll = MessagingPollRules.validated(question: " Quand ? ", options: ["Lundi", " ", "Mardi "])
        XCTAssertEqual(poll?.question, "Quand ?")
        XCTAssertEqual(poll?.options.map(\.label), ["Lundi", "Mardi"])
        XCTAssertEqual(poll?.options.map(\.id), ["o1", "o2"])
    }

    func testSingleChoiceReplacesAndSecondTapWithdraws() {
        XCTAssertEqual(MessagingPollRules.toggled([], option: "o1", allowsMultiple: false), ["o1"])
        XCTAssertEqual(MessagingPollRules.toggled(["o1"], option: "o2", allowsMultiple: false), ["o2"])
        XCTAssertEqual(MessagingPollRules.toggled(["o2"], option: "o2", allowsMultiple: false), [])
        XCTAssertEqual(MessagingPollRules.toggled(["o1"], option: "o2", allowsMultiple: true), ["o1", "o2"])
    }

    func testPollIndexRoundTrip() {
        XCTAssertEqual(MessagingPollIndex.index(MessagingPollIndex.id(0)), 0)
        XCTAssertNil(MessagingPollIndex.index("x1"))
        XCTAssertNil(MessagingPollIndex.index("o99"))
    }

    func testPlainContentKeepsV1TextReadable() throws {
        XCTAssertEqual(MessagingPlainContent.decode(Data("bonjour".utf8))?.text, "bonjour")
        let poll = MessagingPlainContent(poll: .init(question: "Q", options: [.init(id: "o1", label: "A"), .init(id: "o2", label: "B")]))
        XCTAssertEqual(MessagingPlainContent.decode(try poll.encoded()), poll)
    }

    func testPermissionsFollowServerAccessAndRoles() {
        let other = UUID()
        let member = MessagingConversationAccess(canWrite: true, readableUntilSequence: nil, isGroupAdmin: false)
        let admin = MessagingConversationAccess(canWrite: true, readableUntilSequence: nil, isGroupAdmin: true)
        let ended = MessagingConversationAccess(canWrite: false, readableUntilSequence: 4, isGroupAdmin: true)
        XCTAssertTrue(MessagingPermissions.canDeleteForEveryone(senderID: account, account: account, access: member))
        XCTAssertFalse(MessagingPermissions.canDeleteForEveryone(senderID: other, account: account, access: member))
        XCTAssertTrue(MessagingPermissions.canDeleteForEveryone(senderID: other, account: account, access: admin))
        XCTAssertFalse(MessagingPermissions.canDeleteForEveryone(senderID: account, account: account, access: ended))
        let poll = MessagingPollState(allowsMultiple: false, closed: false, creatorID: account, options: [])
        XCTAssertTrue(MessagingPermissions.canClosePoll(poll, account: account, access: member))
        XCTAssertFalse(MessagingPermissions.canClosePoll(poll, account: other, access: admin))
        XCTAssertFalse(MessagingPermissions.canVote(MessagingPollState(allowsMultiple: false, closed: true, creatorID: account, options: []), access: member))
    }

    func testLocalSearchIgnoresCaseAndAccentsAndIncludesPolls() {
        let a = MessagingHistoryEntry(messageID: UUID(), conversationID: conversation, sequence: 1, senderID: account,
                                      acceptedAt: Date(), content: .init(text: "Rendez-vous à l'École"))
        let b = MessagingHistoryEntry(messageID: UUID(), conversationID: conversation, sequence: 2, senderID: account,
            acceptedAt: Date(), content: .init(poll: .init(question: "Créneau ?", options: [.init(id: "o1", label: "ecole"), .init(id: "o2", label: "parking")])))
        let results = MessagingHistorySearch.matches([a, b], query: "ECOLE")
        XCTAssertEqual(results.map(\.messageID), [b.messageID, a.messageID])
        XCTAssertTrue(MessagingHistorySearch.matches([a, b], query: "  ").isEmpty)
    }

    func testPendingV1SnapshotStillDecodes() throws {
        let json = #"{"clientMessageID":"\#(UUID().uuidString)","conversationID":"\#(UUID().uuidString)","ciphertext":{"scheme":"TEST_ONLY","keyId":"k","payload":"AQ=="},"mentionPersonIDs":[]}"#
        let pending = try JSONDecoder().decode(MessagingPending.self, from: Data(json.utf8))
        XCTAssertNil(pending.replyToMessageID)
        XCTAssertNil(pending.poll)
    }

    // MARK: Transport

    func testMessagesDecodeAccessDeletionPollAndReadStates() async throws {
        let id = UUID(), sender = UUID(), reader = UUID()
        let body = envelope("""
        {"items":[{"id":"\(id)","schoolId":"\(school)","conversationId":"\(conversation)","sequence":3,"clientMessageId":"\(UUID())","senderId":"\(sender)","ciphertext":{"scheme":"TEST_ONLY","keyId":"k","payload":"AQ=="},"mentionPersonIds":[],"acceptedAt":"2026-10-23T00:00:00Z","deletedForEveryone":true,"pinned":true,"reactions":[{"emoji":"👍","personIds":["\(reader)"]}],"poll":{"optionCount":2,"multiple":true,"closed":false,"closedAt":null,"creatorId":"\(sender)","votes":[{"optionIndex":1,"personIds":["\(reader)"]}]}}],
         "nextCursor":null,"access":{"canWrite":false,"readableUntilSequence":3},"readStates":[{"personId":"\(reader)","lastReadSequence":3}]}
        """)
        let page = try await transport { _ in body }.messages(scope: scope, conversationID: conversation, before: nil)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertNil(item.ciphertext, "Un message supprimé pour tout le monde ne garde aucune enveloppe")
        XCTAssertTrue(item.meta.deletedForEveryone)
        XCTAssertTrue(item.meta.pinned)
        XCTAssertEqual(item.meta.poll?.options.map(\.optionID), ["o1", "o2"])
        XCTAssertEqual(item.meta.poll?.options[1].voterIDs, [reader])
        XCTAssertEqual(page.access?.canWrite, false)
        XCTAssertEqual(page.access?.readableUntilSequence, 3)
        XCTAssertEqual(page.readReceipts.first?.personID, reader)
    }

    func testPollWithVoteOutsideRangeIsRejected() async {
        let body = envelope("""
        {"items":[{"id":"\(UUID())","schoolId":"\(school)","conversationId":"\(conversation)","sequence":1,"clientMessageId":"\(UUID())","senderId":"\(account)","ciphertext":{"scheme":"TEST_ONLY","keyId":"k","payload":"AQ=="},"mentionPersonIds":[],"acceptedAt":"2026-10-23T00:00:00Z","poll":{"optionCount":2,"multiple":false,"closed":false,"creatorId":"\(account)","votes":[{"optionIndex":5,"personIds":[]}]}}],"nextCursor":null}
        """)
        do {
            _ = try await transport { _ in body }.messages(scope: scope, conversationID: conversation, before: nil)
            XCTFail("Indice hors limite")
        } catch {}
    }

    func testClientDropsMessagesBeyondReadableLimit() async throws {
        let client = MessagingAPIClient(transport: LimitedTransport(school: school, conversation: conversation))
        let page = try await client.messages(scope: scope, conversationID: conversation, before: nil)
        XCTAssertEqual(page.items.map(\.meta.sequence), [1, 2])
        XCTAssertEqual(page.access?.canWrite, false)
    }

    func testActionRoutesAndBodies() async throws {
        let message = UUID(), person = UUID()
        let log = RequestLog()
        let client = transport { request in
            log.append(request)
            return self.envelope("{}")
        }
        try await client.delete(scope: scope, conversationID: conversation, messageID: message, for: .everyone)
        try await client.setReaction(scope: scope, conversationID: conversation, messageID: message, emoji: "👍", active: false)
        try await client.setPinned(scope: scope, conversationID: conversation, messageID: message, pinned: true)
        try await client.vote(scope: scope, conversationID: conversation, messageID: message, optionIDs: ["o2", "o1"])
        try await client.closePoll(scope: scope, conversationID: conversation, messageID: message)
        try await client.setGroupAdmin(scope: scope, personID: person, admin: true)
        try await client.removeGeneralMember(scope: scope, personID: person)
        try await client.report(scope: scope, conversationID: conversation,
            items: [MessagingReportItem(messageID: message, ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "admins", payload: Data([1])))])
        let prefix = "/v1/schools/\(school.uuidString)/messaging"
        let m = "\(prefix)/conversations/\(conversation.uuidString)/messages/\(message.uuidString)"
        XCTAssertEqual(log.lines, [
            "DELETE \(m)?scope=everyone",
            "DELETE \(m)/reactions/👍",
            "PUT \(m)/pin",
            "PUT \(m)/poll/votes",
            "POST \(m)/poll/close",
            "PUT \(prefix)/general/admins/\(person.uuidString)",
            "DELETE \(prefix)/general/members/\(person.uuidString)",
            "POST \(prefix)/reports",
        ])
        let vote = try JSONSerialization.jsonObject(with: log.bodies[3]!) as! [String: Any]
        XCTAssertEqual(vote["optionIndexes"] as? [Int], [0, 1])
        let report = try JSONSerialization.jsonObject(with: log.bodies[7]!) as! [String: Any]
        XCTAssertNotNil(report["clientReportId"])
        XCTAssertEqual((report["items"] as? [[String: Any]])?.count, 1)
    }

    func testUnknownReactionNeverLeavesDevice() async {
        let log = RequestLog()
        let client = transport { request in log.append(request); return self.envelope("{}") }
        do {
            try await client.setReaction(scope: scope, conversationID: conversation, messageID: UUID(), emoji: "x", active: true)
            XCTFail()
        } catch {}
        XCTAssertTrue(log.lines.isEmpty)
    }

    func testMembersExposeNamePhotoAndAdminOnly() async throws {
        let p = UUID()
        let body = envelope(#"{"members":[{"personId":"\#(p)","displayName":"Léa Martin","photoVersion":3,"isGroupAdmin":true}],"nextCursor":null}"#)
        let members = try await transport { _ in body }.members(scope: scope)
        XCTAssertEqual(members, [MessagingMember(id: p, displayName: "Léa Martin", hasPhoto: true, isGroupAdmin: true)])
    }

    // MARK: Workspace

    func testReportFailsClosedWithoutAdminSealing() async {
        let workspace = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), currentScope: { [scope] in scope })
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("salut".utf8)))
        let sent = await workspace.report([message], conversationID: conversation)
        XCTAssertFalse(sent)
        XCTAssertEqual(workspace.actionError, .protectionUnavailable)
    }

    func testReadOnlyConversationRefusesEnqueue() async throws {
        let workspace = MessagingWorkspace(scope: scope, service: LimitedService(school: school, conversation: conversation),
                                           cryptography: ThreadSyntheticCipher(), currentScope: { [scope] in scope })
        await workspace.loadMessages(conversation)
        XCTAssertTrue(workspace.access(for: conversation).isReadOnly)
        do {
            _ = try await workspace.enqueue(content: .init(text: "x"), conversationID: conversation, mentions: [], replyTo: nil)
            XCTFail("Écriture refusée après la fin du lien")
        } catch MessagingFailure.accessChanged {}
    }

    func testReadersExcludeSenderAndUnreadPeople() async {
        let workspace = MessagingWorkspace(scope: scope, service: LimitedService(school: school, conversation: conversation),
                                           currentScope: { [scope] in scope })
        await workspace.loadMessages(conversation)
        let second = workspace.visibleMessages(conversation)[1]
        XCTAssertEqual(workspace.readers(of: second), [LimitedTransport.reader])
    }
}

// MARK: Substituts synthétiques

@MainActor private final class ThreadFixtureToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-token" }
}

private actor ThreadRecordingHTTP: SchoolHTTPTransport {
    private let responder: @Sendable (URLRequest) throws -> SchoolHTTPResponse
    init(_ responder: @escaping @Sendable (URLRequest) throws -> SchoolHTTPResponse) { self.responder = responder }
    func send(_ request: URLRequest) throws -> SchoolHTTPResponse { try responder(request) }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lines: [String] = []
    private(set) var bodies: [Data?] = []
    func append(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        let url = request.url!
        let path = url.path.removingPercentEncoding ?? url.path
        lines.append("\(request.httpMethod ?? "") \(path)" + (url.query.map { "?\($0)" } ?? ""))
        bodies.append(request.httpBody)
    }
}

private struct ThreadSyntheticCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: plaintext)
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { ciphertext.payload }
}

/// Trois messages, lien terminé après la séquence 2.
private struct LimitedTransport: MessagingAPITransport {
    static let reader = UUID()
    let school: UUID, conversation: UUID
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPageDTO<MessagingConversationDTO> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPageDTO<MessagingMessageDTO> {
        MessagingPageDTO(items: (1...3).map { n in
            MessagingMessageDTO(id: UUID(), conversationId: conversation, schoolId: school, senderId: scope.accountID,
                acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data([1])),
                meta: MessagingMessageMeta(sequence: n))
        }, nextCursor: nil, access: MessagingConversationAccess(canWrite: false, readableUntilSequence: 2, isGroupAdmin: false),
           readReceipts: [MessagingReadReceipt(personID: scope.accountID, lastReadSequence: 3),
                          MessagingReadReceipt(personID: Self.reader, lastReadSequence: 2),
                          MessagingReadReceipt(personID: UUID(), lastReadSequence: 1)])
    }
    func send(scope: MessagingScope, conversationID: UUID, body: MessagingSendDTO) async throws -> MessagingAcknowledgementDTO { throw MessagingFailure.unavailable }
}

private struct LimitedService: MessagingService {
    let school: UUID, conversation: UUID
    private var client: MessagingAPIClient { MessagingAPIClient(transport: LimitedTransport(school: school, conversation: conversation)) }
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> {
        try await client.messages(scope: scope, conversationID: conversationID, before: before)
    }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement { throw MessagingFailure.unavailable }
}
