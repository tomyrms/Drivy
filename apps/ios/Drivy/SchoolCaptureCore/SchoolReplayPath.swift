import Foundation

/// Road-matched layer of a capture, computed by the school server after the lesson.
/// It never replaces the measurements: a span only says « between these two measured
/// fixes, the vehicle most likely followed this road geometry ». Where no span exists,
/// the measured line is drawn.
struct SchoolMatchedRoute: Decodable, Sendable, Equatable {
    struct Span: Decodable, Sendable, Equatable {
        let segmentId: UUID
        let firstSequence: Int
        let lastSequence: Int
        let confidence: Double
        /// Encoded polyline, precision 6.
        let geometry: String
        /// `[sequence, metres along the geometry]` for each measured fix the matcher placed on the road.
        let anchors: [[Double]]
    }
    let captureId: UUID
    let status: String
    let spans: [Span]

    /// The school is computing it: worth asking again shortly.
    var isPending: Bool { status == "PENDING" && spans.isEmpty }

    var isUsable: Bool {
        status == "READY" && spans.count <= 2_000 && spans.allSatisfy { span in
            span.firstSequence >= 0 && span.lastSequence > span.firstSequence && span.confidence.isFinite
                && span.geometry.utf8.count <= 400_000 && span.anchors.count >= 2 && span.anchors.count <= 20_000
                && span.anchors.allSatisfy { $0.count == 2 && $0[0].isFinite && $0[1].isFinite && $0[1] >= 0 }
        }
    }
}

enum SchoolEncodedPolyline {
    /// Google polyline algorithm. Invalid input yields an empty array, never a partial line.
    static func decode(_ text: String, precision: Int = 6) -> [(latitude: Double, longitude: Double)] {
        let factor = pow(10, Double(precision))
        let bytes = Array(text.utf8)
        var index = 0, latitude = 0, longitude = 0
        var result: [(latitude: Double, longitude: Double)] = []
        func next() -> Int? {
            var shift = 0, value = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                index += 1
                guard byte >= 0, shift <= 60 else { return nil }
                value |= (byte & 0x1f) << shift
                shift += 5
                if byte < 0x20 { return (value & 1) != 0 ? ~(value >> 1) : value >> 1 }
            }
            return nil
        }
        while index < bytes.count {
            guard let deltaLatitude = next(), let deltaLongitude = next() else { return [] }
            latitude += deltaLatitude; longitude += deltaLongitude
            let lat = Double(latitude) / factor, lon = Double(longitude) / factor
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { return [] }
            result.append((lat, lon))
        }
        return result
    }
}

/// One drawn stretch of a replay and the timetable along it, prepared once.
/// The playhead position is two binary searches, whatever the length of the trip:
/// time gives a distance along the line, the distance gives a place on it.
struct SchoolReplayPath: Sendable {
    struct Knot: Sendable {
        let offset: TimeInterval
        let meters: Double
    }
    struct Place: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        /// Direction of the line at this place; nil on a lone point.
        let heading: Double?
    }

    private(set) var latitudes: [Double] = []
    private(set) var longitudes: [Double] = []
    private(set) var cumulative: [Double] = []
    private(set) var knots: [Knot] = []

    var length: Double { cumulative.last ?? 0 }
    var vertexCount: Int { latitudes.count }

    mutating func addVertex(latitude: Double, longitude: Double) {
        if let lastLatitude = latitudes.last, let lastLongitude = longitudes.last {
            cumulative.append(length + SchoolTrackGeometry.meters(latitude1: lastLatitude, longitude1: lastLongitude,
                                                                  latitude2: latitude, longitude2: longitude))
        } else {
            cumulative.append(0)
        }
        latitudes.append(latitude); longitudes.append(longitude)
    }

    /// Time never goes back and neither does the distance: a late or regressive knot is dropped.
    mutating func addKnot(offset: TimeInterval, meters: Double) {
        let bounded = min(length, max(knots.last?.meters ?? 0, meters))
        if let last = knots.last {
            guard offset >= last.offset else { return }
            if offset == last.offset {
                if bounded > last.meters { knots[knots.count - 1] = Knot(offset: offset, meters: bounded) }
                return
            }
        }
        knots.append(Knot(offset: offset, meters: bounded))
    }

    /// Display position at an instant, clamped to the timetable of this stretch.
    func place(at offset: TimeInterval) -> Place? {
        guard let first = knots.first, let last = knots.last, !latitudes.isEmpty else { return nil }
        let time = min(last.offset, max(first.offset, offset))
        var low = 0, high = knots.count
        while low < high {
            let middle = (low + high) / 2
            if knots[middle].offset <= time { low = middle + 1 } else { high = middle }
        }
        let index = max(0, low - 1)
        var meters = knots[index].meters
        if index + 1 < knots.count {
            let next = knots[index + 1]
            let span = next.offset - knots[index].offset
            if span > 0 { meters += (next.meters - meters) * ((time - knots[index].offset) / span) }
        }
        return place(atMeters: meters)
    }

    func place(atMeters meters: Double) -> Place? {
        guard let latitude = latitudes.first, let longitude = longitudes.first else { return nil }
        guard latitudes.count > 1, length > 0 else { return Place(latitude: latitude, longitude: longitude, heading: nil) }
        let distance = min(length, max(0, meters))
        // First vertex whose cumulative distance exceeds the target closes the edge we are on.
        var low = 1, high = cumulative.count - 1
        while low < high {
            let middle = (low + high) / 2
            if cumulative[middle] < distance { low = middle + 1 } else { high = middle }
        }
        var edge = low
        // Duplicate vertices have no direction: take the nearest edge that has one.
        while edge < cumulative.count - 1, cumulative[edge] - cumulative[edge - 1] <= 0 { edge += 1 }
        while edge > 1, cumulative[edge] - cumulative[edge - 1] <= 0 { edge -= 1 }
        let span = cumulative[edge] - cumulative[edge - 1]
        let fraction = span > 0 ? min(1, max(0, (distance - cumulative[edge - 1]) / span)) : 0
        let point = SchoolTrackGeometry.interpolate(latitude1: latitudes[edge - 1], longitude1: longitudes[edge - 1],
            latitude2: latitudes[edge], longitude2: longitudes[edge], fraction: fraction)
        let heading = span > 0 ? SchoolTrackGeometry.bearing(latitude1: latitudes[edge - 1], longitude1: longitudes[edge - 1],
            latitude2: latitudes[edge], longitude2: longitudes[edge]) : nil
        return Place(latitude: point.latitude, longitude: point.longitude, heading: heading)
    }
}
