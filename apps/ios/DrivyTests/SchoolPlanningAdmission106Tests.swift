import Foundation
import Testing
@testable import Drivy

/// #106 L2 : le client ne remet la mutation au transport que si l'annulation n'a pas déjà gagné.
/// Transports, jeton et coffre sont synthétiques ; aucune transaction PostgreSQL, aucun réseau réel.
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
        token.suspendOnCall(1)
        let server = AdmissionServer()
        let client = makeClient(token: token, server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        try await HubFixture.wait { await MainActor.run { token.calls == 1 && token.hasPendingWait } }
        #expect(token.hasPendingWait)
        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)
        token.resume()

        await #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) { try await attempt.value }
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
        await server.holdNextMe()
        let client = makeClient(token: token, server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        try await HubFixture.wait { await server.isHoldingMe() }
        #expect(await server.isHoldingMe())
        #expect(admission.cancel { try outbox.remove($0) } == .cancelledBeforeSend)
        await server.releaseMe()

        await #expect(throws: SchoolCommandAdmissionFailure.cancelledBeforeSend) { try await attempt.value }
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
        await server.holdNextWrite()
        let client = makeClient(token: AdmissionTokenSource(), server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        try await HubFixture.wait { await server.isHoldingWrite() }
        #expect(await server.isHoldingWrite())
        #expect(admission.cancel { try outbox.remove($0) } == .alreadyHandedToTransport)
        #expect(admission.phase == .handedToTransport)
        #expect(outbox.removals.isEmpty && outbox.commands == [command])
        await server.releaseWrite()

        let receipt = try await attempt.value
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
        token.suspendOnCall(2)
        let client = makeClient(token: token, server: server)

        let attempt = Task { try await client.send(command, admission: admission) }
        try await HubFixture.wait { await MainActor.run { token.calls == 2 && token.hasPendingWait } }
        #expect(token.hasPendingWait)
        #expect(await server.mutationCount() == 1)
        #expect(admission.phase == .handedToTransport)
        #expect(admission.cancel { try outbox.remove($0) } == .alreadyHandedToTransport)
        #expect(outbox.commands == [command])
        token.resume()

        let receipt = try await attempt.value
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

        await #expect(throws: SchoolPlanningFailure.forbidden) {
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

/// Jeton contrôlé : un appel précis peut rester suspendu, pour annuler pendant l'attente réelle du client.
@MainActor
private final class AdmissionTokenSource: AccessTokenSource {
    private(set) var calls = 0
    private(set) var invalidations = 0
    private var token = "token-1"
    private var suspendOn: Int?
    private var waiter: CheckedContinuation<Void, Never>?
    var hasPendingWait: Bool { waiter != nil }

    func suspendOnCall(_ number: Int) { suspendOn = number }

    func accessToken() async throws -> String {
        calls += 1
        if calls == suspendOn {
            suspendOn = nil
            await withCheckedContinuation { waiter = $0 }
        }
        return token
    }

    func invalidateAccessToken(_ token: String) async -> Bool {
        invalidations += 1
        self.token = "token-renewed"
        return true
    }

    func resume() {
        let pending = waiter
        waiter = nil
        pending?.resume()
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

/// Transport synthétique : compte séparément lectures et mutations, et suspend la remise ou /me à la demande.
/// Aucune transaction PostgreSQL n'est prétendue.
private actor AdmissionServer: SchoolHTTPTransport {
    private var recorded: [URLRequest] = []
    private var recordedMutations: [URLRequest] = []
    private var meReads = 0
    private var receiptReads = 0
    private var holdMe = false
    private var pausedMe: CheckedContinuation<Void, Never>?
    private var holdWrite = false
    private var pausedWrite: CheckedContinuation<Void, Never>?
    private var failNextMe = false
    private var failFirstWrite401 = false
    private var failNextWrite = false
    private var operationType = "CREATE_LESSON"

    func requestCount() -> Int { recorded.count }
    func mutations() -> [URLRequest] { recordedMutations }
    func mutationCount() -> Int { recordedMutations.count }
    func meReadCount() -> Int { meReads }
    func receiptReadCount() -> Int { receiptReads }
    func holdNextMe() { holdMe = true }
    func isHoldingMe() -> Bool { pausedMe != nil }
    func releaseMe() { pausedMe?.resume(); pausedMe = nil }
    func holdNextWrite() { holdWrite = true }
    func isHoldingWrite() -> Bool { pausedWrite != nil }
    func releaseWrite() { pausedWrite?.resume(); pausedWrite = nil }
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
            if holdMe {
                holdMe = false
                await withCheckedContinuation { pausedMe = $0 }
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
            if holdWrite {
                holdWrite = false
                await withCheckedContinuation { pausedWrite = $0 }
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
