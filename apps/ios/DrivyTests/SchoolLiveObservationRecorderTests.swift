import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLiveObservationRecorderTests {
    @Test func gestureIsDurableBeforeReturningAndDoubleTapIsRefused() throws {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        let instant = HubFixture.date("2026-09-28T12:11:00Z")
        #expect(model.markMoment(at: instant))
        let command = try #require(outbox.value)
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: command.body)
        #expect(body.operationId == command.id && command.routeResourceID == HubFixture.lessonID)
        #expect(body.observedAt.flatMap(SchoolLesson.date) == instant)
        #expect(body.captureId == nil && body.segmentId == nil && body.pointSequence == nil && body.isValid)
        #expect(!model.markMoment(at: instant) && outbox.saves.count == 1)
        #expect(model.confirmed == 0 && !model.canRecord)
        model.stop()
    }

    @Test func failedStorageNeverClaimsTheGestureWasKept() {
        let outbox = ConfigurationOutboxStub(); outbox.failSave = true
        let model = recorder(outbox: outbox)
        #expect(!model.markMoment())
        #expect(model.pending == nil && model.confirmed == 0 && outbox.value == nil)
        #expect(model.errorMessage?.contains("n’a pas été enregistré") == true)
    }

    @Test func pendingGestureSurvivesRecreationAndAccountChangeStopsSending() throws {
        let outbox = ConfigurationOutboxStub()
        let first = recorder(outbox: outbox)
        #expect(first.markMoment()); first.stop()
        let command = try #require(outbox.value)
        let restored = recorder(outbox: outbox)
        #expect(restored.pending == command && restored.canRetry && !restored.canRecord)
        restored.stop()
        #expect(!restored.canRetry && !restored.markMoment())
        #expect(outbox.value == command)
    }

    @Test func completedReportDoesNotDuplicateObservationTextPastItsPrivacyControl() {
        let observation = SchoolObservation(id: UUID(), schoolId: HubFixture.schoolID, version: 1,
            lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
            captureId: nil, segmentId: nil, pointSequence: nil, competencyId: nil,
            text: "Observation à garder pour moi", origin: "LIVE", observedAt: "2026-09-28T12:11:00Z",
            eventKind: "MARKER", eventStatus: nil, authorMembershipId: ConfigurationFixture.membershipID)
        let result = SchoolLessonHubRules.completionReport(goals: [SchoolLessonGoal(label: "Priorités")],
            observations: [observation], competencies: [])
        #expect(result.workedOn == "Priorités" && result.observationText.isEmpty)
    }

    @Test func qualificationKeepsTheChosenThemeStatusAndOriginalInstant() async throws {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        await model.loadCompetencies()
        let theme = try #require(model.themes.first)
        let instant = HubFixture.date("2026-09-28T12:11:00Z")
        #expect(model.record(theme: theme, status: .attention, at: instant))
        let command = try #require(outbox.value)
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: command.body)
        #expect(body.competencyId == theme.competency.id && body.eventKind == "QUALIFIED")
        #expect(body.eventStatus == "ATTENTION" && body.text == "Priorité à droite")
        #expect(body.observedAt.flatMap(SchoolLesson.date) == instant)
        #expect(body.captureId == nil && body.isValid)
        #expect(!model.record(theme: theme, status: .positive, at: instant))
        model.stop()
    }

    @Test func aThemeNotReadFromTheTrainingCannotBeRecorded() {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        #expect(!model.record(theme: SchoolLiveObservationTheme.choices(for: LiveObservationTransport.competency)[0], status: .attention, at: Date()))
        #expect(outbox.value == nil && model.pending == nil)
        model.stop()
    }

    @Test func preciseThemesOnlyExpandADocumentedSchoolCompetency() {
        let c = LiveObservationTransport.competency
        let priorities = SchoolCatalogCompetency(id: c.id, schoolId: c.schoolId, version: c.version,
            curriculumVersionId: c.curriculumVersionId, key: "priorites", label: "Priorités",
            description: "Priorité de droite, signalisation et céder le passage.", sortOrder: 1)
        let themes = SchoolLiveObservationTheme.choices(for: priorities)
        #expect(themes.map(\.title) == ["Priorité à droite", "Signalisation", "Céder le passage"])
        #expect(themes.allSatisfy { $0.competency.id == priorities.id })
        #expect(SchoolLiveObservationTheme.choices(for: c).count == 1)
    }

    @Test func replayNamesThePreciseObservationAndKeepsItsStatusSeparate() {
        let observation = SchoolObservation(id: UUID(), schoolId: HubFixture.schoolID, version: 1,
            lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
            captureId: nil, segmentId: nil, pointSequence: nil, competencyId: LiveObservationTransport.competency.id,
            text: "Priorité à droite", origin: "LIVE", observedAt: "2026-09-28T12:11:00Z",
            eventKind: "QUALIFIED", eventStatus: "ATTENTION", authorMembershipId: ConfigurationFixture.membershipID)
        let timeline = SchoolReplayTimeline(fragments: [], observations: [observation],
            startsAt: HubFixture.date("2026-09-28T12:00:00Z"), endsAt: HubFixture.date("2026-09-28T12:30:00Z"))
        #expect(timeline.items.first?.title == "Priorité à droite")
        #expect(timeline.items.first?.statusLabel == "Attention")
        #expect(timeline.items.first?.coordinate == nil && timeline.items.first?.offset == 660)
    }

    private func recorder(outbox: ConfigurationOutboxStub) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: LiveObservationTransport())
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
    }
}

private actor LiveObservationTransport: SchoolHTTPTransport {
    static let offeringID = UUID(uuidString: "70000000-0000-4000-8000-000000000002")!
    static let curriculumID = UUID(uuidString: "70000000-0000-4000-8000-000000000003")!
    static let competency = SchoolCatalogCompetency(id: UUID(uuidString: "70000000-0000-4000-8000-000000000004")!,
        schoolId: HubFixture.schoolID, version: 1, curriculumVersionId: curriculumID, key: "priority-right",
        label: "Priorité à droite", description: "Observer la priorité à droite.", sortOrder: 1)
    private let fallback = HubServer()
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func response(_ value: some Encodable) throws -> SchoolHTTPResponse {
            let data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": data,
                "requestId": UUID().uuidString, "serverTime": "2026-09-28T12:15:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        if url.pathComponents.dropLast().last == "trainings" {
            return try response(SchoolTraining(id: HubFixture.trainingID, schoolId: HubFixture.schoolID,
                learnerId: HubFixture.learnerID, offeringId: Self.offeringID, version: 1, categoryCode: "B",
                status: "ACTIVE", startedOn: nil, closedOn: nil))
        }
        if url.lastPathComponent == "offerings" {
            return try response(SchoolPage(items: [SchoolOffering(id: Self.offeringID, schoolId: HubFixture.schoolID,
                version: 1, offeringKey: "B", categoryCode: "B", curriculumVersionId: Self.curriculumID,
                policyVersionId: UUID(), enabled: true, defaultDurationMinutes: 50, defaultPriceCents: 9000)], nextCursor: nil))
        }
        if url.lastPathComponent == "curricula" {
            return try response(SchoolPage(items: [SchoolCurriculum(id: Self.curriculumID, schoolId: HubFixture.schoolID,
                version: 1, categoryCode: "B", revision: 1, approved: true, competencies: [Self.competency])], nextCursor: nil))
        }
        return try await fallback.send(request)
    }
}
