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
        let body = try #require(try JSONSerialization.jsonObject(with: saved.body) as? [String: Any])
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
        let body = try #require(try JSONSerialization.jsonObject(with: saved.body) as? [String: Any])
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

    // MARK: Relectures et réglages de partage

    @Test func aSilentRereadKeepsTheReportOpenAndTheSaveWaitsForItsResult() async throws {
        let server = LessonFinishServer(), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        #expect(model.canMutate && model.acceptsInput && !model.needsReload)
        await server.holdProgress()
        let reread = Task { await model.load() }
        try await HubFixture.wait { await server.isHoldingProgress() }
        // Relecture en cours : l’envoi est fermé, la saisie reste ouverte et aucun état de conflit ne s’affiche.
        #expect(model.isLoading && !model.canMutate && model.acceptsInput && !model.needsReload && !model.pendingAwaitsReview)
        model.nextStep = "Saisi pendant la relecture"
        // L’appui n’est ni perdu ni envoyé sur une version en cours de relecture : il attend.
        let saving = Task { await model.saveDraft() }
        await Task.yield()
        #expect(outbox.saves.isEmpty)
        await server.releaseProgress()
        await reread.value
        let saved = await saving.value
        #expect(saved && model.reportSaveConfirmed && model.nextStep == "Saisi pendant la relecture")
        let command = try #require(outbox.saves.first)
        let body = try #require(try JSONSerialization.jsonObject(with: command.body) as? [String: Any])
        #expect(body["nextStep"] as? String == "Saisi pendant la relecture")
        #expect(await server.requests().filter { $0.httpMethod == "PUT" }.count == 1)
    }

    @Test func sharingChangesKeepTheReportOpenAndAreSentOneAtATime() async throws {
        let server = LessonFinishServer(sharing: true), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        #expect(model.sharing?.version == 1 && model.reportShared && model.captureShared)
        await server.holdSharing()
        let first = Task { await model.updateSharing(reportPrivate: true) }
        try await HubFixture.wait { await server.isHoldingSharing() }
        // Envoi du réglage en cours : il se lit aussitôt, sans griser la saisie ni montrer une demande à vérifier.
        #expect(model.isBusy && !model.canMutate && model.acceptsInput && !model.pendingAwaitsReview && !model.holdsScreen)
        #expect(!model.reportShared && model.captureShared)
        model.nextStep = "Saisi pendant le réglage"
        // Second réglage pendant cet envoi : il se lit aussitôt et attend son tour.
        let second = Task { await model.updateSharing(captureHidden: true) }
        try await HubFixture.wait { !model.captureShared }
        #expect(!model.reportShared && !model.captureShared)
        #expect(await server.sharingWrites().count == 1)
        await server.releaseSharing()
        await first.value
        await second.value
        #expect(model.sharing?.reportPrivate == true && model.sharing?.captureHidden == true && model.sharing?.version == 3)
        #expect(model.optimisticSharing == nil && !model.reportShared && !model.captureShared)
        #expect(model.nextStep == "Saisi pendant le réglage" && model.canMutate && model.acceptsInput && outbox.value == nil)
        let writes = await server.sharingWrites()
        // Le second réglage part de l’état confirmé par le premier.
        #expect(writes.count == 2 && writes.last?.value(forHTTPHeaderField: "If-Match") == "\"2\"")
    }

    @Test func aReportLeftWithoutAnswerIsShownAsARequestToVerifyAndLocksTheForm() async {
        let server = LessonFinishServer()
        let model = workspace(server, outbox: ConfigurationOutboxStub())
        await model.load()
        await server.setReceiptAvailable(false)
        model.nextStep = "À conserver"
        #expect(!(await model.saveDraft()))
        #expect(model.pending != nil && model.pendingAwaitsReview && !model.acceptsInput && !model.canMutate && !model.holdsScreen)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        #expect(model.reportSaveConfirmed && !model.pendingAwaitsReview)
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
    private let sharingEnabled: Bool
    static let progressCompetency = UUID(uuidString: "70000000-0000-4000-8000-0000000000c1")!
    private var receiptAvailable = true
    private var rejectSave = false
    private var operation: UUID?
    private var receiptResourceID: UUID?
    private var recorded: [URLRequest] = []
    private let draftID = UUID(uuidString: "70000000-0000-4000-8000-000000000050")!
    private var heldProgress = false, holdingProgress = false
    private var progressWaiters: [CheckedContinuation<Void, Never>] = []
    private var heldSharing = false, holdingSharing = false
    private var sharingWaiters: [CheckedContinuation<Void, Never>] = []
    private var sharingVersion = 1, reportPrivate = false, captureHidden = false
    private var sharingOperation: UUID?
    /// `sharing` : l’école expose le réglage de partage de la leçon (absent par défaut, comme un serveur plus ancien).
    init(roles: [String] = ["INSTRUCTOR"], emptyContext: Bool = false, progressLevel: String? = nil, progressStatus: Int = 200,
         sharing: Bool = false) {
        self.roles = roles; self.emptyContext = emptyContext; self.progressLevel = progressLevel; self.progressStatus = progressStatus
        sharingEnabled = sharing
    }
    /// Retient la dernière lecture d’une relecture (les niveaux actuels), juste avant son application.
    func holdProgress() { heldProgress = true }
    func releaseProgress() { heldProgress = false; let values = progressWaiters; progressWaiters = []; for item in values { item.resume() } }
    func isHoldingProgress() -> Bool { holdingProgress }
    /// Retient l’écriture d’un réglage de partage.
    func holdSharing() { heldSharing = true }
    func releaseSharing() { heldSharing = false; let values = sharingWaiters; sharingWaiters = []; for item in values { item.resume() } }
    func isHoldingSharing() -> Bool { holdingSharing }
    func sharingWrites() -> [URLRequest] { recorded.filter { $0.httpMethod == "PUT" && $0.url?.path.hasSuffix("/sharing") == true } }
    func setReceiptAvailable(_ value: Bool) { receiptAvailable = value }
    func setRejectSave(_ value: Bool) { rejectSave = value }
    func setConfirmedOperation(_ id: UUID, resourceID: UUID) { operation = id; receiptResourceID = resourceID }
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
            if heldProgress {
                holdingProgress = true
                await withCheckedContinuation { progressWaiters.append($0) }
                holdingProgress = false
            }
            if progressStatus != 200 { return problem(progressStatus, "UNAVAILABLE") }
            let items: [[String: Any]] = progressLevel.map { level in
                [["competencyId": Self.progressCompetency.uuidString, "label": "Observation", "level": level, "context": "Leçon précédente",
                  "observedAt": "2026-09-20T10:00:00Z", "sourceLessonId": UUID().uuidString, "sourceRevisionId": UUID().uuidString]]
            } ?? []
            return try ok(["trainingId": HubFixture.trainingID.uuidString, "items": items, "unobservedCompetencyIds": [] as [String],
                "computedAt": "2026-09-28T13:30:00Z"])
        }
        if sharingEnabled, parts.suffix(3) == ["lessons", HubFixture.lessonID.uuidString.lowercased(), "sharing"] {
            if request.httpMethod == "PUT" {
                if heldSharing {
                    holdingSharing = true
                    await withCheckedContinuation { sharingWaiters.append($0) }
                    holdingSharing = false
                }
                let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                sharingOperation = UUID(uuidString: body?["operationId"] as? String ?? "")
                reportPrivate = body?["reportPrivate"] as? Bool ?? reportPrivate
                captureHidden = body?["captureHidden"] as? Bool ?? captureHidden
                sharingVersion += 1
            }
            return try ok(["lessonId": HubFixture.lessonID.uuidString, "schoolId": HubFixture.schoolID.uuidString, "version": sharingVersion,
                "reportPrivate": reportPrivate, "captureHidden": captureHidden, "privateObservationIds": [] as [String]])
        }
        if parts.dropLast().last == "operations", let sharingOperation, parts.last == sharingOperation.uuidString.lowercased() {
            return try ok(["operationId": sharingOperation.uuidString, "commandType": "UPDATE_LESSON_SHARING", "resourceType": "LessonSharing",
                "resourceId": HubFixture.lessonID.uuidString, "committedAt": "2026-09-28T13:30:00Z", "resourceVersion": sharingVersion])
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
                "resourceId": (receiptResourceID ?? draftID).uuidString, "committedAt": "2026-09-28T13:30:00Z", "resourceVersion": 2])
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
