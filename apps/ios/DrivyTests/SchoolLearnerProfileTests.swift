import Foundation
import Testing
@testable import Drivy

/// Règles de l’onglet Profil et de la carte « Prochaine leçon » de l’élève.
@MainActor struct SchoolLearnerProfileTests {
    private static let instructor = ConfigurationFixture.membershipID
    private static let colleague = UUID(uuidString: "30000000-0000-4000-8000-000000000077")!

    @Test func overviewCountsCompletedLessonsAndTheirActualTimeOnly() {
        let first = Self.lesson(1, status: "COMPLETED", start: "2026-09-01T08:00:00Z",
            actual: ("2026-09-01T08:05:00Z", "2026-09-01T09:35:00Z"))
        // Horaire réel retiré par une correction de l’école : la leçon compte, son temps non.
        let corrected = Self.lesson(2, status: "COMPLETED", start: "2026-09-08T08:00:00Z", actual: nil)
        let latest = Self.lesson(3, status: "COMPLETED", start: "2026-09-15T08:00:00Z",
            actual: ("2026-09-15T08:00:00Z", "2026-09-15T08:45:00Z"))
        let cancelled = Self.lesson(4, status: "CANCELLED", start: "2026-09-20T08:00:00Z")
        let coming = Self.lesson(5, status: "PLANNED", start: "2026-12-01T08:00:00Z")
        let overview = SchoolTrainingOverview.make(lessons: [first, corrected, latest, cancelled, coming], progress: nil)
        #expect(overview.completedLessons == 3)
        #expect(overview.lessonMinutes == 135)
        #expect(overview.lastCompleted?.id == latest.id)
        #expect(overview.independent == nil && overview.competencies == nil)
    }

    @Test func autonomyIsACountOverTheWholeCurriculum() throws {
        let progress = try Self.progress(levels: ["INDEPENDENT", "GUIDED", "INDEPENDENT"], unobserved: 2)
        let overview = SchoolTrainingOverview.make(lessons: [], progress: progress)
        #expect(overview.independent == 2 && overview.competencies == 5)
        #expect(overview.completedLessons == 0 && overview.lastCompleted == nil)
    }

    @Test func durationsReadInHoursAndMinutes() {
        #expect(SchoolTrainingOverview.duration(45) == "45 min")
        #expect(SchoolTrainingOverview.duration(120) == "2 h")
        #expect(SchoolTrainingOverview.duration(605) == "10 h 05")
    }

    @Test func onlyTheCurrentAssignedInstructorIsNamedFromTheirLessons() {
        let now = HubFixture.date("2026-10-11T08:00:00Z")
        let current = Self.assignment(Self.instructor, from: "2026-01-01T00:00:00Z", until: nil)
        let ended = Self.assignment(Self.colleague, from: "2025-01-01T00:00:00Z", until: "2026-06-01T00:00:00Z")
        let lessons = [
            Self.lesson(1, status: "COMPLETED", start: "2026-05-01T08:00:00Z", instructor: Self.colleague, name: "Sam Rey"),
            Self.lesson(2, status: "COMPLETED", start: "2026-09-01T08:00:00Z", instructor: Self.instructor, name: "Alex Martin"),
        ]
        #expect(SchoolTrainingOverview.assignedInstructors(assignments: [current, ended], lessons: lessons, now: now) == ["Alex Martin"])
        // Un moniteur affecté sans leçon lue n’est pas nommé : rien n’est deviné.
        #expect(SchoolTrainingOverview.assignedInstructors(assignments: [current], lessons: [lessons[0]], now: now).isEmpty)
        #expect(SchoolTrainingOverview.assignedInstructors(assignments: [ended], lessons: lessons, now: now).isEmpty)
        // Deux moniteurs affectés : deux noms distincts, dans l’ordre alphabétique, jamais une chaîne concaténée.
        let both = [current, Self.assignment(Self.colleague, from: "2025-01-01T00:00:00Z", until: nil)]
        #expect(SchoolTrainingOverview.assignedInstructors(assignments: both, lessons: lessons, now: now) == ["Alex Martin", "Sam Rey"])
    }

    @Test func permitSummaryGroupsLessonsAndTimeOnOneLine() throws {
        func overview(_ lessons: Int, _ minutes: Int) -> SchoolTrainingOverview {
            SchoolTrainingOverview(completedLessons: lessons, lessonMinutes: minutes, lastCompleted: nil, independent: nil, competencies: nil)
        }
        #expect(overview(0, 0).summary == "Aucune leçon terminée")
        #expect(overview(1, 45).summary == "1 leçon terminée · 45 min")
        #expect(overview(12, 870).summary == "12 leçons terminées · 14 h 30")
        // Aucun horaire réel connu : le temps ne s’invente pas.
        #expect(overview(3, 0).summary == "3 leçons terminées")
        #expect(overview(3, 0).autonomySummary == nil)
        let progress = try Self.progress(levels: ["INDEPENDENT", "GUIDED"], unobserved: 3)
        #expect(SchoolTrainingOverview.make(lessons: [], progress: progress).autonomySummary == "1 sur 5 compétences en autonomie")
    }

    @Test func profileOnlyFlagsAGpsConsentThatAwaitsAnAnswer() {
        func label(notice: Bool = true, revoked: Bool = false, pending: Bool = false, answered: Bool = false) -> String? {
            SchoolRecordingChoiceAttention.label(notice: notice, revoked: revoked, pending: pending, answered: answered)
        }
        #expect(label() == "À donner")
        #expect(label(answered: true) == nil)
        #expect(label(pending: true, answered: true) == "À vérifier")
        // Pas encore lu, lecture en panne ou accès retiré : le Profil ne dit rien, Paramètres porte le détail.
        #expect(label(notice: false) == nil)
        #expect(label(revoked: true) == nil)
        #expect(SchoolRecordingChoiceWorkspace.readingFailure(unreachable: true).hasPrefix("L’accord GPS n’a pas pu être lu"))
        #expect(SchoolRecordingChoiceWorkspace.readingFailure(unreachable: false) == "L’accord GPS n’a pas pu être lu.")
    }

    @Test func nextLessonMomentIsSaidToTheDay() {
        let now = HubFixture.date("2026-10-11T08:00:00Z")
        func moment(_ start: String) -> String? {
            SchoolLearnerLessonMoment.text(for: Self.lesson(1, status: "PLANNED", start: start), now: now)
        }
        #expect(moment("2026-10-11T08:30:00Z") == "Dans 30 min")
        #expect(moment("2026-10-11T15:00:00Z") == "Aujourd’hui")
        #expect(moment("2026-10-12T07:00:00Z") == "Demain")
        #expect(moment("2026-10-14T08:00:00Z") == "Dans 3 jours")
        #expect(moment("2026-10-25T08:00:00Z") == nil)
        let started = Self.lesson(1, status: "PLANNED", start: "2026-10-11T07:30:00Z", actual: ("2026-10-11T07:35:00Z", nil))
        #expect(SchoolLearnerLessonMoment.text(for: started, now: now) == nil)
        #expect(moment("2026-10-11T07:55:00Z") == "Maintenant")
    }

    @Test func theLessonOfTheHourStaysFirstUntilItsSlotEnds() {
        let now = HubFixture.date("2026-10-11T08:05:00Z")
        // Le moniteur n’a pas encore commencé la leçon de 8 h : elle ne cède pas la tête à celle de la semaine suivante.
        let waiting = Self.lesson(1, status: "PLANNED", start: "2026-10-11T08:00:00Z")
        let later = Self.lesson(2, status: "PLANNED", start: "2026-10-18T08:00:00Z")
        let cancelled = Self.lesson(3, status: "CANCELLED", start: "2026-10-11T08:30:00Z")
        #expect(SchoolLearnerLessonMoment.featured([later, cancelled, waiting], now: now)?.id == waiting.id)
        // Une leçon qui se déroule passe devant ; un créneau fini sans résultat n’est plus à venir.
        let running = Self.lesson(4, status: "PLANNED", start: "2026-10-11T07:45:00Z", actual: ("2026-10-11T07:50:00Z", nil))
        #expect(SchoolLearnerLessonMoment.featured([later, waiting, running], now: now)?.id == running.id)
        let lapsed = Self.lesson(5, status: "PLANNED", start: "2026-10-10T08:00:00Z")
        #expect(SchoolLearnerLessonMoment.featured([lapsed, later], now: now)?.id == later.id)
        #expect(SchoolLearnerLessonMoment.featured([lapsed, cancelled], now: now) == nil)
    }

    // MARK: Données de test

    @Test func permitLevelsSplitTheCurriculumWithoutCountingAnUnknownLevelAsAcquired() throws {
        #expect(SchoolPermitLevels(progress: nil) == nil)
        let progress = try Self.progress(levels: ["INDEPENDENT", "GUIDED", "DISCOVERING", "LATER"], unobserved: 2)
        let levels = try #require(SchoolPermitLevels(progress: progress))
        #expect(levels == SchoolPermitLevels(independent: 1, inProgress: 2, unseen: 3))
        #expect(levels.total == 6)
    }

    @Test func permitFiguresNameOnlyWhatExistsAndTheNextLessonStillToCome() {
        let now = HubFixture.date("2026-10-12T10:00:00Z")
        let done = Self.lesson(1, status: "COMPLETED", start: "2026-10-01T08:00:00Z", actual: nil)
        // Commencée mais pas terminée : ce n’est plus une prochaine leçon.
        let started = Self.lesson(2, status: "PLANNED", start: "2026-10-12T09:30:00Z", actual: ("2026-10-12T09:31:00Z", nil))
        let later = Self.lesson(3, status: "PLANNED", start: "2026-10-20T08:00:00Z")
        let sooner = Self.lesson(4, status: "PLANNED", start: "2026-10-14T08:00:00Z")
        let lessons = [done, started, later, sooner]
        #expect(SchoolLearnerPermitDetail.nextLesson(lessons, now: now)?.id == sooner.id)
        let overview = SchoolTrainingOverview.make(lessons: lessons, progress: nil)
        let ids = SchoolLearnerPermitDetail.figures(overview, lessons: lessons, now: now).map(\.id)
        // Aucun horaire réel : le temps de conduite n’est pas affirmé.
        #expect(ids == ["lessons", "last", "next"])
        #expect(SchoolLearnerPermitDetail.figures(SchoolTrainingOverview.make(lessons: [], progress: nil), lessons: [], now: now)
            .map(\.id) == ["lessons"])
    }

    private static func lesson(_ index: Int, status: String, start: String, actual: (String, String?)? = nil,
                               instructor: UUID = instructor, name: String? = "Alex Martin") -> SchoolLesson {
        let begin = HubFixture.date(start)
        let end = ISO8601DateFormatter().string(from: begin.addingTimeInterval(50 * 60))
        return SchoolLesson(id: UUID(uuidString: String(format: "50000000-0000-4000-8000-%012d", index))!, schoolId: HubFixture.schoolID,
            version: 1, trainingId: HubFixture.trainingID, learnerId: HubFixture.learnerID, instructorMembershipId: instructor,
            plannedStart: start, plannedEnd: end, timeZone: "Europe/Zurich", meetingPoint: "Gare de Sion", status: status,
            priceCentsSnapshot: 9_000, bufferMinutesSnapshot: 10, actualStart: actual?.0, actualEnd: actual?.1, permitWarning: false,
            publicationVersion: 0, currentPublishedRevisionId: nil, commercialRevisionVersion: 1, instructorDisplayName: name)
    }

    private static func assignment(_ instructor: UUID, from: String, until: String?) -> SchoolAssignment {
        SchoolAssignment(id: UUID(), schoolId: HubFixture.schoolID, version: 1, trainingId: HubFixture.trainingID,
            instructorMembershipId: instructor, validFrom: from, validUntil: until)
    }

    private static func progress(levels: [String], unobserved: Int) throws -> SchoolReportProgress {
        let items: [[String: Any]] = levels.enumerated().map { index, level in
            ["competencyId": UUID().uuidString, "label": "Compétence \(index)", "level": level, "context": "",
             "observedAt": "2026-09-28T13:00:00Z", "sourceLessonId": HubFixture.lessonID.uuidString,
             "sourceRevisionId": UUID().uuidString]
        }
        let value: [String: Any] = ["trainingId": HubFixture.trainingID.uuidString, "items": items,
            "unobservedCompetencyIds": (0..<unobserved).map { _ in UUID().uuidString }, "computedAt": "2026-09-28T13:30:00Z"]
        return try JSONDecoder().decode(SchoolReportProgress.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
