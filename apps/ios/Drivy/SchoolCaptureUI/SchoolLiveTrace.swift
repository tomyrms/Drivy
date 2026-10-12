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
    private(set) var lines: [DrivyRouteMapLine] = []
    private(set) var hasGaps = false
    private(set) var start: CLLocationCoordinate2D?
    private(set) var position: Position?

    /// Idempotent: called again with unchanged segments, it does nothing.
    func update(_ segments: [SchoolCaptureMapSegment]) {
        let ids = segments.map(\.id)
        var changed = ids != order
        if changed {
            let current = Set(ids)
            states = states.filter { current.contains($0.key) }
            bridges = bridges.filter { key, _ in key.split(separator: ">").allSatisfy { part in current.contains { $0.uuidString == part } } }
            order = ids
        }
        for segment in segments where states[segment.id]?.revision != segment.displayRevision {
            var state = states[segment.id] ?? SegmentState()
            advance(&state, with: segment)
            states[segment.id] = state
            changed = true
        }
        guard changed else { return }
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
            all.append(contentsOf: state.closed)
            all.append(contentsOf: state.tail)
        }
        lines = all
        hasGaps = gapCount > 0
        start = segments.lazy.compactMap { self.states[$0.id]?.first }.first
        position = segments.reversed().lazy.compactMap { self.states[$0.id]?.last }.first
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
