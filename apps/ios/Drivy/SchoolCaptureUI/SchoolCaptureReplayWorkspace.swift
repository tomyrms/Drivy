import Foundation
import Observation

struct SchoolCaptureReplayFragment: Identifiable {
    let id: String
    let segmentID: UUID
    let segmentIndex: Int
    var points: [SchoolCapturePoint]
    let hasGapBefore: Bool
    var qualityLabel: String
}

/// Espace les reconstructions de la chronologie pendant le chargement d’un long trajet : la première page,
/// puis au plus une par intervalle. La fin du chargement et le tracé recalé en déclenchent une de plus.
struct SchoolReplayRebuildPacer {
    let interval: Duration
    private var lastAdmitted: ContinuousClock.Instant?

    init(interval: Duration = .seconds(1)) { self.interval = interval }

    mutating func admits(at now: ContinuousClock.Instant = .now) -> Bool {
        if let lastAdmitted, lastAdmitted.duration(to: now) < interval { return false }
        lastAdmitted = now
        return true
    }
}

enum SchoolReplayMatchingState: Equatable {
    case idle, loading, waitingForSync, processing, matched, noReliableMatch
    case unavailable(String?), retrying(String?), deferred(String?), failed
}

/// One screen visit has a finite retry budget. Server advice is a lower bound, never a target to shorten.
struct SchoolReplayRetryBudget {
    private var attempts = 0
    mutating func nextDelay(minimum: Int, elapsed: TimeInterval) -> TimeInterval? {
        guard attempts < 6 else { return nil }
        let delay = max(Double(minimum), min(30, 2 * pow(2, Double(attempts))))
        guard elapsed + delay <= 120 else { return nil }
        attempts += 1
        return delay
    }
}

/// A private replay is reconstructed by the school. Neither local examples nor
/// published-report geometry are substituted for unavailable private points.
@MainActor @Observable final class SchoolCaptureReplayWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolCaptureClient
    let captureID: UUID
    private(set) var capture: SchoolCaptureSession?
    private(set) var fragments: [SchoolCaptureReplayFragment] = []
    private(set) var observations: [SchoolPrivateGeoObservation] = []
    private(set) var isLoading = false
    private(set) var isComplete = false
    private(set) var errorMessage: String?
    private(set) var quality: String?
    /// Tracé recalé sur la route, quand l’école en a calculé un. Jamais requis pour lire le trajet.
    private(set) var matchedRoute: SchoolMatchedRoute?
    private(set) var contentRevision = 0
    private(set) var matchingState: SchoolReplayMatchingState = .idle
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let now: @Sendable () -> TimeInterval
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false
    var isInvalidated: Bool { invalidated }

    init(scope: SchoolCommandScope, client: SchoolCaptureClient, captureID: UUID,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.scope = scope; self.client = client; self.captureID = captureID
        self.sleep = sleep; self.now = now
    }

    var pointCount: Int { fragments.reduce(0) { $0 + $1.points.count } }
    var startsAt: Date? { capture.flatMap { SchoolLesson.date($0.authorizedAt) } }
    var endsAt: Date? {
        guard let capture else { return nil }
        if let instant = capture.cutoffAt ?? capture.stoppedAt { return SchoolLesson.date(instant) }
        guard let point = fragments.last?.points.last else { return nil }
        return SchoolLesson.date(point.capturedAt)
    }

    func load() async {
        guard !invalidated, loadTask == nil, !Task.isCancelled else { return }
        let request = UUID()
        generation = request
        let task = Task { await performLoad(request) }
        loadTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if generation == request {
            loadTask = nil
            isLoading = false
        }
    }

    /// Also cancels retries started from a button, which do not belong to SwiftUI's `.task`.
    func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
        generation = UUID()
        isLoading = false
    }

    private func performLoad(_ request: UUID) async {
        guard current(request) else { return }
        isLoading = true
        errorMessage = nil
        matchingState = .loading
        var initial: SchoolMatchedRoute?
        var initialFailure: SchoolCaptureFailure?
        do {
            do {
                initial = try await client.matchedRoute(schoolID: scope.schoolID, captureID: captureID, scope: scope)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                if Self.deniesAccess(error) { throw error }
                initialFailure = (error as? SchoolCaptureFailure) ?? .invalidResponse
                // A matching outage must not prevent the measured replay from opening.
            }
            guard current(request) else { return }
            try await loadMeasurements(request, preserving: capture != nil)
            guard current(request) else { return }
            isLoading = false
            if let initialFailure, initialFailure != .unavailable && initialFailure != .changed {
                matchingState = .failed
                return
            }
            await refreshMatching(request, initial: initial)
        } catch is CancellationError {
            // Leaving the screen is not a loading failure.
        } catch {
            guard current(request) else { return }
            failMeasurements(error)
        }
    }

    private func loadMeasurements(_ request: UUID, preserving: Bool) async throws {
            let currentCapture = try await client.capture(schoolID: scope.schoolID, captureID: captureID, scope: scope)
            guard current(request) else { throw CancellationError() }
            guard currentCapture.publicationState == .privateCapture else { throw SchoolCaptureFailure.notFound }
            if !preserving { capture = currentCapture; isComplete = false }
            var cursor: String?, seenCursors = Set<String>(), pointKeys = Set<String>()
            var lastContinues = false
            var accumulated: [SchoolCaptureReplayFragment] = []
            var knownObservations: [UUID: SchoolPrivateGeoObservation] = [:]
            var pages = 0
            var loadedQuality: String?
            var pacer = SchoolReplayRebuildPacer()
            repeat {
                try Task.checkCancellation()
                let page = try await client.privateReplayPage(schoolID: scope.schoolID, captureID: captureID,
                    cursor: cursor, scope: scope)
                guard current(request) else { throw CancellationError() }
                guard page.publicationState == .privateCapture else { throw SchoolCaptureFailure.notFound }
                pages += 1
                guard pages <= 1000, !page.segments.isEmpty || page.nextCursor == nil else { throw SchoolCaptureFailure.invalidResponse }
                if let loadedQuality, loadedQuality != page.quality { throw SchoolCaptureFailure.changed }
                loadedQuality = page.quality
                if !preserving { quality = page.quality }
                for (index, segment) in page.segments.enumerated() {
                    guard let first = segment.points.first, let last = segment.points.last else { throw SchoolCaptureFailure.invalidResponse }
                    for point in segment.points {
                        guard pointKeys.insert("\(segment.segmentId):\(point.sequence)").inserted,
                              pointKeys.count <= 100_000 else { throw SchoolCaptureFailure.invalidResponse }
                    }
                    if let previous = accumulated.last, let previousPoint = previous.points.last {
                        // Une date illisible venue du serveur est une réponse invalide, jamais un plantage.
                        guard segment.segmentIndex >= previous.segmentIndex,
                              let firstDate = SchoolLesson.date(first.capturedAt),
                              let previousDate = SchoolLesson.date(previousPoint.capturedAt),
                              firstDate >= previousDate else {
                            throw SchoolCaptureFailure.invalidResponse
                        }
                        if previous.segmentID == segment.segmentId {
                            guard previous.segmentIndex == segment.segmentIndex, first.sequence > previousPoint.sequence else {
                                throw SchoolCaptureFailure.invalidResponse
                            }
                        } else if previous.segmentIndex == segment.segmentIndex { throw SchoolCaptureFailure.invalidResponse }
                    }
                    if segment.continuesFromPreviousPage {
                        guard index == 0, cursor != nil, lastContinues, !segment.hasGapBefore,
                              let previous = accumulated.last, let previousPoint = previous.points.last,
                              previous.segmentID == segment.segmentId, previous.segmentIndex == segment.segmentIndex,
                              first.sequence == previousPoint.sequence + 1 else { throw SchoolCaptureFailure.invalidResponse }
                        accumulated[accumulated.count - 1].points.append(contentsOf: segment.points)
                        if segment.qualityLabel == "LOW_ACCURACY" { accumulated[accumulated.count - 1].qualityLabel = segment.qualityLabel }
                    } else {
                        // Separate fragments remain separate polylines, including two
                        // fragments of the same segment separated by a missing chunk.
                        if index == 0 && lastContinues { throw SchoolCaptureFailure.changed }
                        accumulated.append(SchoolCaptureReplayFragment(id: "\(segment.segmentId):\(first.sequence)",
                            segmentID: segment.segmentId, segmentIndex: segment.segmentIndex,
                            points: segment.points, hasGapBefore: segment.hasGapBefore, qualityLabel: segment.qualityLabel))
                    }
                    guard !segment.continuesOnNextPage || index == page.segments.count - 1,
                          last.sequence >= first.sequence else { throw SchoolCaptureFailure.invalidResponse }
                }
                lastContinues = page.segments.last?.continuesOnNextPage == true
                if page.nextCursor == nil && lastContinues { throw SchoolCaptureFailure.invalidResponse }
                for observation in page.observations {
                    guard observation.lessonId == currentCapture.lessonId else { throw SchoolCaptureFailure.invalidResponse }
                    if let previous = knownObservations[observation.id], previous != observation { throw SchoolCaptureFailure.changed }
                    knownObservations[observation.id] = observation
                }
                if !preserving {
                    fragments = accumulated
                    observations = Self.sortedObservations(knownObservations)
                    if pacer.admits() { contentRevision += 1 }
                }
                cursor = page.nextCursor
                if let cursor, !seenCursors.insert(cursor).inserted { throw SchoolCaptureFailure.invalidResponse }
            } while cursor != nil
            capture = currentCapture
            fragments = accumulated
            observations = Self.sortedObservations(knownObservations)
            quality = loadedQuality
            // A refresh swaps all pages together, never a shorter prefix that would clamp the player.
            matchedRoute = nil
            isComplete = true
            contentRevision += 1
    }

    private static func sortedObservations(_ values: [UUID: SchoolPrivateGeoObservation]) -> [SchoolPrivateGeoObservation] {
        values.values.sorted {
            let lhs = $0.observedAt.flatMap(SchoolLesson.date) ?? .distantPast
            let rhs = $1.observedAt.flatMap(SchoolLesson.date) ?? .distantPast
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }
    }

    private func refreshMatching(_ request: UUID, initial: SchoolMatchedRoute?) async {
        var measuredVersion = initial?.reconstructionVersion
        var highestVersion = measuredVersion
        func checkVersion(_ value: SchoolMatchedRoute) throws {
            guard let version = value.reconstructionVersion else { return }
            if let highestVersion, version < highestVersion { throw SchoolCaptureFailure.changed }
            highestVersion = version
        }
        var needsSynchronizedMeasurements = initial?.reason == "WAITING_FOR_SYNC"
            || capture?.syncState == .uploading || capture?.syncState == .localOnly
        var budget = SchoolReplayRetryBudget()
        let started = now()
        var first = initial
        if initial == nil {
            matchingState = .retrying(nil)
            guard let delay = budget.nextDelay(minimum: 2, elapsed: now() - started) else {
                matchingState = .deferred(nil)
                return
            }
            do { try await sleep(.seconds(delay)) } catch { return }
        }
        while current(request) {
            var minimum: Int?
            var reason: String?
            do {
                var value: SchoolMatchedRoute
                if let first {
                    value = first
                } else {
                    value = try await client.matchedRoute(schoolID: scope.schoolID, captureID: captureID, scope: scope)
                }
                let confirmsInitialReady = first?.status == "READY"
                first = nil
                if confirmsInitialReady {
                    value = try await client.matchedRoute(schoolID: scope.schoolID, captureID: captureID, scope: scope)
                }
                guard current(request) else { return }
                try checkVersion(value)
                if value.reconstructionVersion != measuredVersion
                    || (needsSynchronizedMeasurements && value.reason != "WAITING_FOR_SYNC") {
                    // Bracket refreshed measurements with matching reads from the same reconstruction.
                    // A capture's business version is not its reconstruction version.
                    try await loadMeasurements(request, preserving: true)
                    guard current(request) else { return }
                    measuredVersion = value.reconstructionVersion
                    needsSynchronizedMeasurements = value.reason == "WAITING_FOR_SYNC"
                    if value.status == "READY" {
                        value = try await client.matchedRoute(schoolID: scope.schoolID, captureID: captureID, scope: scope)
                        guard current(request) else { return }
                        try checkVersion(value)
                    }
                }
                if value.reconstructionVersion != measuredVersion {
                    matchingState = .retrying("WAITING_FOR_SYNC")
                    minimum = value.status == "READY" ? 2 : value.suggestedRetryDelay
                    reason = "WAITING_FOR_SYNC"
                    if minimum == nil { matchingState = .deferred(reason) }
                } else {
                    needsSynchronizedMeasurements = needsSynchronizedMeasurements || value.reason == "WAITING_FOR_SYNC"
                    reason = value.reason
                    if value.status == "READY" {
                        guard value.isUsable else { matchingState = .failed; return }
                        matchedRoute = value
                        matchingState = value.spans.isEmpty ? .noReliableMatch : .matched
                        contentRevision += 1
                        return
                    }
                    if value.reason == "WAITING_FOR_SYNC" { matchingState = .waitingForSync }
                    else if value.isPending { matchingState = .processing }
                    else { matchingState = .unavailable(value.reason) }
                    minimum = value.suggestedRetryDelay
                    if minimum == nil && (matchingState == .waitingForSync || matchingState == .processing) {
                        matchingState = .deferred(reason)
                    } else if minimum != nil && value.status == "UNAVAILABLE" && value.reason != "WAITING_FOR_SYNC" {
                        matchingState = .retrying(reason)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                guard current(request) else { return }
                if Self.deniesAccess(error) { failMeasurements(error); return }
                if let failure = error as? SchoolCaptureFailure, failure == .unavailable || failure == .changed {
                    matchingState = .retrying(nil)
                    minimum = 2
                    if failure == .changed { needsSynchronizedMeasurements = true }
                } else {
                    matchingState = .failed
                    return
                }
            }
            guard let minimum else { return }
            guard let delay = budget.nextDelay(minimum: minimum, elapsed: now() - started) else {
                matchingState = .deferred(reason)
                return
            }
            do { try await sleep(.seconds(delay)) } catch { return }
        }
    }

    private static func deniesAccess(_ error: any Error) -> Bool {
        guard let failure = error as? SchoolCaptureFailure else { return false }
        return failure == .unauthorized || failure == .forbidden || failure == .notFound
    }

    private func failMeasurements(_ error: any Error) {
        if let failure = error as? SchoolCaptureFailure, failure != .unavailable {
            fragments = []; observations = []; capture = nil; matchedRoute = nil; isComplete = false
            contentRevision += 1
        }
        matchingState = .failed
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Le replay n’a pas pu être chargé."
    }

    func invalidate() {
        stopLoading()
        invalidated = true
        matchingState = .idle
        fragments = []; observations = []; capture = nil; matchedRoute = nil; isLoading = false; isComplete = false
        contentRevision += 1
        // Sans message, l’écran resterait sur « Ouverture du trajet… » sans fin.
        errorMessage = "Tes accès ont changé. Ferme le replay puis rouvre-le depuis la leçon."
    }
    private func current(_ request: UUID) -> Bool { !invalidated && generation == request && !Task.isCancelled }
}
