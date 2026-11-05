import Foundation
import Testing
@testable import Drivy

/// Vrais workspace, client et admission ; transport/jeton synthétiques, vrai coffre temporaire.
/// Préparés avant le raccord ; exécution RED/GREEN réservée à Apple.
@MainActor struct SchoolPlanningCancellation106Tests {
    @Test func cancellationWinsAtTokenOrMeForCreationAndMove() async throws {
        for moving in [false, true] {
            for atIdentity in [false, true] {
                let harness = try Harness(moving: moving)
                defer { harness.clean() }
                try await harness.prepare()
                let draft = harness.model.draftSnapshot
                let initialReads = await harness.server.identityReads()
                if atIdentity { await harness.server.holdMe() } else { harness.token.hold = true }
                let sending = Task { await harness.model.saveBooking() }
                try await wait { if atIdentity { return await harness.server.waitingMe() }; return harness.token.waiting > 0 }
                #expect(harness.model.canCancelSend)
                harness.model.cancelSend()
                #expect(harness.model.pending == nil && harness.model.canMutate)
                #expect(harness.model.draftSnapshot == draft)
                #expect(!harness.model.writeConfirmed && harness.model.confirmedLesson == nil)
                #expect(harness.model.successMessage == nil && harness.log.value == 0)
                harness.token.hold = false; await harness.server.releaseMe()
                let result = await sending.value
                let posts = await harness.server.posts()
                let kept = try harness.outbox.pending(for: ConfigurationFixture.scope())
                #expect(!result && posts == 0 && kept == nil)
                let reads = await harness.server.identityReads()
                #expect(reads == initialReads + (atIdentity ? 1 : 0))
                #expect(harness.model.errorMessage == nil && !harness.model.isBusy)
            }
        }
    }

    @Test func refusedRemovalClosesEmissionAndOnlyRetriesRemoval() async throws {
        let harness = try Harness(); defer { harness.clean() }
        try await harness.prepare(); harness.token.hold = true
        let sending = Task { await harness.model.saveBooking() }
        try await wait { harness.token.waiting > 0 }
        let command = try #require(harness.model.pending)
        harness.outbox.failRemoval = true
        harness.model.cancelSend()
        #expect(harness.model.pending == command && harness.model.sendCancellationMessage != nil)
        #expect(harness.model.canCancelSend && !harness.model.canRetry)
        harness.token.hold = false
        let result = await sending.value
        let posts = await harness.server.posts()
        #expect(!result && posts == 0 && harness.model.sendCancellationMessage != nil)
        let retryResult = await harness.model.retry()
        #expect(!retryResult)
        harness.outbox.failRemoval = false; harness.model.cancelSend()
        let kept = try harness.outbox.pending(for: ConfigurationFixture.scope())
        #expect(kept == nil && harness.model.canMutate && harness.model.sendCancellationMessage == nil)
        #expect(harness.log.value == 0)
    }

    @Test func oldCompletionCannotClearANewGesture() async throws {
        let harness = try Harness(); defer { harness.clean() }
        try await harness.prepare(); harness.token.hold = true
        let old = Task { await harness.model.saveBooking() }
        try await wait { harness.token.waiting > 0 }
        let oldID = try #require(harness.model.pending?.id)
        harness.model.cancelSend(); harness.model.meetingPoint = "Nouvelle saisie"
        await harness.server.holdMe()
        let fresh = Task { await harness.model.saveBooking() }
        try await wait { harness.token.waiting == 2 }
        let freshCommand = try #require(harness.model.pending)
        harness.token.hold = false
        let oldResult = await old.value
        try await wait { await harness.server.waitingMe() }
        #expect(!oldResult && freshCommand.id != oldID)
        #expect(harness.model.pending == freshCommand && harness.model.isBusy && harness.model.isSendingRequest)
        #expect(harness.model.meetingPoint == "Nouvelle saisie" && harness.model.errorMessage == nil)
        harness.model.cancelSend(); await harness.server.releaseMe()
        let freshResult = await fresh.value
        #expect(!freshResult && harness.log.value == 0)
    }

    @Test func transportWinsAndConfirmationIsAnnouncedOnce() async throws {
        let harness = try Harness(); defer { harness.clean() }
        try await harness.prepare(); await harness.server.hold()
        let sending = Task { await harness.model.saveBooking() }
        try await wait { await harness.server.isHolding() }
        let command = try #require(harness.model.pending)
        #expect(!harness.model.canCancelSend)
        harness.model.cancelSend()
        #expect(harness.model.pending == command && harness.model.sendCancellationMessage != nil)
        let kept = try harness.outbox.pending(for: ConfigurationFixture.scope())
        #expect(kept == command && harness.log.value == 0)
        await harness.server.release()
        let result = await sending.value
        #expect(result && harness.model.writeConfirmed && harness.log.value == 1)
        await harness.model.verify()
        #expect(harness.log.value == 1)
    }

    @Test func lostResponseAndRestorationNeverRestoreCancellationProof() async throws {
        let harness = try Harness(receiptAvailable: false); defer { harness.clean() }
        try await harness.prepare()
        let sent = await harness.model.saveBooking()
        let command = try #require(harness.model.pending)
        #expect(!sent && !harness.model.canCancelSend && harness.log.value == 0)
        harness.token.hold = true
        let retry = Task { await harness.model.retry() }
        try await wait { harness.token.waiting > 0 }
        #expect(!harness.model.canCancelSend)
        harness.model.cancelSend()
        #expect(harness.model.pending == command)
        harness.token.hold = false
        let retried = await retry.value
        let writes = await harness.server.mutations()
        #expect(!retried && writes.count == 2)
        #expect(writes[0].httpBody == writes[1].httpBody)
        #expect(writes[0].value(forHTTPHeaderField: "Idempotency-Key") == writes[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(writes[0].value(forHTTPHeaderField: "If-Match") == writes[1].value(forHTTPHeaderField: "If-Match"))
        let restored = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: harness.model.client, outbox: harness.outbox)
        await restored.load()
        #expect(restored.pending == command && !restored.canCancelSend)
    }

    @Test func aPreparationFailureKeepsTheLiveProof() async throws {
        let harness = try Harness(); defer { harness.clean() }
        try await harness.prepare(); harness.token.failNext = true
        let result = await harness.model.saveBooking()
        #expect(!result && harness.model.canCancelSend)
        await harness.model.load()
        #expect(harness.model.canCancelSend)
        harness.model.cancelSend()
        #expect(harness.model.pending == nil && harness.log.value == 0)
    }

    @Test func cancellingALessonIsNeverALocalSendCancellation() async throws {
        let harness = try Harness(moving: true); defer { harness.clean() }
        harness.model.readsForCancellation = true
        await harness.model.load(); harness.model.cancellationReason = "OTHER"
        harness.token.hold = true
        let cancelling = Task { await harness.model.cancel() }
        try await wait { harness.token.waiting > 0 }
        #expect(!harness.model.canCancelSend && harness.model.holdsScreen)
        harness.model.cancelSend()
        #expect(harness.model.pending?.kind == .cancelLesson)
        harness.token.hold = false
        let result = await cancelling.value
        #expect(result && harness.model.confirmedCancellationLessonID == HubFixture.lessonID)
        #expect(harness.log.value == 1)
    }

    @Test func closingDoesNotCancelAndLateProofStillAnnouncesOnce() async throws {
        let harness = try Harness(); defer { harness.clean() }
        try await harness.prepare(); harness.token.hold = true
        let sending = Task { await harness.model.saveBooking() }
        try await wait { harness.token.waiting > 0 }
        let command = try #require(harness.model.pending)
        #expect(harness.model.leaveWhileRequestIsSent())
        #expect(!harness.model.canCancelSend)
        let kept = try harness.outbox.pending(for: ConfigurationFixture.scope())
        #expect(kept == command)
        harness.token.hold = false
        let result = await sending.value
        #expect(!result && harness.log.value == 1 && !harness.model.writeConfirmed)
    }

    @Test func cancellingDuringVerificationRejectsItsLateCallback() async throws {
        let harness = try Harness(); defer { harness.clean() }
        try await harness.prepare(); harness.token.failNext = true
        let sent = await harness.model.saveBooking()
        #expect(!sent)
        harness.token.hold = true
        let verifying = Task { await harness.model.verify() }
        try await wait { harness.token.waiting > 0 }
        harness.model.cancelSend()
        harness.model.meetingPoint = "Saisie après retrait"
        harness.token.hold = false
        await verifying.value
        #expect(harness.model.pending == nil && harness.model.errorMessage == nil && !harness.model.isBusy)
        #expect(harness.model.meetingPoint == "Saisie après retrait" && harness.log.value == 0)
    }

    private func wait(_ ready: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !(await ready()) {
            guard Date() < deadline else { Issue.record("Barrière de test non atteinte"); throw Cancellation106Timeout.expired }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private enum Cancellation106Timeout: Error { case expired }
@MainActor private final class Cancellation106Token: AccessTokenSource {
    var hold = false, failNext = false
    var waiting = 0
    func accessToken() async throws -> String {
        if failNext { failNext = false; throw URLError(.notConnectedToInternet) }
        if hold {
            waiting += 1; defer { waiting -= 1 }
            let deadline = Date().addingTimeInterval(5)
            while hold {
                guard Date() < deadline else { Issue.record("Échéance de la frontière contrôlée dépassée"); throw Cancellation106Timeout.expired }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        return "synthetic-token"
    }
}
@MainActor private final class Cancellation106Outbox: SchoolCommandOutbox {
    let real: EncryptedSchoolCommandOutbox
    var failRemoval = false
    init(directory: URL) { real = EncryptedSchoolCommandOutbox(directory: directory, keyData: Data(repeating: 61, count: 32)) }
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? { try real.pending(for: scope) }
    func pendingCommands(for scope: SchoolCommandScope) throws -> [PendingSchoolCommand] { try real.pendingCommands(for: scope) }
    func save(_ command: PendingSchoolCommand) throws { try real.save(command) }
    func remove(_ command: PendingSchoolCommand) throws {
        if failRemoval { throw SchoolConfigurationFailure.storage }
        try real.remove(command)
    }
}
private final class Cancellation106Log: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
@MainActor private final class Harness {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("planning-cancellation-106-" + UUID().uuidString)
    let model: SchoolPlanningWorkspace
    let token = Cancellation106Token()
    let server: Cancellation106Server
    let outbox: Cancellation106Outbox
    let log = Cancellation106Log()
    let notifications = NotificationCenter()
    private var observer: NSObjectProtocol?
    init(moving: Bool = false, receiptAvailable: Bool = true) throws {
        server = Cancellation106Server(receiptAvailable: receiptAvailable)
        outbox = Cancellation106Outbox(directory: directory)
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: token, transport: server)
        model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client,
            date: Date().addingTimeInterval(86_400), lesson: moving ? HubFixture.lesson() : nil,
            outbox: outbox, notifications: notifications)
        let log = self.log
        observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) { _ in log.increment() }
    }
    func prepare() async throws {
        await model.load()
        if model.originalLesson == nil { await model.selectLearner(HubFixture.learnerID) }
        else { model.startsAt = Date().addingTimeInterval(86_400); model.agreementConfirmed = true }
        await model.validateSlot()
        try #require(model.validBooking)
    }
    func clean() {
        token.hold = false
        if let observer { notifications.removeObserver(observer) }
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor Cancellation106Server: SchoolHTTPTransport {
    private let fallback = PlanningDefaultsServer()
    private var receiptAvailable: Bool
    private var operationID: String?
    private var operationType = "CREATE_LESSON"
    private var commandVersion = 0
    private var lessonVersion = 2
    private var lessonStatus = "PLANNED"
    private var held = false, holding = false
    private var holdIdentity = false, identityWaiting = false
    private var recorded: [URLRequest] = []
    private var postCount = 0
    private var meCount = 0

    init(receiptAvailable: Bool = true) { self.receiptAvailable = receiptAvailable }
    /// L’école a reçu la demande et n’a pas encore répondu : l’appareil attend.
    func hold() { held = true }
    func release() { held = false }
    func holdMe() { holdIdentity = true }
    func releaseMe() { holdIdentity = false }
    func waitingMe() -> Bool { identityWaiting }
    func mutations() -> [URLRequest] { recorded }
    func isHolding() -> Bool { holding }
    func posts() -> Int { postCount }
    func identityReads() -> Int { meCount }

    private func lesson() throws -> [String: Any] {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson(status: lessonStatus))) as! [String: Any]
        value["version"] = lessonVersion
        return value
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        let leaf = url.lastPathComponent.lowercased()
        if leaf == "me" { meCount += 1 }
        if leaf == "me", holdIdentity {
            identityWaiting = true
            defer { identityWaiting = false }
            let deadline = Date().addingTimeInterval(5)
            while holdIdentity {
                guard Date() < deadline else { Issue.record("Échéance de la frontière contrôlée dépassée"); throw Cancellation106Timeout.expired }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
        func ok(_ value: Any, status: Int = 200) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": ISO8601DateFormatter().string(from: Date())]), status: status, url: url, contentType: "application/json")
        }
        if request.httpMethod == "POST", ["lessons", "move", "cancel"].contains(leaf) {
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            operationID = body?["operationId"] as? String
            operationType = leaf == "cancel" ? "CANCEL_LESSON" : leaf == "move" ? "MOVE_LESSON" : "CREATE_LESSON"
            commandVersion = Int((request.value(forHTTPHeaderField: "If-Match") ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0
            lessonVersion = max(lessonVersion, commandVersion + 1)
            if leaf == "cancel" { lessonStatus = "CANCELLED" }
            postCount += 1; recorded.append(request)
            if held {
                holding = true
                let deadline = Date().addingTimeInterval(5)
                while held {
                    guard Date() < deadline else { Issue.record("Échéance de la frontière contrôlée dépassée"); throw Cancellation106Timeout.expired }
                    try await Task.sleep(for: .milliseconds(5))
                }
                holding = false
            }
            return try ok([:], status: leaf == "lessons" ? 201 : 200)
        }
        if request.httpMethod == "GET", parent == "lessons", leaf == HubFixture.lessonID.uuidString.lowercased() {
            return try ok(lesson())
        }
        if parent == "operations", let operationID {
            guard receiptAvailable else { throw URLError(.notConnectedToInternet) }
            return try ok(["operationId": operationID, "commandType": operationType, "resourceType": "Lesson",
                "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": commandVersion + 1,
                "committedAt": ISO8601DateFormatter().string(from: Date())])
        }
        return try await fallback.send(request)
    }
}
