import Foundation
import Testing
@testable import Drivy

@MainActor private final class ProfileTokenStub: AccessTokenSource {
    var calls = 0
    func accessToken() async throws -> String { calls += 1; return "synthetic-profile-access" }
}
private actor ProfileTransportStub: SchoolHTTPTransport {
    let data: Data
    let status: Int
    let media: String
    let redirect: URL?
    private var requests: [URLRequest] = []
    init(data: Data, status: Int = 200, media: String = "application/json", redirect: URL? = nil) {
        self.data = data; self.status = status; self.media = media; self.redirect = redirect
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        return .init(data: data, status: status, url: redirect ?? request.url!, contentType: media)
    }
    func recorded() -> [URLRequest] { requests }
}
@MainActor
struct SchoolProfileClientTests {
    @Test func postalAddressWithoutOptionalComplementEncodesTheRequiredNull() throws {
        let address = SchoolPostalAddress(line1: "Rue Exemple 1", line2: nil, postalCode: "1000", locality: "Lausanne", countryCode: "CH")
        let body = try JSONEncoder().encode(["postalAddress": SchoolProfileValue.address(address)])
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sent = try #require(object["postalAddress"] as? [String: Any])
        #expect(sent["line2"] is NSNull)
        #expect(sent["line1"] as? String == "Rue Exemple 1")
        #expect(try JSONDecoder().decode([String: SchoolProfileValue].self, from: body)["postalAddress"] == .address(address))
    }
    let base = URL(string: "https://api.example.invalid")!
    private struct Envelope<T: Encodable>: Encodable { let data: T; let requestId: String; let serverTime: String }
    private func envelope<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(Envelope(data: value, requestId: "synthetic-profile-request", serverTime: ConfigurationFixture.timestamp))
    }
    @Test func profileMutationUsesLearnerRouteWithProfileReceiptAndOriginalBytes() async throws {
        let command = try ProfileFixture.command()
        let transport = ProfileTransportStub(data: try envelope(ProfileFixture.profile(version: 2)))
        let client = SchoolProfileClient(baseURL: base, tokenSource: ProfileTokenStub(), transport: transport)
        _ = try await client.send(command); _ = try await client.send(command)
        let requests = await transport.recorded()
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.url?.path == "/v1/schools/\(command.scope.schoolID.uuidString)/learners/\(ProfileFixture.learnerID.uuidString)/administrative-profile")
            #expect(request.httpMethod == "PATCH" && request.httpBody == command.body)
            #expect(request.value(forHTTPHeaderField: "If-Match") == "\"1\"")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
        }
    }
    @Test func policyCreationUsesSchoolIfMatchSeparateFromInitialResourceVersion() async throws {
        let id = UUID(); let draft = ProfileFixture.policyDraft()
        let command = PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: .createProfilePolicy,
            resourceVersion: 0, createdAt: Date(), body: try JSONEncoder().encode(SchoolProfilePolicyCommand(operationId: id,
                effectiveFrom: ConfigurationFixture.timestamp, fields: draft.selectedRules, noticeVersionId: ProfileFixture.noticeID,
                impactAcknowledged: true)), expectedVersion: 8)
        let transport = ProfileTransportStub(data: try envelope(ProfileFixture.policy(status: "DRAFT", version: 1)), status: 201)
        let client = SchoolProfileClient(baseURL: base, tokenSource: ProfileTokenStub(), transport: transport)
        _ = try await client.send(command)
        let request = try #require(await transport.recorded().first)
        #expect(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "If-Match") == "\"8\"")
        #expect(request.httpBody == command.body)
        #expect(command.matches(ProfileFixture.receipt(command)))
    }
    @Test func protectedFieldsMayBeAbsentAndNoticeUUIDRemainsBackwardCompatible() throws {
        let profileData = try JSONSerialization.data(withJSONObject: ["id": ProfileFixture.profileID.uuidString,
            "schoolId": ConfigurationFixture.schoolID.uuidString, "version": 1, "learnerId": ProfileFixture.learnerID.uuidString,
            "firstName": NSNull(), "lastName": NSNull(), "contactEmail": "alice@example.invalid", "contactPhone": NSNull(),
            "updatedAt": ConfigurationFixture.timestamp, "enteredByMembershipId": ConfigurationFixture.membershipID.uuidString,
            "entrySource": "STAFF_ASSISTED", "policyVersionId": ProfileFixture.policyID.uuidString])
        let result = try JSONDecoder().decode(SchoolAdministrativeProfile.self, from: profileData)
        #expect(result.birthDate == nil && result.postalAddress == nil && result.profilePhotoDocumentId == nil)
        var notice = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ProfileFixture.notice())) as? [String: Any])
        notice.removeValue(forKey: "noticeVersionId")
        #expect(try JSONDecoder().decode(SchoolDataPolicy.self, from: JSONSerialization.data(withJSONObject: notice)).noticeVersionId == nil)
    }
    @Test func unsafeOriginAndRedirectDoNotConfirmProfileData() async throws {
        let token = ProfileTokenStub(); let transport = ProfileTransportStub(data: try envelope(ProfileFixture.profile()))
        let unsafe = SchoolProfileClient(baseURL: URL(string: "http://api.example.invalid")!, tokenSource: token, transport: transport)
        await #expect(throws: SchoolProfileFailure.invalidResponse) { try await unsafe.profile(schoolID: ConfigurationFixture.schoolID, learnerID: ProfileFixture.learnerID) }
        #expect(token.calls == 0)
        let redirect = ProfileTransportStub(data: try envelope(ProfileFixture.profile()), redirect: URL(string: "https://other.example.invalid")!)
        let client = SchoolProfileClient(baseURL: base, tokenSource: token, transport: redirect)
        await #expect(throws: SchoolProfileFailure.invalidResponse) { try await client.profile(schoolID: ConfigurationFixture.schoolID, learnerID: ProfileFixture.learnerID) }
    }
    @Test func wrongTargetOrUnchangedVersionCannotReleaseTheOutbox() async throws {
        let command = try ProfileFixture.command()
        let transport = ProfileTransportStub(data: try envelope(ProfileFixture.profile()))
        let client = SchoolProfileClient(baseURL: base, tokenSource: ProfileTokenStub(), transport: transport)
        await #expect(throws: SchoolProfileFailure.invalidResponse) { try await client.send(command) }
        #expect(!command.matches(ProfileFixture.receipt(command, id: ProfileFixture.learnerID)))
    }
    @Test func unknownOperationAndIdempotencyMismatchRemainUnresolved() async throws {
        let command = try ProfileFixture.command()
        let unknown = ProfileTransportStub(data: Data("{\"code\":\"NOT_FOUND\"}".utf8), status: 404, media: "application/problem+json")
        let client = SchoolProfileClient(baseURL: base, tokenSource: ProfileTokenStub(), transport: unknown)
        await #expect(throws: SchoolProfileFailure.operationUnknown) { try await client.operation(schoolID: command.scope.schoolID, id: command.id) }
        let mismatch = ProfileTransportStub(data: Data("{\"code\":\"IDEMPOTENCY_MISMATCH\"}".utf8), status: 409, media: "application/problem+json")
        let other = SchoolProfileClient(baseURL: base, tokenSource: ProfileTokenStub(), transport: mismatch)
        await #expect(throws: SchoolProfileFailure.pendingCommand) { try await other.send(command) }
    }
    @Test func policyConflictIsSpecificAndOptionalPhotoRuleCannotBeRequired() async throws {
        let command = try ProfileFixture.command()
        let transport = ProfileTransportStub(data: Data("{\"code\":\"PROFILE_POLICY_CHANGED\"}".utf8), status: 409, media: "application/problem+json")
        let client = SchoolProfileClient(baseURL: base, tokenSource: ProfileTokenStub(), transport: transport)
        await #expect(throws: SchoolProfileFailure.conflict) { try await client.send(command) }
        let bad = SchoolProfileRule(field: .profilePhotoDocumentId, requirement: .required, stage: .join,
            purposeCode: .identification, explanation: "Mauvaise règle")
        #expect(!bad.isValid)
    }
}
