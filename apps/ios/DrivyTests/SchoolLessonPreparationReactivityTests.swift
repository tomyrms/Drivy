import Foundation
import Testing
@testable import Drivy

/// #113 : objectifs et note se saisissent pendant l’envoi de la révision précédente, sans être écrasés par sa réponse.
@MainActor struct SchoolLessonPreparationReactivityTests {
    @Test func typingDuringThePreparationSendSurvivesItsAcknowledgement() async throws {
        let hub = HubServer(), server = PreparationHoldServer(hub: hub)
        let model = workspace(server)
        await model.load()
        model.administrativeNote = "Première version"
        let saving = Task { await model.savePreparation() }
        try await HubFixture.wait { await server.holdsPut() }
        // L’envoi est en cours : la saisie reste ouverte et la fiche n’est pas retenue.
        #expect(model.isBusy && model.acceptsInput && !model.holdsScreen)
        model.administrativeNote = "Deuxième version, tapée pendant l’envoi"
        await server.releasePut()
        #expect(await saving.value)
        await model.settled()
        // La réponse de la première version ne remplace pas la seconde, et ce n’est pas un conflit.
        #expect(model.administrativeNote == "Deuxième version, tapée pendant l’envoi")
        #expect(model.preparation?.administrativeCheckNote == "Première version" && model.preparation?.version == 2)
        #expect(!model.needsReload && model.preparationChanged && model.canMutate && model.errorMessage == nil)
    }

    @Test func aRevisionUnchangedDuringItsSendIsSimplyConfirmed() async throws {
        let hub = HubServer(), server = PreparationHoldServer(hub: hub)
        await server.releasePut()
        let model = workspace(server)
        await model.load()
        model.administrativeNote = "Seule version"
        #expect(await model.savePreparation())
        await model.settled()
        #expect(model.administrativeNote == "Seule version" && !model.preparationChanged && !model.needsReload)
        #expect(model.preparation?.version == 2 && model.confirmation == "Objectifs enregistrés.")
    }

    @Test func closingDuringTheFirstSendRestoresTheNextRevisionOnTheConfirmedBase() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedSchoolLessonTextDraftStore(directory: directory, keyData: Data(repeating: 8, count: 32))
        let server = PreparationHoldServer(hub: HubServer()), first = workspace(server, textDrafts: store)
        await first.load(); first.administrativeNote = "Première version"
        let sending = Task { await first.savePreparation() }
        try await HubFixture.wait { await server.holdsPut() }
        first.administrativeNote = "Révision suivante"
        #expect(first.keepLocalDraftAndClose())
        await server.releasePut(); _ = await sending.value
        let reopened = workspace(server, textDrafts: store)
        await reopened.load()
        #expect(reopened.administrativeNote == "Révision suivante")
        #expect(reopened.preparation?.administrativeCheckNote == "Première version")
        #expect(!reopened.needsReload && reopened.canMutate)
    }

    private func workspace(_ server: PreparationHoldServer, textDrafts: (any SchoolLessonTextDraftStore)? = nil) -> SchoolLessonReportWorkspace {
        let membership = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: "https://api.example.invalid")!, tokenSource: HubToken(), transport: server)
        return SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership, lessonID: HubFixture.lessonID,
            client: client, outbox: ConfigurationOutboxStub(), textDrafts: textDrafts)
    }
}

/// Retient l’écriture des objectifs jusqu’à son relâchement, puis l’enregistre en version 2 avec son reçu.
private actor PreparationHoldServer: SchoolHTTPTransport {
    private let hub: HubServer
    private var release: CheckedContinuation<Void, Never>?
    private var released = false
    private var holding = false
    private var operation: UUID?

    init(hub: HubServer) { self.hub = hub }
    func holdsPut() -> Bool { holding }
    func releasePut() { released = true; release?.resume(); release = nil }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!, parts = url.pathComponents.map { $0.lowercased() }
        func ok(_ data: [String: Any]) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
                "requestId": UUID().uuidString.lowercased(), "serverTime": "2026-09-28T13:30:00Z"]),
                status: 200, url: url, contentType: "application/json")
        }
        if request.httpMethod == "PUT", parts.last == "preparation" {
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            operation = UUID(uuidString: body?["operationId"] as? String ?? "")
            holding = true
            if !released { await withCheckedContinuation { release = $0 } }
            holding = false
            await hub.setPreparation(note: body?["administrativeCheckNote"] as? String, version: 2)
            return try ok([:])
        }
        if parts.dropLast().last == "operations", let operation, parts.last == operation.uuidString.lowercased() {
            return try ok(["operationId": operation.uuidString, "commandType": "SAVE_PREPARATION", "resourceType": "Preparation",
                "resourceId": "70000000-0000-4000-8000-000000000001", "committedAt": "2026-09-28T13:30:00Z", "resourceVersion": 2])
        }
        return try await hub.send(request)
    }
}
