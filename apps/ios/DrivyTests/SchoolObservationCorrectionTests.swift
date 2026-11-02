import Foundation
import Testing
@testable import Drivy

/// Corrections et retraits d'observations après la leçon (#112) : écrits avant l'envoi, indépendants d'une observation à l'autre,
/// « non confirmés » après un arrêt de l'app, jamais renvoyés d'eux-mêmes, et rejoués avec la même opération.
@MainActor struct SchoolObservationCorrectionTests {
    private func scope(person: UUID? = nil, epoch: Int? = nil) -> SchoolCommandScope {
        let base = ConfigurationFixture.scope()
        return SchoolCommandScope(personID: person ?? base.personID, schoolID: base.schoolID, membershipID: base.membershipID,
            accessEpoch: epoch ?? base.accessEpoch, apiBaseURL: base.apiBaseURL)
    }

    private func observation(_ number: Int, text: String = "Priorité à droite") -> SchoolObservation {
        SchoolObservation(id: UUID(uuidString: String(format: "70000000-0000-4000-8000-%012d", number))!, schoolId: HubFixture.schoolID,
            version: 3, lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil, captureId: nil, segmentId: nil,
            pointSequence: nil, competencyId: nil, text: text, origin: "REVIEW", observedAt: nil, eventKind: nil, eventStatus: nil,
            authorMembershipId: ConfigurationFixture.membershipID)
    }

    private func loaded(_ server: CorrectionServer, _ store: SchoolObservationCorrectionMemoryStore) async -> SchoolObservationWorkspace {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let workspace = SchoolObservationWorkspace(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID, client: client,
            outbox: ConfigurationOutboxStub(), correctionStore: store)
        await workspace.load()
        return workspace
    }

    private func removal(of observation: SchoolObservation, id: UUID = UUID()) throws -> PendingSchoolCommand {
        PendingSchoolCommand(id: id, scope: scope(), kind: .removeObservation, resourceVersion: observation.version, createdAt: Date(),
            body: try JSONEncoder().encode(SchoolRemoveObservationBody(operationId: id, reason: "Doublon")),
            resourceID: observation.id, routeResourceID: HubFixture.lessonID)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(200)) }

    @Test func aRemovalIsKeptBeforeItIsSentAndLeavesOnTheAnswer() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let workspace = await loaded(server, store)
        let target = observation(1)
        await server.hold()
        // Le geste rend la main aussitôt : la demande est conservée, l'envoi se poursuit sans retenir l'écran.
        #expect(await workspace.remove(target, reason: "Doublon"))
        let kept = try #require(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).first)
        #expect(kept.kind == .removeObservation && kept.resourceID == target.id && kept.resourceVersion == target.version && kept.hasValidTarget)
        try await HubFixture.wait { await server.keys.count == 1 }
        #expect(workspace.correction(for: target.id)?.state == .sending)
        await server.release()
        try await HubFixture.wait { workspace.corrections.isEmpty }
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).isEmpty)
        #expect(await server.keys == [kept.id.uuidString])
        #expect(workspace.confirmation == "Observation retirée.")
    }

    @Test func twoObservationsAreCorrectedIndependentlyUnderLatency() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let workspace = await loaded(server, store)
        let first = observation(1), second = observation(2, text: "Régime trop haut")
        await server.hold()
        #expect(await workspace.remove(first, reason: "Doublon"))
        // La première demande attend l'école : la seconde observation reste utilisable et part elle aussi.
        #expect(workspace.canCorrect)
        #expect(await workspace.remove(second, reason: "Erreur de saisie"))
        try await HubFixture.wait { await server.keys.count == 2 }
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).count == 2)
        #expect(workspace.corrections.allSatisfy { $0.state == .sending })
        await server.release()
        try await HubFixture.wait { workspace.corrections.isEmpty }
        #expect(Set(await server.keys).count == 2)
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).isEmpty)
    }

    @Test func aSecondRequestOnTheSameObservationIsRefusedUntilTheFirstAnswers() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let workspace = await loaded(server, store)
        let target = observation(1)
        await server.hold()
        #expect(await workspace.remove(target, reason: "Doublon"))
        #expect(await workspace.remove(target, reason: "Encore") == false)
        #expect(workspace.corrections.count == 1)
        await server.release()
        try await HubFixture.wait { workspace.corrections.isEmpty }
    }

    @Test func aLostResponseStaysUncertainAndRetryReplaysTheSameOperation() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let workspace = await loaded(server, store)
        let target = observation(1)
        await server.failNext()
        #expect(await workspace.remove(target, reason: "Doublon"))
        try await HubFixture.wait { if case .uncertain = workspace.correction(for: target.id)?.state { true } else { false } }
        // Peut-être enregistrée : jamais présentée comme refusée ni comme acquise, et toujours conservée.
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).count == 1)
        workspace.retryCorrection(target.id)
        try await HubFixture.wait { workspace.corrections.isEmpty }
        let keys = await server.keys
        #expect(keys.count == 2 && keys[0] == keys[1])
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).isEmpty)
    }

    @Test func aRequestLeftByAStoppedAppComesBackUncertainAndIsNeverSentByItself() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let target = observation(1)
        let command = try removal(of: target)
        try store.save(command)
        let workspace = await loaded(server, store)
        let restored = try #require(workspace.correction(for: target.id))
        #expect(restored.id == command.id && restored.state == .uncertain(SchoolObservationCorrectionText.restored))
        await settle()
        #expect(await server.keys.isEmpty)
        // Réessayer rejoue la même opération.
        workspace.retryCorrection(target.id)
        try await HubFixture.wait { workspace.corrections.isEmpty }
        #expect(await server.keys == [command.id.uuidString])
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).isEmpty)
    }

    @Test func abandoningARestoredRequestRemovesItFromTheDevice() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let target = observation(1)
        try store.save(try removal(of: target))
        let workspace = await loaded(server, store)
        #expect(workspace.correction(for: target.id) != nil)
        await workspace.abandonCorrection(target.id)
        #expect(workspace.corrections.isEmpty)
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).isEmpty)
        #expect(await server.keys.isEmpty)
    }

    @Test func aRequestTheDeviceCannotKeepIsNotSent() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let workspace = await loaded(server, store)
        store.refusesToStore = true
        #expect(await workspace.remove(observation(1), reason: "Doublon") == false)
        #expect(workspace.corrections.isEmpty)
        #expect(workspace.errorMessage == SchoolObservationCorrectionText.unkept)
        await settle()
        #expect(await server.keys.isEmpty)
    }

    @Test func aRefusalStopsOnlyThatRequestAndSaysWhy() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let workspace = await loaded(server, store)
        let first = observation(1)
        await server.refuseNext()
        #expect(await workspace.remove(first, reason: "Doublon"))
        try await HubFixture.wait { workspace.correctionNotices[first.id] != nil }
        // Refus de l'école : la demande s'arrête, la ligne dit pourquoi, rien ne reste conservé.
        #expect(workspace.correctionNotices[first.id] == SchoolObservationFailure.conflict.errorDescription)
        #expect(workspace.correction(for: first.id) == nil)
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).isEmpty)
        // Une nouvelle demande sur la même observation efface le refus.
        #expect(await workspace.remove(first, reason: "Doublon"))
        #expect(workspace.correctionNotices[first.id] == nil)
        try await HubFixture.wait { workspace.corrections.isEmpty }
    }

    @Test func aRevokedWorkspaceShowsNothingAndAcceptsNothing() async throws {
        let server = CorrectionServer(), store = SchoolObservationCorrectionMemoryStore()
        let workspace = await loaded(server, store)
        let target = observation(1)
        await server.hold()
        #expect(await workspace.remove(target, reason: "Doublon"))
        try await HubFixture.wait { await server.keys.count == 1 }
        workspace.invalidate()
        await server.release()
        await settle()
        // Les accès ont changé : plus rien n'est affiché ni accepté, la demande déjà partie n'ouvre rien.
        #expect(workspace.accessRevoked && workspace.corrections.isEmpty && !workspace.canCorrect)
        #expect(await workspace.remove(target, reason: "Encore") == false)
    }

    @Test func theRequestedTextIsShownWithoutChangingTheIdentityOrTheVersion() throws {
        let target = observation(1, text: "Priorité à droite")
        let operation = UUID()
        let body = SchoolObservationBody(operationId: operation, draftId: nil, captureId: nil, segmentId: nil, pointSequence: nil,
            competencyId: nil, text: "Priorité à droite : regard tardif", origin: "REVIEW", observedAt: nil, eventKind: nil, eventStatus: nil)
        let command = PendingSchoolCommand(id: operation, scope: scope(), kind: .updateObservation, resourceVersion: target.version,
            createdAt: Date(), body: try JSONEncoder().encode(body), resourceID: target.id, routeResourceID: HubFixture.lessonID)
        let shown = SchoolObservationCorrection(command: command, state: .sending).projecting(target)
        #expect(shown.text == "Priorité à droite : regard tardif" && shown.id == target.id && shown.version == target.version)
        // Un retrait ne change rien à l'observation affichée : la ligne dit seulement qu'il est en cours.
        let removalShown = SchoolObservationCorrection(command: try removal(of: target), state: .sending).projecting(target)
        #expect(removalShown == target)
        // Une demande pour une autre observation ne la modifie jamais.
        #expect(SchoolObservationCorrection(command: command, state: .sending).projecting(observation(2)) == observation(2))
    }

    // MARK: File chiffrée

    @Test func twoCorrectionsOfDifferentObservationsNeverBlockEachOtherInTheOutbox() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("corrections-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = EncryptedSchoolCommandOutbox(directory: directory, keyData: Data(repeating: 9, count: 32))
        try outbox.save(try removal(of: observation(1)))
        try outbox.save(try removal(of: observation(2)))
        #expect(try outbox.pendingCommands(for: scope()).count == 2)
        // Deux demandes sur la même observation restent ordonnées.
        #expect(throws: SchoolConfigurationFailure.pendingCommand) { try outbox.save(try removal(of: observation(1))) }
    }

    @Test func theEncryptedStoreFollowsTheAccessEpochAndIsolatesAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("corrections-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolObservationCorrectionStore(directory: directory, keyData: Data(repeating: 9, count: 32))
        try store.save(try removal(of: observation(1)))
        try store.save(try removal(of: observation(2)))
        #expect(try store.commands(scope: scope(), lessonID: HubFixture.lessonID).count == 2)
        // Une affectation de plus avance l'époque : les demandes suivent la portée actuelle au lieu de rester bloquées.
        let newer = scope(epoch: ConfigurationFixture.scope().accessEpoch + 1)
        let moved = try store.commands(scope: newer, lessonID: HubFixture.lessonID)
        #expect(moved.count == 2 && moved.allSatisfy { $0.scope == newer })
        // Une autre leçon, un autre compte : rien.
        #expect(try store.commands(scope: newer, lessonID: UUID()).isEmpty)
        let other = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        #expect(try store.commands(scope: scope(person: other, epoch: newer.accessEpoch), lessonID: HubFixture.lessonID).isEmpty)
        for command in moved { try store.remove(command) }
        #expect(try store.commands(scope: newer, lessonID: HubFixture.lessonID).isEmpty)
    }
}

/// Serveur synthétique : les lectures suivent le serveur d'observations existant ; le retrait attend, échoue ou est refusé sur demande.
private actor CorrectionServer: SchoolHTTPTransport {
    private let reads = ObservationReadServer()
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var failures = 0
    private var refusals = 0
    private(set) var keys: [String] = []

    func hold() { held = true }
    func release() {
        held = false
        let values = waiters; waiters = []
        for waiter in values { waiter.resume() }
    }
    func failNext() { failures += 1 }
    func refuseNext() { refusals += 1 }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, request.httpMethod == "POST", url.lastPathComponent == "remove" else { return try await reads.send(request) }
        let key = request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""
        keys.append(key)
        if held { await withCheckedContinuation { waiters.append($0) } }
        if failures > 0 { failures -= 1; throw URLError(.notConnectedToInternet) }
        if refusals > 0 {
            refusals -= 1
            return SchoolHTTPResponse(data: Data("{\"code\":\"VERSION_CONFLICT\"}".utf8), status: 412, url: url, contentType: "application/problem+json")
        }
        let envelope: [String: Any] = ["data": ["operationId": key, "accepted": true] as [String: Any],
            "requestId": "correction-test", "serverTime": "2026-09-28T13:30:00Z"]
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: 200, url: url, contentType: "application/json")
    }
}
