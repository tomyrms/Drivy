import Foundation
import Testing
@testable import Drivy

struct SchoolHelpTests {
    @Test func onlyAConfiguredSingleEmailAddressOpensAContact() {
        let invalidAddresses: [String?] = [nil, "", " ", "contact", "contact@example", "contact@a..invalid",
            "contact@-example.invalid", "first@example.invalid,second@example.invalid",
            "contact@example.invalid?body=secret", "contact@example.invalid#fragment",
            "contact%0aBcc@example.invalid", "contact\r\n@example.invalid", "contact@example.invalid/extra"]
        for invalid in invalidAddresses {
            #expect(SchoolHelpContact.mail(invalid) == nil)
        }
        let url = SchoolHelpContact.mail(" help+drivy@example.invalid ")
        #expect(url?.scheme == "mailto")
        #expect(url?.path == "help+drivy@example.invalid")
        #expect(url?.query == nil && url?.fragment == nil)
    }

    @Test func theDiagnosticContainsOnlyThePublicPreview() {
        let value = SchoolHelpDiagnostic(version: "0.7.0", build: "123", system: "iPadOS 26.0")
        #expect(value.text == "Drivy\nVersion : 0.7.0\nBuild : 123\nSystème : iPadOS 26.0")
        #expect(value.text.split(separator: "\n").count == 4)
    }
}
