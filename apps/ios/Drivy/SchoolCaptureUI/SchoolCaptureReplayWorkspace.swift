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
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, client: SchoolCaptureClient, captureID: UUID) {
        self.scope = scope; self.client = client; self.captureID = captureID
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
        guard !invalidated, !isLoading else { return }
        let request = UUID(); generation = request
        isLoading = true; isComplete = false; errorMessage = nil
        fragments = []; observations = []; quality = nil; capture = nil
        defer { if current(request) { isLoading = false } }
        do {
            let currentCapture = try await client.capture(schoolID: scope.schoolID, captureID: captureID, scope: scope)
            guard current(request) else { return }
            guard currentCapture.publicationState == .privateCapture else { throw SchoolCaptureFailure.notFound }
            capture = currentCapture
            var cursor: String?, seenCursors = Set<String>(), pointKeys = Set<String>()
            var lastContinues = false
            var accumulated: [SchoolCaptureReplayFragment] = []
            var knownObservations: [UUID: SchoolPrivateGeoObservation] = [:]
            var pages = 0
            repeat {
                try Task.checkCancellation()
                let page = try await client.privateReplayPage(schoolID: scope.schoolID, captureID: captureID,
                    cursor: cursor, scope: scope)
                guard current(request) else { return }
                guard page.publicationState == .privateCapture else { throw SchoolCaptureFailure.notFound }
                pages += 1
                guard pages <= 1000, !page.segments.isEmpty || page.nextCursor == nil else { throw SchoolCaptureFailure.invalidResponse }
                if let quality, quality != page.quality { throw SchoolCaptureFailure.changed }
                quality = page.quality
                for (index, segment) in page.segments.enumerated() {
                    guard let first = segment.points.first, let last = segment.points.last else { throw SchoolCaptureFailure.invalidResponse }
                    for point in segment.points {
                        guard pointKeys.insert("\(segment.segmentId):\(point.sequence)").inserted,
                              pointKeys.count <= 100_000 else { throw SchoolCaptureFailure.invalidResponse }
                    }
                    if let previous = accumulated.last, let previousPoint = previous.points.last {
                        guard segment.segmentIndex >= previous.segmentIndex,
                              SchoolLesson.date(first.capturedAt)! >= SchoolLesson.date(previousPoint.capturedAt)! else {
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
                fragments = accumulated
                observations = knownObservations.values.sorted {
                    let lhs = $0.observedAt.flatMap(SchoolLesson.date) ?? .distantPast
                    let rhs = $1.observedAt.flatMap(SchoolLesson.date) ?? .distantPast
                    return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
                }
                cursor = page.nextCursor
                if let cursor, !seenCursors.insert(cursor).inserted { throw SchoolCaptureFailure.invalidResponse }
            } while cursor != nil
            isComplete = true
        } catch is CancellationError {
            if current(request) { errorMessage = "Le chargement du trajet a été interrompu." }
        } catch {
            guard current(request) else { return }
            if let failure = error as? SchoolCaptureFailure, failure != .unavailable {
                fragments = []; observations = []; capture = nil
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Le replay n’a pas pu être chargé."
        }
    }

    func invalidate() {
        invalidated = true; generation = UUID()
        fragments = []; observations = []; capture = nil; isLoading = false; isComplete = false
    }
    private func current(_ request: UUID) -> Bool { !invalidated && generation == request }
}
