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
            #expect(SchoolLessonHubRules.mayCancel(lesson, roles: ["INSTRUCTOR"]))
        }
    }

    @Test func aConfirmedEarlyOrLateStartCanFinishAndKeepsItsRealTimes() {
        for instant in ["2026-09-28T10:00:00Z", "2026-09-28T15:00:00Z"] {
            let lesson = HubFixture.lesson(actualStart: instant)
            let now = lesson.startedAt!.addingTimeInterval(120)
            #expect(SchoolLessonHubRules.mayFinish(lesson, now: now))
            #expect(!SchoolLessonHubRules.mayMove(lesson, roles: ["INSTRUCTOR"], now: now))
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
    func setReceiptAvailable(_ value: Bool) { receiptAvailable = value }

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
        if leaf == HubFixture.lessonID.uuidString.lowercased() {
            let lesson = HubFixture.lesson(status: completed ? "COMPLETED" : "PLANNED", permitWarning: false,
                actualStart: started ? "2026-09-28T11:00:00Z" : nil)
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lesson)) as! [String: Any]
            value["version"] = completed ? 4 : started ? 3 : 2
            return try ok(value)
        }
        if let operation, leaf == operation.uuidString.lowercased() {
            guard receiptAvailable else { throw SchoolReportFailure.unavailable }
            return try ok(["operationId": operation.uuidString, "commandType": command, "resourceType": "Lesson",
                "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": completed ? 4 : 3,
                "committedAt": "2026-09-28T11:00:00Z"])
        }
        return try await fallback.send(request)
    }
}
