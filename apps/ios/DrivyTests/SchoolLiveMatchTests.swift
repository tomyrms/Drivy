import Foundation
import Testing
@testable import Drivy

/// Synthetic positions only. No recorded journey is included in these fixtures.
struct SchoolLiveMatchTests {
    private let segment = UUID()
    private let metre = 180 / (.pi * 6_371_000.0)

    private func point(_ sequence: Int, speed: Double? = 10) -> SchoolLiveMatchPoint {
        SchoolLiveMatchPoint(sequence: sequence, elapsedMs: sequence * 1_000,
            capturedAt: SchoolCaptureLocationTime.timestamp(Date(timeIntervalSince1970: 1_792_526_400 + Double(sequence))),
            latitude: 0, longitude: Double(sequence) * 10 * metre, accuracyMeters: 8, speed: speed)
    }

    private func matched(_ request: SchoolLiveMatchRequest, north: Double = 4,
                         confidence: Double = 0.95, distance: Double = 4) -> SchoolLiveMatchResponse {
        let last = request.points.last!
        return .init(status: .matched, segmentId: request.segmentId, sequence: last.sequence, elapsedMs: last.elapsedMs,
            position: .init(latitude: last.latitude + north * metre, longitude: last.longitude),
            confidence: confidence, distanceMeters: distance)
    }

    @Test func realWindowIsBoundedAndRequestsNeverOutrunCadence() throws {
        var window = SchoolLiveMatchWindow(segmentID: segment)
        window.append([point(0), point(1)])
        #expect(window.request(at: 0) == nil)
        window.append([point(2)])
        let first = try #require(window.request(at: 0))
        #expect(first.points == [point(0), point(1), point(2)])
        window.append([point(3)])
        #expect(window.request(at: 2.49) == nil)
        #expect(window.request(at: 2.5)?.points.last == point(3))
        window.append((4...100).map { point($0) })
        let bounded = try #require(window.request(at: 5))
        #expect(bounded.points == (81...100).map { point($0) })
        #expect(window.request(at: 8) == nil) // Never resend the same fix.
    }

    @Test func noWindowCrossesSilenceOrAcceptsDisorderedMeasurements() throws {
        var window = SchoolLiveMatchWindow(segmentID: segment)
        window.append([point(0), point(1), point(2), point(1)])
        #expect(window.request(at: 0)?.points.map(\.sequence) == [0, 1, 2])
        window.append([point(40)])
        #expect(window.request(at: 3) == nil)
    }

    @Test func onlyTheExactCurrentFixCanBeCorrectedWithinTheResponseDeadline() throws {
        var window = SchoolLiveMatchWindow(segmentID: segment)
        window.append([point(0), point(1), point(2)])
        let request = try #require(window.request(at: 10))
        let response = matched(request)
        #expect(window.accepts(response, for: request, sentAt: 10, now: 10.2))
        #expect(!window.accepts(response, for: request, sentAt: 10, now: 12.01))
        #expect(!window.accepts(response, for: request, sentAt: 10, now: 9))
        let wrongSegment = SchoolLiveMatchResponse(status: .matched, segmentId: UUID(), sequence: 2, elapsedMs: 2_000,
            position: response.position, confidence: 0.95, distanceMeters: 4)
        #expect(!window.accepts(wrongSegment, for: request, sentAt: 10, now: 10.2))
        let wrongSequence = SchoolLiveMatchResponse(status: .matched, segmentId: segment, sequence: 1, elapsedMs: 2_000,
            position: response.position, confidence: 0.95, distanceMeters: 4)
        #expect(!window.accepts(wrongSequence, for: request, sentAt: 10, now: 10.2))
        let wrongTime = SchoolLiveMatchResponse(status: .matched, segmentId: segment, sequence: 2, elapsedMs: 1_999,
            position: response.position, confidence: 0.95, distanceMeters: 4)
        #expect(!window.accepts(wrongTime, for: request, sentAt: 10, now: 10.2))
        window.append([point(3)])
        #expect(!window.accepts(response, for: request, sentAt: 10, now: 10.3))
    }

    @Test func parkingLowConfidenceAndExcessDistanceNeverForceTheMarker() throws {
        var window = SchoolLiveMatchWindow(segmentID: segment)
        window.append([point(0), point(1), point(2)])
        let request = try #require(window.request(at: 0))
        #expect(!window.accepts(matched(request, confidence: 0.79), for: request, sentAt: 0, now: 0.1))
        #expect(!window.accepts(matched(request, distance: 30), for: request, sentAt: 0, now: 0.1))
        // Do not trust only the server's distance field.
        #expect(!window.accepts(matched(request, north: 40), for: request, sentAt: 0, now: 0.1))
        var parking = SchoolLiveMatchWindow(segmentID: segment)
        parking.append([point(0), point(1), point(2, speed: 0.5)])
        #expect(parking.request(at: 0) == nil)
        let unavailable = SchoolLiveMatchResponse(status: .unavailable, segmentId: segment, sequence: 2, elapsedMs: 2_000,
            position: nil, confidence: nil, distanceMeters: nil)
        #expect(!window.accepts(unavailable, for: request, sentAt: 0, now: 0.1))
    }

    @Test func aRoadCorrectionPreservesPredictionClockAndNeverJumpsOrChangesTheFix() throws {
        var predictor = SchoolMapPredictor()
        predictor.receive(latitude: 0, longitude: 0, speed: 10, course: 90, at: 0, instant: true)
        let before = try #require(predictor.position(at: 0.2))
        #expect(predictor.correctRoadPosition(latitude: 4 * metre, longitude: 0, at: 0.2))
        let after = try #require(predictor.position(at: 0.2))
        #expect(abs(after.latitude - before.latitude) < 1e-12)
        #expect(abs(after.longitude - before.longitude) < 1e-12)
        let rolling = try #require(predictor.position(at: 1))
        #expect(rolling.latitude / metre > 3 && rolling.latitude / metre < 4)
        #expect(abs(rolling.longitude / metre - 10) < 0.01)
        // A road result must not restart the 1.6s prediction horizon.
        #expect(abs(try #require(predictor.position(at: 3)).longitude / metre - 16) < 0.01)
        let priorToFix = try #require(predictor.position(at: 3))
        predictor.receive(latitude: 0, longitude: 30 * metre, speed: 10, course: 90, at: 3)
        #expect(abs(try #require(predictor.position(at: 3)).latitude - priorToFix.latitude) < 1e-12)
        #expect(abs(try #require(predictor.position(at: 6)).latitude / metre) < 0.02)
        #expect(!predictor.correctRoadPosition(latitude: 1, longitude: 1, at: 6))
        predictor.reset()
        #expect(!predictor.correctRoadPosition(latitude: 0, longitude: 0, at: 7))
    }
}

@MainActor
struct SchoolLiveMatchTransportTests {
    private let base = URL(string: "https://example.invalid")!
    private let segment = UUID()
    private var scope: SchoolCommandScope {
        .init(personID: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
            schoolID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            membershipID: UUID(uuidString: "30000000-0000-4000-8000-000000000002")!,
            accessEpoch: 1, apiBaseURL: base.absoluteString)
    }
    private var request: SchoolLiveMatchRequest {
        .init(segmentId: segment, points: (0...2).map { index in
            .init(sequence: index, elapsedMs: index * 1_000, capturedAt: "2026-10-20T20:00:0\(index).000Z",
                latitude: 0, longitude: Double(index) * 0.0001, accuracyMeters: 8, speed: 10)
        })
    }

    @Test func postUsesPinnedIdentityScopeAndOnlyRealMeasurementsWithoutJournalOrRetry() async throws {
        let transport = LiveMatchTransport(scope: scope)
        let client = SchoolCaptureClient(baseURL: base, tokenSource: LiveMatchToken(), transport: transport)
        let capture = UUID()
        let result = try await client.liveMatch(scope: scope, captureID: capture, request: request)
        #expect(result.status == .matched)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.url?.path == "/v1/me")
        let post = try #require(requests.last)
        #expect(post.url?.path.lowercased() == "/v1/schools/\(scope.schoolID)/captures/\(capture)/live-match".lowercased())
        #expect(post.httpMethod == "POST")
        #expect(post.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-live-token")
        #expect(post.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(post.value(forHTTPHeaderField: "Idempotency-Key") == nil)
        #expect(post.timeoutInterval <= 2)
        #expect(try JSONDecoder().decode(SchoolLiveMatchRequest.self, from: #require(post.httpBody)) == request)
    }

    @Test func revokedScopeNeverSendsCoordinates() async throws {
        let transport = LiveMatchTransport(scope: scope, epoch: 2)
        let client = SchoolCaptureClient(baseURL: base, tokenSource: LiveMatchToken(), transport: transport)
        await #expect(throws: SchoolCaptureFailure.forbidden) {
            try await client.liveMatch(scope: scope, captureID: UUID(), request: request)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func serverFailureDoesNotRetryAndCancellationRemainsCancellation() async throws {
        let failed = LiveMatchTransport(scope: scope, status: 503)
        let client = SchoolCaptureClient(baseURL: base, tokenSource: LiveMatchToken(), transport: failed)
        await #expect(throws: SchoolCaptureFailure.unavailable) {
            try await client.liveMatch(scope: scope, captureID: UUID(), request: request)
        }
        #expect(await failed.requests.count == 2)
        let cancelled = LiveMatchTransport(scope: scope, cancel: true)
        let interrupted = SchoolCaptureClient(baseURL: base, tokenSource: LiveMatchToken(), transport: cancelled)
        await #expect(throws: CancellationError.self) {
            try await interrupted.liveMatch(scope: scope, captureID: UUID(), request: request)
        }
    }

    @Test func slowResponseIsCancelledAtTheTotalDeadline() async throws {
        let transport = LiveMatchTransport(scope: scope, slow: true)
        let client = SchoolCaptureClient(baseURL: base, tokenSource: LiveMatchToken(), transport: transport)
        let start = ContinuousClock.now
        await #expect(throws: SchoolCaptureFailure.unavailable) {
            try await client.liveMatch(scope: scope, captureID: UUID(), request: request)
        }
        #expect(start.duration(to: .now) < .seconds(4))
        #expect(await transport.wasCancelled)
    }
}

@MainActor
struct SchoolLiveMatchLifecycleTests {
    @Test(arguments: ["pause", "context", "newerFix"])
    func lifecycleChangesCancelAnInFlightRequest(_ change: String) async throws {
        let segment = UUID()
        let coordinator = SchoolLiveMatchCoordinator(now: { 0 })
        let (events, continuation) = AsyncStream<Void>.makeStream()
        var eventsIterator = events.makeAsyncIterator()
        coordinator.start(segmentID: segment, permits: { true }, send: { request in
            continuation.yield(())
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                continuation.yield(())
                throw error
            }
            Issue.record("An obsolete request must be cancelled before completion")
            return .init(status: .unavailable, segmentId: request.segmentId, sequence: 2, elapsedMs: 2_000,
                         position: nil, confidence: nil, distanceMeters: nil)
        })
        let measurements = (0...2).map { index in
            SchoolCaptureMeasurement(capturedAt: "2026-10-20T20:00:0\(index)Z", elapsedMs: index * 1_000,
                latitude: 0, longitude: Double(index) * 0.0001, accuracyMeters: 8, speedMetersPerSecond: 10)
        }
        coordinator.appendDurable(measurements, startingAt: 0, segmentID: segment)
        _ = await eventsIterator.next() // Transport actually started, not a scheduling guess.
        switch change {
        case "context":
            coordinator.start(segmentID: UUID(), permits: { true }, send: { _ in
                Issue.record("No measurement belongs to the new context yet")
                throw CancellationError()
            })
        case "newerFix": coordinator.measurementArrived(segmentID: segment, elapsedMs: 3_000)
        default: coordinator.stop()
        }
        _ = await eventsIterator.next() // The in-flight operation observed cancellation.
        #expect(coordinator.result == nil)
        coordinator.stop()
        continuation.finish()
    }

    @Test func attributionContainsNoCaptureOrLocationContext() {
        let url = SchoolMapAttributionSection.copyrightURL
        #expect(url.scheme == "https")
        #expect(url.host == "www.openstreetmap.org")
        #expect(url.path == "/copyright")
        #expect(url.query == nil && url.fragment == nil && url.user == nil && url.password == nil)
    }

    @Test func anExpiredLeaseNeverSendsMeasurements() async {
        let coordinator = SchoolLiveMatchCoordinator()
        let segment = UUID()
        coordinator.start(segmentID: segment, permits: { false }, send: { _ in
            Issue.record("Expired capture must not send coordinates")
            throw CancellationError()
        })
        let measurement = SchoolCaptureMeasurement(capturedAt: "2026-10-20T20:00:00Z", elapsedMs: 0,
            latitude: 0, longitude: 0, accuracyMeters: 8)
        coordinator.appendDurable([measurement], startingAt: 0, segmentID: segment)
        #expect(coordinator.result == nil)
    }
}

@MainActor private final class LiveMatchToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-live-token" }
}

private actor LiveMatchTransport: SchoolHTTPTransport {
    let scope: SchoolCommandScope
    let epoch: Int
    let status: Int
    let cancel: Bool
    let slow: Bool
    private(set) var requests: [URLRequest] = []
    private(set) var wasCancelled = false
    init(scope: SchoolCommandScope, epoch: Int = 1, status: Int = 200, cancel: Bool = false, slow: Bool = false) {
        self.scope = scope
        self.epoch = epoch
        self.status = status
        self.cancel = cancel
        self.slow = slow
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        requests.append(request)
        let isIdentity = request.url!.path == "/v1/me"
        if !isIdentity, cancel { throw URLError(.cancelled) }
        if !isIdentity, slow {
            do { try await Task.sleep(for: .seconds(30)) }
            catch { wasCancelled = true; throw error }
        }
        let value: [String: Any]
        if isIdentity {
            value = ["personId": scope.personID.uuidString, "displayName": "Synthetic", "locale": "fr-CH", "version": 1,
                "memberships": [["membershipId": scope.membershipID.uuidString, "schoolId": scope.schoolID.uuidString,
                    "schoolName": "Synthetic", "roles": ["INSTRUCTOR"], "grants": [], "accessEpoch": epoch]]]
        } else {
            let body = try JSONDecoder().decode(SchoolLiveMatchRequest.self, from: request.httpBody!)
            let last = body.points.last!
            value = ["status": "MATCHED", "segmentId": body.segmentId.uuidString, "sequence": last.sequence,
                "elapsedMs": last.elapsedMs, "position": ["latitude": last.latitude, "longitude": last.longitude],
                "confidence": 0.95, "distanceMeters": 0]
        }
        let data = try JSONSerialization.data(withJSONObject: ["data": value, "requestId": "synthetic-request", "serverTime": "2026-10-20T20:00:03Z"])
        return SchoolHTTPResponse(data: data, status: isIdentity ? 200 : status, url: request.url!, contentType: "application/json")
    }
}
