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

    // MARK: Ce que la leçon contient

    @Test func contentsAreSaidInWordsInAFixedOrder() {
        #expect(DrivyLessonContents().label == nil)
        #expect(DrivyLessonContents.report.label == "Bilan")
        #expect(DrivyLessonContents.trip.label == "Trajet")
        #expect(DrivyLessonContents([.trip, .report]).label == "Bilan · Trajet")
    }

    @Test func onlyACompletedLessonWithASharedReportSaysBilan() throws {
        let revision = UUID().uuidString
        #expect(try lesson(status: "COMPLETED", revision: revision).drivyContents == .report)
        #expect(try lesson(status: "COMPLETED").drivyContents.isEmpty)
        #expect(try lesson(status: "PLANNED", revision: revision).drivyContents.isEmpty)
        #expect(try lesson(status: "CANCELLED", revision: revision).drivyContents.isEmpty)
    }

    @Test func onlyAReconstructedTripSaysTrajet() throws {
        func contents(_ has: Bool, _ sync: String?, _ publication: String, status: String = "COMPLETED") throws -> DrivyLessonContents {
            let syncValue: Any = sync.map { $0 as Any } ?? NSNull()
            let capture: [String: Any] = ["hasCapture": has, "syncState": syncValue, "publicationState": publication]
            return try lesson(status: status, capture: capture).drivyContents
        }
        #expect(try contents(true, "SYNCED", "PRIVATE") == .trip)
        #expect(try contents(true, "PARTIAL", "PRIVATE") == .trip)
        // Le trajet se lit quel que soit le statut de la leçon.
        #expect(try contents(true, "SYNCED", "PRIVATE", status: "PLANNED") == .trip)
        for sync in ["LOCAL_ONLY", "UPLOADING", "REJECTED"] {
            #expect(try contents(true, sync, "PRIVATE").isEmpty)
        }
        #expect(try contents(true, nil, "PRIVATE").isEmpty)
        #expect(try contents(false, "SYNCED", "PRIVATE").isEmpty)
        for publication in ["WITHDRAWN", "DELETED", "PUBLISHED"] {
            #expect(try contents(true, "SYNCED", publication).isEmpty)
        }
        // Un serveur plus ancien n’envoie pas le résumé : aucun trajet n’est annoncé.
        #expect(try lesson(status: "COMPLETED").drivyContents.isEmpty)
        let both = try lesson(status: "COMPLETED", revision: UUID().uuidString,
            capture: ["hasCapture": true, "syncState": "SYNCED", "publicationState": "PRIVATE"])
        #expect(both.drivyContents == [.report, .trip])
    }

    private func lesson(status: String, revision: String? = nil, capture: [String: Any]? = nil) throws -> SchoolLesson {
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson(status: status))) as! [String: Any]
        if let revision { value["currentPublishedRevisionId"] = revision }
        if let capture { value["captureSummary"] = capture }
        return try JSONDecoder().decode(SchoolLesson.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
