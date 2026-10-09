import Foundation
import Testing
@testable import Drivy

/// Une demande que l’école ne connaît pas ne doit ni rester en file, ni bloquer les autres actions sans issue.
@MainActor struct SchoolPendingRequestResolutionTests {
    @Test func aStartTheSchoolCannotRouteIsNotKeptAsAnUncertainRequest() async {
        let server = MissingOperationServer(fallback: HubServer()), outbox = ConfigurationOutboxStub()
        let model = lessonWorkspace(server, outbox)
        await model.load()
        #expect(!(await model.start()))
        #expect(model.pending == nil && outbox.value == nil)
        // La fiche reste lisible : le refus d’une commande n’est pas une perte d’accès à la leçon.
        #expect(model.lesson != nil && !model.isInvalidated)
        #expect(model.errorMessage?.contains("Rien n’a été enregistré") == true)
        #expect(outbox.saves.allSatisfy { $0.kind == .startLesson } && outbox.removals.map(\.kind) == [.startLesson])
    }

    @Test func aRequestUnknownToTheSchoolCanBeAbandonedFromTheLesson() async throws {
        let stale = try staleStart()
        let server = MissingOperationServer(fallback: HubServer()), outbox = ConfigurationOutboxStub(value: stale)
        let model = lessonWorkspace(server, outbox)
        await model.load()
        #expect(model.pending == stale && !model.canMutate && !model.pendingAbsent)
        await model.verifyPending()
        // L’école répond qu’elle ne connaît pas l’opération : ce n’est pas un problème de droits sur la leçon.
        #expect(model.pendingAbsent && model.lesson != nil && !model.isInvalidated && model.errorMessage == nil)
        #expect(outbox.value == stale)
        await model.abandonPending()
        #expect(model.pending == nil && outbox.value == nil && model.canMutate)
    }

    @Test func abandonIsRefusedUntilTheSchoolHasAnswered() async throws {
        let stale = try staleStart()
        let outbox = ConfigurationOutboxStub(value: stale)
        let model = lessonWorkspace(MissingOperationServer(fallback: HubServer()), outbox)
        await model.load()
        await model.abandonPending()
        #expect(model.pending == stale && outbox.value == stale)
    }

    @Test func aRequestFromAnotherScreenNoLongerBlocksStartingALesson() async throws {
        let stale = try staleStart()
        let server = MissingOperationServer(fallback: LessonFinishServer()), outbox = ConfigurationOutboxStub(value: stale)
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client, outbox: outbox)
        await model.load()
        #expect(model.pending == stale && !model.canStart)
        #expect(await model.verify() == nil)
        #expect(model.pendingAbsent && model.pending == stale && outbox.value == stale)
        await model.abandon()
        #expect(model.pending == nil && outbox.value == nil && model.errorMessage == nil)
    }

    @Test func theNoticeNamesTheRequestAndWhatTheSchoolKnows() throws {
        let stale = try staleStart()
        #expect(stale.waitingMessage(absent: false).contains("« Début de la leçon »"))
        #expect(stale.waitingMessage(absent: true).contains("rien n’a été enregistré"))
        #expect(SchoolCommandKind.startLessonNow.requestTitle == "Leçon sans rendez-vous")
    }

    @Test func learnerSearchIgnoresAccentsCaseAndWordOrder() {
        let learners = ["Hélène Dupont", "Marc-André Müller", "Léa Martin"].map(learner)
        func names(_ query: String) -> [String] { SchoolLearnerSearch.filter(learners, query: query).map(\.displayName) }
        #expect(names("") == learners.map(\.displayName))
        #expect(names("helene") == ["Hélène Dupont"])
        #expect(names("DUP hél") == ["Hélène Dupont"])
        #expect(names("andre") == ["Marc-André Müller"])
        #expect(names("ma") == ["Marc-André Müller", "Léa Martin"])
        #expect(names("zz").isEmpty)
    }

    private func learner(_ name: String) -> SchoolLearner {
        SchoolLearner(id: UUID(), schoolId: HubFixture.schoolID, personId: UUID(), version: 1, displayName: name,
            contactEmail: nil, contactPhone: nil, archivedAt: nil, profileReadiness: nil, profilePhotoDocumentId: nil)
    }

    /// Début de leçon resté en file après un envoi que l’école n’a jamais enregistré.
    private func staleStart() throws -> PendingSchoolCommand {
        struct Start: Encodable { let operationId: UUID }
        let operation = UUID()
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .startLesson, resourceVersion: 1,
            createdAt: HubFixture.date("2026-09-28T11:00:00Z"), body: try JSONEncoder().encode(Start(operationId: operation)),
            resourceID: HubFixture.lessonID)
    }

    private func lessonWorkspace(_ server: MissingOperationServer, _ outbox: ConfigurationOutboxStub) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
    }
}

/// École dont le service ne connaît ni le départ explicite d’une leçon ni l’opération demandée : elle répond 404.
private actor MissingOperationServer: SchoolHTTPTransport {
    private let fallback: any SchoolHTTPTransport
    init(fallback: any SchoolHTTPTransport) { self.fallback = fallback }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let parts = url.pathComponents
        let missing = parts.contains("operations") || (request.httpMethod == "POST" && parts.last == "start")
        guard missing else { return try await fallback.send(request) }
        return SchoolHTTPResponse(data: Data("{\"code\":\"NOT_FOUND\",\"title\":\"Introuvable\"}".utf8), status: 404, url: url,
            contentType: "application/problem+json")
    }
}
