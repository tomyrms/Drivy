import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolTrainingRefreshTests {
    @Test func periodsUseTheLessonCalendarAcrossTheNewYear() throws {
        let lesson = try HistoryServer.lesson(id: HubFixture.lessonID, start: "2025-12-31T23:30:00Z", end: "2026-01-01T00:20:00Z")
        #expect(SchoolLessonPeriod(month: 1, year: 2026).includes(lesson))
        #expect(SchoolLessonPeriod(month: 1).includes(lesson))
        #expect(SchoolLessonPeriod(year: 2026).includes(lesson))
        #expect(!SchoolLessonPeriod(month: 12).includes(lesson))
        #expect(!SchoolLessonPeriod(year: 2025).includes(lesson))
        #expect(SchoolLessonPeriod().includes(lesson))
    }

    @Test func periodHistoryIncludesOlderPagesAndRemainsCompleteAfterRefresh() async throws {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        #expect(model.lessons.count == 1 && model.nextCursor != nil)
        await model.loadHistory()
        #expect(model.lessons.count == 2 && model.nextCursor == nil && !model.isLoadingHistory)
        #expect(model.lessons.filter { SchoolLessonPeriod(month: 1, year: 2026).includes($0) }.count == 1)
        await model.refreshOnAppear()
        #expect(model.lessons.count == 2 && model.nextCursor == nil)
    }

    @Test func failedHistoryKeepsItsRowsAndCursorUntilRetry() async {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        await server.setPageUnavailable(true)
        await model.loadHistory()
        #expect(model.lessons.count == 1 && model.nextCursor == "older" && model.errorMessage != nil)
        #expect(!model.isLoadingHistory && !model.isLoadingMore)
        await server.setPageUnavailable(false)
        await model.loadHistory()
        #expect(model.lessons.count == 2 && model.nextCursor == nil && model.errorMessage == nil)
    }

    @Test func failedProgressRefreshKeepsTheLastReadUntilAccessIsRefused() async throws {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        let before = try #require(model.progress)
        let competencies = model.competencies
        await server.setProgressStatus(503)
        await model.loadProgress()
        #expect(model.progress?.items == before.items)
        #expect(model.competencies == competencies)
        #expect(model.progressError != nil)
        await server.setProgressStatus(403)
        await model.loadProgress()
        #expect(model.progress == nil && model.competencies.isEmpty)
        #expect(model.progressError != nil)
        #expect(model.training != nil && !model.accessRevoked)
        await server.setProgressStatus(401)
        await model.loadProgress()
        #expect(model.training == nil && model.lessons.isEmpty && model.accessRevoked)
    }

    @Test func anUnfinishedPastLessonDoesNotTakeTheNextLearnerWish() async {
        let model = workspace(HistoryServer())
        await model.load()
        await model.loadHistory()
        #expect(model.upcomingLessons(at: HubFixture.date("2026-09-28T11:00:00Z")).map(\.id) == [HubFixture.lessonID])
        #expect(model.upcomingLessons(at: HubFixture.date("2026-09-28T12:49:59Z")).map(\.id) == [HubFixture.lessonID])
        #expect(model.upcomingLessons(at: HubFixture.date("2026-09-28T12:50:00Z")).isEmpty)
    }

    @Test func publishedCompetencyWithNoContextRemainsReadable() async throws {
        let client = client(HistoryServer())
        let revision = try await client.revision(schoolID: HubFixture.schoolID, id: HistoryServer.revisionID)
        #expect(revision.observations.count == 1 && revision.observations.first?.context == "")
    }

    @Test func progressionReadsTheNextStepOfTheLastEvaluatedLessonAndDropsItWhenRefused() async throws {
        let server = HistoryServer(), model = workspace(server)
        await server.setEvaluated(true)
        await model.load()
        let last = try #require(model.lastEvaluated)
        #expect(last.lessonID == HubFixture.lessonID && last.revisionID == HistoryServer.revisionID)
        #expect(last.nextStep == "Reprendre les giratoires" && last.date == "2026-09-28T12:00:00Z")
        #expect(SchoolProgressRules.worked(in: last.lessonID, items: model.progress?.items ?? [], order: []).map(\.label) == ["Giratoire"])
        // Une révision publiée ne change pas : une relecture de la progression ne la redemande pas.
        let reads = await server.revisionReads
        await model.loadProgress()
        let readsAfter = await server.revisionReads
        #expect(readsAfter == reads && model.lastEvaluated == last)
        // Lecture du bilan refusée : le bloc disparaît, la progression reste, le dossier ne se ferme pas.
        await server.setRevisionStatus(403)
        await model.loadProgress(keepingCurrent: false)
        #expect(model.lastEvaluated == nil && model.progress != nil)
        #expect(model.training != nil && !model.accessRevoked)
    }

    @Test func aFormationWithoutEvaluationHasNoLastEvaluatedLesson() async {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        // L’évaluation du serveur de test désigne une autre leçon que celle de la révision servie : rien n’est affiché.
        #expect(model.progress != nil && model.lastEvaluated == nil)
    }

    @Test func refreshDuringAnOlderPageRestartsTheCompleteHistory() async {
        let server = HistoryServer(), model = workspace(server)
        await model.load()
        await server.pauseNextPage()
        let previous = Task { await model.loadHistory() }
        await server.waitUntilPaused()
        await model.refreshOnAppear()
        #expect(model.lessons.count == 2 && model.nextCursor == nil && !model.isLoadingHistory)
        await server.resumePage()
        await previous.value
        #expect(model.lessons.count == 2 && model.errorMessage == nil)
    }

    @Test func lessonChangeIsBroadcastOnlyAfterDurableConfirmation() async throws {
        let server = LessonFinishServer(), notifications = NotificationCenter(), changes = RecordedLessonChanges()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) {
            changes.append($0.object as? SchoolLessonChange)
        }
        defer { notifications.removeObserver(observer) }
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let model = SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership,
            lessonID: HubFixture.lessonID, client: client, outbox: ConfigurationOutboxStub(), notifications: notifications)
        await model.load()
        await server.setReceiptAvailable(false)
        model.setObservationLevel("GUIDED", for: LessonFinishServer.progressCompetency)
        #expect(!(await model.saveDraft()))
        #expect(changes.values.isEmpty && !model.reportSaveConfirmed)
        await server.setReceiptAvailable(true)
        await model.verifyPending()
        let change = try #require(changes.values.first)
        #expect(changes.values.count == 1 && model.reportSaveConfirmed)
        #expect(change.schoolID == HubFixture.schoolID && change.trainingID == HubFixture.trainingID && change.lessonID == HubFixture.lessonID)
    }

    @Test func receiptOfAnotherLessonNeverBroadcastsTheOpenLessonAsItsTarget() async throws {
        let server = LessonFinishServer(), notifications = NotificationCenter(), changes = RecordedLessonChanges()
        let observer = notifications.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) {
            changes.append($0.object as? SchoolLessonChange)
        }
        defer { notifications.removeObserver(observer) }
        let operation = UUID(), resource = UUID(), outbox = ConfigurationOutboxStub()
        let body = SchoolSaveReport(operationId: operation, workedOn: "", observationText: "", nextStep: "", observations: [])
        try outbox.save(PendingSchoolCommand(id: operation, scope: ConfigurationFixture.scope(), kind: .saveReportDraft,
            resourceVersion: 1, createdAt: Date(), body: try JSONEncoder().encode(body), resourceID: resource))
        await server.setConfirmedOperation(operation, resourceID: resource)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
        let model = SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: membership,
            lessonID: HubFixture.lessonID, client: client, outbox: outbox, notifications: notifications)
        await model.load()
        await model.verifyPending()
        #expect(changes.count == 1 && changes.values.isEmpty)
        #expect(!model.reportSaveConfirmed && model.pending == nil)
    }

    // MARK: Dossier à plusieurs permis

    @Test func mergedLessonsStopAtTheLastLessonReadOfAFormationThatHasMorePages() throws {
        let early = try HistoryServer.lesson(id: UUID(), start: "2026-01-10T08:00:00Z", end: "2026-01-10T08:50:00Z")
        let limit = try HistoryServer.lesson(id: UUID(), start: "2026-03-10T08:00:00Z", end: "2026-03-10T08:50:00Z")
        let between = try HistoryServer.lesson(id: UUID(), start: "2026-02-10T08:00:00Z", end: "2026-02-10T08:50:00Z")
        let later = try HistoryServer.lesson(id: UUID(), start: "2026-06-10T08:00:00Z", end: "2026-06-10T08:50:00Z")
        // La première formation a d’autres pages après mars : la leçon de juin de la seconde attend.
        let partial = SchoolLessonFeed.merged([(lessons: [early, limit], hasMore: true), (lessons: [between, later], hasMore: false)])
        #expect(Set(partial.map(\.id)) == Set([early.id, limit.id, between.id]))
        let complete = SchoolLessonFeed.merged([(lessons: [early, limit], hasMore: false), (lessons: [between, later], hasMore: false)])
        #expect(complete.count == 4)
        // Une seule formation : ses pages lues sont toutes montrées.
        #expect(SchoolLessonFeed.merged([(lessons: [early, limit], hasMore: true)]).count == 2)
        // Une formation paginée dont rien n’est lu retient tout.
        #expect(SchoolLessonFeed.merged([(lessons: [], hasMore: true), (lessons: [between], hasMore: false)]).isEmpty)
    }

    @Test func aFeedReadsEveryFormationAndPagesOnlyTheOneHoldingTheListBack() async {
        let other = UUID(uuidString: "60000000-0000-4000-8000-000000000002")!
        let first = workspace(HistoryServer()), second = workspace(HistoryServer(), trainingID: other)
        let feed = SchoolLessonFeed(models: [first, second])
        await feed.reload()
        #expect(first.lessons.count == 1 && first.nextCursor != nil && first.errorMessage == nil)
        // Le serveur de test ne connaît qu’une formation : la seconde lecture échoue sans effacer la première.
        #expect(second.training == nil && second.errorMessage != nil)
        #expect(!feed.allRead && feed.hasLessons && feed.hasMore && !feed.isLoadingFirstPage)
        #expect(feed.lessons.map(\.id) == [HubFixture.lessonID])
        await feed.loadMore()
        #expect(first.lessons.count == 2 && !feed.hasMore && feed.lessons.count == 2)
        #expect(feed.model(for: first.lessons[0]) === first)
    }

    @Test func permitsAreNamedOrderedAndSummarisedFromTheLearnerFormations() {
        let b = training("B", status: "COMPLETED", startedOn: "2024-03-01"), a = training("A"), be = training("BE", status: "PAUSED")
        #expect(SchoolPermitName.ordered([b, a, be]).map(\.id) == [a.id, b.id, be.id])
        #expect(SchoolPermitName.names([b, a])[a.id] == "Permis A")
        #expect(SchoolPermitName.summary([]) == nil)
        #expect(SchoolPermitName.summary([b]) == "Permis B")
        #expect(SchoolPermitName.summary([a, b, be]) == "Permis A, B (terminée), BE (en pause)")
        // Deux formations de même catégorie : l’année de début les distingue.
        let again = training("B", startedOn: "2026-09-01")
        let names = SchoolPermitName.names([again, b])
        #expect(names[again.id] == "Permis B · 2026" && names[b.id] == "Permis B · 2024")
    }

    @Test func theSharedCacheKeepsOneModelPerFormationOfTheSameLearner() {
        SchoolTrainingModelCache.reset()
        let client = client(HistoryServer()), scope = ConfigurationFixture.scope(), other = UUID()
        func model(_ training: UUID, learner: UUID = HubFixture.learnerID) -> (model: SchoolTrainingWorkspace, isNew: Bool) {
            SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner, trainingID: training, client: client)
        }
        let first = model(HubFixture.trainingID), second = model(other)
        #expect(first.isNew && second.isNew)
        #expect(!model(HubFixture.trainingID).isNew && model(HubFixture.trainingID).model === first.model)
        #expect(!model(other).isNew)
        // Un autre élève : les modèles du précédent ne sont plus servis.
        #expect(model(UUID(), learner: UUID()).isNew)
        #expect(model(HubFixture.trainingID).isNew)
        SchoolTrainingModelCache.reset()
    }

    private func training(_ category: String, status: String = "ACTIVE", startedOn: String? = nil) -> SchoolTraining {
        SchoolTraining(id: UUID(), schoolId: HubFixture.schoolID, learnerId: HubFixture.learnerID, offeringId: UUID(),
            version: 1, categoryCode: category, status: status, startedOn: startedOn, closedOn: nil)
    }

    private var membership: SchoolMembership {
        SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École de test", roles: ["INSTRUCTOR"], grants: ["permit_review"], accessEpoch: 1)
    }
    private func client(_ server: HistoryServer) -> SchoolTrainingClient {
        SchoolTrainingClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }
    private func workspace(_ server: HistoryServer, trainingID: UUID = HubFixture.trainingID) -> SchoolTrainingWorkspace {
        SchoolTrainingWorkspace(scope: ConfigurationFixture.scope(), membership: membership, learnerID: HubFixture.learnerID,
            trainingID: trainingID, client: client(server))
    }
}

private final class RecordedLessonChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SchoolLessonChange] = []
    private var broadcasts = 0
    func append(_ value: SchoolLessonChange?) {
        lock.lock(); defer { lock.unlock() }; broadcasts += 1
        if let value { stored.append(value) }
    }
    var values: [SchoolLessonChange] { lock.lock(); defer { lock.unlock() }; return stored }
    var count: Int { lock.lock(); defer { lock.unlock() }; return broadcasts }
}

private actor HistoryServer: SchoolHTTPTransport {
    static let revisionID = UUID(uuidString: "70000000-0000-4000-8000-000000000080")!
    private let fallback = LessonFinishServer()
    private var pageUnavailable = false
    private var progressStatus: Int?
    private var evaluated = false
    private var revisionStatus: Int?
    private(set) var revisionReads = 0
    private var shouldPause = false
    private var suspended: CheckedContinuation<Void, Never>?
    private var pauseWaiter: CheckedContinuation<Void, Never>?
    func setPageUnavailable(_ value: Bool) { pageUnavailable = value }
    func setProgressStatus(_ value: Int?) { progressStatus = value }
    /// La leçon de la première page devient une leçon terminée, évaluée, dont le bilan publié est la révision servie.
    func setEvaluated(_ value: Bool) { evaluated = value }
    func setRevisionStatus(_ value: Int?) { revisionStatus = value }
    func pauseNextPage() { shouldPause = true }
    func waitUntilPaused() async {
        if suspended != nil { return }
        await withCheckedContinuation { pauseWaiter = $0 }
    }
    func resumePage() { suspended?.resume(); suspended = nil }

    static func lesson(id: UUID, start: String, end: String) throws -> SchoolLesson {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson())) as! [String: Any]
        value["id"] = id.uuidString; value["plannedStart"] = start; value["plannedEnd"] = end
        return try JSONDecoder().decode(SchoolLesson.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        if url.lastPathComponent == "progress", let progressStatus {
            return SchoolHTTPResponse(data: Data("{}".utf8), status: progressStatus, url: url, contentType: "application/problem+json")
        }
        func ok(_ data: [String: Any]) throws -> SchoolHTTPResponse {
            let value: [String: Any] = ["data": data, "requestId": UUID().uuidString, "serverTime": "2026-09-30T10:00:00Z"]
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: value), status: 200, url: url, contentType: "application/json")
        }
        if url.lastPathComponent == "progress", evaluated {
            return try ok(["trainingId": HubFixture.trainingID.uuidString, "items": [["competencyId": LessonFinishServer.progressCompetency.uuidString,
                "label": "Giratoire", "level": "GUIDED", "context": "", "observedAt": "2026-09-28T13:00:00Z",
                "sourceLessonId": HubFixture.lessonID.uuidString, "sourceRevisionId": Self.revisionID.uuidString]],
                "unobservedCompetencyIds": [String](), "computedAt": "2026-09-28T13:30:00Z"])
        }
        if url.pathComponents.dropLast().last?.lowercased() == "report-revisions" {
            revisionReads += 1
            if let revisionStatus {
                return SchoolHTTPResponse(data: Data("{}".utf8), status: revisionStatus, url: url, contentType: "application/problem+json")
            }
            return try ok(["id": Self.revisionID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "lessonId": HubFixture.lessonID.uuidString, "authorMembershipId": ConfigurationFixture.membershipID.uuidString,
                "version": 1, "sequence": 1, "publishedAt": "2026-09-28T13:00:00Z", "workedOn": "", "observationText": "",
                "nextStep": evaluated ? "Reprendre les giratoires" : "",
                "observations": [["competencyId": LessonFinishServer.progressCompetency.uuidString, "level": "GUIDED", "context": ""]],
                "attachmentIds": [], "correctionReason": NSNull(), "capturePublication": NSNull(), "textObservations": []])
        }
        if url.lastPathComponent == "lessons" {
            let older = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "cursor" } == true
            if older && shouldPause {
                shouldPause = false
                await withCheckedContinuation { suspended = $0; pauseWaiter?.resume(); pauseWaiter = nil }
            }
            if older && pageUnavailable {
                return SchoolHTTPResponse(data: Data("{}".utf8), status: 503, url: url, contentType: "application/problem+json")
            }
            let lesson = older ? try Self.lesson(id: UUID(uuidString: "50000000-0000-4000-8000-000000000002")!,
                start: "2025-12-31T23:30:00Z", end: "2026-01-01T00:20:00Z") : HubFixture.lesson(status: evaluated ? "COMPLETED" : "PLANNED")
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lesson)) as! [String: Any]
            if evaluated && !older { value["currentPublishedRevisionId"] = Self.revisionID.uuidString }
            return try ok(["items": [value], "nextCursor": older ? NSNull() : "older" as Any])
        }
        return try await fallback.send(request)
    }
}
