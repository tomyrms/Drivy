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
}
