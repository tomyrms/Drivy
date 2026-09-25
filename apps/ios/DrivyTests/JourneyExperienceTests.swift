import Foundation
import Testing
@testable import Drivy

@MainActor
struct JourneyUndoTests {
    @Test func undoErasesTheObservationDurablyWhileTheJourneyIsOpen() async throws {
        let store = MemorySessionStore(supportsRemoval: true)
        let controller = SessionController(store: store, location: JourneyTestLocationSource())
        await controller.load()
        await controller.startSession(useGPS: false)
        let context = try #require(controller.beginObservation())
        #expect(await controller.addObservation(theme: .priority, status: .attention, note: "", context: context))
        #expect(controller.canUndoObservations)
        let sessionID = try #require(controller.activeSession?.id)
        #expect(await controller.removeObservation(context.id, from: sessionID))
        #expect(controller.activeSession?.observations.isEmpty == true)
        #expect(try await store.session(id: sessionID).observations.isEmpty)
        controller.stopSession()
        await controller.awaitPendingWrites()
    }

    @Test func undoIsRefusedAfterTheStopBarrier() async throws {
        let store = MemorySessionStore(supportsRemoval: true)
        let controller = SessionController(store: store, location: JourneyTestLocationSource())
        await controller.load()
        await controller.startSession(useGPS: false)
        let context = try #require(controller.beginObservation())
        #expect(await controller.addObservation(theme: .signs, status: .positive, note: "", context: context))
        let sessionID = try #require(controller.activeSession?.id)
        controller.stopSession()
        #expect(await controller.removeObservation(context.id, from: sessionID) == false)
        await controller.awaitPendingWrites()
        #expect(try await store.session(id: sessionID).observations.count == 1)
    }

    @Test func storeWithoutRemovalNeverHidesAnObservation() async throws {
        let store = MemorySessionStore(supportsRemoval: false)
        let controller = SessionController(store: store, location: JourneyTestLocationSource())
        await controller.load()
        await controller.startSession(useGPS: false)
        let context = try #require(controller.beginObservation())
        #expect(await controller.addObservation(theme: .parking, status: .toWorkOn, note: "", context: context))
        let sessionID = try #require(controller.activeSession?.id)
        #expect(!controller.canUndoObservations)
        #expect(await controller.removeObservation(context.id, from: sessionID) == false)
        #expect(controller.activeSession?.observations.count == 1)
        #expect(try await store.session(id: sessionID).observations.count == 1)
        controller.stopSession()
        await controller.awaitPendingWrites()
    }
}

struct JourneyReplayTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func observation(at seconds: TimeInterval, status: ObservationStatus = .attention,
                             theme: ObservationTheme = .priority) -> LessonObservation {
        LessonObservation(id: UUID(), observedAt: start.addingTimeInterval(seconds), theme: theme,
                          status: status, note: "", anchorPointID: nil)
    }

    private func point(at seconds: TimeInterval, segment: UUID) -> RecordedPoint {
        let date = start.addingTimeInterval(seconds)
        return RecordedPoint(id: UUID(), timestamp: date, receivedAt: date, latitude: 46.99, longitude: 6.93,
                             accuracy: 5, segmentID: segment)
    }

    private func finished(usesGPS: Bool, points: [RecordedPoint] = [], observations: [LessonObservation] = [],
                          duration: TimeInterval = 600) -> DrivingSession {
        var session = DrivingSession(startedAt: start, usesGPS: usesGPS)
        session.points = points
        session.observations = observations
        session.state = .completed
        session.endedAt = start.addingTimeInterval(duration)
        return session
    }

    @Test func gapsCoverMissingStartSegmentChangesSilencesAndEnd() {
        let first = UUID(), second = UUID()
        let session = finished(usesGPS: true, points: [
            point(at: 30, segment: first), point(at: 35, segment: first),
            point(at: 40, segment: second), point(at: 100, segment: second),
            point(at: 105, segment: second)
        ])
        #expect(JourneyReplay.gaps(in: session) == [0...30, 35...40, 40...100, 105...600])
    }

    @Test func journeyWithoutGPSHasNoGapAndGPSWithoutPointIsOneGap() {
        #expect(JourneyReplay.gaps(in: finished(usesGPS: false)).isEmpty)
        #expect(JourneyReplay.gaps(in: finished(usesGPS: true)) == [0...600])
    }

    @Test func orderKeepsSimultaneousObservationsAndFilterApplies() {
        let a = observation(at: 50, status: .attention)
        let b = observation(at: 50, status: .positive, theme: .signs)
        let c = observation(at: 10, status: .toWorkOn)
        #expect(JourneyReplay.ordered([a, b, c]).map(\.id) == [c.id, a.id, b.id])
        var filter = JourneyObservationFilter()
        filter.statuses = [.positive, .toWorkOn]
        #expect(JourneyReplay.ordered([a, b, c], filter: filter).map(\.id) == [c.id, b.id])
        filter = JourneyObservationFilter(statuses: [], theme: .signs)
        #expect(JourneyReplay.ordered([a, b, c], filter: filter).map(\.id) == [b.id])
    }

    @Test func adjacentFollowsSelectionThenPlayhead() {
        let a = observation(at: 10), b = observation(at: 20), c = observation(at: 30)
        let ordered = [a, b, c]
        #expect(JourneyReplay.adjacent(in: ordered, selectedID: b.id, offset: 0, startedAt: start, forward: true)?.id == c.id)
        #expect(JourneyReplay.adjacent(in: ordered, selectedID: b.id, offset: 0, startedAt: start, forward: false)?.id == a.id)
        #expect(JourneyReplay.adjacent(in: ordered, selectedID: c.id, offset: 0, startedAt: start, forward: true) == nil)
        #expect(JourneyReplay.adjacent(in: ordered, selectedID: nil, offset: 15, startedAt: start, forward: true)?.id == b.id)
        #expect(JourneyReplay.adjacent(in: ordered, selectedID: nil, offset: 15, startedAt: start, forward: false)?.id == a.id)
    }

    @Test func playbackSelectsTheLastObservationPassed() {
        let a = observation(at: 10), b = observation(at: 12), c = observation(at: 30)
        #expect(JourneyReplay.crossed(in: [a, b, c], from: 9, to: 13, startedAt: start)?.id == b.id)
        #expect(JourneyReplay.crossed(in: [a, b, c], from: 10, to: 11, startedAt: start) == nil)
        #expect(JourneyReplay.crossed(in: [a, b, c], from: 13, to: 13, startedAt: start) == nil)
    }

    @Test func positionIsNeverTakenFromAStalePoint() {
        let segment = UUID()
        let session = finished(usesGPS: true, points: [point(at: 10, segment: segment), point(at: 60, segment: segment)])
        #expect(JourneyReplay.point(at: 20, in: session) != nil)
        #expect(JourneyReplay.point(at: 40, in: session) == nil)
        #expect(JourneyReplay.point(at: 5, in: session) == nil)
    }

    @Test func statsCountStatusesAndLocatedObservationsWithoutScore() {
        let segment = UUID()
        let anchor = point(at: 10, segment: segment)
        let located = LessonObservation(id: UUID(), observedAt: start.addingTimeInterval(12), theme: .roundabout,
                                        status: .positive, note: "", anchorPointID: anchor.id)
        var session = finished(usesGPS: true, points: [anchor],
                               observations: [located, observation(at: 20), observation(at: 30)], duration: 2_700)
        session.summary = "  "
        let stats = JourneyStats(session: session)
        #expect(stats.observationCount == 3)
        #expect(stats.locatedCount == 1)
        #expect(stats.unlocatedCount == 2)
        #expect(stats.count(.attention) == 2)
        #expect(stats.count(.positive) == 1)
        #expect(stats.count(.toWorkOn) == 0)
        #expect(!stats.hasSummary)
        #expect(DrivySeanceText.duration(stats.duration) == "45 min")
    }

    @Test func durationTextStaysReadable() {
        #expect(DrivySeanceText.duration(20) == "moins d’une minute")
        #expect(DrivySeanceText.duration(3_900) == "1 h 05")
        #expect(DrivySeanceText.privateObservations(3) == "Observations privées (3)")
    }
}

/// In-memory store with the same guards as the encrypted store for the undo path.
private actor MemorySessionStore: SessionStore {
    private var storage: [UUID: DrivingSession] = [:]
    private let removal: Bool

    init(supportsRemoval: Bool) { removal = supportsRemoval }

    nonisolated var supportsObservationRemoval: Bool { removal }

    func sessions() async throws -> [DrivingSession] { storage.values.sorted { $0.startedAt > $1.startedAt } }
    func session(id: UUID) async throws -> DrivingSession {
        guard let session = storage[id] else { throw SessionError.missingSession }
        return session
    }
    func create(_ session: DrivingSession) async throws {
        guard !storage.values.contains(where: { $0.state == .active }) else { throw SessionError.sessionAlreadyActive }
        storage[session.id] = session
    }
    func append(_ point: RecordedPoint, to sessionID: UUID) async throws {
        guard storage[sessionID]?.state == .active else { throw SessionError.sessionClosed }
        storage[sessionID]?.points.append(point)
    }
    func append(_ observation: LessonObservation, to sessionID: UUID) async throws {
        guard let session = storage[sessionID], session.state == .active else { throw SessionError.sessionClosed }
        if session.observations.contains(where: { $0.id == observation.id }) { return }
        storage[sessionID]?.observations.append(observation)
    }
    func finish(_ id: UUID, at date: Date, state: SessionState) async throws {
        guard storage[id]?.state == .active else { return }
        storage[id]?.state = state
        storage[id]?.endedAt = date
    }
    func updateSummary(_ text: String, for id: UUID) async throws { storage[id]?.summary = text }
    func recoverInterruptedSessions() async throws {
        for (id, session) in storage where session.state == .active { storage[id]?.state = .interrupted }
    }
    func deleteSession(_ id: UUID) async throws { storage[id] = nil }
    func removeObservation(_ observationID: UUID, from sessionID: UUID) async throws {
        guard removal else { throw SessionError.observationRemovalUnavailable }
        guard storage[sessionID]?.state == .active else { throw SessionError.sessionClosed }
        storage[sessionID]?.observations.removeAll { $0.id == observationID }
    }
}

@MainActor
private final class JourneyTestLocationSource: LocationSource {
    var permission: LocationPermission = .allowed
    var onEvent: (@MainActor (LocationEvent) -> Void)?
    func requestPermission() { onEvent?(.permission(permission)) }
    func start() { }
    func stop() { }
}
