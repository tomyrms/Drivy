import Foundation
import Testing
@testable import Drivy

/// Démarrage immédiat de bout en bout, sans GPS (aucun contrôleur de trajet) : les données sont synthétiques.
@MainActor struct SchoolStartNowLaunchTests {
    private func makeLaunch(server: LessonFinishServer, learnerID: UUID? = HubFixture.learnerID)
        -> (SchoolStartNowLaunch, SchoolStartNowWorkspace) {
        let agenda = SchoolAgendaClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let form = SchoolStartNowWorkspace(scope: ConfigurationFixture.scope(), client: agenda.planningClient,
            learnerID: learnerID, outbox: ConfigurationOutboxStub())
        let launch = SchoolStartNowLaunch(form: form, agenda: agenda, workspace: SchoolWorkspace(api: agenda.reader), controller: nil)
        return (launch, form)
    }

    @Test func aDoubleTapStartsOneLessonAndOpensItInTheSameSheet() async throws {
        let server = LessonFinishServer(); await server.enableStartNow()
        let (launch, form) = makeLaunch(server: server)
        // Élève imposé par sa fiche : le récapitulatif d’emblée, sans liste.
        #expect(launch.step == .summary)
        await launch.open()
        try #require(form.canStart)
        // Sans contrôleur de trajet, aucun accord GPS n’est demandé et aucun rideau ne se montre.
        #expect(launch.gps == nil)
        launch.launch(); launch.launch()
        #expect(launch.phase == .creating && launch.launches == 1 && launch.isBusy)
        try await HubFixture.wait { launch.phase == .done }
        let posts = await server.requests().filter { $0.httpMethod == "POST" && $0.url?.lastPathComponent == "start-now" }
        #expect(posts.count == 1)
        guard case .lesson(let lesson) = launch.step else { Issue.record("La leçon démarrée s’ouvre à la place du récapitulatif"); return }
        #expect(lesson.id == HubFixture.lessonID)
        // La feuille reste ouverte sur la leçon : c’est sa fermeture qui termine le geste.
        #expect(!launch.closesSheet && !launch.finishesItself && launch.tripIssue == nil)
        #expect(!launch.isBusy)
    }

    @Test func aPlanningConflictKeepsTheSummaryAndOffersPlanningInstead() async throws {
        let server = LessonFinishServer(); await server.enableStartNowConflict()
        let (launch, form) = makeLaunch(server: server)
        await launch.open()
        try #require(form.canStart)
        launch.launch()
        try await HubFixture.wait { launch.phase == .editing && form.conflicted }
        #expect(launch.step == .summary && form.started == nil && !launch.isBusy)
        #expect(form.errorMessage == SchoolPlanningClient.startNowConflictMessage)
    }

    @Test func aSingleLearnerOpensOnTheSummaryAndTheListStaysReachable() async throws {
        let server = LessonFinishServer()
        let (launch, form) = makeLaunch(server: server, learnerID: nil)
        #expect(launch.step == .learner)
        await launch.open()
        try #require(form.learners.count == 1 && form.learnerID != nil)
        #expect(launch.step == .summary)
        launch.changeLearner()
        #expect(launch.step == .learner)
        let learnerID = try #require(form.learnerID)
        launch.choose(learnerID)
        #expect(launch.step == .summary)
    }

    @Test func aDiagnosticMeasureIsReusedOnlyWhenFreshAndPrecise() {
        #expect(SchoolCaptureDiagnosticSample.isReusable(ageSeconds: 0, accuracyMeters: 5))
        #expect(SchoolCaptureDiagnosticSample.isReusable(ageSeconds: 5, accuracyMeters: 35))
        #expect(!SchoolCaptureDiagnosticSample.isReusable(ageSeconds: 5.1, accuracyMeters: 5))
        #expect(!SchoolCaptureDiagnosticSample.isReusable(ageSeconds: 1, accuracyMeters: 35.1))
        #expect(!SchoolCaptureDiagnosticSample.isReusable(ageSeconds: -1, accuracyMeters: 5))
        #expect(!SchoolCaptureDiagnosticSample.isReusable(ageSeconds: .nan, accuracyMeters: 5))
        #expect(!SchoolCaptureDiagnosticSample.isReusable(ageSeconds: 1, accuracyMeters: .infinity))
    }

    @Test(arguments: ["", "du mar", "elo", "ÉLO", "eb", "jean luc", "zz"])
    func theLearnerIndexKeepsTheSearchRule(query: String) {
        func learner(_ name: String) -> SchoolLearner {
            SchoolLearner(id: UUID(), schoolId: HubFixture.schoolID, personId: UUID(), version: 1, displayName: name,
                contactEmail: nil, contactPhone: nil, archivedAt: nil, profileReadiness: nil, profilePhotoDocumentId: nil)
        }
        let learners = [learner("Marie Dupont"), learner("Élodie Martin"), learner("Jean-Luc Ébène")]
        #expect(SchoolLearnerIndex(learners: learners).filter(query) == SchoolLearnerSearch.filter(learners, query: query))
    }

    @Test func theCurtainNoLongerWaitsForTheWholeSequence() {
        // Le rideau attend que le symbole soit assemblé, pas la séquence entière : le reste est le temps réel du départ.
        #expect(DrivyLaunchCurtain.minimumShown < DrivyLaunchTimeline.duration)
        #expect(DrivyLaunchCurtain.minimumShown >= 1)
    }
}
