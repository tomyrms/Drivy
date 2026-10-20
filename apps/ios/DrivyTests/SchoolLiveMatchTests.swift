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
        let tooShort = window.request(at: 0)
        #expect(tooShort == nil)
        window.append([point(2)])
        let firstRequest = window.request(at: 0)
        let first = try #require(firstRequest)
        #expect(first.points == [point(0), point(1), point(2)])
        window.append([point(3)])
        let tooEarly = window.request(at: 2.49)
        #expect(tooEarly == nil)
        let nextRequest = window.request(at: 2.5)
        #expect(nextRequest?.points.last == point(3))
        window.append((4...100).map { point($0) })
        let boundedRequest = window.request(at: 5)
        let bounded = try #require(boundedRequest)
        #expect(bounded.points == (81...100).map { point($0) })
        let duplicate = window.request(at: 8)
        #expect(duplicate == nil) // Never resend the same fix.
    }

    @Test func requestRejectsClockDriftAndContractBoundsBeforeSending() {
        let first = point(0), second = point(1), last = point(2)
        let drifted = SchoolLiveMatchPoint(sequence: last.sequence, elapsedMs: last.elapsedMs,
            capturedAt: point(8).capturedAt, latitude: last.latitude, longitude: last.longitude,
            accuracyMeters: last.accuracyMeters, speed: last.speed)
        #expect(!SchoolLiveMatchRequest(segmentId: segment, points: [first, second, drifted]).isValid)
        let tooLong = SchoolLiveMatchPoint(sequence: 2, elapsedMs: 10_800_001, capturedAt: last.capturedAt,
            latitude: 0, longitude: 0, accuracyMeters: 8, speed: nil)
        #expect(!tooLong.isValid)
    }

    @Test func noWindowCrossesSilenceOrAcceptsDisorderedMeasurements() throws {
        var window = SchoolLiveMatchWindow(segmentID: segment)
        window.append([point(0), point(1), point(2), point(1)])
        let orderedRequest = window.request(at: 0)
        #expect(orderedRequest?.points.map(\.sequence) == [0, 1, 2])
        window.append([point(40)])
        let afterSilence = window.request(at: 3)
        #expect(afterSilence == nil)
    }

    @Test func onlyTheExactCurrentFixCanBeCorrectedWithinTheResponseDeadline() throws {
        var window = SchoolLiveMatchWindow(segmentID: segment)
        window.append([point(0), point(1), point(2)])
        let candidate = window.request(at: 10)
        let request = try #require(candidate)
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
        let candidate = window.request(at: 0)
        let request = try #require(candidate)
        #expect(!window.accepts(matched(request, confidence: 0.79), for: request, sentAt: 0, now: 0.1))
        #expect(!window.accepts(matched(request, distance: 30), for: request, sentAt: 0, now: 0.1))
        // Do not trust only the server's distance field.
        #expect(!window.accepts(matched(request, north: 40), for: request, sentAt: 0, now: 0.1))
        var parking = SchoolLiveMatchWindow(segmentID: segment)
        parking.append([point(0), point(1), point(2, speed: 0.5)])
        let parkedRequest = parking.request(at: 0)
        #expect(parkedRequest == nil)
        let unavailable = SchoolLiveMatchResponse(status: .unavailable, segmentId: segment, sequence: 2, elapsedMs: 2_000,
            position: nil, confidence: nil, distanceMeters: nil)
        #expect(!window.accepts(unavailable, for: request, sentAt: 0, now: 0.1))
    }

    @Test @MainActor func roadDisplayNeverChangesTheTraceOrObservationAnchor() throws {
        let measurements = (0...2).map { index in
            SchoolCaptureMeasurement(capturedAt: "2026-10-20T20:00:0\(index)Z", elapsedMs: index * 1_000,
                latitude: 0, longitude: Double(index) * 10 * metre, accuracyMeters: 8,
                speedMetersPerSecond: 10, courseDegrees: 90)
        }
        let mapSegment = SchoolCaptureMapSegment(id: segment, measurements: measurements)
        let trace = SchoolLiveTrace()
        trace.update([mapSegment])
        let before = try #require(trace.coordinate(segmentID: segment, sequence: 2))
        let motion = SchoolLiveMapMotion()
        motion.show(trace.position, fix: mapSegment.liveFix)
        let request = SchoolLiveMatchRequest(segmentId: segment, points: (0...2).map { point($0) })
        motion.showRoadMatch(matched(request, confidence: 0.1), segment: mapSegment)
        #expect(try #require(motion.pose(at: 1e12)).latitude == 0)
        motion.showRoadMatch(matched(request, north: 40), segment: mapSegment)
        #expect(try #require(motion.pose(at: 1e12)).latitude == 0)
        motion.showRoadMatch(matched(request), segment: mapSegment)
        #expect(try #require(motion.pose(at: 1e12)).latitude > 0)
        let after = try #require(trace.coordinate(segmentID: segment, sequence: 2))
        #expect(after.latitude == before.latitude && after.longitude == before.longitude)
        #expect(mapSegment.lastPoint?.latitude == 0)
        #expect(mapSegment.lastPoint?.longitude == measurements.last?.longitude)
        #expect(mapSegment.measurementCount == 3)
        #expect(trace.position?.point == mapSegment.lastPoint)
        motion.showRoadMatch(nil, segment: mapSegment)
        #expect(trace.coordinate(segmentID: segment, sequence: 2)?.latitude == 0)
    }

    @Test func aRoadCorrectionPreservesPredictionClockAndNeverJumpsOrChangesTheFix() throws {
        var predictor = SchoolMapPredictor()
        predictor.receive(latitude: 0, longitude: 0, speed: 10, course: 90, at: 0, instant: true)
        let before = try #require(predictor.position(at: 0.2))
        let corrected = predictor.correctRoadPosition(latitude: 4 * metre, longitude: 0, at: 0.2)
        #expect(corrected)
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
        let excessiveCorrection = predictor.correctRoadPosition(latitude: 1, longitude: 1, at: 6)
        #expect(!excessiveCorrection)
        predictor.reset()
        let correctionWithoutFix = predictor.correctRoadPosition(latitude: 0, longitude: 0, at: 7)
        #expect(!correctionWithoutFix)
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

    @Test(arguments: [false, true])
    func aSuspendedSharedTokenDoesNotBlockTimeoutOrCancellation(_ cancel: Bool) async throws {
        let token = SuspendedLiveMatchToken()
        let transport = LiveMatchTransport(scope: scope)
        let client = SchoolCaptureClient(baseURL: base, tokenSource: token, transport: transport)
        var starts = token.starts.makeAsyncIterator()
        // A broken implementation eventually exits too, so the test fails instead of hanging CI.
        let rescue = Task { try? await Task.sleep(for: .seconds(5)); token.release() }
        defer { rescue.cancel(); token.release() }
        let began = ContinuousClock.now
        let operation = Task { try await client.liveMatch(scope: scope, captureID: UUID(), request: request) }
        _ = await starts.next()
        if cancel { operation.cancel() }
        do {
            _ = try await operation.value
            Issue.record("A suspended identity must not complete live matching")
        } catch {
            if cancel { #expect(error is CancellationError) }
            else { #expect(error as? SchoolCaptureFailure == .unavailable) }
        }
        #expect(began.duration(to: .now) < .seconds(cancel ? 1 : 3))
        #expect(!token.wasReleased)
        #expect(token.calls == 1)
        #expect(await transport.requests.isEmpty)
        token.release()
        var completions = token.completions.makeAsyncIterator()
        _ = await completions.next()
        #expect(!token.refreshWasCancelled)
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
    @Test(arguments: [SchoolCaptureFailure.unauthorized, .forbidden, .notFound, .expired, .unavailable, .invalidResponse])
    func onlyAccessFailuresAskForCanonicalRevalidation(_ failure: SchoolCaptureFailure) async {
        let coordinator = SchoolLiveMatchCoordinator(now: { 0 })
        let segment = UUID()
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        var iterator = completion.makeAsyncIterator()
        var accessChecks = 0
        coordinator.start(segmentID: segment, permits: { true }, onAccessFailure: { accessChecks += 1 }, send: { _ in
            defer { continuation.finish() }
            throw failure
        })
        let measurements = (0...2).map { index in
            SchoolCaptureMeasurement(capturedAt: "2026-10-20T20:00:0\(index)Z", elapsedMs: index * 1_000,
                latitude: 0, longitude: Double(index) * 0.0001, accuracyMeters: 8, speedMetersPerSecond: 10)
        }
        coordinator.appendDurable(measurements, startingAt: 0, segmentID: segment)
        _ = await iterator.next()
        #expect(accessChecks == ([.unauthorized, .forbidden, .notFound, .expired].contains(failure) ? 1 : 0))
        #expect(coordinator.result == nil)
        coordinator.stop()
    }

    @Test(arguments: ["pause", "context", "newerFix"])
    func lifecycleChangesCancelAnInFlightRequest(_ change: String) async throws {
        let segment = UUID()
        let coordinator = SchoolLiveMatchCoordinator(now: { 0 })
        let (events, continuation) = AsyncStream<Void>.makeStream()
        var eventsIterator = events.makeAsyncIterator()
        coordinator.start(segmentID: segment, permits: { true }, send: { request in
            defer { continuation.finish() }
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

    @Test func aLateResponseGetsOnlyTheRemainingDisplayLifetime() async throws {
        var now = 10.0
        let (waits, continuation) = AsyncStream<TimeInterval>.makeStream()
        var iterator = waits.makeAsyncIterator()
        let coordinator = SchoolLiveMatchCoordinator(now: { now }, sleep: { duration in
            continuation.yield(duration)
            try await Task.sleep(for: .seconds(30))
        })
        let segment = UUID()
        coordinator.start(segmentID: segment, permits: { true }, send: { request in
            now = 11.9
            let last = request.points.last!
            return .init(status: .matched, segmentId: request.segmentId, sequence: last.sequence, elapsedMs: last.elapsedMs,
                position: .init(latitude: last.latitude, longitude: last.longitude), confidence: 0.9, distanceMeters: 0)
        })
        let measurements = (0...2).map { index in
            SchoolCaptureMeasurement(capturedAt: "2026-10-20T20:00:0\(index)Z", elapsedMs: index * 1_000,
                latitude: 0, longitude: Double(index) * 0.0001, accuracyMeters: 8, speedMetersPerSecond: 10)
        }
        coordinator.appendDurable(measurements, startingAt: 0, segmentID: segment)
        let nextWait = await iterator.next()
        let remaining = try #require(nextWait)
        #expect(abs(remaining - 0.1) < 0.000_001)
        #expect(coordinator.result != nil)
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

@MainActor private final class SuspendedLiveMatchToken: AccessTokenSource {
    let starts: AsyncStream<Void>
    let completions: AsyncStream<Void>
    private let started: AsyncStream<Void>.Continuation
    private let completed: AsyncStream<Void>.Continuation
    private var pending: CheckedContinuation<String, Error>?
    private(set) var calls = 0
    private(set) var wasReleased = false
    private(set) var refreshWasCancelled = false

    init() {
        let startStream = AsyncStream<Void>.makeStream()
        starts = startStream.stream
        started = startStream.continuation
        let completionStream = AsyncStream<Void>.makeStream()
        completions = completionStream.stream
        completed = completionStream.continuation
    }
    func accessToken() async throws -> String {
        calls += 1
        started.yield(())
        let token = try await withCheckedThrowingContinuation { pending = $0 }
        refreshWasCancelled = Task.isCancelled
        completed.yield(())
        return token
    }
    func release() {
        wasReleased = true
        pending?.resume(returning: "synthetic-live-token")
        pending = nil
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
