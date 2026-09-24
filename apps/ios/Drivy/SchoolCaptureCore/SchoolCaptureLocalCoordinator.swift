import Foundation

/// Barrière locale uniquement : aucune permission OS n'est demandée et aucun upload
/// n'est déclenché. Le futur adaptateur GPS fournit son arrêt synchrone et des mesures
/// déjà normalisées avec le mapping d'horloge de la source qualifiée.
@MainActor
final class SchoolCaptureLocalCoordinator {
    let store: SQLCipherSchoolCaptureStore
    let scope: SchoolCommandScope
    private let stopLocalCollector: @MainActor () -> Void
    private var activeHandle: SchoolCaptureSegmentHandle?
    private var lifecycle = UUID()
    private var beginTask: Task<SchoolCaptureSegmentHandle, Error>?
    private var writeTail: Task<Void, Error>?
    private var stopping = false
    private var queuedMeasurementCount = 0
    private(set) var lastFailure: String?

    init(store: SQLCipherSchoolCaptureStore, scope: SchoolCommandScope,
         stopLocalCollector: @escaping @MainActor () -> Void) {
        self.store = store
        self.scope = scope
        self.stopLocalCollector = stopLocalCollector
    }

    func begin(captureID: UUID, startedAt: String,
               reason: SchoolCaptureChunkBody.StartReason) async throws -> SchoolCaptureSegmentHandle {
        guard activeHandle == nil, beginTask == nil, !stopping else { throw SchoolCaptureStorageFailure.alreadyActive }
        let token = UUID()
        lifecycle = token
        let previous = writeTail
        let task = Task {
            try await previous?.value
            return try await store.beginSegment(captureID: captureID, scope: scope, startedAt: startedAt, reason: reason)
        }
        beginTask = task
        do {
            let handle = try await task.value
            guard lifecycle == token else { throw SchoolCaptureStorageFailure.closed }
            beginTask = nil
            activeHandle = handle
            lastFailure = nil
            return handle
        } catch {
            if lifecycle == token { beginTask = nil }
            throw error
        }
    }

    // La mise en file est synchrone sur MainActor : elle fixe l'ordre des callbacks.
    // Le Task retourné ne réussit qu'après le commit SQLCipher de toutes ses mesures.
    @discardableResult
    func enqueue(_ measurements: [SchoolCaptureMeasurement], handle: SchoolCaptureSegmentHandle) throws -> Task<Int, Error> {
        guard activeHandle == handle, !stopping else { throw SchoolCaptureStorageFailure.closed }
        guard !measurements.isEmpty, measurements.count <= 1000,
              queuedMeasurementCount + measurements.count <= 1000 else {
            closeAdmission()
            lastFailure = "Le journal ne peut plus suivre la collecte. Le collecteur est arrêté."
            throw SchoolCaptureStorageFailure.capacity
        }
        queuedMeasurementCount += measurements.count
        let previous = writeTail
        let task = Task {
            defer { queuedMeasurementCount -= measurements.count }
            do {
                try await previous?.value
                return try await store.append(measurements: measurements, handle: handle, scope: scope)
            } catch {
                if activeHandle == handle {
                    activeHandle = nil
                    lifecycle = UUID()
                    stopLocalCollector()
                }
                lastFailure = "Une mesure n’a pas pu être écrite durablement. Le collecteur est arrêté."
                throw error
            }
        }
        writeTail = Task { _ = try await task.value }
        return task
    }

    func pause(handle: SchoolCaptureSegmentHandle, endedAt: String,
               reason: SchoolCaptureManifest.EndReason) async throws {
        guard activeHandle == handle, !stopping else { throw SchoolCaptureStorageFailure.closed }
        stopping = true
        defer { stopping = false }
        let pendingStart = beginTask
        let pendingWrites = writeTail
        closeAdmission()
        _ = try? await pendingStart?.value
        _ = try? await pendingWrites?.value
        try await store.sealSegment(handle: handle, scope: scope, endedAt: endedAt, reason: reason)
        beginTask = nil
        writeTail = nil
    }

    @discardableResult
    func stop(captureID: UUID, stoppedAt: String,
              reason: SchoolCaptureLocalStopReason) async throws -> SchoolCapturePendingMutation {
        guard !stopping else { closeAdmission(); throw SchoolCaptureStorageFailure.closed }
        stopping = true
        defer { stopping = false }
        let pendingStart = beginTask
        let pendingWrites = writeTail
        // Toujours avant le premier await, y compris lors d'une panne réseau ou disque.
        closeAdmission()
        _ = try? await pendingStart?.value
        _ = try? await pendingWrites?.value
        let command = try await store.stopAndSeal(captureID: captureID, scope: scope, stoppedAt: stoppedAt,
            reason: lastFailure == nil ? reason : .deviceError)
        beginTask = nil
        writeTail = nil
        return command
    }

    func recover(deviceID: UUID) async throws {
        guard !stopping else { closeAdmission(); throw SchoolCaptureStorageFailure.closed }
        stopping = true
        defer { stopping = false }
        let pendingStart = beginTask
        let pendingWrites = writeTail
        closeAdmission()
        _ = try? await pendingStart?.value
        _ = try? await pendingWrites?.value
        await store.invalidateLeases()
        try await store.recoverInterrupted(deviceID: deviceID)
        beginTask = nil
        writeTail = nil
    }

    private func closeAdmission() {
        activeHandle = nil
        lifecycle = UUID()
        stopLocalCollector()
    }
}
