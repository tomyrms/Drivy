import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolLessonWishReactivityTests {
    @Test func verifyingAWishReceiptKeepsTheNextRevisionWithoutAFalseConflict() async throws {
        let server = WishReceiptServer()
        let member = SchoolMembership(membershipId: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID,
            schoolName: "École synthétique", roles: ["LEARNER"], grants: [], accessEpoch: 1)
        let client = SchoolLessonReportClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        let model = SchoolLessonReportWorkspace(scope: ConfigurationFixture.scope(), membership: member,
            lessonID: HubFixture.lessonID, client: client, outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(model.isOwnLearner && model.canMutate)
        _ = try #require(model.wish, "La fixture doit fournir un souhait décodable avant de vérifier sa reprise.")
        model.wishText = "Souhait envoyé"
        let sending = Task { await model.saveWish() }
        try await HubFixture.wait { await server.holdsPut() }
        let isHeld = await server.holdsPut()
        try #require(isHeld, "La première écriture doit être réellement suspendue avant la saisie suivante.")
        model.wishText = "Souhait suivant"
        await server.releasePut()
        await sending.value
        #expect(model.pending != nil && !model.acceptsInput)
        await server.allowReceipt()
        await model.verifyPending()
        #expect(model.pending == nil && model.wishText == "Souhait suivant")
        #expect(model.wish?.text == "Souhait envoyé" && model.wish?.version == 2)
        #expect(model.wishChanged && !model.needsReload && model.canMutate)
    }
}

/// Compte élève autorisé, écriture retenue puis reçue ; le premier accès au reçu échoue.
private actor WishReceiptServer: SchoolHTTPTransport {
    private let fallback = HubServer()
    private let wishID = UUID(uuidString: "70000000-0000-4000-8000-000000000091")!
    private var text = "", version = 1
    private var operation: UUID?
    private var holding = false, receiptAvailable = false
    private var waiter: CheckedContinuation<Void, Never>?

    func holdsPut() -> Bool { holding }
    func releasePut() { waiter?.resume(); waiter = nil }
    func allowReceipt() { receiptAvailable = true }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!, parts = url.pathComponents.map { $0.lowercased() }
        func ok(_ value: [String: Any]) throws -> SchoolHTTPResponse {
            .init(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": "70000000-0000-4000-8000-000000000092",
                "serverTime": "2026-09-28T13:30:00Z"]), status: 200, url: url, contentType: "application/json")
        }
        if parts.last == "me" {
            return try ok(["personId": ConfigurationFixture.personID.uuidString, "version": 1,
                "displayName": "Élève synthétique", "locale": "fr", "memberships": [
                    ["membershipId": ConfigurationFixture.membershipID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                     "schoolName": "École synthétique", "roles": ["LEARNER"], "grants": [] as [String], "accessEpoch": 1] as [String: Any]]])
        }
        if parts.suffix(2) == ["learners", HubFixture.learnerID.uuidString.lowercased()] {
            return try ok(["id": HubFixture.learnerID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "personId": ConfigurationFixture.personID.uuidString, "version": 1, "displayName": "Élève synthétique",
                "contactEmail": NSNull(), "contactPhone": NSNull(), "archivedAt": NSNull()])
        }
        if parts.last == "wish" {
            if request.httpMethod == "PUT" {
                let body = try JSONDecoder().decode(SchoolSaveWish.self, from: request.httpBody ?? Data())
                holding = true
                await withCheckedContinuation { waiter = $0 }
                holding = false
                operation = body.operationId; text = body.text; version = 2
                return try ok([:])
            }
            return try ok(["id": wishID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                "trainingId": HubFixture.trainingID.uuidString, "version": version, "lessonId": NSNull(), "text": text])
        }
        if parts.dropLast().last == "operations", let operation, parts.last == operation.uuidString.lowercased() {
            guard receiptAvailable else {
                return .init(data: Data("{\"code\":\"UNAVAILABLE\",\"title\":\"Indisponible\"}".utf8),
                    status: 503, url: url, contentType: "application/problem+json")
            }
            return try ok(["operationId": operation.uuidString, "commandType": SchoolCommandKind.saveWish.operationType,
                "resourceType": SchoolCommandKind.saveWish.resourceType, "resourceId": wishID.uuidString,
                "committedAt": "2026-09-28T13:30:00Z", "resourceVersion": version])
        }
        return try await fallback.send(request)
    }
}
