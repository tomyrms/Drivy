import Foundation
import Testing
@testable import Drivy

/// Une observation que l’école refuse ou ne connaît pas ne doit ni annoncer un ajout, ni bloquer la file
/// chiffrée (une seule demande par école et par personne).
@MainActor struct SchoolObservationRefusalTests {
    @Test func aDefinitiveRefusalOfTheFirstSendFreesTheQueueAndNamesItself() async throws {
        let outbox = ConfigurationOutboxStub(), server = ObservationRefusalServer(refusesCreation: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment(at: HubFixture.date("2026-09-28T12:11:00Z")))
        let command = try #require(outbox.value)
        let receipt = try #require(model.lastAdded)
        try await HubFixture.wait { !model.isSending }
        #expect(!model.isSending && model.pending == nil && outbox.value == nil)
        #expect(outbox.removals == [command])
        #expect(model.undoState == .refused && !model.canUndo(receipt.id))
        #expect(model.mapObservations.isEmpty && model.confirmed == 0)
        #expect(model.errorMessage?.contains("non enregistrée") == true && model.undoErrorMessage == model.errorMessage)
        // La file est libre : un nouveau signalement reste possible.
        #expect(model.acceptsSignal && model.canRecord)
        #expect(await server.creationAttempts() == 1)
        model.stop()
    }

    @Test func anUncertainFirstSendKeepsTheRequestForARetry() async throws {
        let outbox = ConfigurationOutboxStub(), server = ObservationRefusalServer(offline: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        let command = try #require(outbox.value)
        try await HubFixture.wait { !model.isSending }
        #expect(model.pending == command && outbox.value == command && model.undoState == .none)
        #expect(model.canRetry && !model.canRecord)
        model.stop()
    }

    @Test func aRetryNeverRewritesARequestRemovedFromAnotherScreen() async throws {
        let outbox = ConfigurationOutboxStub(), server = ObservationRefusalServer(offline: true)
        let model = recorder(outbox, server)
        #expect(model.markMoment())
        try await HubFixture.wait { !model.isSending }
        #expect(model.canRetry)
        let saves = outbox.saves.count
        // Abandon ou vérification réussie depuis les observations de la leçon.
        outbox.value = nil
        await model.retry()
        #expect(outbox.value == nil && outbox.saves.count == saves)
        #expect(model.pending == nil && !model.isSending && model.canRecord)
        model.stop()
    }

    @Test func aRequestUnknownToTheSchoolCanBeAbandonedFromTheObservations() async throws {
        let outbox = ConfigurationOutboxStub(), server = ObservationRefusalServer(refusesCreation: true)
        let command = try pendingMarker()
        outbox.value = command
        let workspace = SchoolObservationWorkspace(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client(server), outbox: outbox)
        await workspace.load()
        #expect(workspace.pending == command && workspace.canRetry && !workspace.pendingAbsent)
        // Sans réponse de l’école, rien ne s’abandonne.
        await workspace.abandonPending()
        #expect(outbox.value == command)
        await workspace.verifyPending()
        #expect(workspace.pendingAbsent && workspace.pending == command && !workspace.isBusy && !workspace.accessRevoked)
        await workspace.abandonPending()
        #expect(outbox.value == nil && workspace.pending == nil && !workspace.pendingAbsent)
        #expect(outbox.removals == [command] && workspace.canAdd)
        #expect(await server.creationAttempts() == 0)
    }

    private func pendingMarker() throws -> PendingSchoolCommand {
        let operation = UUID()
        let body = SchoolObservationBody(operationId: operation, draftId: nil, captureId: nil, segmentId: nil,
            pointSequence: nil, competencyId: nil, text: "Moment à revoir", origin: "LIVE",
            observedAt: "2026-09-28T12:11:00.000Z", eventKind: "MARKER", eventStatus: nil)
        return PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .createObservation,
            resourceVersion: 0, createdAt: HubFixture.date("2026-09-28T12:11:00Z"), body: try JSONEncoder().encode(body),
            routeResourceID: HubFixture.lessonID)
    }
    private func recorder(_ outbox: ConfigurationOutboxStub, _ server: ObservationRefusalServer) -> SchoolLiveObservationRecorder {
        SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client(server), outbox: outbox)
    }
    private func client(_ server: ObservationRefusalServer) -> SchoolObservationClient {
        SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }
}

/// École qui ne connaît aucune opération d’observation et refuse, sur demande, toute création.
private actor ObservationRefusalServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private let offline: Bool
    private let refusesCreation: Bool
    private var creations = 0

    init(offline: Bool = false, refusesCreation: Bool = false) {
        self.offline = offline; self.refusesCreation = refusesCreation
    }
    func creationAttempts() -> Int { creations }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        if offline { throw URLError(.notConnectedToInternet) }
        let url = request.url!
        func failure(_ code: String, status: Int) -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\"}".utf8), status: status, url: url,
                contentType: "application/problem+json")
        }
        if url.pathComponents.dropLast().last == "operations" { return failure("NOT_FOUND", status: 404) }
        if url.lastPathComponent == "geo-observations" {
            if request.httpMethod == "POST" {
                creations += 1
                if refusesCreation { return failure("LESSON_STATE_CONFLICT", status: 409) }
                throw URLError(.networkConnectionLost)
            }
            let page: [String: Any] = ["items": [Any](), "nextCursor": NSNull()]
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": page,
                "requestId": UUID().uuidString, "serverTime": "2026-09-28T12:15:00Z"]),
                status: 200, url: url, contentType: "application/json")
        }
        return try await fallback.send(request)
    }
}
