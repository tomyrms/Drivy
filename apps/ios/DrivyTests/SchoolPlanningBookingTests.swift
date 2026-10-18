import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolPlanningBookingTests {
    @Test func confirmedCreateExposesTheServerLessonOnlyAfterItsReceiptAndRead() async throws {
        let server = PlanningBookingServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.validateSlot()
        try #require(model.validBooking)

        #expect(model.confirmedLesson == nil)
        #expect(await model.saveBooking())
        let confirmed = try #require(model.confirmedLesson)
        #expect(confirmed.id == HubFixture.lessonID)
        #expect(confirmed.version == 2)
        #expect(abs((confirmed.startsAt?.timeIntervalSince1970 ?? 0) - model.startsAt.timeIntervalSince1970) < 1)
        #expect(!confirmed.hasStarted)
        #expect(await server.operationReads() == 1)
    }

    @Test func confirmedMoveExposesTheRereadServerVersionAndNeverAutoStarts() async throws {
        let server = PlanningBookingServer(), model = workspace(server, lesson: HubFixture.lesson())
        await model.load()
        model.startsAt = Date().addingTimeInterval(86_400)
        model.agreementConfirmed = true
        await model.validateSlot()
        try #require(model.validBooking)

        #expect(await model.saveBooking())
        let confirmed = try #require(model.confirmedLesson)
        #expect(confirmed.id == HubFixture.lessonID)
        #expect(confirmed.version == 3)
        #expect(abs((confirmed.startsAt?.timeIntervalSince1970 ?? 0) - model.startsAt.timeIntervalSince1970) < 1)
        #expect(!confirmed.hasStarted)
    }

    @Test func unknownOrRejectedBookingNeverExposesALesson() async throws {
        let uncertain = workspace(PlanningBookingServer(receiptAvailable: false))
        await uncertain.load()
        await uncertain.selectLearner(HubFixture.learnerID)
        await uncertain.validateSlot()
        #expect(await uncertain.saveBooking() == false)
        #expect(uncertain.pending != nil && uncertain.confirmedLesson == nil)

        let rejected = workspace(PlanningBookingServer(rejection: "SLOT_CONFLICT"))
        await rejected.load()
        await rejected.selectLearner(HubFixture.learnerID)
        await rejected.validateSlot()
        #expect(await rejected.saveBooking() == false)
        #expect(rejected.confirmedLesson == nil)
    }

    @Test func invalidatingWhileTheConfirmedLessonIsReadDropsTheOldScopeResult() async throws {
        let server = PlanningBookingServer(lessonReadDelayMilliseconds: 100), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.validateSlot()
        let saving = Task { await model.saveBooking() }
        var attempts = 0
        while attempts < 100, !(await server.didStartLessonRead()) {
            try await Task.sleep(for: .milliseconds(5))
            attempts += 1
        }
        #expect(await server.didStartLessonRead())
        model.invalidate()

        #expect(await saving.value == false)
        #expect(model.confirmedLesson == nil)
    }

    @Test func invalidatingVerificationDuringConfirmedReadPublishesNeitherSuccessNorNotification() async throws {
        let server = PlanningBookingServer(receiptAvailable: false, lessonReadDelayMilliseconds: 100)
        let model = workspace(server)
        await model.load(); await model.selectLearner(HubFixture.learnerID); await model.validateSlot()
        #expect(await model.saveBooking() == false)
        await server.enableReceipt()
        let notifications = PlanningNotificationCounter()
        let token = NotificationCenter.default.addObserver(forName: .drivyLessonsDidChange, object: nil, queue: nil) { _ in
            notifications.increment()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let verifying = Task { await model.verify() }
        var attempts = 0
        while attempts < 100, !(await server.didStartLessonRead()) {
            try await Task.sleep(for: .milliseconds(5)); attempts += 1
        }
        #expect(await server.didStartLessonRead())
        model.invalidate()
        await verifying.value

        #expect(model.confirmedLesson == nil)
        #expect(model.successMessage == nil)
        #expect(notifications.value == 0)
    }

    @Test func rereadAcceptsANewerCurrentVersionButRejectsAnOlderOne() async throws {
        let newer = workspace(PlanningBookingServer(lessonVersionDelta: 1))
        await newer.load(); await newer.selectLearner(HubFixture.learnerID); await newer.validateSlot()
        #expect(await newer.saveBooking())
        #expect(newer.confirmedLesson?.version == 3)

        let older = workspace(PlanningBookingServer(lessonVersionDelta: -1))
        await older.load(); await older.selectLearner(HubFixture.learnerID); await older.validateSlot()
        #expect(await older.saveBooking() == false)
        #expect(older.confirmedLesson == nil)
        #expect(older.errorMessage != nil)
    }

    @Test func forbiddenConfirmedLessonReadRevokesTheWorkspaceInsteadOfOfferingGenericRetry() async throws {
        let model = workspace(PlanningBookingServer(lessonReadStatus: 403))
        await model.load(); await model.selectLearner(HubFixture.learnerID); await model.validateSlot()

        #expect(await model.saveBooking() == false)
        #expect(model.accessRevoked)
        #expect(model.confirmedLesson == nil)
    }

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
        let payload = try #require(sent.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let change = try #require(body["commercialChange"] as? [String: Any])
        #expect(sent.value(forHTTPHeaderField: "If-Match") == "\"\(version)\"")
        #expect(body["agreementConfirmed"] as? Bool == true)
        #expect(change["reason"] as? String == "Durée convenue avec l’élève")
    }

    @Test func aSingleCompatibleTariffIsRetainedWithoutAnyChoice() async throws {
        let model = workspace(PlanningBookingServer())
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        let product = try #require(model.selectedProduct)
        #expect(product.id == PlanningDefaultsServer.productID && model.compatibleProducts.count == 1)
        #expect(model.automaticTariff?.id == product.id)
        #expect(!model.needsTariffChoice && model.tariffMessage == nil)
        #expect(model.quantity == 1 && model.quantityCovered(by: product) == 1)

        // Une durée multiple change la quantité, pas le fait qu’il n’y a rien à choisir.
        model.selectDuration(100)
        #expect(model.automaticTariff?.id == product.id && model.quantity == 2 && model.quantityCovered(by: product) == 2)
        #expect(!model.needsTariffChoice && model.tariffMessage == nil)

        let price = SchoolCatalogFormatting.price(product.unitPriceCents)
        #expect(SchoolPlanningFormat.tariff(product, quantity: 1) == "\(product.label) · \(price)")
        #expect(SchoolPlanningFormat.tariff(product, quantity: 2) == "\(product.label) · 2 × \(price)")
    }

    @Test func severalCompatibleTariffsLeaveTheChoiceToTheInstructor() async throws {
        let model = workspace(PlanningBookingServer(restriction: "second-product"))
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.validateSlot()
        #expect(model.compatibleProducts.count == 2)
        #expect(model.productID == nil && model.automaticTariff == nil && model.needsTariffChoice)
        #expect(model.tariffMessage == "Choisis un tarif." && !model.validBooking)

        model.productID = PlanningBookingServer.secondProductID
        #expect(model.tariffMessage == nil && model.automaticTariff == nil && model.needsTariffChoice)
        #expect(model.selectedPrice == 8_000 && model.validBooking)
    }

    @Test func theDefaultTariffIsPreselectedButTheChoiceStaysOpenWhenSeveralMatch() async throws {
        let model = workspace(PlanningBookingServer(restriction: "second-product-default"))
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        #expect(model.compatibleProducts.count == 2)
        #expect(model.productID == PlanningBookingServer.secondProductID)
        #expect(model.needsTariffChoice && model.automaticTariff == nil && model.tariffMessage == nil)
    }

    @Test func noCompatibleTariffIsExplainedInsteadOfOfferingAChoice() async throws {
        let model = workspace(PlanningBookingServer(restriction: "product-expired"))
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        #expect(model.compatibleProducts.isEmpty)
        #expect(model.automaticTariff == nil && !model.needsTariffChoice)
        #expect(model.tariffMessage == "Aucun tarif ne correspond à cette durée et à cette date.")
    }

    @Test func aMoveThatKeepsItsTermsNeverAsksForATariff() async throws {
        let model = workspace(PlanningBookingServer(restriction: "product-expired"), lesson: HubFixture.lesson())
        await model.load()
        try #require(model.canMutate && model.selectedTraining != nil)
        #expect(!model.changesCommercialTerms && model.tariffMessage == nil)
        model.changesCommercialTerms = true
        #expect(model.tariffMessage == "Aucun tarif ne correspond à cette durée et à cette date.")
    }

    @Test func cancellingALessonReadsOnlyTheAccountTheSchoolAndTheLesson() async throws {
        let server = PlanningBookingServer()
        let model = workspace(server, lesson: HubFixture.lesson())
        model.readsForCancellation = true
        await model.load()
        // Ni catalogue, ni préférences, ni élèves : le motif est saisissable dès ces trois lectures.
        let read = Set(await server.reads())
        #expect(read == ["me", ConfigurationFixture.schoolID.uuidString, HubFixture.lessonID.uuidString])
        #expect(model.canMutate && model.originalLesson?.id == HubFixture.lessonID)
        #expect(model.learners.isEmpty && model.products.isEmpty && model.errorMessage == nil)
    }

    private func workspace(_ server: PlanningBookingServer, outbox: ConfigurationOutboxStub? = nil,
                           date: Date = Date().addingTimeInterval(86_400), lesson: SchoolLesson? = nil) -> SchoolPlanningWorkspace {
        let client = SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!,
            tokenSource: HubToken(), transport: server)
        return SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client, date: date, lesson: lesson, outbox: outbox ?? ConfigurationOutboxStub())
    }
}

private final class PlanningNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Transport synthétique : vérifie la commande client, sans prétendre qualifier les transactions PostgreSQL.
private actor PlanningBookingServer: SchoolHTTPTransport {
    static let secondProductID = UUID(uuidString: "76000000-0000-4000-8000-000000000011")!
    static let secondProductKey = "lesson-50-reduced"
    private let fallback = PlanningDefaultsServer()
    private let restriction: String?
    private let deadline: String?
    private let rejection: String?
    private let lessonReadDelayMilliseconds: Int
    private let lessonVersionDelta: Int
    private let lessonReadStatus: Int?
    private var receiptAvailable: Bool
    private var operationID: String?
    private var operationType = "CREATE_LESSON"
    private var lessonReadStarted = false
    private var recorded: [URLRequest] = []

    init(receiptAvailable: Bool = true, restriction: String? = nil, deadline: String? = nil, rejection: String? = nil,
         lessonReadDelayMilliseconds: Int = 0, lessonVersionDelta: Int = 0, lessonReadStatus: Int? = nil) {
        self.receiptAvailable = receiptAvailable; self.restriction = restriction; self.deadline = deadline; self.rejection = rejection
        self.lessonReadDelayMilliseconds = lessonReadDelayMilliseconds; self.lessonVersionDelta = lessonVersionDelta
        self.lessonReadStatus = lessonReadStatus
    }
    func writes() -> [URLRequest] { recorded.filter { $0.httpMethod != "GET" } }
    /// Dernier segment de chaque lecture reçue.
    func reads() -> [String] { recorded.filter { $0.httpMethod == "GET" }.compactMap { $0.url?.lastPathComponent } }
    func operationReads() -> Int {
        recorded.filter { $0.httpMethod == "GET" && $0.url?.deletingLastPathComponent().lastPathComponent == "operations" }.count
    }
    func didStartLessonRead() -> Bool { lessonReadStarted }
    func enableReceipt() { receiptAvailable = true }

    private var confirmedLessonVersion: Int {
        operationType == "MOVE_LESSON" ? 3 : 2
    }

    private func confirmedLesson() -> [String: Any] {
        let start: Date
        if let write = recorded.last(where: { $0.httpMethod == "POST" }),
           let data = write.httpBody,
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = body["plannedStart"] as? String,
           let parsed = ISO8601DateFormatter().date(from: value) { start = parsed }
        else { start = HubFixture.lesson().startsAt! }
        let end: Date
        if let write = recorded.last(where: { $0.httpMethod == "POST" }),
           let data = write.httpBody,
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = body["plannedEnd"] as? String,
           let parsed = ISO8601DateFormatter().date(from: value) { end = parsed }
        else { end = start.addingTimeInterval(3_000) }
        let iso = ISO8601DateFormatter()
        return ["id": HubFixture.lessonID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
            "version": confirmedLessonVersion + lessonVersionDelta, "trainingId": HubFixture.trainingID.uuidString,
            "learnerId": HubFixture.learnerID.uuidString, "instructorMembershipId": ConfigurationFixture.membershipID.uuidString,
            "plannedStart": iso.string(from: start), "plannedEnd": iso.string(from: end), "timeZone": "Europe/Zurich",
            "meetingPoint": "Gare", "status": "PLANNED", "priceCentsSnapshot": 10_000,
            "bufferMinutesSnapshot": 10, "actualStart": NSNull(), "actualEnd": NSNull(), "permitWarning": false,
            "publicationVersion": 0, "currentPublishedRevisionId": NSNull(), "commercialRevisionVersion": 1]
    }

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
        if request.httpMethod == "GET", url.lastPathComponent == HubFixture.lessonID.uuidString,
           url.deletingLastPathComponent().lastPathComponent == "lessons", operationID != nil {
            lessonReadStarted = true
            if lessonReadDelayMilliseconds > 0 { try await Task.sleep(for: .milliseconds(lessonReadDelayMilliseconds)) }
            if let lessonReadStatus {
                return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["code": lessonReadStatus == 403 ? "FORBIDDEN" : "UNAUTHORIZED"]),
                    status: lessonReadStatus, url: url, contentType: "application/problem+json")
            }
            return try reply(confirmedLesson())
        }
        if url.deletingLastPathComponent().lastPathComponent == "operations", let operationID {
            guard receiptAvailable else { throw URLError(.notConnectedToInternet) }
            return try reply(["operationId": operationID, "commandType": operationType, "resourceType": "Lesson",
                // Un déplacement fait passer la leçon de la version 2 de la fixture à la version 3 : le reçu la porte.
                "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": confirmedLessonVersion,
                "committedAt": ISO8601DateFormatter().string(from: Date())])
        }
        let response = try await fallback.send(request)
        if restriction == "second-product-default", url.lastPathComponent == "planning-defaults" {
            // Les préférences du moniteur désignent la seconde prestation.
            var defaults = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
            var record = defaults["data"] as! [String: Any]
            record["serviceProductKey"] = Self.secondProductKey
            defaults["data"] = record
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: defaults), status: response.status,
                url: url, contentType: response.contentType)
        }
        guard let restriction, ["service-products", "commercial-terms"].contains(url.lastPathComponent) else { return response }
        var envelope = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
        var page = envelope["data"] as! [String: Any]
        var items: [[String: Any]] = (page["items"] as! [[String: Any]]).map { original in
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
        if restriction.hasPrefix("second-product"), url.lastPathComponent == "service-products", var second = items.first {
            // Deux prestations correspondent à la même catégorie, à la même durée et aux mêmes conditions.
            second["id"] = Self.secondProductID.uuidString
            second["productKey"] = Self.secondProductKey
            second["label"] = "Leçon réduite"
            second["unitPriceCents"] = 8_000
            items.append(second)
        }
        page["items"] = items
        envelope["data"] = page
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: response.status,
            url: url, contentType: response.contentType)
    }
}
