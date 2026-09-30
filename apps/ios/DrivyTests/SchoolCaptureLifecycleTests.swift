import CryptoKit
import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolCaptureLifecycleTests {
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
}

@MainActor private struct CaptureLifecycleFixture {
    let scope: SchoolCommandScope
    let capture: SchoolCaptureSession
    let store: SQLCipherSchoolCaptureStore
    let server: CaptureLifecycleServer
    let source: CaptureLifecycleSource
    let controller: SchoolCaptureSessionController

    static func make() async throws -> Self {
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
        let command = try SchoolCapturePendingMutation.make(id: operation, scope: scope, kind: .startCapture,
            targetID: capture.lessonId, expectedVersion: 1, body: SchoolStartCaptureBody(operationId: operation, deviceId: device,
                choiceId: capture.choiceId, choiceVersion: 1, noticeVersionId: UUID(), explicitStartConfirmed: true, deviceAssessmentId: capture.deviceAssessmentId))
        try await store.stage(command)
        _ = try await store.markAttempted(id: operation, scope: scope)
        let session = try await store.acceptAuthorization(operationID: operation, authorization: authorization, lease: lease, scope: scope, deviceID: device)
        let server = CaptureLifecycleServer(scope: scope, capture: capture)
        let client = SchoolCaptureClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store, stopCollection: { _ in })
        let controller = SchoolCaptureSessionController(store: store), source = CaptureLifecycleSource()
        controller.setScope(scope)
        try await controller.adoptAndStart(transfer: transfer, source: source, session: session, lease: lease,
            authorization: authorization, receivedAt: received)
        return Self(scope: scope, capture: capture, store: store, server: server, source: source, controller: controller)
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
    private var segment: SchoolCaptureLocationSegment?
    private var handle: SchoolCaptureSegmentHandle?
    private var boundary: SchoolCaptureLocationStop?
    func requestPermission() {}
    func requestDiagnosticSample() throws {}
    func diagnosticSnapshot() throws -> SchoolCaptureDeviceSnapshot { throw SchoolCaptureLocationFailure.diagnosticUnavailable }
    func diagnosticBody(operationID: UUID, networkAvailable: Bool) throws -> SchoolDeviceAssessmentBody { throw SchoolCaptureLocationFailure.diagnosticUnavailable }
    func updateScope(_ scope: SchoolCommandScope?) {}
    func prepareSegment(authorization: SchoolCaptureAuthorization, lease: SchoolCaptureLease, scope: SchoolCommandScope,
                        clockReference: SchoolCaptureClockReference, policy: SchoolCaptureLocationPolicy) throws -> SchoolCaptureLocationSegment {
        let now = ContinuousClock.now
        let mapped = SchoolCaptureLocationTime.millisecondDate(clockReference.serverTime.addingTimeInterval(SchoolCaptureLocationTime.seconds(clockReference.receivedAt.duration(to: now))))
        return .init(id: UUID(), captureID: lease.captureID, scope: scope, startedAt: SchoolCaptureLocationTime.timestamp(mapped),
            lease: lease, policy: policy, wallStartedAt: Date(), monotonicStartedAt: now, mappedStartedAt: mapped)
    }
    func start(segment: SchoolCaptureLocationSegment, handle: SchoolCaptureSegmentHandle) throws {
        self.segment = segment; self.handle = handle; isRunning = true; boundary = nil
    }
    func emitPoint() -> Date? {
        guard isRunning, let segment, let handle else { return nil }
        let elapsed = max(1, Int(SchoolCaptureLocationTime.seconds(segment.monotonicStartedAt.duration(to: .now)) * 1000))
        let date = segment.mappedStartedAt.addingTimeInterval(Double(elapsed) / 1000)
        onEvent?(.measurements(handle: handle, values: [.init(capturedAt: SchoolCaptureLocationTime.timestamp(date),
            elapsedMs: elapsed, latitude: 47, longitude: 7, accuracyMeters: 5)]))
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
    private var recorded: [URLRequest] = []
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var loseFinalization = false
    private var conflictFinalization = false
    private var finalized: [UUID: SchoolCaptureSession] = [:]
    init(scope: SchoolCommandScope, capture: SchoolCaptureSession) { self.scope = scope; self.capture = capture }
    func requests() -> [URLRequest] { recorded }
    func holdTransfers() { held = true }
    func releaseTransfers() { held = false; let values = waiters; waiters = []; for item in values { item.resume() } }
    func loseNextFinalizationResponse() { loseFinalization = true }
    func conflictNextFinalization() { conflictFinalization = true }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        let url = request.url!
        func ok<T: Encodable>(_ value: T) throws -> SchoolHTTPResponse {
            let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data, "requestId": UUID().uuidString,
                "serverTime": capture.authorizedAt]), status: 200, url: url, contentType: "application/json")
        }
        if url.lastPathComponent == "me" {
            return try ok(SchoolPerson(personId: scope.personID, version: 1, displayName: "Moniteur synthétique", locale: "fr",
                memberships: [.init(membershipId: scope.membershipID, schoolId: scope.schoolID, schoolName: "École synthétique",
                    roles: ["INSTRUCTOR"], grants: [], accessEpoch: scope.accessEpoch)]))
        }
        if held { await withCheckedContinuation { waiters.append($0) } }
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
