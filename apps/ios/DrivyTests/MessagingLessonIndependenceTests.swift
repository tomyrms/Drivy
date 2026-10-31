import Foundation
import Testing
@testable import Drivy

/// Les quatre états dégradés de la messagerie que la recette MSG-17 (#78) doit pouvoir traverser sans toucher à la leçon.
enum MessagingOutage: CaseIterable, Sendable {
    /// Chaque envoi échoue aussitôt.
    case serviceDown
    /// Un envoi est parti et ne reviendra qu'une fois la leçon terminée.
    case requestHung
    /// Deux cents messages attendent ; la reprise n'en traite que vingt par passage.
    case queueFull
    /// La file protégée est inutilisable : rien ne peut être lu ni écrit.
    case protectedStorageUnavailable
}

/// MSG-17 (#78) : une messagerie en panne, suspendue ou saturée n'empêche ni le départ, ni l'arrêt d'une leçon, ni « Signaler ».
/// Données synthétiques. La file de messagerie réelle (MessagingOutboxCoordinator) travaille pendant que la leçon se déroule
/// avec les fixtures existantes (SchoolLessonReportWorkspace pour le départ et l'arrêt, SchoolLiveObservationRecorder pour
/// « Signaler »). Cette preuve est logique : elle ne remplace ni le GPS réel, ni la recette sur deux appareils sur le terrain.
@MainActor struct MessagingLessonIndependenceTests {
    @Test(arguments: MessagingOutage.allCases)
    func departureStopAndReportDoNotWaitForMessaging(outage: MessagingOutage) async throws {
        let stress = try await MessagingStress.begin(outage)
        let lessonOutbox = ConfigurationOutboxStub()
        let model = lessonWorkspace(IndependenceLessonServer(), lessonOutbox)
        await model.load()
        #expect(model.lesson?.hasStarted == false)

        // Départ : la commande est durable, relue, et la leçon est commencée.
        #expect(await model.start())
        #expect(model.lesson?.hasStarted == true)
        let start = try #require(model.lesson?.startedAt)
        let startCommand = try #require(lessonOutbox.saves.first)
        #expect(startCommand.kind == .startLesson)

        // « Signaler » : le geste est écrit avant de rendre la main, sans attendre aucune réponse.
        let reportOutbox = ConfigurationOutboxStub()
        let recorder = liveRecorder(outbox: reportOutbox)
        #expect(recorder.markMoment())
        #expect(reportOutbox.saves.count == 1)
        recorder.stop()

        // Arrêt : la leçon est terminée avec ses heures réelles.
        #expect(await model.complete(start: start, end: start.addingTimeInterval(60), reason: "", localCaptureStopped: true))
        #expect(model.lesson?.status == "COMPLETED")
        #expect(lessonOutbox.saves.contains { $0.kind == .completeLesson })

        // Pendant tout cela, la messagerie était réellement dans son état dégradé.
        if outage == .requestHung {
            #expect(await stress.hungAttempts() == 1)
            #expect(stress.flushIsStillRunning)
        }
        let outcome = await stress.finish()
        #expect(!outcome.failures.isEmpty)
        #expect(outcome.acceptedCount == 0)
        switch outage {
        case .serviceDown, .requestHung:
            #expect(outcome.failures == [.unavailable, .unavailable, .unavailable])
            #expect(outcome.remaining == 3)
        case .queueFull:
            #expect(outcome.failures.count == 20)
            #expect(outcome.failures.allSatisfy({ $0 == .unavailable }))
            #expect(outcome.remaining == 200)
        case .protectedStorageUnavailable:
            #expect(outcome.failures == [.protectionUnavailable])
        }
        // La leçon n'a pas bougé pendant que la messagerie échouait.
        #expect(model.lesson?.status == "COMPLETED")
    }

    @Test func theLessonQueueAndTheMessageQueueStaySeparate() async throws {
        let stress = try await MessagingStress.begin(.queueFull)
        let lessonOutbox = ConfigurationOutboxStub()
        let model = lessonWorkspace(IndependenceLessonServer(), lessonOutbox)
        await model.load()
        #expect(await model.start())
        let outcome = await stress.finish()
        // Les deux files sont distinctes : la leçon ne vide pas les messages, les messages ne retiennent pas la leçon.
        #expect(outcome.remaining == 200)
        #expect(lessonOutbox.removals.contains { $0.kind == .startLesson })
        #expect(lessonOutbox.saves.allSatisfy { $0.kind == .startLesson })
    }

    private func lessonWorkspace(_ server: IndependenceLessonServer, _ outbox: ConfigurationOutboxStub) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
    }

    private func liveRecorder(outbox: ConfigurationOutboxStub) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: HubServer())
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, outbox: outbox, permitsAnchor: nil)
    }
}

// MARK: Messagerie dégradée

/// Met la messagerie dans l'état voulu et la fait travailler (une reprise de file) pendant que le test déroule la leçon.
@MainActor private final class MessagingStress {
    struct Outcome {
        var failures: [MessagingFailure]
        var acceptedCount: Int
        var remaining: Int
    }

    private let scope: MessagingScope
    private let outbox: (any MessagingProtectedOutbox)
    private let hung: HungMessagingService?
    private var flush: Task<[MessagingOutboxCoordinator.Delivery], Never>?
    private var flushFinished = false

    private init(scope: MessagingScope, outbox: any MessagingProtectedOutbox, hung: HungMessagingService?) {
        self.scope = scope; self.outbox = outbox; self.hung = hung
    }

    static func begin(_ outage: MessagingOutage) async throws -> MessagingStress {
        let scope = MessagingScope(accountID: UUID(), schoolID: ConfigurationFixture.schoolID, accessEpoch: 1)
        let service: any MessagingService
        var hung: HungMessagingService?
        let outbox: any MessagingProtectedOutbox
        switch outage {
        case .serviceDown:
            service = UnavailableMessagingService()
            outbox = try await filledOutbox(count: 3, scope: scope)
        case .requestHung:
            let hanging = HungMessagingService()
            hung = hanging; service = hanging
            outbox = try await filledOutbox(count: 3, scope: scope)
        case .queueFull:
            service = UnavailableMessagingService()
            outbox = try await filledOutbox(count: 200, scope: scope)
        case .protectedStorageUnavailable:
            service = UnavailableMessagingService()
            outbox = UnavailableMessagingOutbox()
        }
        let stress = MessagingStress(scope: scope, outbox: outbox, hung: hung)
        let coordinator = MessagingOutboxCoordinator(scope: scope, service: service, cryptography: IndependenceCipher(),
            outbox: outbox, currentScope: { scope })
        stress.flush = Task { @MainActor in
            let deliveries = await coordinator.flushPending(currentScope: scope)
            stress.flushFinished = true
            return deliveries
        }
        if let hung { try await HubFixture.wait { await hung.attemptCount() > 0 } }
        return stress
    }

    private static func filledOutbox(count: Int, scope: MessagingScope) async throws -> StressOutbox {
        let outbox = StressOutbox()
        for _ in 0..<count {
            let entry = MessagingPending(clientMessageID: UUID(), conversationID: UUID(),
                ciphertext: MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1, 2, 3])))
            try await outbox.put(entry, scope: scope)
        }
        return outbox
    }

    var flushIsStillRunning: Bool { !flushFinished }
    func hungAttempts() async -> Int { await hung?.attemptCount() ?? 0 }

    /// Laisse la messagerie terminer sa reprise (une requête suspendue est relâchée) puis rend ce qu'elle a observé.
    func finish() async -> Outcome {
        await hung?.release()
        let deliveries = await flush?.value ?? []
        var failures: [MessagingFailure] = [], accepted = 0
        for delivery in deliveries {
            switch delivery {
            case .failed(let failure): failures.append(failure)
            case .accepted: accepted += 1
            case .waiting: break
            }
        }
        let remaining = (try? await outbox.entries(scope: scope).count) ?? -1
        return Outcome(failures: failures, acceptedCount: accepted, remaining: remaining)
    }
}

/// Un envoi suspendu tant qu'on ne le relâche pas, puis qui échoue : une messagerie qui ne répond pas.
private actor HungMessagingService: MessagingService {
    private var attempts = 0
    private var released = false
    private var gate: CheckedContinuation<Void, Never>?

    func attemptCount() -> Int { attempts }
    func release() { released = true; gate?.resume(); gate = nil }

    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement {
        attempts += 1
        if !released {
            await withCheckedContinuation { continuation in gate = continuation }
        }
        throw MessagingFailure.unavailable
    }
}

/// File protégée en mémoire, sans limite : la saturation vient du nombre de messages en attente, pas du stockage.
private actor StressOutbox: MessagingProtectedOutbox {
    private var entriesByID: [UUID: MessagingPending] = [:]
    private var order: [UUID] = []
    func put(_ entry: MessagingPending, scope: MessagingScope) throws {
        if entriesByID[entry.clientMessageID] == nil { order.append(entry.clientMessageID) }
        entriesByID[entry.clientMessageID] = entry
    }
    func entries(scope: MessagingScope) throws -> [MessagingPending] { order.compactMap { entriesByID[$0] } }
    func remove(clientMessageID: UUID, scope: MessagingScope) throws {
        entriesByID.removeValue(forKey: clientMessageID)
        order.removeAll { $0 == clientMessageID }
    }
}

/// Substitut exclusivement synthétique : ne constitue ni chiffrement ni stockage de production.
private struct IndependenceCipher: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        MessagingCiphertext(scheme: "TEST_ONLY", keyID: "fixture", payload: Data([1, 2, 3]), expectedMembersEpoch: 7)
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { Data() }
}

// MARK: Leçon

/// Serveur de leçon minimal : départ, arrêt, relecture et reçu d'opération. Les autres routes passent par la fixture commune.
private actor IndependenceLessonServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private var started = false, completed = false
    private var operation: UUID?, command = "START_LESSON"
    private let preparationID = UUID(uuidString: "70000000-0000-4000-8000-000000000001")!

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!, leaf = url.lastPathComponent.lowercased()
        func ok(_ data: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": "2026-09-28T13:00:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        if request.httpMethod == "POST", ["start", "complete"].contains(leaf) {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            operation = UUID(uuidString: body["operationId"] as! String)
            if leaf == "start" { started = true; command = "START_LESSON" }
            else { completed = true; command = "COMPLETE_LESSON" }
            return try ok([:])
        }
        if leaf == "preparation" {
            return try ok(["id": preparationID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "lessonId": HubFixture.lessonID.uuidString, "version": 1, "goals": [] as [Any],
                "administrativeCheckNote": "", "plannedWaypoints": [] as [Any]])
        }
        if leaf == HubFixture.lessonID.uuidString.lowercased() {
            let lesson = HubFixture.lesson(status: completed ? "COMPLETED" : "PLANNED", permitWarning: false,
                actualStart: started ? "2026-09-28T11:00:00Z" : nil)
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lesson)) as! [String: Any]
            value["version"] = completed ? 4 : started ? 3 : 2
            return try ok(value)
        }
        if let operation, leaf == operation.uuidString.lowercased() {
            return try ok(["operationId": operation.uuidString, "commandType": command, "resourceType": "Lesson",
                "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": completed ? 4 : 3,
                "committedAt": "2026-09-28T11:00:00Z"])
        }
        return try await fallback.send(request)
    }
}
