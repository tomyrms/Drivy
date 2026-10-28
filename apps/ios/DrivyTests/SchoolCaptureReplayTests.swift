import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolCaptureReplayTests {
    @Test func retryBudgetBacksOffAndNeverShortensServerAdvice() {
        var budget = SchoolReplayRetryBudget()
        // Evaluate mutating calls outside Testing macros, as with the rebuild pacer tests.
        let adviceDelays = [budget.nextDelay(minimum: 1, elapsed: 0),
            budget.nextDelay(minimum: 1, elapsed: 2),
            budget.nextDelay(minimum: 20, elapsed: 6),
            budget.nextDelay(minimum: 120, elapsed: 26)]
        #expect(adviceDelays == [2, 4, 20, nil])
        var bounded = SchoolReplayRetryBudget()
        let delays = (0..<7).map { _ in bounded.nextDelay(minimum: 1, elapsed: 0) }
        #expect(delays == [2, 4, 8, 16, 30, 30, nil])
    }

    @Test func matchingAdviceDistinguishesLegacyPendingExplicitStopAndUnavailable() throws {
        let legacy = try route(status: "PENDING")
        #expect(legacy.suggestedRetryDelay == 2)
        let legacyUnavailable = try route(status: "UNAVAILABLE")
        #expect(legacyUnavailable.reason == nil && legacyUnavailable.suggestedRetryDelay == 2)
        let stopped = try route(status: "PENDING", extra: ",\"retryAfterSeconds\":null")
        #expect(stopped.suggestedRetryDelay == nil)
        let waiting = try route(status: "UNAVAILABLE", extra: ",\"reason\":\"WAITING_FOR_SYNC\",\"retryAfterSeconds\":5")
        #expect(waiting.reason == "WAITING_FOR_SYNC" && waiting.suggestedRetryDelay == 5)
        let terminal = try route(status: "UNAVAILABLE", extra: ",\"reason\":\"MATCHING_DISABLED\",\"retryAfterSeconds\":null")
        #expect(terminal.suggestedRetryDelay == nil)
        let ready = try route(status: "READY", extra: ",\"reason\":\"NO_RELIABLE_MATCH\",\"retryAfterSeconds\":null")
        #expect(ready.isUsable && ready.spans.isEmpty && ready.suggestedRetryDelay == nil)
    }

    @Test func invalidRetryAdviceIsNotAccepted() throws {
        for seconds in [0, -1, 604801] {
            let value = try route(status: "PENDING", extra: ",\"retryAfterSeconds\":\(seconds)")
            #expect(!value.isValidResponse)
        }
    }

    @Test func pendingThenReadyKeepsMeasuredReplayAndAddsGeometry() async {
        let server = ReplayMatchingServer(replies: [.pending(), .ready()])
        let model = workspace(server)
        await model.load()
        #expect(model.isComplete && model.pointCount == 3)
        #expect(model.matchingState == .matched && model.matchedRoute?.isUsable == true)
        #expect(model.errorMessage == nil)
        #expect(await server.replayReads == 1)
    }

    @Test func legacyUnavailableCanBecomeReadyWithoutClosingTheScreen() async {
        let server = ReplayMatchingServer(replies: [.legacyUnavailable, .ready()])
        let model = workspace(server)
        await model.load()
        #expect(model.matchingState == .matched && model.matchedRoute?.isUsable == true)
        #expect(await server.matchingReads == 2)
    }

    @Test func prolongedLegacyUnavailableIsBoundedAndDoesNotInventACause() async {
        let server = ReplayMatchingServer(replies: Array(repeating: .legacyUnavailable, count: 7))
        let model = workspace(server)
        await model.load()
        #expect(model.matchingState == .deferred(nil) && model.isComplete)
        #expect(await server.matchingReads == 7)
    }

    @Test func refreshKeepsTheOldCompleteReplayUntilEveryNewPageArrives() async throws {
        let server = ReplayMatchingServer(replies: [.ready(), .ready(), .ready(version: 2), .ready(version: 2)],
            heldReplayRead: 3, pagedRefresh: true)
        let model = workspace(server)
        await model.load()
        let oldObservations = model.observations
        let selected = try #require(oldObservations.first?.id)
        let before = timeline(model)
        #expect(before.duration == 20 && model.pointCount == 3)
        let refreshing = Task { await model.load() }
        defer { refreshing.cancel(); Task { await server.release() } }
        try await HubFixture.wait { await server.isHeld }
        try #require(await server.isHeld)
        // A short first page must not remove the selection or clamp the playhead.
        #expect(model.pointCount == 3 && model.observations == oldObservations && model.isComplete)
        #expect(timeline(model).duration == before.duration)
        #expect(timeline(model).retainedSelection(selected) == selected)
        await server.release()
        await refreshing.value
        let after = timeline(model)
        #expect(model.pointCount == 5 && model.observations == oldObservations)
        #expect(after.duration == 40 && after.retainedSelection(selected) == selected)
        #expect(after.retainedSelection(UUID()) == nil)
        #expect(after.matchingCoverage.state == .full)
        #expect(await server.sawContinuationCursor)
        #expect(model.fragments.count == 1 && model.fragments[0].points.map(\.sequence) == [0, 1, 2, 3, 4])
    }

    /// #115 : un trajet déjà ouvert se rouvre sans retélécharger ses pages tant que l’école garde sa version.
    @Test func reopeningAnUnchangedReplayKeepsItsPagesAndOnlyRereadsItsVersion() async {
        let server = ReplayMatchingServer(replies: [.ready(), .ready(), .ready(), .ready()])
        let cache = SchoolReplayCache()
        let first = cachedWorkspace(server, cache)
        await first.load()
        #expect(first.isComplete && first.pointCount == 3 && first.matchingState == .matched)
        let pagesRead = await server.replayReads
        let second = cachedWorkspace(server, cache)
        await second.load()
        #expect(second.isComplete && second.pointCount == 3 && second.observations == first.observations)
        #expect(second.matchingState == .matched && second.errorMessage == nil)
        #expect(await server.replayReads == pagesRead)
        // Une autre époque d’accès ne lit jamais ce qui a été gardé pour la précédente.
        #expect(cache.entry(scope: ConfigurationFixture.scope(epoch: 2), captureID: server.captureID) == nil)
        second.invalidate()
        #expect(cache.entry(scope: ConfigurationFixture.scope(), captureID: server.captureID) == nil)
    }

    private func cachedWorkspace(_ server: ReplayMatchingServer, _ cache: SchoolReplayCache) -> SchoolCaptureReplayWorkspace {
        SchoolCaptureReplayWorkspace(scope: ConfigurationFixture.scope(), client: client(server), captureID: server.captureID,
            cache: cache, sleep: { _ in try Task.checkCancellation() }, now: { 0 })
    }

    private func timeline(_ model: SchoolCaptureReplayWorkspace) -> SchoolReplayTimeline {
        SchoolReplayTimeline(fragments: model.fragments, observations: model.observations,
            startsAt: model.startsAt, endsAt: model.endsAt, matched: model.matchedRoute)
    }

    @Test func transientFailureBetweenPendingAndReadyDoesNotEndPolling() async {
        let server = ReplayMatchingServer(replies: [.pending(), .http(503), .ready()])
        let model = workspace(server)
        await model.load()
        #expect(model.matchingState == .matched && model.isComplete)
        #expect(await server.matchingReads == 3)
    }

    @Test func serverDelayBeyondBudgetDefersWithoutAnotherRequest() async {
        let server = ReplayMatchingServer(replies: [.pending(delay: 600)])
        let model = workspace(server)
        await model.load()
        #expect(model.matchingState == .deferred("PROCESSING"))
        #expect(model.isComplete && model.pointCount == 3)
        #expect(await server.matchingReads == 1)
    }

    @Test func pendingForeverStopsAfterSixAutomaticRetries() async {
        let server = ReplayMatchingServer(replies: Array(repeating: .pending(), count: 7))
        let model = workspace(server)
        await model.load()
        #expect(model.matchingState == .deferred("PROCESSING"))
        #expect(await server.matchingReads == 7)
    }

    @Test func invalidMatchingResponseKeepsMeasurementsWithoutAutomaticRetry() async {
        let server = ReplayMatchingServer(replies: [.wrongCapture])
        let model = workspace(server)
        await model.load()
        #expect(model.isComplete && model.matchingState == .failed)
        #expect(model.matchedRoute == nil && model.pointCount == 3)
        #expect(await server.matchingReads == 1)
    }

    @Test func cancellationWhileWaitingPreventsTheNextNetworkRequest() async throws {
        let server = ReplayMatchingServer(replies: [.pending(), .ready()])
        let gate = ReplaySleepGate()
        let model = SchoolCaptureReplayWorkspace(scope: ConfigurationFixture.scope(), client: client(server), captureID: server.captureID,
            sleep: { _ in await gate.wait() }, now: { 0 })
        let loading = Task { await model.load() }
        defer { loading.cancel(); Task { await gate.release() } }
        try await HubFixture.wait { await gate.isWaiting }
        try #require(await gate.isWaiting)
        model.stopLoading()
        await gate.release()
        await loading.value
        #expect(await server.matchingReads == 1)
        #expect(model.matchedRoute == nil && model.errorMessage == nil)
    }

    @Test func waitingForSyncReloadsMeasurementsBeforeApplyingNewReconstruction() async {
        let server = ReplayMatchingServer(replies: [.waiting(), .ready(version: 2), .ready(version: 2)])
        let model = workspace(server)
        await model.load()
        #expect(model.matchingState == .matched && model.matchedRoute?.reconstructionVersion == 2)
        #expect(model.pointCount == 5 && model.observations.count == 1)
        #expect(await server.replayReads == 2)
    }

    @Test func changingReconstructionDuringRefreshIsNeverAppliedToEarlierMeasurements() async {
        let server = ReplayMatchingServer(replies: [.waiting(), .ready(version: 2), .ready(version: 3), .ready(version: 3), .ready(version: 3)])
        let model = workspace(server)
        await model.load()
        #expect(model.matchedRoute?.reconstructionVersion == 3 && model.pointCount == 7)
        #expect(await server.replayReads == 3)
    }

    @Test func olderReconstructionCannotReplaceTheNewestOneAlreadyObserved() async {
        let server = ReplayMatchingServer(replies: [.waiting(), .ready(version: 2), .ready(version: 3),
            .ready(version: 2), .ready(version: 3), .ready(version: 3)])
        let model = workspace(server)
        await model.load()
        #expect(model.matchedRoute?.reconstructionVersion == 3 && model.pointCount == 7)
        #expect(await server.replayReads == 3)
    }

    @Test func refusalWhilePollingPurgesThePreviouslyLoadedPrivateReplay() async {
        let server = ReplayMatchingServer(replies: [.pending(), .http(403)])
        let model = workspace(server)
        await model.load()
        #expect(model.fragments.isEmpty && model.observations.isEmpty && model.capture == nil)
        #expect(model.matchedRoute == nil && !model.isComplete && model.errorMessage != nil)
    }

    @Test func disappearingScreenIgnoresResponseEvenWhenTransportDoesNotCooperate() async throws {
        let server = ReplayMatchingServer(replies: [.pending(), .ready()], heldRead: 2)
        let model = workspace(server)
        let loading = Task { await model.load() }
        defer { loading.cancel(); Task { await server.release() } }
        try await HubFixture.wait { await server.isHeld }
        try #require(await server.isHeld)
        let revision = model.contentRevision
        model.stopLoading()
        await server.release()
        await loading.value
        #expect(model.matchedRoute == nil && model.contentRevision == revision)
        #expect(model.errorMessage == nil && !model.isLoading)
    }

    @Test func invalidatedAccountCannotReceiveLateGeometry() async throws {
        let server = ReplayMatchingServer(replies: [.pending(), .ready()], heldRead: 2)
        let model = workspace(server)
        let loading = Task { await model.load() }
        defer { loading.cancel(); Task { await server.release() } }
        try await HubFixture.wait { await server.isHeld }
        try #require(await server.isHeld)
        model.invalidate()
        await server.release()
        await loading.value
        #expect(model.isInvalidated && model.fragments.isEmpty && model.matchedRoute == nil)
        #expect(!model.isLoading && !model.isComplete)
    }

    @Test func oldScreenGenerationCannotOverwriteAReopenedReplay() async throws {
        let server = ReplayMatchingServer(replies: [.pending(), .ready(), .ready(version: 2), .ready(version: 2)], heldRead: 2)
        let model = workspace(server)
        let old = Task { await model.load() }
        defer { old.cancel(); Task { await server.release() } }
        try await HubFixture.wait { await server.isHeld }
        try #require(await server.isHeld)
        model.stopLoading()
        await model.load()
        #expect(model.matchedRoute?.reconstructionVersion == 2)
        await server.release()
        await old.value
        #expect(model.matchedRoute?.reconstructionVersion == 2 && model.pointCount == 5)
    }

    @Test func readyWithNoReliableGeometryIsTerminalNotAnOutage() async {
        let server = ReplayMatchingServer(replies: [.ready(empty: true), .ready(empty: true)])
        let model = workspace(server)
        await model.load()
        #expect(model.matchingState == .noReliableMatch && model.errorMessage == nil)
        #expect(model.isComplete && model.pointCount == 3)
    }

    @Test func clientDoesNotSwallowCancellationOrAnotherCapturesResponse() async {
        let cancelled = ReplayMatchingServer(replies: [.cancelled])
        do {
            _ = try await client(cancelled).matchedRoute(schoolID: ConfigurationFixture.schoolID, captureID: cancelled.captureID)
            Issue.record("Cancellation must propagate")
        } catch { #expect(error is CancellationError) }
        let other = ReplayMatchingServer(replies: [.wrongCapture])
        do {
            _ = try await client(other).matchedRoute(schoolID: ConfigurationFixture.schoolID, captureID: other.captureID)
            Issue.record("Another capture must be refused")
        } catch { #expect(error as? SchoolCaptureFailure == .invalidResponse) }
    }

    private func client(_ server: ReplayMatchingServer) -> SchoolCaptureClient {
        SchoolCaptureClient(baseURL: URL(string: ConfigurationFixture.scope().apiBaseURL)!, tokenSource: HubToken(), transport: server)
    }

    private func workspace(_ server: ReplayMatchingServer) -> SchoolCaptureReplayWorkspace {
        SchoolCaptureReplayWorkspace(scope: ConfigurationFixture.scope(), client: client(server), captureID: server.captureID,
            sleep: { _ in try Task.checkCancellation() }, now: { 0 })
    }

    private func route(status: String, extra: String = "") throws -> SchoolMatchedRoute {
        let provider = status == "READY" ? "\"osrm\"" : "null"
        return try JSONDecoder().decode(SchoolMatchedRoute.self, from: Data("""
        {"captureId":"\(UUID())","status":"\(status)","provider":\(provider),"algorithmVersion":2,"reconstructionVersion":1,"spans":[]\(extra)}
        """.utf8))
    }
}

private actor ReplaySleepGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false
    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
        isWaiting = false
    }
}

private enum ReplayMatchingReply: Sendable {
    case pending(version: Int = 1, delay: Int = 2)
    case waiting(version: Int = 1)
    case ready(version: Int = 1, empty: Bool = false)
    case http(Int), cancelled, wrongCapture, legacyUnavailable
}

/// No network or real location. A held response deliberately ignores cancellation.
private actor ReplayMatchingServer: SchoolHTTPTransport {
    nonisolated let captureID = UUID()
    private let segmentID = UUID()
    private let observationID = UUID()
    private let scope = ConfigurationFixture.scope()
    private var replies: [ReplayMatchingReply]
    private var version = 1
    private let heldRead: Int?
    private let heldReplayRead: Int?
    private let pagedRefresh: Bool
    private(set) var sawContinuationCursor = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var isHeld = false
    private(set) var matchingReads = 0
    private(set) var replayReads = 0

    init(replies: [ReplayMatchingReply], heldRead: Int? = nil, heldReplayRead: Int? = nil, pagedRefresh: Bool = false) {
        self.replies = replies
        self.heldRead = heldRead
        self.heldReplayRead = heldReplayRead
        self.pagedRefresh = pagedRefresh
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
        isHeld = false
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url!
        func response(_ value: Any) throws -> SchoolHTTPResponse {
            SchoolHTTPResponse(data: try JSONSerialization.data(withJSONObject: ["data": value,
                "requestId": UUID().uuidString, "serverTime": "2026-10-01T12:00:00Z"]),
                status: 200, url: url, contentType: "application/json")
        }
        func encoded(_ value: some Encodable) throws -> SchoolHTTPResponse {
            try response(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)))
        }
        if url.lastPathComponent == "me" {
            return try encoded(SchoolPerson(personId: scope.personID, version: 1, displayName: "Moniteur synthétique", locale: "fr",
                memberships: [.init(membershipId: scope.membershipID, schoolId: scope.schoolID, schoolName: "École synthétique",
                    roles: ["INSTRUCTOR"], grants: [], accessEpoch: scope.accessEpoch)]))
        }
        if url.lastPathComponent == "matched-route" {
            matchingReads += 1
            guard !replies.isEmpty else { throw SchoolCaptureFailure.invalidResponse }
            let reply = replies.removeFirst()
            var status = "PENDING", reason = "PROCESSING"
            var provider: Any = NSNull(), delay: Any = NSNull()
            var spans: [[String: Any]] = []
            var returnedID = captureID
            switch reply {
            case .pending(let revision, let seconds):
                version = revision; delay = seconds
            case .waiting(let revision):
                version = revision; status = "UNAVAILABLE"; reason = "WAITING_FOR_SYNC"; delay = 2
            case .ready(let revision, let empty):
                version = revision; status = "READY"; reason = empty ? "NO_RELIABLE_MATCH" : "MATCHED"; provider = "osrm"
                let end = version * 2
                if !empty {
                    spans = [["segmentId": segmentID.uuidString, "firstSequence": 0, "lastSequence": end,
                        "confidence": 0.9, "geometry": Self.line(end: end), "anchors": [[0.0, 0.0], [Double(end), Double(end) * 11.1195]]]]
                }
            case .http(let code):
                return SchoolHTTPResponse(data: Data("{\"code\":\"UNAVAILABLE\"}".utf8), status: code,
                    url: url, contentType: "application/problem+json")
            case .cancelled: throw URLError(.cancelled)
            case .legacyUnavailable: status = "UNAVAILABLE"
            case .wrongCapture: returnedID = UUID()
            }
            var body: [String: Any] = ["captureId": returnedID.uuidString, "status": status, "reason": reason,
                "retryAfterSeconds": delay, "provider": provider, "algorithmVersion": 2, "reconstructionVersion": version,
                "spans": spans, "generatedAt": "2026-10-01T12:00:00Z"]
            if case .legacyUnavailable = reply {
                body.removeValue(forKey: "reason")
                body.removeValue(forKey: "retryAfterSeconds")
            }
            if matchingReads == heldRead {
                isHeld = true
                await withCheckedContinuation { releaseContinuation = $0 }
            }
            return try response(body)
        }
        if url.lastPathComponent == "replay" {
            replayReads += 1
            let start = SchoolLesson.date("2026-10-01T12:00:00Z")!
            let points = (0...(version * 2)).map { index in
                SchoolCapturePoint(sequence: index, elapsedMs: index * 1000,
                    capturedAt: SchoolCaptureLocationTime.timestamp(start.addingTimeInterval(Double(index))),
                    latitude: 0, longitude: Double(index) / 10_000, accuracyMeters: 3)
            }
            let observation = SchoolPrivateGeoObservation(id: observationID, schoolId: scope.schoolID, version: 1,
                lessonId: HubFixture.lessonID, trainingId: HubFixture.trainingID, draftId: nil,
                captureId: captureID, segmentId: segmentID, pointSequence: 1, competencyId: nil,
                text: "Observation synthétique", origin: "LIVE", observedAt: points[1].capturedAt,
                eventKind: "MARKER", eventStatus: nil, authorMembershipId: scope.membershipID)
            let paged = pagedRefresh && version >= 2
            let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value
            let continuation = paged && cursor == "synthetic-next"
            if continuation { sawContinuationCursor = true }
            let pagePoints = !paged ? points : continuation ? Array(points.dropFirst(2)) : Array(points.prefix(2))
            let page = SchoolPrivateReplayPage(captureId: captureID, quality: "SYNCED", publicationState: .privateCapture,
                segments: [.init(segmentId: segmentID, segmentIndex: 0, points: pagePoints, hasGapBefore: false,
                    qualityLabel: "AVAILABLE", continuesFromPreviousPage: continuation, continuesOnNextPage: paged && !continuation)],
                observations: paged && !continuation ? [] : [observation], nextCursor: paged && !continuation ? "synthetic-next" : nil,
                generatedAt: "2026-10-01T12:00:00Z", reportRevisionId: nil, geometrySnapshotId: nil)
            if replayReads == heldReplayRead {
                isHeld = true
                await withCheckedContinuation { releaseContinuation = $0 }
            }
            return try encoded(page)
        }
        if url.lastPathComponent.lowercased() == captureID.uuidString.lowercased() {
            return try encoded(SchoolCaptureSession(id: captureID, schoolId: scope.schoolID, version: version,
                lessonId: HubFixture.lessonID, learnerId: HubFixture.learnerID, instructorMembershipId: scope.membershipID,
                deviceId: nil, choiceId: UUID(), authorizedAt: "2026-10-01T12:00:00Z", expiresAt: "2026-10-01T14:00:00Z",
                stoppedAt: SchoolCaptureLocationTime.timestamp(SchoolLesson.date("2026-10-01T12:00:00Z")!.addingTimeInterval(Double(version) * 20)),
                cutoffAt: nil, uploadDeadline: "2026-10-02T14:00:00Z",
                captureState: .stopped, syncState: .synced, publicationState: .privateCapture, deviceAssessmentId: nil))
        }
        throw SchoolCaptureFailure.invalidResponse
    }

    private static func line(end: Int) -> String {
        // Two synthetic vertices, (0, 0) and (0, end / 10_000), precision six.
        var value = end * 100 * 2
        var encoded = "???"
        while value >= 0x20 {
            encoded.append(Character(UnicodeScalar(UInt8((0x20 | (value & 0x1f)) + 63))))
            value >>= 5
        }
        encoded.append(Character(UnicodeScalar(UInt8(value + 63))))
        return encoded
    }
}
