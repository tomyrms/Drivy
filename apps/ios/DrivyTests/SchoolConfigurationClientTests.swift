import Foundation
import Testing
@testable import Drivy

@MainActor
private final class ConfigurationToken: AccessTokenSource {
    var calls = 0
    func accessToken() async throws -> String { calls += 1; return "configuration-test-access-token" }
}

private actor ConfigurationTransport: SchoolHTTPTransport {
    let data: Data
    let status: Int
    let mediaType: String
    let responseURL: URL?
    private var requests: [URLRequest] = []
    init(_ data: Data, status: Int = 200, mediaType: String = "application/json", responseURL: URL? = nil) {
        self.data = data; self.status = status; self.mediaType = mediaType; self.responseURL = responseURL
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        return SchoolHTTPResponse(data: data, status: status, url: responseURL ?? request.url!, contentType: mediaType)
    }
    func recorded() -> [URLRequest] { requests }
}

@MainActor
struct SchoolConfigurationClientTests {
    private let school = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let member = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private let base = URL(string: "https://api.example.invalid/refonte")!
    private let time = "2026-09-24T15:00:00.000Z"

    private func envelope(_ data: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["data": data, "requestId": "opaque-config-request", "serverTime": time])
    }
    private func policy(schoolID: UUID? = nil, version: Int = 2) -> [String: Any] {
        ["id": (schoolID ?? school).uuidString, "schoolId": (schoolID ?? school).uuidString, "version": version, "status": "APPROVED",
         "noticeText": "Notice de recette", "retentionText": "Conservation de recette", "contactEmail": "luc@example.com",
         "approvedAt": time, "approvedByMembershipId": member.uuidString]
    }
    private func readiness(ready: Bool = true) -> [String: Any] {
        ["schoolId": school.uuidString, "configurationVersion": 2, "computedAt": time,
         "activationReady": ready, "activationBlockers": [], "capabilities":
            ["CAN_USE_WORKSPACE", "CAN_PLAN_LESSON", "CAN_CAPTURE", "CAN_PUBLISH_COURSE"].map {
                ["capability": $0, "ready": true, "blockers": []] as [String: Any]
            }]
    }
    private func pending(id: UUID = UUID(), scopeURL: String? = nil) throws -> PendingSchoolCommand {
        let body = SchoolDataPolicyCommand(operationId: id, noticeText: "Notice de recette", retentionText: "Conservation de recette",
            contactEmail: "luc@example.com", reviewAcknowledged: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return PendingSchoolCommand(id: id,
            scope: SchoolCommandScope(personID: UUID(), schoolID: school, membershipID: member, accessEpoch: 1, apiBaseURL: scopeURL ?? base.absoluteString),
            kind: .saveDataPolicy, resourceVersion: 1, createdAt: Date(), body: try encoder.encode(body))
    }

    @Test func policyEmissionPreservesIdempotencyVersionAndExactRequestAcrossRetry() async throws {
        let transport = ConfigurationTransport(try envelope(policy()))
        let token = ConfigurationToken()
        let client = SchoolConfigurationClient(baseURL: base, tokenSource: token, transport: transport)
        let command = try pending()
        guard case .dataPolicy(let first) = try await client.send(command),
              case .dataPolicy(let second) = try await client.send(command) else { Issue.record("Réponse de politique attendue"); return }
        #expect(first == second)
        let requests = await transport.recorded()
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/refonte/v1/schools/\(school.uuidString)/data-policy")
            #expect(request.httpBody == command.body)
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
            #expect(request.value(forHTTPHeaderField: "If-Match") == "\"1\"")
            #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        }
        #expect(token.calls == 2)
    }

    @Test func validatesReadinessAndSetupInsteadOfTrustingReadyFlag() async throws {
        let token = ConfigurationToken()
        let client = SchoolConfigurationClient(baseURL: base, tokenSource: token,
            transport: ConfigurationTransport(try envelope(readiness())))
        #expect(try await client.readiness(schoolID: school).activationReady == true)
        let contradictory = SchoolConfigurationClient(baseURL: base, tokenSource: token,
            transport: ConfigurationTransport(try envelope(readiness(ready: false))))
        await #expect(throws: SchoolConfigurationFailure.invalidResponse) { try await contradictory.readiness(schoolID: school) }
        let data: [String: Any] = ["id": school.uuidString, "schoolId": school.uuidString, "version": 1, "status": "READY", "currentStep": "REVIEW",
            "completedSteps": ["IDENTITY", "DATA"], "lastSavedAt": time, "configuredByMembershipId": member.uuidString, "readiness": readiness()]
        let setup = SchoolConfigurationClient(baseURL: base, tokenSource: token, transport: ConfigurationTransport(try envelope(data)))
        #expect(try await setup.setup(schoolID: school).currentStep == "REVIEW")
    }

    @Test func rejectsUnsafeDestinationBeforeObtainingTokenOrSending() async throws {
        let token = ConfigurationToken()
        let transport = ConfigurationTransport(try envelope(policy()))
        let insecure = SchoolConfigurationClient(baseURL: URL(string: "http://api.example.invalid")!, tokenSource: token, transport: transport)
        await #expect(throws: SchoolConfigurationFailure.invalidResponse) { try await insecure.dataPolicy(schoolID: school) }
        let secure = SchoolConfigurationClient(baseURL: base, tokenSource: token, transport: transport)
        let wrongServer = try pending(scopeURL: "https://another.example.invalid")
        await #expect(throws: SchoolConfigurationFailure.invalidResponse) { try await secure.send(wrongServer) }
        #expect(token.calls == 0)
        #expect(await transport.recorded().isEmpty)
    }

    @Test func rejectsForeignScopeRedirectAndUnchangedVersionAsAcknowledgment() async throws {
        let command = try pending()
        let foreign = SchoolConfigurationClient(baseURL: base, tokenSource: ConfigurationToken(),
            transport: ConfigurationTransport(try envelope(policy(schoolID: UUID()))))
        await #expect(throws: SchoolConfigurationFailure.invalidResponse) { try await foreign.send(command) }
        let redirect = SchoolConfigurationClient(baseURL: base, tokenSource: ConfigurationToken(),
            transport: ConfigurationTransport(try envelope(policy()), responseURL: URL(string: "https://another.example.invalid")))
        await #expect(throws: SchoolConfigurationFailure.invalidResponse) { try await redirect.send(command) }
        let unchanged = SchoolConfigurationClient(baseURL: base, tokenSource: ConfigurationToken(),
            transport: ConfigurationTransport(try envelope(policy(version: 1))))
        await #expect(throws: SchoolConfigurationFailure.invalidResponse) { try await unchanged.send(command) }
    }

    @Test func mapsExplicitRejectionsWithoutAutomaticRetryOrDiscardingUnknownOperation() async throws {
        let cases: [(Int, String, SchoolConfigurationFailure)] = [
            (400, "INVALID_REQUEST", .rejected), (401, "UNAUTHORIZED", .unauthorized), (403, "SETUP_ACCESS_REQUIRED", .forbidden),
            (409, "IDEMPOTENCY_MISMATCH", .pendingCommand), (409, "POLICY_REVIEW_REQUIRED", .rejected),
            (412, "VERSION_CONFLICT", .conflict), (500, "INTERNAL_ERROR", .unavailable)
        ]
        let command = try pending()
        for (status, code, failure) in cases {
            let data = try JSONSerialization.data(withJSONObject: ["code": code, "status": status])
            let transport = ConfigurationTransport(data, status: status, mediaType: "application/problem+json")
            let client = SchoolConfigurationClient(baseURL: base, tokenSource: ConfigurationToken(), transport: transport)
            await #expect(throws: failure) { try await client.send(command) }
            #expect(await transport.recorded().count == 1)
        }
        let absent = SchoolConfigurationClient(baseURL: base, tokenSource: ConfigurationToken(),
            transport: ConfigurationTransport(Data("{}".utf8), status: 404, mediaType: "application/problem+json"))
        await #expect(throws: SchoolConfigurationFailure.operationUnknown) { try await absent.operation(schoolID: school, id: command.id) }
        #expect(!SchoolConfigurationFailure.operationUnknown.permitsCorrectionOfFreshRequest)
        #expect(!SchoolConfigurationFailure.pendingCommand.permitsCorrectionOfFreshRequest)
    }

    @Test func operationReceiptMustMatchRequestedOperationAndSchool() async throws {
        let id = UUID()
        var data: [String: Any] = ["operationId": id.uuidString, "commandType": "ADOPT_SCHOOL_DATA_POLICY", "resourceType": "SchoolDataPolicy",
            "resourceId": school.uuidString, "resourceVersion": 2, "committedAt": time]
        let good = SchoolConfigurationClient(baseURL: base, tokenSource: ConfigurationToken(), transport: ConfigurationTransport(try envelope(data)))
        #expect(try await good.operation(schoolID: school, id: id).operationId == id)
        data["operationId"] = UUID().uuidString
        let wrong = SchoolConfigurationClient(baseURL: base, tokenSource: ConfigurationToken(), transport: ConfigurationTransport(try envelope(data)))
        await #expect(throws: SchoolConfigurationFailure.invalidResponse) { try await wrong.operation(schoolID: school, id: id) }
    }
}
