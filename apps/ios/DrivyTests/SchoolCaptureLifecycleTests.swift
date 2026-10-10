import CryptoKit
import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolCaptureLifecycleTests {
    @Test func closingPreparationDuringTransferredAdoptionKeepsTheFinalRightsCheck() async throws {
        let fixture = try await CaptureLifecycleFixture.make(startImmediately: false)
        let model = fixture.preparation(holdAdoption: true)
        let starting = Task { await model.begin() }
        try await fixture.waitForScopeRead(model: model, starting: starting)
        #expect(fixture.controller.captureID == fixture.capture.id && fixture.controller.state == .preparing)
        #expect(!fixture.source.isRunning)
        // Aujourd’hui remplace la préparation par le trajet pendant le dernier GET /me du contrôleur.
        model.suspend()
        await fixture.server.releaseScopeReads()
        #expect(await starting.value)
        #expect(model.captureStarted && fixture.controller.isCollecting && fixture.source.isRunning && fixture.source.startCount == 1)
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    @Test func closingPreparationBeforeOwnershipTransferStillCancelsTheStart() async throws {
        let fixture = try await CaptureLifecycleFixture.make(startImmediately: false)
        let model = fixture.preparation()
        await fixture.server.holdScopeReads()
        let starting = Task { await model.begin() }
        try await fixture.waitForScopeRead(model: model, starting: starting)
        model.suspend()
        await fixture.server.releaseScopeReads()
        #expect(!(await starting.value))
        #expect(!fixture.source.isRunning && fixture.source.startCount == 0 && fixture.controller.captureID == nil && !model.captureStarted)
        #expect(!(await fixture.server.requests()).contains { $0.httpMethod == "POST" && $0.url?.lastPathComponent == "captures" })
    }

    @Test func changingScopeDuringTransferredAdoptionStillStopsTheSource() async throws {
        let fixture = try await CaptureLifecycleFixture.make(startImmediately: false)
        let model = fixture.preparation(holdAdoption: true)
        let starting = Task { await model.begin() }
        try await fixture.waitForScopeRead(model: model, starting: starting)
        model.invalidate()
        fixture.controller.setScope(nil)
        await fixture.server.releaseScopeReads()
        #expect(!(await starting.value))
        #expect(!fixture.source.isRunning && fixture.source.startCount == 0 && fixture.controller.captureID == nil && !model.captureStarted)
    }

    @Test func aRemoteRightsRefusalAfterPreparationClosesCannotStartGPS() async throws {
        let fixture = try await CaptureLifecycleFixture.make(startImmediately: false)
        let model = fixture.preparation(holdAdoption: true)
        let starting = Task { await model.begin() }
        try await fixture.waitForScopeRead(model: model, starting: starting)
        model.suspend()
        await fixture.server.releaseScopeReads(refused: true)
        #expect(!(await starting.value))
        #expect(!fixture.source.isRunning && fixture.source.startCount == 0 && fixture.controller.captureID == nil && !model.captureStarted)
        let stored = try await fixture.store.storedSession(captureID: fixture.capture.id, scope: fixture.scope)
        #expect(stored.state == .stopped && stored.manifest?.isEmpty == true)
    }

    @Test func aFailedAdoptionLeavesThePreparationAbleToRetryInsteadOfBlamingThePermission() async throws {
        let fixture = try await CaptureLifecycleFixture.make(startImmediately: false)
        let model = fixture.preparation()
        // L’école autorise le départ, puis la dernière lecture des droits du contrôleur échoue (réseau).
        await fixture.server.failScopeReadAfterNextAuthorization()
        #expect(!(await model.begin()))
        #expect(!fixture.source.isRunning && fixture.source.startCount == 0 && fixture.controller.captureID == nil)
        #expect(!model.captureStarted && !model.accessRevoked && model.errorMessage != nil)
        let stored = try await fixture.store.storedSession(captureID: fixture.capture.id, scope: fixture.scope)
        #expect(stored.state == .stopped)
        // Nouvel essai : la localisation est toujours autorisée, la préparation ne doit pas prétendre le contraire.
        _ = await model.begin()
        if case .permission = model.quickBlock { Issue.record("Un départ échoué ne retire pas l’autorisation de localisation") }
        #expect(model.mayDiagnose)
        model.invalidate()
    }

    @Test func aOneStepStartReviewsTheLessonOnceAndWakesTheReceiverAfterTheChoice() async throws {
        let fixture = try await CaptureLifecycleFixture.make(startImmediately: false)
        let model = fixture.preparation()
        // L’accord et la leçon se lisent avant tout rideau : le départ peut partir sans question.
        await model.load()
        #expect(model.readyForOneStepStart)
        #expect(await model.begin(reload: false))
        #expect(model.captureStarted && fixture.source.isRunning && fixture.source.warmUps > 0)
        // Une seule relecture du départ : l’école (GET) n’est lue qu’une fois, et les droits jamais deux fois d’affilée.
        let requests = await fixture.server.requests()
        let school = fixture.scope.schoolID.uuidString.lowercased()
        #expect(requests.filter { $0.httpMethod == "GET" && $0.url?.lastPathComponent.lowercased() == school }.count == 1)
        #expect(requests.filter { $0.httpMethod == "POST" && $0.url?.lastPathComponent == "captures" }.count == 1)
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    @Test func aClosedPreparationIsNeverReadyForAOneStepStart() async throws {
        let fixture = try await CaptureLifecycleFixture.make(startImmediately: false)
        let model = fixture.preparation()
        #expect(!model.readyForOneStepStart)
        await model.load()
        #expect(model.readyForOneStepStart)
        model.invalidate()
        #expect(!model.readyForOneStepStart)
    }

    @Test func slowFirstFixDoesNotBecomeASignalBreak() throws {
        let policy = try SchoolCaptureLocationPolicy()
        #expect(!policy.requiresNewSegment(previousElapsedMs: nil, nextElapsedMs: 90_000))
        #expect(!policy.requiresNewSegment(previousElapsedMs: 1_000, nextElapsedMs: 61_000))
        #expect(policy.requiresNewSegment(previousElapsedMs: 1_000, nextElapsedMs: 61_001))
        #expect(policy.distanceFilterMeters == 0)
    }

    @Test func backgroundSignalRecoveryRequiresTheSameLiveCaptureAndScope() {
        let scope = ConfigurationFixture.scope(), captureID = UUID()
        var gate = SchoolCaptureLocationStartGate()
        func permitted(_ value: SchoolCaptureLocationStartGate, foreground: Bool = false, id: UUID? = nil,
                       current: SchoolCommandScope? = nil, scopeAvailable: Bool = true,
                       lease: Bool = true, background: Bool = true) -> Bool {
            value.permits(captureID: id ?? captureID, scope: scope, currentScope: scopeAvailable ? current ?? scope : nil,
                isForeground: foreground, allowsBackground: background, leasePermitsCollection: lease)
        }
        #expect(!permitted(gate))
        #expect(permitted(gate, foreground: true))
        gate.didStartInForeground(captureID: captureID, scope: scope)
        #expect(permitted(gate))
        #expect(!permitted(gate, id: UUID()))
        #expect(!permitted(gate, lease: false))
        #expect(!permitted(gate, foreground: true, lease: false))
        #expect(!permitted(gate, scopeAvailable: false))
        #expect(!permitted(gate, background: false))
        let changed = SchoolCommandScope(personID: scope.personID, schoolID: scope.schoolID,
            membershipID: scope.membershipID, accessEpoch: scope.accessEpoch + 1, apiBaseURL: scope.apiBaseURL)
        #expect(!permitted(gate, current: changed))
        gate.reset()
        #expect(!permitted(gate))
    }

    @Test func waitingForGPSDoesNotStopTheLessonOrInventAPoint() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        fixture.source.onEvent?(.signalChanged(.temporarilyUnavailable))
        #expect(fixture.controller.isCollecting && fixture.source.isRunning)
        #expect(fixture.controller.locationMessage != nil && fixture.controller.pointCount == 0)
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
        #expect(fixture.controller.finalizedSyncState == .synced)
        let saved = try await fixture.store.storedSession(captureID: fixture.capture.id, scope: fixture.scope)
        #expect(saved.manifest?.count == 1 && saved.manifest?.first?.expectedPointCount == 0)
        #expect(fixture.controller.lessonTimes(lessonID: fixture.capture.lessonId) != nil)
    }

    @Test func liveObservationUsesOnlyDurableFreshPointsAndFlushesWithoutPausing() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        #expect(fixture.controller.observationAnchor(at: Date()) == nil)
        try await Task.sleep(for: .milliseconds(5))
        let measured = try #require(fixture.source.emitPoint())
        // The callback has queued its transaction; its position is not durable yet.
        #expect(fixture.controller.observationAnchor(at: measured) == nil)
        for _ in 0..<300 {
            if fixture.controller.pointCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let anchor = try #require(fixture.controller.observationAnchor(at: measured.addingTimeInterval(1)))
        #expect(anchor.captureID == fixture.capture.id && anchor.pointSequence == 0)
        #expect(fixture.controller.observationAnchor(at: measured.addingTimeInterval(16)) == nil)
        #expect(fixture.controller.observationAnchor(at: measured.addingTimeInterval(-1)) == nil)
        try await fixture.store.flushForObservation(captureID: anchor.captureID, segmentID: anchor.segmentID,
            sequence: anchor.pointSequence, scope: fixture.scope)
        try await fixture.store.flushForObservation(captureID: anchor.captureID, segmentID: anchor.segmentID,
            sequence: anchor.pointSequence, scope: fixture.scope)
        let queue = try await fixture.store.pending(scope: fixture.scope, deviceID: fixture.capture.deviceId)
        let chunks = queue.filter { $0.mutation.kind == .uploadChunk }
        #expect(chunks.count == 1)
        let queued = try #require(chunks.first)
        let chunk = try JSONDecoder().decode(SchoolCaptureChunkBody.self, from: queued.mutation.body)
        #expect(chunk.points.count == 1 && chunk.points.first?.sequence == 0)
        #expect(fixture.controller.isCollecting && fixture.controller.segments.count == 1)
        await fixture.controller.pause()
        #expect(fixture.controller.observationAnchor(at: measured.addingTimeInterval(1)) == nil)
    }

    @Test func aSignalGapResumesLocallyInANewSegmentWithoutASecondAuthorization() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        let count = await fixture.server.requests().count
        let boundary = try #require(fixture.source.stop())
        fixture.source.onEvent?(.interrupted(.signalLost, boundary))
        for _ in 0..<300 {
            if fixture.controller.isCollecting && fixture.controller.segments.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fixture.controller.isCollecting && fixture.source.isRunning)
        #expect(fixture.controller.segments.count == 2 && fixture.controller.pointCount == 0)
        #expect(await fixture.server.requests().count == count)
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    @Test func displayedAnchorPreservesDurableSequenceAfterAnImpreciseDeparture() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        let imprecise = try #require(fixture.source.emitPoint(accuracyMeters: 100))
        for _ in 0..<300 {
            if fixture.controller.pointCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fixture.controller.pointCount == 1)
        #expect(fixture.controller.displayedPointCount == 0)
        #expect(fixture.controller.observationAnchor(at: imprecise.addingTimeInterval(1)) == nil)
        try await Task.sleep(for: .milliseconds(5))
        let precise = try #require(fixture.source.emitPoint())
        for _ in 0..<300 {
            if fixture.controller.pointCount == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fixture.controller.pointCount == 2)
        #expect(fixture.controller.displayedPointCount == 1)
        let anchor = try #require(fixture.controller.observationAnchor(at: precise.addingTimeInterval(1)))
        #expect(anchor.pointSequence == 1)
        try await fixture.store.flushForObservation(captureID: anchor.captureID, segmentID: anchor.segmentID,
            sequence: anchor.pointSequence, scope: fixture.scope)
        let queue = try await fixture.store.pending(scope: fixture.scope, deviceID: fixture.capture.deviceId)
        let chunkData = try #require(queue.first(where: { $0.mutation.kind == .uploadChunk })?.mutation.body)
        let chunk = try JSONDecoder().decode(SchoolCaptureChunkBody.self, from: chunkData)
        #expect(chunk.points.map(\.sequence) == [0, 1])
        #expect(chunk.points.first?.accuracyMeters == 100)
        try await Task.sleep(for: .milliseconds(5))
        let rejected = try #require(fixture.source.emitPoint(accuracyMeters: 100))
        for _ in 0..<300 {
            if fixture.controller.pointCount == 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fixture.controller.observationAnchor(at: rejected.addingTimeInterval(1)) == nil)
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    @Test func closingTheLessonDoesNotCancelDurableSynchronization() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        await fixture.server.holdTransfers()
        #expect(await fixture.controller.finishForLesson(lessonID: fixture.capture.lessonId))
        #expect(!fixture.source.isRunning)
        let saved = try await fixture.store.storedSession(captureID: fixture.capture.id, scope: fixture.scope)
        #expect(saved.state == .stopped && saved.stopOperationID != nil && saved.manifest != nil)
        fixture.controller.closeLessonFlow(lessonID: fixture.capture.lessonId)
        #expect(fixture.controller.captureID == nil)
        await fixture.server.releaseTransfers()
        for _ in 0..<300 {
            if try await fixture.store.acknowledgedFinalizations(scope: fixture.scope)[fixture.capture.id] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let acknowledged = try await fixture.store.acknowledgedFinalizations(scope: fixture.scope)
        #expect(acknowledged[fixture.capture.id]?.syncState == .synced)
        let sent = await fixture.server.requests()
        #expect(sent.filter { $0.url?.lastPathComponent == "stop" }.count == 1)
        #expect(sent.filter { $0.url?.lastPathComponent == "finalize" }.count == 1)
    }

    @Test func lostFinalizationResponseRetriesTheSameDurableOperation() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        await fixture.server.loseNextFinalizationResponse()
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
        #expect(fixture.controller.synchronizationNeedsRetry && fixture.controller.finalizedSyncState == nil)
        let queue = try await fixture.store.pending(scope: fixture.scope, deviceID: fixture.capture.deviceId)
        let pending = try #require(queue.first { $0.mutation.kind == .finalizeCapture })
        await fixture.controller.retrySynchronization()
        #expect(fixture.controller.finalizedSyncState == .synced && !fixture.controller.synchronizationNeedsRetry)
        let sent = await fixture.server.requests().filter { $0.url?.lastPathComponent == "finalize" }
        #expect(sent.count == 2 && sent[0].httpBody == sent[1].httpBody)
        #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == pending.id.uuidString })
        let body = try JSONDecoder().decode(SchoolFinalizeCaptureBody.self, from: pending.mutation.body)
        #expect(!body.allowPartial)
    }

    @Test func concurrentLessonCompletionVersionIsReconciledWithoutAnotherUserAction() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        await fixture.server.conflictNextFinalization()
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
        #expect(fixture.controller.finalizedSyncState == .synced && !fixture.controller.synchronizationNeedsRetry)
        let sent = await fixture.server.requests().filter { $0.url?.lastPathComponent == "finalize" }
        #expect(sent.count == 2)
        #expect(sent[0].value(forHTTPHeaderField: "Idempotency-Key") != sent[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(sent[0].value(forHTTPHeaderField: "If-Match") != sent[1].value(forHTTPHeaderField: "If-Match"))
    }

    @Test func returningToTheAppReplaysAClosedLessonsPendingFinalization() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        await fixture.server.loseNextFinalizationResponse()
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
        fixture.controller.closeLessonFlow(lessonID: fixture.capture.lessonId)
        #expect(fixture.controller.pendingSynchronizationError != nil)
        #expect(fixture.controller.pendingSynchronizationCount == 1)

        // Comme au prochain lancement, aucun contexte GPS n'est restauré.
        let resumed = SchoolCaptureSessionController(store: fixture.store)
        resumed.setScope(fixture.scope)
        let client = SchoolCaptureClient(baseURL: URL(string: fixture.scope.apiBaseURL)!, tokenSource: HubToken(), transport: fixture.server)
        await resumed.resumePendingSynchronizations(client: client, scope: fixture.scope)
        for _ in 0..<300 {
            if resumed.pendingSynchronizationCount == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(resumed.pendingSynchronizationCount == 0 && resumed.pendingSynchronizationError == nil)
        #expect(resumed.captureID == nil && !resumed.isCollecting)
        let sent = await fixture.server.requests().filter { $0.url?.lastPathComponent == "finalize" }
        #expect(sent.count == 2 && sent[0].httpBody == sent[1].httpBody)
        #expect(sent[0].value(forHTTPHeaderField: "Idempotency-Key") == sent[1].value(forHTTPHeaderField: "Idempotency-Key"))
        resumed.setScope(nil)
    }

    @Test func signingOutPreventsPendingCaptureReplay() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        await fixture.server.loseNextFinalizationResponse()
        #expect(await fixture.controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
        let before = await fixture.server.requests().count
        fixture.controller.setScope(nil)
        let client = SchoolCaptureClient(baseURL: URL(string: fixture.scope.apiBaseURL)!, tokenSource: HubToken(), transport: fixture.server)
        await fixture.controller.resumePendingSynchronizations(client: client, scope: fixture.scope)
        #expect(await fixture.server.requests().count == before)
        #expect(fixture.controller.pendingSynchronizationError == nil)
        let pending = try await fixture.store.pending(scope: fixture.scope, deviceID: fixture.capture.deviceId)
        #expect(pending.contains { $0.mutation.kind == .finalizeCapture })
    }

    @Test func pauseThenResumeNeverPresentAnIntermediateState() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        let controller = fixture.controller
        #expect(controller.presentedState == .recording && controller.transition == nil)
        let pausing = Task { await controller.pause() }
        var deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.state != .paused, ContinuousClock.now < deadline {
            // Pause pas encore écrite : l’écran garde « en route », sans « sauvegarde » ni commande grisée.
            #expect(controller.presentedState == .recording && controller.isCollecting)
            #expect(controller.presentsPauseEnabled && controller.presentsStopEnabled)
            await Task.yield()
        }
        await pausing.value
        #expect(controller.state == .paused && controller.presentedState == .paused && controller.transition == nil)
        #expect(controller.presentsResumeEnabled && !controller.presentsPauseEnabled && controller.presentsStopEnabled)
        #expect(!fixture.source.isRunning && controller.segments.count == 1)

        let resuming = Task { await controller.resume() }
        deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.state != .recording, ContinuousClock.now < deadline {
            // Reprise pas encore confirmée : l’écran garde « en pause », sans « préparation ».
            #expect(controller.presentedState == .paused && !controller.isCollecting)
            #expect(controller.presentsResumeEnabled && controller.presentsStopEnabled)
            await Task.yield()
        }
        await resuming.value
        #expect(controller.state == .recording && controller.presentedState == .recording && controller.transition == nil)
        #expect(fixture.source.isRunning && controller.segments.count == 2)
        #expect(await controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    @Test func aSignalGapKeepsTheRecordingStateOnScreenWhileItsNewSegmentOpens() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        let controller = fixture.controller
        let boundary = try #require(fixture.source.stop())
        fixture.source.onEvent?(.interrupted(.signalLost, boundary))
        // État réel protégé (aucune mesure admise), état présenté inchangé.
        #expect(controller.state == .stopping && controller.transition == .recoveringSignal)
        #expect(!controller.canPause && controller.observationAnchor(at: Date()) == nil)
        #expect(controller.presentedState == .recording && controller.isCollecting)
        #expect(controller.presentsPauseEnabled && controller.presentsStopEnabled)
        for _ in 0..<300 {
            #expect(controller.presentedState == .recording)
            if controller.segments.count == 2 && controller.transition == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.state == .recording && controller.transition == nil && controller.segments.count == 2)
        #expect(await controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    @Test func endingTheLessonDuringAResumeReplacesTheTransitionOnScreen() async throws {
        let fixture = try await CaptureLifecycleFixture.make()
        let controller = fixture.controller
        await controller.pause()
        #expect(controller.state == .paused)
        await fixture.server.holdTransfers()
        let resuming = Task { await controller.resume() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.transition != .resuming, ContinuousClock.now < deadline { await Task.yield() }
        #expect(controller.state == .preparing && controller.presentedState == .paused && controller.presentsStopEnabled)
        // La fin de leçon n’attend pas la relecture de l’école ; l’écran quitte aussitôt l’état « en pause ».
        #expect(await controller.stopAndSynchronize())
        #expect(controller.state == .saved && controller.presentedState == .saved && controller.transition == nil)
        await fixture.server.releaseTransfers()
        await resuming.value
        await fixture.waitUntilSettled()
        #expect(controller.state == .saved && controller.transition == nil && !fixture.source.isRunning)
    }
}

@MainActor private struct CaptureLifecycleFixture {
    let scope: SchoolCommandScope
    let capture: SchoolCaptureSession
    let store: SQLCipherSchoolCaptureStore
    let server: CaptureLifecycleServer
    let source: CaptureLifecycleSource
    let controller: SchoolCaptureSessionController

    static func make(startImmediately: Bool = true) async throws -> Self {
        let scope = ConfigurationFixture.scope(), device = UUID(), operation = UUID()
        let time = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 1)
        let stamp = SchoolCaptureLocationTime.timestamp
        let capture = SchoolCaptureSession(id: UUID(), schoolId: scope.schoolID, version: 1, lessonId: UUID(), learnerId: UUID(),
            instructorMembershipId: scope.membershipID, deviceId: device, choiceId: UUID(), authorizedAt: stamp(time),
            expiresAt: stamp(time.addingTimeInterval(3600)), stoppedAt: nil, cutoffAt: nil,
            uploadDeadline: stamp(time.addingTimeInterval(86_400)), captureState: .authorized, syncState: .localOnly,
            publicationState: .privateCapture, deviceAssessmentId: UUID())
        let key = Curve25519.Signing.PrivateKey()
        func base64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        func token(_ purpose: String, expiry: String) throws -> String {
            let header = try JSONSerialization.data(withJSONObject: ["alg": "EdDSA", "typ": "drivy-capture+jwt", "kid": "test"])
            let claims: [String: Any] = ["iss": scope.apiBaseURL, "aud": "drivy-native-capture", "sub": scope.personID.uuidString,
                "jti": "\(capture.id.uuidString.lowercased()):\(purpose)", "iat": Int(time.timeIntervalSince1970),
                "exp": Int(SchoolLesson.date(expiry)!.timeIntervalSince1970), "scope": purpose,
                "schoolId": scope.schoolID.uuidString, "captureId": capture.id.uuidString, "lessonId": capture.lessonId.uuidString,
                "deviceId": device.uuidString, "deviceAssessmentId": capture.deviceAssessmentId.uuidString,
                "authorizedAt": capture.authorizedAt, "expiresAt": capture.expiresAt, "uploadDeadline": capture.uploadDeadline]
            let encoded = "\(base64(header)).\(base64(try JSONSerialization.data(withJSONObject: claims)))"
            return "\(encoded).\(base64(try key.signature(for: Data(encoded.utf8))))"
        }
        let authorization = try SchoolCaptureAuthorization(capture: capture,
            signedCaptureAuthorization: token("capture:collect", expiry: capture.expiresAt), serverTime: stamp(time),
            signedUploadAuthorization: token("capture:upload", expiry: capture.uploadDeadline))
        let keys = SchoolCapturePublicKeys(keys: [.init(kty: "OKP", crv: "Ed25519", x: base64(key.publicKey.rawRepresentation), kid: "test", alg: "EdDSA", use: "sig")])
        let received = ContinuousClock.now
        let lease = try SchoolCaptureAuthorizationVerifier.verify(authorization, keys: keys, expectedIssuer: URL(string: scope.apiBaseURL)!,
            scope: scope, lessonID: capture.lessonId, deviceID: device, assessmentID: capture.deviceAssessmentId, requestStartedAt: received)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-lifecycle-\(UUID()).sqlite")
        let store = try SQLCipherSchoolCaptureStore(url: url, key: Data(repeating: 0x3D, count: 32), protectFiles: false, installationID: device)
        let server = CaptureLifecycleServer(scope: scope, capture: capture, authorization: authorization, keys: keys)
        let client = SchoolCaptureClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store, stopCollection: { _ in })
        let controller = SchoolCaptureSessionController(store: store), source = CaptureLifecycleSource()
        controller.setScope(scope)
        if startImmediately {
            let command = try SchoolCapturePendingMutation.make(id: operation, scope: scope, kind: .startCapture,
                targetID: capture.lessonId, expectedVersion: 1, body: SchoolStartCaptureBody(operationId: operation, deviceId: device,
                    choiceId: capture.choiceId, choiceVersion: 1, noticeVersionId: UUID(), explicitStartConfirmed: true, deviceAssessmentId: capture.deviceAssessmentId))
            try await store.stage(command)
            _ = try await store.markAttempted(id: operation, scope: scope)
            let session = try await store.acceptAuthorization(operationID: operation, authorization: authorization, lease: lease, scope: scope, deviceID: device)
            try await controller.adoptAndStart(transfer: transfer, source: source, session: session, lease: lease,
                authorization: authorization, receivedAt: received)
        }
        return Self(scope: scope, capture: capture, store: store, server: server, source: source, controller: controller)
    }

    func preparation(holdAdoption: Bool = false) -> SchoolCapturePreparationWorkspace {
        let agenda = SchoolAgendaClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: server)
        return SchoolCapturePreparationWorkspace(scope: scope, lessonID: capture.lessonId, client: agenda.captureClient,
            reader: agenda.reader, agenda: agenda, store: store, onCaptureAuthorized: { transfer, source, session, lease, authorization, received in
                if holdAdoption { await server.holdScopeReads() }
                try await controller.adoptAndStart(transfer: transfer, source: source, session: session, lease: lease,
                    authorization: authorization, receivedAt: received)
            }, onRefusalConfirmed: { _, _ in }, canUseDiagnostic: { controller.canPrepareCapture }, makeLocationSource: { source })
    }

    func waitForScopeRead(model: SchoolCapturePreparationWorkspace, starting: Task<Bool, Never>) async throws {
        for _ in 0..<600 {
            if await server.isWaitingForScope() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let waiting = await server.isWaitingForScope()
        let diagnostic = "Lecture des droits non atteinte : \(String(describing: model.quickBlock)); \(model.errorMessage ?? "aucune erreur de préparation")."
        if !waiting {
            starting.cancel()
            model.invalidate()
            await server.releaseScopeReads()
            _ = await starting.value
        }
        try #require(waiting, "\(diagnostic)")
    }

    func waitUntilSettled() async {
        for _ in 0..<300 {
            if !controller.isTransferring { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.isTransferring)
    }
}

@MainActor private final class CaptureLifecycleSource: SchoolCaptureLocationProviding {
    var onEvent: (@MainActor (SchoolCaptureLocationEvent) -> Void)?
    var permission: SchoolCaptureLocationPermission { .foreground }
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var warmUps = 0
    private var warming = false
    var isWarming: Bool { warming }
    func warmUp() { warmUps += 1; warming = true }
    func coolDown() { warming = false }
    private var segment: SchoolCaptureLocationSegment?
    private var handle: SchoolCaptureSegmentHandle?
    private var boundary: SchoolCaptureLocationStop?
    func requestPermission() {}
    func requestDiagnosticSample() throws { Task { onEvent?(.diagnosticChanged) } }
    func diagnosticSnapshot() throws -> SchoolCaptureDeviceSnapshot {
        .init(permission: .foreground, preciseLocation: true, deviceClass: "PHONE", modelCode: "test-phone",
            osVersion: "26.0", appBuild: "1", sampleAgeSeconds: 0, horizontalAccuracyMeters: 5, availableBytesLocally: nil)
    }
    func diagnosticBody(operationID: UUID, networkAvailable: Bool) throws -> SchoolDeviceAssessmentBody {
        .init(operationId: operationID, platform: "IOS", deviceClass: "PHONE", modelCode: "test-phone",
            osVersion: "26.0", appBuild: "1", permission: permission.assessmentValue, preciseLocation: true,
            sampleAgeSeconds: 0, horizontalAccuracyMeters: 5, freeBytes: nil, networkAvailable: networkAvailable)
    }
    func updateScope(_ scope: SchoolCommandScope?) {}
    func prepareSegment(authorization: SchoolCaptureAuthorization, lease: SchoolCaptureLease, scope: SchoolCommandScope,
                        clockReference: SchoolCaptureClockReference, policy: SchoolCaptureLocationPolicy) throws -> SchoolCaptureLocationSegment {
        let now = ContinuousClock.now
        let mapped = SchoolCaptureLocationTime.millisecondDate(clockReference.serverTime.addingTimeInterval(SchoolCaptureLocationTime.seconds(clockReference.receivedAt.duration(to: now))))
        return .init(id: UUID(), captureID: lease.captureID, scope: scope, startedAt: SchoolCaptureLocationTime.timestamp(mapped),
            lease: lease, policy: policy, wallStartedAt: Date(), monotonicStartedAt: now, mappedStartedAt: mapped)
    }
    func start(segment: SchoolCaptureLocationSegment, handle: SchoolCaptureSegmentHandle) throws {
        self.segment = segment; self.handle = handle; isRunning = true; startCount += 1; boundary = nil
    }
    func emitPoint(accuracyMeters: Double = 5) -> Date? {
        guard isRunning, let segment, let handle else { return nil }
        let elapsed = max(1, Int(SchoolCaptureLocationTime.seconds(segment.monotonicStartedAt.duration(to: .now)) * 1000))
        let date = segment.mappedStartedAt.addingTimeInterval(Double(elapsed) / 1000)
        onEvent?(.measurements(handle: handle, values: [.init(capturedAt: SchoolCaptureLocationTime.timestamp(date),
            elapsedMs: elapsed, latitude: 47, longitude: 7, accuracyMeters: accuracyMeters)]))
        return date
    }
    func stop() -> SchoolCaptureLocationStop? {
        guard isRunning, let segment, let handle else { return boundary }
        isRunning = false
        boundary = .init(handle: handle, stoppedAt: SchoolCaptureLocationTime.timestamp(segment.mappedDate(at: .now)))
        return boundary
    }
}

private actor CaptureLifecycleServer: SchoolHTTPTransport {
    private let scope: SchoolCommandScope
    private var capture: SchoolCaptureSession
    private let authorization: SchoolCaptureAuthorization
    private let keys: SchoolCapturePublicKeys
    private let noticeID = UUID()
    private var scopeHeld = false, scopeRefused = false
    private var failsScopeAfterAuthorization = false, failsNextScopeRead = false
    private var scopeWaiters: [CheckedContinuation<Void, Never>] = []
    private var recorded: [URLRequest] = []
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var loseFinalization = false
    private var conflictFinalization = false
    private var finalized: [UUID: SchoolCaptureSession] = [:]
    init(scope: SchoolCommandScope, capture: SchoolCaptureSession, authorization: SchoolCaptureAuthorization, keys: SchoolCapturePublicKeys) {
        self.scope = scope; self.capture = capture; self.authorization = authorization; self.keys = keys
    }
    func requests() -> [URLRequest] { recorded }
    func holdScopeReads() { scopeHeld = true }
    func failScopeReadAfterNextAuthorization() { failsScopeAfterAuthorization = true }
    func isWaitingForScope() -> Bool { !scopeWaiters.isEmpty }
    func releaseScopeReads(refused: Bool = false) {
        scopeHeld = false; scopeRefused = refused
        let values = scopeWaiters; scopeWaiters = []; for item in values { item.resume() }
    }
    func holdTransfers() { held = true }
    func releaseTransfers() { held = false; let values = waiters; waiters = []; for item in values { item.resume() } }
    func loseNextFinalizationResponse() { loseFinalization = true }
    func conflictNextFinalization() { conflictFinalization = true }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        let url = request.url!
        func json(_ value: Any) throws -> SchoolHTTPResponse {
            // Les créations de diagnostic et de capture répondent 201 ; le client refuse correctement un simple 200.
            let created = request.httpMethod == "POST" && ["assessments", "captures"].contains(url.lastPathComponent)
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": capture.authorizedAt]), status: created ? 201 : 200, url: url, contentType: "application/json")
        }
        func ok<T: Encodable>(_ value: T) throws -> SchoolHTTPResponse {
            try json(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)))
        }
        if url.lastPathComponent == "me" {
            if scopeHeld { await withCheckedContinuation { scopeWaiters.append($0) } }
            if failsNextScopeRead { failsNextScopeRead = false; throw URLError(.notConnectedToInternet) }
            if scopeRefused {
                return SchoolHTTPResponse(data: Data("{\"code\":\"FORBIDDEN\"}".utf8), status: 403,
                    url: url, contentType: "application/problem+json")
            }
            return try ok(SchoolPerson(personId: scope.personID, version: 1, displayName: "Moniteur synthétique", locale: "fr",
                memberships: [.init(membershipId: scope.membershipID, schoolId: scope.schoolID, schoolName: "École synthétique",
                    roles: ["INSTRUCTOR"], grants: [], accessEpoch: scope.accessEpoch)]))
        }
        if held { await withCheckedContinuation { waiters.append($0) } }
        let leaf = url.lastPathComponent.lowercased()
        if leaf == "capture-keys" {
            return try json(["keys": keys.keys.map { ["kty": $0.kty, "crv": $0.crv, "x": $0.x,
                "kid": $0.kid, "alg": $0.alg, "use": $0.use] }])
        }
        if leaf == scope.schoolID.uuidString.lowercased() {
            return try json(["id": scope.schoolID.uuidString, "schoolId": scope.schoolID.uuidString, "version": 1,
                "name": "École synthétique", "timeZone": "Europe/Zurich", "status": "ACTIVE", "contactEmail": "ecole@example.invalid",
                "contactPhone": NSNull(), "logoAssetId": NSNull(), "configurationVersion": 1,
                "modules": ["gpsEnabled": true, "packsEnabled": false, "collectiveCoursesEnabled": false, "courseOffersVisibleByDefault": false]])
        }
        if leaf == capture.lessonId.uuidString.lowercased() {
            return try ok(SchoolLesson(id: capture.lessonId, schoolId: scope.schoolID, version: 1, trainingId: HubFixture.trainingID,
                learnerId: capture.learnerId, instructorMembershipId: scope.membershipID, plannedStart: capture.authorizedAt,
                plannedEnd: capture.expiresAt, timeZone: "Europe/Zurich", meetingPoint: "", status: "PLANNED", priceCentsSnapshot: 9000,
                bufferMinutesSnapshot: 10, actualStart: capture.authorizedAt, actualEnd: nil, permitWarning: false,
                publicationVersion: 0, currentPublishedRevisionId: nil, commercialRevisionVersion: 1))
        }
        if leaf == capture.learnerId.uuidString.lowercased() {
            return try json(["id": capture.learnerId.uuidString, "schoolId": scope.schoolID.uuidString, "personId": UUID().uuidString,
                "version": 1, "displayName": "Élève synthétique", "contactEmail": NSNull(), "contactPhone": NSNull(), "archivedAt": NSNull(),
                "profileReadiness": NSNull(), "profilePhotoDocumentId": NSNull()])
        }
        if leaf == "recording-notice" {
            return try json(["noticeVersionId": noticeID.uuidString, "noticeText": "Information GPS synthétique",
                "retentionText": "Conservation de test", "contactEmail": "ecole@example.invalid", "approvedAt": capture.authorizedAt])
        }
        if leaf == "recording-choice" {
            return try ok(SchoolRecordingChoice(id: capture.choiceId, schoolId: scope.schoolID, version: 1,
                learnerId: capture.learnerId, lessonId: capture.lessonId, status: .allowed, noticeVersionId: noticeID,
                recordedBy: scope.membershipID, recordedAt: capture.authorizedAt, source: .verbal))
        }
        if leaf == "assessments" || leaf == capture.deviceAssessmentId.uuidString.lowercased() {
            return try ok(SchoolDeviceAssessment(id: capture.deviceAssessmentId, schoolId: scope.schoolID, version: 1,
                deviceId: capture.deviceId, membershipId: scope.membershipID, platform: "IOS", deviceClass: "PHONE",
                modelCode: "test-phone", osVersion: "26.0", appBuild: "1", qualificationProfileVersion: "test",
                status: .qualified, assessedAt: capture.authorizedAt, expiresAt: capture.expiresAt, blockers: []))
        }
        if leaf == "captures", request.httpMethod == "POST" {
            if failsScopeAfterAuthorization { failsScopeAfterAuthorization = false; failsNextScopeRead = true }
            return try ok(authorization)
        }
        if url.lastPathComponent == "stop" {
            let body = try JSONDecoder().decode(SchoolStopCaptureBody.self, from: request.httpBody!)
            capture = changed(stoppedAt: body.stoppedAt, sync: .uploading)
        } else if url.lastPathComponent == "finalize" {
            let body = try JSONDecoder().decode(SchoolFinalizeCaptureBody.self, from: request.httpBody!)
            if let prior = finalized[body.operationId] { return try ok(prior) }
            if conflictFinalization {
                conflictFinalization = false; capture = changed(stoppedAt: capture.stoppedAt, sync: .uploading)
                return SchoolHTTPResponse(data: Data("{\"code\":\"VERSION_CONFLICT\"}".utf8), status: 412, url: url, contentType: "application/problem+json")
            }
            capture = changed(stoppedAt: capture.stoppedAt, sync: .synced)
            finalized[body.operationId] = capture
            if loseFinalization { loseFinalization = false; throw URLError(.networkConnectionLost) }
        }
        return try ok(capture)
    }
    private func changed(stoppedAt: String?, sync: SchoolCaptureSession.SyncState) -> SchoolCaptureSession {
        SchoolCaptureSession(id: capture.id, schoolId: capture.schoolId, version: capture.version + 1, lessonId: capture.lessonId,
            learnerId: capture.learnerId, instructorMembershipId: capture.instructorMembershipId, deviceId: capture.deviceId,
            choiceId: capture.choiceId, authorizedAt: capture.authorizedAt, expiresAt: capture.expiresAt, stoppedAt: stoppedAt,
            cutoffAt: stoppedAt, uploadDeadline: capture.uploadDeadline, captureState: .stopped, syncState: sync,
            publicationState: .privateCapture, deviceAssessmentId: capture.deviceAssessmentId)
    }
}
