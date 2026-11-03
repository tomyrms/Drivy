import Foundation
import Testing
@testable import Drivy

/// #109 : une création ou un déplacement déjà écrit dans le coffre chiffré ne retient plus la feuille pendant l’envoi.
/// Rien n’est confirmé avant la preuve de l’école, une annulation reste verrouillée (la capture en direct en dépend),
/// et une réponse perdue laisse la demande au coffre, retrouvée par son repère. Personnes, école, leçon et réponses
/// sont synthétiques ; aucune position n’intervient et aucune requête ne sort de ce transport.
@MainActor struct SchoolPlanningLeaveWhileSendingTests {
    @Test func aCreationBeingSentLeavesTheSheetFreeButConfirmsNothing() async throws {
        let server = PlanningLeaveServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load(); await model.selectLearner(HubFixture.learnerID); await model.validateSlot()
        try #require(model.validBooking)

        await server.hold()
        let booking = Task { await model.saveBooking() }
        try await HubFixture.wait { await server.isHolding() }

        // La demande est écrite dans le coffre, l’école n’a pas répondu : la feuille se libère, rien n’est confirmé.
        #expect(model.isSendingRequest && !model.holdsScreen && !model.writeConfirmed && model.confirmedLesson == nil)
        #expect(model.successMessage == nil && outbox.value?.kind == .createLesson && !model.canMutate)
        #expect(model.pending?.kind.inProgressTitle == "Planification en cours")
        #expect(model.leaveWhileRequestIsSent() && model.invalidated)
        #expect(model.pending != nil && model.successMessage == nil)

        await server.release()
        // Feuille fermée : elle ne reçoit pas le résultat, mais la demande a bien quitté le coffre, une seule fois.
        #expect(await booking.value == false)
        #expect(outbox.value == nil && outbox.removals.count == 1)
        #expect(model.confirmedLesson == nil && !model.writeConfirmed && model.successMessage == nil)
        #expect(await server.posts() == 1)
    }

    @Test func aMoveBeingSentLeavesTheSheetFreeToo() async throws {
        let server = PlanningLeaveServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox, lesson: HubFixture.lesson())
        await model.load()
        model.startsAt = Date().addingTimeInterval(86_400)
        model.agreementConfirmed = true
        await model.validateSlot()
        try #require(model.validBooking)

        await server.hold()
        let moving = Task { await model.saveBooking() }
        try await HubFixture.wait { await server.isHolding() }

        #expect(model.isSendingRequest && !model.holdsScreen && !model.writeConfirmed && model.confirmedLesson == nil)
        #expect(outbox.value?.kind == .moveLesson && model.pending?.kind.inProgressTitle == "Déplacement en cours")
        #expect(model.leaveWhileRequestIsSent() && model.invalidated)

        await server.release()
        #expect(await moving.value == false)
        #expect(outbox.value == nil && outbox.removals.count == 1)
        #expect(model.confirmedLesson == nil && !model.writeConfirmed)
        #expect(await server.posts() == 1)
    }

    @Test func aCancellationBeingSentKeepsTheSheetLocked() async throws {
        let server = PlanningLeaveServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox, lesson: HubFixture.lesson())
        model.readsForCancellation = true
        await model.load()
        model.cancellationReason = "OTHER"
        try #require(model.canMutate)

        await server.hold()
        let cancelling = Task { await model.cancel() }
        try await HubFixture.wait { await server.isHolding() }

        // La capture en direct ferme le trajet sur la preuve d’une annulation : la feuille reste verrouillée.
        #expect(model.isBusy && model.holdsScreen && !model.isSendingRequest)
        #expect(!model.leaveWhileRequestIsSent() && !model.invalidated)

        await server.release()
        #expect(await cancelling.value)
        #expect(!model.invalidated && model.confirmedCancellationLessonID == HubFixture.lessonID)
        let posts = await server.posts()
        #expect(model.writeConfirmed && outbox.value == nil && posts == 1)
    }

    @Test func nothingCanBeLeftBeforeARequestIsBeingSent() async {
        let model = workspace(PlanningLeaveServer(), outbox: ConfigurationOutboxStub())
        await model.load()
        // Ouvrir, lire, vérifier un créneau : aucun envoi, donc rien à quitter « pendant l’envoi ».
        #expect(!model.isSendingRequest && !model.holdsScreen && !model.draftChangedSinceSend)
        #expect(!model.leaveWhileRequestIsSent() && !model.invalidated)
    }

    @Test func leavingWhileTheSchoolAnswersPublishesTheConfirmationOnce() async throws {
        let server = PlanningLeaveServer(), outbox = ConfigurationOutboxStub()
        let notifications = NotificationCenter(), log = PlanningLeaveNotificationLog()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) { _ in
            log.increment()
        }
        defer { notifications.removeObserver(observer) }
        let model = workspace(server, outbox: outbox, notifications: notifications)
        await model.load(); await model.selectLearner(HubFixture.learnerID); await model.validateSlot()
        try #require(model.validBooking)

        await server.hold()
        let booking = Task { await model.saveBooking() }
        try await HubFixture.wait { await server.isHolding() }
        #expect(model.leaveWhileRequestIsSent())
        // Feuille quittée : rien n’est annoncé tant que l’école n’a pas répondu, et la demande reste conservée.
        #expect(log.value == 0 && outbox.value?.kind == .createLesson)

        await server.release()
        #expect(await booking.value == false)
        // L’école a confirmé : une seule annonce, une seule sortie du coffre, aucun envoi supplémentaire.
        #expect(log.value == 1 && outbox.value == nil && outbox.removals.count == 1)
        let posts = await server.posts()
        #expect(posts == 1)
        // La feuille fermée n’affiche aucune confirmation : rien n’est réécrit dans un écran qui n’existe plus.
        #expect(model.confirmedLesson == nil && !model.writeConfirmed && model.successMessage == nil)
    }

    @Test func aLostProofAfterLeavingKeepsTheRequestWithoutASecondPost() async throws {
        let server = PlanningLeaveServer(receiptAvailable: false), outbox = ConfigurationOutboxStub()
        let notifications = NotificationCenter(), log = PlanningLeaveNotificationLog()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) { _ in
            log.increment()
        }
        defer { notifications.removeObserver(observer) }
        let model = workspace(server, outbox: outbox, notifications: notifications)
        await model.load(); await model.selectLearner(HubFixture.learnerID); await model.validateSlot()
        try #require(model.validBooking)

        await server.hold()
        let booking = Task { await model.saveBooking() }
        try await HubFixture.wait { await server.isHolding() }
        #expect(model.leaveWhileRequestIsSent())
        await server.release()
        #expect(await booking.value == false)

        // Sans preuve, rien n’est confirmé ni supprimé : la demande reste dans le coffre, et rien n’est annoncé.
        let kept = try #require(outbox.value)
        #expect(kept.kind == .createLesson && outbox.removals.isEmpty && log.value == 0)
        #expect(await server.posts() == 1)

        // Hors de la feuille, le repère de l’agenda la retrouve et ne renvoie jamais rien de lui-même.
        let markers = SchoolPendingPlanningProjection.markers(from: [kept], scope: ConfigurationFixture.scope(),
            now: Date().addingTimeInterval(SchoolPendingPlanningProjection.inFlightWindow + 60))
        let marker = try #require(markers.first)
        #expect(markers.count == 1 && marker.id == kept.id && marker.state == .toVerify && marker.title == "À vérifier")

        // Feuille rouverte : la demande est retrouvée telle quelle, et la lecture seule n’ajoute aucun envoi.
        let reopened = workspace(server, outbox: outbox, notifications: notifications)
        await reopened.load()
        #expect(reopened.pending == kept && !reopened.canMutate)
        #expect(await server.posts() == 1)
    }

    @Test func aDraftChangedDuringTheSendIsNeverAbandonedByLeaving() async throws {
        let server = PlanningLeaveServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load(); await model.selectLearner(HubFixture.learnerID); await model.validateSlot()
        try #require(model.validBooking)

        await server.hold()
        let booking = Task { await model.saveBooking() }
        try await HubFixture.wait { await server.isHolding() }
        #expect(!model.draftChangedSinceSend)

        // Saisie retouchée après le départ de l’envoi (une proposition d’horaire, par exemple) : elle n’est pas jetée.
        model.meetingPoint = "Parking nord"
        #expect(model.draftChangedSinceSend)
        #expect(!model.leaveWhileRequestIsSent() && !model.invalidated && model.isSendingRequest)

        await server.release()
        // La feuille est restée : elle reçoit la confirmation et la saisie non envoyée reste à l’écran.
        #expect(await booking.value)
        #expect(model.writeConfirmed && model.confirmedLesson?.id == HubFixture.lessonID)
        #expect(model.meetingPoint == "Parking nord" && !model.invalidated)
        let posts = await server.posts()
        #expect(outbox.value == nil && posts == 1)
    }

    private func workspace(_ server: PlanningLeaveServer, outbox: ConfigurationOutboxStub, lesson: SchoolLesson? = nil,
                           notifications: NotificationCenter = .default) -> SchoolPlanningWorkspace {
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        return SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client,
            date: Date().addingTimeInterval(86_400), lesson: lesson, outbox: outbox, notifications: notifications)
    }
}

private final class PlanningLeaveNotificationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Transport synthétique : les lectures sont celles des fixtures de planification, l’écriture peut être retenue par
/// l’école et le reçu AP72 peut manquer. Aucune transaction PostgreSQL n’est prétendue ici.
private actor PlanningLeaveServer: SchoolHTTPTransport {
    private let fallback = PlanningDefaultsServer()
    private var receiptAvailable: Bool
    private var operationID: String?
    private var operationType = "CREATE_LESSON"
    private var commandVersion = 0
    private var lessonVersion = 2
    private var lessonStatus = "PLANNED"
    private var held = false, holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var postCount = 0

    init(receiptAvailable: Bool = true) { self.receiptAvailable = receiptAvailable }
    /// L’école a reçu la demande et n’a pas encore répondu : l’appareil attend.
    func hold() { held = true }
    func release() { held = false; let values = waiters; waiters = []; for item in values { item.resume() } }
    func isHolding() -> Bool { holding }
    func posts() -> Int { postCount }

    private func lesson() throws -> [String: Any] {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson(status: lessonStatus))) as! [String: Any]
        value["version"] = lessonVersion
        return value
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        let leaf = url.lastPathComponent.lowercased()
        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
        func ok(_ value: Any, status: Int = 200) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": ISO8601DateFormatter().string(from: Date())]), status: status, url: url, contentType: "application/json")
        }
        if request.httpMethod == "POST", ["lessons", "move", "cancel"].contains(leaf) {
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            operationID = body?["operationId"] as? String
            operationType = leaf == "cancel" ? "CANCEL_LESSON" : leaf == "move" ? "MOVE_LESSON" : "CREATE_LESSON"
            commandVersion = Int((request.value(forHTTPHeaderField: "If-Match") ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0
            lessonVersion = max(lessonVersion, commandVersion + 1)
            if leaf == "cancel" { lessonStatus = "CANCELLED" }
            postCount += 1
            if held {
                holding = true
                await withCheckedContinuation { waiters.append($0) }
                holding = false
            }
            return try ok([:], status: leaf == "lessons" ? 201 : 200)
        }
        if request.httpMethod == "GET", parent == "lessons", leaf == HubFixture.lessonID.uuidString.lowercased() {
            return try ok(lesson())
        }
        if parent == "operations", let operationID {
            guard receiptAvailable else { throw URLError(.notConnectedToInternet) }
            return try ok(["operationId": operationID, "commandType": operationType, "resourceType": "Lesson",
                "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": commandVersion + 1,
                "committedAt": ISO8601DateFormatter().string(from: Date())])
        }
        return try await fallback.send(request)
    }
}
