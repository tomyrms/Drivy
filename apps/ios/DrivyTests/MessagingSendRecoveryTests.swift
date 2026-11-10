import XCTest
@testable import Drivy

/// #428 : reprise unique des envois (actualisation, retour réseau, relance). NON COMPILÉ / NON EXÉCUTÉ localement :
/// à lancer sur runner Apple. Vrais workspace et coordinateur, transport synthétique scripté par message.
@MainActor
final class MessagingSendRecoveryTests: XCTestCase {
    private let school = UUID(), account = UUID(), conversation = UUID(), otherConversation = UUID()
    private var scope: MessagingScope { MessagingScope(accountID: account, schoolID: school, accessEpoch: 1) }

    private func pending(_ text: String, in conversationID: UUID? = nil) -> MessagingPending {
        MessagingPending(clientMessageID: UUID(), conversationID: conversationID ?? conversation,
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data(text.utf8), expectedMembersEpoch: 1),
            recoveryContent: Data(text.utf8))
    }

    private func workspace(_ service: ScriptedSender, store: RecoveryStore = RecoveryStore()) -> MessagingWorkspace {
        let box = RecoveryScopeBox(scope)
        return MessagingWorkspace(scope: scope, service: service, cryptography: RecoveryCipher(), outbox: store,
                                  mutationLatency: MessagingMutationLatency(slow: .seconds(60), unconfirmed: .seconds(120)),
                                  currentScope: { box.value })
    }

    private func until(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition non atteinte", file: file, line: line)
    }

    private func isAccepted(_ workspace: MessagingWorkspace, _ entry: MessagingPending) -> Bool {
        if case .accepted? = workspace.sendStatus(entry.clientMessageID) { return true }
        return false
    }

    /// M1 incertain (réponse perdue), M2 derrière lui : l'actualisation confirme M1 sans nouvel envoi de contenu,
    /// puis M2 part, dans l'ordre. Le même clientMessageID est rejoué, dédupliqué par le serveur.
    func testUncertainFirstMessageConfirmedOnRefreshReleasesTheSecond() async {
        let m1 = pending("un"), m2 = pending("deux")
        let service = ScriptedSender(account: account, school: school, scripts: [m1.clientMessageID: [.lost, .accept]])
        let workspace = workspace(service)
        workspace.scheduleSend(m1)
        await until { workspace.sendStatus(m1.clientMessageID) == .uncertain }
        workspace.scheduleSend(m2)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(workspace.sendStatus(m2.clientMessageID), .queued, "M2 ne passe jamais devant un M1 incertain")
        let before = await service.sent
        XCTAssertEqual(before, [m1.clientMessageID])
        await workspace.refreshVisible()
        await until { self.isAccepted(workspace, m2) }
        XCTAssertTrue(isAccepted(workspace, m1))
        let order = await service.sent
        XCTAssertEqual(order, [m1.clientMessageID, m1.clientMessageID, m2.clientMessageID])
    }

    /// M1 encore incertain au retour : M2 reste retenu, rien n'est inventé.
    func testStillUncertainFirstMessageKeepsTheSecondHeld() async {
        let m1 = pending("un"), m2 = pending("deux")
        let service = ScriptedSender(account: account, school: school, scripts: [m1.clientMessageID: [.lost, .lost]])
        let workspace = workspace(service)
        workspace.scheduleSend(m1)
        await until { workspace.sendStatus(m1.clientMessageID) == .uncertain }
        workspace.scheduleSend(m2)
        await workspace.refreshVisible()
        XCTAssertEqual(workspace.sendStatus(m1.clientMessageID), .uncertain)
        XCTAssertEqual(workspace.sendStatus(m2.clientMessageID), .queued)
        let sent = await service.sent
        XCTAssertEqual(sent, [m1.clientMessageID, m1.clientMessageID])
    }

    /// Un M1 incertain d'une conversation ne retient aucune autre conversation.
    func testConversationsAreIndependent() async {
        let m1 = pending("un"), other = pending("autre", in: otherConversation)
        let service = ScriptedSender(account: account, school: school, scripts: [m1.clientMessageID: [.lost, .lost]])
        let workspace = workspace(service)
        workspace.scheduleSend(m1)
        await until { workspace.sendStatus(m1.clientMessageID) == .uncertain }
        workspace.scheduleSend(other)
        await until { self.isAccepted(workspace, other) }
        XCTAssertEqual(workspace.sendStatus(m1.clientMessageID), .uncertain)
    }

    /// Un refus définitif est distinct d'une panne : il ne retient pas le suivant et n'est pas rejoué.
    func testDefinitiveRefusalDoesNotHoldTheNextAndIsNotReplayed() async {
        let m1 = pending("refusé"), m2 = pending("suivant")
        let service = ScriptedSender(account: account, school: school, scripts: [m1.clientMessageID: [.refuse(.membersChanged)]])
        let workspace = workspace(service)
        workspace.scheduleSend(m1)
        workspace.scheduleSend(m2)
        await until { self.isAccepted(workspace, m2) }
        XCTAssertEqual(workspace.sendStatus(m1.clientMessageID), .failed(.membersChanged))
        await workspace.refreshVisible()
        let sent = await service.sent
        XCTAssertEqual(sent, [m1.clientMessageID, m2.clientMessageID], "Un refus n'est jamais renvoyé par la reprise")
    }

    /// Relance de l'app : le journal durable est rattaché à la file dans son ordre, une seule fois.
    func testRelaunchRestoresTheDurableJournalInOrder() async {
        let m1 = pending("un"), m2 = pending("deux")
        let store = RecoveryStore()
        try? await store.put(m1, scope: scope)
        try? await store.put(m2, scope: scope)
        let service = ScriptedSender(account: account, school: school, scripts: [:])
        let workspace = workspace(service, store: store)
        await workspace.refreshVisible()
        await until { self.isAccepted(workspace, m2) }
        await workspace.refreshVisible()
        let sent = await service.sent
        XCTAssertEqual(sent, [m1.clientMessageID, m2.clientMessageID])
    }

    /// Retour réseau : même route de reprise que l'actualisation, sans doublon d'envoi.
    func testNetworkReturnUsesTheSameRecoveryPath() async {
        let m1 = pending("un")
        let service = ScriptedSender(account: account, school: school, scripts: [m1.clientMessageID: [.lost, .accept]])
        let workspace = workspace(service)
        workspace.scheduleSend(m1)
        await until { workspace.sendStatus(m1.clientMessageID) == .uncertain }
        workspace.setNetworkAvailable(false)
        workspace.setNetworkAvailable(true)
        await until { self.isAccepted(workspace, m1) }
        let sent = await service.sent
        XCTAssertEqual(sent, [m1.clientMessageID, m1.clientMessageID])
    }

    /// Une panne de protection rencontrée pendant la reprise est signalée, jamais présentée comme un succès.
    func testProtectionFailureDuringRecoveryIsSignalled() async {
        let m1 = pending("un")
        let service = ScriptedSender(account: account, school: school, scripts: [m1.clientMessageID: [.lost, .refuse(.protectionUnavailable)]])
        let workspace = workspace(service)
        workspace.scheduleSend(m1)
        await until { workspace.sendStatus(m1.clientMessageID) == .uncertain }
        await workspace.refreshVisible()
        XCTAssertEqual(workspace.sendStatus(m1.clientMessageID), .failed(.protectionUnavailable))
        XCTAssertEqual(workspace.error, .protectionUnavailable)
    }
}

@MainActor private final class RecoveryScopeBox: Sendable {
    var value: MessagingScope?
    init(_ value: MessagingScope?) { self.value = value }
}

private struct RecoveryCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: plaintext, expectedMembersEpoch: 1)
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { ciphertext.payload }
}

/// Journal d'envoi synthétique en mémoire (double de test, jamais utilisé en production).
private actor RecoveryStore: MessagingProtectedOutbox {
    private var stored: [MessagingPending] = []
    func put(_ entry: MessagingPending, scope: MessagingScope) async throws { stored.append(entry) }
    func entries(scope: MessagingScope) async throws -> [MessagingPending] { stored }
    func remove(clientMessageID: UUID, scope: MessagingScope) async throws { stored.removeAll { $0.clientMessageID == clientMessageID } }
}

/// Transport scripté par clientMessageID : chaque appel consomme le comportement suivant, puis accepte.
private actor ScriptedSender: MessagingService {
    enum Behavior: Sendable { case accept, lost, refuse(MessagingFailure) }
    private(set) var sent: [UUID] = []
    private var scripts: [UUID: [Behavior]]
    private let account: UUID, school: UUID
    init(account: UUID, school: UUID, scripts: [UUID: [Behavior]]) { self.account = account; self.school = school; self.scripts = scripts }

    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> {
        MessagingPage(items: [], nextCursor: nil)
    }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> {
        MessagingPage(items: [], nextCursor: nil)
    }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement {
        sent.append(pending.clientMessageID)
        var script = scripts[pending.clientMessageID] ?? []
        let behavior = script.isEmpty ? Behavior.accept : script.removeFirst()
        scripts[pending.clientMessageID] = script
        switch behavior {
        case .lost: throw MessagingFailure.unavailable
        case .refuse(let failure): throw failure
        case .accept:
            return MessagingAcknowledgement(clientMessageID: pending.clientMessageID, serverMessageID: UUID(),
                conversationID: pending.conversationID, schoolID: school, acceptedAt: Date(), senderID: account)
        }
    }
}
