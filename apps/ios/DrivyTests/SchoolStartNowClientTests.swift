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
        #expect(!stranger.hasPresetLearner)
    }

    private func command() throws -> PendingSchoolCommand {
        let operation = UUID()
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .startLessonNow,
            resourceVersion: 0, createdAt: HubFixture.date("2026-09-28T12:00:00Z"),
            body: try JSONEncoder().encode(SchoolStartNowBody(operationId: operation, trainingId: HubFixture.trainingID, meetingPoint: nil)),
            routeResourceID: HubFixture.trainingID)
    }
}
