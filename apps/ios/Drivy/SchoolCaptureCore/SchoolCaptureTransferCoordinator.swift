import Foundation

/// Transmission explicite d'intentions déjà durables. Ne crée jamais de collecteur,
/// de segment ou de points, et ne convertit pas une erreur en nouvelle opération.
@MainActor
final class SchoolCaptureTransferCoordinator {
    enum Result {
        case confirmed(SchoolCaptureMutationResult)
        // La vue doit encore demander un départ explicite et graver le segment.
        case authorization(session: SchoolCaptureStoredSession, lease: SchoolCaptureLease,
                           response: SchoolCaptureAuthorization, receivedAt: ContinuousClock.Instant)
    }

    let scope: SchoolCommandScope
    let client: SchoolCaptureClient
    let store: SQLCipherSchoolCaptureStore
    private let stopCollection: @MainActor (UUID?) -> Void
    private var generation = UUID()
    private var invalidated = false
    private(set) var isTransmitting = false

    /// stopCollection ferme synchroniquement la source ET l'admission des callbacks.
    /// nil ferme toute collecte du contexte ; le scellement durable est ensuite assuré
    /// par le coordinateur local. Cette fermeture ne doit pas dépendre du réseau.
    init(scope: SchoolCommandScope, client: SchoolCaptureClient, store: SQLCipherSchoolCaptureStore,
         stopCollection: @escaping @MainActor (UUID?) -> Void) {
        self.scope = scope
        self.client = client
        self.store = store
        self.stopCollection = stopCollection
    }

    func invalidate() {
        stopCollection(nil)
        invalidated = true
        generation = UUID()
        Task { await store.invalidateLeases() }
    }

    func pending() async throws -> [SchoolCaptureQueuedMutation] {
        let request = generation
        do {
            try check(request)
            try await client.verifyScope(scope)
            try check(request)
            let deviceID = await store.installationID()
            let commands = try await store.pending(scope: scope, deviceID: deviceID)
            try check(request)
            return commands
        } catch { closeOnAccessFailure(error); throw error }
    }

    /// Un reçu AP72 est affichable comme preuve de commit. Il ne contient ni preuve
    /// signée ni hash de lot, donc il n'efface pas à lui seul la demande locale.
    func receipt(operationID: UUID) async throws -> SchoolOperationReceipt {
        let request = generation
        do {
            try check(request)
            let queued = try await store.queuedMutation(id: operationID, scope: scope)
            try check(request)
            let receipt = try await client.receipt(for: queued.mutation)
            try check(request)
            return receipt
        } catch {
            // Une absence AP72 peut simplement signifier que la demande n'a pas été
            // commise. Elle n'est pas une preuve de révocation du trajet actif.
            if error as? SchoolCaptureFailure != .notFound { closeOnAccessFailure(error) }
            throw error
        }
    }

    /// Premier envoi ou renvoi demandé par l'utilisateur : même UUID, même corps.
    /// Le départ ne fait pas partie d'une vidange automatique de lots.
    func transmit(operationID: UUID) async throws -> Result {
        guard !isTransmitting else { throw SchoolCaptureStorageFailure.uncertainCommand }
        isTransmitting = true
        defer { isTransmitting = false }
        let request = generation
        do { return try await sendPersisted(operationID: operationID, request: request) }
        catch { closeOnAccessFailure(error); throw error }
    }

    /// Les arrêts sont transmis avant les lots : une grosse file de mesures ne doit
    /// pas retarder l'information d'arrêt. Aucun choix ou départ en attente n'est émis.
    @discardableResult
    func transferAvailableData(captureID: UUID) async throws -> Int {
        guard !isTransmitting else { throw SchoolCaptureStorageFailure.uncertainCommand }
        isTransmitting = true
        defer { isTransmitting = false }
        let request = generation
        do {
            try check(request)
            _ = try await reconcileCapture(captureID, request: request)
            let deviceID = await store.installationID()
            var confirmed = 0
            // Un arrêt peut être scellé pendant l'upload précédent. Il doit passer
            // devant les lots déjà présents dès la prochaine émission.
            while confirmed < 2001 {
                let queue = try await store.pending(scope: scope, deviceID: deviceID)
                try check(request)
                let eligible = queue.filter {
                    $0.mutation.scope == scope && $0.mutation.targetID == captureID
                        && ($0.mutation.kind == .stopCapture || $0.mutation.kind == .uploadChunk)
                }.sorted {
                    if $0.mutation.kind != $1.mutation.kind { return $0.mutation.kind == .stopCapture }
                    if $0.mutation.createdAt != $1.mutation.createdAt { return $0.mutation.createdAt < $1.mutation.createdAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
                guard let queued = eligible.first else { break }
                _ = try await sendPersisted(operationID: queued.id, request: request)
                confirmed += 1
            }
            _ = try await reconcileCapture(captureID, request: request)
            return confirmed
        } catch { closeOnAccessFailure(error); throw error }
    }

    /// allowPartial doit venir d'une confirmation distincte de l'utilisateur.
    /// Une précédente finalisation incertaine conserve ses octets et sa version.
    func finalize(captureID: UUID, allowPartial: Bool) async throws -> SchoolCaptureSession {
        guard !isTransmitting else { throw SchoolCaptureStorageFailure.uncertainCommand }
        isTransmitting = true
        defer { isTransmitting = false }
        let request = generation
        do {
            let current = try await reconcileCapture(captureID, request: request)
            let mutation = try await store.stageFinalization(captureID: captureID, scope: scope,
                expectedVersion: current.serverCapture.version, allowPartial: allowPartial)
            try check(request)
            let result = try await sendPersisted(operationID: mutation.id, request: request)
            guard case .confirmed(.capture(let projection)) = result else { throw SchoolCaptureFailure.invalidResponse }
            return projection
        } catch { closeOnAccessFailure(error); throw error }
    }

    func refresh(captureID: UUID) async throws -> SchoolCaptureStoredSession {
        let request = generation
        do { return try await reconcileCapture(captureID, request: request) }
        catch { closeOnAccessFailure(error); throw error }
    }

    private func sendPersisted(operationID: UUID, request: UUID) async throws -> Result {
        try check(request)
        let queued = try await store.queuedMutation(id: operationID, scope: scope)
        guard queued.state != .acknowledged else { throw SchoolCaptureStorageFailure.uncertainCommand }
        try check(request)
        let keys: SchoolCapturePublicKeys?
        if queued.mutation.kind == .startCapture { keys = try await client.publicKeys() }
        else { keys = nil }
        try check(request)
        let command = try await store.markAttempted(id: operationID, scope: scope)
        try check(request)
        let startedAt = ContinuousClock.now
        let result = try await client.send(command)
        let receivedAt = ContinuousClock.now
        if case .authorization(let authorization) = result, authorization.capture.captureState == .authorized {
            try check(request)
            guard let keys, let body = try? JSONDecoder().decode(SchoolStartCaptureBody.self, from: command.body) else {
                throw SchoolCaptureFailure.invalidResponse
            }
            let lease = try SchoolCaptureAuthorizationVerifier.verify(authorization, keys: keys,
                expectedIssuer: client.baseURL, scope: scope, lessonID: command.targetID,
                deviceID: body.deviceId, assessmentID: body.deviceAssessmentId, requestStartedAt: startedAt)
            let installed = try await store.acceptAuthorization(operationID: command.id, authorization: authorization,
                lease: lease, scope: scope, deviceID: body.deviceId)
            try check(request)
            return .authorization(session: installed, lease: lease, response: authorization, receivedAt: receivedAt)
        }
        if case .authorization(let authorization) = result { stopCollection(authorization.capture.id) }
        if case .capture(let projection) = result, projection.captureState != .authorized { stopCollection(projection.id) }
        // Le résultat d'une commande déjà envoyée reste lié à sa portée originale.
        // Même si la vue a disparu, son accusé doit être durable avant de refuser le
        // retour UI ; aucune donnée n'est réaffectée à un autre compte/epoch.
        try await store.acknowledge(id: command.id, scope: scope, result: result)
        try check(request)
        return .confirmed(result)
    }

    private func reconcileCapture(_ id: UUID, request: UUID) async throws -> SchoolCaptureStoredSession {
        try check(request)
        let projection = try await client.capture(schoolID: scope.schoolID, captureID: id, scope: scope)
        try check(request)
        if projection.captureState != .authorized || projection.publicationState != .privateCapture {
            stopCollection(id)
        }
        let current = try await store.reconcileProjection(projection, scope: scope)
        try check(request)
        return current
    }

    private func check(_ request: UUID) throws {
        guard !invalidated, generation == request else { throw SchoolCaptureStorageFailure.changedScope }
        try Task.checkCancellation()
    }

    private func closeOnAccessFailure(_ error: Error) {
        if let failure = error as? SchoolCaptureFailure,
           failure == .unauthorized || failure == .forbidden || failure == .notFound || failure == .expired { invalidate() }
        else if error as? SchoolCaptureStorageFailure == .changedScope { invalidate() }
    }
}
