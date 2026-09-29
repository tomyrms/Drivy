import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLiveObservationRecorderTests {
    @Test func gestureIsDurableBeforeReturningAndDoubleTapIsRefused() throws {
        let outbox = ConfigurationOutboxStub()
        let model = recorder(outbox: outbox)
        let instant = HubFixture.date("2026-09-28T12:11:00Z")
        #expect(model.record(.attention, at: instant))
        let command = try #require(outbox.value)
        let body = try JSONDecoder().decode(SchoolObservationBody.self, from: command.body)
        #expect(body.operationId == command.id && command.routeResourceID == HubFixture.lessonID)
        #expect(body.observedAt.flatMap(SchoolLesson.date) == instant)
        #expect(body.captureId == nil && body.segmentId == nil && body.pointSequence == nil && body.isValid)
        #expect(!model.record(.positive, at: instant) && outbox.saves.count == 1)
        #expect(model.confirmed == 0 && !model.canRecord)
        model.stop()
    }

    @Test func failedStorageNeverClaimsTheGestureWasKept() {
        let outbox = ConfigurationOutboxStub(); outbox.failSave = true
        let model = recorder(outbox: outbox)
        #expect(!model.record(.marker))
        #expect(model.pending == nil && model.confirmed == 0 && outbox.value == nil)
        #expect(model.errorMessage?.contains("n’a pas été enregistré") == true)
    }

    @Test func pendingGestureSurvivesRecreationAndAccountChangeStopsSending() throws {
        let outbox = ConfigurationOutboxStub()
        let first = recorder(outbox: outbox)
        #expect(first.record(.toWorkOn)); first.stop()
        let command = try #require(outbox.value)
        let restored = recorder(outbox: outbox)
        #expect(restored.pending == command && restored.canRetry && !restored.canRecord)
        restored.stop()
        #expect(!restored.canRetry && !restored.record(.positive))
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

    private func recorder(outbox: ConfigurationOutboxStub) -> SchoolLiveObservationRecorder {
        let client = SchoolObservationClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: HubServer())
        return SchoolLiveObservationRecorder(scope: ConfigurationFixture.scope(), lessonID: HubFixture.lessonID,
            client: client, outbox: outbox)
    }
}
