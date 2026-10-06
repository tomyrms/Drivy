import Foundation
import Testing
@testable import Drivy

struct SchoolDossierTests {
    @Test func contactLinksUseOnlyWhatTheSchoolRecorded() {
        #expect(SchoolContactLinks.call("+41 79 123 45 67")?.absoluteString == "tel:+41791234567")
        #expect(SchoolContactLinks.message("079 123 45 67")?.absoluteString == "sms:0791234567")
        #expect(SchoolContactLinks.call("12") == nil)
        #expect(SchoolContactLinks.call("pas de numéro") == nil)
        #expect(SchoolContactLinks.call("+41+79 123")?.absoluteString == "tel:+4179123")
        #expect(SchoolContactLinks.mail(" camille@example.test ")?.absoluteString == "mailto:camille@example.test")
        #expect(SchoolContactLinks.mail("camille") == nil)
        #expect(SchoolContactLinks.mail("camille @example.test") == nil)
    }

    @Test func contactGesturesExistOnlyForUsableRecordedContacts() {
        let links = SchoolLearnerContactLink.links(
            for: SchoolLearnerContact(email: " camille@example.test ", phone: "+41 79 123 45 67"))
        #expect(links.map(\.id) == ["phone", "message", "email"])
        #expect(links.map(\.url.absoluteString) == ["tel:+41791234567", "sms:+41791234567", "mailto:camille@example.test"])
        #expect(links.first?.value == "+41 79 123 45 67")
        #expect(SchoolLearnerContactLink.links(for: SchoolLearnerContact(email: "camille", phone: "12")).isEmpty)
        #expect(SchoolLearnerContactLink.links(for: SchoolLearnerContact()).isEmpty)
        #expect(SchoolLearnerContactLink.links(for: SchoolLearnerContact(email: "camille@example.test")).map(\.id) == ["email"])
    }

    @Test func profileNameIsRepeatedOnlyWhenItDiffersFromTheDisplayedName() {
        let name = SchoolLearnerRecordedName.text(firstName: " Camille ", lastName: "Exemple")
        #expect(name == "Camille Exemple")
        #expect(SchoolLearnerRecordedName.repeats(name, displayedName: "camille  EXEMPLE"))
        #expect(!SchoolLearnerRecordedName.repeats(name, displayedName: "Cam Exemple"))
        #expect(!SchoolLearnerRecordedName.repeats(name, displayedName: nil))
        #expect(SchoolLearnerRecordedName.text(firstName: nil, lastName: "  ").isEmpty)
        // Un profil sans nom n’est pas une répétition : la ligne reste, avec « Non renseigné ».
        #expect(!SchoolLearnerRecordedName.repeats("", displayedName: "Camille Exemple"))
    }

    // MARK: Ligne de leçon

    @MainActor @Test func aDossierLessonRowIsTitledByItsDayAndNeverShowsTheMeetingPoint() {
        let lesson = HubFixture.lesson(status: "COMPLETED", meetingPoint: "Gare de Lausanne")
        let day = SchoolTrainingFormatting.rowDay(lesson.plannedStart, zone: lesson.timeZone)
        #expect(SchoolLessonHistoryRow.titleText(lesson, title: .day) == day)
        // Un seul permis, le lecteur est le moniteur : la ligne de détail n’existe pas.
        #expect(SchoolLessonHistoryRow.detail(lesson, title: .day, permit: nil, instructor: nil).isEmpty)
        #expect(SchoolLessonHistoryRow.detail(lesson, title: .day, permit: "Permis B", instructor: " ") == "Permis B")
        #expect(SchoolLessonHistoryRow.detail(lesson, title: .day, permit: "Permis B", instructor: "Luc Morel") == "Permis B · Luc Morel")
    }

    @MainActor @Test func anInstructorHistoryRowIsTitledByTheLearnerAndDatedInItsDetail() {
        var lesson = HubFixture.lesson(status: "COMPLETED")
        let day = SchoolTrainingFormatting.rowDay(lesson.plannedStart, zone: lesson.timeZone)
        // Sans nom fourni avec la leçon, aucun nom n’est déduit.
        #expect(SchoolLessonHistoryRow.titleText(lesson, title: .learner) == "Élève")
        lesson.learnerDisplayName = "Camille Perret"
        #expect(SchoolLessonHistoryRow.titleText(lesson, title: .learner) == "Camille Perret")
        #expect(SchoolLessonHistoryRow.detail(lesson, title: .learner, permit: nil, instructor: nil) == day)
        #expect(SchoolLessonHistoryRow.detail(lesson, title: .learner, permit: nil, instructor: "Luc Morel") == "\(day) · Luc Morel")
    }
}
