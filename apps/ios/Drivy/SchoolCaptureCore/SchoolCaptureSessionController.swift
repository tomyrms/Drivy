import Foundation
import Observation

struct SchoolCaptureMapSegment: Identifiable {
    let id: UUID
    var measurements: [SchoolCaptureMeasurement]
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
    private(set) var transferMessage: String?
    private(set) var isTransferring = false
    private(set) var finalizedSyncState: SchoolCaptureSession.SyncState?

    @ObservationIgnored private var permittedScope: SchoolCommandScope?
    @ObservationIgnored private var context: Context?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var beginning: ContinuousClock.Instant?
    @ObservationIgnored private var endedAt: ContinuousClock.Instant?
    @ObservationIgnored private var sharedJournal: SQLCipherSchoolCaptureStore?
    @ObservationIgnored private var openingJournal: Task<SQLCipherSchoolCaptureStore, Error>?
    private var personalCaptureActive = false

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

    var pointCount: Int { segments.reduce(0) { $0 + $1.measurements.count } }
    var isCollecting: Bool { state == .recording }
    var canPause: Bool { state == .recording }
    var canResume: Bool { state == .paused && context?.terminalRequested == false && context?.lease.permitsCollection() == true }
    var canStop: Bool { state == .recording || state == .paused || state == .preparing }
    var canRetrySaving: Bool { state == .failed && context != nil }
    var learnerID: UUID? { context?.session.serverCapture.learnerId }
    var canPrepareCapture: Bool { !personalCaptureActive && (captureID == nil || state == .saved) }
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

    func setPersonalCaptureActive(_ active: Bool) {
        personalCaptureActive = active
        // Les parcours personnels et scolaires ne partagent jamais un collecteur.
        if active, let context, state != .saved {
            remoteStop(captureID: context.session.id, request: generation)
        }
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
        context?.source.onEvent = nil
        context = nil; generation = UUID()
        state = .idle; captureID = nil; lessonID = nil; segments = []
        errorMessage = nil; transferMessage = nil; isTransferring = false
        finalizedSyncState = nil
        beginning = nil; endedAt = nil
    }

    /// Appelé par la racine sur toute modification réelle des accès, même si une
    /// feuille est présentée. Les mesures de l'ancien contexte disparaissent aussitôt.
    func setScope(_ scope: SchoolCommandScope?) {
        guard permittedScope != scope else { return }
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
        errorMessage = nil; transferMessage = nil; isTransferring = false; beginning = nil; endedAt = nil
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
        errorMessage = nil; transferMessage = nil; isTransferring = false
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

    func transfer() async {
        guard let active = context, !isTransferring else { return }
        let request = generation
        isTransferring = true; transferMessage = nil
        defer { if generation == request { isTransferring = false } }
        do {
            let count = try await active.transfer.transferAvailableData(captureID: active.session.id)
            guard generation == request else { return }
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
        if beginning == nil { beginning = .now }
        segments.append(SchoolCaptureMapSegment(id: handle.segmentID, measurements: []))
        state = .recording
    }

    private func receive(_ event: SchoolCaptureLocationEvent, request: UUID) {
        guard generation == request, let active = context else { return }
        switch event {
        case .diagnosticChanged: break
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
            active.terminalRequested = true; active.local.halt()
            state = .stopping
            errorMessage = reason == .expired ? "L’autorisation GPS est arrivée à sa fin. La leçon peut continuer sans GPS." : "Le GPS est arrêté. Les mesures déjà écrites restent conservées."
            Task { await finish(active, request: request, boundary: stop.stoppedAt, reason: reason.stopReason) }
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

    private func finish(_ active: Context, request: UUID, boundary: String, reason: SchoolCaptureLocalStopReason) async {
        active.terminalRequested = true
        if generation == request {
            state = .stopping
            if endedAt == nil { endedAt = min(.now, active.lease.collectionDeadline) }
        }
        do {
            _ = try await active.local.stop(captureID: active.session.id, stoppedAt: boundary, reason: reason)
            guard generation == request else { return }
            active.handle = nil; state = .saved
        } catch {
            guard generation == request else { return }
            state = .failed; errorMessage = "Le GPS est arrêté. \(message(error))"
        }
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "L’opération n’a pas pu être confirmée. Les données conservées restent dans le journal."
    }
}
