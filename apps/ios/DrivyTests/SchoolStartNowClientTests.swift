import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolStartNowClientTests {
    @Test func replayedStartStillReturnsItsOriginalLessonAfterMoreThanAnHour() async throws {
        let server = HubServer(); await server.enableStartNow()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let command = try command()
        let lesson = try await client.startNow(command)
        #expect(lesson.id == HubFixture.lessonID)
        let sent = await server.requests()
        #expect(sent.filter { $0.httpMethod == "POST" }.count == 1)
        #expect(sent.first?.url?.path == "/v1/me")
    }

    @Test func differentAccountCannotStartThePendingLesson() async throws {
        let server = HubServer(); await server.enableStartNow(); await server.setPersonID(UUID())
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let command = try command()
        await #expect(throws: SchoolPlanningFailure.forbidden) { try await client.startNow(command) }
        #expect(await server.requests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func planningConflictIsExplainedForAnImmediateLessonAndNothingIsForced() async throws {
        let server = HubServer(); await server.enableStartNowConflict()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let command = try command()
        await #expect(throws: SchoolPlanningFailure.rejected(SchoolPlanningClient.startNowConflictMessage)) { try await client.startNow(command) }
        #expect(await server.requests().filter { $0.httpMethod == "POST" }.count == 1)
        // La planification classique garde son texte : le créneau choisi est en cause, pas une leçon immédiate.
        #expect(SchoolPlanningClient.failure(409, "SLOT_CONFLICT") == .rejected(SchoolPlanningClient.slotConflictMessage))
    }

    @Test func conflictOffersPlanningInsteadOfRetrying() async throws {
        let server = LessonFinishServer(); await server.enableStartNowConflict()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client, outbox: ConfigurationOutboxStub())
        await model.load()
        _ = await model.start()
        #expect(model.conflicted && model.started == nil && model.pending == nil && !model.unsupported)
        #expect(model.errorMessage == SchoolPlanningClient.startNowConflictMessage)
        model.planLater()
        #expect(model.planInstead)
    }

    @Test func learnerFromTheirFileIsChosenWithoutTheList() async throws {
        let server = LessonFinishServer()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client,
            learnerID: HubFixture.learnerID, outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(model.hasPresetLearner && model.learnerName == "Élève de test" && model.canStart)
        // Un élève qui n’est pas affecté au moniteur n’est jamais présélectionné.
        let stranger = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client,
            learnerID: UUID(), outbox: ConfigurationOutboxStub())
        await stranger.load()
        #expect(!stranger.hasPresetLearner && stranger.learnerID == nil && !stranger.canStart)
        #expect(stranger.errorMessage != nil)
    }

    @Test func reloadPreservesTheSelectedTrainingAndTypedMeetingPoint() async throws {
        let server = LessonFinishServer()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client, outbox: ConfigurationOutboxStub())
        await model.load()
        let trainingID = try #require(model.trainingID)
        model.meetingPoint = "Rendez-vous saisi"
        await model.load()
        #expect(model.canStart && model.trainingID == trainingID)
        #expect(model.meetingPoint == "Rendez-vous saisi")
    }

    @Test func failedReloadKeepsTheFormButRequiresFreshContextBeforeStarting() async throws {
        let server = StartNowAssignmentReloadServer(), outbox = ConfigurationOutboxStub()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client, outbox: outbox)
        await model.load()
        try #require(model.canStart)
        model.meetingPoint = "Rendez-vous saisi"
        await server.setUnavailable(true)
        await model.load()
        #expect(model.learnerID == HubFixture.learnerID && model.meetingPoint == "Rendez-vous saisi")
        #expect(!model.canStart && model.errorMessage != nil && outbox.saves.isEmpty)
        await server.setUnavailable(false)
        await model.load()
        #expect(model.canStart && model.meetingPoint == "Rendez-vous saisi")
    }

    @Test func todayTimeContextDoesNotClaimTheLessonHasBeenStarted() {
        let lesson = HubFixture.lesson()
        let start = lesson.startsAt!
        #expect(SchoolTodayPresentation.moment(for: lesson, now: start.addingTimeInterval(-12 * 60)) == "Dans 12 min")
        #expect(SchoolTodayPresentation.moment(for: lesson, now: start.addingTimeInterval(-75 * 60)) == "Dans 1 h 15 min")
        #expect(SchoolTodayPresentation.moment(for: lesson, now: start) == "Horaire commencé")
    }

    @Test func optionalImmediatePlaceUsesTheSameTrimmedUTF16LimitAsTheAPI() async throws {
        let server = LessonFinishServer()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client,
            learnerID: HubFixture.learnerID, outbox: ConfigurationOutboxStub())
        await model.load()
        try #require(model.canStart)

        for value in ["", " \n\t ", String(repeating: "a", count: 500), "  \(String(repeating: "a", count: 500))\n", String(repeating: "🚗", count: 250)] {
            model.meetingPoint = value
            #expect(!model.meetingPointTooLong)
            #expect(model.canStart)
        }
        for value in [String(repeating: "a", count: 501), String(repeating: "🚗", count: 251)] {
            model.meetingPoint = value
            #expect(model.meetingPointTooLong)
            #expect(!model.canStart)
        }
    }

    @Test func retryAfterStorageFailureDiscardsALearnerWhoseAssignmentWasRemoved() async throws {
        let server = StartNowAssignmentReloadServer(), outbox = ConfigurationOutboxStub()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client, outbox: outbox)
        await model.load()
        try #require(model.canStart && model.learnerID == HubFixture.learnerID)

        outbox.failRead = true
        await model.load()
        try #require(!model.storageAvailable && !model.canStart)
        try #require(model.errorMessage != nil)
        #expect(model.errorMessage == SchoolConfigurationFailure.storage.localizedDescription)
        await server.removeOriginalAssignment()
        outbox.failRead = false
        await model.load()

        #expect(model.storageAvailable && model.learners.count == 2)
        #expect(model.errorMessage == nil)
        #expect(model.learnerID == nil && model.trainingID == nil && model.trainings.isEmpty)
        #expect(!model.canStart)
        #expect(outbox.saves.isEmpty)
    }

    private func command() throws -> PendingSchoolCommand {
        let operation = UUID()
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .startLessonNow,
            resourceVersion: 0, createdAt: HubFixture.date("2026-09-28T12:00:00Z"),
            body: try JSONEncoder().encode(SchoolStartNowBody(operationId: operation, trainingId: HubFixture.trainingID, meetingPoint: nil)),
            routeResourceID: HubFixture.trainingID)
    }
}

private actor StartNowAssignmentReloadServer: SchoolHTTPTransport {
    private let fallback = LessonFinishServer()
    private var originalRemoved = false
    private var unavailable = false
    func removeOriginalAssignment() { originalRemoved = true }
    func setUnavailable(_ value: Bool) { unavailable = value }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        if unavailable { throw URLError(.notConnectedToInternet) }
        guard originalRemoved, let url = request.url, url.lastPathComponent == "learners" else {
            return try await fallback.send(request)
        }
        let learners: [[String: Any]] = (1...2).map { index in
            ["id": UUID().uuidString, "schoolId": HubFixture.schoolID.uuidString, "personId": UUID().uuidString,
             "version": 1, "displayName": "Autre élève \(index)", "contactEmail": NSNull(), "contactPhone": NSNull(), "archivedAt": NSNull()]
        }
        let envelope: [String: Any] = ["data": ["items": learners, "nextCursor": NSNull()],
            "requestId": UUID().uuidString, "serverTime": "2026-09-30T12:00:00Z"]
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: 200, url: url, contentType: "application/json")
    }
}
