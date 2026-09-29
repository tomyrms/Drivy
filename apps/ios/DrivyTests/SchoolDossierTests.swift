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
}
