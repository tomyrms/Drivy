import Foundation
import Testing
@testable import Drivy

private final class SchoolFixtureBundle: NSObject {}

private func apiFixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: SchoolFixtureBundle.self)
    let url = try #require(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") ??
                           bundle.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

@MainActor
private final class TestAccessToken: AccessTokenSource {
    var calls = 0
    var value = "opaque-unit-test-token"
    func accessToken() async throws -> String { calls += 1; return value }
}

private actor ResponseTransport: SchoolHTTPTransport {
    let data: Data
    let status: Int
    let contentType: String
    let redirect: URL?
    private var requests: [URLRequest] = []

    init(data: Data, status: Int = 200, contentType: String = "application/json; charset=utf-8", redirect: URL? = nil) {
        self.data = data; self.status = status; self.contentType = contentType; self.redirect = redirect
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        return SchoolHTTPResponse(data: data, status: status, url: redirect ?? request.url!, contentType: contentType)
    }
    func recordedRequests() -> [URLRequest] { requests }
}

@MainActor
struct SchoolAPIClientTests {
    private let base = URL(string: "https://api.example.invalid")!
    private let school = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let learner = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    private let training = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!

    @Test func readsTheSixRealPostgresResponses() async throws {
        let token = TestAccessToken()
        func client(_ name: String) throws -> DrivyAPIClient {
            DrivyAPIClient(baseURL: base, tokenSource: token, transport: ResponseTransport(data: try apiFixture(name)))
        }
        let me = try await client("me").me()
        #expect(me.displayName == "Alex Moniteur")
        #expect(me.memberships.count == 2)
        #expect(try await client("school").school(id: school).id == school)
        #expect(try await client("learners").learners(schoolID: school, query: "", cursor: nil).items.map(\.id) == [learner])
        #expect(try await client("learner").learner(schoolID: school, id: learner).displayName == "Alice Exemple")
        #expect(try await client("trainings").trainings(schoolID: school, learnerID: learner, cursor: nil).items.map(\.id) == [training])
        #expect(try await client("training").training(schoolID: school, id: training).startedOn == "2026-01-01")
        #expect(token.calls == 6)
    }

    @Test func preservesSearchCharactersAndOpaqueCursor() async throws {
        let transport = ResponseTransport(data: try apiFixture("learners"))
        let client = DrivyAPIClient(baseURL: base, tokenSource: TestAccessToken(), transport: transport)
        _ = try await client.learners(schoolID: school, query: "Éva + Alice & Noé", cursor: "opaque_-123")
        let request = try #require(await transport.recordedRequests().first)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "Éva + Alice & Noé")
        #expect(components.percentEncodedQuery?.contains("%2B") == true)
        #expect(components.queryItems?.first(where: { $0.name == "cursor" })?.value == "opaque_-123")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer opaque-unit-test-token")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.httpMethod == "GET")
    }

    @Test func refusesForeignSchoolPayloadAndRedirect() async throws {
        let data = try apiFixture("learner")
        let foreign = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let client = DrivyAPIClient(baseURL: base, tokenSource: TestAccessToken(), transport: ResponseTransport(data: data))
        await #expect(throws: SchoolAPIError.invalidResponse) { try await client.learner(schoolID: foreign, id: learner) }
        let redirect = DrivyAPIClient(baseURL: base, tokenSource: TestAccessToken(),
            transport: ResponseTransport(data: try apiFixture("me"), redirect: URL(string: "https://foreign.example.invalid/v1/me")!))
        await #expect(throws: SchoolAPIError.invalidResponse) { try await redirect.me() }
    }

    @Test func mapsDenialsWithoutShowingServerDetailsOrRetryingTokens() async throws {
        let cases: [(Int, String, SchoolAPIError)] = [
            (401, "UNAUTHORIZED", .unauthorized), (403, "FORBIDDEN", .forbidden),
            (403, "IDENTITY_NOT_LINKED", .identityNotLinked), (404, "NOT_FOUND", .notFound),
            (400, "INVALID_CURSOR", .invalidCursor), (503, "SERVICE_UNAVAILABLE", .unavailable)
        ]
        for (status, code, expected) in cases {
            let token = TestAccessToken()
            let data = Data("{\"code\":\"\(code)\",\"title\":\"private server detail\"}".utf8)
            let transport = ResponseTransport(data: data, status: status, contentType: "application/problem+json")
            let client = DrivyAPIClient(baseURL: base, tokenSource: token, transport: transport)
            await #expect(throws: expected) { try await client.me() }
            #expect(token.calls == 1)
            #expect(await transport.recordedRequests().count == 1)
        }
    }

    @Test func rejectsUnsafeEndpointBeforeReadingToken() async throws {
        let token = TestAccessToken()
        for value in ["http://remote.example.invalid", "https://user:password@example.invalid", "https://example.invalid?next=foreign", "https://example.invalid#fragment"] {
            let transport = ResponseTransport(data: Data())
            let client = DrivyAPIClient(baseURL: URL(string: value)!, tokenSource: token, transport: transport)
            await #expect(throws: SchoolAPIError.invalidConfiguration) { try await client.me() }
            #expect(await transport.recordedRequests().isEmpty)
        }
        #expect(token.calls == 0)
    }

    @Test func requiresNullableFieldsAndValidEnvelope() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: apiFixture("learner")) as? [String: Any])
        var data = try #require(object["data"] as? [String: Any])
        data.removeValue(forKey: "contactPhone")
        object["data"] = data
        let incomplete = try JSONSerialization.data(withJSONObject: object)
        let client = DrivyAPIClient(baseURL: base, tokenSource: TestAccessToken(), transport: ResponseTransport(data: incomplete))
        await #expect(throws: SchoolAPIError.invalidResponse) { try await client.learner(schoolID: school, id: learner) }
        let html = DrivyAPIClient(baseURL: base, tokenSource: TestAccessToken(),
            transport: ResponseTransport(data: try apiFixture("me"), contentType: "text/html"))
        await #expect(throws: SchoolAPIError.invalidResponse) { try await html.me() }
    }

    @Test func civilDatesRemainDatesAndRejectImpossibleDays() {
        #expect(DrivyAPIClient.isCivilDate("2024-02-29"))
        #expect(!DrivyAPIClient.isCivilDate("2025-02-29"))
        #expect(!DrivyAPIClient.isCivilDate("2026-13-01"))
        #expect(!DrivyAPIClient.isCivilDate("2026-01-01T00:00:00Z"))
        #expect(DrivyAPIClient.isCivilDate(nil))
    }

    @Test func acceptsOpaqueRequestIdentifiersFromTheContract() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: apiFixture("me")) as? [String: Any])
        object["requestId"] = "req-example-001"
        let transport = ResponseTransport(data: try JSONSerialization.data(withJSONObject: object))
        let client = DrivyAPIClient(baseURL: base, tokenSource: TestAccessToken(), transport: transport)
        #expect(try await client.me().displayName == "Alex Moniteur")
    }

    // MARK: Historique des leçons

    private func historyLesson(_ index: Int, start: String, end: String, instructor: UUID, capture: [String: Any]? = nil) -> [String: Any] {
        var lesson: [String: Any] = [
            "id": String(format: "81000000-0000-4000-8000-%012d", index), "schoolId": school.uuidString, "version": 2,
            "trainingId": training.uuidString, "learnerId": learner.uuidString, "instructorMembershipId": instructor.uuidString,
            "plannedStart": start, "plannedEnd": end, "timeZone": "Europe/Zurich", "meetingPoint": "Gare", "status": "COMPLETED",
            "priceCentsSnapshot": 9_000, "bufferMinutesSnapshot": 10, "actualStart": NSNull(), "actualEnd": NSNull(),
            "permitWarning": false, "publicationVersion": 0, "currentPublishedRevisionId": NSNull(), "commercialRevisionVersion": 1,
            "learnerDisplayName": "Alice Exemple", "instructorDisplayName": "Alex Moniteur"
        ]
        if let capture { lesson["captureSummary"] = capture }
        return lesson
    }

    private func historyPage(_ items: [[String: Any]], nextCursor: String?) throws -> Data {
        let page: [String: Any] = ["items": items, "nextCursor": nextCursor.map { $0 as Any } ?? NSNull()]
        let envelope: [String: Any] = ["data": page, "requestId": "90000000-0000-4000-8000-000000000001",
                                       "serverTime": "2026-10-06T10:00:00Z"]
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    @Test func lessonHistoryAsksForTheOrderAndReadsTheCaptureSummaryWhenPresent() async throws {
        let instructor = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
        let before = try #require(SchoolLesson.date("2026-10-06T10:00:00Z"))
        let items = [
            historyLesson(1, start: "2026-10-05T08:00:00Z", end: "2026-10-05T08:50:00Z", instructor: instructor,
                capture: ["hasCapture": true, "syncState": "SYNCED", "publicationState": "PRIVATE"]),
            historyLesson(2, start: "2026-10-04T08:00:00Z", end: "2026-10-04T08:50:00Z", instructor: instructor,
                capture: ["hasCapture": false, "syncState": NSNull(), "publicationState": "NONE"]),
            // Serveur plus ancien : pas de résumé de trajet, la leçon se lit quand même.
            historyLesson(3, start: "2026-10-03T08:00:00Z", end: "2026-10-03T08:50:00Z", instructor: instructor)
        ]
        let transport = ResponseTransport(data: try historyPage(items, nextCursor: "next-page"))
        let client = SchoolAgendaClient(baseURL: base, tokenSource: TestAccessToken(), transport: transport)
        let page = try await client.lessonHistory(schoolID: school, before: before, instructorMembershipID: instructor, cursor: "previous-page")
        #expect(page.items.count == 3 && page.nextCursor == "next-page")
        #expect(page.items[0].captureSummary == SchoolLessonCaptureSummary(hasCapture: true, syncState: "SYNCED", publicationState: "PRIVATE"))
        #expect(page.items[1].captureSummary == SchoolLessonCaptureSummary(hasCapture: false, syncState: nil, publicationState: "NONE"))
        #expect(page.items[2].captureSummary == nil)
        #expect(page.items[0].drivyContents == [.trip] && page.items[1].drivyContents.isEmpty && page.items[2].drivyContents.isEmpty)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET" && request.url?.path == "/v1/schools/\(school.uuidString)/lessons")
        let query = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query == [URLQueryItem(name: "to", value: "2026-10-06T10:00:00Z"), URLQueryItem(name: "limit", value: "100"),
                          URLQueryItem(name: "order", value: "desc"),
                          URLQueryItem(name: "instructorMembershipId", value: instructor.uuidString.lowercased()),
                          URLQueryItem(name: "cursor", value: "previous-page")])

        // Toute l’école, anciennes d’abord, première page : ni filtre de moniteur ni curseur.
        let oldest = ResponseTransport(data: try historyPage(Array(items.reversed()), nextCursor: nil))
        _ = try await SchoolAgendaClient(baseURL: base, tokenSource: TestAccessToken(), transport: oldest)
            .lessonHistory(schoolID: school, before: before, instructorMembershipID: nil, newestFirst: false, cursor: nil)
        let ascending = try #require(await oldest.recordedRequests().first?.url)
        #expect(URLComponents(url: ascending, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "to", value: "2026-10-06T10:00:00Z"), URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "order", value: "asc")])
    }

    @Test func lessonHistoryRefusesWhatTheRequestDidNotAskFor() async throws {
        let instructor = UUID(uuidString: "30000000-0000-4000-8000-000000000002")!
        let before = try #require(SchoolLesson.date("2026-10-06T10:00:00Z"))
        let past = historyLesson(1, start: "2026-10-05T08:00:00Z", end: "2026-10-05T08:50:00Z", instructor: instructor)
        // Une leçon à venir, celle d’un autre moniteur, un doublon, le curseur rendu tel quel : jamais dans la liste.
        let future = historyLesson(2, start: "2026-10-06T10:00:00Z", end: "2026-10-06T10:50:00Z", instructor: instructor)
        let colleague = historyLesson(3, start: "2026-10-04T08:00:00Z", end: "2026-10-04T08:50:00Z", instructor: UUID())
        let refused: [(items: [[String: Any]], cursor: String?)] = [([past, future], nil), ([past, colleague], nil),
                                                                   ([past, past], nil), ([past], "previous-page")]
        for answer in refused {
            let client = SchoolAgendaClient(baseURL: base, tokenSource: TestAccessToken(),
                transport: ResponseTransport(data: try historyPage(answer.items, nextCursor: answer.cursor)))
            await #expect(throws: SchoolAgendaFailure.invalidResponse) {
                try await client.lessonHistory(schoolID: school, before: before, instructorMembershipID: instructor, cursor: "previous-page")
            }
        }
        // Un résumé de trajet d’une autre forme est une réponse invalide, pas une leçon sans trajet.
        let malformed = historyLesson(4, start: "2026-10-05T08:00:00Z", end: "2026-10-05T08:50:00Z", instructor: instructor,
            capture: ["hasCapture": "yes"])
        let client = SchoolAgendaClient(baseURL: base, tokenSource: TestAccessToken(),
            transport: ResponseTransport(data: try historyPage([malformed], nextCursor: nil)))
        await #expect(throws: SchoolAgendaFailure.invalidResponse) {
            try await client.lessonHistory(schoolID: school, before: before, instructorMembershipID: instructor, cursor: nil)
        }
    }
}
