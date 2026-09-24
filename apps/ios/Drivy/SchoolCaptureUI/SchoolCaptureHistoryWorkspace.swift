import Foundation
import Observation

/// Recovery UI for stopped school captures. It never installs a lease or a source.
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

    var isBusy: Bool { isLoading || busyCaptureID != nil }

    func load() async {
        guard !invalidated, !isBusy else { return }
        let request = generation
        isLoading = true; errorMessage = nil
        defer { if current(request) { isLoading = false } }
        do {
            try await client.verifyScope(scope)
            guard current(request) else { return }
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
                feedback = result.syncState == .synced ? "Le trajet est synchronisé et reste privé."
                    : "Le trajet est conservé comme partiel. Il reste privé."
            } else {
                let count = try await transfer.transferAvailableData(captureID: capture.id)
                guard current(request) else { return }
                feedback = count == 0 ? "Aucun envoi en attente pour ce trajet."
                    : "L’école a confirmé les données envoyées. Vous pouvez vérifier le trajet complet."
            }
            try await reload(store, request: request)
        } catch {
            guard current(request) else { return }
            fail(error, captureID: capture.id)
            if !accessRevoked { try? await reload(store, request: request) }
        }
    }

    private func reload(_ store: SQLCipherSchoolCaptureStore, request: UUID) async throws {
        let stored = try await store.sessions(scope: scope)
        var sessions: [SchoolCaptureStoredSession] = []
        for capture in stored where capture.state == .stopped || capture.state == .interrupted {
            guard current(request) else { return }
            do {
                let projection = try await client.capture(schoolID: scope.schoolID, captureID: capture.id, scope: scope)
                guard current(request) else { return }
                let refreshed = try await store.reconcileProjection(projection, scope: scope)
                guard current(request) else { return }
                sessions.append(refreshed)
            } catch SchoolCaptureFailure.notFound {
                // A changed assignment can remove access to this lesson alone.
                owner.rejectRemoteAccess(scope: scope, captureID: capture.id)
            } catch SchoolCaptureFailure.forbidden {
                owner.rejectRemoteAccess(scope: scope, captureID: capture.id)
            }
        }
        let deviceID = await store.installationID()
        let queue = try await store.pending(scope: scope, deviceID: deviceID)
        let confirmed = try await store.acknowledgedFinalizations(scope: scope)
        guard current(request) else { return }
        captures = sessions.filter { $0.state == .stopped || $0.state == .interrupted }
        confirmedFinalization = confirmed
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

    func invalidate() {
        invalidated = true; generation = UUID()
        captures = []; pendingCount = [:]; pendingFinalization = [:]; confirmedFinalization = [:]; errorMessage = nil; feedback = nil
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
