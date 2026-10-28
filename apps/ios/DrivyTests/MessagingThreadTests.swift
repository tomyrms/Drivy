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

    /// #242 : chaque refus de `validated` a son explication, et seulement ceux-là.
    func testPollProblemsExplainExactlyWhatValidationRefuses() {
        let long = String(repeating: "a", count: MessagingPollRules.maxLength + 1)
        let cases: [(String, [String])] = [(" ", ["A", "B"]), ("Q", ["A", ""]), ("Q", ["Oui", " oui "]), (long, ["A", "B"]),
                                           ("Q", ["A", long]), ("Quand ?", ["Lundi", " ", "Mardi"]), ("", ["", ""])]
        for (question, options) in cases {
            let problems = MessagingPollRules.problems(question: question, options: options)
            XCTAssertEqual(problems.isEmpty, MessagingPollRules.validated(question: question, options: options) != nil, "\(question) \(options)")
        }
        XCTAssertTrue(MessagingPollRules.problems(question: " ", options: ["A", "B"]).questionMissing)
        XCTAssertTrue(MessagingPollRules.problems(question: "Q", options: ["A", ""]).tooFewOptions)
        XCTAssertEqual(MessagingPollRules.problems(question: "Q", options: ["Oui", " oui "]).duplicates, [1])
        XCTAssertEqual(MessagingPollRules.problems(question: long, options: ["A", "B"]).questionLength, MessagingPollRules.maxLength + 1)
        XCTAssertEqual(MessagingPollRules.problems(question: "Q", options: ["A", long]).optionLengths, [1: MessagingPollRules.maxLength + 1])
    }

    /// #239 : l'explication vient de la cause connue ; la restauration n'est proposée que pour une clé absente.
    func testUnreadableMessageExplainsOnlyTheKnownCause() {
        XCTAssertTrue(MessagingDecryptionFailure.explanation(for: "D-NOKEY").contains("restaure tes clés"))
        for code in ["D-WITHHELD", "D-WH-MUNVERIFIED", "D-STORE", "D-MEGOLM", "D-X"] {
            let text = MessagingDecryptionFailure.explanation(for: code)
            XCTAssertFalse(text.contains("restaure"), code)
            XCTAssertFalse(text.contains(code), code)
        }
        XCTAssertEqual(MessagingDecryptionFailure.explanation(for: "D-WH-MUNVERIFIED"), "Ce message n’a pas été partagé avec cet appareil.")
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
        let body = envelope("{}")
        let client = transport { request in
            log.append(request)
            return body
        }
        try await client.delete(scope: scope, conversationID: conversation, messageID: message, for: .everyone)
        try await client.setReaction(scope: scope, conversationID: conversation, messageID: message, emoji: "👍", active: false)
        try await client.setPinned(scope: scope, conversationID: conversation, messageID: message, pinned: true)
        try await client.vote(scope: scope, conversationID: conversation, messageID: message, optionIDs: ["o2", "o1"])
        try await client.closePoll(scope: scope, conversationID: conversation, messageID: message)
        try await client.setGroupAdmin(scope: scope, personID: person, admin: true)
        try await client.removeGeneralMember(scope: scope, personID: person)
        try await client.reinstateGeneralMember(scope: scope, personID: person)
        let reportID = UUID()
        try await client.report(scope: scope, conversationID: conversation, clientReportID: reportID,
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
            "PUT \(prefix)/general/members/\(person.uuidString)",
            "POST \(prefix)/reports",
        ])
        let vote = try JSONSerialization.jsonObject(with: log.bodies[3]!) as! [String: Any]
        XCTAssertEqual(vote["optionIndexes"] as? [Int], [0, 1])
        let report = try JSONSerialization.jsonObject(with: log.bodies[8]!) as! [String: Any]
        XCTAssertEqual(report["clientReportId"] as? String, reportID.uuidString)
        XCTAssertEqual((report["items"] as? [[String: Any]])?.count, 1)
    }

    func testUnknownReactionNeverLeavesDevice() async {
        let log = RequestLog()
        let body = envelope("{}")
        let client = transport { request in log.append(request); return body }
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

    func testReportFailsClosedWithoutAdminSealing() async throws {
        let scope = scope
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let workspace = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), reports: store, currentScope: { scope })
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("salut".utf8)))
        let sent = await workspace.report([message], conversationID: conversation)
        XCTAssertFalse(sent)
        XCTAssertEqual(workspace.actionError, .protectionUnavailable)
    }

    func testReportAbandonIsDurableAndNextAttemptUsesNewIntent() async throws {
        let scope = scope
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let network = ReportLostAcknowledgementHTTP(response: envelope("{}"))
        let actions = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: network, currentScope: { scope })
        let workspace = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), actions: actions,
            reportSealing: ReportChangingSyntheticSealing(), reports: store, currentScope: { scope })
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("SYNTHETIC_REPORT".utf8)))
        let firstSent = await workspace.report([message], conversationID: conversation)
        XCTAssertFalse(firstSent)
        let pending = try await store.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertNotNil(pending)
        let abandoned = await workspace.abandonReport(conversationID: conversation)
        XCTAssertTrue(abandoned)
        let reopened = try MessagingProtectedStore(scope: scope)
        let afterAbandon = try await reopened.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertTrue(afterAbandon == nil)
        let nextSent = await workspace.report([message], conversationID: conversation)
        XCTAssertTrue(nextSent)
        let bodies = await network.bodies
        guard bodies.count == 2,
              let first = try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any],
              let next = try JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any] else {
            XCTFail("Deux tentatives attendues."); return
        }
        XCTAssertTrue(first["clientReportId"] as? String != next["clientReportId"] as? String,
                      "Après abandon explicite, une nouvelle validation crée une intention distincte.")
        let afterACK = try await reopened.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertTrue(afterACK == nil)
    }

    /// Regression: an acknowledgement may be lost after the server has accepted a report.
    /// Recreating the workspace must not create another intention or encrypt the selected items again.
    func testReportRetryAfterWorkspaceRestartReusesDurableIntentAndCiphertext() async throws {
        let scope = scope
        let firstStore = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await firstStore.purge(scope: scope) }
        let network = ReportLostAcknowledgementHTTP(response: envelope("{}"))
        let actions = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: network, currentScope: { scope })
        let sealing = ReportChangingSyntheticSealing()
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data("SYNTHETIC_REPORT".utf8)))
        var first: MessagingWorkspace? = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(),
            outbox: firstStore, drafts: firstStore, actions: actions, reportSealing: sealing, reports: firstStore, currentScope: { scope })
        let firstSent = await first!.report([message], conversationID: conversation)
        XCTAssertFalse(firstSent, "Un acquittement perdu ne doit pas être présenté comme une réussite.")
        first = nil

        let reopenedStore = try MessagingProtectedStore(scope: scope)
        let restarted = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(),
            outbox: reopenedStore, drafts: reopenedStore, actions: actions, reportSealing: sealing, reports: reopenedStore, currentScope: { scope })
        let retrySent = await restarted.report([message], conversationID: conversation)
        XCTAssertTrue(retrySent, "Le réessai explicitement demandé doit pouvoir recevoir son acquittement.")
        let bodies = await network.bodies
        guard bodies.count == 2,
              let before = try JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any],
              let after = try JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any],
              let beforeID = before["clientReportId"] as? String,
              let afterID = after["clientReportId"] as? String,
              let beforeItems = before["items"] as? [[String: Any]],
              let afterItems = after["items"] as? [[String: Any]] else {
            XCTFail("Deux intentions de signalement structurées doivent atteindre le transport."); return
        }
        XCTAssertTrue(beforeID == afterID, "Le redémarrage doit conserver le même identifiant d'intention durable.")
        let beforeBytes = try JSONSerialization.data(withJSONObject: beforeItems, options: [.sortedKeys])
        let afterBytes = try JSONSerialization.data(withJSONObject: afterItems, options: [.sortedKeys])
        XCTAssertTrue(beforeBytes == afterBytes, "Le réessai doit conserver les mêmes enveloppes, sinon le serveur refuse l'empreinte.")
        let sealCount = await sealing.count
        XCTAssertEqual(sealCount, 1, "La reprise ne doit pas rechiffrer une intention déjà persistée.")
        let afterACK = try await reopenedStore.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertTrue(afterACK == nil, "L'acquittement retire durablement l'intention.")
    }

    func testReportOtherWorkspaceCannotAbandonDuringSealing() async throws {
        try await assertConcurrentReportAbandon(pauseDuringSealing: true)
    }

    func testReportOtherWorkspaceCannotAbandonDuringHTTP() async throws {
        try await assertConcurrentReportAbandon(pauseDuringSealing: false)
    }

    private func assertConcurrentReportAbandon(pauseDuringSealing: Bool) async throws {
        let scope = scope
        let conversation = conversation
        let store = try MessagingProtectedStore(scope: scope)
        let otherStore = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let reached = expectation(description: "Envoi suspendu à la frontière choisie")
        let gate = ReportSuspensionGate(reached: reached)
        let network = ReportLostAcknowledgementHTTP(response: envelope("{}"), gate: pauseDuringSealing ? nil : gate)
        let sealing = ReportChangingSyntheticSealing(gate: pauseDuringSealing ? gate : nil)
        let actions = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: network, currentScope: { scope })
        let first = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), actions: actions,
            reportSealing: sealing, reports: store, currentScope: { scope })
        let other = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), actions: actions,
            reportSealing: sealing, reports: otherStore, currentScope: { scope })
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("SYNTHETIC_REPORT".utf8)))
        let sending = Task { await first.report([message], conversationID: conversation) }
        let waitResult = await XCTWaiter.fulfillment(of: [reached], timeout: 5)
        XCTAssertEqual(waitResult, .completed)
        let unrelatedAbandon = await other.abandonReport(conversationID: UUID())
        XCTAssertTrue(unrelatedAbandon, "Une autre conversation n'est pas bloquée.")
        let abandoned = await other.abandonReport(conversationID: conversation)
        XCTAssertFalse(abandoned, "Un autre workspace ne peut pas annoncer un abandon pendant un envoi engagé.")
        let competingSend = await other.report([message], conversationID: conversation)
        XCTAssertFalse(competingSend, "Le cycle entier est exclusif entre workspaces.")
        await gate.release()
        let firstSent = await sending.value
        XCTAssertFalse(firstSent, "ACK perdu injecté après la suspension.")
        let reopenedStore = try MessagingProtectedStore(scope: scope)
        let retained = try await reopenedStore.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertTrue(retained != nil, "L'intention doit survivre au refus d'abandon et à la perte d'ACK.")
        let restarted = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), actions: actions,
            reportSealing: sealing, reports: reopenedStore, currentScope: { scope })
        let retried = await restarted.report([message], conversationID: conversation)
        XCTAssertTrue(retried)
        let bodies = await network.bodies
        guard bodies.count == 2 else { XCTFail("Deux POST attendus exactement."); return }
        let before = try JSONSerialization.jsonObject(with: bodies[0])
        let after = try JSONSerialization.jsonObject(with: bodies[1])
        let beforeBytes = try JSONSerialization.data(withJSONObject: before, options: [.sortedKeys])
        let afterBytes = try JSONSerialization.data(withJSONObject: after, options: [.sortedKeys])
        XCTAssertTrue(beforeBytes == afterBytes, "Identifiant et enveloppes exacts conservés après réouverture.")
        let sealCount = await sealing.count
        XCTAssertEqual(sealCount, 1)
        let afterACK = try await reopenedStore.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertTrue(afterACK == nil)
        let finallyAbandoned = await other.abandonReport(conversationID: conversation)
        XCTAssertTrue(finallyAbandoned, "L'exclusion est libérée après la fin du cycle.")
    }

    func testReportWriteFailurePreventsAnyHTTPPost() async {
        let scope = scope
        let network = ReportLostAcknowledgementHTTP(response: envelope("{}"))
        let actions = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: network, currentScope: { scope })
        let workspace = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), actions: actions,
            reportSealing: ReportChangingSyntheticSealing(), reports: ReportWriteFailureStore(), currentScope: { scope })
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("SYNTHETIC_REPORT".utf8)))
        let sent = await workspace.report([message], conversationID: conversation)
        XCTAssertFalse(sent)
        XCTAssertEqual(workspace.actionError, .protectionUnavailable)
        let bodies = await network.bodies
        XCTAssertTrue(bodies.isEmpty, "Aucun POST sans intention écrite durablement.")
    }

    func testReportRejectsContextChangeBeforeRetry() async throws {
        let scope = scope
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let network = ReportLostAcknowledgementHTTP(response: envelope("{}"))
        let actions = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: network, currentScope: { scope })
        let workspace = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), actions: actions,
            reportSealing: ReportChangingSyntheticSealing(), reports: store, currentScope: { nil })
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("SYNTHETIC_REPORT".utf8)))
        let sent = await workspace.report([message], conversationID: conversation)
        XCTAssertFalse(sent)
        XCTAssertEqual(workspace.actionError, .contextChanged)
        let bodies = await network.bodies
        XCTAssertTrue(bodies.isEmpty)
    }

    func testReportContextChangeDuringSealingPreventsPersistenceAndPost() async throws {
        let scope = scope
        let context = ReportCurrentScope(scope)
        let store = try MessagingProtectedStore(scope: scope)
        addTeardownBlock { try await store.purge(scope: scope) }
        let network = ReportLostAcknowledgementHTTP(response: envelope("{}"))
        let actions = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: network, currentScope: { scope })
        let sealing = ReportContextSwitchingSealing { context.value = nil }
        let workspace = MessagingWorkspace(scope: scope, cryptography: ThreadSyntheticCipher(), actions: actions,
            reportSealing: sealing, reports: store, currentScope: { context.value })
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: UUID(),
            acceptedAt: Date(), ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("SYNTHETIC_REPORT".utf8)))
        let sent = await workspace.report([message], conversationID: conversation)
        XCTAssertFalse(sent)
        XCTAssertEqual(workspace.actionError, .contextChanged)
        let bodies = await network.bodies
        XCTAssertTrue(bodies.isEmpty)
        let pending = try await store.pendingReport(conversationID: conversation, scope: scope)
        XCTAssertTrue(pending == nil)
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

    /// Arrivée (readable_after = last_sequence) : le serveur ne renvoie rien d'antérieur, le client affiche un fil vide sans erreur.
    func testArrivalWithEmptyHistoryShowsNoError() async throws {
        let body = envelope(#"{"items":[],"nextCursor":null,"access":{"canWrite":true,"readableUntilSequence":null,"isGroupAdmin":false},"readStates":[]}"#)
        let http = transport { _ in body }
        let page = try await MessagingAPIClient(transport: http).messages(scope: scope, conversationID: conversation, before: nil)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertNil(page.nextCursor)
        let workspace = MessagingWorkspace(scope: scope, service: MessagingAPIClient(transport: http), currentScope: { [scope] in scope })
        await workspace.loadMessages(conversation)
        XCTAssertNil(workspace.error)
        XCTAssertTrue(workspace.visibleMessages(conversation).isEmpty)
        XCTAssertFalse(workspace.canLoadMoreMessages(conversation))
        XCTAssertTrue(workspace.access(for: conversation).canWrite)
    }

    func testDeviceLimitBlocksEnqueueWithoutPlaintextFallback() async {
        let outbox = MessagingOutboxCoordinator(scope: scope, service: LimitedService(school: school, conversation: conversation),
            cryptography: DeviceLimitedCipher(), outbox: UnavailableMessagingOutbox(), currentScope: { [scope] in scope })
        do {
            _ = try await outbox.enqueue(content: .init(text: "bonjour"), conversationID: conversation, currentScope: scope)
            XCTFail("Aucun envoi sans appareil enregistré")
        } catch MessagingFailure.deviceLimitReached {
        } catch { XCTFail("\(error)") }
        XCTAssertTrue(MessagingFailure.deviceLimitReached.localizedDescription.contains("Retire un appareil"))
    }

    func testRelayMapsDeviceLimitConflict() async throws {
        let scope = scope
        let relay = MessagingCryptoHTTPRelay.using(baseURL: baseURL, tokenSource: ThreadFixtureToken(),
            transport: ThreadRecordingHTTP { request in
                SchoolHTTPResponse(data: Data(#"{"error":{"code":"DEVICE_LIMIT_REACHED"}}"#.utf8), status: 409,
                                   url: request.url!, contentType: "application/json")
            }, currentScope: { scope })
        do {
            _ = try await relay.call(scope: scope, deviceID: "SYNTHDEVICE01", method: "POST", path: ["keys", "upload"], query: [], body: Data("{}".utf8))
            XCTFail("409 attendu")
        } catch MessagingCryptoRelayFailure.deviceLimitReached {}
    }

    func testReinstateOffersRemovedMemberThenClearsIt() async {
        let actions = MembersActions(admin: account)
        let workspace = MessagingWorkspace(scope: scope, actions: actions, currentScope: { [scope] in scope })
        await workspace.loadMembers()
        let target = MembersActions.other
        await workspace.removeMember(target)
        XCTAssertEqual(workspace.removedMembers.map(\.id), [target])
        await workspace.reinstateMember(target)
        XCTAssertTrue(workspace.removedMembers.isEmpty)
        XCTAssertTrue(workspace.members.contains { $0.id == target })
        let calls = await actions.calls
        XCTAssertEqual(calls.filter { !$0.hasPrefix("GET") }, ["DELETE \(target)", "PUT \(target)"])
    }

    /// Les retirés viennent du serveur, y compris ceux d'une session précédente.
    func testRemovedSectionLoadsServerListForGroupAdmin() async {
        let actions = MembersActions(admin: account)
        let earlier = MessagingMember(id: UUID(), displayName: "Paul", hasPhoto: false, isGroupAdmin: false)
        await actions.setServerRemoved([earlier])
        let workspace = MessagingWorkspace(scope: scope, actions: actions, currentScope: { [scope] in scope })
        await workspace.loadMembers()
        XCTAssertEqual(workspace.removedMembers.map(\.id), [earlier.id])
        let calls = await actions.calls
        XCTAssertEqual(calls, ["GET removed"])
    }

    func testRemovedListNotRequestedForNonAdmin() async {
        let actions = MembersActions(admin: UUID())
        await actions.setServerRemoved([MessagingMember(id: UUID(), displayName: "Paul", hasPhoto: false, isGroupAdmin: false)])
        let workspace = MessagingWorkspace(scope: scope, actions: actions, currentScope: { [scope] in scope })
        await workspace.loadMembers()
        XCTAssertTrue(workspace.removedMembers.isEmpty)
        let calls = await actions.calls
        XCTAssertTrue(calls.isEmpty)
    }

    // MARK: Ordre des messages et aperçus (#98)

    private func wire(_ sequence: Int, id: UUID = UUID(), text: String = "m", sender: UUID? = nil,
                      at date: Date = Date(timeIntervalSince1970: 1_000)) -> MessagingWireMessage {
        MessagingWireMessage(id: id, conversationID: conversation, schoolID: school, senderID: sender ?? account,
            acceptedAt: date, ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data(text.utf8)),
            meta: MessagingMessageMeta(sequence: sequence))
    }

    func testDescendingPagesAreShownOldestFirstAcrossPages() async {
        let service = PagedService(pages: [nil: .init(items: [wire(6), wire(5), wire(4)], nextCursor: "c1"),
                                           "c1": .init(items: [wire(3), wire(2), wire(1)], nextCursor: nil)])
        let workspace = MessagingWorkspace(scope: scope, service: service, currentScope: { [scope] in scope })
        await workspace.loadMessages(conversation)
        XCTAssertEqual(workspace.visibleMessages(conversation).map(\.meta.sequence), [4, 5, 6])
        await workspace.loadMessages(conversation, more: true)
        XCTAssertEqual(workspace.visibleMessages(conversation).map(\.meta.sequence), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(workspace.lastReadableSequence(conversation), 6)
    }

    func testInitialReloadMergesWithOlderPagesAndReplacesDuplicates() async {
        let kept = UUID()
        let service = PagedService(pages: [nil: .init(items: [wire(4, id: kept), wire(3)], nextCursor: "c1"),
                                           "c1": .init(items: [wire(2), wire(1)], nextCursor: nil)])
        let workspace = MessagingWorkspace(scope: scope, service: service, currentScope: { [scope] in scope })
        await workspace.loadMessages(conversation)
        await workspace.loadMessages(conversation, more: true)
        var pinned = wire(4, id: kept); pinned.meta.pinned = true
        await service.setFirstPage(.init(items: [wire(5), pinned], nextCursor: "c1"))
        await workspace.loadMessages(conversation)
        let visible = workspace.visibleMessages(conversation)
        XCTAssertEqual(visible.map(\.meta.sequence), [1, 2, 3, 4, 5])
        XCTAssertEqual(visible.filter { $0.id == kept }.count, 1)
        XCTAssertTrue(workspace.message(kept, in: conversation)?.meta.pinned == true)
        XCTAssertFalse(workspace.canLoadMoreMessages(conversation))
    }

    func testOutOfOrderAndSameDateUseSequenceThenStableID() {
        let date = Date(timeIntervalSince1970: 5)
        let a = wire(2, at: date), b = wire(1, at: date.addingTimeInterval(60)), c = wire(3, at: date)
        let merged = MessagingWorkspace.mergedMessages([c], [a, b])
        XCTAssertEqual(merged.map(\.meta.sequence), [1, 2, 3])
        let x = wire(7, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let y = wire(7, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        XCTAssertEqual(MessagingWorkspace.mergedMessages([], [x, y]).map(\.id), [y.id, x.id])
        XCTAssertEqual(MessagingWorkspace.mergedMessages([], [y, x]).map(\.id), [y.id, x.id])
    }

    func testPreviewPrefersDecryptedSessionMessage() async {
        let other = UUID()
        let service = PagedService(pages: [nil: .init(items: [wire(2, text: "Dernier", sender: other), wire(1, text: "Premier")], nextCursor: nil)])
        let workspace = MessagingWorkspace(scope: scope, service: service, cryptography: ThreadSyntheticCipher(),
                                           currentScope: { [scope] in scope })
        XCTAssertNil(workspace.preview(for: conversation))
        await workspace.loadMessages(conversation)
        XCTAssertNil(workspace.preview(for: conversation))
        let last = workspace.visibleMessages(conversation).last!
        _ = await workspace.content(for: last)
        XCTAssertEqual(workspace.preview(for: conversation),
            MessagingInboxPreview(text: "Dernier", date: last.acceptedAt, fromMe: false, unavailable: false))
    }

    func testPreviewsComeFromSealedHistoryWithoutNetworkAndClearOnContextChange() async {
        let history = PreviewHistory(entries: [
            MessagingHistoryEntry(messageID: UUID(), conversationID: conversation, sequence: 1, senderID: account,
                acceptedAt: Date(timeIntervalSince1970: 1), content: MessagingPlainContent(text: "Ancien")),
            MessagingHistoryEntry(messageID: UUID(), conversationID: conversation, sequence: 3, senderID: account,
                acceptedAt: Date(timeIntervalSince1970: 3), content: MessagingPlainContent(text: "Récent")),
        ])
        let service = PagedService(pages: [:], conversations: [MessagingConversation(id: conversation, schoolID: school,
            kind: .privateExchange, title: "Léa", identityDetail: nil, unreadCount: 0, lastSequence: 3,
            lastReadSequence: 3, mutedUntil: nil, readStateVersion: 1)])
        let current = PreviewScopeBox(scope)
        let workspace = MessagingWorkspace(scope: scope, service: service, history: history, currentScope: { current.value })
        await workspace.loadConversations()
        await workspace.loadPreviews()
        XCTAssertEqual(workspace.preview(for: conversation),
            MessagingInboxPreview(text: "Récent", date: Date(timeIntervalSince1970: 3), fromMe: true, unavailable: false))
        let messageCalls = await service.messageCalls
        XCTAssertEqual(messageCalls, 0)
        current.value = nil
        await workspace.loadPreviews()
        XCTAssertNil(workspace.preview(for: conversation))
    }
}

/// Pages fixées par curseur, renvoyées telles quelles (séquence décroissante comme le contrat serveur).
private actor PagedService: MessagingService {
    private var pages: [String?: MessagingPage<MessagingWireMessage>]
    private let listed: [MessagingConversation]
    private(set) var messageCalls = 0
    init(pages: [String?: MessagingPage<MessagingWireMessage>], conversations: [MessagingConversation] = []) {
        self.pages = pages; self.listed = conversations
    }
    func setFirstPage(_ page: MessagingPage<MessagingWireMessage>) { pages[nil] = page }
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> {
        MessagingPage(items: listed, nextCursor: nil)
    }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> {
        messageCalls += 1
        guard let page = pages[before] else { throw MessagingFailure.unavailable }
        return page
    }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement { throw MessagingFailure.unavailable }
}

@MainActor private final class PreviewScopeBox: Sendable {
    var value: MessagingScope?
    init(_ value: MessagingScope?) { self.value = value }
}

private actor PreviewHistory: MessagingHistoryStore {
    private var stored: [MessagingHistoryEntry]
    init(entries: [MessagingHistoryEntry]) { stored = entries }
    func upsert(_ entries: [MessagingHistoryEntry], scope: MessagingScope) async throws { stored += entries }
    func entries(conversationID: UUID, scope: MessagingScope) async throws -> [MessagingHistoryEntry] {
        stored.filter { $0.conversationID == conversationID }
    }
    func remove(messageIDs: [UUID], scope: MessagingScope) async throws { stored.removeAll { messageIDs.contains($0.messageID) } }
    func truncate(conversationID: UUID, after sequence: Int, scope: MessagingScope) async throws {
        stored.removeAll { $0.conversationID == conversationID && $0.sequence > sequence }
    }
}

private struct DeviceLimitedCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { false }
    func availabilityFailure(scope: MessagingScope, conversationID: UUID) async -> MessagingFailure? { .deviceLimitReached }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext { throw MessagingFailure.deviceLimitReached }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { throw MessagingFailure.deviceLimitReached }
}

/// Fault injection at the HTTP boundary only. Workspace, serialization and protected store remain real.
private actor ReportLostAcknowledgementHTTP: SchoolHTTPTransport {
    let response: Data
    let gate: ReportSuspensionGate?
    private(set) var bodies: [Data] = []
    init(response: Data, gate: ReportSuspensionGate? = nil) { self.response = response; self.gate = gate }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard request.httpMethod == "POST", request.url?.path.hasSuffix("/messaging/reports") == true,
              let body = request.httpBody else { throw MessagingFailure.invalidResponse }
        let first = bodies.isEmpty
        bodies.append(body)
        if first {
            await gate?.pause()
            throw URLError(.networkConnectionLost)
        }
        return SchoolHTTPResponse(data: response, status: 200, url: request.url!, contentType: "application/json")
    }
}

/// Deliberately different opaque bytes on each call expose accidental re-encryption on retry.
private actor ReportChangingSyntheticSealing: MessagingReportSealing {
    private(set) var count = 0
    let gate: ReportSuspensionGate?
    init(gate: ReportSuspensionGate? = nil) { self.gate = gate }
    func sealForSchoolAdmins(_ plaintext: Data, scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        count += 1
        let ordinal = count
        if ordinal == 1 { await gate?.pause() }
        return MessagingCiphertext(scheme: "TEST_ONLY", keyID: "admins", payload: Data("SYNTHETIC_SEAL_\(ordinal)".utf8))
    }
}

/// Explicit rendezvous, no timing sleeps. Release also works if the expectation times out before entry.
private actor ReportSuspensionGate {
    let reached: XCTestExpectation
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(reached: XCTestExpectation) { self.reached = reached }
    func pause() async {
        reached.fulfill()
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private struct ReportWriteFailureStore: MessagingProtectedReports {
    func pendingReport(conversationID: UUID, scope: MessagingScope) async throws -> MessagingPendingReport? { nil }
    func prepareReport(_ candidate: MessagingPendingReport, scope: MessagingScope) async throws -> MessagingPendingReport {
        throw MessagingFailure.protectionUnavailable
    }
    func removeReport(conversationID: UUID, clientReportID: UUID, scope: MessagingScope) async throws {
        throw MessagingFailure.protectionUnavailable
    }
}

@MainActor private final class ReportCurrentScope {
    var value: MessagingScope?
    init(_ value: MessagingScope) { self.value = value }
}

private struct ReportContextSwitchingSealing: MessagingReportSealing {
    let switchContext: @MainActor @Sendable () -> Void
    func sealForSchoolAdmins(_ plaintext: Data, scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        await switchContext()
        return MessagingCiphertext(scheme: "TEST_ONLY", keyID: "admins", payload: Data([1]))
    }
}

private actor MembersActions: MessagingThreadActions {
    static let other = UUID()
    let admin: UUID
    private var removed = false
    private var serverRemoved: [MessagingMember] = []
    private(set) var calls: [String] = []
    init(admin: UUID) { self.admin = admin }
    func delete(scope: MessagingScope, conversationID: UUID, messageID: UUID, for deletion: MessagingDeletionScope) async throws {}
    func setReaction(scope: MessagingScope, conversationID: UUID, messageID: UUID, emoji: String, active: Bool) async throws {}
    func setPinned(scope: MessagingScope, conversationID: UUID, messageID: UUID, pinned: Bool) async throws {}
    func vote(scope: MessagingScope, conversationID: UUID, messageID: UUID, optionIDs: [String]) async throws {}
    func closePoll(scope: MessagingScope, conversationID: UUID, messageID: UUID) async throws {}
    func setGroupAdmin(scope: MessagingScope, personID: UUID, admin: Bool) async throws {}
    func removeGeneralMember(scope: MessagingScope, personID: UUID) async throws { removed = true; calls.append("DELETE \(personID)") }
    func reinstateGeneralMember(scope: MessagingScope, personID: UUID) async throws { removed = false; calls.append("PUT \(personID)") }
    func members(scope: MessagingScope) async throws -> [MessagingMember] {
        [MessagingMember(id: admin, displayName: "Admin", hasPhoto: false, isGroupAdmin: true)]
            + (removed ? [] : [MessagingMember(id: Self.other, displayName: "Léa", hasPhoto: false, isGroupAdmin: false)])
    }
    func removedMembers(scope: MessagingScope) async throws -> [MessagingMember] {
        calls.append("GET removed")
        return (removed ? [MessagingMember(id: Self.other, displayName: "Léa", hasPhoto: false, isGroupAdmin: false)] : [])
            + serverRemoved
    }
    func setServerRemoved(_ members: [MessagingMember]) { serverRemoved = members }
    func report(scope: MessagingScope, conversationID: UUID, clientReportID: UUID, items: [MessagingReportItem]) async throws {}
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
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: plaintext, expectedMembersEpoch: 0)
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
