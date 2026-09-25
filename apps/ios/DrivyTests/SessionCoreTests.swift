import Foundation
import Testing
@testable import Drivy

struct SessionStoreTests {
    @Test func deletingClosedSessionRemovesItsTraceAndObservationsDurably() async throws {
        let fixture = try StoreFixture()
        let store = try fixture.open()
        let session = DrivingSession(usesGPS: true)
        try await store.create(session)
        let point = testPoint(at: session.startedAt)
        try await store.append(point, to: session.id)
        let observation = LessonObservation(id: UUID(), observedAt: session.startedAt, theme: .observation,
            status: .attention, note: "À effacer", anchorPointID: point.id)
        try await store.append(observation, to: session.id)
        await #expect(throws: SessionError.sessionStillActive) { try await store.deleteSession(session.id) }
        try await store.finish(session.id, at: session.startedAt, state: .completed)
        try await store.deleteSession(session.id)
        let reopened = try fixture.open()
        #expect(try await reopened.sessions().isEmpty)
        await #expect(throws: SessionError.missingSession) { _ = try await reopened.session(id: session.id) }
    }

    @Test func undoneObservationIsErasedDurablyOnlyWhileTheSessionIsOpen() async throws {
        let fixture = try StoreFixture()
        let store = try fixture.open()
        #expect(store.supportsObservationRemoval)
        let session = DrivingSession(usesGPS: false)
        try await store.create(session)
        let kept = LessonObservation(id: UUID(), observedAt: session.startedAt, theme: .observation,
            status: .positive, note: "", anchorPointID: nil)
        let undone = LessonObservation(id: UUID(), observedAt: session.startedAt.addingTimeInterval(1), theme: .priority,
            status: .attention, note: "Annulée", anchorPointID: nil)
        try await store.append(kept, to: session.id)
        try await store.append(undone, to: session.id)
        try await store.removeObservation(undone.id, from: session.id)
        await #expect(throws: SessionError.invalidObservation) { try await store.removeObservation(undone.id, from: session.id) }
        let reopened = try fixture.open()
        #expect(try await reopened.session(id: session.id).observations == [kept])
        try await reopened.finish(session.id, at: session.startedAt.addingTimeInterval(2), state: .completed)
        await #expect(throws: SessionError.sessionClosed) { try await reopened.removeObservation(kept.id, from: session.id) }
        #expect(try await fixture.open().session(id: session.id).observations == [kept])
    }

    @Test func encryptedPersistenceRejectsWrongKeyAndRetainsContent() async throws {
        let fixture = try StoreFixture()
        let store = try fixture.open()
        let session = DrivingSession(usesGPS: false)
        try await store.create(session)
        let secretText = "Une observation confidentielle de qualification"
        let observation = LessonObservation(id: UUID(), observedAt: session.startedAt, theme: .observation,
            status: .attention, note: secretText, anchorPointID: nil)
        try await store.append(observation, to: session.id)
        try await store.updateSummary("Bilan retrouvé après fermeture", for: session.id)

        for suffix in ["", "-wal"] {
            let url = URL(fileURLWithPath: fixture.url.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                let bytes = try Data(contentsOf: url)
                #expect(!bytes.starts(with: Data("SQLite format 3".utf8)))
                #expect(bytes.range(of: Data(secretText.utf8)) == nil)
            }
        }
        #expect(throws: (any Error).self) {
            _ = try SQLCipherSessionStore(url: fixture.url, key: Data(repeating: 0xEF, count: 32), protectFiles: false)
        }
        let reopened = try fixture.open()
        let saved = try await reopened.session(id: session.id)
        #expect(saved.observations == [observation])
        #expect(saved.summary == "Bilan retrouvé après fermeture")
    }

    @Test func interruptedSessionRecoversAtLastDurableFactWithoutResumingGPS() async throws {
        let fixture = try StoreFixture()
        let store = try fixture.open()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = DrivingSession(startedAt: start, usesGPS: true)
        try await store.create(session)
        let point = testPoint(at: start.addingTimeInterval(10))
        try await store.append(point, to: session.id)
        let observation = LessonObservation(id: UUID(), observedAt: start.addingTimeInterval(12),
            theme: .priority, status: .toWorkOn, note: "À l’arrêt", anchorPointID: point.id)
        try await store.append(observation, to: session.id)
        let reopened = try fixture.open()
        try await reopened.recoverInterruptedSessions()
        let saved = try await reopened.session(id: session.id)
        #expect(saved.state == .interrupted)
        #expect(saved.endedAt == observation.observedAt)
        #expect(saved.points == [point])
        #expect(saved.observations == [observation])
        await #expect(throws: SessionError.sessionClosed) {
            try await reopened.append(testPoint(at: start.addingTimeInterval(13)), to: session.id)
        }
    }

    @Test func onlyOneSessionCanBeActiveAndClosedSessionDoesNotReopen() async throws {
        let store = try StoreFixture().open()
        let session = DrivingSession(usesGPS: false)
        try await store.create(session)
        await #expect(throws: SessionError.sessionAlreadyActive) { try await store.create(DrivingSession(usesGPS: false)) }
        try await store.finish(session.id, at: session.startedAt.addingTimeInterval(3), state: .completed)
        try await store.finish(session.id, at: session.startedAt.addingTimeInterval(8), state: .interrupted)
        let saved = try await store.session(id: session.id)
        #expect(saved.state == .completed)
        #expect(saved.endedAt == session.startedAt.addingTimeInterval(3))
    }

    @Test func observationIdempotenceAndAnchorBelongToTheirSession() async throws {
        let store = try StoreFixture().open()
        let first = DrivingSession(usesGPS: true)
        try await store.create(first)
        let point = testPoint(at: first.startedAt)
        try await store.append(point, to: first.id)
        try await store.finish(first.id, at: first.startedAt, state: .completed)
        let second = DrivingSession(usesGPS: false)
        try await store.create(second)
        let bad = LessonObservation(id: UUID(), observedAt: second.startedAt, theme: .observation,
            status: .positive, note: "", anchorPointID: point.id)
        await #expect(throws: SessionError.invalidObservation) { try await store.append(bad, to: second.id) }
        let good = LessonObservation(id: UUID(), observedAt: second.startedAt, theme: .observation,
            status: .positive, note: "Sans position", anchorPointID: nil)
        try await store.append(good, to: second.id)
        try await store.append(good, to: second.id)
        let saved = try await store.session(id: second.id)
        #expect(saved.observations == [good])
        #expect(saved.points.isEmpty)
    }
}

struct LocationAdmissionTests {
    @Test func rejectsOldInvalidAndRepeatedMeasurements() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var admission = LocationAdmission(startedAt: start)
        #expect(admission.admit(testSample(at: start.addingTimeInterval(-1)), receivedAt: start) == nil)
        #expect(admission.admit(testSample(at: start, accuracy: -1), receivedAt: start) == nil)
        #expect(admission.admit(testSample(at: start, latitude: .nan), receivedAt: start) == nil)
        #expect(admission.admit(testSample(at: start.addingTimeInterval(3)), receivedAt: start) == nil)
        #expect(admission.admit(testSample(at: start), receivedAt: start.addingTimeInterval(31)) == nil)
        #expect(admission.admit(testSample(at: start), receivedAt: start) != nil)
        #expect(admission.admit(testSample(at: start), receivedAt: start) == nil)
    }

    @Test func gapsStartNewSegmentsWithoutInventingPositions() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var admission = LocationAdmission(startedAt: start)
        let firstResult = admission.admit(testSample(at: start), receivedAt: start)
        let first = try #require(firstResult)
        let secondResult = admission.admit(testSample(at: start.addingTimeInterval(1)), receivedAt: start.addingTimeInterval(1))
        let second = try #require(secondResult)
        #expect(first.segmentID == second.segmentID)
        admission.interrupt()
        let thirdResult = admission.admit(testSample(at: start.addingTimeInterval(2)), receivedAt: start.addingTimeInterval(2))
        let third = try #require(thirdResult)
        #expect(third.segmentID != second.segmentID)
        let fourthResult = admission.admit(testSample(at: start.addingTimeInterval(30)), receivedAt: start.addingTimeInterval(30))
        let fourth = try #require(fourthResult)
        #expect(fourth.segmentID != third.segmentID)
    }
}

@MainActor
struct SessionControllerTests {
    @Test func restoringLocationPermissionDoesNotRestartRevokedCapture() async throws {
        let store = try StoreFixture().open()
        let source = FakeLocationSource()
        source.permission = .notDetermined
        let controller = SessionController(store: store, location: source)
        await controller.load()
        await controller.startSession(useGPS: true)
        #expect(source.startCount == 0)
        source.permission = .allowed
        source.onEvent?(.permission(.allowed))
        #expect(source.startCount == 1)
        source.permission = .denied
        source.onEvent?(.permission(.denied))
        source.permission = .allowed
        source.onEvent?(.permission(.allowed))
        #expect(source.startCount == 1)
        #expect(controller.gpsStatus == .denied)
        controller.stopSession()
        await controller.awaitPendingWrites()
    }

    @Test func stopIsImmediateAndWaitsForAlreadyAdmittedCommit() async throws {
        let realStore = try StoreFixture().open()
        let gate = GateStore(base: realStore, holdsPoints: true)
        let source = FakeLocationSource()
        let controller = SessionController(store: gate, location: source)
        await controller.load()
        await controller.startSession(useGPS: true)
        let id = try #require(controller.activeSession?.id)
        source.emit(testSample(at: Date()))
        await gate.waitForPoint()
        #expect(controller.activeSession?.points.isEmpty == true)
        controller.stopSession()
        #expect(!controller.isCapturing)
        #expect(source.stopCount > 0)
        source.emit(testSample(at: Date().addingTimeInterval(0.1)))
        await gate.releasePoint()
        await controller.awaitPendingWrites()
        let saved = try await realStore.session(id: id)
        #expect(saved.points.count == 1)
        #expect(saved.state == .completed)
        #expect(controller.activeSession == nil)
    }

    @Test func frozenObservationContextAndRepeatedConfirmationKeepOneObservation() async throws {
        let store = try StoreFixture().open()
        let source = FakeLocationSource()
        let controller = SessionController(store: store, location: source)
        await controller.load()
        await controller.startSession(useGPS: true)
        source.emit(testSample(at: Date()))
        await controller.awaitPendingWrites()
        let context = try #require(controller.beginObservation())
        let firstPointID = try #require(controller.activeSession?.points.last?.id)
        source.emit(testSample(at: Date().addingTimeInterval(0.1)))
        await controller.awaitPendingWrites()
        #expect(await controller.addObservation(theme: .priority, status: .attention, note: "Repère conservé", context: context))
        #expect(await controller.addObservation(theme: .priority, status: .attention, note: "Repère conservé", context: context))
        let observation = try #require(controller.activeSession?.observations.first)
        #expect(observation.anchorPointID == firstPointID)
        #expect(observation.observedAt == context.observedAt)
        #expect(controller.activeSession?.observations.count == 1)
        controller.stopSession()
        await controller.awaitPendingWrites()
    }

    @Test func noGPSNeverStartsSourceAndRecoveredSessionDoesNotAutoResume() async throws {
        let store = try StoreFixture().open()
        let source = FakeLocationSource()
        let controller = SessionController(store: store, location: source)
        await controller.load()
        await controller.startSession(useGPS: false)
        let context = try #require(controller.beginObservation())
        #expect(await controller.addObservation(theme: .anticipation, status: .positive, note: "Sans GPS", context: context))
        #expect(source.startCount == 0)
        #expect(context.anchorPointID == nil)
        controller.stopSession()
        await controller.awaitPendingWrites()
        let reopened = SessionController(store: store, location: source)
        await reopened.load()
        #expect(reopened.activeSession == nil)
        #expect(!reopened.isCapturing)
        #expect(reopened.sessions.first?.observations.count == 1)
        #expect(source.startCount == 0)
    }

    @Test func persistenceFailureStopsSourceAndNeverAcknowledgesPoint() async throws {
        let store = try StoreFixture().open()
        let gate = GateStore(base: store, failsPoints: true)
        let source = FakeLocationSource()
        let controller = SessionController(store: gate, location: source)
        await controller.load()
        await controller.startSession(useGPS: true)
        source.emit(testSample(at: Date()))
        await controller.awaitPendingWrites()
        #expect(!controller.isCapturing)
        #expect(controller.activeSession?.points.isEmpty == true)
        #expect(controller.errorMessage != nil)
        #expect(source.stopCount > 0)
        #expect(controller.beginObservation() == nil)
    }
}

private struct StoreFixture {
    let url: URL
    let key = Data(repeating: 0xAB, count: 32)
    init() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DrivyTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("encrypted.sqlite")
    }
    func open() throws -> SQLCipherSessionStore { try SQLCipherSessionStore(url: url, key: key, protectFiles: false) }
}

private func testPoint(at date: Date) -> RecordedPoint {
    RecordedPoint(id: UUID(), timestamp: date, receivedAt: date, latitude: 46.5197, longitude: 6.6323,
        accuracy: 5, segmentID: UUID())
}

private func testSample(at date: Date, accuracy: Double = 5, latitude: Double = 46.5197) -> LocationSample {
    LocationSample(timestamp: date, latitude: latitude, longitude: 6.6323, horizontalAccuracy: accuracy)
}

@MainActor
private final class FakeLocationSource: LocationSource {
    var permission: LocationPermission = .allowed
    var onEvent: (@MainActor (LocationEvent) -> Void)?
    var startCount = 0
    var stopCount = 0
    func requestPermission() { onEvent?(.permission(permission)) }
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func emit(_ sample: LocationSample) { onEvent?(.samples([sample])) }
}

private actor GateStore: SessionStore {
    let base: SQLCipherSessionStore
    let holdsPoints: Bool
    let failsPoints: Bool
    private var pointContinuation: CheckedContinuation<Void, Never>?
    private var pointWaiters: [CheckedContinuation<Void, Never>] = []
    private var pointEntered = false
    init(base: SQLCipherSessionStore, holdsPoints: Bool = false, failsPoints: Bool = false) {
        self.base = base
        self.holdsPoints = holdsPoints
        self.failsPoints = failsPoints
    }
    func sessions() async throws -> [DrivingSession] { try await base.sessions() }
    func session(id: UUID) async throws -> DrivingSession { try await base.session(id: id) }
    func create(_ session: DrivingSession) async throws { try await base.create(session) }
    func append(_ point: RecordedPoint, to sessionID: UUID) async throws {
        pointEntered = true
        pointWaiters.forEach { $0.resume() }
        pointWaiters.removeAll()
        if failsPoints { throw SessionError.storageUnavailable }
        if holdsPoints { await withCheckedContinuation { pointContinuation = $0 } }
        try await base.append(point, to: sessionID)
    }
    func append(_ observation: LessonObservation, to sessionID: UUID) async throws { try await base.append(observation, to: sessionID) }
    func finish(_ id: UUID, at date: Date, state: SessionState) async throws { try await base.finish(id, at: date, state: state) }
    func updateSummary(_ text: String, for id: UUID) async throws { try await base.updateSummary(text, for: id) }
    func recoverInterruptedSessions() async throws { try await base.recoverInterruptedSessions() }
    func deleteSession(_ id: UUID) async throws { try await base.deleteSession(id) }
    func waitForPoint() async {
        if pointEntered { return }
        await withCheckedContinuation { pointWaiters.append($0) }
    }
    func releasePoint() { pointContinuation?.resume(); pointContinuation = nil }
}
