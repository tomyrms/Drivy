import XCTest
@testable import Drivy

@MainActor
final class MessagingHTTPTransportTests: XCTestCase {
    func testSchoolRouteBearerAndOpaqueMessageDecode() async throws {
        let school = UUID(), conversation = UUID(), sender = UUID(), message = UUID(), intent = UUID()
        let url = URL(string: "https://api.example.invalid/")!
        let scopeAccount = UUID()
        let wire = RecordingMessagingHTTP { request in
            let path = request.url!.path
            guard path == "/v1/schools/\(school.uuidString)/messaging/conversations/\(conversation.uuidString)/messages",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token",
                  request.value(forHTTPHeaderField: "Cache-Control") == "no-store" else {
                throw MessagingFailure.invalidResponse
            }
            guard request.value(forHTTPHeaderField: "X-Drivy-Expected-Person-Id") == scopeAccount.uuidString.lowercased(),
                  request.value(forHTTPHeaderField: "X-Drivy-Expected-Access-Epoch") == "1" else {
                throw MessagingFailure.invalidResponse
            }
            let body = """
            {"data":{"items":[{"id":"\(message.uuidString)","schoolId":"\(school.uuidString)","conversationId":"\(conversation.uuidString)","sequence":1,"clientMessageId":"\(intent.uuidString)","senderId":"\(sender.uuidString)","ciphertext":{"scheme":"synthetic","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[],"acceptedAt":"2026-10-23T00:00:00Z"}],"nextCursor":null},"context":{"schoolId":"\(school.uuidString)","actorPersonId":"\(scopeAccount.uuidString)","accessEpoch":1}}
            """
            return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let scope = MessagingScope(accountID: scopeAccount, schoolID: school, accessEpoch: 1, apiBaseURL: url.absoluteString)
        let client = MessagingHTTPTransport.using(baseURL: url, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let page = try await client.messages(scope: scope, conversationID: conversation, before: nil)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items.first?.ciphertext.payload, Data([1, 2, 3]))
        XCTAssertEqual(page.items.first?.schoolId, school)
    }

    func testReadProgressDoesNotClearMuteAndMuteRequiresVersion() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 4,
                                   apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            guard request.httpMethod == "PUT" else { throw MessagingFailure.invalidResponse }
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            guard json["mutedUntil"] == nil, json["expectedVersion"] == nil,
                  json["lastReadSequence"] as? Int == 2 else { throw MessagingFailure.invalidResponse }
            let body = """
            {"data":{"lastReadSequence":2,"mutedUntil":"2026-10-23T05:00:00Z","readStateVersion":8},"context":{"schoolId":"\(school.uuidString)","actorPersonId":"\(account.uuidString)","accessEpoch":4}}
            """
            return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let state = try await client.readState(scope: scope, conversationID: conversation,
                                               sequence: 2, mutedUntil: nil, expectedVersion: nil)
        XCTAssertEqual(state.version, 8)
        XCTAssertNotNil(state.mutedUntil)
    }

    func testClearingMuteEncodesExplicitNullWithExpectedVersion() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 4,
                                   apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            guard json["mutedUntil"] is NSNull, json["expectedVersion"] as? Int == 8,
                  json["lastReadSequence"] as? Int == 2 else { throw MessagingFailure.invalidResponse }
            let body = """
            {"data":{"lastReadSequence":2,"mutedUntil":null,"readStateVersion":9},"context":{"schoolId":"\(school.uuidString)","actorPersonId":"\(account.uuidString)","accessEpoch":4}}
            """
            return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let state = try await client.readState(scope: scope, conversationID: conversation,
                                               sequence: 2, mutedUntil: nil, expectedVersion: 8)
        XCTAssertNil(state.mutedUntil)
        XCTAssertEqual(state.version, 9)
    }

    func testDifferentAPIURLRejectedBeforeNetwork() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let wire = RecordingMessagingHTTP { _ in throw MessagingFailure.invalidResponse }
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                   apiBaseURL: "https://different.example.invalid/")
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        do {
            _ = try await client.contacts(scope: scope)
            XCTFail("API URL différente")
        } catch MessagingFailure.contextChanged { }
        let requests = await wire.requests()
        XCTAssertEqual(requests, 0)
    }
}

@MainActor private final class MessagingFixtureToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-token" }
}

private actor RecordingMessagingHTTP: SchoolHTTPTransport {
    private let responder: @Sendable (URLRequest) throws -> SchoolHTTPResponse
    private var count = 0
    init(_ responder: @escaping @Sendable (URLRequest) throws -> SchoolHTTPResponse) { self.responder = responder }
    func send(_ request: URLRequest) throws -> SchoolHTTPResponse { count += 1; return try responder(request) }
    func requests() -> Int { count }
}
