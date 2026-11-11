import Foundation
import Testing
@testable import Drivy

/// #131, matrice I39 « être prévenu des prochaines sessions » : l'écriture du suivi d'un type de cours, sans réseau.
/// Ce que le client envoie (méthode, chemin, aucun corps ni clé d'idempotence : la clé naturelle est le type), et le fait
/// qu'un état affiché n'est jamais celui que l'école n'a pas dit.
@MainActor struct SchoolCourseFollow131Tests {
    private let schoolID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let typeID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private func client(_ transport: FollowRecordingTransport) -> SchoolCourseClient {
        SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: transport)
    }

    @Test func followingIsAPutOnTheTypeWithoutBodyOrIdempotencyKey() async throws {
        let transport = FollowRecordingTransport(replyTypeID: typeID, replyFollowing: true)
        let result = try await client(transport).setFollow(schoolID: schoolID, typeID: typeID, following: true)
        #expect(result == true)
        let sent = await transport.requests
        #expect(sent.count == 1)
        #expect(sent[0].httpMethod == "PUT")
        #expect(sent[0].url?.path.hasSuffix("/course-follows/me/\(typeID.uuidString)") == true)
        #expect(sent[0].httpBody == nil)
        #expect(sent[0].value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }

    @Test func unfollowingIsAPostOnTheUnfollowRoute() async throws {
        let transport = FollowRecordingTransport(replyTypeID: typeID, replyFollowing: false)
        let result = try await client(transport).setFollow(schoolID: schoolID, typeID: typeID, following: false)
        #expect(result == false)
        let sent = await transport.requests
        #expect(sent.count == 1)
        #expect(sent[0].httpMethod == "POST")
        #expect(sent[0].url?.path.hasSuffix("/course-follows/me/\(typeID.uuidString)/unfollow") == true)
    }

    @Test func aReplyAboutAnotherTypeOrTheOppositeStateIsNeverTakenAsTheAnswer() async {
        for transport in [FollowRecordingTransport(replyTypeID: UUID(), replyFollowing: true),
                          FollowRecordingTransport(replyTypeID: typeID, replyFollowing: false)] {
            var failed = false
            do { _ = try await client(transport).setFollow(schoolID: schoolID, typeID: typeID, following: true) } catch { failed = true }
            #expect(failed)
        }
    }

    @Test func aFailedWriteThrowsInsteadOfClaimingTheNewState() async {
        let transport = FollowRecordingTransport(replyTypeID: typeID, replyFollowing: true, failing: true)
        var failed = false
        do { _ = try await client(transport).setFollow(schoolID: schoolID, typeID: typeID, following: true) } catch { failed = true }
        #expect(failed)
    }

    @Test func theFollowedTypesAreReadFromTheSchoolAndNeverGuessed() async throws {
        let other = UUID()
        let transport = FollowRecordingTransport(replyTypeID: typeID, replyFollowing: true, followed: [typeID, other])
        let types = try await client(transport).follows(schoolID: schoolID)
        #expect(types == Set([typeID, other]))
        let sent = await transport.requests
        #expect(sent.count == 1 && sent[0].httpMethod == "GET")
        #expect(sent[0].url?.path.hasSuffix("/course-follows/me") == true)
    }
}

private actor FollowRecordingTransport: SchoolHTTPTransport {
    let replyTypeID: UUID
    let replyFollowing: Bool
    let failing: Bool
    let followed: [UUID]
    private(set) var requests: [URLRequest] = []
    init(replyTypeID: UUID, replyFollowing: Bool, failing: Bool = false, followed: [UUID] = []) {
        self.replyTypeID = replyTypeID; self.replyFollowing = replyFollowing; self.failing = failing; self.followed = followed
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        if failing { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        let data: Any = (request.httpMethod ?? "GET") == "GET"
            ? ["typeIds": followed.map(\.uuidString)]
            : ["typeId": replyTypeID.uuidString, "following": replyFollowing]
        let body: [String: Any] = ["data": data, "requestId": "course-follow", "serverTime": "2030-03-10T08:00:00Z"]
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: body), status: 200, url: url, contentType: "application/json")
    }
}
