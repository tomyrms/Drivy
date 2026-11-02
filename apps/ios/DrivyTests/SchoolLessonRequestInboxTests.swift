import Foundation
import Testing
@testable import Drivy

/// Boîte des demandes d'élèves (#52) pour le personnel : l'élève est nommé et identifié pour ouvrir son dossier, sans réseau.
@MainActor struct SchoolLessonRequestInboxTests {
    private let learnerID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private let lessonID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let requestID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let membershipID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private struct Page: Decodable { let items: [SchoolLessonChangeInboxItem] }

    private func inbox(kind: String = "RESCHEDULE", late: String = "false") -> Data {
        Data("""
        {"items":[{"request":{"id":"\(requestID.uuidString.lowercased())","lessonId":"\(lessonID.uuidString.lowercased())","kind":"\(kind)","status":"PENDING",
         "note":"Plutôt jeudi","mine":false,"late":\(late),"deadlineAt":null,"cancellationHours":24,"policyVersionId":null,"resolvedAt":null,"resolutionNote":null,
         "version":1,"createdAt":"2030-03-01T08:00:00.000Z"},
         "lesson":{"id":"\(lessonID.uuidString.lowercased())","plannedStart":"2030-03-04T09:00:00.000Z","plannedEnd":"2030-03-04T09:50:00.000Z",
         "timeZone":"Europe/Zurich","version":2,"instructorMembershipId":"\(membershipID.uuidString.lowercased())",
         "learnerId":"\(learnerID.uuidString.lowercased())","learnerDisplayName":"Camille Exemple"}}]}
        """.utf8)
    }

    @Test func theInboxNamesTheLearnerSoTheirDossierCanOpen() throws {
        let item = try #require(try JSONDecoder().decode(Page.self, from: inbox()).items.first)
        #expect(item.lesson.learnerId == learnerID)
        #expect(item.lesson.learnerDisplayName == "Camille Exemple")
        #expect(item.id == requestID)
        #expect(item.request.isPending)
        #expect(item.request.requestKind == .reschedule)
        #expect(item.request.mine == false)
    }

    @Test func aLateCancellationRequestKeepsItsKindAndLateness() throws {
        let item = try #require(try JSONDecoder().decode(Page.self, from: inbox(kind: "CANCEL", late: "true")).items.first)
        #expect(item.request.requestKind == .cancel)
        #expect(item.request.late == true)
    }

    @Test func anInboxWithoutALearnerIdIsRefusedNotGuessed() {
        let broken = String(decoding: inbox(), as: UTF8.self).replacingOccurrences(of: "\"learnerId\"", with: "\"someoneElse\"")
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Page.self, from: Data(broken.utf8)) }
    }
}
