import Foundation
import Testing
@testable import Drivy

/// La recherche elle-même (ouvertures, pauses, fermetures, occupations, fuseau, changements d’heure) est testée côté API
/// (`apps/api/test/next-slot.test.ts`, puis contre PostgreSQL). Ici : ce que l’app fait de la réponse.
@MainActor struct SchoolPlanningNextSlotTests {
    @Test func theDateAppearsOnlyOnceTheNextFreeSlotIsComputed() async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        let initial = model.startsAt
        #expect(model.suggestsNextSlot && model.awaitingSuggestedSlot)
        // Pendant la recherche, rien ne se vérifie ni ne s’affiche sur la date provisoire.
        #expect(model.slotRequest == nil && model.slotInputMessage == nil && !model.showsSlotDetails)
        let search = try #require(model.nextSlotRequest)
        #expect(search.instructorID == ConfigurationFixture.membershipID && search.durationMinutes == model.duration)

        await model.findSuggestedSlot()
        let proposed = server.proposedStart
        #expect(model.suggestedSlot == .found && model.startsAt == proposed && model.startsAt != initial)
        #expect(!model.awaitingSuggestedSlot && model.suggestedSlotNotice == nil)
        #expect(model.slotRequest?.startsAt == proposed)

        let requests = await server.requests()
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(request.httpMethod == "GET" && request.httpBody == nil)
        #expect(components.path.hasSuffix("/lessons/next-slot"))
        #expect(query["trainingId"] == HubFixture.trainingID.uuidString)
        #expect(query["instructorMembershipId"] == ConfigurationFixture.membershipID.uuidString)
        #expect(query["durationMinutes"] == String(model.duration) && query["bufferMinutes"] == "10")
        #expect(query["timeZone"] == "Europe/Zurich" && query["from"] != nil)

        // La même recherche n’est pas relancée par une relecture de la feuille.
        await model.findSuggestedSlot()
        let again = await server.requests()
        #expect(again.count == 1)
    }

    @Test func aManualChoiceWinsEvenOverASearchInFlight() async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await server.pauseNextRead()
        let search = Task { await model.findSuggestedSlot() }
        await server.waitForPausedRead()
        #expect(model.suggestedSlot == .searching && model.awaitingSuggestedSlot)
        let chosen = Date(timeIntervalSince1970: ceil(Date().addingTimeInterval(5 * 86_400).timeIntervalSince1970 / 60) * 60)
        model.chooseStart(chosen)
        await server.resumeRead()
        await search.value
        #expect(model.startsAt == chosen && model.startChosenByUser)
        #expect(model.nextSlotRequest == nil && !model.awaitingSuggestedSlot && model.suggestedSlotNotice == nil)
        await model.findSuggestedSlot()
        let requests = await server.requests()
        #expect(requests.count == 1)
    }

    @Test func noSlotInThePeriodSaysSoAndSearchesFurtherFromTheNextDay() async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        let initial = model.startsAt
        // Dernier jour examiné : aujourd’hui (Zurich). La reprise part de demain, avant le créneau proposé à deux jours.
        var zurich = Calendar(identifier: .gregorian)
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let today = zurich.dateComponents([.year, .month, .day], from: Date())
        let through = String(format: "%04d-%02d-%02d", today.year!, today.month!, today.day!)
        await server.respond(.none(through))
        await model.findSuggestedSlot()
        #expect(model.suggestedSlot == .exhausted(searchedThrough: through))
        #expect(model.suggestedSlotNotice == .exhausted(searchedThrough: through))
        // La date reste modifiable à la main ; elle n’a pas bougé.
        #expect(!model.awaitingSuggestedSlot && model.startsAt == initial)

        model.searchFurther()
        let resumed = try #require(SchoolPlanningNextSlot.startOfNextCivilDay(after: through, zone: "Europe/Zurich"))
        #expect(model.suggestionResumesAt == resumed && model.nextSlotRequest?.from == resumed)
        #expect(model.awaitingSuggestedSlot && model.suggestedSlotNotice == nil)
        await server.respond(.found)
        await model.findSuggestedSlot()
        let proposed = server.proposedStart
        #expect(model.suggestedSlot == .found && model.startsAt == proposed)
        let requests = await server.requests()
        let from = requests.last.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "from" }?.value }
        #expect(from == ISO8601DateFormatter().string(from: resumed))
    }

    @Test func aServiceWithoutTheSearchKeepsTheManualFormWithoutAnError() async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        let initial = model.startsAt
        await server.respond(.http(404))
        await model.findSuggestedSlot()
        #expect(model.suggestedSlot == .unavailable && model.suggestedSlotNotice == nil)
        #expect(!model.awaitingSuggestedSlot && model.startsAt == initial && model.errorMessage == nil)
        #expect(model.slotRequest?.startsAt == initial)
    }

    @Test func aTransientFailureCanBeRetried() async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await server.respond(.http(503))
        await model.findSuggestedSlot()
        guard case .failed = model.suggestedSlot else { Issue.record("La panne doit être signalée."); return }
        #expect(model.suggestedSlotNotice == model.suggestedSlot && !model.awaitingSuggestedSlot && model.canMutate)
        await server.respond(.found)
        await model.findSuggestedSlot(retrying: true)
        let proposed = server.proposedStart
        #expect(model.suggestedSlot == .found && model.startsAt == proposed)
    }

    @Test(arguments: ["before-search", "wrong-duration", "missing-slot", "bad-day", "other-zone", "end-before-start"])
    func malformedAnswersNeverMoveTheDate(_ variant: String) async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        let initial = model.startsAt
        await server.respond(.malformed(variant))
        await model.findSuggestedSlot()
        guard case .failed = model.suggestedSlot else { Issue.record("Réponse \(variant) acceptée."); return }
        #expect(model.startsAt == initial && !model.awaitingSuggestedSlot)
    }

    @Test func anAnswerForAnotherDurationIsIgnored() async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        let initial = model.startsAt
        await server.pauseNextRead()
        let search = Task { await model.findSuggestedSlot() }
        await server.waitForPausedRead()
        model.selectDuration(model.duration + 50)
        await server.resumeRead()
        await search.value
        #expect(model.startsAt == initial && model.suggestedSlot == .idle && model.suggestedSlotRequest == nil)
        #expect(model.awaitingSuggestedSlot && model.nextSlotRequest?.durationMinutes == model.duration)
    }

    @Test(arguments: [401, 403])
    func accessRevocationPurgesTheForm(_ status: Int) async throws {
        let server = NextSlotServer(), model = workspace(server)
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        await server.respond(.http(status))
        await model.findSuggestedSlot()
        #expect(model.accessRevoked && model.school == nil && model.learners.isEmpty)
        #expect(model.nextSlotRequest == nil && !model.awaitingSuggestedSlot && model.errorMessage != nil)
    }

    @Test func movingALessonNeverSearches() async throws {
        let server = NextSlotServer()
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(server), lesson: HubFixture.lesson(),
            suggestingNextSlotFrom: Date(), outbox: ConfigurationOutboxStub())
        await model.load()
        #expect(!model.suggestsNextSlot && model.nextSlotRequest == nil && !model.awaitingSuggestedSlot)
        await model.findSuggestedSlot()
        let requests = await server.requests()
        #expect(requests.isEmpty)
    }

    @Test func withoutSuggestionTheFormKeepsItsInitialDate() async throws {
        let server = NextSlotServer()
        let model = SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(server),
            date: Date().addingTimeInterval(86_400), outbox: ConfigurationOutboxStub())
        await model.load()
        await model.selectLearner(HubFixture.learnerID)
        #expect(!model.suggestsNextSlot && model.nextSlotRequest == nil && model.slotRequest != nil)
    }

    @Test func civilDaysFollowTheSchoolTimeZoneAcrossClockChanges() throws {
        let iso = ISO8601DateFormatter()
        #expect(SchoolPlanningNextSlot.startOfCivilDay("2026-10-13", zone: "Europe/Zurich") == iso.date(from: "2026-10-12T22:00:00Z"))
        #expect(SchoolPlanningNextSlot.startOfNextCivilDay(after: "2026-03-28", zone: "Europe/Zurich") == iso.date(from: "2026-03-28T23:00:00Z"))
        #expect(SchoolPlanningNextSlot.startOfNextCivilDay(after: "2026-03-29", zone: "Europe/Zurich") == iso.date(from: "2026-03-29T22:00:00Z"))
        #expect(SchoolPlanningNextSlot.startOfNextCivilDay(after: "2026-10-25", zone: "Europe/Zurich") == iso.date(from: "2026-10-25T23:00:00Z"))
        #expect(SchoolPlanningNextSlot.startOfCivilDay("2026-02-30", zone: "Europe/Zurich") == nil)
        #expect(SchoolPlanningNextSlot.startOfCivilDay("2026-1-05", zone: "Europe/Zurich") == nil)
        #expect(SchoolPlanningNextSlot.startOfCivilDay("2026-10-13", zone: "Nowhere/Invalid") == nil)
    }

    private func client(_ server: NextSlotServer) -> SchoolPlanningClient {
        SchoolPlanningClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }
    private func workspace(_ server: NextSlotServer) -> SchoolPlanningWorkspace {
        SchoolPlanningWorkspace(scope: ConfigurationFixture.scope(), client: client(server), date: Date().addingTimeInterval(86_400),
            suggestingNextSlotFrom: Date(), outbox: ConfigurationOutboxStub())
    }
}

/// Réponses synthétiques de la recherche ; le reste du planning vient du serveur des préférences.
private actor NextSlotServer: SchoolHTTPTransport {
    enum Reply: Sendable { case found, none(String), http(Int), malformed(String) }
    private let fallback = PlanningDefaultsServer()
    private var reply: Reply = .found
    private var reads: [URLRequest] = []
    private var pausesNextRead = false
    private var paused: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    /// Début proposé : dans deux jours, à la minute.
    nonisolated let proposedStart = Date(timeIntervalSince1970: floor(Date().addingTimeInterval(2 * 86_400).timeIntervalSince1970 / 60) * 60)

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
        guard url.lastPathComponent == "next-slot", url.deletingLastPathComponent().lastPathComponent == "lessons" else {
            return try await fallback.send(request)
        }
        reads.append(request)
        let captured = reply
        if pausesNextRead {
            pausesNextRead = false
            await withCheckedContinuation { continuation in
                paused = continuation; waiter?.resume(); waiter = nil
            }
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let minutes = Int(query.first { $0.name == "durationMinutes" }?.value ?? "") ?? 50
        let iso = ISO8601DateFormatter()
        func slot(_ start: Date, _ end: Date) -> [String: Any] { ["plannedStart": iso.string(from: start), "plannedEnd": iso.string(from: end)] }
        let end = proposedStart.addingTimeInterval(TimeInterval(minutes * 60))
        var value: [String: Any] = ["slot": slot(proposedStart, end), "searchedThrough": "2026-10-26", "timeZone": "Europe/Zurich"]
        switch captured {
        case .found: break
        case .none(let through): value["slot"] = NSNull(); value["searchedThrough"] = through
        case .http(let status):
            return SchoolHTTPResponse(data: Data("{\"code\":\"NEXT_SLOT_UNAVAILABLE\"}".utf8), status: status,
                url: url, contentType: "application/problem+json")
        case .malformed(let variant):
            switch variant {
            case "before-search": value["slot"] = slot(Date().addingTimeInterval(-7200), Date().addingTimeInterval(-7200 + Double(minutes * 60)))
            case "wrong-duration": value["slot"] = slot(proposedStart, proposedStart.addingTimeInterval(TimeInterval(minutes * 60 + 300)))
            case "missing-slot": value.removeValue(forKey: "slot")
            case "bad-day": value["searchedThrough"] = "26.10.2026"
            case "other-zone": value["timeZone"] = "UTC"
            default: value["slot"] = slot(end, proposedStart)
            }
        }
        return SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value,
            "requestId": UUID().uuidString, "serverTime": iso.string(from: Date())]),
            status: 200, url: url, contentType: "application/json")
    }
}
