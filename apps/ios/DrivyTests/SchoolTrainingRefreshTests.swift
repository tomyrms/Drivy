import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolTrainingRefreshTests {
    @Test func periodsUseTheLessonCalendarAcrossTheNewYear() throws {
        let lesson = try HistoryServer.lesson(id: HubFixture.lessonID, start: "2025-12-31T23:30:00Z", end: "2026-01-01T00:20:00Z")
        #expect(SchoolLessonPeriod(month: 1, year: 2026).includes(lesson))
        #expect(SchoolLessonPeriod(month: 1).includes(lesson))
        #expect(SchoolLessonPeriod(year: 2026).includes(lesson))
        #expect(!SchoolLessonPeriod(month: 12).includes(lesson))
        #expect(!SchoolLessonPeriod(year: 2025).includes(lesson))
        #expect(SchoolLessonPeriod().includes(lesson))
    }

    @Test func periodHistoryIncludesOlderPagesAndRemainsCompleteAfterRefresh() async throws {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        #expect(model.lessons.count == 1 && model.nextCursor != nil)
        await model.loadHistory()
        #expect(model.lessons.count == 2 && model.nextCursor == nil && !model.isLoadingHistory)
        #expect(model.lessons.filter { SchoolLessonPeriod(month: 1, year: 2026).includes($0) }.count == 1)
        await model.refreshOnAppear()
        #expect(model.lessons.count == 2 && model.nextCursor == nil)
    }

    @Test func failedHistoryKeepsItsRowsAndCursorUntilRetry() async {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        await server.setPageUnavailable(true)
        await model.loadHistory()
        #expect(model.lessons.count == 1 && model.nextCursor == "older" && model.errorMessage != nil)
        #expect(!model.isLoadingHistory && !model.isLoadingMore)
        await server.setPageUnavailable(false)
        await model.loadHistory()
        #expect(model.lessons.count == 2 && model.nextCursor == nil && model.errorMessage == nil)
    }

    @Test func publishedCompetencyWithNoContextRemainsReadable() async throws {
        let client = client(HistoryServer())
        let revision = try await client.revision(schoolID: HubFixture.schoolID, id: HistoryServer.revisionID)
        #expect(revision.observations.count == 1 && revision.observations.first?.context == "")
    }

    @Test func refreshDuringAnOlderPageRestartsTheCompleteHistory() async {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        await server.pauseNextPage()
        let previous = Task { await model.loadHistory() }
        await server.waitUntilPaused()
        await model.refreshOnAppear()
        #expect(model.lessons.count == 2 && model.nextCursor == nil && !model.isLoadingHistory)
        await server.resumePage()
        await previous.value
        #expect(model.lessons.count == 2 && model.errorMessage == nil)
    }

    @Test func lessonChangeIsBroadcastOnlyAfterDurableConfirmation() async throws {
        let server = LessonFinishServer(), notifications = NotificationCenter(), changes = RecordedLessonChanges()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) {
            changes.append($0.object as? SchoolLessonChange)
        }
        defer { notifications.removeObserver(observer) }
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let model = SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership,
            lessonID: HubFixture.lessonID, client: client, outbox: ConfigurationOutboxStub(), notifications: notifications)
        await model.load()
        await server.setReceiptAvailable(false)
        model.setObservationLevel("GUIDED", for: LessonFinishServer.progressCompetency)
        #expect(!(await model.saveDraft()))
        #expect(changes.values.isEmpty && !model.reportSaveConfirmed)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        let change = try #require(changes.values.first)
        #expect(changes.values.count == 1 && model.reportSaveConfirmed)
        #expect(change.schoolID == HubFixture.schoolID && change.trainingID == HubFixture.trainingID && change.lessonID == HubFixture.lessonID)
    }

    @Test func receiptOfAnotherLessonNeverBroadcastsTheOpenLessonAsItsTarget() async throws {
        let server = LessonFinishServer(), notifications = NotificationCenter(), changes = RecordedLessonChanges()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) {
            changes.append($0.object as? SchoolLessonChange)
        }
        defer { notifications.removeObserver(observer) }
        let operation = UUID(), resource = UUID(), outbox = ConfigurationOutboxStub()
        let body = SchoolSaveReport(operationId: operation, workedOn: "", observationText: "", nextStep: "", observations: [])
        try outbox.save(PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .saveReportDraft,
            resourceVersion: 1, createdAt: Date(), body: try JSONEncoder().encode(body), resourceID: resource))
        await server.setConfirmedOperation(operation, resourceID: resource)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let model = SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership,
            lessonID: HubFixture.lessonID, client: client, outbox: outbox, notifications: notifications)
        await model.load()
        await model.verifyPending()
        #expect(changes.count == 1 && changes.values.isEmpty)
        #expect(!model.reportSaveConfirmed && model.pending == nil)
    }

    private var membership: SchoolMembership {
        SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
    }
    private func client(_ server: HistoryServer) -> SchoolTrainingClient {
        SchoolTrainingClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }
    private func workspace(_ server: HistoryServer) -> SchoolTrainingWorkspace {
        SchoolTrainingWorkspace(scope: ConfigurationFixture.scope(), membership: membership, learnerID: HubFixture.learnerID,
            trainingID: HubFixture.trainingID, client: client(server))
    }
}

private final class RecordedLessonChanges: @unchecked Sendable {
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

private actor HistoryServer: SchoolHTTPTransport {
    static let revisionID = UUID(uuidString: "70000000-0000-4000-8000-000000000080")!
    private let fallback = LessonFinishServer()
    private var pageUnavailable = false
    private var shouldPause = false
    private var suspended: CheckedContinuation<Void, Never>?
    private var pauseWaiter: CheckedContinuation<Void, Never>?
    func setPageUnavailable(_ value: Bool) { pageUnavailable = value }
    func pauseNextPage() { shouldPause = true }
    func waitUntilPaused() async {
        if suspended != nil { return }
        await withCheckedContinuation { pauseWaiter = $0 }
    }
    func resumePage() { suspended?.resume(); suspended = nil }

    static func lesson(id: UUID, start: String, end: String) throws -> SchoolLesson {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson())) as! [String: Any]
        value["id"] = id.uuidString; value["plannedStart"] = start; value["plannedEnd"] = end
        return try JSONDecoder().decode(SchoolLesson.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func ok(_ data: [String: Any]) throws -> SchoolHTTPResponse {
            let value: [String: Any] = ["data": data, "requestId": UUID().uuidString, "serverTime": "2026-09-30T10:00:00Z"]
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: value), status: 200, url: url, contentType: "application/json")
        }
        if url.pathComponents.dropLast().last?.lowercased() == "report-revisions" {
            return try ok(["id": Self.revisionID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "lessonId": HubFixture.lessonID.uuidString, "authorMembershipId": ConfigurationFixture.membershipID.uuidString,
                "version": 1, "sequence": 1, "publishedAt": "2026-09-28T13:00:00Z", "workedOn": "", "observationText": "", "nextStep": "",
                "observations": [["competencyId": LessonFinishServer.progressCompetency.uuidString, "level": "GUIDED", "context": ""]],
                "attachmentIds": [], "correctionReason": NSNull(), "capturePublication": NSNull(), "textObservations": []])
        }
        if url.lastPathComponent == "lessons" {
            let older = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "cursor" } == true
            if older && shouldPause {
                shouldPause = false
                await withCheckedContinuation { suspended = $0; pauseWaiter?.resume(); pauseWaiter = nil }
            }
            if older && pageUnavailable {
                return SchoolHTTPResponse(data: Data("{}".utf8), status: 503, url: url, contentType: "application/problem+json")
            }
            let lesson = older ? try Self.lesson(id: UUID(uuidString: "50000000-0000-4000-8000-000000000002")!,
                start: "2025-12-31T23:30:00Z", end: "2026-01-01T00:20:00Z") : HubFixture.lesson()
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lesson))
            return try ok(["items": [value], "nextCursor": older ? NSNull() : "older" as Any])
        }
        return try await fallback.send(request)
    }
}
