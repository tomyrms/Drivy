import Foundation
import Testing
@testable import Drivy

/// Examens d'une formation (#54) : contrat de `apps/api/src/exams.ts`, sans réseau.
@MainActor struct SchoolExamTests {
    private let trainingID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let examID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let instructorID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private func examJSON(kind: String = "PRACTICAL", status: String = "SCHEDULED", needsResult: Bool = false, attempt: String = "1",
                          note: String = "", escort: Bool = false) -> String {
        let escortValue = escort
            ? "{\"instructorMembershipId\":\"\(instructorID.uuidString.lowercased())\",\"startsAt\":\"2030-03-04T08:00:00.000Z\",\"endsAt\":\"2030-03-04T10:00:00.000Z\"}"
            : "null"
        let recorded = ["PASSED", "FAILED", "ABSENT"].contains(status) ? "\"2030-03-04T12:00:00.000Z\"" : "null"
        return """
        {"id":"\(examID.uuidString.lowercased())","trainingId":"\(trainingID.uuidString.lowercased())","kind":"\(kind)","categoryCode":"B","status":"\(status)",
         "startsAt":"2030-03-04T09:00:00.000Z","timeZone":"Europe/Zurich","location":"Centre d’examen","escort":\(escortValue),"resultNote":"\(note)",
         "resultRecordedAt":\(recorded),"postponedToExamId":null,"attempt":\(attempt),"needsResult":\(needsResult),"version":2,"createdAt":"2030-03-01T08:00:00.000Z"}
        """
    }

    private func stateJSON(exams: [String], canManage: Bool = true, theory: String = "false,0,null", practical: String = "false,1,null") -> Data {
        func summary(_ kind: String, _ values: String) -> String {
            let parts = values.split(separator: ",").map(String.init)
            return "{\"kind\":\"\(kind)\",\"passed\":\(parts[0]),\"attempts\":\(parts[1]),\"scheduledExamId\":\(parts[2])}"
        }
        return Data("""
        {"trainingId":"\(trainingID.uuidString.lowercased())","canManage":\(canManage),"exams":[\(exams.joined(separator: ","))],
         "summary":[\(summary("THEORY", theory)),\(summary("PRACTICAL", practical))]}
        """.utf8)
    }

    @Test func decodesAScheduledExamWithItsEscort() throws {
        let state = try JSONDecoder().decode(SchoolExamState.self, from: stateJSON(exams: [examJSON(escort: true)]))
        let exam = try #require(state.exams.first)
        #expect(exam.examKind == .practical)
        #expect(exam.examStatus == .scheduled)
        #expect(exam.attempt == 1)
        #expect(exam.escort?.instructorMembershipId == instructorID)
        #expect(exam.date != nil)
        #expect(exam.hasResult == false)
        #expect(state.canManage)
    }

    @Test func aPastDateStaysWaitingForItsResultAndIsNeverAResult() throws {
        let state = try JSONDecoder().decode(SchoolExamState.self, from: stateJSON(exams: [examJSON(needsResult: true)]))
        let exam = try #require(state.exams.first)
        #expect(exam.needsResult)
        #expect(exam.examStatus == .scheduled)
        #expect(exam.hasResult == false)
    }

    @Test func aFailedExamKeepsItsNoteForTheLearner() throws {
        let state = try JSONDecoder().decode(SchoolExamState.self,
            from: stateJSON(exams: [examJSON(status: "FAILED", note: "Priorités à droite")], canManage: false))
        let exam = try #require(state.exams.first)
        #expect(exam.hasResult)
        #expect(exam.resultNote == "Priorités à droite")
        #expect(state.canManage == false)
    }

    @Test func aPostponedExamHasNoAttemptRank() throws {
        let state = try JSONDecoder().decode(SchoolExamState.self, from: stateJSON(exams: [examJSON(status: "POSTPONED", attempt: "null")]))
        #expect(state.exams.first?.attempt == nil)
        #expect(state.exams.first?.hasResult == false)
    }

    @Test func aTestIsOfferedUntilItIsPassedOrAlreadyScheduled() throws {
        let scheduled = "false,1,\"\(examID.uuidString.lowercased())\""
        let state = try JSONDecoder().decode(SchoolExamState.self, from: stateJSON(exams: [], theory: "true,1,null", practical: scheduled))
        #expect(state.canSchedule(.theory) == false)
        #expect(state.canSchedule(.practical) == false)
        let open = try JSONDecoder().decode(SchoolExamState.self, from: stateJSON(exams: [], theory: "false,0,null", practical: "false,2,null"))
        #expect(open.canSchedule(.theory))
        #expect(open.canSchedule(.practical))
    }

    @Test func scheduleKeyChangesWithTheEntryAndNotWithTheClock() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        let first = SchoolExamSchedule(startsAt: date, timeZone: "Europe/Zurich", location: "Salle 1", escort: nil)
        var second = first; second.location = "Salle 2"
        #expect(first.key == SchoolExamSchedule(startsAt: date, timeZone: "Europe/Zurich", location: "Salle 1", escort: nil).key)
        #expect(first.key != second.key)
    }

    @Test func examRefusalsHaveTheirOwnWording() {
        #expect(SchoolExamClient.failure(409, "EXAM_ALREADY_PASSED") == .rejected("Cette épreuve est déjà réussie. Corrige d’abord son résultat pour la replanifier."))
        #expect(SchoolExamClient.failure(422, "EXAM_REASON_REQUIRED") == .rejected("Indique le motif de la correction."))
        #expect(SchoolExamClient.failure(403, nil) == .forbidden)
        #expect(SchoolExamClient.failure(503, nil) == .unavailable)
    }
}
