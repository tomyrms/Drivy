import Foundation
import Testing
@testable import Drivy

/// Un état de leçon se lit en texte dans la ligne, et seulement pour l’inhabituel.
@MainActor struct DrivyLessonRowStateTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var end: Date { start.addingTimeInterval(3_600) }

    private func state(_ status: String, now: Date) -> DrivyLessonState {
        DrivyLessonState(status: status, start: start, end: end, now: now)
    }

    @Test func plannedRunningAndCompletedLessonsSayNothing() {
        #expect(state("PLANNED", now: start.addingTimeInterval(-60)).rowNote == nil)
        #expect(state("PLANNED", now: start.addingTimeInterval(60)).rowNote == nil)
        #expect(state("COMPLETED", now: end.addingTimeInterval(60)).rowNote == nil)
    }

    @Test func unusualLessonsSayOneWord() {
        let after = end.addingTimeInterval(60)
        #expect(state("PLANNED", now: after).rowNote == DrivyRowNote(text: "À terminer", tone: .warning))
        #expect(state("CANCELLED", now: after).rowNote == DrivyRowNote(text: "Annulée", tone: .neutral))
        #expect(state("NO_SHOW", now: after).rowNote == DrivyRowNote(text: "Absence", tone: .neutral))
        #expect(state("UNKNOWN", now: after).rowNote == DrivyRowNote(text: "À vérifier", tone: .neutral))
    }

    @Test func onlyCancelledAndMissedLessonsStepBack() {
        let after = end.addingTimeInterval(60)
        #expect(state("CANCELLED", now: after).isClosed)
        #expect(state("NO_SHOW", now: after).isClosed)
        #expect(!state("PLANNED", now: after).isClosed)
        #expect(!state("COMPLETED", now: after).isClosed)
        #expect(!state("UNKNOWN", now: after).isClosed)
    }
}
