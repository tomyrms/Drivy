import Foundation
import Observation
import QuartzCore

/// Owned by the active capture, not the view. Only durable *real* fixes enter its window.
/// A response has no path back to the store, upload queue, trace or observation anchors.
@MainActor @Observable
final class SchoolLiveMatchCoordinator {
    private(set) var result: SchoolLiveMatchResponse?
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

    func start(segmentID: UUID, permits: @escaping @MainActor () -> Bool,
               onAccessFailure: @escaping @MainActor () -> Void = {},
               send: @escaping @MainActor (SchoolLiveMatchRequest) async throws -> SchoolLiveMatchResponse) {
        stop()
        window = SchoolLiveMatchWindow(segmentID: segmentID)
        self.permits = permits
        self.onAccessFailure = onAccessFailure
        self.send = send
    }

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

    /// Called at acquisition, before the durable append completes. An older network response
    /// cannot win the race against a newer fix still being written to the encrypted store.
    func measurementArrived(segmentID: UUID, elapsedMs: Int) {
        guard window?.segmentID == segmentID else { return }
        latestAcquiredElapsedMs = max(latestAcquiredElapsedMs ?? elapsedMs, elapsedMs)
        generation = UUID()
        task?.cancel()
        task = nil
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
        let generation = self.generation
        let contextGeneration = self.contextGeneration
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                let response = try await send(request)
                guard let self, self.generation == generation else { return }
                self.task = nil
                guard !Task.isCancelled, self.permits?() == true,
                      self.window?.accepts(response, for: request, sentAt: sentAt, now: self.now()) == true else { return }
                self.result = response
                // The total display budget starts at emission, not reception.
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
                if self.generation == generation { self.task = nil }
                // A newer fix invalidates geometry, not a known access refusal for this capture.
                if let failure = error as? SchoolCaptureFailure,
                   [.unauthorized, .forbidden, .notFound, .expired].contains(failure) {
                    self.onAccessFailure?()
                }
                // Transport/matcher failures leave the local prediction alone.
            }
        }
    }
}
