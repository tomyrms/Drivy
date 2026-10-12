import Foundation
import Network
import Observation

struct SchoolCaptureMapSegment: Identifiable {
    let id: UUID
    /// Durable measurements of this segment, in storage order: the next one takes this sequence.
    /// Only their count and the last elapsed time are kept; the map copies nothing else per fix.
    private(set) var measurementCount = 0
    private(set) var lastElapsedMs: Int?
    /// Raw ends of the segment, before any display filter: the dashed bridge between two segments starts from them.
    private(set) var firstPoint: SchoolCapturePoint?
    private(set) var lastPoint: SchoolCapturePoint?
    /// Changes each time the displayed samples do: the map redraws only then.
    private(set) var displayRevision = 0
    private var selector = SchoolCaptureDisplayRoute.Selector()

    var displaySamples: [SchoolCaptureDisplayRoute.Sample] { selector.samples }

    init(id: UUID, measurements: [SchoolCaptureMeasurement]) {
        self.id = id
        appendDurable(measurements)
    }

    /// Constant work per measurement: the filter keeps its state, nothing is replayed from the start.
    mutating func appendDurable(_ added: [SchoolCaptureMeasurement]) {
        for measurement in added {
            let point = SchoolCapturePoint(sequence: measurementCount, elapsedMs: measurement.elapsedMs, capturedAt: measurement.capturedAt,
                latitude: measurement.latitude, longitude: measurement.longitude, accuracyMeters: measurement.accuracyMeters)
            measurementCount += 1
            lastElapsedMs = measurement.elapsedMs
            if firstPoint == nil { firstPoint = point }
            lastPoint = point
            if selector.append(point) != .none { displayRevision += 1 }
        }
    }
}

struct SchoolCaptureLessonTimes {
    let startedAt: String
    let stoppedAt: String
}

/// Signalement d’un trajet précédent de la même leçon, placé sur la position mesurée qu’il désigne.
struct SchoolLivePriorObservation: Identifiable, Equatable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let text: String
    let eventKind: String?
    let eventStatus: String?
    let themeKey: String?
}

/// Trajets déjà enregistrés pour la leçon, avant celui qui tourne (relance après une fermeture, un crash ou
/// un redémarrage). Lus chez l’école : seules des mesures confirmées par elle sont dessinées, et un signalement
/// dont la position n’est pas affichée garde son heure sans lieu inventé.
enum SchoolCapturePriorTrack {
    typealias Track = (segments: [[SchoolCapturePoint]], observations: [SchoolPrivateGeoObservation],
                       pointsByAnchor: [String: SchoolCapturePoint])

    static func make(_ tracks: [Track]) -> (segments: [SchoolCaptureMapSegment], observations: [SchoolLivePriorObservation]) {
        var segments: [SchoolCaptureMapSegment] = []
        var observations: [SchoolLivePriorObservation] = []
        for track in tracks {
            for points in track.segments where !points.isEmpty {
                segments.append(SchoolCaptureMapSegment(id: UUID(), measurements: points.map {
                    SchoolCaptureMeasurement(capturedAt: $0.capturedAt, elapsedMs: $0.elapsedMs, latitude: $0.latitude,
                        longitude: $0.longitude, accuracyMeters: $0.accuracyMeters)
                }))
            }
            for observation in track.observations {
                guard let segmentID = observation.segmentId, let sequence = observation.pointSequence,
                      let point = track.pointsByAnchor["\(segmentID.uuidString.lowercased()):\(sequence)"] else { continue }
                observations.append(.init(id: observation.id, latitude: point.latitude, longitude: point.longitude,
                    text: observation.text, eventKind: observation.eventKind, eventStatus: observation.eventStatus,
                    themeKey: observation.themeKey))
            }
        }
        return (segments, observations)
    }
}

/// Durée de la leçon, distincte de celle du GPS : elle part du départ durable enregistré par l’école et se lit
/// sur l’heure de l’école quand elle est connue. Une relance de l’app ne la remet jamais à zéro.
enum SchoolLessonElapsed {
    static func seconds(lessonStartedAt: Date, now: Date) -> TimeInterval { max(0, now.timeIntervalSince(lessonStartedAt)) }

    static func label(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed))
        return seconds >= 3_600
            ? String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Propriétaire de la séance au niveau de l'application, hors des feuilles SwiftUI.
/// La géométrie visible ne contient que des mesures dont l'écriture est confirmée.
@MainActor @Observable
final class SchoolCaptureSessionController {
    enum State { case idle, preparing, recording, paused, stopping, saved, failed }
    /// Passage bref entre deux états stables : mise en pause, reprise, nouveau segment après une perte de signal.
    enum Transition: Equatable { case pausing, resuming, recoveringSignal }
    private(set) var state: State = .idle
    /// Renseigné pendant le seul passage en cours ; un arrêt définitif ou un autre trajet l’efface.
    private(set) var transition: Transition?
    private(set) var captureID: UUID?
    private(set) var lessonID: UUID?
    private(set) var segments: [SchoolCaptureMapSegment] = []
    /// Une position au moins est affichée. Les écrans lisent ceci plutôt que les segments : ils ne sont pas
    /// réévalués à chaque position reçue.
    private(set) var hasDisplayedPosition = false
    private(set) var errorMessage: String?
    private(set) var locationMessage: String?
    private(set) var transferMessage: String?
    private(set) var isTransferring = false
    private(set) var synchronizationNeedsRetry = false
    private(set) var pendingSynchronizationCount = 0
    private(set) var pendingSynchronizationError: String?
    private(set) var finalizedSyncState: SchoolCaptureSession.SyncState?
    private(set) var liveObservations: SchoolLiveObservationRecorder?
    /// Leçon de ce trajet que l’école a confirmée terminée : le trajet n’a plus rien à proposer que sa fermeture.
    private(set) var completedLessonID: UUID?
    /// Tracé des trajets précédents de cette leçon, dessiné avant celui-ci. Jamais utilisé pour ancrer un signalement.
    private(set) var priorSegments: [SchoolCaptureMapSegment] = []
    private(set) var priorObservations: [SchoolLivePriorObservation] = []
    /// Départ durable de la leçon de ce trajet (`actualStart`), pas celui du GPS.
    private(set) var lessonStartedAt: Date?

    @ObservationIgnored private var permittedScope: SchoolCommandScope?
    /// Époque plus récente de la même adhésion, adoptée à la fermeture du trajet qui garde la sienne.
    @ObservationIgnored private var deferredScope: SchoolCommandScope?
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var scopeGeneration = UUID()
    @ObservationIgnored private var beginning: ContinuousClock.Instant?
    @ObservationIgnored private var endedAt: ContinuousClock.Instant?
    @ObservationIgnored private var sharedJournal: SQLCipherSchoolCaptureStore?
    @ObservationIgnored private var openingJournal: Task<SQLCipherSchoolCaptureStore, Error>?
    @ObservationIgnored private var backgroundTransfers: [UUID: Context] = [:]
    @ObservationIgnored private var recoveryTransfers: [UUID: RecoveryTransfer] = [:]
    @ObservationIgnored private var synchronizationFailures: [UUID: String] = [:]
    @ObservationIgnored private var synchronizationClient: SchoolCaptureClient?
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    @ObservationIgnored private var networkAvailable: Bool?
    @ObservationIgnored private var checkingPendingSynchronizations = false
    /// Départs de leçon lus par les écrans (fiche, Aujourd’hui) : un trajet repris après relance retrouve ainsi
    /// l’heure réelle de début de sa leçon.
    @ObservationIgnored private var knownLessonStarts: [UUID: Date] = [:]

    private struct RecoveryTransfer {
        let id: UUID
        let coordinator: SchoolCaptureTransferCoordinator
        let task: Task<Void, Never>
    }

    @MainActor private final class Context {
        let scope: SchoolCommandScope
        let source: any SchoolCaptureLocationProviding
        let local: SchoolCaptureLocalCoordinator
        let transfer: SchoolCaptureTransferCoordinator
        let session: SchoolCaptureStoredSession
        let authorization: SchoolCaptureAuthorization
        let lease: SchoolCaptureLease
        let clock: SchoolCaptureClockReference
        let policy: SchoolCaptureLocationPolicy
        var handle: SchoolCaptureSegmentHandle?
        var terminalRequested = false
        var finishingTask: Task<Bool, Never>?
        var synchronizationTask: Task<Void, Never>?
        var presentationTail: Task<Void, Never>?
        var startedAt: String?
        var durableStoppedAt: String?

        init(scope: SchoolCommandScope, source: any SchoolCaptureLocationProviding, local: SchoolCaptureLocalCoordinator,
             transfer: SchoolCaptureTransferCoordinator, session: SchoolCaptureStoredSession,
             authorization: SchoolCaptureAuthorization, lease: SchoolCaptureLease,
             clock: SchoolCaptureClockReference, policy: SchoolCaptureLocationPolicy) {
            self.scope = scope; self.source = source; self.local = local; self.transfer = transfer
            self.session = session; self.authorization = authorization; self.lease = lease
            self.clock = clock; self.policy = policy
        }

        func stopBoundary() -> String {
            if let boundary = source.stop() { return boundary.stoppedAt }
            let elapsed = SchoolCaptureLocationTime.seconds(clock.receivedAt.duration(to: .now))
            return SchoolCaptureLocationTime.timestamp(clock.serverTime.addingTimeInterval(max(0, elapsed)))
        }
    }

    init(store: SQLCipherSchoolCaptureStore? = nil) { sharedJournal = store }

    var pointCount: Int { segments.reduce(0) { $0 + $1.measurementCount } }
    var displayedPointCount: Int { segments.reduce(0) { $0 + $1.displaySamples.count } }
    /// État que l’écran présente. Pendant un passage bref, c’est l’état stable que l’on quitte, jusqu’au
    /// résultat durable : ni « sauvegarde » ni « préparation » ne remplacent les commandes ou la carte.
    var presentedState: State {
        switch (transition, state) {
        case (.pausing?, .stopping), (.recoveringSignal?, .stopping), (.recoveringSignal?, .preparing): return .recording
        case (.resuming?, .preparing): return .paused
        default: return state
        }
    }
    /// Une perte de signal récupérée ne se lit pas comme un nouveau départ.
    var isCollecting: Bool { presentedState == .recording }
    var canPause: Bool { state == .recording }
    var canResume: Bool { state == .paused && context?.terminalRequested == false && context?.lease.permitsCollection() == true }
    var canStop: Bool { state == .recording || state == .paused || state == .preparing }
    /// Disponibilité montrée à l’écran : un passage bref ne grise aucune commande. L’appui y reste sans
    /// effet, parce que `pause()` et `resume()` relisent l’état réel ; la fin de leçon attend le scellement.
    var presentsPauseEnabled: Bool { presentedState == .recording }
    var presentsResumeEnabled: Bool { canResume || (transition == .resuming && state == .preparing) }
    var presentsStopEnabled: Bool { canStop || presentedState == .recording }
    var canRetrySaving: Bool { state == .failed && context != nil }
    var learnerID: UUID? { context?.session.serverCapture.learnerId }
    var canPrepareCapture: Bool { captureID == nil || state == .saved }
    func prepareLiveObservations(client: SchoolObservationClient) {
        guard let active = context, active.scope == permittedScope, let lessonID,
              client.baseURL.absoluteString == active.scope.apiBaseURL else { return }
        if liveObservations?.scope == active.scope, liveObservations?.lessonID == lessonID {
            liveObservations?.refreshPending(); return
        }
        liveObservations?.stop()
        liveObservations = SchoolLiveObservationRecorder(scope: active.scope, lessonID: lessonID, client: client,
            themeStore: SchoolObservationThemeStores.store(for: active.scope, client: client.themeClient),
            rankingStore: SchoolObservationRankingStores.store(for: active.scope, client: client.rankingClient),
            signalOrders: SchoolLessonSignalOrderStores.make(active.scope),
            permitsAnchor: { [weak self] anchor in
                guard let self else { return false }
                return self.state == .recording && self.captureID == anchor.captureID
                    && self.context?.handle?.segmentID == anchor.segmentID
                    && self.context?.scope == self.permittedScope
                    && self.context?.lease.permitsCollection() == true
            }, prepareAnchor: { [weak self] anchor in
                guard let self, let active = self.context, active.scope == self.permittedScope,
                      active.session.id == anchor.captureID else { throw SchoolCaptureStorageFailure.closed }
                try await active.local.store.flushForObservation(captureID: anchor.captureID, segmentID: anchor.segmentID,
                    sequence: anchor.pointSequence, scope: active.scope)
                // A stop may already be sending these chunks. Await that attempt first.
                await active.synchronizationTask?.value
                _ = try await active.transfer.transferAvailableData(captureID: anchor.captureID)
            })
    }

    /// Freeze the last durable point available at the opening gesture. Pause, stale
    /// fixes and absent fixes produce a temporal observation, never an old position.
    /// Stopped at a light, the displayed point is held: each later fix inside its uncertainty
    /// confirms it. It stays an anchor while the very last fix confirmed it, and its freshness
    /// is that of this confirmation. The anchor remains the real measurement, at its sequence.
    func observationAnchor(at instant: Date) -> SchoolLiveObservationAnchor? {
        guard state == .recording, let active = context, active.scope == permittedScope,
              active.lease.permitsCollection(), let handle = active.handle,
              let segment = segments.first(where: { $0.id == handle.segmentID }),
              let sample = segment.displaySamples.last, let lastMeasured = segment.lastElapsedMs,
              let measured = SchoolLesson.date(sample.point.capturedAt) else { return nil }
        let point = sample.point
        let confirmedUntilMs: Int
        if point.sequence == segment.measurementCount - 1 { confirmedUntilMs = point.elapsedMs }
        else if sample.heldUntilMs == lastMeasured, sample.heldUntilMs >= point.elapsedMs { confirmedUntilMs = sample.heldUntilMs }
        else { return nil }
        let confirmedAt = measured.addingTimeInterval(Double(confirmedUntilMs - point.elapsedMs) / 1000)
        guard (0...15).contains(instant.timeIntervalSince(confirmedAt)) else { return nil }
        return .init(captureID: active.session.id, segmentID: segment.id, pointSequence: point.sequence)
    }

    func cancellationWorkspace(client: SchoolPlanningClient) async throws -> SchoolPlanningWorkspace {
        guard let active = context, active.scope == permittedScope,
              let lessonID, client.baseURL.absoluteString == active.scope.apiBaseURL else { throw SchoolPlanningFailure.forbidden }
        let lesson = try await client.lesson(schoolID: active.scope.schoolID, id: lessonID)
        guard active.scope == permittedScope, self.lessonID == lessonID, lesson.status == "PLANNED" else {
            throw SchoolPlanningFailure.conflict
        }
        return SchoolPlanningWorkspace(scope: active.scope, client: client, lesson: lesson)
    }
    /// Durée d’enregistrement GPS de ce trajet seulement.
    var elapsedSeconds: TimeInterval {
        guard let beginning else { return 0 }
        return max(0, SchoolCaptureLocationTime.seconds(beginning.duration(to: endedAt ?? .now)))
    }

    /// Durée réelle de la leçon depuis son départ durable, lue sur l’heure de l’école reçue avec l’autorisation
    /// (horloge monotone ensuite) : une heure fausse de l’appareil ne la fausse pas. `nil` sans départ connu.
    var lessonElapsedSeconds: TimeInterval? {
        guard let lessonStartedAt else { return nil }
        let now: Date
        if let clock = context?.clock {
            now = clock.serverTime.addingTimeInterval(max(0, SchoolCaptureLocationTime.seconds(clock.receivedAt.duration(to: .now))))
        } else { now = Date() }
        return SchoolLessonElapsed.seconds(lessonStartedAt: lessonStartedAt, now: now)
    }

    /// Appelé par les écrans qui lisent une leçon commencée. Corrige l’heure provisoire du trajet en cours.
    func noteLessonStart(lessonID: UUID, startedAt: Date?) {
        guard let startedAt else { return }
        knownLessonStarts[lessonID] = startedAt
        if self.lessonID == lessonID { lessonStartedAt = startedAt }
    }

    /// Avant un nouveau trajet pour la même leçon. L’école n’autorise qu’un trajet ouvert par leçon : l’arrêt
    /// scellé d’un trajet interrompu (fermeture, crash, redémarrage) et ses positions partent d’abord. Rien n’est
    /// supprimé ni réécrit ; au-delà de l’attente, c’est la réponse de l’école au départ qui fait foi.
    func settleInterruptedCaptures(lessonID: UUID, timeout: Duration = .seconds(20)) async {
        guard let client = synchronizationClient, let scope = permittedScope,
              let store = try? await journal(), let sessions = try? await store.sessions(scope: scope) else { return }
        let ids = sessions.filter {
            $0.serverCapture.lessonId == lessonID && $0.stopOperationID != nil && $0.id != context?.session.id
        }.map(\.id)
        guard !ids.isEmpty else { return }
        await resumePendingSynchronizations(client: client, scope: scope)
        let waits = ids.compactMap { recoveryTransfers[$0]?.task ?? backgroundTransfers[$0]?.synchronizationTask }
        guard !waits.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for task in waits { await task.value } }
            group.addTask { _ = try? await Task.sleep(for: timeout) }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Tracé et signalements des trajets précédents de la leçon, lus après le départ sans le retarder.
    private func loadPriorTrack(_ active: Context, request: UUID) async {
        let client = active.transfer.client, schoolID = active.scope.schoolID
        guard let captures = try? await client.lessonCaptures(schoolID: schoolID, lessonID: active.session.serverCapture.lessonId) else { return }
        let earlier = captures
            .filter { $0.id != active.session.id && SchoolTripsWorkspace.isReplayable($0) }
            .sorted { (SchoolLesson.date($0.authorizedAt) ?? .distantPast) < (SchoolLesson.date($1.authorizedAt) ?? .distantPast) }
        guard !earlier.isEmpty else { return }
        var tracks: [SchoolCapturePriorTrack.Track] = []
        for capture in earlier {
            guard generation == request else { return }
            if let track = try? await client.replayTrack(schoolID: schoolID, captureID: capture.id) { tracks.append(track) }
        }
        guard generation == request, context === active else { return }
        let prior = SchoolCapturePriorTrack.make(tracks)
        priorSegments = prior.segments; priorObservations = prior.observations
    }

    /// Une seule récupération par lancement, avant de fournir le coffre aux écrans.
    /// Ouvrir une seconde feuille ne scelle pas la séance qui tourne déjà.
    func journal() async throws -> SQLCipherSchoolCaptureStore {
        if let sharedJournal { return sharedJournal }
        if let openingJournal {
            let store = try await openingJournal.value
            sharedJournal = store
            return store
        }
        let task = Task {
            let store = try await SQLCipherSchoolCaptureStore.openDefault()
            let deviceID = await store.installationID()
            try await store.recoverInterrupted(deviceID: deviceID)
            // Les positions déjà confirmées par l’école quittent l’appareil. Un échec n’empêche pas d’ouvrir le
            // coffre : rien n’est perdu, la purge reprend à la prochaine finalisation ou ouverture.
            _ = try? await store.purgeSettledCaptures()
            return store
        }
        openingJournal = task
        do {
            let store = try await task.value
            sharedJournal = store; openingJournal = nil
            return store
        } catch { openingJournal = nil; throw error }
    }

    func rejectRemoteAccess(scope: SchoolCommandScope, captureID: UUID?) {
        guard permittedScope == scope else { return }
        remoteStop(captureID: captureID, request: generation)
    }

    func learnerRefused(learnerID: UUID, lessonID: UUID?) {
        guard let active = context, active.session.serverCapture.learnerId == learnerID,
              lessonID == nil || active.session.serverCapture.lessonId == lessonID,
              state != .saved else { return }
        let request = generation, boundary = active.stopBoundary()
        active.terminalRequested = true
        active.local.halt(); transition = nil; state = .stopping
        Task { await finish(active, request: request, boundary: boundary, reason: .learnerRefusal) }
    }

    func retrySaving() async {
        guard let active = context, canRetrySaving else { return }
        let request = generation, boundary = active.stopBoundary()
        active.terminalRequested = true; active.local.halt()
        await finish(active, request: request, boundary: boundary, reason: .deviceError)
    }

    /// Appelé par la fiche quand l’école confirme la fin de la leçon de ce trajet.
    func noteLessonCompleted(_ id: UUID) {
        if lessonID == id { completedLessonID = id }
    }

    func closeSaved() {
        guard state == .saved else { return }
        completedLessonID = nil
        liveObservations?.stop(); liveObservations = nil
        context?.source.onEvent = nil
        context = nil; generation = UUID()
        transition = nil; state = .idle; captureID = nil; lessonID = nil; segments = []; hasDisplayedPosition = false
        errorMessage = nil; locationMessage = nil; transferMessage = nil; isTransferring = false; synchronizationNeedsRetry = false
        finalizedSyncState = nil
        beginning = nil; endedAt = nil
        priorSegments = []; priorObservations = []; lessonStartedAt = nil
        adoptDeferredScope()
    }

    func closeLessonFlow(lessonID: UUID) {
        guard self.lessonID == lessonID else { return }
        closeSaved()
    }

    func lessonTimes(lessonID: UUID) -> SchoolCaptureLessonTimes? {
        guard self.lessonID == lessonID, state == .saved, let active = context,
              let startedAt = active.startedAt, let stoppedAt = active.durableStoppedAt else { return nil }
        return .init(startedAt: startedAt, stoppedAt: stoppedAt)
    }

    /// Appelé par la racine sur toute modification réelle des accès, même si une
    /// feuille est présentée. Les mesures de l'ancien contexte disparaissent aussitôt.
    /// Exception : une époque plus récente de la même adhésion active, rôle moniteur conservé
    /// (`retainsInstructorRole`, relu dans `/me`), n’est pas une perte de droit. Le trajet ouvert
    /// garde sa portée jusqu’à sa fermeture, puis la nouvelle est adoptée ; l’école reste juge à chaque envoi.
    func setScope(_ scope: SchoolCommandScope?, retainsInstructorRole: Bool = false) {
        if let scope, retainsInstructorRole, let current = permittedScope, context != nil,
           scope.sharesMembership(with: current), scope.accessEpoch > current.accessEpoch {
            deferredScope = scope
            return
        }
        deferredScope = nil
        guard permittedScope != scope else { return }
        scopeGeneration = UUID()
        if scope == nil { networkMonitor?.cancel(); networkMonitor = nil; networkAvailable = nil }
        for active in backgroundTransfers.values {
            active.synchronizationTask?.cancel()
            active.transfer.invalidate()
        }
        backgroundTransfers.removeAll()
        for transfer in recoveryTransfers.values {
            transfer.task.cancel(); transfer.coordinator.invalidate()
        }
        recoveryTransfers.removeAll(); synchronizationFailures.removeAll()
        synchronizationClient = nil; pendingSynchronizationCount = 0; pendingSynchronizationError = nil
        liveObservations?.stop(); liveObservations = nil
        permittedScope = scope
        completedLessonID = nil
        let old = context
        let boundary = old?.stopBoundary()
        old?.terminalRequested = true
        old?.local.halt()
        old?.source.onEvent = nil
        old?.source.updateScope(nil)
        context = nil
        generation = UUID()
        old?.transfer.invalidate()
        transition = nil; state = .idle; captureID = nil; lessonID = nil; segments = []; hasDisplayedPosition = false
        errorMessage = nil; locationMessage = nil; transferMessage = nil; isTransferring = false; synchronizationNeedsRetry = false; beginning = nil; endedAt = nil
        finalizedSyncState = nil
        priorSegments = []; priorObservations = []; lessonStartedAt = nil; knownLessonStarts = [:]
        if let old, let boundary {
            Task {
                // Scellement sous la portée d'origine seulement, jamais émission sous
                // les nouveaux droits. Une panne reste récupérable depuis le coffre.
                _ = try? await old.local.stop(captureID: old.session.id, stoppedAt: boundary, reason: .deviceError)
            }
        }
    }

    /// Appelé uniquement après la confirmation de départ et AP154 vérifié/persisté.
    /// Une capture récupérée après relance ne passe jamais par cette méthode.
    func adoptAndStart(transfer: SchoolCaptureTransferCoordinator, source: any SchoolCaptureLocationProviding,
                       session: SchoolCaptureStoredSession, lease: SchoolCaptureLease,
                       authorization: SchoolCaptureAuthorization, receivedAt: ContinuousClock.Instant) async throws {
        // Un départ sous la nouvelle époque ferme d’abord le trajet terminé qui gardait l’ancienne.
        if let deferredScope, deferredScope == transfer.scope {
            if state == .saved { closeSaved() } else if context == nil { adoptDeferredScope() }
        }
        guard canPrepareCapture, sharedJournal === transfer.store, permittedScope == transfer.scope, session.scope == transfer.scope,
              session.id == authorization.capture.id, session.state == .ready,
              session.manifest == nil, lease.captureID == session.id, lease.permitsCollection(),
              context == nil || state == .saved else {
            try await sealUnusedAuthorization(transfer: transfer, source: source, session: session,
                authorization: authorization, receivedAt: receivedAt)
            throw SchoolCaptureLocationFailure.invalidContext
        }
        let clock: SchoolCaptureClockReference
        let policy: SchoolCaptureLocationPolicy
        do {
            clock = try SchoolCaptureClockReference(serverTime: authorization.serverTime, receivedAt: receivedAt)
            policy = try SchoolCaptureLocationPolicy()
        } catch {
            try await sealUnusedAuthorization(transfer: transfer, source: source, session: session,
                authorization: authorization, receivedAt: receivedAt)
            throw error
        }
        liveObservations?.stop(); liveObservations = nil
        let request = UUID(); generation = request
        let local = SchoolCaptureLocalCoordinator(store: transfer.store, scope: transfer.scope,
            stopLocalCollector: { _ = source.stop() })
        let ownedTransfer = SchoolCaptureTransferCoordinator(scope: transfer.scope, client: transfer.client, store: transfer.store,
            stopCollection: { [weak self] id in self?.remoteStop(captureID: id, request: request) })
        let active = Context(scope: transfer.scope, source: source, local: local, transfer: ownedTransfer,
            session: session, authorization: authorization, lease: lease, clock: clock, policy: policy)
        context = active
        completedLessonID = nil
        captureID = session.id; lessonID = session.serverCapture.lessonId
        segments = []; hasDisplayedPosition = false; beginning = nil; endedAt = nil; transition = nil; state = .preparing
        errorMessage = nil; locationMessage = nil; transferMessage = nil; isTransferring = false; synchronizationNeedsRetry = false
        finalizedSyncState = nil
        priorSegments = []; priorObservations = []
        // Une leçon pas encore commencée l’est par ce départ, à l’heure de l’autorisation (règle de l’école).
        lessonStartedAt = knownLessonStarts[session.serverCapture.lessonId] ?? SchoolLesson.date(authorization.capture.authorizedAt)
        source.updateScope(transfer.scope)
        source.onEvent = { [weak self] event in self?.receive(event, request: request) }
        do {
            try await ownedTransfer.client.verifyScope(transfer.scope)
            guard generation == request, permittedScope == active.scope, state == .preparing,
                  !active.terminalRequested else { throw SchoolCaptureStorageFailure.closed }
            try await openSegment(active, request: request, reason: .start)
            // Seule une leçon commencée avant ce trajet peut en avoir d’autres : rien n’est lu sinon.
            if let lessonStart = lessonStartedAt, let authorized = SchoolLesson.date(authorization.capture.authorizedAt),
               lessonStart < authorized.addingTimeInterval(-1) {
                Task { await loadPriorTrack(active, request: request) }
            }
        } catch {
            // Un arrêt décidé pendant l'attente reste l'état courant. La réponse
            // tardive du départ ne le remplace pas par une erreur de démarrage.
            guard generation == request, state == .preparing, !active.terminalRequested else { throw error }
            let boundary = active.stopBoundary()
            active.terminalRequested = true
            active.local.halt()
            let sealed = (try? await active.local.stop(captureID: session.id, stoppedAt: boundary, reason: .deviceError)) != nil
            if generation == request, state == .preparing {
                if sealed {
                    // Aucune position n’a jamais été collectée et l’arrêt est durable : ne pas laisser un
                    // trajet « en échec » qui interdirait toute nouvelle préparation et la fin de la leçon.
                    // L’arrêt scellé part avec les synchronisations en attente.
                    discardUnstartedContext(active)
                    Task { await retryPendingSynchronizations() }
                } else {
                    endedAt = .now; state = .failed; errorMessage = message(error)
                }
            }
            throw error
        }
    }

    /// Départ qui n’a jamais ouvert de segment et dont l’arrêt est scellé : retour à l’état neutre.
    private func discardUnstartedContext(_ active: Context) {
        active.source.onEvent = nil
        context = nil; generation = UUID()
        transition = nil; state = .idle; captureID = nil; lessonID = nil; segments = []; hasDisplayedPosition = false
        errorMessage = nil; locationMessage = nil; transferMessage = nil; isTransferring = false
        synchronizationNeedsRetry = false; finalizedSyncState = nil
        beginning = nil; endedAt = nil
        priorSegments = []; priorObservations = []; lessonStartedAt = nil
        adoptDeferredScope()
    }

    /// Le trajet qui gardait l’ancienne époque est fermé : la nouvelle portée s’applique, puis les trajets
    /// scellés de l’adhésion repartent sous elle après une relecture de `/me`.
    private func adoptDeferredScope() {
        guard let next = deferredScope, context == nil else { return }
        let client = synchronizationClient
        setScope(next)
        guard let client, permittedScope == next else { return }
        Task { await resumePendingSynchronizations(client: client, scope: next) }
    }

    func pause() async {
        guard let active = context, state == .recording, let handle = active.handle else { return }
        let request = generation, boundary = active.stopBoundary()
        state = .stopping; transition = .pausing
        defer { endTransition(.pausing, request: request) }
        do {
            try await active.local.pause(handle: handle, endedAt: boundary, reason: .pause)
            guard generation == request, !active.terminalRequested else { return }
            active.handle = nil; state = .paused
        } catch {
            guard generation == request, !active.terminalRequested else { return }
            state = .failed; errorMessage = message(error)
        }
    }

    func resume() async {
        guard let active = context, canResume else { return }
        let request = generation
        state = .preparing; transition = .resuming; errorMessage = nil
        defer { endTransition(.resuming, request: request) }
        do {
            // Hors réseau ou école injoignable : le bail local encore valable suffit à rouvrir un segment, comme
            // après une perte de signal. Un trajet clos par l’école pendant la pause se découvre alors au premier
            // envoi (elle refuse les lots au-delà de sa borne). Un refus (401, 403, 404) reste un refus.
            let current: SchoolCaptureStoredSession?
            do { current = try await active.transfer.refresh(captureID: active.session.id) }
            catch SchoolCaptureFailure.unavailable where active.lease.permitsCollection() { current = nil }
            guard generation == request, state == .preparing, !active.terminalRequested else { return }
            if let current, current.serverCapture.captureState != .authorized {
                // L’école a clos le trajet pendant la pause : sans cette branche l’état restait
                // « Préparation du GPS » sans aucune commande. On scelle localement, GPS arrêté.
                let boundary = active.stopBoundary()
                active.terminalRequested = true; active.local.halt()
                errorMessage = "L’école a arrêté ce trajet. Les positions déjà enregistrées sont conservées."
                await finish(active, request: request, boundary: boundary, reason: .deviceError)
                return
            }
            try await openSegment(active, request: request, reason: .resume)
        } catch {
            guard generation == request, state == .preparing, !active.terminalRequested else { return }
            let boundary = active.stopBoundary()
            active.local.halt(); errorMessage = message(error)
            if active.handle != nil {
                await finish(active, request: request, boundary: boundary, reason: .deviceError)
            } else { state = .paused }
        }
    }

    func stop(reason: SchoolCaptureLocalStopReason = .userStop) async {
        guard let active = context, canStop else { return }
        let request = generation, boundary = active.stopBoundary()
        active.terminalRequested = true
        active.local.halt()
        await finish(active, request: request, boundary: boundary, reason: reason)
    }

    /// La fin de leçon attend seulement le scellement durable local. Le transfert
    /// continue au niveau de l'app, même si le trajet ou la feuille sont fermés.
    @discardableResult
    func stopAndSynchronize() async -> Bool {
        guard let active = context, active.scope == permittedScope else { return captureID == nil }
        let request = generation
        if state != .saved {
            let boundary = active.stopBoundary()
            active.terminalRequested = true
            active.local.halt()
            guard await finish(active, request: request, boundary: boundary, reason: .lessonEnded) else { return false }
        }
        guard generation == request, state == .saved else { return false }
        scheduleSynchronization(active)
        return true
    }

    func finishForLesson(lessonID: UUID) async -> Bool {
        guard self.lessonID == lessonID else { return true }
        return await stopAndSynchronize()
    }

    func retrySynchronization() async {
        guard let active = context, state == .saved, active.scope == permittedScope else { return }
        scheduleSynchronization(active)
        await active.synchronizationTask?.value
    }

    /// Appelée à l'ouverture du compte et au retour au premier plan. Le journal
    /// récupéré ne rouvre jamais un collecteur ; seules ses captures scellées partent.
    func resumePendingSynchronizations(client: SchoolCaptureClient, scope: SchoolCommandScope) async {
        guard permittedScope == scope, client.baseURL.absoluteString == scope.apiBaseURL else { return }
        let access = scopeGeneration
        synchronizationClient = client
        installNetworkMonitor()
        guard !checkingPendingSynchronizations else { return }
        checkingPendingSynchronizations = true
        defer { checkingPendingSynchronizations = false }
        do {
            let store = try await journal()
            // Trajets scellés sous une époque antérieure de la même adhésion : adoptés après une relecture de
            // `/me` (adhésion active, cette époque, rôle moniteur), sinon laissés tels quels jusqu’au prochain essai.
            if try await store.capturesAwaitingEpochAdoption(scope: scope) > 0,
               (try? await client.confirmInstructorScope(scope)) != nil,
               permittedScope == scope, scopeGeneration == access {
                _ = try? await store.adoptEpoch(scope)
            }
            guard permittedScope == scope, scopeGeneration == access else { return }
            let sessions = try await store.sessions(scope: scope)
            let finalizations = try await store.acknowledgedFinalizations(scope: scope)
            guard permittedScope == scope, scopeGeneration == access else { return }
            let pending = sessions.filter { $0.manifest != nil && $0.stopOperationID != nil && finalizations[$0.id] == nil }
            let pendingIDs = Set(pending.map(\.id))
            synchronizationFailures = synchronizationFailures.filter { pendingIDs.contains($0.key) }
            pendingSynchronizationError = synchronizationFailures.values.first
            pendingSynchronizationCount = pending.count
            for session in pending {
                guard permittedScope == scope, scopeGeneration == access else { return }
                guard backgroundTransfers[session.id] == nil, recoveryTransfers[session.id] == nil else { continue }
                if let active = context, active.session.id == session.id, state == .saved {
                    scheduleSynchronization(active)
                    continue
                }
                let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store, stopCollection: { _ in })
                let transferID = UUID()
                let task = Task { [self] in
                    defer {
                        if recoveryTransfers[session.id]?.id == transferID { recoveryTransfers.removeValue(forKey: session.id) }
                    }
                    do {
                        _ = try await transfer.synchronizeStoppedCapture(captureID: session.id)
                        guard permittedScope == scope, scopeGeneration == access else { return }
                        synchronizationFinished(session.id)
                    } catch {
                        guard permittedScope == scope, scopeGeneration == access else { return }
                        synchronizationFailed(session.id, error: error)
                    }
                }
                recoveryTransfers[session.id] = RecoveryTransfer(id: transferID, coordinator: transfer, task: task)
            }
        } catch {
            guard permittedScope == scope, scopeGeneration == access else { return }
            pendingSynchronizationError = message(error)
        }
    }

    func retryPendingSynchronizations() async {
        guard let client = synchronizationClient, let scope = permittedScope else { return }
        await resumePendingSynchronizations(client: client, scope: scope)
    }

    private func installNetworkMonitor() {
        guard networkMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let becameAvailable = available && self.networkAvailable != true
                self.networkAvailable = available
                guard becameAvailable else { return }
                // Un signalement resté en file faute de réseau repart de lui-même, sans attendre le trajet.
                if let recorder = self.liveObservations { Task { await recorder.retryAfterReconnection() } }
                await self.retryPendingSynchronizations()
            }
        }
        networkMonitor = monitor
        monitor.start(queue: DispatchQueue(label: "ch.drivy.capture-connectivity"))
    }

    private func synchronizationFinished(_ id: UUID) {
        synchronizationFailures.removeValue(forKey: id)
        pendingSynchronizationCount = max(0, pendingSynchronizationCount - 1)
        pendingSynchronizationError = synchronizationFailures.values.first
    }

    private func synchronizationFailed(_ id: UUID, error: Error) {
        synchronizationFailures[id] = "Le trajet reste sur cet appareil. \(message(error))"
        pendingSynchronizationCount = max(pendingSynchronizationCount, synchronizationFailures.count)
        pendingSynchronizationError = synchronizationFailures.values.first
    }

    private func scheduleSynchronization(_ active: Context) {
        guard active.scope == permittedScope, active.synchronizationTask == nil else { return }
        guard recoveryTransfers[active.session.id] == nil else { return }
        if context === active, finalizedSyncState != nil { return }
        let id = active.session.id
        let access = scopeGeneration
        backgroundTransfers[id] = active
        if context === active {
            isTransferring = true; synchronizationNeedsRetry = false; transferMessage = nil
        }
        active.synchronizationTask = Task { [self] in
            defer {
                active.synchronizationTask = nil
                if backgroundTransfers[id] === active { backgroundTransfers.removeValue(forKey: id) }
                if context === active { isTransferring = false }
            }
            do {
                let result = try await active.transfer.synchronizeStoppedCapture(captureID: id)
                guard permittedScope == active.scope, scopeGeneration == access else { return }
                synchronizationFinished(id)
                guard context === active else { return }
                finalizedSyncState = result.syncState
                transferMessage = result.syncState == .synced ? "Trajet synchronisé." : "Le trajet reçu par l’école est partiel."
            } catch {
                guard permittedScope == active.scope, scopeGeneration == access else { return }
                synchronizationFailed(id, error: error)
                guard context === active else { return }
                synchronizationNeedsRetry = true
                transferMessage = "Le trajet est conservé sur cet appareil. \(message(error))"
            }
        }
    }

    func transfer() async {
        guard let active = context, !isTransferring else { return }
        let request = generation
        isTransferring = true; transferMessage = nil
        defer { if generation == request { isTransferring = false } }
        do {
            let count = try await active.transfer.transferAvailableData(captureID: active.session.id)
            let finalized = try await active.transfer.store.acknowledgedFinalizations(scope: active.scope)
            guard generation == request else { return }
            finalizedSyncState = finalized[active.session.id]?.syncState
            transferMessage = count == 0 ? "Aucun lot en attente." : "Les données envoyées ont été confirmées par l’école."
        } catch {
            guard generation == request else { return }
            transferMessage = message(error)
        }
    }

    func finalize(allowPartial: Bool) async {
        guard let active = context, state == .saved, !isTransferring, finalizedSyncState == nil else { return }
        let request = generation
        isTransferring = true; transferMessage = nil
        defer { if generation == request { isTransferring = false } }
        do {
            let result = try await active.transfer.finalize(captureID: active.session.id, allowPartial: allowPartial)
            guard generation == request else { return }
            finalizedSyncState = result.syncState
            transferMessage = result.syncState == .synced ? "Le trajet privé est synchronisé." : "Le trajet privé est conservé comme partiel."
        } catch {
            guard generation == request else { return }
            transferMessage = message(error)
        }
    }

    /// Une autorisation acquittée mais non adoptée ne doit pas bloquer le coffre.
    /// La source est fermée avant l'attente et l'arrêt reste dans sa portée d'origine.
    private func sealUnusedAuthorization(transfer: SchoolCaptureTransferCoordinator,
        source: any SchoolCaptureLocationProviding, session: SchoolCaptureStoredSession,
        authorization: SchoolCaptureAuthorization, receivedAt: ContinuousClock.Instant) async throws {
        let sourceBoundary = source.stop()?.stoppedAt
        source.onEvent = nil
        source.updateScope(nil)
        guard let authorized = SchoolLesson.date(session.serverCapture.authorizedAt),
              let expiry = SchoolLesson.date(session.serverCapture.expiresAt) else {
            throw SchoolCaptureStorageFailure.invalidContext
        }
        let reference = SchoolLesson.date(authorization.serverTime) ?? authorized
        let elapsed = max(0, SchoolCaptureLocationTime.seconds(receivedAt.duration(to: .now)))
        let boundary = sourceBoundary.flatMap(SchoolLesson.date) ?? reference.addingTimeInterval(elapsed)
        _ = try await transfer.store.stopAndSeal(captureID: session.id, scope: session.scope,
            stoppedAt: SchoolCaptureLocationTime.timestamp(min(expiry, max(authorized, boundary))), reason: .deviceError)
    }

    private func openSegment(_ active: Context, request: UUID, reason: SchoolCaptureChunkBody.StartReason) async throws {
        guard !active.terminalRequested else { throw SchoolCaptureStorageFailure.closed }
        let prepared = try active.source.prepareSegment(authorization: active.authorization, lease: active.lease,
            scope: active.scope, clockReference: active.clock, policy: active.policy)
        let handle = try await active.local.begin(captureID: active.session.id, startedAt: prepared.startedAt, reason: reason)
        guard generation == request, permittedScope == active.scope, state == .preparing,
              !active.terminalRequested else { throw SchoolCaptureStorageFailure.closed }
        active.handle = handle
        try active.source.start(segment: prepared, handle: handle)
        if active.startedAt == nil { active.startedAt = prepared.startedAt }
        if beginning == nil { beginning = .now }
        segments.append(SchoolCaptureMapSegment(id: handle.segmentID, measurements: []))
        state = .recording
    }

    private func receive(_ event: SchoolCaptureLocationEvent, request: UUID) {
        guard generation == request, let active = context else { return }
        switch event {
        case .diagnosticChanged: break
        case .signalChanged(let signal): locationMessage = signal.message
        case .measurements(let handle, let values):
            guard state == .recording, active.handle == handle else { return }
            do {
                let saved = try active.local.enqueue(values, handle: handle)
                let previousPresentation = active.presentationTail
                active.presentationTail = Task {
                    // Completion callbacks can resume in a different order from SQL commits.
                    // Publish in the same order so array indices remain durable sequences.
                    await previousPresentation?.value
                    do {
                        _ = try await saved.value
                        guard generation == request, let index = segments.firstIndex(where: { $0.id == handle.segmentID }) else { return }
                        segments[index].appendDurable(values)
                        if !hasDisplayedPosition, !segments[index].displaySamples.isEmpty { hasDisplayedPosition = true }
                    } catch { failCollector(active, request: request, error: error) }
                }
            } catch { failCollector(active, request: request, error: error) }
        case .interrupted(let reason, let stop):
            guard state == .recording || state == .paused || state == .preparing else { return }
            // Un saut réel de l’horloge (contrôle `coherentClock` de la source) se récupère comme une perte de
            // signal : le nouveau segment reprend sa référence sur l’horloge monotone, les positions gardent leur heure.
            if reason == .signalLost || reason == .clockChanged {
                recoverSignal(active, request: request, stop: stop, reason: reason)
                return
            }
            active.terminalRequested = true; active.local.halt()
            transition = nil; state = .stopping
            locationMessage = nil
            errorMessage = reason.message
            Task { await finish(active, request: request, boundary: stop.stoppedAt, reason: reason.stopReason) }
        }
    }

    /// Une vraie lacune sépare les segments. La même autorisation encore valide
    /// permet la reprise locale, y compris hors réseau ; ce n'est pas un nouveau départ.
    private func recoverSignal(_ active: Context, request: UUID, stop: SchoolCaptureLocationStop,
                               reason: SchoolCaptureLocationInterruption) {
        guard let handle = active.handle, !active.terminalRequested else { return }
        state = .stopping; transition = .recoveringSignal
        locationMessage = reason.message
        Task {
            defer { endTransition(.recoveringSignal, request: request) }
            do {
                try await active.local.pause(handle: handle, endedAt: stop.stoppedAt, reason: reason.segmentEndReason)
                guard generation == request, permittedScope == active.scope, !active.terminalRequested else { return }
                active.handle = nil; state = .preparing
                try await openSegment(active, request: request, reason: .resume)
            } catch {
                guard generation == request, !active.terminalRequested else { return }
                errorMessage = message(error)
                await finish(active, request: request, boundary: active.stopBoundary(), reason: .deviceError)
            }
        }
    }

    /// Seul le passage qui l’a ouvert, dans le même trajet, le referme.
    private func endTransition(_ value: Transition, request: UUID) {
        if generation == request, transition == value { transition = nil }
    }

    private func remoteStop(captureID id: UUID?, request: UUID) {
        guard generation == request, let active = context, id == nil || id == active.session.id,
              state != .saved, !active.terminalRequested else { return }
        let boundary = active.stopBoundary()
        active.terminalRequested = true; active.local.halt(); transition = nil; state = .stopping
        Task { await finish(active, request: request, boundary: boundary, reason: .deviceError) }
    }

    private func failCollector(_ active: Context, request: UUID, error: Error) {
        guard generation == request, state != .stopping, state != .saved, state != .failed else { return }
        let boundary = active.stopBoundary()
        active.terminalRequested = true; active.local.halt(); transition = nil; state = .stopping; errorMessage = message(error)
        Task { await finish(active, request: request, boundary: boundary, reason: .deviceError) }
    }

    @discardableResult
    private func finish(_ active: Context, request: UUID, boundary: String, reason: SchoolCaptureLocalStopReason) async -> Bool {
        if let task = active.finishingTask { return await task.value }
        let task = Task { await finishOnce(active, request: request, boundary: boundary, reason: reason) }
        active.finishingTask = task
        let saved = await task.value
        if !saved { active.finishingTask = nil }
        return saved
    }

    private func finishOnce(_ active: Context, request: UUID, boundary: String, reason: SchoolCaptureLocalStopReason) async -> Bool {
        active.terminalRequested = true
        if generation == request {
            // Un arrêt définitif remplace tout passage bref : l’écran montre la sauvegarde.
            transition = nil; state = .stopping
            if endedAt == nil { endedAt = min(.now, active.lease.collectionDeadline) }
        }
        do {
            let command = try await active.local.stop(captureID: active.session.id, stoppedAt: boundary, reason: reason)
            let saved = try JSONDecoder().decode(SchoolStopCaptureBody.self, from: command.body)
            guard generation == request else { return false }
            active.durableStoppedAt = saved.stoppedAt
            active.handle = nil; state = .saved
            locationMessage = nil
            scheduleSynchronization(active)
            return true
        } catch {
            guard generation == request else { return false }
            state = .failed; errorMessage = "Le GPS est arrêté. \(message(error))"
            return false
        }
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "L’opération n’a pas pu être confirmée. Les données conservées restent dans le journal."
    }
}

#if DEBUG && targetEnvironment(simulator)
extension SchoolCaptureSessionController {
    /// Présentation synthétique seulement : aucune source Core Location, aucun
    /// coffre ni autorisation réelle. Ce chemin n'existe pas dans l'IPA Release.
    static func visualReviewRecording(lessonID: UUID, recorder: SchoolLiveObservationRecorder? = nil,
                                     waitingForPosition: Bool = false) -> SchoolCaptureSessionController {
        let controller = SchoolCaptureSessionController()
        controller.state = .recording
        controller.captureID = UUID(uuidString: "00000000-0000-0000-0000-000000009091")!
        controller.lessonID = lessonID
        controller.beginning = ContinuousClock.now.advanced(by: .seconds(-214))
        controller.liveObservations = recorder
        controller.locationMessage = waitingForPosition ? SchoolCaptureLocationSignal.waitingForPosition.message : nil
        let points: [SchoolCaptureMeasurement] = waitingForPosition ? [] : [
            .init(capturedAt: "2026-09-29T10:00:00.000Z", elapsedMs: 0, latitude: 46.520, longitude: 6.630, accuracyMeters: 8),
            .init(capturedAt: "2026-09-29T10:00:05.000Z", elapsedMs: 5_000, latitude: 46.521, longitude: 6.631, accuracyMeters: 7),
            .init(capturedAt: "2026-09-29T10:00:10.000Z", elapsedMs: 10_000, latitude: 46.522, longitude: 6.632, accuracyMeters: 6)
        ]
        controller.segments = [.init(id: UUID(uuidString: "00000000-0000-0000-0000-000000009092")!, measurements: points)]
        controller.hasDisplayedPosition = controller.displayedPointCount > 0
        return controller
    }
}
#endif
