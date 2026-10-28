import Foundation
import Testing
@testable import Drivy

struct SchoolIndividualCancellationTests {
    @Test func deadlineUsesElapsedHoursAcrossBothClockChanges() throws {
        let rules = SchoolIndividualCancellationRules(cancellationHours: 24, lateAction: .contact)
        let formatter = ISO8601DateFormatter()
        for (start, expected) in [
            ("2027-03-28T10:00:00Z", "2027-03-27T10:00:00Z"),
            ("2027-10-31T10:00:00Z", "2027-10-30T10:00:00Z")
        ] {
            let planned = try #require(formatter.date(from: start))
            let deadline = try #require(rules.deadline(before: planned))
            #expect(formatter.string(from: deadline) == expected)
            #expect(planned.timeIntervalSince(deadline) == 24 * 3600)
        }
    }

    @Test func unknownAndNoFeeRulesNeverInventADeadline() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SchoolIndividualCancellationRules(cancellationHours: nil, lateAction: .contact).deadline(before: start) == nil)
        #expect(SchoolIndividualCancellationRules(cancellationHours: 24, lateAction: .noFee).deadline(before: start) == nil)
        #expect(SchoolIndividualCancellationRules(cancellationHours: 0, lateAction: .contact).deadline(before: start) == start)
    }

    @Test func legacyPolicyWithoutStructuredRulesStillDecodes() throws {
        let json = """
        {"id":"11111111-1111-4111-8111-111111111111","schoolId":"22222222-2222-4222-8222-222222222222","version":1,"categoryCode":"B","procedureText":"Déroulement","cancellationPolicyText":"Ancien texte de 24 heures","sourceUrls":[],"approved":true,"approvedAt":"2026-10-28T10:00:00Z"}
        """
        let policy = try JSONDecoder().decode(SchoolCatalogPolicy.self, from: Data(json.utf8))
        #expect(policy.cancellationRules == nil)
    }
}
