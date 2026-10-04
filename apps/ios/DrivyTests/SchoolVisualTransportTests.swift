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

    private static let path = "/v1/schools/fixture-school/lessons"

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
