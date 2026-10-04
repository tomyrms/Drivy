import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolPlanningBookingTests {
    @Test func bookingConfirmsCurrentVersionsOnlyOnSaveAndRetainsThemForRetry() async throws {
        let server = PlanningBookingServer(receiptAvailable: false), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        model.quantity = 2
        await model.validateSlot()
        try #require(model.validBooking)
        let product = try #require(model.selectedProduct)
        let terms = try #require(model.selectedTerms)
        let policy = try #require(model.selectedPolicy)
        #expect(outbox.saves.isEmpty && model.pending == nil)
        #expect(await server.writes().isEmpty)

        #expect(await model.saveBooking() == false)
        let pending = try #require(model.pending)
        let body = try #require(JSONSerialization.jsonObject(with: pending.body) as? [String: Any])
        let selection = try #require(body["commercialSelection"] as? [String: Any])
        #expect(pending.kind == .createLesson && pending.routeResourceID == HubFixture.trainingID)
        #expect(body["policyVersionId"] as? String == policy.id.uuidString)
        #expect(body["agreedPriceCents"] as? Int64 == product.unitPriceCents * 2)
        #expect(selection["serviceProductVersionId"] as? String == product.id.uuidString)
        #expect(selection["acceptedTermsVersionId"] as? String == terms.id.uuidString)
        #expect(selection["quantity"] as? Int == 2)
        #expect(body["termsAccepted"] == nil && body["agreementConfirmed"] == nil)
        #expect(outbox.value == pending && model.successMessage == nil && !model.validBooking)

        // Même une modification locale ne remplace pas la commande au résultat encore inconnu.
        model.quantity = 3
        #expect(await model.saveBooking() == false)
        #expect(model.pending == pending)
        #expect(await server.writes().count == 1)
        await server.enableReceipt()
        #expect(await model.retry())
        let writes = await server.writes()
        #expect(writes.count == 2)
        #expect(writes.allSatisfy { $0.httpBody == pending.body && $0.value(forHTTPHeaderField: "Idempotency-Key") == pending.id.uuidString })
        #expect(model.pending == nil && outbox.value == nil && model.successMessage != nil)
    }

    @Test(arguments: ["product-expired", "terms-expired", "terms-unapproved", "product-superseded"])
    func invalidCommercialReferencesStillBlockBooking(_ restriction: String) async throws {
        let server = PlanningBookingServer(restriction: restriction)
        let model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        // Une référence devenue invalide ne passe pas même si un ancien choix est encore fourni.
        model.productID = PlanningDefaultsServer.productID
        await model.validateSlot()
        #expect(!model.validBooking)
        #expect(await model.saveBooking() == false)
        #expect(await server.writes().isEmpty)
    }

    @Test(arguments: ["product-deadline", "terms-deadline"])
    func changingDatePastCommercialValidityRequiresAnotherValidTariff(_ restriction: String) async throws {
        let date = Date().addingTimeInterval(86_400)
        let server = PlanningBookingServer(restriction: restriction,
            deadline: SchoolCatalogFormatting.civilDate(date, timeZone: "Europe/Zurich"))
        let model = workspace(server, date: date)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.validateSlot()
        try #require(model.validBooking)
        model.startsAt = model.startsAt.addingTimeInterval(172_800)
        #expect(model.productID == nil && !model.validBooking)
        #expect(await model.saveBooking() == false)
        #expect(await server.writes().isEmpty)
    }

    @Test(arguments: ["COMMERCIAL_SELECTION_INVALID", "SCHOOL_POLICY_CHANGED", "SLOT_CONFLICT"])
    func rejectedBookingRequiresReloadBeforeAnotherConfirmation(_ code: String) async throws {
        let server = PlanningBookingServer(rejection: code), outbox = ConfigurationOutboxStub()
        let model = workspace(server, outbox: outbox)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.validateSlot()
        try #require(model.validBooking)
        #expect(await model.saveBooking() == false)
        #expect(model.needsReload && model.errorMessage != nil && model.successMessage == nil)
        #expect(model.pending == nil && outbox.value == nil)
        #expect(await model.saveBooking() == false)
        #expect(await server.writes().count == 1)
    }

    @Test func movingKeepsItsSeparateAgreementAndCommercialReason() async throws {
        let server = PlanningBookingServer()
        let model = workspace(server, lesson: HubFixture.lesson())
        await model.load()
        model.startsAt = Date().addingTimeInterval(86_400)
        await model.validateSlot()
        try #require(model.canMutate && model.selectedTraining != nil)
        #expect(!model.validBooking)
        model.agreementConfirmed = true
        #expect(model.validBooking)
        model.changesCommercialTerms = true
        #expect(!model.agreementConfirmed && !model.validBooking)
        model.agreementConfirmed = true
        #expect(!model.validBooking)
        model.reason = "Durée convenue avec l’élève"
        #expect(model.validBooking)
        model.quantity = 2
        #expect(!model.agreementConfirmed && !model.validBooking)
        model.agreementConfirmed = true
        await model.validateSlot()
        try #require(model.validBooking)
        let version = try #require(model.originalLesson?.version)
        #expect(await server.writes().isEmpty)
        #expect(await model.saveBooking())
        let sent = try #require(await server.writes().first)
        let body = try #require(JSONSerialization.jsonObject(with: try #require(sent.httpBody)) as? [String: Any])
        let change = try #require(body["commercialChange"] as? [String: Any])
        #expect(sent.value(forHTTPHeaderField: "If-Match") == "\"\(version)\"")
        #expect(body["agreementConfirmed"] as? Bool == true)
        #expect(change["reason"] as? String == "Durée convenue avec l’élève")
    }

    private func workspace(_ server: PlanningBookingServer, outbox: ConfigurationOutboxStub? = nil,
                           date: Date = Date().addingTimeInterval(86_400), lesson: SchoolLesson? = nil) -> SchoolPlanningWorkspace {
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        return SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client, date: date, lesson: lesson, outbox: outbox ?? ConfigurationOutboxStub())
    }
}

/// Transport synthétique : vérifie la commande client, sans prétendre qualifier les transactions PostgreSQL.
private actor PlanningBookingServer: SchoolHTTPTransport {
    private let fallback = PlanningDefaultsServer()
    private let restriction: String?
    private let deadline: String?
    private let rejection: String?
    private var receiptAvailable: Bool
    private var operationID: String?
    private var operationType = "CREATE_LESSON"
    private var recorded: [URLRequest] = []

    init(receiptAvailable: Bool = true, restriction: String? = nil, deadline: String? = nil, rejection: String? = nil) {
        self.receiptAvailable = receiptAvailable; self.restriction = restriction; self.deadline = deadline; self.rejection = rejection
    }
    func writes() -> [URLRequest] { recorded.filter { $0.httpMethod != "GET" } }
    func enableReceipt() { receiptAvailable = true }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        recorded.append(request)
        let url = request.url!
        func reply(_ value: Any, status: Int = 200) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": ISO8601DateFormatter().string(from: Date())]), status: status, url: url, contentType: "application/json")
        }
        if request.httpMethod == "POST", ["lessons", "move"].contains(url.lastPathComponent) {
            if let rejection {
                return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["code": rejection]),
                    status: rejection == "SLOT_CONFLICT" ? 409 : 422, url: url, contentType: "application/problem+json")
            }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            operationID = body["operationId"] as? String
            operationType = url.lastPathComponent == "move" ? "MOVE_LESSON" : "CREATE_LESSON"
            return try reply([:], status: operationType == "CREATE_LESSON" ? 201 : 200)
        }
        if url.deletingLastPathComponent().lastPathComponent == "operations", let operationID {
            guard receiptAvailable else { throw URLError(.notConnectedToInternet) }
            return try reply(["operationId": operationID, "commandType": operationType, "resourceType": "Lesson",
                "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": 2,
                "committedAt": ISO8601DateFormatter().string(from: Date())])
        }
        let response = try await fallback.send(request)
        guard let restriction, ["service-products", "commercial-terms"].contains(url.lastPathComponent) else { return response }
        var envelope = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
        var page = envelope["data"] as! [String: Any]
        page["items"] = (page["items"] as! [[String: Any]]).map { original in
            var item = original
            if url.lastPathComponent == "service-products" {
                if restriction == "product-expired" { item["validUntil"] = "2000-01-01" }
                if restriction == "product-deadline" { item["validUntil"] = deadline }
                if restriction == "product-superseded" { item["current"] = false }
            } else {
                if restriction == "terms-expired" { item["validUntil"] = "2000-01-01" }
                if restriction == "terms-deadline" { item["validUntil"] = deadline }
                if restriction == "terms-unapproved" { item["approved"] = false }
            }
            return item
        }
        envelope["data"] = page
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: response.status,
            url: url, contentType: response.contentType)
    }
}
