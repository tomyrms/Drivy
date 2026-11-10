import XCTest
@testable import Drivy

/// #445 : une alerte de premier plan du fil visible déclenche une lecture autorisée de SA séquence, ou reste présentée.
/// NON COMPILÉ / NON EXÉCUTÉ localement : à lancer sur runner Apple. Doubles synthétiques, aucun contenu réel.
@MainActor
final class MessagingForegroundAlertTests: XCTestCase {
    private let school = UUID(), account = UUID(), other = UUID(), conversation = UUID()
    private var scope: MessagingScope { MessagingScope(accountID: account, schoolID: school, accessEpoch: 1) }

    override func tearDown() {
        MessagingActiveConversation.clear(conversation)
        super.tearDown()
    }

    private func message(sequence: Int) -> MessagingWireMessage {
        var meta = MessagingMessageMeta(sequence: sequence)
        meta.reactions = []
        return MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: other,
            acceptedAt: Date(timeIntervalSince1970: TimeInterval(sequence)),
            ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "k", payload: Data("m".utf8)), meta: meta)
    }

    private func workspace(sequences: [Int], directory: AlertDirectory) -> MessagingWorkspace {
        let box = AlertScopeBox(scope)
        return MessagingWorkspace(scope: scope, service: AlertService(messages: sequences.map(message)), directory: directory,
                                  notifications: AlertNotifications(),
                                  mutationLatency: MessagingMutationLatency(slow: .seconds(60), unconfirmed: .seconds(120)),
                                  currentScope: { box.value })
    }

    private func info(sequence: Int?, conversationID: UUID? = nil) -> [AnyHashable: Any] {
        var value: [AnyHashable: Any] = ["kind": "MESSAGING", "schoolId": school.uuidString.lowercased(),
                                         "conversationId": (conversationID ?? conversation).uuidString.lowercased()]
        if let sequence { value["sequence"] = sequence }
        return value
    }

    // MARK: Lecture autorisée côté workspace

    /// Séquence pas encore chargée : le fil est relu, la séquence est confirmée lue par le serveur, l'alerte est absorbée.
    func testUnloadedSequenceIsLoadedThenReadBeforeTheAlertIsAbsorbed() async {
        let directory = AlertDirectory()
        let workspace = workspace(sequences: [4, 5], directory: directory)
        let absorbed = await workspace.absorbForegroundAlert(conversation, sequence: 5)
        XCTAssertTrue(absorbed)
        let reads = await directory.reads
        XCTAssertEqual(reads, [5])
        XCTAssertEqual(workspace.readStates[conversation]?.lastReadSequence, 5)
    }

    /// Lecture refusée ou perdue : l'alerte n'est jamais absorbée.
    func testFailedReadKeepsTheAlert() async {
        let directory = AlertDirectory(failure: .unavailable)
        let workspace = workspace(sequences: [5], directory: directory)
        let absorbed = await workspace.absorbForegroundAlert(conversation, sequence: 5)
        XCTAssertFalse(absorbed)
        XCTAssertNil(workspace.readStates[conversation]?.lastReadSequence)
    }

    /// La séquence visée n'est pas disponible dans le fil lisible : aucune lecture n'est inventée.
    func testSequenceNotAvailableKeepsTheAlertAndSendsNoRead() async {
        let directory = AlertDirectory()
        let workspace = workspace(sequences: [3, 4], directory: directory)
        let absorbed = await workspace.absorbForegroundAlert(conversation, sequence: 5)
        XCTAssertFalse(absorbed)
        let reads = await directory.reads
        XCTAssertTrue(reads.isEmpty)
    }

    // MARK: Décision du délégué

    func testAbsorbedOnlyWhenTheReadConfirmsTheTargetedSequence() async {
        MessagingActiveConversation.set(schoolID: school, conversationID: conversation, atBottom: true) { sequence in sequence == 5 }
        let confirmed = await MessagingActiveConversation.absorbs(info(sequence: 5))
        XCTAssertTrue(confirmed)
        let refused = await MessagingActiveConversation.absorbs(info(sequence: 6))
        XCTAssertFalse(refused, "Une séquence que la lecture ne confirme pas reste présentée")
        let anonymous = await MessagingActiveConversation.absorbs(info(sequence: nil))
        XCTAssertFalse(anonymous, "Sans séquence, aucune lecture possible : l'alerte reste")
        let elsewhere = await MessagingActiveConversation.absorbs(info(sequence: 5, conversationID: other))
        XCTAssertFalse(elsewhere)
    }

    /// Fil au bas mais recouvert par une feuille : pas d'absorption, pas de lecture.
    func testCoveredThreadNeverAbsorbs() async {
        let asked = AlertCounter()
        MessagingActiveConversation.set(schoolID: school, conversationID: conversation, atBottom: true, covered: true) { _ in
            await asked.bump(); return true
        }
        let absorbed = await MessagingActiveConversation.absorbs(info(sequence: 5))
        XCTAssertFalse(absorbed)
        let calls = await asked.value
        XCTAssertEqual(calls, 0, "Aucune lecture n'est lancée sous une feuille")
        XCTAssertFalse(MessagingActiveConversation.suppresses(info(sequence: 5),
            state: .init(schoolID: school, conversationID: conversation, atBottom: true, covered: true)))
    }

    /// Fil non affiché au bas (historique parcouru, app inactive) : ni lecture ni absorption.
    func testThreadNotAtBottomNeverAbsorbs() async {
        MessagingActiveConversation.set(schoolID: school, conversationID: conversation, atBottom: false) { _ in true }
        let absorbed = await MessagingActiveConversation.absorbs(info(sequence: 5))
        XCTAssertFalse(absorbed)
    }

    /// Une feuille s'ouvre pendant la lecture : l'alerte est quand même présentée.
    func testThreadCoveredDuringTheReadKeepsTheAlert() async {
        let school = school, conversation = conversation
        MessagingActiveConversation.set(schoolID: school, conversationID: conversation, atBottom: true) { _ in
            MessagingActiveConversation.set(schoolID: school, conversationID: conversation, atBottom: true, covered: true)
            return true
        }
        let absorbed = await MessagingActiveConversation.absorbs(info(sequence: 5))
        XCTAssertFalse(absorbed)
    }

    /// Aucune conversation enregistrée (écran quitté) : rien n'est absorbé.
    func testClearedConversationAbsorbsNothing() async {
        MessagingActiveConversation.set(schoolID: school, conversationID: conversation, atBottom: true) { _ in true }
        MessagingActiveConversation.clear(conversation)
        let absorbed = await MessagingActiveConversation.absorbs(info(sequence: 5))
        XCTAssertFalse(absorbed)
    }
}

/// Aucun appel au centre de notifications du système en test.
private struct AlertNotifications: MessagingNotificationCleaning {
    func removeDelivered(schoolID: UUID, conversationID: UUID, upTo sequence: Int) async {}
    func setMessagingBadge(_ count: Int) async {}
}

private actor AlertCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}

@MainActor private final class AlertScopeBox: Sendable {
    var value: MessagingScope?
    init(_ value: MessagingScope?) { self.value = value }
}

/// Service dont le fil contient les messages donnés, dans l'ordre des séquences.
private actor AlertService: MessagingService {
    private let all: [MessagingWireMessage]
    init(messages: [MessagingWireMessage]) { all = messages }
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> {
        MessagingPage(items: [], nextCursor: nil)
    }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> {
        MessagingPage(items: all, nextCursor: nil)
    }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement { throw MessagingFailure.unavailable }
}

/// Accusés de lecture enregistrés ; échec programmable.
private actor AlertDirectory: MessagingDirectoryService {
    private(set) var reads: [Int] = []
    private let failure: MessagingFailure?
    init(failure: MessagingFailure? = nil) { self.failure = failure }
    func readState(scope: MessagingScope, conversationID: UUID, sequence: Int,
                   mutedUntil: Date?, expectedVersion: Int?) async throws -> MessagingReadState {
        if let failure { throw failure }
        reads.append(sequence)
        return .init(lastReadSequence: sequence, mutedUntil: mutedUntil, version: (expectedVersion ?? 0) + 1)
    }
    func contacts(scope: MessagingScope) async throws -> [MessagingContact] { [] }
    func generalMembers(scope: MessagingScope) async throws -> [MessagingContact] { [] }
    func privateConversation(scope: MessagingScope, peerID: UUID) async throws -> UUID { throw MessagingFailure.unavailable }
    func generalConversation(scope: MessagingScope) async throws -> UUID { throw MessagingFailure.unavailable }
}
