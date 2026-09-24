import Foundation
import Testing
@testable import Drivy

@MainActor
private final class InvitationToken: AccessTokenSource {
    var calls = 0
    func accessToken() async throws -> String { calls += 1; return "synthetic-invitation-access" }
}

private actor InvitationTransport: SchoolHTTPTransport {
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
        return .init(data: data, status: status, url: responseURL ?? request.url!, contentType: mediaType)
    }
    func recorded() -> [URLRequest] { requests }
}

@MainActor
struct SchoolInvitationClientTests {
    @Test func unconfiguredDeliveryHasSpecificMessageAndCannotReleaseAnUncertainCommand() async throws {
        let transport = InvitationTransport(Data("{\"code\":\"INVITATION_DELIVERY_UNAVAILABLE\"}".utf8),
            status: 503, mediaType: "application/problem+json")
        let client = SchoolInvitationClient(baseURL: URL(string: "https://api.example.invalid")!, tokenSource: InvitationToken(), transport: transport)
        let command = try InvitationFixture.command()
        await #expect(throws: SchoolInvitationFailure.deliveryUnavailable) { try await client.send(command) }
        #expect(!SchoolInvitationFailure.deliveryUnavailable.permitsCorrectionOfFreshRequest)
        #expect(SchoolInvitationFailure.deliveryUnavailable.localizedDescription.contains("n’est pas encore configuré"))
    }
    private let base = URL(string: "https://api.example.invalid")!
    private let school = ConfigurationFixture.schoolID
    private func envelope<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(Envelope(data: value, requestId: "synthetic-invitation-request", serverTime: ConfigurationFixture.timestamp))
    }
    private struct Envelope<T: Encodable>: Encodable { let data: T; let requestId: String; let serverTime: String }
    private func createCommand() throws -> PendingSchoolCommand {
        let id = UUID()
        return .init(id: id, scope: ConfigurationFixture.scope(), kind: .createInvitation, resourceVersion: 0,
            createdAt: Date(), body: try JSONEncoder().encode(SchoolInviteCommand(operationId: id,
                email: "person@example.invalid", roles: [.learner])))
    }

    @Test func listingUsesCanonicalPaginationAndMaskedProjectionOnly() async throws {
        let expected = InvitationFixture.invitation()
        let page = SchoolPage(items: [expected], nextCursor: "next+cursor=")
        let transport = InvitationTransport(try envelope(page))
        let client = SchoolInvitationClient(baseURL: base, tokenSource: InvitationToken(), transport: transport)
        let result = try await client.invitations(schoolID: school, cursor: "previous+cursor=")
        #expect(result.items == [expected])
        let request = try #require(await transport.recorded().first)
        #expect(request.httpMethod == "GET")
        let query = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query == [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "cursor", value: "previous+cursor=")])
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        // Masking a one-character local part adds three characters; the
        // projection need not have the email input's 254-character bound.
        #expect(SchoolInvitationClient.valid(InvitationFixture.invitation(email: "a***@" + String(repeating: "d", count: 252)), schoolID: school))
    }

    @Test func createUses201WithoutIfMatchAndRetriesTheOriginalBytes() async throws {
        let command = try createCommand()
        let transport = InvitationTransport(try envelope(InvitationFixture.invitation()), status: 201)
        let client = SchoolInvitationClient(baseURL: base, tokenSource: InvitationToken(), transport: transport)
        _ = try await client.send(command)
        _ = try await client.send(command)
        let requests = await transport.recorded()
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/schools/\(school.uuidString)/invitations")
            #expect(request.httpBody == command.body)
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
            #expect(request.value(forHTTPHeaderField: "If-Match") == nil)
        }
    }

    @Test func resendAndRevokeCarryExactTargetVersionAndOperation() async throws {
        let resend = try InvitationFixture.command()
        let id = UUID()
        let revoke = PendingSchoolCommand(id: id, scope: resend.scope, kind: .revokeInvitation,
            resourceVersion: 1, createdAt: Date(), body: try JSONEncoder().encode(
                SchoolRevokeInvitationCommand(operationId: id, reason: "Adresse erronée")), resourceID: resend.resourceID)
        for command in [resend, revoke] {
            let result = InvitationFixture.invitation(version: 2, status: command.kind == .revokeInvitation ? .revoked : .pending)
            let transport = InvitationTransport(try envelope(result))
            let client = SchoolInvitationClient(baseURL: base, tokenSource: InvitationToken(), transport: transport)
            #expect(try await client.send(command) == result)
            let request = try #require(await transport.recorded().first)
            let action = command.kind == .resendInvitation ? "resend" : "revoke"
            #expect(request.url?.path == "/v1/schools/\(school.uuidString)/invitations/\(InvitationFixture.invitationID.uuidString)/\(action)")
            #expect(request.httpBody == command.body)
            #expect(request.value(forHTTPHeaderField: "If-Match") == "\"1\"")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
        }
    }

    @Test func unsafeOriginRedirectAndWrongTargetOrVersionCannotConfirmACommand() async throws {
        let command = try InvitationFixture.command()
        let token = InvitationToken()
        let transport = InvitationTransport(try envelope(InvitationFixture.invitation(version: 2)))
        let unsafe = SchoolInvitationClient(baseURL: URL(string: "http://api.example.invalid")!, tokenSource: token, transport: transport)
        await #expect(throws: SchoolInvitationFailure.invalidResponse) { try await unsafe.invitations(schoolID: school, cursor: nil) }
        #expect(token.calls == 0)
        for result in [InvitationFixture.invitation(), InvitationFixture.invitation(id: UUID(), version: 2),
                       InvitationFixture.invitation(version: 2, status: .accepted)] {
            let client = SchoolInvitationClient(baseURL: base, tokenSource: token, transport: InvitationTransport(try envelope(result)))
            await #expect(throws: SchoolInvitationFailure.invalidResponse) { try await client.send(command) }
        }
        let redirect = SchoolInvitationClient(baseURL: base, tokenSource: token,
            transport: InvitationTransport(try envelope(InvitationFixture.invitation(version: 2)), responseURL: URL(string: "https://another.example.invalid")!))
        await #expect(throws: SchoolInvitationFailure.invalidResponse) { try await redirect.send(command) }
    }

    @Test func creationRejectsUnapprovedRolesForeignSchoolAndWrongSuccessStatus() async throws {
        let command = try createCommand()
        let foreign = SchoolInvitation(id: UUID(), schoolId: UUID(), version: 1, maskedEmail: "p***@example.invalid",
            roles: [.learner], status: .pending, expiresAt: ConfigurationFixture.timestamp)
        for result in [foreign, InvitationFixture.invitation(roles: [.admin])] {
            let client = SchoolInvitationClient(baseURL: base, tokenSource: InvitationToken(),
                transport: InvitationTransport(try envelope(result), status: 201))
            await #expect(throws: SchoolInvitationFailure.invalidResponse) { try await client.send(command) }
        }
        let wrongStatus = SchoolInvitationClient(baseURL: base, tokenSource: InvitationToken(),
            transport: InvitationTransport(try envelope(InvitationFixture.invitation()), status: 200))
        await #expect(throws: SchoolInvitationFailure.invalidResponse) { try await wrongStatus.send(command) }
    }

    @Test func mapsDocumentedBusinessErrorsWithoutTreatingDeliveryFailureAsRejection() async throws {
        let command = try createCommand()
        let cases: [(Int, String, SchoolInvitationFailure)] = [
            (409, "INVITATION_ALREADY_PENDING", .alreadyInvited), (409, "ALREADY_MEMBER", .alreadyMember),
            (409, "INVITATION_USED", .invitationUsed), (409, "INVITATION_REVOKED", .invitationRevoked),
            (409, "POLICY_REVIEW_REQUIRED", .policyRequired), (409, "SCHOOL_ARCHIVED", .schoolInactive),
            (412, "VERSION_CONFLICT", .conflict), (400, "INVALID_REQUEST", .rejected),
            (503, "INVITATION_DELIVERY_UNAVAILABLE", .unavailable), (409, "IDEMPOTENCY_MISMATCH", .pendingCommand),
            (403, "INVITATION_ROLE_FORBIDDEN", .forbidden)
        ]
        for (status, code, expected) in cases {
            let data = try JSONSerialization.data(withJSONObject: ["code": code])
            let client = SchoolInvitationClient(baseURL: base, tokenSource: InvitationToken(),
                transport: InvitationTransport(data, status: status, mediaType: "application/problem+json"))
            await #expect(throws: expected) { try await client.send(command) }
        }
        #expect(!SchoolInvitationFailure.unavailable.permitsCorrectionOfFreshRequest)
        #expect(!SchoolInvitationFailure.pendingCommand.permitsCorrectionOfFreshRequest)
    }

    @Test func receiptMustMatchOperationAndCommandResourceBeforeItCanReleasePendingWork() async throws {
        let command = try InvitationFixture.command()
        let receipt = InvitationFixture.receipt(command)
        let client = SchoolInvitationClient(baseURL: base, tokenSource: InvitationToken(), transport: InvitationTransport(try envelope(receipt)))
        let response = try await client.operation(schoolID: school, id: command.id)
        #expect(command.matches(response))
        #expect(!command.matches(InvitationFixture.receipt(command, resourceID: UUID())))
        await #expect(throws: SchoolInvitationFailure.invalidResponse) { try await client.operation(schoolID: school, id: UUID()) }
    }
}
