import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLiveObservationUndoTests {
    @Test func undoIsDurableScopedToTheLastReceiptAndSurvivesRecreation() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(offline: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment(at: HubFixture.date("2026-09-28T12:11:00Z")))
        let original = try #require(outbox.value), receipt = try #require(model.lastAdded)
        #expect(receipt.id == original.id && model.canUndo(receipt.id))
        #expect(!model.canUndo(UUID()))
        #expect(await model.undoLastAdded(id: receipt.id))
        let withdrawal = try #require(outbox.value)
        #expect(withdrawal.withoutObservationUndo == original && withdrawal.observationUndoOperationID != nil)
        #expect(model.undoState == .pending && !model.canUndo(receipt.id))
        #expect(!model.mapObservations.isEmpty) // A queued withdrawal is not a confirmed removal.
        #expect(!(await model.undoLastAdded(id: receipt.id)))
        model.stop()
        let restored = recorder(outbox, server)
        #expect(restored.lastAdded?.id == receipt.id && restored.undoState == .pending && restored.canRetry)
        restored.stop()
    }

    @Test func failedUndoStorageNeverClaimsWithdrawalAndKeepsTheOriginalRequest() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(offline: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        let original = try #require(outbox.value), receipt = try #require(model.lastAdded)
        outbox.failSave = true
        #expect(!(await model.undoLastAdded(id: receipt.id)))
        #expect(outbox.value == original && model.undoState == .none)
        #expect(model.undoErrorMessage != nil && model.canUndo(receipt.id))
        model.stop()
    }

    @Test func undoDuringCreateFlightCannotBeErasedByTheLateCreateAcknowledgement() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(holdsCreate: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        let original = try #require(outbox.value), receipt = try #require(model.lastAdded)
        try await waitForCreate(server)
        #expect(model.isSending && model.canUndo(receipt.id))
        #expect(await model.undoLastAdded(id: receipt.id))
        let withdrawal = try #require(outbox.value)
        #expect(model.undoState == .pending && outbox.removals.isEmpty)
        await server.releaseCreate()
        try await waitUntil { model.undoState == .confirmed }
        #expect(outbox.value == nil && outbox.removals == [withdrawal])
        #expect(model.mapObservations.isEmpty && model.confirmed == 0)
        let operations = await server.operations()
        let undoID = try #require(withdrawal.observationUndoOperationID)
        #expect(operations.creates == [original.id] && operations.removals == [undoID])
    }

    @Test func aLostCreateResponseThenOfflineUndoReconcilesAfterRestartWithoutAnotherCreation() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(losesCreateResponse: true)
        let first = recorder(outbox, server)
        #expect(first.markMoment())
        let original = try #require(outbox.value), receipt = try #require(first.lastAdded)
        try await waitUntil { first.errorMessage != nil && !first.isSending }
        await server.setOffline(true)
        #expect(await first.undoLastAdded(id: receipt.id))
        first.stop()
        let restored = recorder(outbox, server)
        #expect(restored.undoState == .pending)
        await server.setOffline(false)
        await restored.retry()
        #expect(restored.undoState == .confirmed && outbox.value == nil)
        let operations = await server.operations()
        #expect(operations.creates == [original.id] && operations.removals.count == 1)
    }

    @Test func aLostRemovalResponseCanBeVerifiedFromTheObservationWorkspace() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(losesRemovalResponse: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        try await waitUntil { model.confirmed == 1 && !model.isSending }
        await server.advanceObservationVersion() // Finalization/attachment changed v1 to v2.
        let receipt = try #require(model.lastAdded)
        #expect(await model.undoLastAdded(id: receipt.id))
        try await waitUntil { model.undoErrorMessage != nil && !model.isSending }
        let withdrawal = try #require(outbox.value)
        #expect(model.undoState == .pending && !model.mapObservations.isEmpty)
        model.stop()
        let workspace = SchoolObservationWorkspace(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client(server), outbox: outbox)
        await workspace.load()
        #expect(workspace.canRetry && workspace.pendingText.contains("Annulation"))
        await workspace.verifyPending()
        #expect(outbox.value == nil && workspace.pending == nil && workspace.confirmation == "Observation retirée.")
        #expect(outbox.removals.last == withdrawal)
        #expect(await server.operations().removals.count == 1)
        #expect(await server.removalVersions() == [2])
    }

    @Test func offlineUndoAfterFinalizationRelatesTheCreationReceiptToTheCurrentVersion() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer()
        let first = recorder(outbox, server)
        #expect(first.markMoment())
        try await waitUntil { first.confirmed == 1 && !first.isSending }
        let id = try #require(first.lastAdded?.id)
        await server.setOffline(true)
        #expect(await first.undoLastAdded(id: id))
        let withdrawal = try #require(outbox.value)
        first.stop()
        await server.advanceObservationVersion()
        await server.setOffline(false)
        let restored = recorder(outbox, server)
        await restored.retry()
        #expect(restored.undoState == .confirmed && outbox.value == nil)
        #expect(outbox.removals == [withdrawal])
        #expect(await server.removalVersions() == [2])
        let undoID = try #require(withdrawal.observationUndoOperationID)
        #expect(await server.operations().removals == [undoID])
    }

    @Test func aRemovalReceiptPrecedesCurrentVersionLookupOnRetryAfterItsResponseWasLost() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(losesRemovalResponse: true)
        let first = recorder(outbox, server)
        #expect(first.markMoment())
        try await waitUntil { first.confirmed == 1 && !first.isSending }
        await server.advanceObservationVersion()
        let id = try #require(first.lastAdded?.id)
        #expect(await first.undoLastAdded(id: id))
        try await waitUntil { first.undoErrorMessage != nil && !first.isSending }
        let withdrawal = try #require(outbox.value)
        first.stop()
        // The removed observation is absent from the list; its receipt alone resolves the retry.
        let restored = recorder(outbox, server)
        await restored.retry()
        #expect(restored.undoState == .confirmed && outbox.value == nil)
        let undoID = try #require(withdrawal.observationUndoOperationID)
        #expect(await server.removalAttempts() == [undoID])
        #expect(await server.removalVersions() == [2])
    }

    @Test func aVersionConflictRechecksTheReceiptAndRetriesTheSameWithdrawalOnce() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(advancesBeforeRemoval: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        try await waitUntil { model.confirmed == 1 && !model.isSending }
        let id = try #require(model.lastAdded?.id)
        #expect(await model.undoLastAdded(id: id))
        let withdrawal = try #require(outbox.value)
        try await waitUntil { model.undoState == .confirmed }
        #expect(outbox.value == nil && model.mapObservations.isEmpty)
        #expect(await server.removalVersions() == [1, 2])
        let undoID = try #require(withdrawal.observationUndoOperationID)
        #expect(await server.removalAttempts() == [undoID, undoID])
        #expect(await server.operations().removals == [undoID])
    }

    @Test func theCreateReceiptAloneCannotAcknowledgeAPendingWithdrawal() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer()
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        try await waitUntil { model.confirmed == 1 && !model.isSending }
        await server.setOffline(true)
        let id = try #require(model.lastAdded?.id)
        #expect(await model.undoLastAdded(id: id))
        model.stop()
        let withdrawal = try #require(outbox.value)
        await server.setOffline(false)
        do {
            _ = try await client(server).receipt(for: withdrawal)
            Issue.record("A creation receipt must not acknowledge its withdrawal")
        } catch { #expect(error as? SchoolObservationFailure == .notFound) }
        #expect(outbox.value == withdrawal)
        let workspace = SchoolObservationWorkspace(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client(server), outbox: outbox)
        await workspace.load()
        #expect(await workspace.retryPending())
        #expect(outbox.value == nil && workspace.observations.isEmpty)
    }

    @Test func stoppingWhileCreateIsInFlightPreservesUndoWithoutSendingItsRemoval() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(holdsCreate: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        try await waitForCreate(server)
        let id = try #require(model.lastAdded?.id)
        #expect(await model.undoLastAdded(id: id))
        let withdrawal = try #require(outbox.value)
        model.stop()
        await server.releaseCreate()
        try await waitUntil { !model.isSending }
        #expect(outbox.value == withdrawal && model.lastAdded == nil)
        #expect(await server.operations().removals.isEmpty)
    }

    @Test func aFailedSendClosesSignalAndARequestedRetryKeepsItClosedUntilItsResult() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer(offline: true, holdsCreate: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        #expect(model.acceptsSignal && model.isSettlingGesture)
        try await waitUntil { model.errorMessage != nil && !model.isSending }
        // L’échec dure : « Signaler » se ferme, avec son explication et son nouvel essai.
        #expect(!model.acceptsSignal && !model.isSettlingGesture && model.canRetry)
        await server.setOffline(false)
        let retrying = Task { await model.retry() }
        try await waitForCreate(server)
        // Un nouvel essai n’est pas l’envoi bref qui suit le geste : aucun aller-retour d’apparence.
        #expect(model.isSending && !model.isSettlingGesture && !model.acceptsSignal)
        await server.releaseCreate()
        await retrying.value
        #expect(model.acceptsSignal && model.canRecord && model.confirmed == 1 && outbox.value == nil)
    }

    @Test func theWithdrawalThatFollowsUndoKeepsSignalOpenLikeTheSendThatFollowsAGesture() async throws {
        let outbox = LiveUndoOutbox(), server = LiveUndoServer()
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        try await waitUntil { model.confirmed == 1 && !model.isSending }
        let id = try #require(model.lastAdded?.id)
        #expect(await model.undoLastAdded(id: id))
        #expect(model.isSending && model.isSettlingGesture && model.acceptsSignal && !model.canRecord)
        try await waitUntil { model.undoState == .confirmed && !model.isSending }
        #expect(!model.isSettlingGesture && model.acceptsSignal && model.canRecord && outbox.value == nil)
    }

    private func recorder(_ outbox: LiveUndoOutbox, _ server: LiveUndoServer) -> SchoolLiveObservationRecorder {
        SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client(server), outbox: outbox)
    }
    private func client(_ server: LiveUndoServer) -> SchoolObservationClient {
        SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(predicate())
    }
    private func waitForCreate(_ server: LiveUndoServer) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await server.hasStartedCreate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await server.hasStartedCreate())
    }
}

@MainActor private final class LiveUndoOutbox: SchoolCommandOutbox {
    var value: PendingSchoolCommand?
    var removals: [PendingSchoolCommand] = []
    var failSave = false
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { value }
    func save(_ command: PendingSchoolCommand) throws {
        if failSave { throw SchoolConfigurationFailure.storage }
        if let value, value != command {
            guard value.observationUndoOperationID == nil, command.observationUndoOperationID != nil,
                  command.withoutObservationUndo == value else { throw SchoolConfigurationFailure.pendingCommand }
        }
        value = command
    }
    func remove(_ command: PendingSchoolCommand) throws {
        guard value == command else { throw SchoolConfigurationFailure.storage }
        removals.append(command); value = nil
    }
}

private actor LiveUndoServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private var offline: Bool
    private let holdsCreate: Bool
    private let losesCreateResponse: Bool
    private let losesRemovalResponse: Bool
    private var advancesBeforeRemoval: Bool
    private var createRelease: CheckedContinuation<Void, Never>?
    private var createStarted = false
    private var createReleased = false
    private var values: [UUID: SchoolObservation] = [:]
    private var receipts: [UUID: SchoolOperationReceipt] = [:]
    private var createOperations: [UUID] = []
    private var removalOperations: [UUID] = []
    private var removalAttemptIDs: [UUID] = []
    private var removalAttemptVersions: [Int] = []
    private var committedRemovalVersions: [UUID: Int] = [:]

    init(offline: Bool = false, holdsCreate: Bool = false, losesCreateResponse: Bool = false,
         losesRemovalResponse: Bool = false, advancesBeforeRemoval: Bool = false) {
        self.offline = offline; self.holdsCreate = holdsCreate
        self.losesCreateResponse = losesCreateResponse; self.losesRemovalResponse = losesRemovalResponse
        self.advancesBeforeRemoval = advancesBeforeRemoval
    }
    func setOffline(_ value: Bool) { offline = value }
    func operations() -> (creates: [UUID], removals: [UUID]) { (createOperations, removalOperations) }
    func removalVersions() -> [Int] { removalAttemptVersions }
    func removalAttempts() -> [UUID] { removalAttemptIDs }
    func advanceObservationVersion() {
        for (id, old) in values {
            values[id] = SchoolObservation(id: old.id, schoolId: old.schoolId, version: old.version + 1,
                lessonId: old.lessonId, trainingId: old.trainingId, draftId: UUID(), captureId: old.captureId,
                segmentId: old.segmentId, pointSequence: old.pointSequence, competencyId: old.competencyId,
                text: old.text, origin: old.origin, observedAt: old.observedAt, eventKind: old.eventKind,
                eventStatus: old.eventStatus, authorMembershipId: old.authorMembershipId)
        }
    }
    func hasStartedCreate() -> Bool { createStarted }
    func releaseCreate() { createReleased = true; createRelease?.resume(); createRelease = nil }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        if offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        func response(_ value: some Encodable, status: Int = 200) throws -> SchoolHTTPResponse {
            let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
                "requestId": UUID().uuidString, "serverTime": "2026-09-28T12:15:00Z"]),
                status: status, url: url, contentType: "application/json")
        }
        func failure(_ code: String, status: Int) -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\"}".utf8), status: status, url: url,
                contentType: "application/problem+json")
        }
        if url.pathComponents.dropLast().last == "operations", let id = UUID(uuidString: url.lastPathComponent) {
            guard let receipt = receipts[id] else {
                return SchoolHTTPResponse(data: Data("{\"code\":\"NOT_FOUND\"}".utf8), status: 404, url: url, contentType: "application/problem+json")
            }
            return try response(receipt)
        }
        if url.lastPathComponent == "geo-observations", request.httpMethod == "POST" {
            let body = try JSONDecoder().decode(SchoolObservationBody.self, from: request.httpBody ?? Data())
            createOperations.append(body.operationId)
            createStarted = true
            if holdsCreate, !createReleased { await withCheckedContinuation { createRelease = $0 } }
            let observation = SchoolObservation(id: body.operationId, schoolId: HubFixture.schoolID, version: 1,
                lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
                captureId: body.captureId, segmentId: body.segmentId, pointSequence: body.pointSequence, competencyId: body.competencyId,
                text: body.text, origin: body.origin, observedAt: body.observedAt, eventKind: body.eventKind,
                eventStatus: body.eventStatus, authorMembershipId: ConfigurationFixture.membershipID)
            values[observation.id] = observation
            receipts[body.operationId] = .init(operationId: body.operationId, commandType: "CREATE_GEO_OBSERVATION",
                resourceType: "GeoObservation", resourceId: observation.id, committedAt: "2026-09-28T12:15:00Z", resourceVersion: 1)
            if losesCreateResponse { throw URLError(.networkConnectionLost) }
            return try response(observation, status: 201)
        }
        if url.lastPathComponent == "remove", let id = UUID(uuidString: url.pathComponents.dropLast().last ?? "") {
            let body = try JSONDecoder().decode(SchoolRemoveObservationBody.self, from: request.httpBody ?? Data())
            let version = Int((request.value(forHTTPHeaderField: "If-Match") ?? "").replacingOccurrences(of: "\"", with: "")) ?? 0
            removalAttemptIDs.append(body.operationId); removalAttemptVersions.append(version)
            struct Removal: Encodable { let operationId: UUID; let accepted: Bool }
            // Like schoolCommand: the operation hash is checked before the resource version.
            if let committedVersion = committedRemovalVersions[body.operationId] {
                guard version == committedVersion else { return failure("IDEMPOTENCY_MISMATCH", status: 409) }
                return try response(Removal(operationId: body.operationId, accepted: true))
            }
            if advancesBeforeRemoval { advancesBeforeRemoval = false; advanceObservationVersion() }
            guard let current = values[id] else { return failure("NOT_FOUND", status: 404) }
            guard version == current.version else { return failure("VERSION_CONFLICT", status: 412) }
            removalOperations.append(body.operationId); committedRemovalVersions[body.operationId] = version
            values[id] = nil
            receipts[body.operationId] = .init(operationId: body.operationId, commandType: "REMOVE_GEO_OBSERVATION",
                resourceType: "GeoObservation", resourceId: id, committedAt: "2026-09-28T12:15:00Z", resourceVersion: version + 1)
            if losesRemovalResponse { throw URLError(.networkConnectionLost) }
            return try response(Removal(operationId: body.operationId, accepted: true))
        }
        if url.lastPathComponent == "geo-observations" {
            struct Page: Encodable {
                let items: [SchoolObservation]
                func encode(to encoder: any Encoder) throws {
                    enum Key: String, CodingKey { case items, nextCursor }
                    var c = encoder.container(keyedBy: Key.self)
                    try c.encode(items, forKey: .items); try c.encodeNil(forKey: .nextCursor)
                }
            }
            return try response(Page(items: Array(values.values)))
        }
        return try await fallback.send(request)
    }
}
