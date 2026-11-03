import Foundation
import Testing
@testable import Drivy

/// #114 : le constat de fin et celui d'absence ne retiennent plus la fiche une fois la demande conservée dans la file
/// chiffrée. Rien n'est confirmé (leçon terminée, absence) avant la réponse de l'école, et une demande restée sans
/// preuve se retrouve à vérifier. Personnes, leçon et réponses sont synthétiques ; aucune position n'intervient.
@MainActor struct SchoolLessonClosureReactivityTests {
    @Test func aCompletionBeingSentLeavesTheSheetFreeButConfirmsNothing() async throws {
        let server = ClosureServer(started: true), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        let start = try #require(model.lesson?.startedAt)
        await server.hold()
        let closing = Task { await model.complete(start: start, end: start.addingTimeInterval(60), reason: "", localCaptureStopped: true) }
        try await HubFixture.wait { await server.isHolding() }
        // La demande est déjà dans la file chiffrée ; l'école n'a pas répondu : la leçon n'est pas terminée.
        #expect(model.isSendingClosure && !model.holdsScreen)
        #expect(outbox.value?.kind == .completeLesson)
        #expect(model.lesson?.status == "PLANNED" && !model.canMutate && !model.acceptsInput)
        await server.release()
        #expect(await closing.value)
        #expect(model.lesson?.status == "COMPLETED" && outbox.value == nil && !model.isSendingClosure)
    }

    @Test func nothingCanBeLeftBeforeAClosureIsBeingSent() async {
        let server = ClosureServer(started: true), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        #expect(!model.isSendingClosure && !model.leaveWhileClosureIsSent() && !model.isInvalidated)
    }

    @Test func leavingWhileTheSchoolAnswersKeepsTheRequestThenAnnouncesItsConfirmation() async throws {
        let server = ClosureServer(started: true), outbox = ConfigurationOutboxStub()
        let notifications = NotificationCenter(), changes = ClosureChangeLog()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) {
            changes.append($0.object as? SchoolLessonChange)
        }
        defer { notifications.removeObserver(observer) }
        let model = workspace(server, outbox, notifications: notifications)
        await model.load()
        let start = try #require(model.lesson?.startedAt)
        await server.hold()
        let closing = Task { await model.complete(start: start, end: start.addingTimeInterval(60), reason: "", localCaptureStopped: true) }
        try await HubFixture.wait { await server.isHolding() }
        #expect(model.leaveWhileClosureIsSent() && model.isInvalidated)
        // Fiche quittée : rien n'est annoncé tant que l'école n'a pas répondu, et la demande reste en file.
        #expect(changes.count == 0 && outbox.value?.kind == .completeLesson)
        await server.release()
        // La fiche fermée ne reçoit pas le résultat…
        #expect(!(await closing.value))
        #expect(model.lesson?.status == "PLANNED")
        // …mais l'école l'a confirmé : la demande quitte la file, une seule annonce part, une seule fin a été envoyée.
        #expect(outbox.value == nil && outbox.removals.count == 1)
        let change = try #require(changes.values.first)
        #expect(changes.count == 1 && change.kind == .completeLesson && change.lessonID == HubFixture.lessonID)
        #expect(change.schoolID == HubFixture.schoolID && change.trainingID == HubFixture.trainingID)
        let posts = await server.closurePosts()
        #expect(posts == 1)
    }

    @Test func aFinishWithoutProofStaysRecoverableAfterTheSheetWasLeft() async throws {
        let server = ClosureServer(started: true), outbox = ConfigurationOutboxStub()
        let notifications = NotificationCenter(), changes = ClosureChangeLog()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) {
            changes.append($0.object as? SchoolLessonChange)
        }
        defer { notifications.removeObserver(observer) }
        let model = workspace(server, outbox, notifications: notifications)
        await model.load()
        let start = try #require(model.lesson?.startedAt)
        await server.hold(); await server.setReceiptAvailable(false)
        let closing = Task { await model.complete(start: start, end: start.addingTimeInterval(60), reason: "", localCaptureStopped: true) }
        try await HubFixture.wait { await server.isHolding() }
        #expect(model.leaveWhileClosureIsSent())
        await server.release()
        #expect(!(await closing.value))
        // L'école a reçu la demande mais la preuve manque : rien n'est confirmé ni annoncé, la demande reste en file.
        let kept = try #require(outbox.value)
        #expect(kept.kind == .completeLesson && changes.count == 0)
        // Fiche rouverte : la demande est retrouvée à vérifier, puis confirmée sans aucun nouvel envoi.
        let reopened = workspace(server, outbox, notifications: notifications)
        await reopened.load()
        #expect(reopened.pending == kept && reopened.pendingAwaitsReview && !reopened.canMutate)
        await server.setReceiptAvailable(true)
        await reopened.verifyPending()
        #expect(reopened.pending == nil && outbox.value == nil && reopened.lesson?.status == "COMPLETED")
        let posts = await server.closurePosts()
        #expect(posts == 1)
        #expect(changes.values.contains { $0.kind == .completeLesson })
    }

    @Test func anAbsenceBeingSentDoesNotHoldTheSheetEither() async throws {
        let server = ClosureServer(started: false), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        #expect(model.mayMarkNoShow())
        await server.hold()
        let marking = Task { await model.markNoShow(reason: "Élève absent au rendez-vous.") }
        try await HubFixture.wait { await server.isHolding() }
        // Le constat est dans la file ; la leçon n'est pas encore « absence ».
        #expect(model.isSendingClosure && !model.holdsScreen && model.lesson?.status == "PLANNED")
        #expect(outbox.value?.kind == .markNoShow)
        #expect(model.leaveWhileClosureIsSent())
        await server.release()
        #expect(!(await marking.value))
        #expect(outbox.value == nil)
        let posts = await server.closurePosts()
        #expect(posts == 1)
    }

    @Test func aSharingChangeOrAReportSendIsNeverTakenForAClosure() async throws {
        let server = LessonFinishServer(sharing: true), outbox = ConfigurationOutboxStub()
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let model = SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership,
            lessonID: HubFixture.lessonID, client: client, outbox: outbox)
        await model.load()
        await server.holdSharing()
        let sharing = Task { await model.updateSharing(reportPrivate: true) }
        try await HubFixture.wait { await server.isHoldingSharing() }
        #expect(model.isBusy && !model.isSendingClosure && !model.leaveWhileClosureIsSent())
        await server.releaseSharing()
        await sharing.value
    }

    private func workspace(_ server: ClosureServer, _ outbox: ConfigurationOutboxStub,
                           notifications: NotificationCenter = .default) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox, notifications: notifications)
    }
}

private final class ClosureChangeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SchoolLessonChange] = []
    private var broadcasts = 0
    func append(_ value: SchoolLessonChange?) {
        lock.lock(); defer { lock.unlock() }; broadcasts += 1
        if let value { stored.append(value) }
    }
    var values: [SchoolLessonChange] { lock.lock(); defer { lock.unlock() }; return stored }
    var count: Int { lock.lock(); defer { lock.unlock() }; return broadcasts }
}

/// Leçon planifiée (commencée ou non) dont la fin, ou l'absence, peut être retenue côté école puis relâchée.
private actor ClosureServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private let started: Bool
    private var closed: String?
    private var receiptAvailable = true
    private var operation: UUID?
    private var command = "COMPLETE_LESSON"
    private var held = false, holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var posts = 0

    init(started: Bool) { self.started = started }
    func setReceiptAvailable(_ value: Bool) { receiptAvailable = value }
    func hold() { held = true }
    func release() { held = false; let values = waiters; waiters = []; for item in values { item.resume() } }
    func isHolding() -> Bool { holding }
    func closurePosts() -> Int { posts }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!, leaf = url.lastPathComponent.lowercased()
        func ok(_ data: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": "2026-09-28T13:00:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        if request.httpMethod == "POST", ["complete", "no-show"].contains(leaf) {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            operation = UUID(uuidString: body["operationId"] as! String)
            command = leaf == "complete" ? "COMPLETE_LESSON" : "MARK_NO_SHOW"
            posts += 1
            if held {
                holding = true
                await withCheckedContinuation { waiters.append($0) }
                holding = false
            }
            closed = leaf == "complete" ? "COMPLETED" : "NO_SHOW"
            return try ok([:])
        }
        if leaf == HubFixture.lessonID.uuidString.lowercased() {
            let lesson = HubFixture.lesson(status: closed ?? "PLANNED", permitWarning: false,
                actualStart: started ? "2026-09-28T11:00:00Z" : nil)
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lesson)) as! [String: Any]
            value["version"] = (started ? 3 : 2) + (closed == nil ? 0 : 1)
            return try ok(value)
        }
        if let operation, leaf == operation.uuidString.lowercased() {
            guard receiptAvailable else { throw SchoolReportFailure.unavailable }
            return try ok(["operationId": operation.uuidString, "commandType": command, "resourceType": "Lesson",
                "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": (started ? 3 : 2) + 1,
                "committedAt": "2026-09-28T11:00:00Z"])
        }
        return try await fallback.send(request)
    }
}
