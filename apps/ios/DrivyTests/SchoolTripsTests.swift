import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolTripsTests {
    private static let schoolID = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
    private static let base = URL(string: "https://api.example.test")!

    private static func item(_ index: Int, start: String, stopped: String? = nil, sync: String = "SYNCED",
                             state: String = "STOPPED", instructor: UUID = UUID()) -> [String: Any] {
        let id = UUID(uuidString: String(format: "60000000-0000-4000-8000-%012d", 100 + index))!
        return ["id": id.uuidString, "schoolId": schoolID.uuidString, "version": 3, "lessonId": UUID().uuidString,
                "learnerId": UUID().uuidString, "instructorMembershipId": instructor.uuidString,
                "deviceId": UUID().uuidString, "choiceId": UUID().uuidString, "authorizedAt": start,
                "expiresAt": "2026-09-30T23:00:00Z", "stoppedAt": stopped.map { $0 as Any } ?? NSNull(), "cutoffAt": NSNull(),
                "uploadDeadline": "2026-10-02T23:00:00Z", "captureState": state, "syncState": sync,
                "publicationState": "PRIVATE", "deviceAssessmentId": UUID().uuidString,
                "learnerName": "Camille Exemple", "instructorName": "Luc Exemple",
                "lessonPlannedStart": start, "lessonTimeZone": "Europe/Zurich"]
    }

    @Test func theSchoolTripsAreReadPageByPageAndValidated() async throws {
        let items = [Self.item(1, start: "2026-09-28T08:00:00Z", stopped: "2026-09-28T08:48:00Z"),
                     Self.item(2, start: "2026-09-27T08:00:00Z", stopped: "2026-09-27T09:05:00Z", sync: "PARTIAL")]
        let transport = TripsTransport(body: tripsEnvelope(["items": items, "nextCursor": "next-page"]))
        let client = SchoolCaptureClient(baseURL: Self.base, tokenSource: TripsToken(), transport: transport)
        let page = try await client.captures(schoolID: Self.schoolID, cursor: "previous-page")
        #expect(page.items.count == 2 && page.nextCursor == "next-page")
        #expect(page.items[0].learnerName == "Camille Exemple" && page.items[0].capture.syncState == .synced)
        let request = try #require(await transport.recorded().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/schools/\(Self.schoolID.uuidString)/captures")
        let query = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query == [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: "previous-page")])

        // Another school, a cursor loop or a bad time zone never reach the list.
        var foreign = Self.item(3, start: "2026-09-28T08:00:00Z"); foreign["schoolId"] = UUID().uuidString
        var zone = Self.item(4, start: "2026-09-28T08:00:00Z"); zone["lessonTimeZone"] = "Mars/Olympus"
        for invalid in [["items": [foreign], "nextCursor": NSNull()], ["items": [zone], "nextCursor": NSNull()],
                        ["items": items, "nextCursor": "previous-page"]] as [[String: Any]] {
            let refused = SchoolCaptureClient(baseURL: Self.base, tokenSource: TripsToken(), transport: TripsTransport(body: tripsEnvelope(invalid)))
            await #expect(throws: SchoolCaptureFailure.invalidResponse) {
                try await refused.captures(schoolID: Self.schoolID, cursor: "previous-page")
            }
        }
    }

    @Test func tripsAreGroupedByDayWithTodayAndYesterday() throws {
        let trips = try [Self.item(1, start: "2026-09-28T14:00:00Z"), Self.item(2, start: "2026-09-28T08:00:00Z"),
                         Self.item(3, start: "2026-09-27T08:00:00Z"), Self.item(4, start: "2026-09-20T08:00:00Z")]
            .map { try JSONDecoder().decode(SchoolCaptureTrip.self, from: JSONSerialization.data(withJSONObject: $0)) }
        let now = try #require(SchoolLesson.date("2026-09-28T18:00:00Z"))
        let days = SchoolTripsWorkspace.days(trips, now: now)
        #expect(days.map(\.title).prefix(2) == ["Aujourd’hui", "Hier"])
        #expect(days.count == 3 && days[0].trips.count == 2)
        #expect(days[2].title.hasPrefix("Dimanche"))
        #expect(SchoolTripsWorkspace.time(trips[1]) == "10:00")
    }

    @Test func onlyTheUnusualGetsABadgeAndOnlyReconstructedTripsReplay() throws {
        func capture(_ values: [String: Any]) throws -> SchoolCaptureSession {
            try JSONDecoder().decode(SchoolCaptureTrip.self, from: JSONSerialization.data(withJSONObject: values)).capture
        }
        let synced = try capture(Self.item(1, start: "2026-09-28T08:00:00Z", stopped: "2026-09-28T08:48:00Z"))
        #expect(SchoolTripsWorkspace.badge(synced) == nil && SchoolTripsWorkspace.isReplayable(synced))
        #expect(SchoolTripsWorkspace.duration(synced) == "48 min")
        let partial = try capture(Self.item(2, start: "2026-09-28T08:00:00Z", stopped: "2026-09-28T09:05:00Z", sync: "PARTIAL"))
        #expect(SchoolTripsWorkspace.badge(partial)?.title == "Partiel" && SchoolTripsWorkspace.isReplayable(partial))
        #expect(SchoolTripsWorkspace.duration(partial) == "1 h 05")
        let unsent = try capture(Self.item(3, start: "2026-09-28T08:00:00Z", stopped: "2026-09-28T08:30:00Z", sync: "UPLOADING"))
        #expect(SchoolTripsWorkspace.badge(unsent)?.title == "Pas encore envoyé" && !SchoolTripsWorkspace.isReplayable(unsent))
        let live = try capture(Self.item(4, start: "2026-09-28T08:00:00Z", sync: "LOCAL_ONLY", state: "AUTHORIZED"))
        #expect(SchoolTripsWorkspace.badge(live)?.title == "En cours" && SchoolTripsWorkspace.duration(live) == nil)
    }

    @Test func theInstructorIsNamedOnlyForAnAdministratorReadingSomeoneElsesTrip() throws {
        let own = UUID()
        let scope = SchoolCommandScope(personID: UUID(), schoolID: Self.schoolID, membershipID: own, accessEpoch: 1,
            apiBaseURL: Self.base.absoluteString)
        let model = SchoolTripsWorkspace(scope: scope, client: SchoolCaptureClient(baseURL: Self.base, tokenSource: TripsToken(),
            transport: TripsTransport(body: tripsEnvelope([:]))))
        let mine = try JSONDecoder().decode(SchoolCaptureTrip.self,
            from: JSONSerialization.data(withJSONObject: Self.item(1, start: "2026-09-28T08:00:00Z", instructor: own)))
        let other = try JSONDecoder().decode(SchoolCaptureTrip.self,
            from: JSONSerialization.data(withJSONObject: Self.item(2, start: "2026-09-28T08:00:00Z")))
        #expect(model.instructorName(other, viewerRoles: ["ADMIN", "INSTRUCTOR"]) == "Luc Exemple")
        #expect(model.instructorName(mine, viewerRoles: ["ADMIN", "INSTRUCTOR"]) == nil)
        #expect(model.instructorName(other, viewerRoles: ["INSTRUCTOR"]) == nil)
    }
}

@MainActor
private final class TripsToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-trips-access" }
}

private func tripsEnvelope(_ page: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: ["data": page, "requestId": "synthetic-trips-request",
        "serverTime": "2026-09-28T18:00:00Z"])) ?? Data()
}

private actor TripsTransport: SchoolHTTPTransport {
    private let body: Data
    private var requests: [URLRequest] = []
    init(body: Data) { self.body = body }
    func recorded() -> [URLRequest] { requests }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        return SchoolHTTPResponse(data: body, status: 200, url: request.url!, contentType: "application/json")
    }
}
