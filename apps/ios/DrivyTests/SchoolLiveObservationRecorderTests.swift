import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLiveObservationRecorderTests {
    @Test func gestureIsDurableBeforeReturningAndDoubleTapIsRefused() throws {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        let instant = HubFixture.date("2026-09-28T12:11:00Z")
        #expect(model.markMoment(at: instant))
        let command = try #require(outbox.value)
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: command.body)
        #expect(body.operationId == command.id && command.routeResourceID == HubFixture.lessonID)
        #expect(body.observedAt.flatMap(SchoolLesson.date) == instant)
        #expect(body.captureId == nil && body.segmentId == nil && body.pointSequence == nil && body.isValid)
        // Même instant d’ouverture : le même geste, il n’écrit pas une seconde fois.
        #expect(!model.markMoment(at: instant) && outbox.saves.count == 1)
        // Un autre geste, lui, n’attend pas l’envoi du premier (#112).
        #expect(model.confirmed == 0 && model.canRecord)
        #expect(model.mapObservations.count == 1 && model.mapObservations.first?.isPending == true)
        model.stop()
    }

    @Test func anotherPendingCommandIsNamedForeignAndNeverReportedAsAnObservation() {
        let other = PendingSchoolCommand(id: UUID(), scope: ConfigurationFixture.scope(), kind: .completeLesson,
            resourceVersion: 1, createdAt: Date(), body: Data("{}".utf8), routeResourceID: HubFixture.lessonID)
        let outbox = ConfigurationOutboxStub(value: other)
        let model = recorder(outbox: outbox)
        #expect(model.pending == other && model.pendingIsForeign)
        #expect(!model.canRecord && !model.canRetry && !model.markMoment())
        #expect(outbox.saves.isEmpty && outbox.value == other)
        model.stop()
    }

    @Test func aPendingObservationOfThisLessonIsNotForeign() throws {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        #expect(!model.pendingIsForeign)
        #expect(model.markMoment())
        #expect(model.pending != nil && !model.pendingIsForeign)
        model.stop()
    }

    @Test func invalidatedReplayNamesItsStateInsteadOfLoadingForever() async {
        let scope = ConfigurationFixture.scope()
        let client = SchoolCaptureClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: LiveObservationTransport())
        let replay = SchoolCaptureReplayWorkspace(scope: scope, client: client, captureID: UUID())
        replay.invalidate()
        await replay.load()
        #expect(replay.isInvalidated && replay.errorMessage != nil && !replay.isLoading && !replay.isComplete)
    }

    @Test func failedStorageNeverClaimsTheGestureWasKept() {
        let outbox = ConfigurationOutboxStub(); outbox.failSave = true
        let model = recorder(outbox: outbox)
        #expect(!model.markMoment())
        #expect(model.pending == nil && model.confirmed == 0 && outbox.value == nil)
        #expect(model.mapObservations.isEmpty)
        #expect(model.errorMessage?.contains("n’a pas été enregistré") == true)
    }

    @Test func pendingGestureSurvivesRecreationAndAccountChangeStopsSending() throws {
        let outbox = ConfigurationOutboxStub()
        let first = recorder(outbox: outbox)
        #expect(first.markMoment()); first.stop()
        let command = try #require(outbox.value)
        let restored = recorder(outbox: outbox)
        #expect(restored.pending == command && restored.canRetry && restored.canRecord)
        #expect(restored.mapObservations.first?.id == command.id)
        restored.stop()
        #expect(!restored.canRetry && !restored.markMoment())
        #expect(outbox.value == command)
    }

    @Test func completedReportDoesNotDuplicateObservationTextPastItsPrivacyControl() {
        let observation = SchoolObservation(id: UUID(), schoolId: HubFixture.schoolID, version: 1,
            lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
            captureId: nil, segmentId: nil, pointSequence: nil, competencyId: nil,
            text: "Observation à garder pour moi", origin: "LIVE", observedAt: "2026-09-28T12:11:00Z",
            eventKind: "MARKER", eventStatus: nil, authorMembershipId: ConfigurationFixture.membershipID)
        let result = SchoolLessonHubRules.completionReport(goals: [SchoolLessonGoal(label: "Priorités")],
            observations: [observation], competencies: [])
        #expect(result.workedOn == "Priorités" && result.observationText.isEmpty)
    }

    @Test func qualificationKeepsTheChosenThemeStatusAndOriginalInstant() async throws {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        let theme = try #require(model.themes.first)
        let instant = HubFixture.date("2026-09-28T12:11:00Z")
        #expect(model.record(theme: theme, status: .attention, at: instant))
        let command = try #require(outbox.value)
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: command.body)
        // #56 : le thème qualifie seul ; aucune compétence n’est jointe.
        #expect(body.competencyId == nil && body.themeKey == theme.key && body.eventKind == "QUALIFIED")
        #expect(body.eventStatus == "ATTENTION" && body.text == theme.title)
        #expect(body.observedAt.flatMap(SchoolLesson.date) == instant)
        #expect(body.captureId == nil && body.isValid)
        #expect(!model.record(theme: theme, status: .positive, at: instant))
        model.stop()
    }

    @Test func aThemeOutsideTheSchoolCatalogueCannotBeRecorded() {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        let unread = SchoolLiveObservationTheme(key: "tunnel", title: "Tunnels")
        #expect(!model.record(theme: unread, status: .attention, at: Date()))
        #expect(outbox.value == nil && model.pending == nil)
        model.stop()
    }

    /// #56 : la palette est prête sans aucune lecture du référentiel de la formation.
    @Test func thePaletteNeedsNoReferentialRead() {
        let model = recorder(outbox: ConfigurationOutboxStub())
        #expect(model.themes.map(\.key) == SchoolObservationThemeCatalog.embedded.filter(\.visible).map(\.key))
        #expect(model.expectedTileCount == model.themes.count)
        model.stop()
    }

    @Test func replayNamesThePreciseObservationAndKeepsItsStatusSeparate() {
        let observation = SchoolObservation(id: UUID(), schoolId: HubFixture.schoolID, version: 1,
            lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
            captureId: nil, segmentId: nil, pointSequence: nil, competencyId: LiveObservationTransport.competency.id,
            text: "Priorité à droite", origin: "LIVE", observedAt: "2026-09-28T12:11:00Z",
            eventKind: "QUALIFIED", eventStatus: "ATTENTION", authorMembershipId: ConfigurationFixture.membershipID)
        let timeline = SchoolReplayTimeline(fragments: [], observations: [observation],
            startsAt: HubFixture.date("2026-09-28T12:00:00Z"), endsAt: HubFixture.date("2026-09-28T12:30:00Z"))
        #expect(timeline.items.first?.title == "Priorité à droite")
        #expect(timeline.items.first?.statusLabel == "Attention")
        #expect(timeline.items.first?.coordinate == nil && timeline.items.first?.offset == 660)
    }

    @Test func lateConfirmationRefreshesTheNoGPSWorkspaceAfterItsSheetClosed() async throws {
        let transport = DelayedLiveObservationTransport(), outbox = ConfigurationOutboxStub()
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: transport)
        let workspace = SchoolObservationWorkspace(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
        await workspace.load()
        let recorder = try #require(workspace.liveRecorder())
        #expect(recorder.markMoment(at: HubFixture.date("2026-09-28T12:11:00Z")))
        let command = try #require(outbox.value)
        // Lecture déclenchée par onDismiss, avant la confirmation du POST.
        await workspace.load()
        #expect(workspace.pending == command && !workspace.canAdd)
        await transport.releasePost()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (workspace.pending != nil || workspace.isLoading || workspace.observations.isEmpty), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(workspace.pending == nil && workspace.canAdd && workspace.observations.count == 1)
        #expect(outbox.value == nil && outbox.removals == [command])
        #expect(await transport.operations() == [command.id])
        #expect(recorder.confirmed == 1)
    }

    @Test func lateConfirmationCannotReopenAnInvalidatedObservationWorkspace() async throws {
        let transport = DelayedLiveObservationTransport(), outbox = ConfigurationOutboxStub()
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: transport)
        let workspace = SchoolObservationWorkspace(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
        await workspace.load()
        let recorder = try #require(workspace.liveRecorder())
        #expect(recorder.markMoment())
        await workspace.load()
        workspace.invalidate()
        await transport.releasePost()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while recorder.confirmed == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(recorder.confirmed == 1 && outbox.value == nil)
        #expect(workspace.accessRevoked && !workspace.loaded && !workspace.canAdd && workspace.lesson == nil && workspace.observations.isEmpty)
    }

    @Test func measuredAnchorIsDurableAndNeverChangesWhenTheConfirmationArrivesLater() throws {
        let outbox = ConfigurationOutboxStub()
        let anchor = SchoolLiveObservationAnchor(captureID: UUID(), segmentID: UUID(), pointSequence: 7)
        let model = recorder(outbox: outbox, permitsAnchor: { $0 == anchor })
        let instant = HubFixture.date("2026-09-28T12:11:00Z")
        #expect(model.markMoment(at: instant, anchor: anchor))
        model.stop()
        let command = try #require(outbox.value)
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: command.body)
        #expect(body.captureId == anchor.captureID && body.segmentId == anchor.segmentID && body.pointSequence == 7)
        #expect(body.observedAt.flatMap(SchoolLesson.date) == instant && body.isValid)
        #expect(model.mapObservations.first?.body.pointSequence == 7)
        let restored = recorder(outbox: outbox)
        #expect(restored.mapObservations.first?.body.captureId == anchor.captureID)
        restored.stop()
    }

    @Test func revokedAnchorRequiresAnotherExplicitGestureInsteadOfMovingTheMarker() {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox, permitsAnchor: { _ in false })
        let anchor = SchoolLiveObservationAnchor(captureID: UUID(), segmentID: UUID(), pointSequence: 0)
        let accepted = model.markMoment(anchor: anchor)
        #expect(accepted == false)
        #expect(outbox.value == nil && model.mapObservations.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(model.markMoment())
        #expect(model.mapObservations.first?.body.captureId == nil)
        model.stop()
    }

    @Test func theSendThatFollowsAGestureNeverDelaysTheNextGesture() async throws {
        try await inOutbox { outbox in
            let transport = DelayedLiveObservationTransport()
            let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
                tokenSource: HubToken(), transport: transport)
            let model = SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
                client: client, outbox: outbox, retryDelays: [])
            #expect(model.acceptsSignal && model.canRecord && !model.isSettlingGesture)
            #expect(model.markMoment(at: HubFixture.date("2026-09-28T12:11:00Z")))
            // Dès le retour du geste : l’envoi est réclamé, « Signaler » reste ouvert et le geste suivant s’écrit aussitôt.
            #expect(model.isSending && model.isSettlingGesture && model.acceptsSignal && model.canRecord)
            #expect(model.markMoment(at: HubFixture.date("2026-09-28T12:11:04Z")))
            let queued = try outbox.pendingCommands(for: ConfigurationFixture.scope())
            #expect(queued.count == 2 && model.queuedCount == 2 && model.mapObservations.count == 2)
            await transport.releasePost()
            try await HubFixture.wait { !model.isSending }
            // Dans l’ordre des gestes, chacun une seule fois.
            #expect(await transport.operations() == queued.map(\.id))
            #expect(model.confirmed == 2 && model.queuedCount == 0 && model.pending == nil)
            #expect(try outbox.pendingCommands(for: ConfigurationFixture.scope()).isEmpty)
            #expect(model.mapObservations.allSatisfy { !$0.isPending })
            model.stop()
        }
    }

    @Test func gesturesQueueWhileTheSchoolIsUnreachableAndLeaveInGestureOrder() async throws {
        try await inOutbox { outbox in
            let server = QueuedObservationServer(offline: true)
            let model = queuedRecorder(outbox: outbox, server: server)
            #expect(model.markMoment(at: HubFixture.date("2026-09-28T12:11:00Z")))
            try await HubFixture.wait { !model.isSending }
            // L’école est injoignable : « Signaler » reste ouvert, le geste suivant rejoint la file.
            #expect(model.acceptsSignal && model.canRecord && model.canRetry && model.queuedCount == 1)
            #expect(model.errorMessage?.contains("conservée sur cet appareil") == true)
            let theme = try #require(model.themes.first)
            #expect(model.record(theme: theme, status: .attention, at: HubFixture.date("2026-09-28T12:11:20Z")))
            try await HubFixture.wait { !model.isSending }
            let queued = try outbox.pendingCommands(for: ConfigurationFixture.scope())
            #expect(queued.count == 2 && model.queuedCount == 2 && model.mapObservations.count == 2)
            #expect(model.mapObservations.allSatisfy(\.isPending) && model.confirmed == 0)
            #expect(model.errorMessage?.contains("2 signalements") == true)
            await server.setOffline(false)
            await model.retry()
            #expect(await server.creations() == queued.map(\.id))
            #expect(model.confirmed == 2 && model.queuedCount == 0 && model.pending == nil && model.errorMessage == nil)
            #expect(try outbox.pendingCommands(for: ConfigurationFixture.scope()).isEmpty)
            model.stop()
        }
    }

    @Test func undoingAQueuedGestureThatNeverLeftTheDeviceSendsNothing() async throws {
        try await inOutbox { outbox in
            let server = QueuedObservationServer(offline: true)
            let model = queuedRecorder(outbox: outbox, server: server)
            #expect(model.markMoment(at: HubFixture.date("2026-09-28T12:11:00Z")))
            try await HubFixture.wait { !model.isSending }
            #expect(model.markMoment(at: HubFixture.date("2026-09-28T12:11:30Z")))
            try await HubFixture.wait { !model.isSending }
            let second = try #require(model.lastAdded?.id)
            // Le premier bloque toujours l’envoi : le second n’est jamais parti, il quitte simplement la file.
            #expect(model.canUndo(second))
            #expect(await model.undoLastAdded(id: second))
            #expect(model.undoState == .confirmed && model.queuedCount == 1 && model.mapObservations.count == 1)
            #expect(try outbox.pendingCommands(for: ConfigurationFixture.scope()).map(\.id).contains(second) == false)
            await server.setOffline(false)
            await model.retry()
            let created = await server.creations()
            #expect(created.count == 1 && !created.contains(second))
            #expect(model.confirmed == 1 && model.queuedCount == 0)
            model.stop()
        }
    }

    @Test func anotherTeachingRequestStillClosesSignal() {
        let other = PendingSchoolCommand(id: UUID(), scope: ConfigurationFixture.scope(), kind: .completeLesson,
            resourceVersion: 1, createdAt: Date(), body: Data("{}".utf8), resourceID: HubFixture.lessonID)
        let model = recorder(outbox: ConfigurationOutboxStub(value: other))
        #expect(model.pendingIsForeign && !model.acceptsSignal && !model.canRecord && !model.canRetry)
        model.stop()
    }
    @Test func aRequestLeftFromAnEarlierSessionStaysQueuedWithoutClosingSignal() throws {
        let outbox = ConfigurationOutboxStub()
        let first = recorder(outbox: outbox)
        #expect(first.markMoment()); first.stop()
        #expect(!first.acceptsSignal)
        let restored = recorder(outbox: outbox)
        // Aucun envoi n’est en cours : la demande attend son nouvel essai sans fermer « Signaler » (#112).
        #expect(restored.pending != nil && !restored.isSending && !restored.isSettlingGesture)
        #expect(restored.acceptsSignal && restored.canRecord && restored.canRetry && restored.queuedCount == 1)
        restored.stop()
    }
    private func queuedRecorder(outbox: EncryptedSchoolCommandOutbox, server: QueuedObservationServer) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, outbox: outbox, retryDelays: [])
    }

    /// Vraie file chiffrée, dans un dossier jetable : elle seule applique la règle de conflit des signalements.
    private func inOutbox(_ body: (EncryptedSchoolCommandOutbox) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LiveQueue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(EncryptedSchoolCommandOutbox(directory: directory, keyData: Data(repeating: 0x5A, count: 32)))
    }
    private func recorder(outbox: ConfigurationOutboxStub,
                          permitsAnchor: (@MainActor (SchoolLiveObservationAnchor) -> Bool)? = nil) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: LiveObservationTransport())
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, outbox: outbox, permitsAnchor: permitsAnchor)
    }
}

/// Maintient la réponse POST en attente pendant la relecture déclenchée par la fermeture de la feuille.
private actor DelayedLiveObservationTransport: SchoolHTTPTransport {
    private let fallback = LiveObservationTransport()
    private var release: CheckedContinuation<Void, Never>?
    private var released = false
    private var observations: [SchoolObservation] = []
    private var sentOperations: [UUID] = []

    func operations() -> [UUID] { sentOperations }
    func releasePost() { released = true; release?.resume(); release = nil }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.lastPathComponent == "geo-observations" else { return try await fallback.send(request) }
        func response(_ value: some Encodable, status: Int = 200) throws -> SchoolHTTPResponse {
            var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            if var page = data as? [String: Any], page["items"] != nil {
                page["nextCursor"] = NSNull(); data = page
            }
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
                "requestId": UUID().uuidString, "serverTime": "2026-09-28T12:15:00Z"]), status: status, url: url, contentType: "application/json")
        }
        if request.httpMethod == "POST" {
            let body = try JSONDecoder().decode(SchoolObservationBody.self, from: request.httpBody ?? Data())
            sentOperations.append(body.operationId)
            if !released { await withCheckedContinuation { release = $0 } }
            let observation = SchoolObservation(id: body.operationId, schoolId: HubFixture.schoolID, version: 1,
                lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
                captureId: nil, segmentId: nil, pointSequence: nil, competencyId: body.competencyId,
                text: body.text, origin: body.origin, observedAt: body.observedAt, eventKind: body.eventKind,
                eventStatus: body.eventStatus, authorMembershipId: ConfigurationFixture.membershipID)
            observations.append(observation)
            return try response(observation, status: 201)
        }
        return try response(SchoolPage(items: observations, nextCursor: nil))
    }
}

private actor LiveObservationTransport: SchoolHTTPTransport {
    static let offeringID = UUID(uuidString: "70000000-0000-4000-8000-000000000002")!
    static let curriculumID = UUID(uuidString: "70000000-0000-4000-8000-000000000003")!
    static let competency = SchoolCatalogCompetency(id: UUID(uuidString: "70000000-0000-4000-8000-000000000004")!,
        schoolId: HubFixture.schoolID, version: 1, curriculumVersionId: curriculumID, key: "priority-right",
        label: "Priorité à droite", description: "Observer la priorité à droite.", sortOrder: 1)
    private let fallback = HubServer()
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func response(_ value: some Encodable) throws -> SchoolHTTPResponse {
            var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            if value is SchoolTraining, var training = data as? [String: Any] {
                training["startedOn"] = NSNull(); training["closedOn"] = NSNull(); data = training
            }
            if var page = data as? [String: Any], page["items"] != nil {
                page["nextCursor"] = NSNull(); data = page
            }
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
                "requestId": UUID().uuidString, "serverTime": "2026-09-28T12:15:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        if url.pathComponents.dropLast().last == "trainings" {
            return try response(SchoolTraining(id: HubFixture.trainingID, schoolId: HubFixture.schoolID,
                learnerId: HubFixture.learnerID, offeringId: Self.offeringID, version: 1, categoryCode: "B",
                status: "ACTIVE", startedOn: nil, closedOn: nil))
        }
        if url.lastPathComponent == "offerings" {
            return try response(SchoolPage(items: [SchoolOffering(id: Self.offeringID, schoolId: HubFixture.schoolID,
                version: 1, offeringKey: "B", categoryCode: "B", curriculumVersionId: Self.curriculumID,
                policyVersionId: UUID(), enabled: true, defaultDurationMinutes: 50, defaultPriceCents: 9000)], nextCursor: nil))
        }
        if url.lastPathComponent == "curricula" {
            return try response(SchoolPage(items: [SchoolCurriculum(id: Self.curriculumID, schoolId: HubFixture.schoolID,
                version: 1, categoryCode: "B", revision: 1, approved: true, competencies: [Self.competency])], nextCursor: nil))
        }
        return try await fallback.send(request)
    }
}

/// École joignable ou non selon le test ; garde l’ordre des créations reçues.
private actor QueuedObservationServer: SchoolHTTPTransport {
    private let fallback = LiveObservationTransport()
    private var offline: Bool
    private var created: [UUID] = []

    init(offline: Bool) { self.offline = offline }
    func setOffline(_ value: Bool) { offline = value }
    func creations() -> [UUID] { created }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        if offline { throw URLError(.notConnectedToInternet) }
        guard let url = request.url, url.lastPathComponent == "geo-observations", request.httpMethod == "POST" else {
            return try await fallback.send(request)
        }
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: request.httpBody ?? Data())
        created.append(body.operationId)
        let observation = SchoolObservation(id: body.operationId, schoolId: HubFixture.schoolID, version: 1,
            lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
            captureId: nil, segmentId: nil, pointSequence: nil, competencyId: nil,
            text: body.text, origin: body.origin, observedAt: body.observedAt, eventKind: body.eventKind,
            eventStatus: body.eventStatus, authorMembershipId: ConfigurationFixture.membershipID)
        let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(observation))
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
            "requestId": UUID().uuidString, "serverTime": "2026-09-28T12:15:00Z"]), status: 201, url: url, contentType: "application/json")
    }
}