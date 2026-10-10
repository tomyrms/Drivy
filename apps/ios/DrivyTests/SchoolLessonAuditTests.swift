import Foundation
import Testing
@testable import Drivy

/// Audit du 10 octobre 2026, lot « leçons et agenda » : une preuve d’écriture manquante n’est pas un refus,
/// un refus sans équivoque ne reste pas en file, et une leçon restée sans fin se retrouve depuis Aujourd’hui.
@MainActor struct SchoolLessonAuditTests {
    @Test func aRequestTimeoutIsNeverAFinalRefusal() {
        #expect(SchoolPlanningClient.failure(408, "REQUEST_TIMEOUT", title: "Délai dépassé") == .unavailable)
        #expect(SchoolLessonReportClient.failure(408, "REQUEST_TIMEOUT", title: "Délai dépassé") == .unavailable)
        // Une saisie que l’école ne peut pas enregistrer est un refus définitif : elle ne se rejoue pas.
        #expect(SchoolPlanningClient.failure(400, "INVALID_REQUEST").definitiveRejection)
        #expect(SchoolLessonReportClient.failure(400, "INVALID_REQUEST").permitsFreshCorrection)
        // Panne du fournisseur d’identité : à réessayer, ni refus ni session expirée.
        #expect(SchoolPlanningClient.failure(503, "IDENTITY_UNAVAILABLE") == .unavailable)
        #expect(SchoolLessonReportClient.failure(503, "IDENTITY_UNAVAILABLE") == .unavailable)
    }

    @Test func aWriteWhoseProofIsMissingStaysQueuedInsteadOfBeingDroppedAsRefused() async throws {
        let server = MissingReceiptServer(), outbox = ConfigurationOutboxStub()
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(server),
            lesson: HubFixture.lesson(), outbox: outbox)
        await model.load()
        try #require(model.errorMessage == nil && model.canMutate)
        model.cancellationReason = "OTHER"
        // L’école a répondu 200 à l’annulation puis 404 au reçu : rien ne dit que l’écriture a échoué.
        #expect(await model.cancel() == false)
        #expect(model.pending != nil && outbox.value != nil && model.confirmedCancellationLessonID == nil)
        #expect(await server.writes().count == 1)
        // La vérification explicite reste le seul chemin vers « l’école ne connaît pas cette demande ».
        #expect(!model.pendingAbsent)
        await model.verify()
        #expect(model.pendingAbsent && outbox.value != nil)
    }

    @Test func preferencesTheSchoolCannotRouteLeaveTheQueue() async throws {
        let server = MissingReceiptServer(missingDefaultsWrite: true), outbox = ConfigurationOutboxStub()
        let model = SchoolPlanningSettingsWorkspace(scope: ConfigurationFixture.scope(), client: client(server), outbox: outbox)
        await model.load()
        try #require(model.saved != nil && model.errorMessage == nil)
        model.trainingCategoryCode = "B"; model.serviceProductKey = "lesson-50"
        #expect(model.canSave)
        await model.save()
        #expect(model.pending == nil && outbox.value == nil && !model.isBusy)
        #expect(model.errorMessage?.contains("Rien n’a été modifié") == true && model.successMessage == nil)
        // La saisie reste à l’écran pour un nouvel essai.
        #expect(model.trainingCategoryCode == "B" && model.hasChanges)
    }

    @Test func onlyLessonsStartedOnAnEarlierDayAreLeftToFinish() {
        // 29 septembre 2026, minuit à Zurich.
        let dayStart = HubFixture.date("2026-09-28T22:00:00Z")
        let started = HubFixture.lesson(actualStart: "2026-09-28T12:02:00Z")
        #expect(SchoolTodayPresentation.unfinishedLessons([started], before: dayStart).map(\.id) == [started.id])
        // Jamais commencée : en attente, pas à terminer. Terminée ou annulée : un résultat existe.
        #expect(SchoolTodayPresentation.unfinishedLessons([HubFixture.lesson()], before: dayStart).isEmpty)
        let completed = HubFixture.lesson(status: "COMPLETED", actualStart: "2026-09-28T12:02:00Z")
        #expect(SchoolTodayPresentation.unfinishedLessons([completed], before: dayStart).isEmpty)
        #expect(SchoolTodayPresentation.unfinishedLessons([HubFixture.lesson(status: "CANCELLED")], before: dayStart).isEmpty)
        // Commencée aujourd’hui : la journée la montre déjà.
        let sameDay = HubFixture.date("2026-09-27T22:00:00Z")
        #expect(SchoolTodayPresentation.unfinishedLessons([started], before: sameDay).isEmpty)
    }

    private func client(_ server: MissingReceiptServer) -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }
}

/// École qui confirme une écriture puis ne retrouve pas son reçu, ou dont le service ne connaît pas
/// l’écriture des préférences : elle répond 404. Tout le reste vient de l’école synthétique du planning.
private actor MissingReceiptServer: SchoolHTTPTransport {
    private let fallback = PlanningDefaultsServer()
    private let missingDefaultsWrite: Bool
    init(missingDefaultsWrite: Bool = false) { self.missingDefaultsWrite = missingDefaultsWrite }

    func writes() async -> [URLRequest] { await fallback.writes() }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let parts = url.pathComponents
        let missing = parts.contains("operations")
            || (missingDefaultsWrite && request.httpMethod == "PUT" && parts.last == "planning-defaults")
        guard missing else { return try await fallback.send(request) }
        return SchoolHTTPResponse(data: Data("{\"code\":\"NOT_FOUND\",\"title\":\"Introuvable\"}".utf8), status: 404, url: url,
            contentType: "application/problem+json")
    }
}
