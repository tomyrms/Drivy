import CoreLocation
import Foundation

/// Geometry of the trip being recorded, kept up to date one fix at a time.
/// Closed stretches are built once and never touched again; only the short open
/// tail is redrawn when a fix arrives. Every vertex is a measured, retained fix.
@MainActor final class SchoolLiveTrace {
    /// A trace is cut into polylines of this many vertices: redrawing the tail stays
    /// cheap however long the lesson lasts.
    static let chunkSize = 200

    struct Position {
        let segmentID: UUID
        let point: SchoolCapturePoint
        let startsFragment: Bool
        /// Direction of the measured movement, nil while it cannot be trusted.
        let course: Double?
    }

    private struct SegmentState {
        var revision = -1
        /// Samples already drawn in final form (all but the last, which may still change).
        var committed = 0
        var fragment = 0
        var chunk = 0
        var open: [CLLocationCoordinate2D] = []
        var closed: [DrivyRouteMapLine] = []
        var gaps: [DrivyRouteMapLine] = []
        var tail: [DrivyRouteMapLine] = []
        var course = SchoolMapCourse()
        var anchors: [Int: CLLocationCoordinate2D] = [:]
        /// The last sample may still be withdrawn: its anchor stays apart from the final ones.
        var tailAnchor: (sequence: Int, coordinate: CLLocationCoordinate2D)?
        var first: CLLocationCoordinate2D?
        var last: Position?
        var previousCommitted: SchoolCapturePoint?
    }

    private var states: [UUID: SegmentState] = [:]
    private var order: [UUID] = []
    private var bridges: [String: DrivyRouteMapLine?] = [:]
    /// Lines of a segment drawn on the road (#90), keyed by its display revision and its stretches.
    private var roadLines: [UUID: (key: Int, lines: [DrivyRouteMapLine])] = [:]
    private(set) var lines: [DrivyRouteMapLine] = []
    private(set) var hasGaps = false
    private(set) var start: CLLocationCoordinate2D?
    private(set) var position: Position?
    private var liveFrom = 0

    /// Idempotent: called again with unchanged segments, it does nothing.
    /// `liveFrom`: index of the first segment of the trip being recorded. Earlier segments (previous trips of the
    /// same lesson) are drawn and give the start, never the current position.
    /// `roads`: accepted road stretches; between their anchors the line follows the road instead of the fixes.
    /// Positions, start and observation anchors stay the measured ones.
    func update(_ segments: [SchoolCaptureMapSegment], liveFrom: Int = 0, roads: [SchoolLiveRoadRoute] = []) {
        let ids = segments.map(\.id)
        var changed = ids != order
        if changed {
            let current = Set(ids)
            states = states.filter { current.contains($0.key) }
            roadLines = roadLines.filter { current.contains($0.key) }
            bridges = bridges.filter { key, _ in key.split(separator: ">").allSatisfy { part in current.contains { $0.uuidString == part } } }
            order = ids
        }
        for segment in segments where states[segment.id]?.revision != segment.displayRevision {
            var state = states[segment.id] ?? SegmentState()
            advance(&state, with: segment)
            states[segment.id] = state
            changed = true
        }
        let bySegment = Dictionary(grouping: roads, by: \.segmentID)
        for segment in segments {
            guard let stretches = bySegment[segment.id], !stretches.isEmpty else {
                if roadLines.removeValue(forKey: segment.id) != nil { changed = true }
                continue
            }
            var hasher = Hasher()
            hasher.combine(segment.displayRevision)
            for stretch in stretches { hasher.combine(stretch.anchors.first?.sequence); hasher.combine(stretch.anchors.last?.sequence); hasher.combine(stretch.vertices.count) }
            let key = hasher.finalize()
            guard roadLines[segment.id]?.key != key else { continue }
            roadLines[segment.id] = (key, Self.roadLines(segment: segment, stretches: stretches))
            changed = true
        }
        guard changed || liveFrom != self.liveFrom else { return }
        self.liveFrom = liveFrom
        var all: [DrivyRouteMapLine] = []
        var gapCount = 0
        for (index, segment) in segments.enumerated() {
            guard let state = states[segment.id] else { continue }
            all.append(contentsOf: state.gaps)
            gapCount += state.gaps.count
            if index > 0, let bridge = bridge(from: segments[index - 1], to: segment) {
                all.append(bridge)
                gapCount += 1
            }
            if let road = roadLines[segment.id] {
                all.append(contentsOf: road.lines)
            } else {
                all.append(contentsOf: state.closed)
                all.append(contentsOf: state.tail)
            }
        }
        lines = all
        hasGaps = gapCount > 0
        start = segments.lazy.compactMap { self.states[$0.id]?.first }.first
        position = segments.dropFirst(min(liveFrom, segments.count)).reversed().lazy.compactMap { self.states[$0.id]?.last }.first
    }

    /// Exact anchor only: an observation whose fix is not displayed keeps its time, without a place.
    func coordinate(segmentID: UUID, sequence: Int) -> CLLocationCoordinate2D? {
        guard let state = states[segmentID] else { return nil }
        if let tail = state.tailAnchor, tail.sequence == sequence { return tail.coordinate }
        return state.anchors[sequence]
    }

    private func advance(_ state: inout SegmentState, with segment: SchoolCaptureMapSegment) {
        let samples = segment.displaySamples
        let prefix = segment.id.uuidString
        let stable = max(0, samples.count - 1)
        var index = state.committed
        while index < stable {
            let sample = samples[index]
            let coordinate = CLLocationCoordinate2D(latitude: sample.point.latitude, longitude: sample.point.longitude)
            if sample.startsFragment {
                if !state.open.isEmpty {
                    state.closed.append(.init(id: "\(prefix):\(state.fragment):\(state.chunk)", revision: -1, style: .route, coordinates: state.open))
                    state.open = []
                    state.fragment += 1; state.chunk = 0
                }
                if sample.followsSilence, let previous = state.previousCommitted {
                    state.gaps.append(Self.gap(id: "\(prefix):gap:\(sample.point.sequence)", from: previous, to: sample.point))
                }
                state.course = SchoolMapCourse()
            }
            state.open.append(coordinate)
            if state.open.count >= Self.chunkSize {
                state.closed.append(.init(id: "\(prefix):\(state.fragment):\(state.chunk)", revision: -1, style: .route, coordinates: state.open))
                // The next chunk starts on the same vertex: the line has no hole.
                state.open = [coordinate]
                state.chunk += 1
            }
            _ = state.course.receive(coordinate, at: Double(sample.point.elapsedMs) / 1000, accuracy: sample.point.accuracyMeters)
            state.anchors[sample.point.sequence] = coordinate
            if state.first == nil { state.first = coordinate }
            state.previousCommitted = sample.point
            index += 1
        }
        state.committed = stable
        state.revision = segment.displayRevision
        state.tail = []
        state.tailAnchor = nil
        guard let sample = samples.last else { state.last = nil; return }
        let coordinate = CLLocationCoordinate2D(latitude: sample.point.latitude, longitude: sample.point.longitude)
        var course = state.course
        if sample.startsFragment { course = SchoolMapCourse() }
        let heading = course.receive(coordinate, at: Double(sample.point.elapsedMs) / 1000, accuracy: sample.point.accuracyMeters)
        state.tailAnchor = (sample.point.sequence, coordinate)
        if state.first == nil { state.first = coordinate }
        state.last = Position(segmentID: segment.id, point: sample.point, startsFragment: sample.startsFragment, course: heading)
        let revision = sample.point.sequence &* 1024 &+ state.open.count
        if sample.startsFragment {
            if !state.open.isEmpty {
                state.tail.append(.init(id: "\(prefix):\(state.fragment):\(state.chunk)", revision: state.open.count, style: .route, coordinates: state.open))
                if sample.followsSilence, let previous = state.previousCommitted {
                    state.tail.append(Self.gap(id: "\(prefix):gap:\(sample.point.sequence)", from: previous, to: sample.point))
                }
                state.tail.append(.init(id: "\(prefix):\(state.fragment + 1):0", revision: revision, style: .route, coordinates: [coordinate]))
            } else {
                state.tail.append(.init(id: "\(prefix):\(state.fragment):\(state.chunk)", revision: revision, style: .route, coordinates: [coordinate]))
            }
        } else {
            state.tail.append(.init(id: "\(prefix):\(state.fragment):\(state.chunk)", revision: revision, style: .route,
                                    coordinates: state.open + [coordinate]))
        }
    }

    /// The displayed fixes of one segment, with each accepted stretch drawn in place of the fixes it covers.
    /// A stretch is used only inside one fragment (never across a silence or a rejected jump); when two overlap,
    /// the later one wins from its first anchor and the earlier one is cut at its last anchor before that.
    /// Cut into chunks like the measured line, each chunk revised only when its content changes.
    static func roadLines(segment: SchoolCaptureMapSegment, stretches: [SchoolLiveRoadRoute]) -> [DrivyRouteMapLine] {
        let samples = segment.displaySamples
        guard !samples.isEmpty else { return [] }
        let breaks = samples.filter(\.startsFragment).map(\.point.sequence)
        // Non-overlapping stretches, oldest first, none crossing a fragment start.
        var resolved: [(first: Int, last: Int, vertices: [SchoolLiveRoadRoute.Vertex])] = []
        for stretch in stretches.sorted(by: { ($0.anchors.first?.sequence ?? 0) < ($1.anchors.first?.sequence ?? 0) }) {
            guard let first = stretch.anchors.first, let last = stretch.anchors.last,
                  !breaks.contains(where: { $0 > first.sequence && $0 <= last.sequence }) else { continue }
            while let previous = resolved.last, previous.last > first.sequence {
                resolved.removeLast()
                guard let source = stretches.first(where: { $0.anchors.first?.sequence == previous.first }),
                      let cut = source.anchors.last(where: { $0.sequence <= first.sequence }), cut.sequence > previous.first else { continue }
                resolved.append((previous.first, cut.sequence, Array(source.vertices[0...cut.index])))
                break
            }
            resolved.append((first.sequence, last.sequence, stretch.vertices))
        }
        var fragments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var next = 0
        var skipUntil = -1
        for sample in samples {
            if sample.startsFragment, !current.isEmpty { fragments.append(current); current = [] }
            let sequence = sample.point.sequence
            // Every stretch that starts at or before this fix is drawn here, in order: its first vertex is the
            // road place of its first anchor, its last the road place of its last anchor.
            while next < resolved.count, sequence >= resolved[next].first {
                current.append(contentsOf: resolved[next].vertices.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                skipUntil = max(skipUntil, resolved[next].last)
                next += 1
            }
            if sequence <= skipUntil { continue }
            current.append(CLLocationCoordinate2D(latitude: sample.point.latitude, longitude: sample.point.longitude))
        }
        if !current.isEmpty { fragments.append(current) }
        let prefix = segment.id.uuidString
        var out: [DrivyRouteMapLine] = []
        for (fragment, coordinates) in fragments.enumerated() {
            var start = 0, chunk = 0
            repeat {
                let end = min(coordinates.count, start + chunkSize)
                let slice = Array(coordinates[start..<end])
                var hasher = Hasher()
                for c in slice { hasher.combine(c.latitude); hasher.combine(c.longitude) }
                out.append(.init(id: "\(prefix):road:\(fragment):\(chunk)", revision: hasher.finalize(), style: .route, coordinates: slice))
                // The next chunk starts on the same vertex: the line has no hole.
                start = end - 1; chunk += 1
            } while start < coordinates.count - 1
        }
        return out
    }

    /// Dashed connector across a silence between two segments; decided once both ends are known.
    private func bridge(from previous: SchoolCaptureMapSegment, to next: SchoolCaptureMapSegment) -> DrivyRouteMapLine? {
        let key = "\(previous.id.uuidString)>\(next.id.uuidString)"
        if let known = bridges[key] { return known }
        guard let previousSource = previous.lastPoint, let nextSource = next.firstPoint,
              let previousDisplayed = previous.displaySamples.last?.point,
              let nextDisplayed = next.displaySamples.first?.point else { return nil }
        let gap = SchoolMapRouteGap.betweenSegments(id: "between:\(key)", previousSource: previousSource, nextSource: nextSource,
            previousDisplayed: previousDisplayed, nextDisplayed: nextDisplayed)
        let line = gap.map { Self.gap(id: $0.id, from: $0.start, to: $0.end) }
        bridges[key] = .some(line)
        return line
    }

    private static func gap(id: String, from: SchoolCapturePoint, to: SchoolCapturePoint) -> DrivyRouteMapLine {
        .init(id: id, revision: 0, style: .gap, coordinates: [
            CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude),
            CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)
        ])
    }
}
