import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolPlanningAvailabilityTests {
    @Test func availabilityIsReadBeforeConfirmationWithTheExactIntervalAndNoCommercialData() async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        #expect(model.canMutate && !model.slotIsAvailable && !model.validBooking)
        #expect(await model.saveBooking() == false)
        model.productID = nil
        await model.validateSlot()
        try #require(model.slotIsAvailable && !model.validBooking)
        let request = try #require(await server.requests().last)
        let query = Dictionary(uniqueKeysWithValues: try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems).map { ($0.name, $0.value ?? "") })
        let iso = ISO8601DateFormatter()
        #expect(request.httpMethod == "GET" && request.httpBody == nil)
        #expect(query == ["trainingId": HubFixture.trainingID.uuidString,
            "instructorMembershipId": ConfigurationFixture.membershipID.uuidString,
            "plannedStart": iso.string(from: model.startsAt), "plannedEnd": iso.string(from: model.endsAt),
            "timeZone": "Europe/Zurich", "bufferMinutes": "10"])
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        model.productID = PlanningDefaultsServer.productID
        #expect(model.validBooking)
    }

    @Test(arguments: ["SLOT_UNAVAILABLE", "SLOT_CONFLICT"])
    func closedOrOccupiedSlotsKeepCorrectionPossibleAndBlockBooking(_ reason: String) async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await server.respond(.refused(reason))
        await model.validateSlot()
        #expect(model.canMutate && !model.slotIsAvailable && !model.validBooking)
        #expect(model.slotAvailability?.reasonCode == reason && model.slotAvailability?.refusalMessage != nil)
        #expect(model.slotError == nil && !model.isCheckingSlot)
        #expect(await model.saveBooking() == false)
        model.startsAt = model.startsAt.addingTimeInterval(86_400)
        #expect(model.checkedSlotRequest != model.slotRequest)
        await server.respond(.free)
        await model.validateSlot()
        #expect(model.slotIsAvailable && model.validBooking)
    }

    @Test func shorteningTheLessonAfterAConflictDoesNotRestoreTheIncompatibleTariffDuration() async throws {
        let server = PlanningSlotServer(hasLongProduct: true, maximumMinutes: 50), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        model.selectDuration(100)
        model.productID = PlanningSlotServer.longProductID
        #expect(model.duration == 100 && model.quantity == 1)
        await model.validateSlot()
        #expect(!model.slotIsAvailable && model.canMutate)
        model.selectDuration(50)
        #expect(model.duration == 50 && model.quantity == 1 && model.productID == PlanningDefaultsServer.productID)
        #expect(!model.compatibleProducts.contains { $0.id == PlanningSlotServer.longProductID })
        await model.validateSlot()
        #expect(model.slotIsAvailable && model.validBooking && model.duration == 50)
        #expect(model.selectedPrice == 9000)
    }

    @Test func transientFailureClearsThePreviousAvailabilityAndCanBeRetried() async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.validateSlot()
        try #require(model.slotIsAvailable)
        await server.respond(.http(503))
        await model.validateSlot()
        #expect(model.canMutate && !model.slotIsAvailable && !model.isCheckingSlot)
        #expect(model.slotError != nil && model.slotAvailability == nil)
        await server.respond(.free)
        await model.validateSlot()
        #expect(model.slotIsAvailable && model.slotError == nil)
    }

    @Test func lateAvailabilityCannotReplaceTheNewDateOrBufferResult() async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await server.pauseNextRead()
        let oldRead = Task { await model.validateSlot() }
        await server.waitForPausedRead()
        #expect(model.isCheckingSlot && model.canMutate && !model.validBooking)
        model.startsAt = model.startsAt.addingTimeInterval(3600)
        model.bufferMinutes = 20
        await server.respond(.refused("SLOT_CONFLICT"))
        await model.validateSlot()
        let current = model.checkedSlotRequest
        await server.resumeRead()
        await oldRead.value
        #expect(model.checkedSlotRequest == current && current == model.slotRequest)
        #expect(model.slotAvailability?.reasonCode == "SLOT_CONFLICT" && !model.slotIsAvailable)
        #expect(!model.isCheckingSlot && model.slotError == nil)
    }

    @Test(arguments: [401, 403])
    func accessRevocationPurgesAvailabilityAndSchoolData(_ status: Int) async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await model.validateSlot()
        try #require(model.slotIsAvailable)
        await server.respond(.http(status))
        await model.validateSlot()
        #expect(model.accessRevoked && model.school == nil && model.learners.isEmpty)
        #expect(model.slotRequest == nil && model.checkedSlotRequest == nil && model.slotAvailability == nil)
        #expect(!model.isCheckingSlot && !model.validBooking && model.errorMessage != nil)
    }

    @Test func cancelledReadAndInvalidatedScopeNeverPublishAvailability() async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await server.pauseNextRead()
        let read = Task { await model.validateSlot() }
        await server.waitForPausedRead()
        read.cancel()
        await server.resumeRead()
        await read.value
        #expect(!model.slotIsAvailable && !model.isCheckingSlot && model.slotError == nil)
        await server.pauseNextRead()
        let invalidatedRead = Task { await model.validateSlot() }
        await server.waitForPausedRead()
        model.invalidate()
        await server.resumeRead()
        await invalidatedRead.value
        #expect(model.school == nil && model.slotAvailability == nil && model.checkedSlotRequest == nil)
        #expect(!model.isCheckingSlot && !model.slotIsAvailable)
    }

    @Test func movingExcludesOnlyTheOriginalLessonAndKeepsItsBuffer() async throws {
        let server = PlanningSlotServer(), model = workspace(server, lesson: HubFixture.lesson())
        await model.load()
        model.startsAt = Date().addingTimeInterval(86_400)
        await model.validateSlot()
        try #require(model.slotIsAvailable)
        let request = try #require(await server.requests().last)
        let query = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "excludeLessonId" }?.value == HubFixture.lessonID.uuidString)
        #expect(query.first { $0.name == "bufferMinutes" }?.value == String(HubFixture.lesson().bufferMinutesSnapshot))
        #expect(!model.validBooking)
        model.agreementConfirmed = true
        #expect(model.validBooking)
    }

    @Test(arguments: ["{\"available\":true}", "{\"available\":true,\"reasonCode\":\"SLOT_CONFLICT\"}",
        "{\"available\":false,\"reasonCode\":null}", "{\"available\":false,\"reasonCode\":\"UNKNOWN\"}",
        "{\"available\":\"true\",\"reasonCode\":null}"])
    func malformedAvailabilityNeverEnablesConfirmation(_ response: String) async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await server.respond(.invalid(response))
        await model.validateSlot()
        #expect(!model.slotIsAvailable && !model.validBooking && !model.isCheckingSlot)
        #expect(model.slotError != nil && model.canMutate)
    }

    @Test func debounceCancellationAndInvalidInputDoNotSendARead() async throws {
        let server = PlanningSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        let read = Task { await model.validateSlot(debounced: true) }
        read.cancel()
        await read.value
        #expect(await server.requests().isEmpty)
        model.startsAt = Date().addingTimeInterval(-60)
        await model.validateSlot()
        #expect(model.slotInputMessage != nil && model.slotRequest == nil && !model.isCheckingSlot)
        #expect(await server.requests().isEmpty)
    }

    private func workspace(_ server: PlanningSlotServer, lesson: SchoolLesson? = nil) -> SchoolPlanningWorkspace {
        SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: SchoolPlanningClient(
            baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server),
            date: Date().addingTimeInterval(86_400), lesson: lesson, outbox: ConfigurationOutboxStub())
    }
}

/// Server decisions are synthetic here; opening hours and anonymous conflicts are tested against PostgreSQL separately.
private actor PlanningSlotServer: SchoolHTTPTransport {
    enum Reply: Sendable { case free, refused(String), http(Int), invalid(String) }
    static let longProductID = UUID(uuidString: "77000000-0000-4000-8000-000000000001")!
    private let fallback = PlanningDefaultsServer()
    private let hasLongProduct: Bool
    private let maximumMinutes: Int?
    private var reply: Reply = .free
    private var reads: [URLRequest] = []
    private var pausesNextRead = false
    private var paused: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(hasLongProduct: Bool = false, maximumMinutes: Int? = nil) {
        self.hasLongProduct = hasLongProduct; self.maximumMinutes = maximumMinutes
    }
    func requests() -> [URLRequest] { reads }
    func respond(_ reply: Reply) { self.reply = reply }
    func pauseNextRead() { pausesNextRead = true }
    func waitForPausedRead() async {
        if paused != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resumeRead() { paused?.resume(); paused = nil }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        if url.lastPathComponent == "availability", url.deletingLastPathComponent().lastPathComponent == "lessons" {
            reads.append(request)
            var captured = reply
            if let maximumMinutes, let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let startText = query.first(where: { $0.name == "plannedStart" })?.value,
               let endText = query.first(where: { $0.name == "plannedEnd" })?.value,
               let start = SchoolLesson.date(startText), let end = SchoolLesson.date(endText),
               end.timeIntervalSince(start) > Double(maximumMinutes * 60) { captured = .refused("SLOT_CONFLICT") }
            if pausesNextRead {
                pausesNextRead = false
                await withCheckedContinuation { continuation in
                    paused = continuation; waiter?.resume(); waiter = nil
                }
            }
            let value: Any
            switch captured {
            case .free: value = ["available": true, "reasonCode": NSNull()] as [String: Any]
            case .refused(let reason): value = ["available": false, "reasonCode": reason] as [String: Any]
            case .invalid(let raw): value = try JSONSerialization.jsonObject(with: Data(raw.utf8))
            case .http(let status):
                return SchoolHTTPResponse(data: Data("{\"code\":\"AVAILABILITY_UNAVAILABLE\"}".utf8), status: status,
                    url: url, contentType: "application/problem+json")
            }
            return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value,
                "requestId": UUID().uuidString, "serverTime": ISO8601DateFormatter().string(from: Date())]),
                status: 200, url: url, contentType: "application/json")
        }
        let response = try await fallback.send(request)
        guard hasLongProduct, url.lastPathComponent == "service-products" else { return response }
        var envelope = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
        var page = envelope["data"] as! [String: Any]
        var items = page["items"] as! [[String: Any]], long = items[0]
        long["id"] = Self.longProductID.uuidString; long["productKey"] = "lesson-100"; long["durationMinutes"] = 100
        long["unitPriceCents"] = 17000
        items.append(long); page["items"] = items; envelope["data"] = page
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: envelope), status: 200, url: url, contentType: "application/json")
    }
}
