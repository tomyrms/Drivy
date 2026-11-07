import Foundation
import Testing
@testable import Drivy

/// Refus explicite d’accès à un cours (#426) : la feuille et les inscrits sont purgés, une panne transitoire garde le contenu
/// autorisé, une réponse partie avant le refus ne remet rien, et une lecture autorisée rend l’écran. Serveurs synthétiques.
@MainActor struct SchoolCourseAccessRevocationTests {
    private let schoolID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let seriesID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let occurrence = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    private let personID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    private let membershipID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    private let first = CourseSheetServer.first

    private func scope() -> SchoolCommandScope {
        SchoolCommandScope(personID: personID, schoolID: schoolID, membershipID: membershipID, accessEpoch: 1,
            apiBaseURL: "https://school.example.test")
    }

    private func workspace(_ server: CourseSheetServer, store: SchoolCourseIntentMemoryStore? = nil) async -> SchoolCourseAttendanceWorkspace {
        let client = SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: server)
        let model = SchoolCourseAttendanceWorkspace(schoolID: schoolID, seriesID: seriesID, timeZone: "Europe/Zurich", client: client,
            persistence: store.map { SchoolCourseIntentPersistence(store: $0, scope: scope()) })
        await model.load()
        return model
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(200)) }

    private func expectPurged(_ model: SchoolCourseAttendanceWorkspace) {
        #expect(model.sheet == nil && model.rows.isEmpty && model.rights == nil && model.occurrence == nil)
        #expect(SchoolCourseParticipantMode.available(model.rights).isEmpty)
        #expect(model.lanes.isEmpty && model.notices.isEmpty && model.announcement == nil)
        #expect(model.accessRevoked && model.errorMessage != nil)
    }

    // MARK: Feuille d’appel et règlements

    @Test func anExplicitRefusalRemovesNamesMarksPaymentsRightsAndPendingProjection() async throws {
        for status in [401, 403, 404] {
            let server = CourseSheetServer()
            let model = await workspace(server)
            try #require(model.rows.count == 2 && model.rights?.canRecordPayment == true)
            // Une demande en cours : sa projection (règlement saisi) part avec la feuille.
            await server.hold(first)
            model.submit(.payment(enrollmentID: first, amountCents: 8000), learnerName: "Alex")
            await eventually { model.isSending }
            await server.denyReads(status)
            await model.load()
            expectPurged(model)
            // Plus aucune action : rien ne part sous des droits retirés.
            let sent = await server.keys.count
            model.submit(.attendance(enrollmentID: first, occurrenceID: occurrence, status: .present, expectedVersion: nil), learnerName: "Alex")
            model.retry(first)
            model.abandon(first)
            await settle()
            #expect(model.lanes.isEmpty && model.sheet == nil && model.announcement == nil)
            #expect(await server.keys.count == sent)
            await server.release()
            await settle()
            // La réponse de la demande partie avant le refus ne remet ni feuille ni annonce.
            #expect(model.sheet == nil && model.lanes.isEmpty && model.announcement == nil && model.accessRevoked)
        }
    }

    @Test func aTransientOutageKeepsTheAuthorisedSheetAndIsNotARefusal() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.outage(true)
        await model.load()
        #expect(model.rows.count == 2 && model.rights?.canRecordPayment == true)
        #expect(model.errorMessage != nil && !model.accessRevoked)
        await server.outage(false)
        await model.load()
        #expect(model.errorMessage == nil && model.rows.count == 2)
    }

    @Test func aReadSentBeforeTheRefusalCannotBringTheSheetBack() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.holdReads()
        let stale = Task { await model.load() }
        defer { stale.cancel(); Task { await server.releaseReads() } }
        try await HubFixture.wait { await server.heldReads == 1 }
        // Le refus arrive par une écriture pendant que l’ancienne lecture est encore en vol.
        await server.denyWrites(403)
        model.submit(.attendance(enrollmentID: first, occurrenceID: occurrence, status: .present, expectedVersion: nil), learnerName: "Alex")
        await eventually { model.accessRevoked }
        expectPurged(model)
        await server.releaseReads()
        await stale.value
        expectPurged(model)
    }

    @Test func accessGivenBackByANewAuthorisedReadReopensTheSheet() async throws {
        let server = CourseSheetServer()
        let model = await workspace(server)
        await server.denyReads(403)
        await model.load()
        expectPurged(model)
        await server.denyReads(nil)
        await model.load()
        #expect(!model.accessRevoked && model.errorMessage == nil)
        #expect(model.rows.count == 2 && model.rights?.canTakeAttendance == true && model.occurrence != nil)
        model.submit(.attendance(enrollmentID: first, occurrenceID: occurrence, status: .present, expectedVersion: nil), learnerName: "Alex")
        await eventually { model.lanes.isEmpty }
        #expect(model.rows.first { $0.enrollmentId == first }?.mark(occurrence)?.status == .present)
    }

    @Test func aDurablePaymentSurvivesTheRefusalWithoutBeingSentAgainBeforeTheRightsReturn() async throws {
        let server = CourseSheetServer(), store = SchoolCourseIntentMemoryStore()
        let model = await workspace(server, store: store)
        await server.denyWrites(403)
        model.submit(.payment(enrollmentID: first, amountCents: 8000), learnerName: "Alex")
        await eventually { model.accessRevoked }
        expectPurged(model)
        // L’intention financière reste dans le coffre de l’appareil, hors de l’écran.
        let kept = try #require(try store.commands(scope: scope(), seriesID: seriesID).first)
        #expect(kept.kind == .courseSheetIntent && kept.resourceID == first)
        let attempts = await server.keys.count
        await settle()
        #expect(await server.keys.count == attempts)

        // Droits rendus : elle revient « à reprendre », jamais renvoyée d’elle-même, puis rejouée avec la même opération.
        await server.denyWrites(nil)
        await model.load()
        let row = try #require(model.rows.first { $0.enrollmentId == first })
        let pending = try #require(model.unconfirmed(row))
        #expect(pending.intent.id == kept.id && model.hasUnconfirmed && !model.isSending)
        await settle()
        #expect(await server.keys.count == attempts)
        model.retry(first)
        await eventually { model.lanes.isEmpty }
        #expect(await server.keys.last == kept.id.uuidString)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
        #expect(model.rows.first { $0.enrollmentId == first }?.payments.map(\.amountCents) == [8000])
    }

    // MARK: Inscrits

    private func rosterWorkspace(_ transport: RosterServer, learners: [SchoolLearner] = []) -> SchoolCourseRosterWorkspace {
        let client = SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: transport)
        return SchoolCourseRosterWorkspace(schoolID: schoolID, seriesID: seriesID, client: client, learners: learners)
    }

    private func learner(_ name: String) -> SchoolLearner {
        SchoolLearner(id: UUID(), schoolId: schoolID, personId: UUID(), version: 1, displayName: name, contactEmail: nil,
            contactPhone: nil, archivedAt: nil, profileReadiness: nil, profilePhotoDocumentId: nil)
    }

    @Test func anExplicitRefusalRemovesTheRosterItsConfirmationAndTheProposedLearners() async throws {
        for status in [401, 403, 404] {
            let server = RosterServer(seriesID: seriesID)
            let model = rosterWorkspace(server, learners: [learner("Zoé Exemple")])
            await model.load()
            try #require(model.roster?.active.count == 1)
            await server.deny(status)
            await model.load()
            #expect(model.roster == nil && model.candidates.isEmpty && model.confirmation == nil)
            #expect(model.accessRevoked && model.errorMessage != nil)
            // Aucune action ne part sous des droits retirés.
            let writes = await server.writes
            #expect(await model.enroll(learner("Autre")) == false)
            #expect(await server.writes == writes)
        }
    }

    @Test func aTransientOutageKeepsTheRosterAndSaysSo() async throws {
        let server = RosterServer(seriesID: seriesID)
        let model = rosterWorkspace(server)
        await model.load()
        await server.deny(503)
        await model.load()
        #expect(model.roster?.active.count == 1 && model.errorMessage != nil && !model.accessRevoked)
    }

    @Test func aRosterReadSentBeforeTheRefusalCannotBringTheRosterBack() async throws {
        let server = RosterServer(seriesID: seriesID)
        let model = rosterWorkspace(server, learners: [learner("Zoé Exemple")])
        await model.load()
        await server.holdReads()
        let stale = Task { await model.load() }
        defer { stale.cancel(); Task { await server.releaseReads() } }
        try await HubFixture.wait { await server.heldReads == 1 }
        // Le refus arrive par une écriture pendant que l’ancienne lecture est encore en vol.
        await server.deny(403, writesOnly: true)
        _ = await model.enroll(learner("Autre"))
        #expect(model.roster == nil && model.accessRevoked)
        await server.releaseReads()
        await stale.value
        #expect(model.roster == nil && model.candidates.isEmpty && model.accessRevoked)
    }

    @Test func accessGivenBackByANewAuthorisedReadReopensTheRoster() async throws {
        let server = RosterServer(seriesID: seriesID)
        let model = rosterWorkspace(server, learners: [learner("Zoé Exemple")])
        await model.load()
        await server.deny(403)
        await model.load()
        #expect(model.roster == nil && model.accessRevoked)
        await server.deny(nil)
        await model.load()
        #expect(!model.accessRevoked && model.errorMessage == nil && model.roster?.active.count == 1)
        #expect(model.candidates.count == 1)
    }
}

/// Un inscrit, une lecture que l’on peut refuser ou retenir, des écritures comptées.
actor RosterServer: SchoolHTTPTransport {
    let seriesID: UUID
    private var status: Int?
    private var writesOnly = false
    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var heldReads = 0
    private(set) var writes = 0

    init(seriesID: UUID) { self.seriesID = seriesID }

    func deny(_ status: Int?, writesOnly: Bool = false) { self.status = status; self.writesOnly = writesOnly }
    func holdReads() { held = true }
    func releaseReads() { held = false; waiting.forEach { $0.resume() }; waiting = [] }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        let isRead = (request.httpMethod ?? "GET") == "GET"
        if !isRead { writes += 1 }
        if let status, !(writesOnly && isRead) {
            return SchoolHTTPResponse(data: Data(#"{"code":"DENIED","title":"Denied"}"#.utf8), status: status, url: url,
                contentType: "application/problem+json")
        }
        let body = #"""
        {"items":[{"id":"\#(UUID().uuidString.lowercased())","seriesId":"\#(seriesID.uuidString.lowercased())","learnerId":"\#(UUID().uuidString.lowercased())",
         "version":2,"status":"ACTIVE","source":"STAFF","policyVersion":1,"selfCancelHours":24,"selfCancelDeadline":"2030-03-03T17:00:00.000Z",
         "canSelfCancel":true,"createdAt":"2030-01-02T08:00:00.000Z","cancelledAt":null,"cancelKind":null,"cancelReason":null,
         "learnerDisplayName":"Alex Exemple"}],"waitlist":[]}
        """#
        let reply = SchoolHTTPResponse(data: Data(#"{"data":\#(body),"requestId":"roster","serverTime":"2030-03-04T18:00:00Z"}"#.utf8),
            status: 200, url: url, contentType: "application/json")
        if isRead && held {
            heldReads += 1
            await withCheckedContinuation { waiting.append($0) }
        }
        return reply
    }
}
