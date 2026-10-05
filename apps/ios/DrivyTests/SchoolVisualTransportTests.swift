#if DEBUG && targetEnvironment(simulator)
import Foundation
import Testing
@testable import Drivy

struct SchoolVisualTransportTests {
    @Test func agendaWindowUsesStrictOverlapAndKeepsCrossingLessons() async throws {
        let response = try await fixture().send(request([
            URLQueryItem(name: "from", value: "2026-10-04T09:00:00Z"),
            URLQueryItem(name: "to", value: "2026-10-04T10:00:00Z")
        ]))
        #expect(try identifiers(response) == ["enters", "inside", "spans", "leaves"])
        let envelope = try #require(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        #expect(envelope["requestId"] as? String == "visual-test-request")
        let page = try #require(envelope["data"] as? [String: Any])
        #expect(page["nextCursor"] is NSNull)
    }

    @Test func eitherAgendaBoundaryCanBeUsedAlone() async throws {
        let lower = try await fixture().send(request([URLQueryItem(name: "from", value: "2026-10-04T09:00:00Z")]))
        #expect(try identifiers(lower) == ["enters", "inside", "spans", "leaves", "after"])
        let upper = try await fixture().send(request([URLQueryItem(name: "to", value: "2026-10-04T10:00:00Z")]))
        #expect(try identifiers(upper) == ["before", "enters", "inside", "spans", "leaves"])
    }

    @Test func dossierWithoutWindowKeepsItsFixedHistory() async throws {
        let transport = try fixture()
        let response = try await transport.send(request([URLQueryItem(name: "trainingId", value: "fixture-training")]))
        #expect(response.data == transport.responses[Self.path])
        #expect(try identifiers(response) == ["history"])
    }

    @Test func trainingReadKeepsOnlyTheLessonsOfItsTraining() async throws {
        let transport = try trainingFixture()
        let first = try await transport.send(request([
            URLQueryItem(name: "trainingId", value: "10000000-0000-4000-8000-0000000000aa"),
            URLQueryItem(name: "limit", value: "100")
        ]))
        #expect(try identifiers(first) == ["first", "third"])
        let second = try await transport.send(request([
            URLQueryItem(name: "trainingId", value: "10000000-0000-4000-8000-0000000000BB")
        ]))
        #expect(try identifiers(second) == ["second"])
        let none = try await transport.send(request([
            URLQueryItem(name: "trainingId", value: "10000000-0000-4000-8000-0000000000cc")
        ]))
        #expect(try identifiers(none) == [])
    }

    @MainActor @Test func defaultFixtureKeepsOneTrainingAndTwoLessons() async throws {
        let context = try await SchoolVisualData.prepare()
        let schoolID = SchoolVisualData.schoolID
        let trainings = try await context.client.reader.trainings(schoolID: schoolID, learnerID: SchoolVisualData.learnerID, cursor: nil)
        #expect(trainings.items.count == 1)
        let lessons = try await context.client.lessons(schoolID: schoolID, trainingID: SchoolVisualData.trainingID, cursor: nil)
        #expect(lessons.items.count == 2)
    }

    @MainActor @Test func threePermitFixtureIsAcceptedByTheClients() async throws {
        let context = try await SchoolVisualData.prepare(permitCount: 3)
        let schoolID = SchoolVisualData.schoolID
        let trainings = try await context.client.reader.trainings(schoolID: schoolID, learnerID: SchoolVisualData.learnerID, cursor: nil)
        #expect(trainings.items.map(\.categoryCode) == ["B", "A", "BE"])
        #expect(trainings.items.map(\.status) == ["ACTIVE", "PAUSED", "COMPLETED"])
        var states = Set<String>()
        for training in trainings.items {
            let lessons = try await context.client.lessons(schoolID: schoolID, trainingID: training.id, cursor: nil)
            #expect(!lessons.items.isEmpty)
            states.formUnion(lessons.items.map { $0.drivyState.title })
            let progress = try await context.client.reports.progress(schoolID: schoolID, trainingID: training.id)
            #expect(progress.trainingId == training.id)
        }
        #expect(states == ["Planifiée", "À terminer", "Terminée", "Annulée", "Absence"])
    }

    @MainActor @Test func twoPermitFixtureServesTheFirstTwoTrainings() async throws {
        let context = try await SchoolVisualData.prepare(permitCount: 2)
        let trainings = try await context.client.reader.trainings(schoolID: SchoolVisualData.schoolID,
            learnerID: SchoolVisualData.learnerID, cursor: nil)
        #expect(trainings.items.map(\.categoryCode) == ["B", "A"])
    }

    @MainActor @Test func cancelledLessonOpensWithItsPlannedGoals() async throws {
        let context = try await SchoolVisualData.prepare()
        let schoolID = SchoolVisualData.schoolID
        let lesson = try await context.agenda.lesson(schoolID: schoolID, id: SchoolVisualData.cancelledLessonID)
        #expect(lesson.status == "CANCELLED")
        let preparation = try await context.agenda.reportClient.preparation(schoolID: schoolID, lessonID: lesson.id)
        #expect(preparation.goals.count == 2)
        let reports = try await context.agenda.reportClient.revisions(schoolID: schoolID, lessonID: lesson.id)
        #expect(reports.isEmpty)
    }

    private static let path = "/v1/schools/fixture-school/lessons"

    private func trainingFixture() throws -> SchoolVisualTransport {
        func lesson(_ id: String, training: String) -> [String: Any] {
            ["id": id, "trainingId": training, "plannedStart": "2026-09-21T08:00:00Z", "plannedEnd": "2026-09-21T09:00:00Z"]
        }
        let items: [[String: Any]] = [
            lesson("first", training: "10000000-0000-4000-8000-0000000000AA"),
            lesson("second", training: "10000000-0000-4000-8000-0000000000bb"),
            lesson("third", training: "10000000-0000-4000-8000-0000000000AA")
        ]
        let page: [String: Any] = ["items": items, "nextCursor": NSNull()]
        let body: [String: Any] = ["data": page, "requestId": "visual-test-request", "serverTime": "2026-10-04T10:00:00Z"]
        return SchoolVisualTransport(responses: [Self.path: try JSONSerialization.data(withJSONObject: body)])
    }

    private func request(_ query: [URLQueryItem]) throws -> URLRequest {
        var components = try #require(URLComponents(string: "https://visual.drivy.invalid" + Self.path))
        components.queryItems = query
        return URLRequest(url: try #require(components.url))
    }

    private func identifiers(_ response: SchoolHTTPResponse) throws -> [String] {
        let envelope = try #require(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
        let page = try #require(envelope["data"] as? [String: Any])
        let items = try #require(page["items"] as? [[String: Any]])
        return try items.map { try #require($0["id"] as? String) }
    }

    private func fixture() throws -> SchoolVisualTransport {
        func lesson(_ id: String, _ start: String, _ end: String) -> [String: Any] {
            ["id": id, "plannedStart": start, "plannedEnd": end]
        }
        func envelope(_ lessons: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "data": ["items": lessons, "nextCursor": NSNull()],
                "requestId": "visual-test-request", "serverTime": "2026-10-04T10:00:00Z"
            ])
        }
        let agenda = [
            lesson("before", "2026-10-04T08:00:00Z", "2026-10-04T09:00:00Z"),
            lesson("enters", "2026-10-03T23:30:00Z", "2026-10-04T09:01:00Z"),
            lesson("inside", "2026-10-04T09:20:00Z", "2026-10-04T09:40:00Z"),
            lesson("spans", "2026-10-04T08:00:00Z", "2026-10-04T11:00:00Z"),
            lesson("leaves", "2026-10-04T09:59:00Z", "2026-10-04T10:01:00Z"),
            lesson("after", "2026-10-04T10:00:00Z", "2026-10-04T11:00:00Z")
        ]
        return try SchoolVisualTransport(responses: [
            Self.path: envelope([lesson("history", "2026-09-21T08:00:00Z", "2026-09-21T09:00:00Z")]),
            Self.path + SchoolVisualTransport.agendaSuffix: envelope(agenda)
        ])
    }
}
#endif
