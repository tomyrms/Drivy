import Foundation
import Network
import Observation

struct SchoolCaptureMapSegment: Identifiable {
    let id: UUID
    var measurements: [SchoolCaptureMeasurement]
}

struct SchoolCaptureLessonTimes {
    let startedAt: String
    let stoppedAt: String
}

/// Propriétaire de la séance au niveau de l'application, hors des feuilles SwiftUI.
/// La géométrie visible ne contient que des mesures dont l'écriture est confirmée.
@MainActor @Observable
final class SchoolCaptureSessionController {
    enum State { case idle, preparing, recording, paused, stopping, saved, failed }
    private(set) var state: State = .idle
    private(set) var captureID: UUID?
    private(set) var lessonID: UUID?
    private(set) var segments: [SchoolCaptureMapSegment] = []
    private(set) var errorMessage: String?
    private(set) var locationMessage: String?
    private(set) var transferMessage: String?
    private(set) var isTransferring = false
    private(set) var synchronizationNeedsRetry = false
    private(set) var pendingSynchronizationCount = 0
    private(set) var pendingSynchronizationError: String?
    private(set) var finalizedSyncState: SchoolCaptureSession.SyncState?
    private(set) var liveObservations: SchoolLiveObservationRecorder?

    @ObservationIgnored private var permittedScope: SchoolCommandScope?
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var generation = UUID()
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

    private struct RecoveryTransfer {
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

    var pointCount: Int { segments.reduce(0) { $0 + $1.measurements.count } }
    var isCollecting: Bool { state == .recording }
    var canPause: Bool { state == .recording }
    var canResume: Bool { state == .paused && context?.terminalRequested == false && context?.lease.permitsCollection() == true }
    var canStop: Bool { state == .recording || state == .paused || state == .preparing }
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
        liveObservations = SchoolLiveObservationRecorder(scope: active.scope, lessonID: lessonID, client: client)
    }
    var elapsedSeconds: TimeInterval {
        guard let beginning else { return 0 }
        return max(0, SchoolCaptureLocationTime.seconds(beginning.duration(to: endedAt ?? .now)))
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
        active.local.halt(); state = .stopping
        Task { await finish(active, request: request, boundary: boundary, reason: .learnerRefusal) }
    }

    func retrySaving() async {
        guard let active = context, canRetrySaving else { return }
        let request = generation, boundary = active.stopBoundary()
        active.terminalRequested = true; active.local.halt()
        await finish(active, request: request, boundary: boundary, reason: .deviceError)
    }

    func closeSaved() {
        guard state == .saved else { return }
        liveObservations?.stop(); liveObservations = nil
        context?.source.onEvent = nil
        context = nil; generation = UUID()
        state = .idle; captureID = nil; lessonID = nil; segments = []
        errorMessage = nil; locationMessage = nil; transferMessage = nil; isTransferring = false; synchronizationNeedsRetry = false
        finalizedSyncState = nil
        beginning = nil; endedAt = nil
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
    func setScope(_ scope: SchoolCommandScope?) {
        guard permittedScope != scope else { return }
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
        let old = context
        let boundary = old?.stopBoundary()
        old?.terminalRequested = true
        old?.local.halt()
        old?.source.onEvent = nil
        old?.source.updateScope(nil)
        context = nil
        generation = UUID()
        old?.transfer.invalidate()
        state = .idle; captureID = nil; lessonID = nil; segments = []
        errorMessage = nil; locationMessage = nil; transferMessage = nil; isTransferring = false; synchronizationNeedsRetry = false; beginning = nil; endedAt = nil
        finalizedSyncState = nil
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
        captureID = session.id; lessonID = session.serverCapture.lessonId
        segments = []; beginning = nil; endedAt = nil; state = .preparing
        errorMessage = nil; locationMessage = nil; transferMessage = nil; isTransferring = false; synchronizationNeedsRetry = false
        finalizedSyncState = nil
        source.updateScope(transfer.scope)
        source.onEvent = { [weak self] event in self?.receive(event, request: request) }
        do {
            try await ownedTransfer.client.verifyScope(transfer.scope)
            guard generation == request, permittedScope == active.scope, state == .preparing,
                  !active.terminalRequested else { throw SchoolCaptureStorageFailure.closed }
            try await openSegment(active, request: request, reason: .start)
        } catch {
            // Un arrêt décidé pendant l'attente reste l'état courant. La réponse
            // tardive du départ ne le remplace pas par une erreur de démarrage.
            guard generation == request, state == .preparing, !active.terminalRequested else { throw error }
            let boundary = active.stopBoundary()
            active.terminalRequested = true
            active.local.halt()
            _ = try? await active.local.stop(captureID: session.id, stoppedAt: boundary, reason: .deviceError)
            if generation == request, state == .preparing { endedAt = .now; state = .failed; errorMessage = message(error) }
            throw error
        }
    }

    func pause() async {
        guard let active = context, state == .recording, let handle = active.handle else { return }
        let request = generation, boundary = active.stopBoundary()
        state = .stopping
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
        state = .preparing; errorMessage = nil
        do {
            let current = try await active.transfer.refresh(captureID: active.session.id)
            guard generation == request, state == .preparing, !active.terminalRequested,
                  current.serverCapture.captureState == .authorized else { return }
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
        synchronizationClient = client
        installNetworkMonitor()
        guard !checkingPendingSynchronizations else { return }
        checkingPendingSynchronizations = true
        defer { checkingPendingSynchronizations = false }
        do {
            let store = try await journal()
            let sessions = try await store.sessions(scope: scope)
            let finalizations = try await store.acknowledgedFinalizations(scope: scope)
            guard permittedScope == scope else { return }
            let pending = sessions.filter { $0.manifest != nil && $0.stopOperationID != nil && finalizations[$0.id] == nil }
            pendingSynchronizationCount = pending.count
            for session in pending {
                guard permittedScope == scope else { return }
                guard backgroundTransfers[session.id] == nil, recoveryTransfers[session.id] == nil else { continue }
                if let active = context, active.session.id == session.id, state == .saved {
                    scheduleSynchronization(active)
                    continue
                }
                let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store, stopCollection: { _ in })
                let task = Task { [self] in
                    defer { recoveryTransfers.removeValue(forKey: session.id) }
                    do {
                        _ = try await transfer.synchronizeStoppedCapture(captureID: session.id)
                        guard permittedScope == scope else { return }
                        synchronizationFinished(session.id)
                    } catch {
                        guard permittedScope == scope else { return }
                        synchronizationFailed(session.id, error: error)
                    }
                }
                recoveryTransfers[session.id] = RecoveryTransfer(coordinator: transfer, task: task)
            }
        } catch {
            guard permittedScope == scope else { return }
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
                if becameAvailable { await self.retryPendingSynchronizations() }
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
                guard permittedScope == active.scope else { return }
                synchronizationFinished(id)
                guard context === active else { return }
                finalizedSyncState = result.syncState
                transferMessage = result.syncState == .synced ? "Trajet synchronisé." : "Le trajet reçu par l’école est partiel."
            } catch {
                guard permittedScope == active.scope else { return }
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
                Task {
                    do {
                        _ = try await saved.value
                        guard generation == request, let index = segments.firstIndex(where: { $0.id == handle.segmentID }) else { return }
                        segments[index].measurements.append(contentsOf: values)
                        segments[index].measurements.sort { $0.elapsedMs < $1.elapsedMs }
                    } catch { failCollector(active, request: request, error: error) }
                }
            } catch { failCollector(active, request: request, error: error) }
        case .interrupted(let reason, let stop):
            guard state == .recording || state == .paused || state == .preparing else { return }
            if reason == .signalLost {
                recoverSignal(active, request: request, stop: stop)
                return
            }
            active.terminalRequested = true; active.local.halt()
            state = .stopping
            locationMessage = nil
            errorMessage = reason.message
            Task { await finish(active, request: request, boundary: stop.stoppedAt, reason: reason.stopReason) }
        }
    }

    /// Une vraie lacune sépare les segments. La même autorisation encore valide
    /// permet la reprise locale, y compris hors réseau ; ce n'est pas un nouveau départ.
    private func recoverSignal(_ active: Context, request: UUID, stop: SchoolCaptureLocationStop) {
        guard let handle = active.handle, !active.terminalRequested else { return }
        state = .stopping
        locationMessage = SchoolCaptureLocationInterruption.signalLost.message
        Task {
            do {
                try await active.local.pause(handle: handle, endedAt: stop.stoppedAt, reason: .signalLost)
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

    private func remoteStop(captureID id: UUID?, request: UUID) {
        guard generation == request, let active = context, id == nil || id == active.session.id,
              state != .saved, !active.terminalRequested else { return }
        let boundary = active.stopBoundary()
        active.terminalRequested = true; active.local.halt(); state = .stopping
        Task { await finish(active, request: request, boundary: boundary, reason: .deviceError) }
    }

    private func failCollector(_ active: Context, request: UUID, error: Error) {
        guard generation == request, state != .stopping, state != .saved, state != .failed else { return }
        let boundary = active.stopBoundary()
        active.terminalRequested = true; active.local.halt(); state = .stopping; errorMessage = message(error)
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
            state = .stopping
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
        return controller
    }
}
#endif
