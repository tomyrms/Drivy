import Foundation
import Testing
@testable import Drivy

/// Gestes de cours conservés sur l'appareil (#126, #128 à #130) : écrits avant l'envoi, rendus « non confirmés » après un arrêt de
/// l'app, jamais renvoyés d'eux-mêmes, et rejoués avec la même opération.
@MainActor struct SchoolCourseIntentPersistenceTests {
    private let schoolID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let seriesID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let occurrence = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    private let personID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    private let membershipID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!

    private func scope(person: UUID? = nil, epoch: Int = 1) -> SchoolCommandScope {
        SchoolCommandScope(personID: person ?? personID, schoolID: schoolID, membershipID: membershipID, accessEpoch: epoch,
            apiBaseURL: "https://school.example.test")
    }

    private func workspace(_ server: CourseSheetServer, store: SchoolCourseIntentMemoryStore) async -> SchoolCourseAttendanceWorkspace {
        let client = SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: server)
        let model = SchoolCourseAttendanceWorkspace(schoolID: schoolID, seriesID: seriesID, timeZone: "Europe/Zurich", client: client,
            persistence: SchoolCourseIntentPersistence(store: store, scope: scope()))
        await model.load()
        return model
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Laisse à un envoi qui ne devrait pas avoir lieu le temps de se produire.
    private func settle() async { try? await Task.sleep(for: .milliseconds(200)) }

    private func present(_ model: SchoolCourseAttendanceWorkspace, _ learner: UUID = CourseSheetServer.first) {
        model.submit(.attendance(enrollmentID: learner, occurrenceID: occurrence, status: .present, expectedVersion: nil), learnerName: "Alex")
    }

    // MARK: Feuille du cours (#128 à #130)

    @Test func aGestureIsKeptBeforeItIsSentAndLeavesOnTheAnswer() async throws {
        let server = CourseSheetServer(), store = SchoolCourseIntentMemoryStore()
        let model = await workspace(server, store: store)
        await server.hold(CourseSheetServer.first)
        present(model)
        // Écrit dans le coffre avant la réponse de l'école.
        let kept = try #require(try store.commands(scope: scope(), seriesID: seriesID).first)
        #expect(kept.kind == .courseSheetIntent && kept.hasValidTarget && kept.resourceID == CourseSheetServer.first)
        #expect(model.isSending)
        await server.release()
        await eventually { model.lanes.isEmpty }
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
    }

    @Test func aGestureLeftByAStoppedAppComesBackUnconfirmedAndIsNeverSentByItself() async throws {
        let store = SchoolCourseIntentMemoryStore()
        let stopped = CourseSheetServer()
        let first = await workspace(stopped, store: store)
        await stopped.hold(CourseSheetServer.first)
        present(first)
        let operation = try #require(try store.commands(scope: scope(), seriesID: seriesID).first).id

        // L'app redémarre : une nouvelle feuille relit le coffre.
        let fresh = CourseSheetServer()
        let reopened = await workspace(fresh, store: store)
        #expect(reopened.hasUnconfirmed && !reopened.isSending)
        let waiting = try #require(reopened.rows.first { $0.enrollmentId == CourseSheetServer.first })
        let pending = try #require(reopened.unconfirmed(waiting))
        #expect(pending.intent.id == operation && pending.message == SchoolCourseIntentPersistence.restoredMessage)
        // La présence choisie reste visible, jamais présentée comme enregistrée.
        #expect(reopened.displayedStatus(waiting, occurrenceID: occurrence) == .present)
        #expect(waiting.mark(occurrence)?.status == nil)
        await settle()
        #expect(await fresh.keys.isEmpty)

        // Réessayer rejoue la même opération : l'école ne l'enregistre pas deux fois.
        reopened.retry(CourseSheetServer.first)
        await eventually { reopened.lanes.isEmpty }
        #expect(await fresh.keys == [operation.uuidString])
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
        await stopped.release()
    }

    @Test func abandoningARestoredGestureRemovesItFromTheDevice() async throws {
        let store = SchoolCourseIntentMemoryStore()
        let stopped = CourseSheetServer()
        let first = await workspace(stopped, store: store)
        await stopped.hold(CourseSheetServer.first)
        present(first)
        let reopened = await workspace(CourseSheetServer(), store: store)
        #expect(reopened.hasUnconfirmed)
        reopened.abandon(CourseSheetServer.first)
        await eventually { reopened.lanes.isEmpty }
        #expect(!reopened.hasUnconfirmed)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
        await stopped.release()
    }

    @Test func aGestureTheDeviceCannotKeepIsNotSentAndSaysSo() async throws {
        let server = CourseSheetServer(), store = SchoolCourseIntentMemoryStore()
        let model = await workspace(server, store: store)
        store.refusesToStore = true
        present(model)
        #expect(model.lanes.isEmpty && !model.isSending)
        #expect(model.notices[CourseSheetServer.first] == SchoolCourseIntentPersistence.unkeptMessage)
        await settle()
        #expect(await server.keys.isEmpty)
    }

    @Test func aRestoredGestureForAnEnrollmentNoLongerOnTheSheetIsDropped() async throws {
        let server = CourseSheetServer(), store = SchoolCourseIntentMemoryStore()
        let ghost = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let intent = SchoolCourseSheetIntent(id: UUID(), action: .attendance(enrollmentID: ghost, occurrenceID: occurrence,
            status: .absent, expectedVersion: nil), learnerName: "Parti")
        try store.replace(nil, with: SchoolCourseSheetRecord(intent).command(scope: scope(), seriesID: seriesID, createdAt: Date()))
        let model = await workspace(server, store: store)
        #expect(model.lanes.isEmpty && !model.hasUnconfirmed)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
    }

    @Test func aGestureOfAnotherAccountOrCourseIsNeverRestored() async throws {
        let server = CourseSheetServer(), store = SchoolCourseIntentMemoryStore()
        let intent = SchoolCourseSheetIntent(id: UUID(), action: .validate(enrollmentID: CourseSheetServer.first), learnerName: "Alex")
        let other = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        try store.replace(nil, with: SchoolCourseSheetRecord(intent).command(scope: scope(person: other), seriesID: seriesID, createdAt: Date()))
        let anotherCourse = SchoolCourseSheetIntent(id: UUID(), action: .validate(enrollmentID: CourseSheetServer.second), learnerName: "Zoé")
        try store.replace(nil, with: SchoolCourseSheetRecord(anotherCourse).command(scope: scope(), seriesID: other, createdAt: Date()))
        let model = await workspace(server, store: store)
        #expect(model.lanes.isEmpty && !model.hasUnconfirmed)
    }

    @Test func aPaymentAndAValidationKeepTheirOwnTarget() throws {
        let enrollment = CourseSheetServer.first
        let payment = SchoolCourseSheetIntent(id: UUID(), action: .payment(enrollmentID: enrollment, amountCents: 8000), learnerName: "Alex")
        let record = try JSONDecoder().decode(SchoolCourseSheetRecord.self, from: JSONEncoder().encode(SchoolCourseSheetRecord(payment)))
        #expect(record.action == payment.action && record.operationId == payment.id)
        let void = SchoolCourseSheetIntent(id: UUID(), action: .voidPayment(enrollmentID: enrollment, paymentID: UUID(), reason: "Erreur de saisie"), learnerName: "Alex")
        let voided = try JSONDecoder().decode(SchoolCourseSheetRecord.self, from: JSONEncoder().encode(SchoolCourseSheetRecord(void)))
        #expect(voided.action == void.action)
        // Un archive incomplet est écarté, jamais deviné.
        var broken = SchoolCourseSheetRecord(payment)
        broken.amountCents = nil
        #expect(broken.action == nil)
    }

    // MARK: Demande de l'élève (#126)

    @Test func aLearnerRequestIsKeptBeforeItLeavesAndComesBackUnconfirmed() async throws {
        let store = SchoolCourseIntentMemoryStore()
        let persistence = SchoolCourseIntentPersistence(store: store, scope: scope())
        let client = SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: CourseOfflineTransport())
        let model = SchoolCourseLearnerWorkspace(schoolID: schoolID, seriesID: seriesID, timeZone: "Europe/Zurich", client: client, persistence: persistence)
        model.submit(.enroll)
        let kept = try #require(try store.commands(scope: scope(), seriesID: seriesID).first)
        #expect(kept.kind == .courseLearnerIntent && kept.hasValidTarget)
        let sent = try #require(model.pending)
        #expect(sent.operation == kept.id)
        // Hors ligne : la demande reste à reprendre, jamais présentée comme acquise ni refusée.
        await eventually { if case .uncertain = model.pending?.state { true } else { false } }
        #expect(model.pending?.operation == kept.id)

        // Après un arrêt de l'app : une nouvelle fiche retrouve la même demande, à reprendre.
        let reopened = SchoolCourseLearnerWorkspace(schoolID: schoolID, seriesID: seriesID, timeZone: "Europe/Zurich", client: client, persistence: persistence)
        reopened.restoreKeptRequest()
        let restored = try #require(reopened.pending)
        #expect(restored.operation == kept.id && restored.action == .enroll)
        #expect(restored.state == .uncertain(SchoolCourseIntentPersistence.restoredMessage))

        // Abandonner la retire du coffre.
        await reopened.abandonPending()
        #expect(reopened.pending == nil)
        #expect(try store.commands(scope: scope(), seriesID: seriesID).isEmpty)
    }

    @Test func aLearnerRequestTheDeviceCannotKeepIsNotSent() async throws {
        let store = SchoolCourseIntentMemoryStore()
        store.refusesToStore = true
        let client = SchoolCourseClient(baseURL: URL(string: "https://school.example.test")!, tokenSource: HubToken(), transport: CourseOfflineTransport())
        let model = SchoolCourseLearnerWorkspace(schoolID: schoolID, seriesID: seriesID, timeZone: "Europe/Zurich", client: client,
            persistence: SchoolCourseIntentPersistence(store: store, scope: scope()))
        model.submit(.joinWaitlist)
        #expect(model.pending == nil && !model.isBusy)
        #expect(model.errorMessage == SchoolCourseIntentPersistence.unkeptMessage)
    }

    @Test func everyLearnerActionSurvivesTheRoundTrip() throws {
        let offer = UUID(), enrollment = UUID()
        let actions: [SchoolCourseLearnerAction] = [.enroll, .joinWaitlist, .leaveWaitlist, .accept(offerID: offer), .decline(offerID: offer),
            .cancel(enrollmentID: enrollment, version: 3)]
        for action in actions {
            let record = SchoolCourseLearnerRecord(action: action, operation: UUID())
            let decoded = try JSONDecoder().decode(SchoolCourseLearnerRecord.self, from: JSONEncoder().encode(record))
            #expect(decoded.action == action)
        }
        // Une annulation sans version n'est jamais rejouée au hasard.
        var broken = SchoolCourseLearnerRecord(action: .cancel(enrollmentID: enrollment, version: 3), operation: UUID())
        broken.version = nil
        #expect(broken.action == nil)
    }

    // MARK: Coffre chiffré

    @Test func theEncryptedStoreKeepsCourseGesturesApartAndFollowsTheAccessEpoch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("course-intents-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolCourseIntentStore(directory: directory, keyData: Data(repeating: 7, count: 32))
        let intent = SchoolCourseSheetIntent(id: UUID(), action: .validate(enrollmentID: CourseSheetServer.first), learnerName: "Alex")
        let command = try SchoolCourseSheetRecord(intent).command(scope: scope(epoch: 1), seriesID: seriesID, createdAt: Date())
        try store.replace(nil, with: command)
        // Deux gestes de cours ne se bloquent jamais entre eux.
        let second = SchoolCourseSheetIntent(id: UUID(), action: .validate(enrollmentID: CourseSheetServer.second), learnerName: "Zoé")
        try store.replace(nil, with: SchoolCourseSheetRecord(second).command(scope: scope(epoch: 1), seriesID: seriesID, createdAt: Date()))
        #expect(try store.commands(scope: scope(epoch: 1), seriesID: seriesID).count == 2)
        // Une affectation de plus avance l'époque : les gestes suivent la portée actuelle au lieu de rester bloqués.
        let moved = try store.commands(scope: scope(epoch: 2), seriesID: seriesID)
        #expect(moved.count == 2 && moved.allSatisfy { $0.scope.accessEpoch == 2 })
        // Un autre compte ne voit rien.
        let other = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        #expect(try store.commands(scope: scope(person: other, epoch: 2)).isEmpty)
        for command in moved { try store.remove(command) }
        #expect(try store.commands(scope: scope(epoch: 2)).isEmpty)
    }
}

/// Aucune réponse de l'école : la panne laisse la demande « non confirmée ».
private struct CourseOfflineTransport: SchoolHTTPTransport {
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse { throw URLError(.notConnectedToInternet) }
}
