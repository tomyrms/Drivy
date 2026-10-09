import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLessonLifecycleTests {
    @Test func theClockNeverStartsOrFinishesALesson() {
        let lesson = HubFixture.lesson()
        for now in [lesson.startsAt!, lesson.startsAt!.addingTimeInterval(1800), lesson.endsAt!.addingTimeInterval(86400)] {
            #expect(lesson.drivyState(now: now) == .waiting)
            #expect(lesson.drivyState(now: now).rowNote?.text == "En attente")
            #expect(!SchoolLessonHubRules.mayFinish(lesson, now: now))
            #expect(SchoolLessonHubRules.mayCancel(lesson, roles: ["INSTRUCTOR"], membershipID: lesson.instructorMembershipId))
        }
    }

    @Test func aConfirmedEarlyOrLateStartCanFinishAndKeepsItsRealTimes() {
        for instant in ["2026-09-28T10:00:00Z", "2026-09-28T15:00:00Z"] {
            let lesson = HubFixture.lesson(actualStart: instant)
            let now = lesson.startedAt!.addingTimeInterval(120)
            #expect(SchoolLessonHubRules.mayFinish(lesson, now: now))
            #expect(!SchoolLessonHubRules.mayMove(lesson, roles: ["INSTRUCTOR"], membershipID: lesson.instructorMembershipId, now: now))
            let times = SchoolLessonHubRules.completionTimes(lesson: lesson,
                captures: [HubFixture.capture(authorizedAt: "2026-09-28T12:20:00Z", stoppedAt: "2026-09-28T12:30:00Z", state: .stopped)], now: now)
            #expect(times.start == lesson.startedAt && times.end == now)
        }
    }

    @Test func startingPersistsTheCommandThenRereadsTheSameLessonAndCanFinish() async throws {
        let server = LifecycleServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        #expect(model.lesson?.hasStarted == false)
        #expect(await model.start())
        #expect(model.lesson?.hasStarted == true && model.lesson?.version == 3)
        #expect(!model.mayMarkNoShow())
        let command = try #require(outbox.saves.first)
        #expect(command.kind == .startLesson && command.hasValidTarget && command.resourceID == HubFixture.lessonID)
        #expect(command.resourceVersion == 2 && outbox.removals.contains(command))
        let start = try #require(model.lesson?.startedAt)
        #expect(await model.complete(start: start, end: start.addingTimeInterval(60), reason: "", localCaptureStopped: true))
        #expect(model.lesson?.status == "COMPLETED")
        #expect(outbox.saves.contains { $0.kind == .completeLesson && $0.resourceVersion == 3 })
    }

    @Test func aLostStartAcknowledgementCannotClaimSuccessAndCanBeRecovered() async {
        let server = LifecycleServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        await server.setReceiptAvailable(false)
        #expect(!(await model.start()))
        #expect(model.lesson?.hasStarted == false && model.pending?.kind == .startLesson)
        #expect(outbox.value != nil && !model.canMutate)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        #expect(model.lesson?.hasStarted == true && model.pending == nil && outbox.value == nil)
    }

    @Test func startingSavesObjectivesBeforeStartingTheLesson() async throws {
        let server = LifecycleServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        let goals = [SchoolLessonGoal(label: "Contrôler les angles morts")]
        model.goals = goals; model.administrativeNote = "Revoir le départ."
        #expect(await model.start())
        #expect(model.lesson?.hasStarted == true && !model.preparationChanged)
        #expect(model.preparation?.goals == goals && model.preparation?.administrativeCheckNote == "Revoir le départ.")
        #expect(outbox.removals.map(\.kind) == [.savePreparation, .startLesson])
        let body = try #require(outbox.saves.first?.body)
        let saved = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((saved["goals"] as? [[String: Any]])?.first?["label"] as? String == goals.first?.label)
        #expect(saved["administrativeCheckNote"] as? String == "Revoir le départ.")
    }

    @Test func failedObjectivesSavePreventsStartingAndKeepsTheDraft() async {
        let server = LifecycleServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        let goals = [SchoolLessonGoal(label: "Contrôler les angles morts")]
        model.goals = goals
        await server.setPreparationRejected(true)
        #expect(!(await model.start()))
        #expect(model.lesson?.hasStarted == false && model.goals == goals && model.preparationChanged)
        #expect(model.errorMessage != nil)
        #expect(!outbox.saves.isEmpty && outbox.saves.allSatisfy { $0.kind == .savePreparation })
    }

    @Test func invalidObjectivesCannotBeDiscardedByStarting() async {
        let outbox = ConfigurationOutboxStub()
        let model = workspace(LifecycleServer(), outbox)
        await model.load()
        model.goals = [SchoolLessonGoal(label: "")]
        #expect(!(await model.start()))
        #expect(model.lesson?.hasStarted == false && model.goals.count == 1 && model.preparationChanged)
        #expect(model.errorMessage != nil && outbox.saves.isEmpty)
    }

    @Test func laterGPSDepartureAlsoWaitsForSavedObjectives() async {
        let server = LifecycleServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox)
        await model.load()
        #expect(await model.start())
        let goals = [SchoolLessonGoal(label: "Priorités à droite")]
        model.goals = goals
        await server.setPreparationRejected(true)
        #expect(!(await model.savePreparationBeforeDeparture()))
        #expect(model.goals == goals && model.preparationChanged)
        await server.setPreparationRejected(false)
        #expect(await model.savePreparationBeforeDeparture())
        #expect(model.preparation?.goals == goals && !model.preparationChanged)
        #expect(Set(outbox.saves.filter { $0.kind == .startLesson }.map(\.id)).count == 1)
    }

    @Test func anUnstartedLessonCannotSendCompletion() async {
        let outbox = ConfigurationOutboxStub()
        let model = workspace(LifecycleServer(), outbox)
        await model.load()
        #expect(!(await model.complete(start: Date().addingTimeInterval(-3600), end: Date(), reason: "", localCaptureStopped: true)))
        #expect(outbox.saves.isEmpty && model.lesson?.hasStarted == false)
    }

    private func workspace(_ server: LifecycleServer, _ outbox: ConfigurationOutboxStub) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
    }
}

private actor LifecycleServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private var started = false, completed = false, receiptAvailable = true
    private var operation: UUID?, command = "START_LESSON"
    private let preparationID = UUID(uuidString: "70000000-0000-4000-8000-000000000001")!
    private var preparationGoals: [[String: Any]] = [], preparationNote = "", preparationVersion = 1
    private var preparationRejected = false
    func setReceiptAvailable(_ value: Bool) { receiptAvailable = value }
    func setPreparationRejected(_ value: Bool) { preparationRejected = value }

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
            if request.httpMethod == "PUT" {
                if preparationRejected {
                    return SchoolHTTPResponse(data: Data("{\"code\":\"INVALID_REQUEST\",\"title\":\"Objectifs refusés\"}".utf8),
                        status: 422, url: url, contentType: "application/problem+json")
                }
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                operation = UUID(uuidString: body["operationId"] as! String); command = "SAVE_PREPARATION"
                preparationGoals = body["goals"] as! [[String: Any]]
                preparationNote = body["administrativeCheckNote"] as? String ?? ""
                preparationVersion += 1
            }
            return try ok(["id": preparationID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "lessonId": HubFixture.lessonID.uuidString, "version": preparationVersion, "goals": preparationGoals,
                "administrativeCheckNote": preparationNote, "plannedWaypoints": [] as [Any]])
        }
        if leaf == HubFixture.lessonID.uuidString.lowercased() {
            let lesson = HubFixture.lesson(status: completed ? "COMPLETED" : "PLANNED", permitWarning: false,
                actualStart: started ? "2026-09-28T11:00:00Z" : nil)
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lesson)) as! [String: Any]
            value["version"] = completed ? 4 : started ? 3 : 2
            return try ok(value)
        }
        if let operation, leaf == operation.uuidString.lowercased() {
            guard receiptAvailable else { throw SchoolReportFailure.unavailable }
            let preparation = command == "SAVE_PREPARATION"
            return try ok(["operationId": operation.uuidString, "commandType": command, "resourceType": preparation ? "Preparation" : "Lesson",
                "resourceId": (preparation ? preparationID : HubFixture.lessonID).uuidString, "resourceVersion": preparation ? preparationVersion : completed ? 4 : 3,
                "committedAt": "2026-09-28T11:00:00Z"])
        }
        return try await fallback.send(request)
    }
}
