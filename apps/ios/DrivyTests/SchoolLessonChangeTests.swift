import Foundation
import Testing
@testable import Drivy

/// Demandes de l'élève sur sa leçon (#52) : contrat de `apps/api/src/lesson-change-requests.ts`, sans réseau.
@MainActor struct SchoolLessonChangeTests {
    private let lessonID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let requestID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let policyID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private func stateJSON(status: String, kind: String = "RESCHEDULE", blocked: String? = nil, resolution: String? = nil, late: Bool? = false) -> Data {
        let blockedValue = blocked.map { "\"\($0)\"" } ?? "null"
        let resolutionValue = resolution.map { "\"\($0)\"" } ?? "null"
        let lateValue = late.map { $0 ? "true" : "false" } ?? "null"
        let deadline = late == nil ? "null" : "\"2030-03-03T17:00:00.000Z\""
        let resolvedAt = status == "PENDING" ? "null" : "\"2030-03-02T09:00:00.000Z\""
        return Data("""
        {"lessonId":"\(lessonID.uuidString.lowercased())",
         "conditions":{"policyVersionId":"\(policyID.uuidString.lowercased())","policyVersion":2,"cancellationPolicyText":"Prévenez l’école 24 heures avant.",
          "cancellationHours":24,"lateAction":"CONTACT","deadlineAt":\(deadline),"late":\(lateValue),"canRequest":\(blocked == nil),"blockedReason":\(blockedValue)},
         "requests":[{"id":"\(requestID.uuidString.lowercased())","lessonId":"\(lessonID.uuidString.lowercased())","kind":"\(kind)","status":"\(status)",
          "note":"Mardi après 17 h","mine":true,"late":\(lateValue),"deadlineAt":\(deadline),"cancellationHours":24,
          "policyVersionId":"\(policyID.uuidString.lowercased())","resolvedAt":\(resolvedAt),"resolutionNote":\(resolutionValue),"version":1,
          "createdAt":"2030-03-01T08:00:00.000Z"}]}
        """.utf8)
    }

    @Test func decodesAPendingRequestAndItsConditions() throws {
        let state = try JSONDecoder().decode(SchoolLessonChangeState.self, from: stateJSON(status: "PENDING", blocked: "REQUEST_PENDING"))
        #expect(state.lessonId == lessonID)
        #expect(state.pending?.id == requestID)
        #expect(state.pending?.requestKind == .reschedule)
        #expect(state.pending?.mine == true)
        #expect(state.lastClosed == nil)
        #expect(state.conditions.canRequest == false)
        #expect(state.conditions.blockedReason == "REQUEST_PENDING")
        #expect(state.conditions.cancellationHours == 24)
        #expect(state.conditions.deadline != nil)
    }

    @Test func aRefusedRequestIsTheLastClosedOneWithItsReason() throws {
        let state = try JSONDecoder().decode(SchoolLessonChangeState.self,
            from: stateJSON(status: "REFUSED", kind: "CANCEL", resolution: "Ce créneau est déjà pris"))
        #expect(state.pending == nil)
        #expect(state.lastClosed?.requestStatus == .refused)
        #expect(state.lastClosed?.requestKind == .cancel)
        #expect(state.lastClosed?.resolutionNote == "Ce créneau est déjà pris")
        #expect(state.conditions.canRequest)
    }

    @Test func aSchoolWithoutDeadlineAssumesNothing() throws {
        let state = try JSONDecoder().decode(SchoolLessonChangeState.self, from: stateJSON(status: "WITHDRAWN", late: nil))
        #expect(state.requests.first?.late == nil)
        #expect(state.requests.first?.deadline == nil)
        #expect(state.conditions.late == nil)
        #expect(state.conditions.deadline == nil)
    }

    @Test func anUnknownKindOrStatusFromANewerServerIsNeitherPendingNorCrashing() throws {
        let state = try JSONDecoder().decode(SchoolLessonChangeState.self, from: stateJSON(status: "ON_HOLD", kind: "SWAP"))
        #expect(state.requests.first?.requestKind == nil)
        #expect(state.requests.first?.requestStatus == nil)
        #expect(state.pending == nil)
    }

    @Test func requestRefusalsHaveTheirOwnWording() {
        let known = SchoolLessonChangeClient.failure(409, "LESSON_CHANGE_REQUEST_PENDING")
        #expect(known == .rejected("Une demande est déjà en attente pour cette leçon."))
        #expect(SchoolLessonChangeClient.failure(404, nil) == .notFound)
        #expect(SchoolLessonChangeClient.failure(503, nil) == .unavailable)
    }
}
