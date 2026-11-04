import Foundation
import Testing
@testable import Drivy

/// #106 L1b : barrière native du créneau demandé avant chaque transport d'écriture.
/// Aucun réseau réel, aucune transaction PostgreSQL : transports synthétiques et horloge contrôlée.
/// Le RED/GREEN natif reste à exécuter sur un runner Apple ; ces tests préparent la règle et son câblage.
@MainActor
struct SchoolPlanningRecovery106Tests {
    private let now = HubFixture.date("2027-01-15T10:00:00Z")

    // MARK: - Règle pure

    @Test func onlyCreationAndMoveCarryTheRequestedStartRule() throws {
        let future = now.addingTimeInterval(3_600)
        let creation = try lessonCommand(.createLesson, start: future)
        let move = try lessonCommand(.moveLesson, start: future)
        let cancellation = try cancellationCommand()
        let startNow = try startNowCommand()

        #expect(SchoolPlanningRecoveryPolicy.admission(creation, at: now) == .future(future))
        #expect(SchoolPlanningRecoveryPolicy.admission(move, at: now) == .future(future))
        #expect(SchoolPlanningRecoveryPolicy.admission(cancellation, at: now) == .notConcerned)
        #expect(SchoolPlanningRecoveryPolicy.admission(startNow, at: now) == .notConcerned)
        #expect(SchoolPlanningRecoveryPolicy.permitsWrite(cancellation, at: now))
        #expect(SchoolPlanningRecoveryPolicy.permitsWrite(startNow, at: now))
        #expect(!cancellation.isStaleLessonRequest(at: now))
    }

    @Test func equalityAndPastCloseTheWrite() throws {
        for offset in [0.0, -1.0] {
            let start = now.addingTimeInterval(offset)
            let command = try lessonCommand(.createLesson, start: start)
            #expect(SchoolPlanningRecoveryPolicy.admission(command, at: now) == .notFuture(start))
            #expect(!SchoolPlanningRecoveryPolicy.permitsWrite(command, at: now))
            #expect(command.isStaleLessonRequest(at: now))
        }
    }

    @Test func anAbsentOrUnreadableStartNeverAuthorisesAWrite() throws {
        let future = now.addingTimeInterval(3_600)
        let missing = try lessonCommand(.createLesson, start: future, includeStart: false)
        let word = try lessonCommand(.moveLesson, start: future, plannedStart: "pas-une-date")
        let number = try lessonCommand(.createLesson, start: future, plannedStart: 42)

        for command in [missing, word, number] {
            #expect(SchoolPlanningRecoveryPolicy.admission(command, at: now) == .unreadable)
            #expect(!SchoolPlanningRecoveryPolicy.permitsWrite(command, at: now))
            #expect(command.isStaleLessonRequest(at: now))
        }
    }

    // MARK: - Client direct

    @Test func aFutureCreationWritesOnceWithItsExactHeaders() async throws {
        let clock = RecoveryClock(now)
        let token = RecoveryTokenSource()
        let server = RecoveryServer()
        let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(3_600))
        let client = makeClient(clock: clock, token: token, server: server)

        let receipt = try await client.send(command)

        #expect(receipt?.operationId == command.id)
        let writes = await server.writes()
        #expect(writes.count == 1)
        let write = try #require(writes.first)
        #expect(write.httpBody == command.body)
        #expect(write.value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
        #expect(write.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
        #expect(write.value(forHTTPHeaderField: "If-Match") == nil)
        #expect(token.calls == 1)
        #expect(clock.now == now)
    }

    @Test func aFutureMoveKeepsItsVersionPrecondition() async throws {
        let clock = RecoveryClock(now)
        let server = RecoveryServer()
        let command = try lessonCommand(.moveLesson, start: now.addingTimeInterval(3_600))
        let client = makeClient(clock: clock, token: RecoveryTokenSource(), server: server)

        let receipt = try await client.send(command)

        #expect(receipt?.operationId == command.id)
        let write = try #require(await server.writes().first)
        #expect(write.url?.lastPathComponent == "move")
        #expect(write.httpBody == command.body)
        #expect(write.value(forHTTPHeaderField: "If-Match") == "\"2\"")
        #expect(write.value(forHTTPHeaderField: "Idempotency-Key") == command.id.uuidString)
    }

    @Test func anEqualOrPastStartIsRefusedBeforeAnyTokenOrNetwork() async throws {
        for offset in [0.0, -1.0] {
            let clock = RecoveryClock(now)
            let token = RecoveryTokenSource()
            let server = RecoveryServer()
            let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(offset))
            let client = makeClient(clock: clock, token: token, server: server)

            await #expect(throws: SchoolPlanningWriteRefusal.lessonStartNotAdmissible) {
                try await client.send(command)
            }
            #expect(token.calls == 0)
            #expect(await server.requestCount() == 0)
        }
    }

    @Test func anAbsentOrUnreadableStartIsRefusedBeforeAnyTokenOrNetwork() async throws {
        let future = now.addingTimeInterval(3_600)
        let commands = [
            try lessonCommand(.createLesson, start: future, includeStart: false),
            try lessonCommand(.moveLesson, start: future, plannedStart: "pas-une-date"),
            try lessonCommand(.createLesson, start: future, plannedStart: 42)
        ]
        for command in commands {
            let clock = RecoveryClock(now)
            let token = RecoveryTokenSource()
            let server = RecoveryServer()
            let client = makeClient(clock: clock, token: token, server: server)

            await #expect(throws: SchoolPlanningWriteRefusal.lessonStartNotAdmissible) {
                try await client.send(command)
            }
            #expect(token.calls == 0)
            #expect(await server.requestCount() == 0)
        }
    }

    @Test func otherCommandsStillWriteWhateverTheirDates() async throws {
        let clock = RecoveryClock(now)
        let server = RecoveryServer()
        let command = try cancellationCommand()
        let client = makeClient(clock: clock, token: RecoveryTokenSource(), server: server)

        let receipt = try await client.send(command)

        #expect(receipt?.operationId == command.id)
        let writes = await server.writes()
        #expect(writes.count == 1 && writes.first?.url?.lastPathComponent == "cancel")
    }

    // MARK: - Expiration pendant les attentes

    @Test func anExpiryWhileTheTokenIsSuspendedSendsNoWrite() async throws {
        let clock = RecoveryClock(now)
        let token = RecoveryTokenSource()
        token.suspendOnNextCall()
        let server = RecoveryServer()
        let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(60))
        let client = makeClient(clock: clock, token: token, server: server)

        let attempt = Task { try await client.send(command) }
        try await waitForSuspendedToken(token, call: 1)
        #expect(token.hasPendingWait)
        clock.advance(by: 120)
        token.resume()

        await #expect(throws: SchoolPlanningWriteRefusal.lessonStartNotAdmissible) {
            try await attempt.value
        }
        #expect(await server.writes().isEmpty)
        #expect(token.calls == 1)
    }

    @Test func anExpiryWhileMeIsSuspendedSendsNoWrite() async throws {
        let clock = RecoveryClock(now)
        let server = RecoveryServer()
        await server.holdNextMe()
        let command = try lessonCommand(.moveLesson, start: now.addingTimeInterval(60))
        let client = makeClient(clock: clock, token: RecoveryTokenSource(), server: server)

        let attempt = Task { try await client.send(command) }
        try await HubFixture.wait { await server.isHoldingMe() }
        #expect(await server.isHoldingMe())
        clock.advance(by: 120)
        await server.releaseMe()

        await #expect(throws: SchoolPlanningWriteRefusal.lessonStartNotAdmissible) {
            try await attempt.value
        }
        #expect(await server.writes().isEmpty)
        #expect(await server.meReadCount() == 1)
    }

    @Test func anExpiryBeforeTheSecondAttemptAfter401LeavesOnlyTheFirst401() async throws {
        let clock = RecoveryClock(now)
        let token = RecoveryTokenSource()
        token.suspendOnCall(2)
        let server = RecoveryServer(firstWriteStatus: 401)
        let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(60))
        let client = makeClient(clock: clock, token: token, server: server)

        let attempt = Task { try await client.send(command) }
        try await waitForSuspendedToken(token, call: 2)
        #expect(token.hasPendingWait)
        clock.advance(by: 120)
        token.resume()

        await #expect(throws: SchoolPlanningWriteRefusal.lessonStartNotAdmissible) {
            try await attempt.value
        }
        #expect(await server.writes().count == 1)
        #expect(await server.firstWriteWas401())
        #expect(token.invalidations == 1)
        #expect(token.calls == 2)
    }

    // MARK: - Reprise et reçu

    @Test func aWorkspaceRetryLosingItsSlotKeepsTheSameCommandWithoutRemoval() async throws {
        let clock = RecoveryClock(now)
        let token = RecoveryTokenSource()
        let server = RecoveryServer()
        let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(60))
        let outbox = ConfigurationOutboxStub(value: command)
        let client = makeClient(clock: clock, token: token, server: server)
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client,
            date: now.addingTimeInterval(3_600), outbox: outbox)
        await model.load()
        try #require(model.pending == command && model.canRetry && !model.pendingIsStale)

        let suspendedCall = token.suspendOnNextCall()
        let attempt = Task { await model.retry() }
        try await waitForSuspendedToken(token, call: suspendedCall)
        #expect(token.hasPendingWait)
        clock.advance(by: 120)
        token.resume()

        #expect(try await attempt.value == false)
        // Le refus est local et non définitif : mêmes octets, même identifiant, même version, aucune suppression.
        #expect(outbox.value == command)
        #expect(outbox.removals.isEmpty)
        #expect(outbox.saves == [command])
        #expect(model.pending == command)
        #expect(model.pending?.id == command.id)
        #expect(model.pending?.body == command.body)
        #expect(model.pending?.resourceVersion == command.resourceVersion)
        #expect(model.pendingIsStale && !model.canRetry)
        #expect(model.errorMessage != nil)
        #expect(await server.writes().isEmpty)
    }

    @Test func aKeptCommandWithoutReadableStartIsNotRetriedOrRemoved() async throws {
        let clock = RecoveryClock(now)
        let server = RecoveryServer()
        let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(3_600), includeStart: false)
        let outbox = ConfigurationOutboxStub(value: command)
        let client = makeClient(clock: clock, token: RecoveryTokenSource(), server: server)
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client,
            date: now.addingTimeInterval(3_600), outbox: outbox)
        await model.load()

        #expect(model.pending == command && model.pendingIsStale && !model.canRetry)
        // Aucun début lisible : la note d’un horaire « passé » serait fausse, mais le renvoi reste fermé.
        #expect(model.pendingNotes.isEmpty)
        #expect(await model.retry() == false)
        #expect(outbox.value == command && outbox.removals.isEmpty)
        #expect(await server.writes().isEmpty)
    }

    @Test func anExpiredStartStillVerifiesAndConfirmsLate() async throws {
        let clock = RecoveryClock(now)
        let server = RecoveryServer()
        let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(-60))
        let outbox = ConfigurationOutboxStub(value: command)
        let client = makeClient(clock: clock, token: RecoveryTokenSource(), server: server)
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client,
            date: now.addingTimeInterval(3_600), outbox: outbox)
        await model.load()
        #expect(model.pending == command && model.pendingIsStale && !model.canRetry)

        // Une expiration ne prouve jamais que l'école n'a pas enregistré : le renvoi est fermé, pas la vérification.
        #expect(await model.retry() == false)
        #expect(outbox.value == command && outbox.removals.isEmpty)
        #expect(await server.writes().isEmpty)

        await model.verify()

        #expect(model.pending == nil && outbox.value == nil && outbox.removals == [command])
        #expect(model.successMessage != nil && model.confirmedLesson != nil)
        #expect(await server.receiptReadCount() == 1)
        #expect(await server.writes().isEmpty)
    }

    @Test func aReceiptStaysReadableAfterTheRequestedStartPassed() async throws {
        let clock = RecoveryClock(now)
        let server = RecoveryServer()
        let command = try lessonCommand(.createLesson, start: now.addingTimeInterval(60))
        let client = makeClient(clock: clock, token: RecoveryTokenSource(), server: server)
        clock.advance(by: 3_600)

        let receipt = try await client.receipt(for: command)

        #expect(receipt.operationId == command.id)
        #expect(receipt.commandType == "CREATE_LESSON")
        #expect(await server.writes().isEmpty)
    }

    // MARK: - Outils

    private func waitForSuspendedToken(_ token: RecoveryTokenSource, call: Int) async throws {
        try await HubFixture.wait { await MainActor.run { token.calls == call && token.hasPendingWait } }
    }

    private func makeClient(clock: RecoveryClock, token: RecoveryTokenSource, server: RecoveryServer) -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: token, transport: server, now: { clock.now })
    }

    private func lessonCommand(_ kind: SchoolCommandKind, start: Date, plannedStart: Any? = nil,
                               includeStart: Bool = true) throws -> PendingSchoolCommand {
        let operation = UUID(), iso = ISO8601DateFormatter()
        var body: [String: Any] = ["operationId": operation.uuidString,
            "plannedEnd": iso.string(from: start.addingTimeInterval(3_000)), "timeZone": "Europe/Zurich",
            "trainingId": HubFixture.trainingID.uuidString,
            "instructorMembershipId": ConfigurationFixture.membershipID.uuidString]
        if includeStart { body["plannedStart"] = plannedStart ?? iso.string(from: start) }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        if kind == .createLesson {
            return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: kind,
                resourceVersion: 0, createdAt: now, body: data, routeResourceID: HubFixture.trainingID)
        }
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: kind,
            resourceVersion: 2, createdAt: now, body: data, resourceID: HubFixture.lessonID)
    }

    private func cancellationCommand() throws -> PendingSchoolCommand {
        let operation = UUID()
        let data = try JSONSerialization.data(withJSONObject: ["operationId": operation.uuidString,
            "reasonCode": "OTHER", "comment": ""], options: [.sortedKeys])
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .cancelLesson,
            resourceVersion: 2, createdAt: now, body: data, resourceID: HubFixture.lessonID)
    }

    private func startNowCommand() throws -> PendingSchoolCommand {
        let operation = UUID()
        let data = try JSONSerialization.data(withJSONObject: ["operationId": operation.uuidString,
            "trainingId": HubFixture.trainingID.uuidString, "meetingPoint": NSNull()], options: [.sortedKeys])
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .startLessonNow,
            resourceVersion: 0, createdAt: now, body: data, routeResourceID: HubFixture.trainingID)
    }
}

/// Horloge contrôlée : la règle est exercée à un instant fixe, sans dépendre du jour réel de la CI.
private final class RecoveryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(by seconds: TimeInterval) { lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock() }
}

/// Jeton contrôlé : une suspension précise permet de faire expirer le créneau pendant l'attente réelle du client.
@MainActor
private final class RecoveryTokenSource: AccessTokenSource {
    private(set) var calls = 0
    private(set) var invalidations = 0
    private var token = "token-1"
    private var suspendOn: Int?
    private var waiter: CheckedContinuation<Void, Never>?
    var hasPendingWait: Bool { waiter != nil }

    @discardableResult func suspendOnNextCall() -> Int {
        let next = calls + 1
        suspendOn = next
        return next
    }
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

/// Transport synthétique : /me et lectures viennent de la fixture de planification, l'écriture est comptée et le reçu
/// AP72 est servi. Aucune transaction PostgreSQL n'est prétendue.
private actor RecoveryServer: SchoolHTTPTransport {
    private let fallback = PlanningDefaultsServer()
    private let firstWriteStatus: Int?
    private var refusedFirstWrite = false
    private var recorded: [URLRequest] = []
    private var lastOperationType = "CREATE_LESSON"
    private var holdNextMeRead = false
    private var pausedMe: CheckedContinuation<Void, Never>?
    private var meReads = 0
    private var receiptReads = 0

    init(firstWriteStatus: Int? = nil) { self.firstWriteStatus = firstWriteStatus }

    func holdNextMe() { holdNextMeRead = true }
    func isHoldingMe() -> Bool { pausedMe != nil }
    func releaseMe() { pausedMe?.resume(); pausedMe = nil }
    func requestCount() -> Int { recorded.count }
    func writes() -> [URLRequest] { recorded.filter { $0.httpMethod == "POST" } }
    func firstWriteWas401() -> Bool { refusedFirstWrite }
    func meReadCount() -> Int { meReads }
    func receiptReadCount() -> Int { receiptReads }

    private func envelope(_ data: Any, status: Int, url: URL) throws -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
            "requestId": UUID().uuidString, "serverTime": ISO8601DateFormatter().string(from: Date())]),
            status: status, url: url, contentType: "application/json")
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        guard let url = request.url else { throw URLError(.badURL) }
        let parts = url.pathComponents
        if parts.last == "me" {
            meReads += 1
            if holdNextMeRead {
                holdNextMeRead = false
                await withCheckedContinuation { pausedMe = $0 }
            }
            return try await fallback.send(request)
        }
        let isLessonWrite = request.httpMethod == "POST"
            && (parts.last == "lessons" || parts.last == "move" || parts.last == "cancel")
        if isLessonWrite {
            lastOperationType = parts.last == "move" ? "MOVE_LESSON"
                : parts.last == "cancel" ? "CANCEL_LESSON" : "CREATE_LESSON"
            if firstWriteStatus == 401 && !refusedFirstWrite {
                refusedFirstWrite = true
                return SchoolHTTPResponse(data: Data("{\"code\":\"UNAUTHORIZED\",\"title\":\"Jeton expiré\"}".utf8),
                    status: 401, url: url, contentType: "application/problem+json")
            }
            return try envelope([:], status: parts.last == "lessons" ? 201 : 200, url: url)
        }
        if parts.dropLast().last == "operations" {
            receiptReads += 1
            let operationID = (parts.last ?? "").isEmpty ? UUID() : UUID(uuidString: parts.last!) ?? UUID()
            let data: [String: Any] = ["operationId": operationID.uuidString, "commandType": lastOperationType,
                "resourceType": "Lesson", "resourceId": HubFixture.lessonID.uuidString,
                "committedAt": ISO8601DateFormatter().string(from: Date()),
                "resourceVersion": lastOperationType == "CREATE_LESSON" ? 1 : 3]
            return try envelope(data, status: 200, url: url)
        }
        return try await fallback.send(request)
    }
}
