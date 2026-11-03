import CryptoKit
import Foundation
import Testing
@testable import Drivy

/// #111 : réactivité de la pause, de la reprise et de l’arrêt d’un trajet.
///
/// Les doublures de `SchoolCaptureLifecycleTests` sont `private` (visibilité limitée à leur fichier) :
/// `ReactivityFixture`, `ReactivitySource` et `ReactivityServer` recopient donc le strict nécessaire,
/// avec les mêmes types, les mêmes modèles et le même transport en mémoire. Aucun code de production
/// n’est modifié par ces tests.
@MainActor
struct SchoolCaptureLifecycleReactivityTests {
    // MARK: Double appui

    /// `SchoolCaptureSessionController.pause()` : la garde `state == .recording` est franchie une seule fois,
    /// `state = .stopping` étant posé avant le premier point de suspension. Le second appui ne scelle rien.
    @Test func aSecondTapOnPauseClosesOneSegmentAndQueuesNoPauseOperation() async throws {
        let fixture = try await ReactivityFixture.make()
        let controller = fixture.controller
        let device = try #require(fixture.capture.deviceId)
        #expect(try await fixture.store.pending(scope: fixture.scope, deviceID: device).isEmpty)

        let first = Task { await controller.pause() }
        let second = Task { await controller.pause() }
        await first.value
        await second.value

        #expect(controller.state == .paused && controller.presentedState == .paused && controller.transition == nil)
        #expect(!fixture.source.isRunning && fixture.source.startCount == 1)
        #expect(controller.segments.count == 1)
        #expect(controller.presentsResumeEnabled && !controller.presentsPauseEnabled)

        let segments = try fixture.segments()
        #expect(segments.count == 1)
        #expect(segments.first?.endReason?.rawValue == "PAUSE")
        #expect(segments.first?.endedAt != nil)

        let saved = try await fixture.store.storedSession(captureID: fixture.capture.id, scope: fixture.scope)
        #expect(saved.state == .paused && saved.stopOperationID == nil && saved.manifest == nil)

        // Le contrat n’a aucune opération de pause : le second appui n’ajoute donc aucune écriture en file.
        #expect(try await fixture.store.pending(scope: fixture.scope, deviceID: device).isEmpty)

        #expect(await controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    /// `SchoolCaptureSessionController.resume()` : la garde `canResume` (`state == .paused`) n’est franchie
    /// qu’une fois, `state = .preparing` étant posé avant `openSegment`. Un seul segment est rouvert.
    @Test func aSecondTapOnResumeReopensOnlyOneSegment() async throws {
        let fixture = try await ReactivityFixture.make()
        let controller = fixture.controller
        await controller.pause()
        #expect(controller.state == .paused && controller.segments.count == 1)

        let first = Task { await controller.resume() }
        let second = Task { await controller.resume() }
        await first.value
        await second.value

        #expect(controller.state == .recording && controller.transition == nil && controller.isCollecting)
        #expect(fixture.source.isRunning && fixture.source.startCount == 2)
        #expect(controller.segments.count == 2)

        let segments = try fixture.segments()
        #expect(segments.map(\.handle.segmentIndex) == [0, 1])
        #expect(segments.last?.reason.rawValue == "RESUME")
        #expect(segments.last?.endReason == nil)

        #expect(await controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
    }

    // MARK: Pause sans réseau

    /// `pause()` n’écrit que dans le coffre (`SQLCipherSchoolCaptureStore.sealSegment`) : aucune requête ne
    /// part, même sans réseau. Au retour du réseau, `resumePendingSynchronizations` ne rejoue rien pour une
    /// pause et ne rouvre aucun segment.
    ///
    /// Écart connu : le critère « la mutation de pause part au retour du réseau avec la même clé
    /// d’idempotence » suppose une opération de pause que le contrat n’a pas (voir le bloc `withKnownIssue`).
    @Test func aPauseWithoutNetworkAppliesLocallyAndLeavesNoPauseOperationBehind() async throws {
        let fixture = try await ReactivityFixture.make()
        let controller = fixture.controller
        let device = try #require(fixture.capture.deviceId)
        try await fixture.recordPoint()

        await fixture.server.setOffline(true)
        let beforePause = await fixture.server.requests().count
        await controller.pause()

        // La pause est appliquée localement tout de suite.
        #expect(controller.state == .paused && controller.presentedState == .paused)
        #expect(!fixture.source.isRunning && controller.segments.count == 1)
        let segments = try fixture.segments()
        #expect(segments.count == 1 && segments.first?.endReason?.rawValue == "PAUSE")

        // Aucune mutation n’a été tentée : la pause ne touche pas au réseau.
        let duringPause = await fixture.server.requests().dropFirst(beforePause)
        #expect(duringPause.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == nil })

        // Le seul fait mis en file est le lot des positions scellées par la pause, pas une pause.
        let queued = try await fixture.store.pending(scope: fixture.scope, deviceID: device)
        #expect(queued.map(\.mutation.kind) == [.uploadChunk])

        // Retour du réseau : rien ne part pour la pause, rien n’est rouvert.
        await fixture.server.setOffline(false)
        let beforeReconnection = await fixture.server.requests().count
        await controller.resumePendingSynchronizations(client: fixture.client, scope: fixture.scope)
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.state == .paused && controller.segments.count == 1 && fixture.source.startCount == 1)
        let afterReconnection = await fixture.server.requests()
        #expect(afterReconnection.dropFirst(beforeReconnection).allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == nil })
        #expect(afterReconnection.filter { ["stop", "finalize"].contains($0.url?.lastPathComponent ?? "") }.isEmpty)

        let pauseRequests = afterReconnection.filter {
            $0.httpMethod == "POST" && $0.url?.lastPathComponent.lowercased() == "pause"
        }
        await withKnownIssue("La pause n’a aucune opération réseau : SchoolCaptureMutationKind n’en contient pas et l’école n’apprend la pause qu’avec le manifeste d’arrêt (endReason PAUSE). Le critère « la mutation de pause part au retour du réseau avec la même clé d’idempotence, une seule fois » ne peut donc pas être satisfait par le code actuel ; le comportement réel (pause locale immédiate, aucun envoi) est vérifié au-dessus.") {
            #expect(pauseRequests.count == 1)
        }

        #expect(await controller.stopAndSynchronize())
        await fixture.waitUntilSettled()
        controller.setScope(nil)
    }

    // MARK: Arrêt sans réseau

    /// `stopAndSynchronize()` scelle localement (`SchoolCaptureLocalCoordinator.stop`) puis seulement
    /// `scheduleSynchronization` : la source est arrêtée et l’arrêt est durable alors qu’une requête est
    /// encore en vol. Au retour du réseau, la même opération d’arrêt repart avec la même clé.
    @Test func aStopWithoutNetworkStopsTheGPSBeforeAnyNetworkAndLeavesOnceWhenTheNetworkReturns() async throws {
        let fixture = try await ReactivityFixture.make()
        let controller = fixture.controller

        // Le réseau ne répond plus : la requête de synchronisation reste en vol.
        await fixture.server.holdTransfers()
        #expect(await controller.stopAndSynchronize())
        #expect(!fixture.source.isRunning && controller.state == .saved)
        #expect(controller.segments.count == 1 && fixture.source.startCount == 1)

        let saved = try await fixture.store.storedSession(captureID: fixture.capture.id, scope: fixture.scope)
        #expect(saved.state == .stopped && saved.manifest?.count == 1)
        let stopID = saved.stopOperationID
        #expect(stopID != nil)

        // Le GPS est déjà arrêté alors qu’un échange réseau est encore suspendu.
        for _ in 0..<300 {
            if await fixture.server.isHoldingTransfers() { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await fixture.server.isHoldingTransfers())

        // Le réseau est coupé pour de bon, puis revient.
        await fixture.server.setOffline(true)
        await fixture.server.releaseTransfers()
        for _ in 0..<300 {
            if !controller.isTransferring { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.isTransferring)
        #expect(controller.finalizedSyncState == nil && controller.synchronizationNeedsRetry)
        #expect(controller.segments.count == 1 && fixture.source.startCount == 1)

        await fixture.server.setOffline(false)
        await controller.resumePendingSynchronizations(client: fixture.client, scope: fixture.scope)
        for _ in 0..<300 {
            if controller.finalizedSyncState == .synced { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.finalizedSyncState == .synced && !controller.synchronizationNeedsRetry)

        // Une seule opération d’arrêt durable, rejouée sous sa propre clé : aucune seconde écriture.
        let stops = try fixture.mutations(kind: .stopCapture)
        #expect(stops.count == 1 && stops.first?.id == stopID)
        let sent = await fixture.server.requests()
        let stopRequests = sent.filter { $0.url?.lastPathComponent == "stop" }
        #expect(!stopRequests.isEmpty)
        #expect(stopRequests.allSatisfy { $0.value(forHTTPHeaderField: "Idempotency-Key") == stopID?.uuidString })
        #expect(sent.filter { $0.url?.lastPathComponent == "finalize" }.count == 1)

        // Aucun segment n’a été rouvert et aucune position n’a été réécrite.
        #expect(controller.segments.count == 1 && fixture.source.startCount == 1)
        #expect(try fixture.segments().count == 1)
        controller.setScope(nil)
    }

    // MARK: Pause puis arrêt rapprochés

    /// Une pause en cours puis un arrêt : `stopAndSynchronize` attend le scellement de la pause
    /// (`SchoolCaptureLocalCoordinator.stop` attend `stopping`), donc le manifeste garde l’ordre
    /// pause → arrêt et l’émission envoie l’arrêt avant les lots.
    @Test func aPauseFollowedByAStopWithoutNetworkKeepsTheirOrderOnSend() async throws {
        let fixture = try await ReactivityFixture.make()
        let controller = fixture.controller
        try await fixture.recordPoint()
        try await fixture.recordPoint()

        await fixture.server.setOffline(true)
        let pausing = Task { await controller.pause() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.state == .recording, ContinuousClock.now < deadline { await Task.yield() }
        #expect(controller.state != .recording)

        #expect(await controller.stopAndSynchronize())
        await pausing.value

        #expect(controller.state == .saved && !fixture.source.isRunning)
        #expect(fixture.source.startCount == 1 && controller.segments.count == 1)
        let segments = try fixture.segments()
        #expect(segments.count == 1 && segments.first?.endReason?.rawValue == "PAUSE")

        let saved = try await fixture.store.storedSession(captureID: fixture.capture.id, scope: fixture.scope)
        #expect(saved.manifest?.map(\.endReason.rawValue) == ["PAUSE"])
        #expect(try fixture.mutations(kind: .stopCapture).count == 1)

        await fixture.server.setOffline(false)
        await controller.resumePendingSynchronizations(client: fixture.client, scope: fixture.scope)
        for _ in 0..<300 {
            if controller.finalizedSyncState == .synced { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.finalizedSyncState == .synced)

        let sent = await fixture.server.requests()
        let stopIndex = sent.firstIndex { $0.url?.lastPathComponent == "stop" }
        let chunkIndex = sent.firstIndex { $0.url?.pathComponents.dropLast().last == "chunks" }
        #expect(stopIndex != nil && chunkIndex != nil)
        if let stopIndex, let chunkIndex {
            // L’arrêt passe devant les lots : l’école apprend la fin avant le reste du trajet.
            #expect(stopIndex < chunkIndex)
        }
        #expect(controller.segments.count == 1 && fixture.source.startCount == 1)
        controller.setScope(nil)
    }
}

@MainActor
private struct ReactivityFixture {
    let scope: SchoolCommandScope
    let capture: SchoolCaptureSession
    let store: SQLCipherSchoolCaptureStore
    let server: ReactivityServer
    let source: ReactivitySource
    let controller: SchoolCaptureSessionController
    let client: SchoolCaptureClient
    let storeURL: URL

    private static let vaultKey = Data(repeating: 0x3D, count: 32)

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
                "deviceId": device.uuidString, "deviceAssessmentId": capture.deviceAssessmentId!.uuidString,
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
            scope: scope, lessonID: capture.lessonId, deviceID: device, assessmentID: capture.deviceAssessmentId!, requestStartedAt: received)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("capture-reactivity-\(UUID()).sqlite")
        let store = try SQLCipherSchoolCaptureStore(url: url, key: vaultKey, protectFiles: false, installationID: device)
        let server = ReactivityServer(scope: scope, capture: capture, authorization: authorization, keys: keys)
        let client = SchoolCaptureClient(baseURL: URL(string: scope.apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store, stopCollection: { _ in })
        let controller = SchoolCaptureSessionController(store: store), source = ReactivitySource()
        controller.setScope(scope)
        let command = try SchoolCapturePendingMutation.make(id: operation, scope: scope, kind: .startCapture,
            targetID: capture.lessonId, expectedVersion: 1, body: SchoolStartCaptureBody(operationId: operation, deviceId: device,
                choiceId: capture.choiceId, choiceVersion: 1, noticeVersionId: UUID(), explicitStartConfirmed: true,
                deviceAssessmentId: capture.deviceAssessmentId!))
        try await store.stage(command)
        _ = try await store.markAttempted(id: operation, scope: scope)
        let session = try await store.acceptAuthorization(operationID: operation, authorization: authorization, lease: lease,
            scope: scope, deviceID: device)
        try await controller.adoptAndStart(transfer: transfer, source: source, session: session, lease: lease,
            authorization: authorization, receivedAt: received)
        return Self(scope: scope, capture: capture, store: store, server: server, source: source, controller: controller,
            client: client, storeURL: url)
    }

    /// Une position de plus, attendue jusqu’à son écriture durable.
    @discardableResult
    func recordPoint(accuracyMeters: Double = 5) async throws -> Date {
        let before = controller.pointCount
        try await Task.sleep(for: .milliseconds(5))
        let measured = try #require(source.emitPoint(accuracyMeters: accuracyMeters))
        for _ in 0..<300 {
            if controller.pointCount == before + 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(controller.pointCount == before + 1)
        return measured
    }

    /// Segments réellement écrits dans le coffre, dans l’ordre de leur index. Lecture seule, hors du magasin
    /// partagé, comme les injections du fichier voisin.
    func segments() throws -> [SchoolCaptureStoredSegment] {
        let connection = try CipherConnection(url: storeURL, key: Self.vaultKey)
        return try connection.records("SELECT data FROM segment ORDER BY segment_index", as: SchoolCaptureStoredSegment.self)
    }

    /// Opérations durables de ce trajet, y compris celles déjà acquittées : une seule ligne par fait.
    func mutations(kind: SchoolCaptureMutationKind) throws -> [SchoolCaptureQueuedMutation] {
        let connection = try CipherConnection(url: storeURL, key: Self.vaultKey)
        return try connection.records("SELECT data FROM mutation WHERE kind=? ORDER BY created_at", [.text(kind.rawValue)],
            as: SchoolCaptureQueuedMutation.self)
    }

    func waitUntilSettled() async {
        for _ in 0..<300 {
            if !controller.isTransferring { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.isTransferring)
    }
}

@MainActor
private final class ReactivitySource: SchoolCaptureLocationProviding {
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

/// Transport synthétique : réseau disponible ou coupé, requêtes suspendues à la demande, tout ce qui part
/// est enregistré. Aucun contenu de personne réelle.
private actor ReactivityServer: SchoolHTTPTransport {
    private let scope: SchoolCommandScope
    private var capture: SchoolCaptureSession
    private let authorization: SchoolCaptureAuthorization
    private let keys: SchoolCapturePublicKeys
    private var recorded: [URLRequest] = []
    private var offline = false
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(scope: SchoolCommandScope, capture: SchoolCaptureSession, authorization: SchoolCaptureAuthorization,
         keys: SchoolCapturePublicKeys) {
        self.scope = scope; self.capture = capture; self.authorization = authorization; self.keys = keys
    }

    func setOffline(_ value: Bool) { offline = value }
    func holdTransfers() { held = true }
    func isHoldingTransfers() -> Bool { !waiters.isEmpty }
    func releaseTransfers() {
        held = false
        let values = waiters; waiters = []
        for item in values { item.resume() }
    }
    func requests() -> [URLRequest] { recorded }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        if offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        func json(_ value: Any) throws -> SchoolHTTPResponse {
            let created = request.httpMethod == "POST" && ["assessments", "captures"].contains(url.lastPathComponent)
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": capture.authorizedAt]), status: created ? 201 : 200, url: url, contentType: "application/json")
        }
        func ok<T: Encodable>(_ value: T) throws -> SchoolHTTPResponse {
            try json(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)))
        }
        if url.lastPathComponent == "me" {
            return try ok(SchoolPerson(personId: scope.personID, version: 1, displayName: "Moniteur synthétique", locale: "fr",
                memberships: [.init(membershipId: scope.membershipID, schoolId: scope.schoolID, schoolName: "École synthétique",
                    roles: ["INSTRUCTOR"], grants: [], accessEpoch: scope.accessEpoch)]))
        }
        if held { await withCheckedContinuation { waiters.append($0) } }
        let leaf = url.lastPathComponent.lowercased()
        if leaf == "live-match" {
            let body = try JSONDecoder().decode(SchoolLiveMatchRequest.self, from: request.httpBody!)
            let latest = body.points.last!
            return try json(["status": "UNAVAILABLE", "segmentId": body.segmentId.uuidString,
                "sequence": latest.sequence, "elapsedMs": latest.elapsedMs])
        }
        if leaf == "capture-keys" {
            return try json(["keys": keys.keys.map { ["kty": $0.kty, "crv": $0.crv, "x": $0.x,
                "kid": $0.kid, "alg": $0.alg, "use": $0.use] }])
        }
        if request.httpMethod == "PUT", url.pathComponents.dropLast().last == "chunks",
           let index = Int(url.lastPathComponent), let segment = UUID(uuidString: url.pathComponents[url.pathComponents.count - 3]) {
            let body = try JSONDecoder().decode(SchoolCaptureChunkBody.self, from: request.httpBody!)
            return try ok(SchoolCaptureChunkReceipt(captureId: capture.id, segmentId: segment, chunkIndex: index,
                contentHash: body.contentHash, acknowledgedAt: capture.authorizedAt, duplicate: false))
        }
        if leaf == "captures", request.httpMethod == "POST" {
            return try ok(authorization)
        }
        if url.lastPathComponent == "stop" {
            let body = try JSONDecoder().decode(SchoolStopCaptureBody.self, from: request.httpBody!)
            capture = changed(stoppedAt: body.stoppedAt, sync: .uploading)
        } else if url.lastPathComponent == "finalize" {
            capture = changed(stoppedAt: capture.stoppedAt, sync: .synced)
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
