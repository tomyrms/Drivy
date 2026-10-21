import Foundation
import Observation
import QuartzCore

/// Owned by the active capture, not the view. Only durable *real* fixes enter its window.
/// A response has no path back to the store, upload queue, trace or observation anchors.
///
/// Two uses of one answer (#90): the road *stretch* describes fixes already drawn and stays valid after newer fixes
/// arrive, so it replaces their part of the line even when it comes back late; the road *position* moves the marker
/// only while it still describes the current fix, within two seconds of emission. A newer fix therefore no longer
/// cancels the request in flight: it only withdraws the marker correction.
@MainActor @Observable
final class SchoolLiveMatchCoordinator {
    /// Marker correction for the current fix, cleared by the next fix or after its display lifetime.
    private(set) var result: SchoolLiveMatchResponse?
    /// Road stretches accepted for this segment, oldest first. Bounded; never measurements.
    private(set) var roadRoutes: [SchoolLiveRoadRoute] = []
    static let maximumRoutes = 600
    @ObservationIgnored private var window: SchoolLiveMatchWindow?
    @ObservationIgnored private var latestAcquiredElapsedMs: Int?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var contextGeneration = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var send: (@MainActor (SchoolLiveMatchRequest) async throws -> SchoolLiveMatchResponse)?
    @ObservationIgnored private var permits: (@MainActor () -> Bool)?
    @ObservationIgnored private var onAccessFailure: (@MainActor () -> Void)?
    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    @ObservationIgnored private let sleep: @MainActor (TimeInterval) async throws -> Void

    init(now: @escaping @MainActor () -> TimeInterval = { CACurrentMediaTime() },
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.now = now
        self.sleep = sleep
    }

    /// A new segment of the same capture keeps the stretches already drawn; another capture starts from none.
    func start(segmentID: UUID, permits: @escaping @MainActor () -> Bool,
               onAccessFailure: @escaping @MainActor () -> Void = {}, keepsRoutes: Bool = false,
               send: @escaping @MainActor (SchoolLiveMatchRequest) async throws -> SchoolLiveMatchResponse) {
        let kept = keepsRoutes ? roadRoutes : []
        stop()
        roadRoutes = kept
        window = SchoolLiveMatchWindow(segmentID: segmentID)
        self.permits = permits
        self.onAccessFailure = onAccessFailure
        self.send = send
    }

    /// Pause, end, revocation or scope change: nothing is in flight any more and no correction remains.
    /// The accepted stretches stay drawn until `start` for another capture or `clearRoutes`.
    func stop() {
        generation = UUID()
        contextGeneration = UUID()
        task?.cancel()
        task = nil
        expiry?.cancel()
        expiry = nil
        result = nil
        window = nil
        latestAcquiredElapsedMs = nil
        send = nil
        permits = nil
        onAccessFailure = nil
    }

    func clearRoutes() { stop(); roadRoutes = [] }

    /// Called at acquisition, before the durable append completes: the marker correction for an older fix is
    /// withdrawn at once. The request in flight continues; its stretch may still be drawn.
    func measurementArrived(segmentID: UUID, elapsedMs: Int) {
        guard window?.segmentID == segmentID else { return }
        latestAcquiredElapsedMs = max(latestAcquiredElapsedMs ?? elapsedMs, elapsedMs)
        generation = UUID()
        expiry?.cancel()
        expiry = nil
        result = nil
    }

    func appendDurable(_ measurements: [SchoolCaptureMeasurement], startingAt sequence: Int, segmentID: UUID) {
        guard !measurements.isEmpty, window?.segmentID == segmentID else { return }
        guard permits?() == true else { stop(); return }
        window?.append(measurements.enumerated().map { SchoolLiveMatchPoint(sequence: sequence + $0.offset, measurement: $0.element) })
        result = nil
        expiry?.cancel()
        expiry = nil
        let sentAt = now()
        guard measurements.last!.elapsedMs >= (latestAcquiredElapsedMs ?? 0),
              task == nil, let request = window?.request(at: sentAt), let send else { return }
        let contextGeneration = self.contextGeneration
        let fixGeneration = self.generation
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let response = try await send(request)
                guard let self, self.contextGeneration == contextGeneration else { return }
                self.task = nil
                guard !Task.isCancelled, self.permits?() == true else { return }
                if let route = response.roadRoute(for: request) { self.keep(route) }
                // The marker only for the fix it describes: no newer fix acquired since, still within its lifetime.
                guard self.generation == fixGeneration,
                      self.window?.accepts(response, for: request, sentAt: sentAt, now: self.now()) == true else { return }
                self.result = response
                let generation = self.generation
                let remaining = max(0, sentAt + SchoolLiveMatchWindow.responseLifetime - self.now())
                let sleep = self.sleep
                self.expiry = Task { [weak self] in
                    do { try await sleep(remaining) }
                    catch { return }
                    guard let self, self.generation == generation else { return }
                    self.result = nil
                    self.expiry = nil
                }
            } catch {
                guard let self, self.contextGeneration == contextGeneration else { return }
                self.task = nil
                // A known access refusal for this capture asks for revalidation; transport failures change nothing.
                if let failure = error as? SchoolCaptureFailure,
                   [.unauthorized, .forbidden, .notFound, .expired].contains(failure) {
                    self.onAccessFailure?()
                }
            }
        }
    }

    /// Stretches arrive in request order; one starting no later than the previous one replaces what it overlaps.
    private func keep(_ route: SchoolLiveRoadRoute) {
        guard let first = route.anchors.first?.sequence else { return }
        while let last = roadRoutes.last, last.segmentID == route.segmentID,
              let lastFirst = last.anchors.first?.sequence, lastFirst >= first { roadRoutes.removeLast() }
        roadRoutes.append(route)
        if roadRoutes.count > Self.maximumRoutes { roadRoutes.removeFirst(roadRoutes.count - Self.maximumRoutes) }
    }
}
