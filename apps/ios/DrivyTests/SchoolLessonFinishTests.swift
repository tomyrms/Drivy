import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLessonFinishTests {
    @Test func emptyReportSavesAndClosesOnlyAfterItsDurableReceipt() async throws {
        let server = LessonFinishServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        #expect(model.draft != nil && !model.draftChanged && model.canMutate)
        #expect(await model.saveDraft())
        #expect(model.reportSaveConfirmed && model.pending == nil && outbox.value == nil)
        let saved = try #require(outbox.saves.first)
        let body = try #require(JSONSerialization.jsonObject(with: saved.body) as? [String: Any])
        #expect(body["workedOn"] as? String == "" && body["observationText"] as? String == "" && body["nextStep"] as? String == "")
        #expect(outbox.removals == [saved])
    }

    @Test func nextStepAloneIsAValidReport() async {
        let model = workspace(LessonFinishServer(), outbox: ConfigurationOutboxStub())
        await model.load()
        model.nextStep = "Reprendre les contrôles avant de tourner."
        #expect(await model.saveDraft())
        #expect(model.reportSaveConfirmed)
    }

    @Test func competencyContextCanBeEmptyWithoutBlockingReadOrSave() async {
        let model = workspace(LessonFinishServer(emptyContext: true), outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(model.draft?.observations.count == 1 && model.observations.first?.context == "")
        #expect(model.observationsValid && model.canMutate)
        #expect(await model.saveDraft())
        #expect(model.reportSaveConfirmed)
    }

    @Test func lostReceiptRetainsTextUntilVerificationThenClosesWithoutAnotherSave() async throws {
        let server = LessonFinishServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        await server.setReceiptAvailable(false)
        model.nextStep = "À conserver"
        #expect(!(await model.saveDraft()))
        #expect(!model.reportSaveConfirmed && model.nextStep == "À conserver" && model.pending != nil)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        #expect(model.reportSaveConfirmed && model.pending == nil && outbox.value == nil)
        #expect(await server.requests().filter { $0.httpMethod == "PUT" }.count == 1)
    }

    @Test func rejectedReportNeverClosesAndKeepsItsText() async {
        let server = LessonFinishServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        await server.setRejectSave(true)
        model.observationText = "Texte conservé après refus"
        #expect(!(await model.saveDraft()))
        #expect(!model.reportSaveConfirmed && model.observationText == "Texte conservé après refus")
        #expect(model.errorMessage != nil)
    }

    @Test func administratorCanReachReplayWithoutReadingPrivatePedagogicalContent() async {
        let server = LessonFinishServer(roles: ["ADMIN"])
        let model = workspace(server, outbox: ConfigurationOutboxStub(), roles: ["ADMIN"])
        await model.load()
        #expect(model.lesson?.status == "COMPLETED" && !model.isAuthor && model.canReadLessonContent)
        #expect(model.replayableCaptures.count == 1 && model.draft == nil && model.lessonObservations.isEmpty)
        let paths = await server.requests().compactMap { $0.url?.path }
        #expect(!paths.contains { $0.hasSuffix("/report-drafts") || $0.hasSuffix("/reports") || $0.hasSuffix("/preparation") || $0.hasSuffix("/observations") })
        // An unavailable preview must leave the route to the independently authorized replay visible.
        #expect(model.track.isEmpty && model.errorMessage == nil)
    }

    @Test func currentLevelsStartTheNextReportWithoutBecomingObservationsOfThisLesson() async throws {
        let competency = LessonFinishServer.progressCompetency
        let server = LessonFinishServer(progressLevel: "GUIDED"), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        // Une nouvelle leçon ne repart pas de zéro : le niveau actuel est rappelé, sans être écrit dans son bilan.
        #expect(model.currentLevels[competency]?.level == "GUIDED")
        #expect(model.unchangedChoiceLabel(for: competency) == "Actuel : Avec accompagnement")
        #expect(model.unchangedChoiceLabel(for: UUID()) == "Pas encore vu")
        #expect(model.observations.isEmpty)
        model.setObservationLevel("INDEPENDENT", for: competency)
        #expect(await model.saveDraft())
        let saved = try #require(outbox.saves.first)
        let body = try #require(JSONSerialization.jsonObject(with: saved.body) as? [String: Any])
        let sent = try #require(body["observations"] as? [[String: Any]])
        #expect(sent.count == 1 && sent.first?["competencyId"] as? String == competency.uuidString && sent.first?["level"] as? String == "INDEPENDENT")
        // Après l’enregistrement, la progression est relue pour que le niveau suivant parte du plus récent.
        let reads = await server.requests().filter { $0.url?.path.hasSuffix("/progress") == true }
        #expect(reads.count >= 1)
    }

    @Test func takingBackAChosenLevelLeavesTheReportUntouchedAndSendsNothing() async {
        let competency = LessonFinishServer.progressCompetency
        let outbox = ConfigurationOutboxStub()
        let model = workspace(LessonFinishServer(progressLevel: "GUIDED"), outbox: outbox)
        await model.load()
        model.setObservationLevel("INDEPENDENT", for: competency)
        #expect(model.draftChanged)
        // Le retour arrière est libre tant que rien n’est enregistré : le bilan redevient identique à celui de l’école.
        model.setObservationLevel("", for: competency)
        #expect(!model.draftChanged && model.observations.isEmpty)
        #expect(outbox.saves.isEmpty && !model.reportSaveConfirmed)
    }

    @Test func aFailedProgressReadNeverBlocksTheReport() async {
        let model = workspace(LessonFinishServer(progressStatus: 503), outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(model.currentLevels.isEmpty && model.draft != nil && model.canMutate)
        #expect(model.unchangedChoiceLabel(for: LessonFinishServer.progressCompetency) == "Pas encore vu")
    }

    @Test func administrationReadsProgressButNotThePrivateReport() {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["ADMIN", "INSTRUCTOR"], grants: [], accessEpoch: 1)
        let admin = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["ADMIN"], grants: [], accessEpoch: 1)
        let client = SchoolTrainingClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: LessonFinishServer())
        for value in [membership, admin] {
            let model = SchoolTrainingWorkspace(scope: ConfigurationFixture.scope(), membership: value, learnerID: HubFixture.learnerID,
                trainingID: HubFixture.trainingID, client: client)
            #expect(model.hasPedagogicalRole)
        }
    }

    @Test func startNowReadsOnlyAssignedLearnersAndEligibleTrainings() async throws {
        let server = LessonFinishServer()
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let model = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: client, outbox: ConfigurationOutboxStub())
        await model.load()
        let request = try #require(await server.requests().first { $0.url?.path.hasSuffix("/learners") == true })
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first(where: { $0.name == "instructorMembershipId" })?.value == ConfigurationFixture.membershipID.uuidString)
        #expect(model.trainings.count == 1 && model.trainingID == HubFixture.trainingID && model.canStart)
    }

    private func workspace(_ server: LessonFinishServer, outbox: ConfigurationOutboxStub, roles: [String] = ["INSTRUCTOR"]) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: roles, grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
    }
}

/// Toutes les personnes, demandes et séances sont synthétiques ; aucune position n’est nécessaire à ces tests.
actor LessonFinishServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private let roles: [String]
    private let emptyContext: Bool
    private let progressLevel: String?
    private let progressStatus: Int
    static let progressCompetency = UUID(uuidString: "70000000-0000-4000-8000-0000000000c1")!
    private var receiptAvailable = true
    private var rejectSave = false
    private var operation: UUID?
    private var recorded: [URLRequest] = []
    private let draftID = UUID(uuidString: "70000000-0000-4000-8000-000000000050")!
    init(roles: [String] = ["INSTRUCTOR"], emptyContext: Bool = false, progressLevel: String? = nil, progressStatus: Int = 200) {
        self.roles = roles; self.emptyContext = emptyContext; self.progressLevel = progressLevel; self.progressStatus = progressStatus
    }
    func setReceiptAvailable(_ value: Bool) { receiptAvailable = value }
    func setRejectSave(_ value: Bool) { rejectSave = value }
    func requests() -> [URLRequest] { recorded }
    func enableStartNowConflict() async { await fallback.enableStartNowConflict() }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        let url = request.url!, parts = url.pathComponents.map { $0.lowercased() }
        func ok(_ data: [String: Any]) throws -> SchoolHTTPResponse {
            let envelope: [String: Any] = ["data": data, "requestId": UUID().uuidString, "serverTime": "2026-09-28T13:30:00Z"]
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: 200, url: url, contentType: "application/json")
        }
        func problem(_ status: Int, _ code: String) -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\",\"title\":\"Refus\"}".utf8), status: status, url: url, contentType: "application/problem+json")
        }
        if parts.last == "planning-defaults" {
            return try ok(["id": ConfigurationFixture.membershipID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "version": 1, "trainingCategoryCode": NSNull(), "serviceProductKey": NSNull()])
        }
        if parts.last == "me" {
            return try ok(["personId": ConfigurationFixture.personID.uuidString, "version": 1, "displayName": "Compte de test", "locale": "fr",
                "memberships": [["membershipId": ConfigurationFixture.membershipID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                    "schoolName": "École de test", "roles": roles, "grants": ["permit_review"], "accessEpoch": 1] as [String: Any]]])
        }
        if parts.suffix(2) == ["lessons", HubFixture.lessonID.uuidString.lowercased()] {
            let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson(status: "COMPLETED", permitWarning: false)))
            return try ok(data as! [String: Any])
        }
        if parts.last == "progress" {
            if progressStatus != 200 { return problem(progressStatus, "UNAVAILABLE") }
            let items: [[String: Any]] = progressLevel.map { level in
                [["competencyId": Self.progressCompetency.uuidString, "label": "Observation", "level": level, "context": "Leçon précédente",
                  "observedAt": "2026-09-20T10:00:00Z", "sourceLessonId": UUID().uuidString, "sourceRevisionId": UUID().uuidString]]
            } ?? []
            return try ok(["trainingId": HubFixture.trainingID.uuidString, "items": items, "unobservedCompetencyIds": [] as [String],
                "computedAt": "2026-09-28T13:30:00Z"])
        }
        if parts.last == "report-drafts" {
            let draft = SchoolReportDraft(id: draftID, schoolId: HubFixture.schoolID, lessonId: HubFixture.lessonID,
                authorMembershipId: ConfigurationFixture.membershipID, version: 1, basePublicationVersion: 0,
                workedOn: "", observationText: "", nextStep: "",
                observations: emptyContext ? [SchoolReportObservation(competencyId: UUID(), level: "GUIDED", context: "")] : [],
                attachmentIds: [], geoObservationIds: [])
            let item = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft))
            return try ok(["items": [item], "nextCursor": NSNull()])
        }
        if request.httpMethod == "PUT", parts.suffix(2) == ["report-drafts", draftID.uuidString.lowercased()] {
            if rejectSave { return problem(409, "VERSION_CONFLICT") }
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            operation = UUID(uuidString: body?["operationId"] as? String ?? "")
            return try ok([:])
        }
        if parts.dropLast().last == "operations", let operation, parts.last == operation.uuidString.lowercased() {
            guard receiptAvailable else { return problem(503, "UNAVAILABLE") }
            return try ok(["operationId": operation.uuidString, "commandType": "SAVE_REPORT_DRAFT", "resourceType": "ReportDraft",
                "resourceId": draftID.uuidString, "committedAt": "2026-09-28T13:30:00Z", "resourceVersion": 2])
        }
        if parts.suffix(3) == ["lessons", HubFixture.lessonID.uuidString.lowercased(), "captures"] {
            let capture = HubFixture.capture(authorizedAt: "2026-09-28T12:00:00Z", stoppedAt: "2026-09-28T12:50:00Z", state: .stopped)
            var item = try JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as! [String: Any]
            item["syncState"] = "SYNCED"
            return try ok(["items": [item]])
        }
        if parts.last == "learners" {
            return try ok(["items": [["id": HubFixture.learnerID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "personId": UUID().uuidString, "version": 1, "displayName": "Élève de test", "contactEmail": NSNull(), "contactPhone": NSNull(),
                "archivedAt": NSNull()] as [String: Any]], "nextCursor": NSNull()])
        }
        if parts.last == "trainings" {
            var training: [String: Any] = ["id": HubFixture.trainingID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "learnerId": HubFixture.learnerID.uuidString, "offeringId": UUID().uuidString, "version": 1, "categoryCode": "B",
                "status": "ACTIVE", "startedOn": NSNull(), "closedOn": NSNull(), "startNowBlockerCode": NSNull()]
            var unavailable = training
            unavailable["id"] = UUID().uuidString; unavailable["categoryCode"] = "A"
            unavailable["startNowBlockerCode"] = "INSTRUCTOR_NOT_ASSIGNED"
            training["startNowBlockerCode"] = NSNull()
            return try ok(["items": [training, unavailable], "nextCursor": NSNull()])
        }
        return try await fallback.send(request)
    }
}
