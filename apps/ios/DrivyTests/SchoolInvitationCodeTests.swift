import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolInvitationCodeTests {
    // MARK: Format

    @Test func codesAreNormalizedLikeTheServerAndFormattedWhileTyping() {
        #expect(SchoolInvitationCode.normalized(" k7q4-mx2p ") == "K7Q4MX2P")
        #expect(SchoolInvitationCode.normalized("K7Q4 MX2P") == "K7Q4MX2P")
        #expect(SchoolInvitationCode.normalized("K7Q4–MX2P") == "K7Q4MX2P")
        #expect(SchoolInvitationCode.normalized("K7Q4-MX2") == nil)
        #expect(SchoolInvitationCode.normalized("K7Q4-MX2PA") == nil)
        // Look-alikes are not part of the alphabet.
        #expect(SchoolInvitationCode.normalized("O7Q4-MX2P") == nil)
        #expect(SchoolInvitationCode.normalized("K7Q4-MX21") == nil)
        #expect(SchoolInvitationCode.normalized("K7Q4.MX2P") == nil)

        #expect(SchoolInvitationCode.formatted("k7q") == "K7Q")
        #expect(SchoolInvitationCode.formatted("k7q4") == "K7Q4")
        #expect(SchoolInvitationCode.formatted("K7Q4-") == "K7Q4")
        #expect(SchoolInvitationCode.formatted("k7q4m") == "K7Q4-M")
        #expect(SchoolInvitationCode.formatted("k7q4 mx2p") == "K7Q4-MX2P")
        #expect(SchoolInvitationCode.formatted("K7Q4-MX2PXYZ") == "K7Q4-MX2P")
        #expect(SchoolInvitationCode.formatted("é7q4") == "7Q4")

        #expect(SchoolInvitationCode.display("k7q4mx2p") == "K7Q4-MX2P")
        #expect(SchoolInvitationCode.display("k7q4") == nil)
        #expect(SchoolInvitationCode.isMistyped("K7Q4-MX21"))
        #expect(!SchoolInvitationCode.isMistyped("K7Q4-MX2"))
        #expect(!SchoolInvitationCode.isMistyped("K7Q4-MX2P"))
    }

    @Test func aCodeProjectionDecodesWithoutAddressAndAnOlderServerMeansEmail() throws {
        let code = Data("""
        {"id":"40000000-0000-4000-8000-000000000009","schoolId":"\(ConfigurationFixture.schoolID.uuidString)","version":1,
         "maskedEmail":null,"roles":["LEARNER"],"status":"PENDING","expiresAt":"2026-10-05T10:00:00Z",
         "delivery":"CODE","code":"K7Q4-MX2P"}
        """.utf8)
        let invitation = try JSONDecoder().decode(SchoolInvitation.self, from: code)
        #expect(invitation.isCode && invitation.maskedEmail == nil && invitation.code == "K7Q4-MX2P")
        #expect(SchoolInvitationClient.valid(invitation, schoolID: ConfigurationFixture.schoolID))
        #expect(invitation.withoutCode.code == nil)
        let legacy = Data("""
        {"id":"40000000-0000-4000-8000-000000000009","schoolId":"\(ConfigurationFixture.schoolID.uuidString)","version":1,
         "maskedEmail":"a***@example.invalid","roles":["LEARNER"],"status":"PENDING","expiresAt":"2026-10-05T10:00:00Z"}
        """.utf8)
        let email = try JSONDecoder().decode(SchoolInvitation.self, from: legacy)
        #expect(email.delivery == .email && SchoolInvitationClient.valid(email, schoolID: ConfigurationFixture.schoolID))
        // An e-mail invitation never carries a code; a malformed code is refused.
        var leaked = email; leaked.code = "K7Q4MX2P"
        #expect(!SchoolInvitationClient.valid(leaked, schoolID: ConfigurationFixture.schoolID))
        var malformed = invitation; malformed.code = "K7Q4-MX21"
        #expect(!SchoolInvitationClient.valid(malformed, schoolID: ConfigurationFixture.schoolID))
    }

    // MARK: Instructor

    private static func offering(_ category: String = "B") -> SchoolOffering {
        SchoolOffering(id: UUID(), schoolId: ConfigurationFixture.schoolID, version: 1, offeringKey: category,
            categoryCode: category, curriculumVersionId: UUID(), policyVersionId: UUID(), enabled: true,
            defaultDurationMinutes: 50, defaultPriceCents: 9000)
    }

    @Test func creatingACodeSendsDeliveryCodeWithTheTrainingAndSurfacesTheCodeOnce() async throws {
        let api = InvitationAPIStub()
        let offering = Self.offering()
        api.offeringValues = [offering]
        let outbox = ConfigurationOutboxStub()
        let model = InvitationFixture.workspace(api: api, roles: ["INSTRUCTOR"], outbox: outbox)
        await model.load()
        #expect(model.selectedOfferingID == offering.id && model.codeDraftIsValid)
        #expect(await model.createCode(offeringID: model.selectedOfferingID))
        let command = try #require(api.commands.last)
        #expect(command.kind == .createInvitation && command.resourceVersion == 0)
        // Stored encrypted before sending, released once confirmed.
        #expect(outbox.saves.first == command && outbox.value == nil)
        let body = try JSONDecoder().decode(SchoolInviteCommand.self, from: command.body)
        #expect(body.delivery == .code && body.email == nil && body.roles == [.learner])
        #expect(body.training == SchoolInvitationTraining(offeringId: offering.id, instructorMembershipId: ConfigurationFixture.membershipID))
        let raw = try #require(String(data: command.body, encoding: .utf8))
        #expect(raw.contains("\"delivery\":\"CODE\"") && !raw.contains("email"))
        #expect(model.issuedCode?.code == "K7Q4-MX2P")
        #expect(model.codeRecovery == nil)
        // The list never keeps the code.
        #expect(model.invitations.allSatisfy { $0.code == nil })
        model.dismissIssuedCode()
        #expect(model.issuedCode == nil)
    }

    @Test func withSeveralTrainingsTheInstructorMustChooseOne() async {
        let api = InvitationAPIStub()
        api.offeringValues = [Self.offering("B"), Self.offering("A")]
        let model = InvitationFixture.workspace(api: api, roles: ["INSTRUCTOR"])
        await model.load()
        #expect(model.selectedOfferingID == nil && !model.codeDraftIsValid)
        #expect(await model.createCode(offeringID: nil) == false)
        #expect(await model.createCode(offeringID: UUID()) == false)
        #expect(api.commands.isEmpty)
        model.selectedOfferingID = api.offeringValues[1].id
        #expect(await model.createCode(offeringID: model.selectedOfferingID))
    }

    @Test func aCodeAlwaysCarriesATrainingSoOnlyAnInstructorCreatesOne() async {
        let api = InvitationAPIStub()
        api.offeringValues = [Self.offering()]
        let admin = InvitationFixture.workspace(api: api, roles: ["ADMIN"])
        await admin.load()
        #expect(!admin.canCreateCode && !admin.codeDraftIsValid)
        #expect(await admin.createCode(offeringID: api.offeringValues[0].id) == false)
        api.offeringValues = []
        let instructor = InvitationFixture.workspace(api: api, roles: ["INSTRUCTOR"])
        await instructor.load()
        #expect(instructor.lacksOpenTraining && !instructor.codeDraftIsValid)
        #expect(api.commands.isEmpty)
    }

    @Test func aReplayedCreationWithoutCodeOffersANewCodeThroughResend() async throws {
        let api = InvitationAPIStub()
        api.creationCode = nil
        api.offeringValues = [Self.offering()]
        let model = InvitationFixture.workspace(api: api, roles: ["INSTRUCTOR"])
        await model.load()
        #expect(await model.createCode(offeringID: model.selectedOfferingID))
        #expect(model.issuedCode == nil)
        let recovery = try #require(model.codeRecovery)
        #expect(await model.renewRecoveredCode())
        let resend = try #require(api.commands.last)
        #expect(resend.kind == .resendInvitation && resend.resourceID == recovery.invitationID)
        #expect(resend.resourceVersion == recovery.version)
        #expect(model.issuedCode?.code == "M3N4-P5Q6" && model.issuedCode?.invitationID == recovery.invitationID)
        #expect(model.codeRecovery == nil)
    }

    @Test func aVerifiedCodeCreationKnowsOnlyTheInvitationAndOffersANewCode() async throws {
        let id = UUID()
        let command = PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: .createInvitation, resourceVersion: 0,
            createdAt: Date(), body: try JSONEncoder().encode(SchoolInviteCommand(operationId: id, delivery: .code, roles: [.learner])))
        let outbox = ConfigurationOutboxStub(value: command)
        let api = InvitationAPIStub()
        let created = UUID()
        api.receipt = SchoolOperationReceipt(operationId: id, commandType: "CREATE_INVITATION", resourceType: "Invitation",
            resourceId: created, committedAt: ConfigurationFixture.timestamp, resourceVersion: 1)
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        await model.verifyPending()
        #expect(outbox.value == nil)
        #expect(model.codeRecovery == SchoolCodeRecovery(invitationID: created, version: 1))
        #expect(model.issuedCode == nil && model.successMessage == nil)
    }

    @Test func renewingAListedCodeInvitationShowsTheNewCode() async throws {
        let api = InvitationAPIStub()
        let listed = InvitationFixture.codeInvitation(status: .expired)
        api.items = [listed]
        let model = InvitationFixture.workspace(api: api)
        await model.load()
        #expect(model.invitations.first?.isCode == true)
        #expect(await model.resendAfterConfirmation(try #require(model.invitations.first)))
        #expect(model.issuedCode?.code == "M3N4-P5Q6")
        #expect(model.invitations.first?.code == nil)
    }

    // MARK: Learner

    @Test func joiningByCodeSendsTheNormalizedCodeUnderOneOperation() async throws {
        let transport = CodeJoinTransport()
        let store = CodeJoinStoreStub()
        let model = SchoolCodeJoinWorkspace(client: CodeJoinFixture.client(transport), store: store)
        await model.load()
        #expect(model.isReady)
        model.code = SchoolInvitationCode.formatted("k7q4 mx2p")
        #expect(model.code == "K7Q4-MX2P" && model.canPreview)
        await model.inspect()
        #expect(model.preview?.schoolName == "Luc auto école" && model.preview?.trainingCategoryCode == "B")
        await model.accept()
        #expect(model.isConfirmed && model.member?.schoolId == CodeJoinFixture.schoolID)
        #expect(!model.trainingNotOpened)

        let requests = await transport.recorded()
        let preview = try #require(requests.first { $0.url?.path == "/v1/invitations/code/preview" })
        #expect(try JSONDecoder().decode([String: String].self, from: try #require(preview.httpBody)) == ["code": "K7Q4MX2P"])
        let accept = try #require(requests.first { $0.url?.path == "/v1/invitations/code/accept" })
        let body = try JSONDecoder().decode(SchoolJoinCodeBody.self, from: try #require(accept.httpBody))
        #expect(body.code == "K7Q4MX2P")
        #expect(accept.value(forHTTPHeaderField: "Idempotency-Key") == body.operationId.uuidString)
        #expect(accept.httpMethod == "POST")
        // Once joined, the stored intention no longer holds the code.
        #expect(store.record?.membership != nil && store.record?.body == nil)
    }

    @Test func anUncertainJoinIsKeptAndVerifiedWithTheSameRequest() async throws {
        let transport = CodeJoinTransport()
        await transport.setAcceptFailure(true)
        let store = CodeJoinStoreStub()
        let model = SchoolCodeJoinWorkspace(client: CodeJoinFixture.client(transport), store: store)
        await model.load()
        model.code = "K7Q4-MX2P"
        await model.inspect()
        await model.accept()
        #expect(model.isPending && model.errorMessage != nil)
        let kept = try #require(store.record)
        #expect(kept.membership == nil)

        // Reopened later: the same intention is shown, then verified.
        let reopened = SchoolCodeJoinWorkspace(client: CodeJoinFixture.client(transport), store: store)
        await reopened.load()
        #expect(reopened.isPending && !reopened.canPreview)
        await transport.setAcceptFailure(false)
        await reopened.verify()
        #expect(reopened.isConfirmed)
        let accepts = await transport.recorded().filter { $0.url?.path == "/v1/invitations/code/accept" }
        #expect(accepts.count == 2)
        #expect(accepts[0].httpBody == accepts[1].httpBody)
        #expect(accepts[0].value(forHTTPHeaderField: "Idempotency-Key") == accepts[1].value(forHTTPHeaderField: "Idempotency-Key"))
    }

    @Test func aTrainingTheSchoolCouldNotOpenIsAnnounced() async throws {
        let transport = CodeJoinTransport()
        await transport.setTrainingOpened(false)
        let model = SchoolCodeJoinWorkspace(client: CodeJoinFixture.client(transport), store: CodeJoinStoreStub())
        await model.load()
        model.code = "K7Q4-MX2P"
        await model.inspect()
        await model.accept()
        #expect(model.isConfirmed && model.trainingNotOpened)
    }

    @Test func aRefusedCodeIsExplainedAndNothingStaysPending() async throws {
        let transport = CodeJoinTransport()
        await transport.setPreviewProblem(404, code: "INVITATION_CODE_INVALID")
        let store = CodeJoinStoreStub()
        let model = SchoolCodeJoinWorkspace(client: CodeJoinFixture.client(transport), store: store)
        await model.load()
        model.code = "K7Q4-MX2P"
        await model.inspect()
        #expect(model.preview == nil && model.errorMessage == SchoolJoinFailure.invalidCode.codeMessage)
        #expect(store.record == nil)
        await transport.setPreviewProblem(429, code: "INVITATION_CODE_ATTEMPTS")
        await model.inspect()
        #expect(model.errorMessage == SchoolJoinFailure.codeAttempts.codeMessage)
    }
}

// MARK: Support

enum CodeJoinFixture {
    static let schoolID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    static let membershipID = UUID(uuidString: "50000000-0000-4000-8000-000000000002")!
    static let configuration = AppConfiguration(apiBaseURL: URL(string: "https://api.example.test")!,
        issuer: URL(string: "https://id.example.test")!, clientID: "drivy-ios-tests", redirectURL: AppConfiguration.callback)
    @MainActor static func client(_ transport: CodeJoinTransport) -> SchoolJoinClient {
        SchoolJoinClient(configuration: configuration, tokenSource: CodeJoinToken(), transport: transport)
    }
}

@MainActor
final class CodeJoinToken: AccessTokenSource {
    func accessToken() async throws -> String {
        let claims = Data(#"{"iss":"https://id.example.test","sub":"synthetic-learner"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "eyJhbGciOiJub25lIn0.\(claims).c3ludGhldGlj"
    }
}

@MainActor
final class CodeJoinStoreStub: SchoolCodeJoinStore {
    var record: SchoolCodeJoinRecord?
    func load(for principal: SchoolJoinPrincipal) throws -> SchoolCodeJoinRecord? { record?.principal == principal ? record : nil }
    func save(_ record: SchoolCodeJoinRecord) throws {
        if let existing = self.record, existing.operationID != record.operationID, existing.membership == nil { throw SchoolJoinFailure.pending }
        self.record = record
    }
    func remove(_ record: SchoolCodeJoinRecord) throws { self.record = nil }
}

actor CodeJoinTransport: SchoolHTTPTransport {
    private var requests: [URLRequest] = []
    private var acceptFails = false
    private var trainingOpened: Bool?
    private var previewProblem: (status: Int, code: String)?

    func setAcceptFailure(_ value: Bool) { acceptFails = value }
    func setTrainingOpened(_ value: Bool?) { trainingOpened = value }
    func setPreviewProblem(_ status: Int, code: String) { previewProblem = (status, code) }
    func recorded() -> [URLRequest] { requests }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        let url = request.url!
        switch url.path {
        case "/v1/invitations/code/preview":
            if let previewProblem { return problem(url, status: previewProblem.status, code: previewProblem.code) }
            return try envelope(url, status: 200, data: ["schoolName": "Luc auto école", "roles": ["LEARNER"],
                "trainingCategoryCode": "B", "expiresAt": "2026-10-06T10:00:00Z"])
        case "/v1/me":
            // A brand-new account belongs to no school yet.
            return problem(url, status: 403, code: "IDENTITY_NOT_LINKED")
        case "/v1/invitations/code/accept":
            if acceptFails { throw URLError(.networkConnectionLost) }
            var member: [String: Any] = ["membershipId": CodeJoinFixture.membershipID.uuidString,
                "schoolId": CodeJoinFixture.schoolID.uuidString, "schoolName": "Luc auto école", "roles": ["LEARNER"],
                "grants": [String](), "accessEpoch": 1]
            if let trainingOpened { member["trainingOpened"] = trainingOpened }
            return try envelope(url, status: 201, data: member)
        default:
            return problem(url, status: 404, code: "NOT_FOUND")
        }
    }

    private func envelope(_ url: URL, status: Int, data: [String: Any]) throws -> SchoolHTTPResponse {
        let body = try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
            "serverTime": "2026-09-29T10:00:00Z"])
        return SchoolHTTPResponse(data: body, status: status, url: url, contentType: "application/json")
    }

    private func problem(_ url: URL, status: Int, code: String) -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\"}".utf8), status: status, url: url,
            contentType: "application/problem+json")
    }
}
