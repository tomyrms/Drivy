import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolJoinIdentityTests {
    @Test func authenticatedPreviewsKeepStructuredNamesAndReadOlderResponses() async throws {
        for identity in [SchoolJoinProfileIdentity(firstName: "Anne-Marie", lastName: "de la Côte"), nil] as [SchoolJoinProfileIdentity?] {
            let code = SchoolCodePreview(schoolName: "École exemple", roles: ["LEARNER"], trainingCategoryCode: "B",
                expiresAt: "2026-10-22T10:00:00Z", profileIdentity: identity)
            let link = SchoolJoinPreview(invitationId: UUID(), schoolId: UUID(), schoolName: "École exemple",
                roles: ["LEARNER"], maskedEmail: "a***@example.invalid", expiresAt: "2026-10-22T10:00:00Z",
                notice: .init(version: 1, noticeText: "Notice de test", retentionText: "Conservation de test",
                    contactEmail: "ecole@example.invalid"), profileIdentity: identity)
            let transport = try JoinIdentityPreviewTransport(code: code, link: link)
            let client = SchoolJoinClient(configuration: CodeJoinFixture.configuration, tokenSource: CodeJoinToken(), transport: transport)
            let principal = try await client.principal()
            let codeResult = try await client.previewCode("K7Q4MX2P", principal: principal)
            let linkResult = try await client.preview(token: String(repeating: "a", count: 43), principal: principal)
            #expect(codeResult.profileIdentity == identity)
            #expect(linkResult.profileIdentity == identity)
            #expect(codeResult.profileIdentity?.fullName == identity.map { "\($0.firstName) \($0.lastName)" })
            // Les journaux chiffrés anciens, sans identité de compte, restent décodables.
            #expect(try JSONDecoder().decode(SchoolCodePreview.self, from: JSONEncoder().encode(code)) == code)
            #expect(try JSONDecoder().decode(SchoolJoinPreview.self, from: JSONEncoder().encode(link)) == link)
        }
    }

    @Test func malformedStructuredNamesAreRejectedBeforeJoining() async throws {
        for name in [" ", "Camille\nAutre", String(repeating: "a", count: 151)] {
            let identity = SchoolJoinProfileIdentity(firstName: name, lastName: "Test")
            let code = SchoolCodePreview(schoolName: "École exemple", roles: ["LEARNER"], trainingCategoryCode: nil,
                expiresAt: "2026-10-22T10:00:00Z", profileIdentity: identity)
            let link = SchoolJoinPreview(invitationId: UUID(), schoolId: UUID(), schoolName: "École exemple",
                roles: ["LEARNER"], maskedEmail: "a***@example.invalid", expiresAt: "2026-10-22T10:00:00Z",
                notice: .init(version: 1, noticeText: "Notice de test", retentionText: "Conservation de test",
                    contactEmail: "ecole@example.invalid"), profileIdentity: identity)
            let client = SchoolJoinClient(configuration: CodeJoinFixture.configuration, tokenSource: CodeJoinToken(),
                transport: try JoinIdentityPreviewTransport(code: code, link: link))
            let principal = try await client.principal()
            await #expect(throws: SchoolJoinFailure.invalidResponse) { try await client.previewCode("K7Q4MX2P", principal: principal) }
            await #expect(throws: SchoolJoinFailure.invalidResponse) {
                try await client.preview(token: String(repeating: "a", count: 43), principal: principal)
            }
        }
    }
}

private actor JoinIdentityPreviewTransport: SchoolHTTPTransport {
    let code: Data
    let link: Data

    init(code: SchoolCodePreview, link: SchoolJoinPreview) throws {
        self.code = try JSONEncoder().encode(Envelope(data: code))
        self.link = try JSONEncoder().encode(Envelope(data: link))
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = try #require(request.url)
        return .init(data: url.path.contains("/code/") ? code : link, status: 200, url: url, contentType: "application/json")
    }

    private struct Envelope<Value: Encodable>: Encodable {
        let data: Value
        let serverTime = "2026-10-17T10:00:00Z"
    }
}
