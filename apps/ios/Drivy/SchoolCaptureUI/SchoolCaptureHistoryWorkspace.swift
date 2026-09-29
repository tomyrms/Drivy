import Foundation
import Observation

/// Trips stopped on this device that the school has not confirmed yet (« À envoyer »).
/// It never installs a lease or a source. A trip whose confirmation the school acknowledged is
/// finished: it is neither read again nor listed.
@MainActor @Observable final class SchoolCaptureHistoryWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolCaptureClient
    private(set) var captures: [SchoolCaptureStoredSession] = []
    private(set) var pendingCount: [UUID: Int] = [:]
    private(set) var pendingFinalization: [UUID: Bool] = [:]
    private(set) var confirmedFinalization: [UUID: SchoolCaptureSession] = [:]
    private(set) var isLoading = false
    private(set) var busyCaptureID: UUID?
    private(set) var errorMessage: String?
    private(set) var feedback: String?
    private(set) var accessRevoked = false
    @ObservationIgnored private let owner: SchoolCaptureSessionController
    @ObservationIgnored private var store: SQLCipherSchoolCaptureStore?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false

    init(scope: SchoolCommandScope, client: SchoolCaptureClient, owner: SchoolCaptureSessionController) {
        self.scope = scope; self.client = client; self.owner = owner
    }

    /// Trips stopped on this device whose data or final confirmation has not reached the school yet.
    private(set) var incomplete: Set<UUID> = []

    var isBusy: Bool { isLoading || busyCaptureID != nil }
    var pendingUploads: [SchoolCaptureStoredSession] { captures.filter(maySend) }

    func load() async {
        guard !invalidated, !isBusy else { return }
        let request = generation
        isLoading = true; errorMessage = nil
        defer { if current(request) { isLoading = false } }
        do {
            let journal = try await owner.journal()
            guard current(request) else { return }
            store = journal
            try await reload(journal, request: request)
        } catch { if current(request) { fail(error) } }
    }

    func maySend(_ capture: SchoolCaptureStoredSession) -> Bool {
        !invalidated && !accessRevoked && capture.scope == scope
            && captures.contains(where: { $0.id == capture.id })
            && capture.manifest != nil && capture.stopOperationID != nil
            && (confirmedFinalization[capture.id] == nil || pendingFinalization[capture.id] != nil)
            && capture.serverCapture.publicationState == .privateCapture
    }

    func send(_ capture: SchoolCaptureStoredSession) async { await perform(capture, finalizing: nil) }
    func finalize(_ capture: SchoolCaptureStoredSession, allowPartial: Bool) async {
        await perform(capture, finalizing: allowPartial)
    }

    /// One action for the trip: resend an already queued confirmation as is, otherwise send
    /// the kept data then confirm a complete trip. Missing positions leave the choice of a
    /// partial trip to the instructor.
    func upload(_ capture: SchoolCaptureStoredSession) async {
        if let allowPartial = pendingFinalization[capture.id] {
            await perform(capture, finalizing: allowPartial)
            return
        }
        guard !isBusy, maySend(capture), let store else { return }
        let request = generation
        busyCaptureID = capture.id; errorMessage = nil; feedback = nil
        defer { if current(request) { busyCaptureID = nil } }
        let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store,
            stopCollection: { [weak owner = owner, scope = scope] id in owner?.rejectRemoteAccess(scope: scope, captureID: id) })
        do {
            _ = try await transfer.transferAvailableData(captureID: capture.id)
            guard current(request) else { return }
            _ = try await transfer.finalize(captureID: capture.id, allowPartial: false)
            guard current(request) else { return }
            incomplete.remove(capture.id)
            try await reload(store, request: request)
        } catch {
            guard current(request) else { return }
            if error as? SchoolCaptureFailure == .finalizationRefused("CAPTURE_INCOMPLETE") { incomplete.insert(capture.id) }
            fail(error, captureID: capture.id)
            if !accessRevoked { try? await reload(store, request: request) }
        }
    }

    private func perform(_ capture: SchoolCaptureStoredSession, finalizing: Bool?) async {
        guard !isBusy, maySend(capture), let store else { return }
        let request = generation
        busyCaptureID = capture.id; errorMessage = nil; feedback = nil
        defer { if current(request) { busyCaptureID = nil } }
        let transfer = SchoolCaptureTransferCoordinator(scope: scope, client: client, store: store,
            stopCollection: { [weak owner = owner, scope = scope] id in owner?.rejectRemoteAccess(scope: scope, captureID: id) })
        do {
            if let finalizing {
                let result = try await transfer.finalize(captureID: capture.id, allowPartial: finalizing)
                guard current(request) else { return }
                incomplete.remove(capture.id)
                feedback = result.syncState == .synced ? "Trajet envoyé." : "Trajet gardé en partiel."
            } else {
                let count = try await transfer.transferAvailableData(captureID: capture.id)
                guard current(request) else { return }
                feedback = count == 0 ? "Aucun envoi en attente pour ce trajet."
                    : "L’école a confirmé les données envoyées. Vous pouvez vérifier le trajet complet."
            }
            try await reload(store, request: request)
        } catch {
            guard current(request) else { return }
            if error as? SchoolCaptureFailure == .finalizationRefused("CAPTURE_INCOMPLETE") { incomplete.insert(capture.id) }
            fail(error, captureID: capture.id)
            if !accessRevoked { try? await reload(store, request: request) }
        }
    }

    private func reload(_ store: SQLCipherSchoolCaptureStore, request: UUID) async throws {
        let stored = try await store.sessions(scope: scope)
        let finished = try await store.acknowledgedFinalizations(scope: scope)
        let deviceID = await store.installationID()
        let queued = try await store.pending(scope: scope, deviceID: deviceID)
        guard current(request) else { return }
        let requeued = Set(queued.filter { $0.mutation.kind == .finalizeCapture }.map(\.mutation.targetID))
        let unfinished = stored.filter { ($0.state == .stopped || $0.state == .interrupted)
            && (finished[$0.id] == nil || requeued.contains($0.id)) }
        var sessions: [SchoolCaptureStoredSession] = []
        if !unfinished.isEmpty {
            // One scope check, then every projection at once instead of one request after another.
            try await client.verifyScope(scope)
            guard current(request) else { return }
            let projections = await Self.projections(unfinished.map(\.id), client: client, schoolID: scope.schoolID)
            guard current(request) else { return }
            for capture in unfinished {
                switch projections[capture.id] {
                case .success(let projection)?:
                    let refreshed = try await store.reconcileProjection(projection, scope: scope)
                    guard current(request) else { return }
                    sessions.append(refreshed)
                case .failure(let error)?:
                    // A changed assignment can remove access to this lesson alone.
                    guard let failure = error as? SchoolCaptureFailure, failure == .notFound || failure == .forbidden else { throw error }
                    owner.rejectRemoteAccess(scope: scope, captureID: capture.id)
                case nil:
                    break
                }
            }
        }
        let queue = queued
        captures = sessions.filter { $0.state == .stopped || $0.state == .interrupted }
        confirmedFinalization = finished
        pendingCount = Dictionary(grouping: queue.filter { $0.mutation.scope == scope
            && [.uploadChunk, .stopCapture, .finalizeCapture].contains($0.mutation.kind) }, by: { $0.mutation.targetID })
            .mapValues(\.count)
        pendingFinalization = [:]
        for queued in queue where queued.mutation.scope == scope && queued.mutation.kind == .finalizeCapture {
            if let body = try? JSONDecoder().decode(SchoolFinalizeCaptureBody.self, from: queued.mutation.body) {
                pendingFinalization[queued.mutation.targetID] = body.allowPartial
            }
        }
    }

    private static func projections(_ ids: [UUID], client: SchoolCaptureClient,
                                     schoolID: UUID) async -> [UUID: Result<SchoolCaptureSession, any Error>] {
        await withTaskGroup(of: (UUID, Result<SchoolCaptureSession, any Error>).self) { group in
            for id in ids {
                group.addTask { @MainActor in
                    do { return (id, .success(try await client.capture(schoolID: schoolID, captureID: id))) }
                    catch { return (id, .failure(error)) }
                }
            }
            var results: [UUID: Result<SchoolCaptureSession, any Error>] = [:]
            for await (id, result) in group { results[id] = result }
            return results
        }
    }

    func invalidate() {
        invalidated = true; generation = UUID()
        captures = []; pendingCount = [:]; pendingFinalization = [:]; confirmedFinalization = [:]; errorMessage = nil; feedback = nil
        incomplete = []
        // Admitted commands keep their original identity and persist their receipt.
        // Closing this list must not invalidate the ongoing session's lease.
    }

    private func current(_ request: UUID) -> Bool { !invalidated && request == generation }
    private func fail(_ error: Error, captureID: UUID? = nil) {
        if error as? SchoolCaptureFailure == .notFound, let captureID {
            captures.removeAll { $0.id == captureID }
            pendingCount.removeValue(forKey: captureID)
            pendingFinalization.removeValue(forKey: captureID)
            confirmedFinalization.removeValue(forKey: captureID)
            owner.rejectRemoteAccess(scope: scope, captureID: captureID)
        }
        if let failure = error as? SchoolCaptureFailure,
           failure == .unauthorized || failure == .forbidden {
            accessRevoked = true; captures = []; pendingCount = [:]; pendingFinalization = [:]; confirmedFinalization = [:]
            owner.rejectRemoteAccess(scope: scope, captureID: nil)
        }
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? "L’opération n’a pas pu être confirmée. Le trajet reste conservé sur cet appareil."
    }
}
