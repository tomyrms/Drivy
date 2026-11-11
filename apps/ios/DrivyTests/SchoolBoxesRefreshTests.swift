import Foundation
import Testing
@testable import Drivy

/// Boîtes de l'onglet Élèves (#447, #449) : liste complète au-delà de huit lignes, relecture par contexte, panne locale, réponses tardives.
/// Les lectures du serveur sont retenues puis libérées à la main ; aucun réseau.
@MainActor struct SchoolBoxesRefreshTests {
    /// Une lecture retenue : la réponse n'arrive que quand le test la libère.
    private actor Gate {
        private var continuation: CheckedContinuation<[Int], Error>?
        private var released: Result<[Int], Error>?
        func wait() async throws -> [Int] {
            if let released { return try released.get() }
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func release(_ result: Result<[Int], Error>) {
            if let continuation { continuation.resume(with: result); self.continuation = nil } else { released = result }
        }
    }

    private func reading() -> SchoolBoxReading<Int> { SchoolBoxReading<Int>() }

    // MARK: Liste complète

    @Test func zeroToEightRowsNeverOfferAnExpansion() {
        for count in 0...8 {
            let items = Array(0..<count)
            #expect(!SchoolBoxExpansion.canExpand(count))
            #expect(SchoolBoxExpansion.visible(items, expanded: false).count == count)
            #expect(SchoolBoxExpansion.hiddenCount(count, expanded: false) == 0)
        }
    }

    @Test func nineAndTwentyRowsAreAllReachableOnceExpandedInOrder() {
        for count in [9, 20] {
            let items = Array(0..<count)
            #expect(SchoolBoxExpansion.canExpand(count))
            #expect(Array(SchoolBoxExpansion.visible(items, expanded: false)) == Array(0..<8))
            #expect(SchoolBoxExpansion.hiddenCount(count, expanded: false) == count - 8)
            #expect(Array(SchoolBoxExpansion.visible(items, expanded: true)) == items)
            #expect(SchoolBoxExpansion.hiddenCount(count, expanded: true) == 0)
        }
    }

    // MARK: Relecture, panne et contexte

    @Test func aReloadShowsAdditionsAndRemovalsMadeElsewhere() async {
        let box = reading()
        await box.load(context: "a", failure: "x") { [1, 2, 3] }
        #expect(box.items == [1, 2, 3])
        await box.load(context: "a", failure: "x") { [2, 3, 4, 5] }
        #expect(box.items == [2, 3, 4, 5] && box.errorMessage == nil)
        await box.load(context: "a", failure: "x") { [] }
        #expect(box.items.isEmpty && box.errorMessage == nil)
    }

    @Test func aFailureKeepsThePreviousReadingAndSaysSoUntilItWorksAgain() async {
        let box = reading()
        await box.load(context: "a", failure: "Panne") { [1, 2] }
        await box.load(context: "a", failure: "Panne") { throw SchoolPlanningFailure.unavailable }
        #expect(box.items == [1, 2])
        #expect(box.errorMessage == "Panne")
        await box.load(context: "a", failure: "Panne") { [1, 2, 3] }
        #expect(box.items == [1, 2, 3] && box.errorMessage == nil)
    }

    @Test func oneSectionFailingDoesNotStopTheOtherFromRefreshing() async {
        let requests = reading(), exams = reading()
        await requests.load(context: "a", failure: "R") { [1] }
        await exams.load(context: "a", failure: "E") { [9] }
        async let first: Void = requests.load(context: "a", failure: "R") { throw SchoolPlanningFailure.unavailable }
        async let second: Void = exams.load(context: "a", failure: "E") { [9, 10] }
        _ = await (first, second)
        #expect(requests.items == [1] && requests.errorMessage == "R")
        #expect(exams.items == [9, 10] && exams.errorMessage == nil)
    }

    @Test func lostAccessPurgesWhatWasReadBeforeInsteadOfKeepingIt() async {
        for failure in [SchoolPlanningFailure.forbidden, .notFound, .unauthorized] {
            let box = reading()
            await box.load(context: "a", failure: "Accès") { [1, 2] }
            await box.load(context: "a", failure: "Accès") { throw failure }
            #expect(box.items.isEmpty)
            #expect(box.errorMessage == "Accès")
        }
    }

    @Test func aNewContextDropsTheOldReadingBeforeItsOwnAnswerAndWithoutAClient() async {
        let box = reading()
        await box.load(context: "école A", failure: "x") { [1, 2] }
        await box.load(context: "école B", failure: "x", fetch: nil)
        #expect(box.items.isEmpty && box.errorMessage == nil)
    }

    @Test func aLateAnswerFromAnOlderContextIsIgnored() async {
        let box = reading()
        let slow = Gate()
        let late = Task { await box.load(context: "compte A", failure: "x") { try await slow.wait() } }
        while !box.isLoading { await Task.yield() }
        await box.load(context: "compte B", failure: "x") { [7] }
        #expect(box.items == [7])
        await slow.release(.success([1, 2, 3]))
        await late.value
        #expect(box.items == [7] && box.errorMessage == nil)
    }

    @Test func aLateFailureFromAnOlderContextDoesNotMarkTheNewOneAsFailed() async {
        let box = reading()
        let slow = Gate()
        let late = Task { await box.load(context: "école A", failure: "x") { try await slow.wait() } }
        while !box.isLoading { await Task.yield() }
        await box.load(context: "école B", failure: "x") { [7] }
        await slow.release(.failure(SchoolPlanningFailure.forbidden))
        await late.value
        #expect(box.items == [7] && box.errorMessage == nil)
    }

    @Test func anOlderAnswerArrivingAfterANewerReloadOfTheSameContextIsIgnored() async {
        let box = reading()
        let slow = Gate()
        let older = Task { await box.load(context: "a", failure: "x") { try await slow.wait() } }
        while !box.isLoading { await Task.yield() }
        await box.load(context: "a", failure: "x") { [5, 6] }
        await slow.release(.success([1]))
        await older.value
        #expect(box.items == [5, 6])
    }

    @Test func aConfirmedTreatmentAsksForOneReadingNotAPoll() {
        let signal = SchoolBoxesSignal()
        let before = signal.revision
        signal.settled()
        #expect(signal.revision == before + 1)
    }

    // MARK: Vrais clients derrière un transport retenu

    /// Serveur synthétique : répond par suffixe de chemin, ou retient la prochaine requête jusqu'à ce que le test la libère.
    private actor BoxServer: SchoolHTTPTransport {
        private var held: [CheckedContinuation<(Int, Data), Never>] = []
        private var holdSuffix: String?
        private var answers: [String: (Int, Data)] = [:]
        func answer(_ suffix: String, status: Int, body: Data) { answers[suffix] = (status, body) }
        /// Retient la prochaine requête dont le chemin finit par `suffix` ; les suivantes passent.
        func hold(_ suffix: String) { holdSuffix = suffix }
        func heldCount() -> Int { held.count }
        func release(status: Int, body: Data) {
            let waiting = held
            held = []
            for next in waiting { next.resume(returning: (status, body)) }
        }
        func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
            let url = request.url!
            let result: (Int, Data)
            if let suffix = holdSuffix, url.path.hasSuffix(suffix) {
                holdSuffix = nil
                result = await withCheckedContinuation { held.append($0) }
            } else {
                result = answers.first(where: { url.path.hasSuffix($0.key) })?.value ?? (404, Data())
            }
            return SchoolHTTPResponse(data: result.1, status: result.0, url: url, contentType: "application/json")
        }
    }

    private let base = URL(string: "https://school.example")!
    private let schoolA = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let schoolB = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let requestA = UUID(uuidString: "aaaa0000-0000-4000-8000-000000000001")!
    private let requestB = UUID(uuidString: "bbbb0000-0000-4000-8000-000000000002")!
    private let examA = UUID(uuidString: "eeee0000-0000-4000-8000-000000000001")!

    private func envelope(_ data: String) -> Data {
        Data("{\"data\":\(data),\"requestId\":\"req-1\",\"serverTime\":\"2030-03-01T08:00:00.000Z\"}".utf8)
    }

    private func inboxBody(request: UUID, learner: String) -> Data {
        envelope("""
        {"items":[{"request":{"id":"\(request.uuidString.lowercased())","lessonId":"11111111-1111-4111-8111-111111111111","kind":"RESCHEDULE","status":"PENDING",
         "note":"Plutôt jeudi","mine":false,"late":false,"deadlineAt":null,"cancellationHours":24,"policyVersionId":null,"resolvedAt":null,
         "resolutionNote":null,"version":1,"createdAt":"2030-03-01T08:00:00.000Z"},
         "lesson":{"id":"11111111-1111-4111-8111-111111111111","plannedStart":"2030-03-04T09:00:00.000Z","plannedEnd":"2030-03-04T09:50:00.000Z",
         "timeZone":"Europe/Zurich","version":2,"instructorMembershipId":"33333333-3333-4333-8333-333333333333",
         "learnerId":"44444444-4444-4444-8444-444444444444","learnerDisplayName":"\(learner)"}}]}
        """)
    }

    private func examsBody(exam: UUID, learner: String) -> Data {
        envelope("""
        {"filter":"PENDING_RESULT","items":[{"exam":{"id":"\(exam.uuidString.lowercased())","trainingId":"55555555-5555-4555-8555-555555555555","kind":"PRACTICAL",
         "categoryCode":"B","status":"SCHEDULED","startsAt":"2030-03-04T09:00:00.000Z","timeZone":"Europe/Zurich","location":"Lausanne","escort":null,
         "resultNote":"","resultRecordedAt":null,"postponedToExamId":null,"attempt":1,"needsResult":true,"version":1,
         "createdAt":"2030-03-01T08:00:00.000Z"},"learnerId":"44444444-4444-4444-8444-444444444444","learnerDisplayName":"\(learner)"}]}
        """)
    }

    @Test func theRealInboxClientPurgesTheBoxOn401And403And404ButKeepsItOnAnOutage() async {
        for (status, purges) in [(401, true), (403, true), (404, true), (503, false)] {
            let server = BoxServer()
            let client = SchoolLessonChangeClient(baseURL: base, tokenSource: HubToken(), transport: server)
            await server.answer("lesson-change-requests", status: 200, body: inboxBody(request: requestA, learner: "Camille"))
            let box = SchoolLessonRequestInboxModel()
            await box.load(client: client, schoolID: schoolA, context: "a")
            #expect(box.items.map(\.id) == [requestA], "lecture initiale, statut \(status)")
            await server.answer("lesson-change-requests", status: status, body: Data())
            await box.load(client: client, schoolID: schoolA, context: "a")
            #expect(box.items.isEmpty == purges, "statut \(status)")
            #expect(box.errorMessage != nil, "statut \(status)")
        }
    }

    @Test func theRealExamClientPurgesTheBoxWhenAccessIsRefused() async {
        let server = BoxServer()
        let client = SchoolExamClient(baseURL: base, tokenSource: HubToken(), transport: server)
        await server.answer("exams", status: 200, body: examsBody(exam: examA, learner: "Camille"))
        let box = SchoolPendingExamsModel()
        await box.load(client: client, schoolID: schoolA, context: "a")
        #expect(box.items.map(\.id) == [examA])
        await server.answer("exams", status: 403, body: Data())
        await box.load(client: client, schoolID: schoolA, context: "a")
        #expect(box.items.isEmpty && box.errorMessage != nil)
    }

    @Test func aHeldInboxAnswerArrivingAfterASchoolChangeNeverReplacesTheNewSchool() async {
        let server = BoxServer()
        let client = SchoolLessonChangeClient(baseURL: base, tokenSource: HubToken(), transport: server)
        let box = SchoolLessonRequestInboxModel()
        await server.hold("lesson-change-requests")
        let late = Task { await box.load(client: client, schoolID: schoolA, context: "école A") }
        while await server.heldCount() == 0 { await Task.yield() }
        await server.answer("lesson-change-requests", status: 200, body: inboxBody(request: requestB, learner: "École B"))
        await box.load(client: client, schoolID: schoolB, context: "école B")
        #expect(box.items.map(\.id) == [requestB])
        await server.release(status: 200, body: inboxBody(request: requestA, learner: "École A"))
        await late.value
        #expect(box.items.map(\.id) == [requestB] && box.errorMessage == nil)
    }

    @Test func aHeldExamAnswerArrivingAfterTheRightsAreLostLeavesTheBoxEmpty() async {
        let server = BoxServer()
        let client = SchoolExamClient(baseURL: base, tokenSource: HubToken(), transport: server)
        let box = SchoolPendingExamsModel()
        await server.hold("exams")
        let late = Task { await box.load(client: client, schoolID: schoolA, context: "gère les examens") }
        while await server.heldCount() == 0 { await Task.yield() }
        // Les droits ont changé : plus de client pour ce contexte.
        await box.load(client: nil, schoolID: schoolA, context: "ne gère plus les examens")
        await server.release(status: 200, body: examsBody(exam: examA, learner: "Camille"))
        await late.value
        #expect(box.items.isEmpty && box.errorMessage == nil)
    }

    // MARK: Cible d'une boîte : acquittée à la résolution, purgée au changement de contexte

    private final class UnreadAPI: SchoolAPI {
        func me() async throws -> SchoolPerson { throw SchoolAPIError.invalidResponse }
        func school(id: UUID) async throws -> SchoolDetails { throw SchoolAPIError.invalidResponse }
        func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> { throw SchoolAPIError.invalidResponse }
        func incompleteLearners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> { throw SchoolAPIError.invalidResponse }
        func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner { throw SchoolAPIError.invalidResponse }
        func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining> { throw SchoolAPIError.invalidResponse }
        func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining { throw SchoolAPIError.invalidResponse }
        func ownLearners(schoolID: UUID) async throws -> SchoolPage<SchoolLearner> { throw SchoolAPIError.invalidResponse }
        func learnersToComplete(schoolID: UUID) async throws -> [SchoolLearner]? { nil }
        func selfProfile() async throws -> SchoolSelfProfile { throw SchoolAPIError.invalidResponse }
        func saveSelfProfile(_ edit: SchoolSelfProfileEdit, version: Int) async throws -> SchoolSelfProfile { throw SchoolAPIError.invalidResponse }
        func setSelfPhoto(_ jpeg: Data?, version: Int) async throws -> SchoolSelfProfile { throw SchoolAPIError.invalidResponse }
        func personPhoto(personID: UUID) async throws -> Data? { nil }
    }

    private let learnerOne = UUID(uuidString: "11110000-0000-4000-8000-000000000001")!
    private let learnerTwo = UUID(uuidString: "22220000-0000-4000-8000-000000000002")!
    private let trainingOne = UUID(uuidString: "33330000-0000-4000-8000-000000000003")!
    private let examOne = UUID(uuidString: "44440000-0000-4000-8000-000000000004")!
    private let examTwo = UUID(uuidString: "55550000-0000-4000-8000-000000000005")!

    private func examTarget(_ exam: UUID, learner: UUID? = nil) -> SchoolBoxTarget {
        SchoolBoxTarget(learnerID: learner ?? learnerOne, trainingID: trainingOne, examID: exam)
    }

    @Test func aBoxTargetStaysUntilItIsResolvedAndOnlyTheSameTargetResolvesIt() {
        let workspace = SchoolWorkspace(api: UnreadAPI())
        workspace.open(examTarget(examOne))
        #expect(workspace.boxTarget == examTarget(examOne) && workspace.selectedLearnerID == learnerOne)
        // Une action tardive portant une autre cible, ou un autre élève, ne l'acquitte pas.
        workspace.resolveBoxTarget(examTarget(examTwo))
        workspace.resolveBoxTarget(examTarget(examOne, learner: learnerTwo))
        #expect(workspace.boxTarget == examTarget(examOne))
        workspace.resolveBoxTarget(examTarget(examOne), message: "Cet examen n’est plus dans la liste de la formation.")
        #expect(workspace.boxTarget == nil && workspace.boxTargetMessage != nil)
        // La cible suivante efface le message précédent.
        workspace.open(examTarget(examTwo))
        #expect(workspace.boxTargetMessage == nil && workspace.boxTarget == examTarget(examTwo))
    }

    @Test func aBoxTargetIsPurgedWhenTheLearnerChangesOrTheWorkspaceIsReset() {
        let workspace = SchoolWorkspace(api: UnreadAPI())
        workspace.open(examTarget(examOne))
        workspace.selectLearner(learnerTwo)
        #expect(workspace.boxTarget == nil, "un autre élève ne reçoit pas la cible du précédent")
        workspace.open(examTarget(examOne))
        workspace.selectLearner(nil)
        #expect(workspace.boxTarget == nil && workspace.boxTargetMessage == nil)
        workspace.open(examTarget(examTwo))
        workspace.resolveBoxTarget(examTarget(examTwo), message: "perdu")
        workspace.open(examTarget(examOne))
        workspace.reset()
        #expect(workspace.boxTarget == nil && workspace.boxTargetMessage == nil && workspace.selectedLearnerID == nil)
        // Après la remise à zéro, la réponse tardive de l'ancienne section n'a plus rien à acquitter.
        workspace.resolveBoxTarget(examTarget(examOne), message: "tardif")
        #expect(workspace.boxTargetMessage == nil)
    }
}
