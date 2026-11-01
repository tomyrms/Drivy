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
        {"trainingId":"\(trainingID.uuidString.lowercased())","canManage":\(canManage),
         "escortCandidates":[{"membershipId":"\(instructorID.uuidString.lowercased())","displayName":"Camille Exemple"}],"exams":[\(exams.joined(separator: ","))],
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

    // MARK: Gestes conservés dans la file chiffrée

    private let scope = SchoolCommandScope(personID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
        schoolID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!, membershipID: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
        accessEpoch: 3, apiBaseURL: "https://drivy.example.invalid")

    private func command(_ kind: SchoolCommandKind, version: Int, resource: UUID?, route: UUID?, expected: Int? = nil) -> PendingSchoolCommand {
        let id = UUID()
        let body = Data("{\"operationId\":\"\(id.uuidString.lowercased())\"}".utf8)
        return PendingSchoolCommand(id: id, scope: scope, kind: kind, resourceVersion: version, createdAt: Date(), body: body,
            resourceID: resource, routeResourceID: route, expectedVersion: expected)
    }

    @Test func examCommandsHaveAValidTargetOnlyWithTheirTrainingAndExam() {
        #expect(command(.createExam, version: 0, resource: nil, route: trainingID).hasValidTarget)
        #expect(command(.createExam, version: 0, resource: nil, route: nil).hasValidTarget == false)
        #expect(command(.createExam, version: 2, resource: nil, route: trainingID).hasValidTarget == false)
        for kind in [SchoolCommandKind.updateExam, .postponeExam, .setExamResult] {
            #expect(command(kind, version: 2, resource: examID, route: trainingID).hasValidTarget)
            #expect(command(kind, version: 0, resource: examID, route: trainingID).hasValidTarget == false)
            #expect(command(kind, version: 2, resource: nil, route: trainingID).hasValidTarget == false)
            #expect(command(kind, version: 2, resource: examID, route: trainingID, expected: 2).hasValidTarget == false)
        }
    }

    @Test func examCommandsAreTeachingCommandsNeverConfiguration() {
        for kind in [SchoolCommandKind.createExam, .updateExam, .postponeExam, .setExamResult] {
            #expect(kind.isExam)
            #expect(kind.isConfiguration == false)
            #expect(kind.isPlanning == false)
            #expect(kind.schedulingDomain == .teaching)
            #expect(kind.resourceType == "Exam")
        }
        #expect(SchoolCommandKind.createExam.operationType == "CREATE_EXAM")
        #expect(SchoolCommandKind.updateExam.operationType == "UPDATE_EXAM")
        #expect(SchoolCommandKind.postponeExam.operationType == "POSTPONE_EXAM")
        #expect(SchoolCommandKind.setExamResult.operationType == "SET_EXAM_RESULT")
    }

    @Test func aReceiptSettlesAnExamCommandOnlyForItsOperationAndANewerVersion() {
        let update = command(.updateExam, version: 2, resource: examID, route: trainingID)
        func receipt(_ operation: UUID, _ type: String, _ resource: UUID, _ version: Int) -> SchoolOperationReceipt {
            let json = "{\"operationId\":\"\(operation.uuidString.lowercased())\",\"commandType\":\"\(type)\",\"resourceType\":\"Exam\","
                + "\"resourceId\":\"\(resource.uuidString.lowercased())\",\"committedAt\":\"2030-03-04T12:00:00.000Z\",\"resourceVersion\":\(version)}"
            return try! JSONDecoder().decode(SchoolOperationReceipt.self, from: Data(json.utf8))
        }
        #expect(update.matches(receipt(update.id, "UPDATE_EXAM", examID, 3)))
        #expect(update.matches(receipt(update.id, "UPDATE_EXAM", examID, 2)) == false)
        #expect(update.matches(receipt(update.id, "SET_EXAM_RESULT", examID, 3)) == false)
        #expect(update.matches(receipt(UUID(), "UPDATE_EXAM", examID, 3)) == false)
        #expect(update.matches(receipt(update.id, "UPDATE_EXAM", UUID(), 3)) == false)
    }

    @Test func examBodiesCarryOnlyTheFieldsTheirRouteAccepts() throws {
        let operation = UUID(), date = Date(timeIntervalSince1970: 1_900_000_000)
        let schedule = SchoolExamSchedule(startsAt: date, timeZone: "Europe/Zurich", location: "Salle 1",
            escort: .init(instructorMembershipID: instructorID, startsAt: date.addingTimeInterval(-3_600), endsAt: date.addingTimeInterval(3_600)))
        func keys(_ body: SchoolExamBody) throws -> Set<String> {
            Set(try #require(try JSONSerialization.jsonObject(with: try body.encoded()) as? [String: Any]).keys)
        }
        #expect(try keys(.create(operationID: operation, kind: .theory, schedule: schedule)) == ["operationId", "kind", "startsAt", "timeZone", "location", "escort"])
        #expect(try keys(.reschedule(operationID: operation, schedule: schedule, reason: "Convocation")) == ["operationId", "reason", "startsAt", "timeZone", "location", "escort"])
        #expect(try keys(.result(operationID: operation, result: .failed, note: "Priorités", reason: "")) == ["operationId", "result", "note", "reason"])
        let withoutEscort = SchoolExamSchedule(startsAt: date, timeZone: "Europe/Zurich", location: "", escort: nil)
        #expect(try keys(.create(operationID: operation, kind: .practical, schedule: withoutEscort)) == ["operationId", "kind", "startsAt", "timeZone", "location"])
    }

    @Test func examRefusalsHaveTheirOwnWording() {
        #expect(SchoolExamClient.failure(409, "EXAM_ALREADY_PASSED") == .rejected("Cette épreuve est déjà réussie. Corrige d’abord son résultat pour la replanifier."))
        #expect(SchoolExamClient.failure(422, "EXAM_REASON_REQUIRED") == .rejected("Indique le motif de la correction."))
        #expect(SchoolExamClient.failure(403, nil) == .forbidden)
        #expect(SchoolExamClient.failure(503, nil) == .unavailable)
    }
}
