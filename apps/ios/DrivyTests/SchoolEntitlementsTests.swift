import Foundation
import Testing
@testable import Drivy

// Droits commerciaux de l’école aux modules (R01-T03, #455). Écrits sans toolchain Swift ni exécution : à compiler et
// exécuter sur le runner Apple (règle du porteur : aucun test avant la fin de l’epic).

private let firstSchool = UUID(uuidString: "10000000-0000-4000-8000-0000000000a1")!
private let secondSchool = UUID(uuidString: "10000000-0000-4000-8000-0000000000a2")!
private let base = URL(string: "https://api.example.invalid")!

private func projection(courses: Bool = true, messaging: Bool = true, version: Int = 2,
                        next: String? = nil, state: String = "OFFER_ACTIVE") -> SchoolEntitlements {
    SchoolEntitlements(state: state,
        modules: [.init(code: "MESSAGING", entitled: messaging), .init(code: "COLLECTIVE_COURSES", entitled: courses)],
        version: version, nextChangeAt: next, computedAt: "2026-11-15T10:00:00.000Z")
}

private func envelope(_ data: String) -> Data {
    Data("{\"data\":\(data),\"requestId\":\"req-1\",\"serverTime\":\"2026-11-15T10:00:00.000Z\"}".utf8)
}

private let wire = """
{"state":"OFFER_ACTIVE","modules":[{"code":"MESSAGING","entitled":true},{"code":"COLLECTIVE_COURSES","entitled":false}],"version":3,"nextChangeAt":"2026-12-01T08:00:00.000Z","computedAt":"2026-11-15T10:00:00.000Z"}
"""

@MainActor
private final class EntitlementsToken: AccessTokenSource {
    func accessToken() async throws -> String { "opaque-unit-test-token" }
}

private actor EntitlementsTransport: SchoolHTTPTransport {
    let data: Data
    let status: Int
    private var requests: [URLRequest] = []
    init(data: Data, status: Int = 200) { self.data = data; self.status = status }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        return SchoolHTTPResponse(data: data, status: status, url: request.url!,
                                  contentType: status == 200 ? "application/json; charset=utf-8" : "application/problem+json")
    }
    func recordedRequests() -> [URLRequest] { requests }
}

/// Source de droits pilotable ; sans gestionnaire, elle répond comme une API plus ancienne (404).
@MainActor
private final class EntitlementsSource: SchoolEntitlementsReading {
    var handler: ((UUID) async throws -> SchoolEntitlements)?
    var calls: [UUID] = []
    func entitlements(schoolID: UUID) async throws -> SchoolEntitlements {
        calls.append(schoolID)
        guard let handler else { throw SchoolAPIError.notFound }
        return try await handler(schoolID)
    }
}

/// Point de passage d’une lecture en vol, pour rendre sa réponse après un changement d’école.
@MainActor
private final class EntitlementsGate {
    private var continuation: CheckedContinuation<SchoolEntitlements, any Error>?
    private var requested: CheckedContinuation<Void, Never>?
    func value() async throws -> SchoolEntitlements {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            requested?.resume()
            requested = nil
        }
    }
    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { requested = $0 }
    }
    func succeed(_ value: SchoolEntitlements) { continuation?.resume(returning: value); continuation = nil }
}

/// Doublure minimale de `SchoolAPI` : ne sait pas lire les droits (le protocole n’est pas étendu).
@MainActor
private final class EntitlementsAPIStub: SchoolAPI {
    let person: SchoolPerson
    init(memberships: [SchoolMembership]) {
        person = SchoolPerson(personId: UUID(), version: 1, displayName: "Compte de test", locale: "fr", memberships: memberships)
    }
    func me() async throws -> SchoolPerson { person }
    func school(id: UUID) async throws -> SchoolDetails {
        SchoolDetails(id: id, schoolId: id, version: 1, name: "École de test", timeZone: "Europe/Zurich", status: "ACTIVE",
            contactEmail: "ecole@example.test", contactPhone: nil, logoAssetId: nil,
            modules: .init(gpsEnabled: true, packsEnabled: false, collectiveCoursesEnabled: true, courseOffersVisibleByDefault: false),
            configurationVersion: 1)
    }
    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> {
        .init(items: [], nextCursor: nil)
    }
    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner { throw SchoolAPIError.notFound }
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining> {
        .init(items: [], nextCursor: nil)
    }
    func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining { throw SchoolAPIError.notFound }
}

private func membership(_ school: UUID, name: String = "École test") -> SchoolMembership {
    SchoolMembership(membershipId: UUID(), schoolId: school, schoolName: name, roles: ["ADMIN"], grants: [], accessEpoch: 1)
}

@MainActor
struct SchoolEntitlementsTests {
    // MARK: Modèle

    @Test func decodesTheServerProjectionAndNamesWhatIsClosed() throws {
        let value = try JSONDecoder().decode(SchoolEntitlements.self, from: Data(wire.utf8))
        #expect(value.isWellFormed)
        #expect(value.state == "OFFER_ACTIVE" && value.version == 3)
        #expect(value.isEntitled(.messaging))
        #expect(!value.isEntitled(.collectiveCourses))
        #expect(value.nextChangeDate != nil)
    }

    @Test func aModuleTheReadDoesNotMentionIsNeverClosedByTheApp() {
        let silent = SchoolEntitlements(state: "NOT_CONFIGURED", modules: [], version: 1, nextChangeAt: nil,
                                        computedAt: "2026-11-15T10:00:00Z")
        #expect(silent.isWellFormed)
        for module in SchoolModuleCode.allCases { #expect(silent.isEntitled(module)) }
        let unknown = SchoolEntitlements(state: "OFFER_ACTIVE", modules: [.init(code: "FUTURE_MODULE", entitled: false)],
                                         version: 1, nextChangeAt: nil, computedAt: "2026-11-15T10:00:00Z")
        for module in SchoolModuleCode.allCases { #expect(unknown.isEntitled(module)) }
    }

    @Test func refusesImplausibleProjections() {
        #expect(!SchoolEntitlements(state: "OFFER_ACTIVE", modules: [], version: 0, nextChangeAt: nil,
                                    computedAt: "2026-11-15T10:00:00Z").isWellFormed)
        #expect(!SchoolEntitlements(state: "", modules: [], version: 1, nextChangeAt: nil,
                                    computedAt: "2026-11-15T10:00:00Z").isWellFormed)
        #expect(!SchoolEntitlements(state: "OFFER_ACTIVE", modules: [], version: 1, nextChangeAt: nil,
                                    computedAt: "hier").isWellFormed)
        #expect(!SchoolEntitlements(state: "OFFER_ACTIVE", modules: [], version: 1, nextChangeAt: "demain",
                                    computedAt: "2026-11-15T10:00:00Z").isWellFormed)
        #expect(!SchoolEntitlements(state: "OFFER_ACTIVE",
            modules: [.init(code: "MESSAGING", entitled: true), .init(code: "MESSAGING", entitled: false)],
            version: 1, nextChangeAt: nil, computedAt: "2026-11-15T10:00:00Z").isWellFormed)
    }

    // MARK: Cadence de relecture

    @Test func aReadIsDueWhenNeverDoneOldOrWhenItsAnnouncedChangeArrived() {
        let readAt = Date(timeIntervalSince1970: 1_800_000_000)
        let steady = projection()
        #expect(SchoolEntitlementsPolicy.isDue(readAt: nil, projection: nil, now: readAt))
        #expect(SchoolEntitlementsPolicy.isDue(readAt: nil, projection: steady, now: readAt))
        #expect(!SchoolEntitlementsPolicy.isDue(readAt: readAt, projection: steady, now: readAt.addingTimeInterval(60)))
        #expect(SchoolEntitlementsPolicy.isDue(readAt: readAt, projection: steady, now: readAt.addingTimeInterval(301)))
        #expect(SchoolEntitlementsPolicy.isDue(readAt: readAt, projection: steady, now: readAt, minimumInterval: 0))
        // Une attribution programmée prend effet : la lecture fraîche mais périmée est relue sans attendre cinq minutes.
        let scheduled = projection(next: "2026-11-15T10:00:30.000Z")
        let scheduledAt = SchoolLesson.date("2026-11-15T10:00:00.000Z")!
        #expect(!SchoolEntitlementsPolicy.isDue(readAt: scheduledAt, projection: scheduled, now: scheduledAt.addingTimeInterval(10)))
        #expect(SchoolEntitlementsPolicy.isDue(readAt: scheduledAt, projection: scheduled, now: scheduledAt.addingTimeInterval(31)))
    }

    // MARK: Client

    @Test func theClientReadsTheSchoolRouteWithTheBearerAndNeverCaches() async throws {
        let transport = EntitlementsTransport(data: envelope(wire))
        let client = DrivyAPIClient(baseURL: base, tokenSource: EntitlementsToken(), transport: transport)
        let value = try await client.entitlements(schoolID: firstSchool)
        #expect(!value.isEntitled(.collectiveCourses))
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/schools/\(firstSchool.uuidString)/entitlements")
        #expect(request.httpMethod == "GET" && request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer opaque-unit-test-token")
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
    }

    @Test func theClientRefusesAnImplausibleAnswerAndNamesAnOlderApi() async throws {
        let invalid = envelope("{\"state\":\"OFFER_ACTIVE\",\"modules\":[],\"version\":0,\"nextChangeAt\":null,\"computedAt\":\"2026-11-15T10:00:00.000Z\"}")
        let client = DrivyAPIClient(baseURL: base, tokenSource: EntitlementsToken(), transport: EntitlementsTransport(data: invalid))
        await #expect(throws: SchoolAPIError.invalidResponse) { try await client.entitlements(schoolID: firstSchool) }
        let older = DrivyAPIClient(baseURL: base, tokenSource: EntitlementsToken(),
            transport: EntitlementsTransport(data: Data("{\"code\":\"NOT_FOUND\"}".utf8), status: 404))
        await #expect(throws: SchoolAPIError.notFound) { try await older.entitlements(schoolID: firstSchool) }
    }

    // MARK: Espace de travail

    @Test func withoutAReadingNothingIsClosedByTheDisplay() async {
        let api = EntitlementsAPIStub(memberships: [membership(firstSchool)])
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        #expect(workspace.entitlements == nil)
        for module in SchoolModuleCode.allCases { #expect(workspace.isEntitled(module)) }
    }

    @Test func theSchoolRightsAreReadOnEntryAndClosedModulesAreReported() async {
        let api = EntitlementsAPIStub(memberships: [membership(firstSchool)])
        let source = EntitlementsSource()
        source.handler = { _ in projection(courses: false) }
        let workspace = SchoolWorkspace(api: api, entitlementsSource: source)
        await workspace.loadAccount()
        #expect(source.calls == [firstSchool])
        #expect(workspace.isEntitled(.messaging))
        #expect(!workspace.isEntitled(.collectiveCourses))
    }

    @Test func aFailureKeepsTheLastProjectionAndNeverTouchesTheAccount() async {
        let api = EntitlementsAPIStub(memberships: [membership(firstSchool)])
        let source = EntitlementsSource()
        source.handler = { _ in projection(courses: false) }
        let workspace = SchoolWorkspace(api: api, entitlementsSource: source)
        await workspace.loadAccount()
        let known = workspace.entitlements
        let failures: [SchoolAPIError] = [.unavailable, .notFound, .forbidden, .unauthorized, .invalidResponse]
        for failure in failures {
            source.handler = { _ in throw failure }
            await workspace.refreshEntitlements(minimumInterval: 0)
            #expect(workspace.entitlements == known)
            #expect(!workspace.accessRevoked && !workspace.requiresAuthentication && workspace.person != nil)
        }
    }

    @Test func aRestoredModuleReopensTheEntriesAtTheNextDueReading() async {
        let api = EntitlementsAPIStub(memberships: [membership(firstSchool)])
        let source = EntitlementsSource()
        source.handler = { _ in projection(courses: false, version: 2) }
        let workspace = SchoolWorkspace(api: api, entitlementsSource: source)
        await workspace.loadAccount()
        #expect(!workspace.isEntitled(.collectiveCourses))
        let reads = source.calls.count
        // Une relecture récente n’en lance pas une autre.
        await workspace.refreshEntitlements()
        #expect(source.calls.count == reads)
        source.handler = { _ in projection(courses: true, version: 3) }
        await workspace.refreshEntitlements(now: Date().addingTimeInterval(301))
        #expect(source.calls.count == reads + 1)
        #expect(workspace.isEntitled(.collectiveCourses) && workspace.entitlements?.version == 3)
    }

    @Test func leavingTheSchoolDropsItsRights() async {
        let api = EntitlementsAPIStub(memberships: [membership(firstSchool)])
        let source = EntitlementsSource()
        source.handler = { _ in projection(courses: false) }
        let workspace = SchoolWorkspace(api: api, entitlementsSource: source)
        await workspace.loadAccount()
        #expect(workspace.entitlements != nil)
        workspace.leaveSchool()
        #expect(workspace.entitlements == nil)
        for module in SchoolModuleCode.allCases { #expect(workspace.isEntitled(module)) }
    }

    @Test func aLateAnswerFromTheSchoolLeftNeverReachesTheNextOne() async {
        let first = membership(firstSchool, name: "École A"), second = membership(secondSchool, name: "École B")
        let api = EntitlementsAPIStub(memberships: [first, second])
        let source = EntitlementsSource()
        let gate = EntitlementsGate()
        source.handler = { id in
            if id == firstSchool { return try await gate.value() }
            return projection(courses: true, messaging: true, version: 7)
        }
        let workspace = SchoolWorkspace(api: api, entitlementsSource: source)
        await workspace.loadAccount()
        let pending = Task { await workspace.selectSchool(first) }
        await gate.waitUntilRequested()
        await workspace.selectSchool(second)
        gate.succeed(projection(courses: false, messaging: false, version: 99))
        await pending.value
        #expect(workspace.membership?.schoolId == secondSchool)
        #expect(workspace.entitlements?.version == 7)
        #expect(workspace.isEntitled(.collectiveCourses) && workspace.isEntitled(.messaging))
    }
}
