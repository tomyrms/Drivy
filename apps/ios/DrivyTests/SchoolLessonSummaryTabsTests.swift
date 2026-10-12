import Foundation
import Testing
@testable import Drivy

/// Règles du récapitulatif à onglets d’une leçon terminée, et reprise de l’accord GPS sous « Mon souhait ».
@MainActor struct SchoolLessonSummaryTabsTests {
    @Test func tabsKeepTheirOrderAndSpeakTheirFullTitle() {
        #expect(SchoolLessonSummaryTab.allCases.map(\.title) == ["Bilan", "Compétences", "Trajet & notes"])
        #expect(SchoolLessonSummaryTab.route.spokenTitle == "Trajet et observations")
        // Le segmenté garde ses trois intitulés jusqu’à « xLarge », puis devient un menu.
        #expect(!SchoolLessonSummaryRules.usesMenu(.xLarge))
        #expect(SchoolLessonSummaryRules.usesMenu(.xxLarge))
        #expect(SchoolLessonSummaryRules.usesMenu(.accessibility3))
    }

    @Test func durationIsTheActualOneWhenTheSchoolKnowsItOtherwiseTheBookedOne() {
        let actual = Self.lesson(actual: ("2026-10-01T08:04:00Z", "2026-10-01T08:59:00Z"))
        #expect(SchoolLessonSummaryRules.duration(actual) == .init(minutes: 55, isActual: true))
        let booked = Self.lesson(actual: nil)
        #expect(SchoolLessonSummaryRules.duration(booked) == .init(minutes: 50, isActual: false))
        // Fin avant le départ : rien de réel n’est affirmé, la durée réservée reste.
        let inverted = Self.lesson(actual: ("2026-10-01T09:00:00Z", "2026-10-01T08:00:00Z"))
        #expect(SchoolLessonSummaryRules.duration(inverted)?.isActual == false)
    }

    @Test func observationsGroupByAppraisalKeepingTheirOrder() {
        let items: [(String, SchoolObservationStatus?)] = [("a", .attention), ("b", .positive), ("c", nil), ("d", .toWorkOn), ("e", .positive)]
        let sections = SchoolLessonSummaryRules.sections(items) { $0.1 }
        #expect(sections.map(\.group) == [.positive, .attention, .general])
        #expect(sections.map { $0.items.map(\.0) } == [["b", "e"], ["a", "d"], ["c"]])
        // Un groupe vide n’existe pas.
        #expect(SchoolLessonSummaryRules.sections([("a", SchoolObservationStatus?.some(.positive))]) { $0.1 }.map(\.group) == [.positive])
    }

    @Test func levelBreakdownGoesFromTheMostAdvancedAndSkipsAbsentLevels() {
        #expect(SchoolLessonSummaryRules.levelBreakdown(["GUIDED", "INDEPENDENT", "GUIDED"]) == "1 en autonomie · 2 avec accompagnement")
        #expect(SchoolLessonSummaryRules.levelBreakdown(["DISCOVERING"]) == "1 en découverte")
        #expect(SchoolLessonSummaryRules.levelBreakdown([]) == nil)
    }

    /// Le squelette « Lecture de l’accord GPS… » ne reste que pendant une lecture ; une lecture interrompue reprend.
    @Test func anInterruptedConsentReadIsRestartedNeverLeftLoading() {
        #expect(SchoolOwnRecordingChoice.interruptedRead(hasNotice: false, isLoading: false, hasError: false,
            accessRevoked: false, needsReload: true))
        // En cours, lue, en panne ou accès retiré : rien à relancer.
        #expect(!SchoolOwnRecordingChoice.interruptedRead(hasNotice: false, isLoading: true, hasError: false,
            accessRevoked: false, needsReload: true))
        #expect(!SchoolOwnRecordingChoice.interruptedRead(hasNotice: true, isLoading: false, hasError: false,
            accessRevoked: false, needsReload: false))
        #expect(!SchoolOwnRecordingChoice.interruptedRead(hasNotice: false, isLoading: false, hasError: true,
            accessRevoked: false, needsReload: true))
        #expect(!SchoolOwnRecordingChoice.interruptedRead(hasNotice: false, isLoading: false, hasError: false,
            accessRevoked: true, needsReload: true))
    }

    private static func lesson(actual: (String, String)?) -> SchoolLesson {
        SchoolLesson(id: HubFixture.lessonID, schoolId: HubFixture.schoolID, version: 1, trainingId: HubFixture.trainingID,
            learnerId: HubFixture.learnerID, instructorMembershipId: ConfigurationFixture.membershipID,
            plannedStart: "2026-10-01T08:00:00Z", plannedEnd: "2026-10-01T08:50:00Z", timeZone: "Europe/Zurich",
            meetingPoint: "Gare de Sion", status: "COMPLETED", priceCentsSnapshot: 9_000, bufferMinutesSnapshot: 10,
            actualStart: actual?.0, actualEnd: actual?.1, permitWarning: false, publicationVersion: 0,
            currentPublishedRevisionId: nil, commercialRevisionVersion: 1)
    }
}
