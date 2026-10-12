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
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false
    var isInvalidated: Bool { invalidated }

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
        defer { if current(request) { isLoading = false } }
        do {
            let currentCapture = try await client.capture(schoolID: scope.schoolID, captureID: captureID, scope: scope)
            guard current(request) else { return }
            guard currentCapture.publicationState == .privateCapture else { throw SchoolCaptureFailure.notFound }
            capture = currentCapture
            // Demandé avant les pages : la carte se dessine d’emblée sur la route, sans se redessiner ensuite.
            let matched = await client.matchedRoute(schoolID: scope.schoolID, captureID: captureID, scope: scope)
            guard current(request) else { return }
            matchedRoute = matched?.isUsable == true ? matched : nil
            var awaitsMatching = matched?.isPending == true
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
                guard current(request) else { return }
                guard page.publicationState == .privateCapture else { throw SchoolCaptureFailure.notFound }
                pages += 1
                guard pages <= 1000, !page.segments.isEmpty || page.nextCursor == nil else { throw SchoolCaptureFailure.invalidResponse }
                if let loadedQuality, loadedQuality != page.quality { throw SchoolCaptureFailure.changed }
                loadedQuality = page.quality
                quality = page.quality
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
                fragments = accumulated
                observations = knownObservations.values.sorted {
                    let lhs = $0.observedAt.flatMap(SchoolLesson.date) ?? .distantPast
                    let rhs = $1.observedAt.flatMap(SchoolLesson.date) ?? .distantPast
                    return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
                }
                // Chaque page reconstruisait toute la chronologie et redessinait tout le tracé : travail quadratique.
                if pacer.admits() { contentRevision += 1 }
                cursor = page.nextCursor
                if let cursor, !seenCursors.insert(cursor).inserted { throw SchoolCaptureFailure.invalidResponse }
            } while cursor != nil
            isComplete = true
            contentRevision += 1
            // Premier affichage d’un trajet : l’école le recale à cet instant. Le trajet mesuré est déjà à l’écran ;
            // le tracé sur route le remplace s’il arrive dans les secondes qui suivent, sinon à la prochaine ouverture.
            isLoading = false
            var attempts = 0
            while awaitsMatching, attempts < 5 {
                attempts += 1
                // Quitter l’écran pendant cette attente n’est pas une erreur de chargement.
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                let next = await client.matchedRoute(schoolID: scope.schoolID, captureID: captureID, scope: scope)
                guard current(request) else { return }
                awaitsMatching = next?.isPending == true
                if let next, next.isUsable, !next.spans.isEmpty {
                    matchedRoute = next
                    contentRevision += 1
                }
            }
        } catch is CancellationError {
            if current(request) { errorMessage = "Le chargement du trajet a été interrompu." }
        } catch {
            guard current(request) else { return }
            if let failure = error as? SchoolCaptureFailure, failure != .unavailable {
                fragments = []; observations = []; capture = nil; matchedRoute = nil
                contentRevision += 1
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Le replay n’a pas pu être chargé."
        }
    }

    func invalidate() {
        invalidated = true; generation = UUID()
        fragments = []; observations = []; capture = nil; matchedRoute = nil; isLoading = false; isComplete = false
        contentRevision += 1
        // Sans message, l’écran resterait sur « Ouverture du trajet… » sans fin.
        errorMessage = "Tes accès ont changé. Ferme le replay puis rouvre-le depuis la leçon."
    }
    private func current(_ request: UUID) -> Bool { !invalidated && generation == request }
}
