import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolPlanningDefaultsTests {
    @Test func preferenceOnlySelectsAnExistingUnambiguousTraining() {
        let defaults = SchoolPlanningDefaults(id: ConfigurationFixture.membershipID, schoolId: HubFixture.schoolID, version: 1,
            trainingCategoryCode: "B", serviceProductKey: nil)
        let b = training("B"), a = training("A")
        #expect(defaults.trainingID(in: []) == nil)
        #expect(defaults.trainingID(in: [a]) == a.id)
        #expect(defaults.trainingID(in: [a, b]) == b.id)
        #expect(defaults.trainingID(in: [b, training("B")]) == nil)
        #expect(defaults.trainingID(in: [a, training("C")]) == nil)
        let paused = SchoolTraining(id: UUID(), schoolId: HubFixture.schoolID, learnerId: HubFixture.learnerID, offeringId: UUID(),
            version: 1, categoryCode: "B", status: "PAUSED", startedOn: nil, closedOn: nil)
        #expect(defaults.trainingID(in: [paused]) == nil)
        #expect(defaults.trainingID(in: [paused, a]) == a.id)
        #expect(defaults.trainingID(in: [paused, a, training("C")]) == nil)
    }

    @Test func settingsRetainEditsWhenRefreshFailsAndRequireAValidatedContext() async throws {
        let server = PlanningDefaultsServer()
        let model = SchoolPlanningSettingsWorkspace(scope: ConfigurationFixture.scope(), client: client(server), outbox: ConfigurationOutboxStub())
        await model.load()
        try #require(model.saved != nil && model.errorMessage == nil)
        model.trainingCategoryCode = "B"; model.serviceProductKey = "lesson-50"
        await server.setReadUnavailable(true)
        await model.load()
        #expect(model.saved != nil && model.trainingCategoryCode == "B" && model.serviceProductKey == "lesson-50")
        #expect(!model.canSave && model.errorMessage != nil)
        await server.setReadUnavailable(false)
        await model.load()
        #expect(model.canSave && model.trainingCategoryCode == "B" && model.serviceProductKey == "lesson-50")
        #expect(await server.writes().isEmpty)
    }

    @Test func settingsRequireExplicitResolutionOfConcurrentChanges() async throws {
        let server = PlanningDefaultsServer()
        let model = SchoolPlanningSettingsWorkspace(scope: ConfigurationFixture.scope(), client: client(server), outbox: ConfigurationOutboxStub())
        await model.load()
        try #require(model.saved?.version == 1)
        model.trainingCategoryCode = "B"; model.serviceProductKey = "lesson-50"
        await server.changeDefaultsRemotely()
        await model.load()
        #expect(model.saved?.version == 1 && model.conflictingDefaults?.version == 2)
        #expect(model.trainingCategoryCode == "B" && model.serviceProductKey == "lesson-50")
        #expect(!model.canSave && model.errorMessage != nil)
        await model.save()
        #expect(await server.writes().isEmpty)
        model.useUpdatedDefaults()
        #expect(model.saved?.version == 2 && model.conflictingDefaults == nil)
        #expect(model.trainingCategoryCode == "B" && model.serviceProductKey.isEmpty)
        #expect(model.errorMessage == nil && !model.hasChanges)
    }

    @Test func cancellationReasonUsesTheAPIsUTF16Limit() async throws {
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(PlanningDefaultsServer()),
            lesson: HubFixture.lesson(), outbox: ConfigurationOutboxStub())
        model.reason = String(repeating: "🚗", count: 500)
        #expect(!model.reasonTooLong)
        model.reason += "🚗"
        #expect(model.reasonTooLong)
        #expect(await model.cancel() == false)
    }

    @Test func planningPrefillsCurrentInstructorForDualRoleAndRequiresCommercialAgreementWithoutAPlace() async throws {
        let server = PlanningDefaultsServer()
        let model = planning(server)
        await model.load()
        try #require(model.errorMessage == nil && !model.needsReload)
        await model.selectLearner(HubFixture.learnerID)
        #expect(model.trainingID == HubFixture.trainingID)
        #expect(model.instructorID == ConfigurationFixture.membershipID)
        #expect(model.productID == PlanningDefaultsServer.productID)
        #expect(model.meetingPoint.isEmpty && !model.termsAccepted && !model.validBooking)
        model.termsAccepted = true
        #expect(model.validBooking)
    }

    @Test func currentMemberIsNotPrefilledWithoutAnAssignment() async throws {
        let server = PlanningDefaultsServer(assigned: false)
        let model = planning(server)
        await model.load()
        try #require(model.errorMessage == nil && !model.needsReload)
        await model.selectLearner(HubFixture.learnerID)
        #expect(model.trainingID == HubFixture.trainingID && model.instructorID == nil)
        model.termsAccepted = true
        #expect(!model.validBooking)
    }

    @Test func optionalPlanningPlaceUsesTheSameTrimmedUTF16LimitAsTheAPI() async throws {
        let server = PlanningDefaultsServer()
        let model = planning(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        model.termsAccepted = true
        try #require(model.validBooking)

        for value in ["", " \n\t ", String(repeating: "a", count: 500), "  \(String(repeating: "a", count: 500))\n", String(repeating: "🚗", count: 250)] {
            model.meetingPoint = value
            #expect(!model.meetingPointTooLong)
            #expect(model.validBooking)
        }
        for value in [String(repeating: "a", count: 501), String(repeating: "🚗", count: 251)] {
            model.meetingPoint = value
            #expect(model.meetingPointTooLong)
            #expect(!model.validBooking)
        }
        #expect(await server.writes().isEmpty)
    }

    @Test func settingsKeepTheSameCommandUntilItsDurableReceiptIsAvailable() async throws {
        let server = PlanningDefaultsServer(receiptAvailable: false), outbox = ConfigurationOutboxStub()
        let model = SchoolPlanningSettingsWorkspace(scope: ConfigurationFixture.scope(), client: client(server), outbox: outbox)
        await model.load()
        try #require(model.saved != nil && model.errorMessage == nil)
        model.trainingCategoryCode = "B"; model.serviceProductKey = "lesson-50"
        #expect(model.canSave)
        await model.save()
        let pending = try #require(model.pending)
        #expect(outbox.value == pending && model.successMessage == nil)
        #expect(pending.kind == .savePlanningDefaults && pending.resourceID == ConfigurationFixture.membershipID && pending.hasValidTarget)
        let writes = await server.writes()
        #expect(writes.count == 1 && writes[0].httpMethod == "PUT" && writes[0].value(forHTTPHeaderField: "If-Match") == "\"1\"")
        await server.enableReceipt()
        await model.verify()
        #expect(model.pending == nil && outbox.value == nil && model.saved?.version == 2)
        #expect(model.successMessage != nil && !model.canSave)
        #expect(await server.writes().count == 1)
    }

    @Test func cancellationIsConfirmedEvenWhenTheFollowingReadFails() async throws {
        let server = PlanningDefaultsServer(failReadsAfterCancellation: true), outbox = ConfigurationOutboxStub()
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(server),
            lesson: HubFixture.lesson(), outbox: outbox)
        await model.load()
        try #require(model.errorMessage == nil && model.canMutate)
        model.cancellationReason = "OTHER"
        #expect(await model.cancel())
        #expect(model.confirmedCancellationLessonID == HubFixture.lessonID)
        #expect(model.originalLesson?.status == "PLANNED" && model.errorMessage != nil)
        #expect(model.pending == nil && outbox.value == nil)
    }

    @Test func cancellationWaitsForTheReceiptAndCanBeConfirmedByVerification() async throws {
        let server = PlanningDefaultsServer(receiptAvailable: false, failReadsAfterCancellation: true)
        let outbox = ConfigurationOutboxStub()
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(server),
            lesson: HubFixture.lesson(), outbox: outbox)
        await model.load()
        try #require(model.errorMessage == nil && model.canMutate)
        model.cancellationReason = "OTHER"
        #expect(await model.cancel() == false)
        #expect(model.confirmedCancellationLessonID == nil && outbox.value != nil)
        await server.enableReceipt()
        await model.verify()
        #expect(model.confirmedCancellationLessonID == HubFixture.lessonID)
        #expect(model.pending == nil && outbox.value == nil)
        #expect(await server.writes().count == 1)
    }

    @Test func reloadingTheSameInstructorRestoresAvailabilityWithoutAViewTaskRestart() async throws {
        let model = planning(PlanningDefaultsServer())
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.loadAvailability()
        try #require(model.instructorID != nil && model.availabilityLoaded)
        let instructor = model.instructorID
        await model.load()
        #expect(model.instructorID == instructor)
        #expect(model.availabilityLoaded && !model.isLoadingAvailability && model.availabilityError == nil)
    }

    private func training(_ category: String) -> SchoolTraining {
        SchoolTraining(id: UUID(), schoolId: HubFixture.schoolID, learnerId: HubFixture.learnerID, offeringId: UUID(),
            version: 1, categoryCode: category, status: "ACTIVE", startedOn: nil, closedOn: nil)
    }
    private func client(_ server: PlanningDefaultsServer) -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }
    private func planning(_ server: PlanningDefaultsServer) -> SchoolPlanningWorkspace {
        SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(server), date: Date().addingTimeInterval(86_400), outbox: ConfigurationOutboxStub())
    }
}

actor PlanningDefaultsServer: SchoolHTTPTransport {
    static let productID = UUID(uuidString: "76000000-0000-4000-8000-000000000001")!
    private let offeringID = UUID(uuidString: "76000000-0000-4000-8000-000000000002")!
    private let policyID = UUID(uuidString: "76000000-0000-4000-8000-000000000003")!
    private let termsID = UUID(uuidString: "76000000-0000-4000-8000-000000000004")!
    private let assigned: Bool
    private var receiptAvailable: Bool
    private var defaultsVersion = 1
    private var category: Any = NSNull()
    private var productKey: Any = NSNull()
    private var operationID: String?
    private var cancelled = false
    private let failReadsAfterCancellation: Bool
    private var sent: [URLRequest] = []
    private var readUnavailable = false
    init(assigned: Bool = true, receiptAvailable: Bool = true, failReadsAfterCancellation: Bool = false) {
        self.assigned = assigned; self.receiptAvailable = receiptAvailable
        self.failReadsAfterCancellation = failReadsAfterCancellation
    }
    func writes() -> [URLRequest] { sent.filter { $0.httpMethod != "GET" } }
    func enableReceipt() { receiptAvailable = true }
    func setReadUnavailable(_ value: Bool) { readUnavailable = value }
    func changeDefaultsRemotely() { defaultsVersion = 2; category = "B"; productKey = NSNull() }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        if readUnavailable && request.httpMethod == "GET" { throw URLError(.notConnectedToInternet) }
        sent.append(request)
        let url = request.url!, parts = url.pathComponents.map { $0.lowercased() }
        func ok(_ value: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value, "requestId": UUID().uuidString,
                "serverTime": ISO8601DateFormatter().string(from: Date())]), status: 200, url: url, contentType: "application/json")
        }
        func record(_ id: UUID, _ extra: [String: Any]) -> [String: Any] {
            ["id": id.uuidString, "schoolId": HubFixture.schoolID.uuidString, "version": 1].merging(extra) { _, rhs in rhs }
        }
        func page(_ items: [[String: Any]]) throws -> SchoolHTTPResponse { try ok(["items": items, "nextCursor": NSNull()]) }
        if parts.last == "me" {
            if cancelled && failReadsAfterCancellation { throw URLError(.notConnectedToInternet) }
            return try ok(["personId": ConfigurationFixture.personID.uuidString, "version": 1, "displayName": "Moniteur de test", "locale": "fr",
                "memberships": [["membershipId": ConfigurationFixture.membershipID.uuidString, "schoolId": HubFixture.schoolID.uuidString,
                    "schoolName": "École de test", "roles": ["ADMIN", "INSTRUCTOR"], "grants": [], "accessEpoch": 1] as [String: Any]]])
        }
        if parts.last == HubFixture.schoolID.uuidString.lowercased() {
            var school = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.school(gps: true))) as! [String: Any]
            // The API includes nullable fields; synthesized Encodable omits nil properties.
            school["contactPhone"] = NSNull(); school["logoAssetId"] = NSNull()
            return try ok(school)
        }
        if parts.dropLast().last == "lessons", parts.last == HubFixture.lessonID.uuidString.lowercased() {
            return try ok(JSONSerialization.jsonObject(with: JSONEncoder().encode(HubFixture.lesson(status: cancelled ? "CANCELLED" : "PLANNED"))))
        }
        if parts.last == "cancel" {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            operationID = body["operationId"] as? String; cancelled = true
            return try ok(["accepted": true])
        }
        if parts.last == "planning-defaults" {
            if request.httpMethod == "PUT" {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                defaultsVersion = 2; operationID = body["operationId"] as? String
                category = body["trainingCategoryCode"] ?? NSNull(); productKey = body["serviceProductKey"] ?? NSNull()
            }
            return try ok(record(ConfigurationFixture.membershipID, ["version": defaultsVersion, "trainingCategoryCode": category, "serviceProductKey": productKey]))
        }
        if parts.dropLast().last == "operations", let operationID {
            if !receiptAvailable { return SchoolHTTPResponse(data: Data("{\"code\":\"SERVICE_UNAVAILABLE\"}".utf8), status: 503, url: url, contentType: "application/problem+json") }
            if cancelled {
                return try ok(["operationId": operationID, "commandType": "CANCEL_LESSON", "resourceType": "Lesson",
                    "resourceId": HubFixture.lessonID.uuidString, "resourceVersion": 3, "committedAt": ISO8601DateFormatter().string(from: Date())])
            }
            return try ok(["operationId": operationID, "commandType": "SAVE_PLANNING_DEFAULTS", "resourceType": "PlanningDefaults",
                "resourceId": ConfigurationFixture.membershipID.uuidString, "resourceVersion": 2, "committedAt": ISO8601DateFormatter().string(from: Date())])
        }
        if parts.last == "offerings" { return try page([record(offeringID, ["offeringKey": "B", "categoryCode": "B", "curriculumVersionId": UUID().uuidString, "policyVersionId": policyID.uuidString, "enabled": true, "defaultDurationMinutes": 50, "defaultPriceCents": 9000])]) }
        if parts.last == "policy-versions" { return try page([record(policyID, ["categoryCode": "B", "procedureText": "Procédure", "cancellationPolicyText": "Annulation", "sourceUrls": [], "approved": true, "approvedAt": "2026-01-01T00:00:00Z"])]) }
        if parts.last == "service-products" { return try page([record(Self.productID, ["productKey": "lesson-50", "label": "Leçon", "type": "INDIVIDUAL_LESSON", "categoryCode": "B", "durationMinutes": 50, "siteId": NSNull(), "unitLabel": "leçon", "unitPriceCents": 9000, "validFrom": "2020-01-01", "validUntil": NSNull(), "termsVersionId": termsID.uuidString, "enabled": true, "current": true])]) }
        if parts.last == "commercial-terms" { return try page([record(termsID, ["label": "Conditions", "termsText": "Texte", "validFrom": "2020-01-01", "validUntil": NSNull(), "approved": true])]) }
        if parts.last == "members" { return try page([record(ConfigurationFixture.membershipID, ["personId": ConfigurationFixture.personID.uuidString, "displayName": "Moniteur de test", "status": "ACTIVE", "roles": ["ADMIN", "INSTRUCTOR"], "grants": [], "accessEpoch": 1])]) }
        if parts.last == "learners" { return try page([record(HubFixture.learnerID, ["personId": UUID().uuidString, "displayName": "Élève de test", "contactEmail": NSNull(), "contactPhone": NSNull(), "archivedAt": NSNull()])]) }
        if parts.last == "trainings" { return try page([record(HubFixture.trainingID, ["learnerId": HubFixture.learnerID.uuidString, "offeringId": offeringID.uuidString, "categoryCode": "B", "status": "ACTIVE", "startedOn": NSNull(), "closedOn": NSNull()])]) }
        if parts.last == "assignments" { return try page(assigned ? [record(UUID(), ["trainingId": HubFixture.trainingID.uuidString, "instructorMembershipId": ConfigurationFixture.membershipID.uuidString, "validFrom": "2020-01-01T00:00:00Z", "validUntil": NSNull()])] : []) }
        return try page([])
    }
}
