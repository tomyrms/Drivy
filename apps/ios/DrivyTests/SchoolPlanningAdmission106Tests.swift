import Foundation
import Testing
@testable import Drivy

/// #106 L2 : le client ne remet la mutation au transport que si l'annulation n'a pas déjà gagné.
/// Transports, jeton et coffre sont synthétiques ; aucune transaction PostgreSQL, aucun réseau réel.
/// Toute retenue du harnais est bornée et libérable : un défaut d'arrivée ou une retenue oubliée échoue
/// explicitement au lieu de suspendre le test, et l'opération reste attendue sous une borne indépendante.
/// Aucune exécution Apple n'est revendiquée depuis Windows ; le RED/GREEN natif reste à observer au candidat.
@MainActor
struct SchoolPlanningAdmission106Tests {
    private let now = HubFixture.date("2027-01-15T10:00:00Z")

    @Test func anAdmissionStaysOptionalForEveryExistingCaller() async throws {
        let command = try creation()
        let server = AdmissionServer()
        let client = makeClient(token: AdmissionTokenSource(), server: server)

        let receipt = try await client.send(command)

        #expect(receipt?.operationId == command.id)
        #expect(await server.mutationCount() == 1)
        #expect(await server.receiptReadCount() == 1)
    }

    @Test func cancellingBeforeTheTokenRequestsNoTokenAndNoIdentityRead() async throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let token = AdmissionTokenSource()
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)

        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)
        await #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) {
            try await client.send(command, admission: admission)
        }

        #expect(token.calls == 0)
        #expect(await server.requestCount() == 0)
        #expect(await server.mutationCount() == 0)
        #expect(await server.meReadCount() == 0)
        #expect(outbox.commands.isEmpty)
        #expect(outbox.removals == [command])
    }

    @Test func cancellingWhileTheTokenIsHeldStopsBeforeAnyRequest() async throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let token = AdmissionTokenSource()
        let hold = token.hold(onCall: 1, label: "jeton 1")
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        // Nettoyage garanti avant toute attente : une assertion qui interrompt le scénario libère la retenue.
        defer { hold.release(); attempt.cancel() }
        try await requireArrival(hold, "jeton 1")
        try #require(token.calls == 1 && hold.isWaiting)

        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)
        hold.release()

        await #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) {
            try await boundedValue(attempt, label: "envoi après jeton")
        }
        #expect(token.calls == 1)
        #expect(await server.requestCount() == 0)
        #expect(await server.mutationCount() == 0)
        #expect(outbox.commands.isEmpty)
    }

    @Test func cancellingWhileMeIsHeldStopsTheMutationButKeepsTheReadThatAlreadyHappened() async throws {
        let command = try move()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let token = AdmissionTokenSource()
        let server = AdmissionServer()
        let hold = await server.holdNextMe()
        let client = makeClient(token: token, server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        defer { hold.release(); attempt.cancel() }
        try await requireArrival(hold, "lecture /me")
        try #require(hold.isWaiting)

        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)
        hold.release()

        await #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) {
            try await boundedValue(attempt, label: "envoi après /me")
        }
        // « Zéro mutation » ne prétend pas « zéro lecture » : /me a déjà eu lieu avant le verdict.
        #expect(await server.meReadCount() == 1)
        #expect(await server.mutationCount() == 0)
        #expect(await server.receiptReadCount() == 0)
        #expect(outbox.commands.isEmpty)
    }

    @Test func cancellingAfterTheHandOffLosesTheRaceAndTheWriteStaysFollowed() async throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let server = AdmissionServer()
        let hold = await server.holdNextWrite()
        let client = makeClient(token: AdmissionTokenSource(), server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        defer { hold.release(); attempt.cancel() }
        try await requireArrival(hold, "écriture")
        let mutationsAtArrival = await server.mutationCount()
        try #require(mutationsAtArrival == 1)

        #expect(admission.cancel { try outbox.remove($0) } == .alreadyHandedToTransport)
        #expect(admission.phase == .handedToTransport)
        #expect(outbox.removals.isEmpty && outbox.commands == [command])
        hold.release()

        let receipt = try await boundedValue(attempt, label: "écriture remise")
        #expect(receipt?.operationId == command.id)
        #expect(await server.mutationCount() == 1)
        // Le client ne retire jamais la commande : la preuve AP72 revient au suivi existant.
        #expect(outbox.commands == [command])
    }

    @Test func aCancellationDuringTheRenewalAfter401CannotUndoTheHandedWrite() async throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let server = AdmissionServer()
        await server.failFirstWriteWith401()
        let token = AdmissionTokenSource()
        let hold = token.hold(onCall: 2, label: "jeton 2")
        let client = makeClient(token: token, server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        defer { hold.release(); attempt.cancel() }
        try await requireArrival(hold, "jeton 2")
        let mutationsAtArrival = await server.mutationCount()
        try #require(mutationsAtArrival == 1)

        #expect(admission.phase == .handedToTransport)
        #expect(admission.cancel { try outbox.remove($0) } == .alreadyHandedToTransport)
        #expect(outbox.commands == [command])
        hold.release()

        let receipt = try await boundedValue(attempt, label: "envoi après renouvellement")
        #expect(receipt?.operationId == command.id)
        let writes = await server.mutations()
        #expect(writes.count == 2)
        #expect(writes[0].httpBody == command.body && writes[1].httpBody == command.body)
        #expect(writes[0].value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
        #expect(writes[1].value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
        #expect(writes[0].value(forHTTPHeaderField: "If-Match") == nil)
        #expect(writes[1].value(forHTTPHeaderField: "If-Match") == nil)
        #expect(token.invalidations == 1 && token.calls == 2)
    }

    @Test func aFailedRemovalClosesTheEmissionAndTheRetryRemovesOnlyTheExactRecord() async throws {
        let command = try creation()
        let other = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command, other])
        outbox.failuresRemaining = 1
        let token = AdmissionTokenSource()
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)

        #expect(admission.cancel { try outbox.remove($0) } == .storageFailure)
        #expect(admission.phase == .cancellationStorageFailed)
        #expect(outbox.commands == [command, other])
        await #expect(throws: SchoolCommandAdmissionFailure.cancellationStorageFailed) {
            try await client.send(command, admission: admission)
        }
        #expect(token.calls == 0)
        #expect(await server.requestCount() == 0)
        // Le retrait a échoué : l'intention reste conservée telle quelle, rien n'est réécrit ni renvoyé.
        #expect(outbox.commands == [command, other])
        #expect(outbox.saves.isEmpty)

        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)
        #expect(outbox.commands == [other])
        #expect(outbox.removals == [command])
        #expect(outbox.removals.first == command)
        #expect(outbox.removals.first?.createdAt == command.createdAt)
        #expect(outbox.removals.first?.body == command.body)
        #expect(outbox.removals.first?.resourceVersion == command.resourceVersion)
    }

    @Test func anotherCommandOrAnotherScopeIsRefusedBeforeAnyToken() async throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        let other = try creation()
        let altered = try creation(id: command.id, scope: ConfigurationFixture.scope(epoch: 4),
                                   start: now.addingTimeInterval(7_200))
        let token = AdmissionTokenSource()
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)

        await #expect(throws: SchoolCommandAdmissionFailure.wrongCommand) {
            try await client.send(other, admission: admission)
        }
        await #expect(throws: SchoolCommandAdmissionFailure.wrongCommand) {
            try await client.send(altered, admission: admission)
        }

        #expect(admission.phase == .waiting)
        #expect(token.calls == 0)
        #expect(await server.requestCount() == 0)
    }

    @Test func anAdmissionNeverCoversAnotherCommandFamily() async throws {
        let command = try cancellation()
        let admission = SchoolCommandSendAdmission(command: command)
        let token = AdmissionTokenSource()
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)

        await #expect(throws: SchoolPlanningFailure.invalidResponse) {
            try await client.send(command, admission: admission)
        }

        #expect(admission.phase == .waiting)
        #expect(token.calls == 0)
        #expect(await server.requestCount() == 0)
    }

    @Test func readsAndAP72AreNotSubjectToTheAdmission() async throws {
        let command = try creation()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let token = AdmissionTokenSource()
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)
        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)

        let receipt = try await client.receipt(for: command)
        let lessons = try await client.recentLessons(schoolID: ConfigurationFixture.schoolID, trainingID: HubFixture.trainingID)

        #expect(receipt.operationId == command.id)
        #expect(await server.receiptReadCount() == 1)
        #expect(lessons.isEmpty)
        #expect(await server.mutationCount() == 0)
    }

    @Test func theSlotBarrierStillRefusesBeforeTheHandOff() async throws {
        let command = try creation(start: now.addingTimeInterval(-60))
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let token = AdmissionTokenSource()
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)

        await #expect(throws: SchoolPlanningWriteRefusal.lessonStartNotAdmissible) {
            try await client.send(command, admission: admission)
        }

        // La barrière L1b a refusé avant la remise : l'admission reste annulable, sans paquet ni jeton.
        #expect(admission.phase == .waiting)
        #expect(token.calls == 0)
        #expect(await server.requestCount() == 0)
        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)
        #expect(outbox.commands.isEmpty)
    }

    @Test func aRetryAfterAPreHandOffRefusalKeepsTheSameBytesAndTheSameAdmission() async throws {
        let command = try move()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let server = AdmissionServer()
        await server.failNextMeWith403()
        let token = AdmissionTokenSource()
        let client = makeClient(token: token, server: server)

        await #expect(throws: SchoolAPIError.forbidden) {
            try await client.send(command, admission: admission)
        }
        #expect(admission.phase == .waiting)
        #expect(await server.mutationCount() == 0)
        #expect(outbox.commands == [command] && outbox.removals.isEmpty)

        let receipt = try await client.send(command, admission: admission)

        #expect(receipt?.operationId == command.id)
        #expect(admission.phase == .handedToTransport)
        let writes = await server.mutations()
        #expect(writes.count == 1)
        #expect(writes[0].httpBody == command.body)
        #expect(writes[0].value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
        #expect(writes[0].value(forHTTPHeaderField: "If-Match") == "\"2\"")
        #expect(writes[0].url?.lastPathComponent == "move")
    }

    @Test func aRetryAfterATransportFailureKeepsTheHandedAdmissionAndTheExactRequest() async throws {
        let command = try move()
        let admission = SchoolCommandSendAdmission(command: command)
        let outbox = AdmissionOutboxStub([command])
        let server = AdmissionServer()
        await server.failNextWriteWithURLError()
        let client = makeClient(token: AdmissionTokenSource(), server: server)

        await #expect(throws: SchoolPlanningFailure.unavailable) {
            try await client.send(command, admission: admission)
        }
        // La remise a eu lieu : l'échec de transport ne prouve pas l'absence d'écriture et ne rend pas annulable.
        #expect(admission.phase == .handedToTransport)
        #expect(admission.cancel { try outbox.remove($0) } == .alreadyHandedToTransport)
        #expect(outbox.commands == [command])

        let receipt = try await client.send(command, admission: admission)

        #expect(receipt?.operationId == command.id)
        let writes = await server.mutations()
        #expect(writes.count == 2)
        #expect(writes[0].httpBody == writes[1].httpBody)
        #expect(writes[0].value(forHTTPHeaderField: "Idempotency-Key") == writes[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(writes[0].value(forHTTPHeaderField: "If-Match") == writes[1].value(forHTTPHeaderField: "If-Match"))
        #expect(admission.phase == .handedToTransport)
    }

    // MARK: - Contrôle du harnais

    @Test func theBoundedHoldFailsExplicitlyWhenNeverReleased() async throws {
        let hold = BoundedHold("retenue jamais libérée", timeout: .milliseconds(50))

        await #expect(throws: BoundedHold.Failure.timedOut("retenue jamais libérée")) {
            try await boundedValue(Task { try await hold.wait() }, label: "retenue seule", timeout: .seconds(3))
        }

        // L'échéance a libéré l'attente ; la libération tardive reste sans effet et ne ressemble pas à un succès.
        #expect(!hold.isWaiting)
        hold.release()
        #expect(!hold.isWaiting)
    }

    @Test func anOperationThatNeverReachesTheHoldFailsTheArrivalUnderABound() async throws {
        let hold = BoundedHold("point jamais atteint", timeout: .seconds(30))
        // Opération volontairement non coopérative : elle n'atteint jamais la retenue.
        let attempt = Task { try await Task.sleep(for: .seconds(30)) }
        defer { hold.release(); attempt.cancel() }

        await #expect(throws: AdmissionHarnessFailure.arrivalTimedOut("point jamais atteint")) {
            try await requireArrival(hold, "point jamais atteint", timeout: .milliseconds(50))
        }

        #expect(!hold.isWaiting)
    }

    @Test func anOperationThatNeverTerminatesFailsUnderTheExternalBound() async throws {
        // L'opération ne termine pas et n'atteint aucune retenue : seule la borne externe peut conclure.
        let never = Task { try await Task.sleep(for: .seconds(30)); return 0 }
        defer { never.cancel() }

        await #expect(throws: BoundedOutcome<Int>.Failure.timedOut("opération sans fin")) {
            try await boundedValue(never, label: "opération sans fin", timeout: .milliseconds(50))
        }
        // L'annulation suit la publication de l'échéance ; la confirmation est bornée, jamais une attente nue.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !never.isCancelled, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(never.isCancelled)
    }

    @Test func aReleaseArrivingBeforeTheWaitIsNotLost() async throws {
        let hold = BoundedHold("libérée avant attente", timeout: .milliseconds(50))
        hold.release()

        // La libération anticipée est mémorisée : aucune attente, aucune expiration, aucun faux succès d'opération.
        try await boundedValue(Task { try await hold.wait() }, label: "libération anticipée", timeout: .seconds(3))
        #expect(!hold.isWaiting)
        hold.release()
        #expect(!hold.isWaiting)
    }

    // MARK: - Outils

    private func makeClient(token: AdmissionTokenSource, server: AdmissionServer) -> SchoolPlanningClient {
        let instant = now
        return SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: token, transport: server, now: { instant })
    }

    private func creation(id: UUID = UUID(), scope: SchoolCommandScope = ConfigurationFixture.scope(),
                          start: Date? = nil) throws -> PendingSchoolCommand {
        let start = start ?? now.addingTimeInterval(3_600)
        return PendingSchoolCommand(id: id, scope: scope, kind: .createLesson, resourceVersion: 0, createdAt: now,
            body: try lessonBody(id: id, start: start), routeResourceID: HubFixture.trainingID)
    }

    private func move() throws -> PendingSchoolCommand {
        let id = UUID()
        return PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: .moveLesson, resourceVersion: 2,
            createdAt: now, body: try lessonBody(id: id, start: now.addingTimeInterval(3_600)), resourceID: HubFixture.lessonID)
    }

    private func cancellation() throws -> PendingSchoolCommand {
        let id = UUID()
        let body = try JSONSerialization.data(withJSONObject: ["operationId": id.uuidString,
            "reasonCode": "OTHER", "comment": ""], options: [.sortedKeys])
        return PendingSchoolCommand(id: id, scope: ConfigurationFixture.scope(), kind: .cancelLesson, resourceVersion: 2,
            createdAt: now, body: body, resourceID: HubFixture.lessonID)
    }

    private func lessonBody(id: UUID, start: Date) throws -> Data {
        let iso = ISO8601DateFormatter()
        return try JSONSerialization.data(withJSONObject: ["operationId": id.uuidString,
            "plannedStart": iso.string(from: start), "plannedEnd": iso.string(from: start.addingTimeInterval(3_000)),
            "timeZone": "Europe/Zurich", "trainingId": HubFixture.trainingID.uuidString,
            "instructorMembershipId": ConfigurationFixture.membershipID.uuidString], options: [.sortedKeys])
    }
}

/// Échec du harnais lui-même : une arrivée attendue qui ne vient pas doit interrompre le scénario.
private enum AdmissionHarnessFailure: Error, Equatable {
    case arrivalTimedOut(String)
}

/// Retenue d'un point d'observation du transport ou du jeton.
/// - toute attente a une échéance interne et échoue explicitement (`timedOut`) ;
/// - `release()` est idempotente et mémorise une libération arrivée avant l'enregistrement ;
/// - une seconde attente concurrente est refusée au lieu d'écraser la première.
private final class BoundedHold: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case timedOut(String)
        case duplicateWait(String)
    }

    private let label: String
    private let timeout: Duration
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Error>?
    private var released = false
    private var deadline: Task<Void, Never>?

    init(_ label: String, timeout: Duration = .seconds(5)) {
        self.label = label
        self.timeout = timeout
    }

    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiter != nil
    }

    func wait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
                return
            }
            if waiter != nil {
                lock.unlock()
                continuation.resume(throwing: Failure.duplicateWait(label))
                return
            }
            waiter = continuation
            let timeout = self.timeout
            deadline = Task.detached { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.expire()
            }
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        released = true
        let pending = waiter
        waiter = nil
        let timer = deadline
        deadline = nil
        lock.unlock()
        timer?.cancel()
        pending?.resume()
    }

    private func expire() {
        lock.lock()
        let pending = waiter
        waiter = nil
        deadline = nil
        lock.unlock()
        pending?.resume(throwing: Failure.timedOut(label))
    }
}

/// Attend que l'opération atteigne la retenue, avec une échéance propre au harnais : la borne silencieuse
/// d'un poll d'arrivée ne suffit jamais à elle seule.
private func requireArrival(_ hold: BoundedHold, _ label: String,
                            timeout: Duration = .seconds(3)) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !hold.isWaiting {
        guard ContinuousClock.now < deadline else {
            throw AdmissionHarnessFailure.arrivalTimedOut(label)
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// Résultat unique d'une course entre l'opération et son échéance externe : la première issue gagne,
/// les suivantes sont ignorées. Une échéance produit un échec explicite, jamais un succès.
private final class BoundedOutcome<Value: Sendable>: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case timedOut(String)
    }

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(throwing: Failure.timedOut("résultat déjà publié"))
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    @discardableResult
    func complete(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard !finished else { lock.unlock(); return false }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        switch result {
        case .success(let value): continuation?.resume(returning: value)
        case .failure(let error): continuation?.resume(throwing: error)
        }
        return true
    }
}

/// Attend la terminaison de l'opération sous une borne externe indépendante des retenues et de `HubFixture.wait`.
/// À l'échéance : échec explicite et annulation de la tâche ; aucune jointure non coopérative ne décide du verdict.
@MainActor
private func boundedValue<Value: Sendable>(_ task: Task<Value, Error>, label: String,
                                           timeout: Duration = .seconds(10)) async throws -> Value {
    let outcome = BoundedOutcome<Value>()
    return try await withCheckedThrowingContinuation { continuation in
        outcome.install(continuation)
        _ = Task.detached {
            do { outcome.complete(.success(try await task.value)) }
            catch { outcome.complete(.failure(error)) }
        }
        _ = Task.detached {
            try? await Task.sleep(for: timeout)
            // L'échéance publie l'échec, puis annule la tâche : le verdict ne dépend pas de la coopération.
            if outcome.complete(.failure(BoundedOutcome<Value>.Failure.timedOut(label))) {
                task.cancel()
            }
        }
    }
}

/// Jeton contrôlé : un appel précis peut rester suspendu sur une retenue bornée, pour annuler pendant
/// l'attente réelle du client. Aucun point de suspension n'existe sans échéance.
@MainActor
private final class AdmissionTokenSource: AccessTokenSource {
    private(set) var calls = 0
    private(set) var invalidations = 0
    private var token = "token-1"
    private var holds: [Int: BoundedHold] = [:]

    @discardableResult
    func hold(onCall number: Int, label: String) -> BoundedHold {
        let hold = BoundedHold(label)
        holds[number] = hold
        return hold
    }

    func accessToken() async throws -> String {
        calls += 1
        if let hold = holds.removeValue(forKey: calls) { try await hold.wait() }
        return token
    }

    func invalidateAccessToken(_ token: String) async -> Bool {
        invalidations += 1
        self.token = "token-renewed"
        return true
    }
}

/// Coffre synthétique : retire le record exact, jamais un identifiant voisin, et peut échouer à la demande.
@MainActor
private final class AdmissionOutboxStub: SchoolCommandOutbox {
    var commands: [PendingSchoolCommand]
    private(set) var removals: [PendingSchoolCommand] = []
    private(set) var saves: [PendingSchoolCommand] = []
    var failuresRemaining = 0

    init(_ commands: [PendingSchoolCommand]) { self.commands = commands }

    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? {
        commands.first { $0.scope.belongsToWorkspace(scope) }
    }

    func pendingCommands(for scope: SchoolCommandScope) throws -> [PendingSchoolCommand] {
        commands.filter { $0.scope.belongsToWorkspace(scope) }
    }

    func save(_ command: PendingSchoolCommand) throws {
        saves.append(command)
        if !commands.contains(command) { commands.append(command) }
    }

    func remove(_ command: PendingSchoolCommand) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw SchoolConfigurationFailure.storage
        }
        guard let index = commands.firstIndex(where: { $0 == command }) else { throw SchoolConfigurationFailure.storage }
        removals.append(command)
        commands.remove(at: index)
    }
}

/// Transport synthétique : compte séparément lectures et mutations, et suspend `/me` ou la remise sur des
/// retenues bornées. Aucune transaction PostgreSQL n'est prétendue.
private actor AdmissionServer: SchoolHTTPTransport {
    private var recorded: [URLRequest] = []
    private var recordedMutations: [URLRequest] = []
    private var meReads = 0
    private var receiptReads = 0
    private var meHold: BoundedHold?
    private var writeHold: BoundedHold?
    private var failNextMe = false
    private var failFirstWrite401 = false
    private var failNextWrite = false
    private var operationType = "CREATE_LESSON"

    func requestCount() -> Int { recorded.count }
    func mutations() -> [URLRequest] { recordedMutations }
    func mutationCount() -> Int { recordedMutations.count }
    func meReadCount() -> Int { meReads }
    func receiptReadCount() -> Int { receiptReads }
    func holdNextMe(_ label: String = "lecture /me") -> BoundedHold {
        let hold = BoundedHold(label)
        meHold = hold
        return hold
    }
    func holdNextWrite(_ label: String = "écriture") -> BoundedHold {
        let hold = BoundedHold(label)
        writeHold = hold
        return hold
    }
    func failNextMeWith403() { failNextMe = true }
    func failFirstWriteWith401() { failFirstWrite401 = true }
    func failNextWriteWithURLError() { failNextWrite = true }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        guard let url = request.url else { throw URLError(.badURL) }
        let parts = url.pathComponents
        if parts.last == "me" {
            meReads += 1
            if failNextMe {
                failNextMe = false
                return problem(403, "FORBIDDEN", url: url)
            }
            if let hold = meHold {
                meHold = nil
                try await hold.wait()
            }
            let person: [String: Any] = ["personId": ConfigurationFixture.personID.uuidString, "version": 1,
                "displayName": "Moniteur de test", "locale": "fr",
                "memberships": [["membershipId": ConfigurationFixture.membershipID.uuidString,
                    "schoolId": ConfigurationFixture.schoolID.uuidString, "schoolName": "École de test",
                    "roles": ["ADMIN", "INSTRUCTOR"], "grants": [], "accessEpoch": 1] as [String: Any]]]
            return try envelope(person, status: 200, url: url)
        }
        if request.httpMethod == "POST" {
            recordedMutations.append(request)
            operationType = parts.last == "move" ? "MOVE_LESSON" : "CREATE_LESSON"
            if let hold = writeHold {
                writeHold = nil
                try await hold.wait()
            }
            if failNextWrite {
                failNextWrite = false
                throw URLError(.networkConnectionLost)
            }
            if failFirstWrite401 {
                failFirstWrite401 = false
                return problem(401, "UNAUTHORIZED", url: url)
            }
            return try envelope([:], status: parts.last == "lessons" ? 201 : 200, url: url)
        }
        if parts.dropLast().last == "operations" {
            receiptReads += 1
            let operationID = UUID(uuidString: parts.last ?? "") ?? UUID()
            let data: [String: Any] = ["operationId": operationID.uuidString, "commandType": operationType,
                "resourceType": "Lesson", "resourceId": HubFixture.lessonID.uuidString,
                "committedAt": ISO8601DateFormatter().string(from: Date()),
                "resourceVersion": operationType == "CREATE_LESSON" ? 1 : 3]
            return try envelope(data, status: 200, url: url)
        }
        if parts.last == "lessons" {
            return try envelope(["items": [] as [Any], "nextCursor": NSNull()], status: 200, url: url)
        }
        throw URLError(.unsupportedURL)
    }

    private func envelope(_ data: Any, status: Int, url: URL) throws -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
            "requestId": UUID().uuidString, "serverTime": ISO8601DateFormatter().string(from: Date())]),
            status: status, url: url, contentType: "application/json")
    }

    private func problem(_ status: Int, _ code: String, url: URL) -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\",\"title\":\"Refus synthétique\"}".utf8),
            status: status, url: url, contentType: "application/problem+json")
    }
}
