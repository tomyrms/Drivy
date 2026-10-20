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
    /// Only the self-hosted OSRM generation is displayable. Missing metadata is legacy, not a fallback.
    let provider: String?
    let algorithmVersion: Int?
    let spans: [Span]

    /// The school is computing it: worth asking again shortly.
    var isPending: Bool { status == "PENDING" && algorithmVersion == 2 && spans.isEmpty }

    var isUsable: Bool {
        status == "READY" && provider == "osrm" && algorithmVersion == 2
            && spans.count <= 2_000 && spans.allSatisfy { span in
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
        guard let meters = meters(at: offset) else { return nil }
        return place(atMeters: meters)
    }

    /// Distance along the line at an instant. Between two knots the distance follows a monotone
    /// cubic (Fritsch-Butland tangents): the speed changes smoothly from one stretch to the next
    /// instead of jumping at every fix, never goes backwards, and every knot is reached exactly.
    /// A knot next to a stop gets a zero tangent: the vehicle leaves and stops without a jolt.
    func meters(at offset: TimeInterval) -> Double? {
        guard let first = knots.first, let last = knots.last, !latitudes.isEmpty else { return nil }
        let time = min(last.offset, max(first.offset, offset))
        var low = 0, high = knots.count
        while low < high {
            let middle = (low + high) / 2
            if knots[middle].offset <= time { low = middle + 1 } else { high = middle }
        }
        let index = max(0, low - 1)
        guard index + 1 < knots.count else { return knots[index].meters }
        let start = knots[index], end = knots[index + 1]
        let span = end.offset - start.offset
        guard span > 0 else { return end.meters }
        let secant = (end.meters - start.meters) / span
        let s = (time - start.offset) / span
        let m0 = tangent(at: index, secantAfter: secant), m1 = tangent(at: index + 1, secantBefore: secant)
        let s2 = s * s, s3 = s2 * s
        let value = (2 * s3 - 3 * s2 + 1) * start.meters + (s3 - 2 * s2 + s) * span * m0
            + (-2 * s3 + 3 * s2) * end.meters + (s3 - s2) * span * m1
        return min(end.meters, max(start.meters, value))
    }

    private func secant(_ index: Int) -> Double? {
        guard index >= 0, index + 1 < knots.count else { return nil }
        let span = knots[index + 1].offset - knots[index].offset
        return span > 0 ? (knots[index + 1].meters - knots[index].meters) / span : nil
    }

    private func tangent(at index: Int, secantAfter: Double) -> Double {
        guard let before = secant(index - 1) else { return secantAfter }
        return Self.blend(before, secantAfter, spanBefore: knots[index].offset - knots[index - 1].offset,
                          spanAfter: knots[index + 1].offset - knots[index].offset)
    }

    private func tangent(at index: Int, secantBefore: Double) -> Double {
        guard let after = secant(index) else { return secantBefore }
        return Self.blend(secantBefore, after, spanBefore: knots[index].offset - knots[index - 1].offset,
                          spanAfter: knots[index + 1].offset - knots[index].offset)
    }

    /// Fritsch-Butland: weighted harmonic mean of the two secants, zero at a stop. Equal secants
    /// give that same slope, so a steady movement stays exactly linear.
    private static func blend(_ before: Double, _ after: Double, spanBefore: Double, spanAfter: Double) -> Double {
        guard before > 0, after > 0, spanBefore > 0, spanAfter > 0 else { return 0 }
        return 3 * (spanBefore + spanAfter) / ((2 * spanAfter + spanBefore) / before + (spanAfter + 2 * spanBefore) / after)
    }

    /// Distance along the line of the point closest to a coordinate, searched only between two
    /// distances: a loop or a road taken twice never pulls a fix onto the wrong passage.
    func project(latitude: Double, longitude: Double, from lower: Double, to upper: Double) -> Double {
        guard latitudes.count > 1, upper > lower else { return lower }
        var low = 1, high = cumulative.count - 1
        while low < high {
            let middle = (low + high) / 2
            if cumulative[middle] <= lower { low = middle + 1 } else { high = middle }
        }
        var best = lower, bestDistance = Double.infinity
        var edge = low
        let cosine = cos(latitude * .pi / 180)
        while edge < cumulative.count {
            let span = cumulative[edge] - cumulative[edge - 1]
            if span > 0 {
                let ax = longitudes[edge - 1] * cosine, ay = latitudes[edge - 1]
                let dx = longitudes[edge] * cosine - ax, dy = latitudes[edge] - ay
                let square = dx * dx + dy * dy
                let t = square > 0 ? min(1, max(0, ((longitude * cosine - ax) * dx + (latitude - ay) * dy) / square)) : 0
                let along = min(upper, max(lower, cumulative[edge - 1] + span * t))
                guard let point = place(atMeters: along) else { break }
                let distance = SchoolTrackGeometry.meters(latitude1: latitude, longitude1: longitude,
                                                          latitude2: point.latitude, longitude2: point.longitude)
                if distance < bestDistance { bestDistance = distance; best = along }
            }
            if cumulative[edge] >= upper { break }
            edge += 1
        }
        return best
    }

    /// Direction of travel seen from a little ahead: the bearing from slightly behind the place
    /// to `ahead` metres further along the line. Short wiggles of a measured line no longer turn
    /// the arrow or the camera at every vertex, and a bend is taken as one smooth turn.
    func heading(atMeters meters: Double, ahead: Double) -> Double? {
        guard latitudes.count > 1, length > 0 else { return nil }
        let behind = min(ahead / 3, 4), span = min(length, behind + ahead)
        var from = meters - behind, to = meters + ahead
        // Near the ends the window slides inward rather than shrinking to nothing.
        if from < 0 { from = 0; to = span } else if to > length { to = length; from = length - span }
        guard to - from > 0.5, let start = place(atMeters: from), let end = place(atMeters: to) else {
            return place(atMeters: meters)?.heading
        }
        guard SchoolTrackGeometry.meters(latitude1: start.latitude, longitude1: start.longitude,
                                         latitude2: end.latitude, longitude2: end.longitude) > 0.5 else {
            return place(atMeters: meters)?.heading
        }
        return SchoolTrackGeometry.bearing(latitude1: start.latitude, longitude1: start.longitude,
                                           latitude2: end.latitude, longitude2: end.longitude)
    }

    /// One measured fix offered to `refineTimetable`.
    struct Fix: Sendable {
        let offset: TimeInterval
        let latitude: Double
        let longitude: Double
    }

    /// Rebuilds the timetable from every measured fix, not only from the vertices the display
    /// filter kept. The filter holds a slow vehicle on one vertex while its fixes stay inside the
    /// uncertainty radius, then jumps to the next one: on a lesson spent at walking pace the
    /// playhead stopped for seconds and leapt a few metres, over and over.
    ///
    /// Fixes whose place on the line is known stay as they are: every knot of the timetable
    /// (a drawn vertex, a road anchor, the end of the stretch), except the knots that only held
    /// the vehicle on a vertex. Between two known places, the other fixes are placed on the line
    /// within that stretch only. A real stop (no progress from the first third of the fixes to
    /// the last) keeps the vehicle on its vertex, exactly as before. A slow movement is cleaned
    /// (median of five, isotonic regression, mean of five) so that progress is smooth and never
    /// goes back. The line itself does not change.
    mutating func refineTimetable(with fixes: [Fix]) {
        guard latitudes.count > 1, knots.count >= 2 else { return }
        var anchors: [Knot] = []
        for (index, knot) in knots.enumerated() {
            let holds = index > 0 && index < knots.count - 1 && knot.meters <= knots[index - 1].meters
            if !holds { anchors.append(knot) }
        }
        let sorted = fixes.filter { $0.latitude.isFinite && $0.longitude.isFinite && $0.offset.isFinite }
            .sorted { $0.offset < $1.offset }
        var refined: [Knot] = []
        refined.reserveCapacity(knots.count + sorted.count)
        var cursor = 0
        for (from, to) in zip(anchors, anchors.dropFirst()) {
            refined.append(from)
            while cursor < sorted.count, sorted[cursor].offset <= from.offset { cursor += 1 }
            var inner: [Fix] = []
            while cursor < sorted.count, sorted[cursor].offset < to.offset { inner.append(sorted[cursor]); cursor += 1 }
            guard !inner.isEmpty else { continue }
            let placed = Self.progress(of: inner, along: self, from: from.meters, to: max(from.meters, to.meters))
            for (fix, meters) in zip(inner, placed) {
                refined.append(Knot(offset: fix.offset, meters: min(to.meters, max(refined[refined.count - 1].meters, meters))))
            }
        }
        if let last = anchors.last { refined.append(last) }
        guard zip(refined, refined.dropFirst()).allSatisfy({ $0.offset < $1.offset && $0.meters <= $1.meters }) else { return }
        knots = refined
    }

    /// Distance along the line of each fix of one stretch between two known places.
    private static func progress(of fixes: [Fix], along path: SchoolReplayPath, from lower: Double, to upper: Double) -> [Double] {
        let gap = upper - lower
        guard gap > 0 else { return fixes.map { _ in lower } }
        let raw = fixes.map { path.project(latitude: $0.latitude, longitude: $0.longitude, from: lower, to: upper) - lower }
        // One or two fixes between known places: nothing to clean, each keeps its own place.
        guard raw.count >= 3 else { return raw.map { lower + $0 } }
        let third = max(1, (raw.count + 2) / 3)
        func median(_ values: ArraySlice<Double>) -> Double { let s = values.sorted(); return s[s.count / 2] }
        // A stop: the fixes scatter around the vertex without getting anywhere.
        if raw.count >= 2, median(raw.suffix(third)) - median(raw.prefix(third)) < max(1, 0.3 * gap) {
            return fixes.map { _ in lower }
        }
        var values = raw.indices.map { median(raw[max(0, $0 - 2)...min(raw.count - 1, $0 + 2)]) }
        isotonic(&values)
        // The mean of a non-decreasing sequence is non-decreasing: the flats left by the
        // regression are rounded off without any backward step. Both known places take part.
        let framed = [0] + values.map { min(gap, max(0, $0)) } + [gap]
        return values.indices.map { index in
            let centre = index + 1
            let window = framed[max(0, centre - 2)...min(framed.count - 1, centre + 2)]
            return lower + window.reduce(0, +) / Double(window.count)
        }
    }

    /// Pool-adjacent-violators: the closest non-decreasing sequence, in place.
    private static func isotonic(_ values: inout [Double]) {
        guard values.count > 1 else { return }
        var means: [Double] = [], weights: [Int] = []
        for value in values {
            means.append(value); weights.append(1)
            while means.count > 1, means[means.count - 2] > means[means.count - 1] {
                let w = weights[weights.count - 2] + weights[weights.count - 1]
                let m = (means[means.count - 2] * Double(weights[weights.count - 2])
                    + means[means.count - 1] * Double(weights[weights.count - 1])) / Double(w)
                means.removeLast(2); weights.removeLast(2)
                means.append(m); weights.append(w)
            }
        }
        var index = 0
        for (mean, weight) in zip(means, weights) {
            for _ in 0..<weight { values[index] = mean; index += 1 }
        }
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
