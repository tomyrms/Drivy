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

    private func command() throws -> PendingSchoolCommand {
        let operation = UUID()
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .startLessonNow,
            resourceVersion: 0, createdAt: HubFixture.date("2026-09-28T12:00:00Z"),
            body: try JSONEncoder().encode(SchoolStartNowBody(operationId: operation, trainingId: HubFixture.trainingID, meetingPoint: nil)),
            routeResourceID: HubFixture.trainingID)
    }
}
