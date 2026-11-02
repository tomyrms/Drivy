import Foundation
import Testing
@testable import Drivy

/// Prochaine étape après un résultat d'examen (#54) : toujours une suggestion au personnel, jamais une clôture automatique.
@MainActor struct SchoolExamNextStepTests {
    private let trainingID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let examID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private func summary(_ kind: String, passed: Bool, attempts: Int, scheduled: Bool = false) -> String {
        let scheduledValue = scheduled ? "\"\(examID.uuidString.lowercased())\"" : "null"
        return "{\"kind\":\"\(kind)\",\"passed\":\(passed),\"attempts\":\(attempts),\"scheduledExamId\":\(scheduledValue)}"
    }

    private func exam(kind: String = "PRACTICAL", status: String, startsAt: String = "2030-03-04T09:00:00.000Z", attempt: String = "1") -> String {
        let recorded = ["PASSED", "FAILED", "ABSENT"].contains(status) ? "\"2030-03-04T12:00:00.000Z\"" : "null"
        return """
        {"id":"\(UUID().uuidString.lowercased())","trainingId":"\(trainingID.uuidString.lowercased())","kind":"\(kind)","categoryCode":"B","status":"\(status)",
         "startsAt":"\(startsAt)","timeZone":"Europe/Zurich","location":"","escort":null,"resultNote":"","resultRecordedAt":\(recorded),"postponedToExamId":null,
         "attempt":\(attempt),"needsResult":false,"version":1,"createdAt":"2030-03-01T08:00:00.000Z"}
        """
    }

    private func step(_ theory: String, _ practical: String, exams: [String] = []) throws -> SchoolExamNextStep? {
        let json = Data("""
        {"trainingId":"\(trainingID.uuidString.lowercased())","canManage":true,"escortCandidates":[],"exams":[\(exams.joined(separator: ","))],
         "summary":[\(theory),\(practical)]}
        """.utf8)
        return try JSONDecoder().decode(SchoolExamState.self, from: json).nextStep
    }

    @Test func bothPassedProposeClosingWithoutClosingAnything() throws {
        let result = try step(summary("THEORY", passed: true, attempts: 1), summary("PRACTICAL", passed: true, attempts: 2))
        #expect(result?.kind == .close)
        #expect(result?.text.contains("rien n’est clos automatiquement") == true)
    }

    @Test func aPassedTheoryProposesThePracticalUntilItHasAnAttemptOrADate() throws {
        let theory = summary("THEORY", passed: true, attempts: 1)
        #expect(try step(theory, summary("PRACTICAL", passed: false, attempts: 0))?.kind == .schedulePractical)
        #expect(try step(theory, summary("PRACTICAL", passed: false, attempts: 0, scheduled: true)) == nil)
    }

    @Test func aFailureOrAnAbsenceWithoutANewDateProposesANewDate() throws {
        let theory = summary("THEORY", passed: true, attempts: 1), practical = summary("PRACTICAL", passed: false, attempts: 1)
        let failed = try step(theory, practical, exams: [exam(status: "FAILED")])
        #expect(failed?.kind == .scheduleAgain)
        #expect(failed?.text == "Examen échoué : prévoir une nouvelle date pour l’examen pratique.")
        #expect(try step(theory, practical, exams: [exam(status: "ABSENT")])?.text.hasPrefix("Absence à l’examen") == true)
    }

    @Test func aPostponementIsNeitherAFailureNorAnAbsence() throws {
        let theory = summary("THEORY", passed: true, attempts: 1), practical = summary("PRACTICAL", passed: false, attempts: 1)
        #expect(try step(theory, practical, exams: [exam(status: "POSTPONED", attempt: "null")]) == nil)
        #expect(try step(summary("THEORY", passed: false, attempts: 0), summary("PRACTICAL", passed: false, attempts: 0)) == nil)
    }

    @Test func theLatestAttemptDecidesNotTheFirstOne() throws {
        let theory = summary("THEORY", passed: true, attempts: 1), practical = summary("PRACTICAL", passed: false, attempts: 2)
        let earlierFailure = exam(status: "FAILED", startsAt: "2030-01-10T09:00:00.000Z", attempt: "1")
        let laterAbsence = exam(status: "ABSENT", startsAt: "2030-03-10T09:00:00.000Z", attempt: "2")
        #expect(try step(theory, practical, exams: [earlierFailure, laterAbsence])?.text.hasPrefix("Absence à l’examen") == true)
    }
}
