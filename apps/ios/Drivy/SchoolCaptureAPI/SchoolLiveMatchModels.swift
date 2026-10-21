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
        guard (3...30).contains(points.count), points.allSatisfy(\.isValid),
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
    /// Road geometry between the retained measurements: `coordinates` as [latitude, longitude], `anchors` as
    /// [measurement sequence, vertex index]. Display only, like the position.
    struct Route: Decodable, Sendable, Equatable {
        let coordinates: [[Double]]
        let anchors: [[Int]]
    }
    let status: Status
    let segmentId: UUID
    let sequence: Int
    let elapsedMs: Int
    let position: Position?
    let confidence: Double?
    let distanceMeters: Double?
    var route: Route? = nil

    init(status: Status, segmentId: UUID, sequence: Int, elapsedMs: Int, position: Position?, confidence: Double?,
         distanceMeters: Double?, route: Route? = nil) {
        self.status = status; self.segmentId = segmentId; self.sequence = sequence; self.elapsedMs = elapsedMs
        self.position = position; self.confidence = confidence; self.distanceMeters = distanceMeters; self.route = route
    }

    func matches(_ request: SchoolLiveMatchRequest) -> Bool {
        guard let last = request.points.last, segmentId == request.segmentId,
              sequence == last.sequence, elapsedMs == last.elapsedMs else { return false }
        switch status {
        case .unavailable: return position == nil && confidence == nil && distanceMeters == nil && route == nil
        case .matched:
            guard let position, position.isValid, let confidence, confidence.isFinite, (0...1).contains(confidence),
                  let distanceMeters, distanceMeters.isFinite, distanceMeters >= 0 else { return false }
            return true
        }
    }

    /// The route checked against the measurements that were sent: increasing anchors on real fixes of the request,
    /// each within the admitted correction of its fix, the last one on the returned position. Nil if anything differs.
    func roadRoute(for request: SchoolLiveMatchRequest) -> SchoolLiveRoadRoute? {
        guard status == .matched, matches(request), let route, let position,
              (2...400).contains(route.coordinates.count), (3...30).contains(route.anchors.count) else { return nil }
        var vertices: [SchoolLiveRoadRoute.Vertex] = []
        vertices.reserveCapacity(route.coordinates.count)
        for pair in route.coordinates {
            guard pair.count == 2, pair[0].isFinite, pair[1].isFinite, (-90...90).contains(pair[0]), (-180...180).contains(pair[1]) else { return nil }
            vertices.append(.init(latitude: pair[0], longitude: pair[1]))
        }
        let points = Dictionary(request.points.map { ($0.sequence, $0) }, uniquingKeysWith: { first, _ in first })
        var anchors: [(sequence: Int, index: Int)] = []
        for pair in route.anchors {
            guard pair.count == 2, let point = points[pair[0]], vertices.indices.contains(pair[1]) else { return nil }
            if let previous = anchors.last, pair[0] <= previous.sequence || pair[1] <= previous.index { return nil }
            let vertex = vertices[pair[1]]
            guard SchoolTrackGeometry.meters(latitude1: point.latitude, longitude1: point.longitude,
                latitude2: vertex.latitude, longitude2: vertex.longitude) <= SchoolLiveMatchWindow.maximumCorrection(point.accuracyMeters) else { return nil }
            anchors.append((pair[0], pair[1]))
        }
        guard anchors.first?.index == 0, anchors.last?.index == vertices.count - 1, anchors.last?.sequence == sequence,
              let end = vertices.last, SchoolTrackGeometry.meters(latitude1: end.latitude, longitude1: end.longitude,
                  latitude2: position.latitude, longitude2: position.longitude) <= 1 else { return nil }
        return SchoolLiveRoadRoute(segmentID: segmentId, vertices: vertices, anchors: anchors)
    }
}

/// A road stretch between real measurements, accepted for display. It never becomes a measurement.
struct SchoolLiveRoadRoute: Sendable, Equatable {
    struct Vertex: Sendable, Equatable { let latitude: Double; let longitude: Double }
    let segmentID: UUID
    let vertices: [Vertex]
    let anchors: [(sequence: Int, index: Int)]

    static func == (a: Self, b: Self) -> Bool {
        a.segmentID == b.segmentID && a.vertices == b.vertices && a.anchors.elementsEqual(b.anchors, by: { $0 == $1 })
    }
}

/// Deterministic cadence and freshness gate. It owns only a small window of actual measurements.
struct SchoolLiveMatchWindow {
    static let interval: TimeInterval = 2.5
    static let responseLifetime: TimeInterval = 2
    /// Same admission as the school (#90): a fix and its road place may differ by 2.5 times its accuracy, 10 to 25 m.
    static let minimumConfidence = 0.6
    static func maximumCorrection(_ accuracyMeters: Double) -> Double { min(25, max(10, accuracyMeters * 2.5)) }
    static let capacity = 30
    let segmentID: UUID
    private var points: [SchoolLiveMatchPoint] = []
    private var latest: SchoolLiveMatchPoint?
    private var lastRequestAt: TimeInterval?
    private var lastRequestedSequence: Int?

    init(segmentID: UUID) { self.segmentID = segmentID }

    mutating func append(_ added: [SchoolLiveMatchPoint]) {
        for point in added {
            if let latest, point.sequence <= latest.sequence || point.elapsedMs <= latest.elapsedMs { continue }
            if let latest, point.elapsedMs - latest.elapsedMs > 4_000 { points.removeAll(keepingCapacity: true) }
            latest = point // Even a rejected fix makes an older response stale.
            guard point.isValid else { points.removeAll(keepingCapacity: true); continue }
            points.append(point)
            points.removeAll { point.elapsedMs - $0.elapsedMs > 30_000 }
            if points.count > Self.capacity { points.removeFirst(points.count - Self.capacity) }
        }
    }

    /// No speed gate: the school spaces the fixes itself and refuses a stationary window without calling the engine.
    mutating func request(at now: TimeInterval) -> SchoolLiveMatchRequest? {
        guard now.isFinite, let latest, latest == points.last,
              lastRequestedSequence != latest.sequence,
              lastRequestAt.map({ now - $0 >= Self.interval }) ?? true else { return nil }
        let request = SchoolLiveMatchRequest(segmentId: segmentID, points: points)
        guard request.isValid else { return nil }
        lastRequestAt = now
        lastRequestedSequence = latest.sequence
        return request
    }

    /// The position moves the marker only for the current fix, within the display lifetime.
    func accepts(_ response: SchoolLiveMatchResponse, for request: SchoolLiveMatchRequest,
                 sentAt: TimeInterval, now: TimeInterval) -> Bool {
        guard now.isFinite, sentAt.isFinite, (0...Self.responseLifetime).contains(now - sentAt),
              request.segmentId == segmentID, request.points.last == latest,
              response.matches(request), response.status == .matched,
              let point = latest, let position = response.position,
              let confidence = response.confidence, confidence >= Self.minimumConfidence,
              let distance = response.distanceMeters else { return false }
        let maximumDistance = Self.maximumCorrection(point.accuracyMeters)
        return distance <= maximumDistance && SchoolTrackGeometry.meters(latitude1: point.latitude, longitude1: point.longitude,
            latitude2: position.latitude, longitude2: position.longitude) <= maximumDistance
    }
}
