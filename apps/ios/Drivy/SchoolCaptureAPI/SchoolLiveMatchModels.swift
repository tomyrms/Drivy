import Foundation

/// Ephemeral transport of real fixes only. Never enters the capture outbox or replay.
struct SchoolLiveMatchPoint: Codable, Sendable, Equatable {
    let sequence: Int
    let elapsedMs: Int
    let capturedAt: String
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
    let speed: Double?

    init(sequence: Int, elapsedMs: Int, capturedAt: String, latitude: Double, longitude: Double,
         accuracyMeters: Double, speed: Double?) {
        self.sequence = sequence
        self.elapsedMs = elapsedMs
        self.capturedAt = capturedAt
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.speed = speed
    }

    init(sequence: Int, measurement: SchoolCaptureMeasurement) {
        self.init(sequence: sequence, elapsedMs: measurement.elapsedMs, capturedAt: measurement.capturedAt,
            latitude: measurement.latitude, longitude: measurement.longitude, accuracyMeters: measurement.accuracyMeters,
            speed: measurement.speedMetersPerSecond.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
    }

    var isValid: Bool {
        (0...2_147_483_646).contains(sequence) && (0...10_800_000).contains(elapsedMs) && SchoolLesson.date(capturedAt) != nil
            && latitude.isFinite && (-90...90).contains(latitude)
            && longitude.isFinite && (-180...180).contains(longitude)
            && accuracyMeters.isFinite && accuracyMeters >= 0 && accuracyMeters <= 30
            && (speed.map { $0.isFinite && (0...100).contains($0) } ?? true)
    }
}

struct SchoolLiveMatchRequest: Codable, Sendable, Equatable {
    let segmentId: UUID
    let points: [SchoolLiveMatchPoint]

    var isValid: Bool {
        guard (3...20).contains(points.count), points.allSatisfy(\.isValid),
              let first = points.first, let last = points.last,
              last.elapsedMs - first.elapsedMs <= 30_000 else { return false }
        let dates = points.compactMap { SchoolLesson.date($0.capturedAt) }
        guard dates.count == points.count, dates.last!.timeIntervalSince(dates.first!) <= 30 else { return false }
        return points.indices.dropFirst().allSatisfy { index in
            let previous = points[index - 1], next = points[index]
            let wallMs = dates[index].timeIntervalSince(dates[index - 1]) * 1_000
            return next.sequence > previous.sequence && next.elapsedMs > previous.elapsedMs && wallMs > 0
                && abs(Double(next.elapsedMs - previous.elapsedMs) - wallMs) <= 1_000
        }
    }
}

/// A display suggestion, not a measurement. No Codable conformance for encoding or persistence.
struct SchoolLiveMatchResponse: Decodable, Sendable, Equatable {
    enum Status: String, Decodable, Sendable { case matched = "MATCHED", unavailable = "UNAVAILABLE" }
    struct Position: Decodable, Sendable, Equatable {
        let latitude: Double
        let longitude: Double
        var isValid: Bool {
            latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
        }
    }
    let status: Status
    let segmentId: UUID
    let sequence: Int
    let elapsedMs: Int
    let position: Position?
    let confidence: Double?
    let distanceMeters: Double?

    func matches(_ request: SchoolLiveMatchRequest) -> Bool {
        guard let last = request.points.last, segmentId == request.segmentId,
              sequence == last.sequence, elapsedMs == last.elapsedMs else { return false }
        switch status {
        case .unavailable: return position == nil && confidence == nil && distanceMeters == nil
        case .matched:
            guard let position, position.isValid, let confidence, confidence.isFinite, (0...1).contains(confidence),
                  let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 else { return false }
            return true
        }
    }
}

/// Deterministic cadence and freshness gate. It owns only a small window of actual measurements.
struct SchoolLiveMatchWindow {
    static let interval: TimeInterval = 2.5
    static let responseLifetime: TimeInterval = 2
    let segmentID: UUID
    private var points: [SchoolLiveMatchPoint] = []
    private var latest: SchoolLiveMatchPoint?
    private var lastRequestAt: TimeInterval?
    private var lastRequestedSequence: Int?

    mutating func append(_ added: [SchoolLiveMatchPoint]) {
        for point in added {
            if let latest, point.sequence <= latest.sequence || point.elapsedMs <= latest.elapsedMs { continue }
            if let latest, point.elapsedMs - latest.elapsedMs > 4_000 { points.removeAll(keepingCapacity: true) }
            latest = point // Even a rejected fix makes an older response stale.
            guard point.isValid else { points.removeAll(keepingCapacity: true); continue }
            points.append(point)
            points.removeAll { point.elapsedMs - $0.elapsedMs > 30_000 }
            if points.count > 20 { points.removeFirst(points.count - 20) }
        }
    }

    mutating func request(at now: TimeInterval) -> SchoolLiveMatchRequest? {
        guard now.isFinite, let latest, latest == points.last,
              lastRequestedSequence != latest.sequence,
              lastRequestAt.map({ now - $0 >= Self.interval }) ?? true,
              latest.speed.map({ $0 >= 2 }) ?? true else { return nil }
        let request = SchoolLiveMatchRequest(segmentId: segmentID, points: points)
        guard request.isValid else { return nil }
        lastRequestAt = now
        lastRequestedSequence = latest.sequence
        return request
    }

    func accepts(_ response: SchoolLiveMatchResponse, for request: SchoolLiveMatchRequest,
                 sentAt: TimeInterval, now: TimeInterval) -> Bool {
        guard now.isFinite, sentAt.isFinite, (0...Self.responseLifetime).contains(now - sentAt),
              request.segmentId == segmentID, request.points.last == latest,
              response.matches(request), response.status == .matched,
              let point = latest, let position = response.position,
              let confidence = response.confidence, confidence >= 0.8,
              let distance = response.distanceMeters, point.speed.map({ $0 >= 2 }) ?? true else { return false }
        let maximumDistance = min(20, max(5, point.accuracyMeters))
        return distance <= maximumDistance && SchoolTrackGeometry.meters(latitude1: point.latitude, longitude1: point.longitude,
            latitude2: position.latitude, longitude2: position.longitude) <= maximumDistance
    }
}
