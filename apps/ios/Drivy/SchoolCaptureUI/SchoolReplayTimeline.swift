import MapKit
import SwiftUI

private extension ObservationStatus {
    /// Wire value of a school observation status (ATTENTION, TO_REWORK, POSITIVE).
    init?(schoolValue: String) {
        switch schoolValue {
        case "ATTENTION": self = .attention
        case "TO_REWORK": self = .toWorkOn
        case "POSITIVE": self = .positive
        default: return nil
        }
    }
}

/// Coverage of rendered intervals, not a count of the spans advertised by the server.
struct SchoolReplayMatchingCoverage: Equatable {
    enum State: Equatable { case none, partial, full }
    private(set) var matchedIntervals = 0
    private(set) var measuredIntervals = 0
    var totalIntervals: Int { matchedIntervals + measuredIntervals }
    var state: State {
        matchedIntervals == 0 ? .none : measuredIntervals == 0 ? .full : .partial
    }

    /// Count only rendered intervals, split at accepted anchor boundaries. Gaps and lone fixes are excluded.
    mutating func include(sequences: [Int], matched ranges: [ClosedRange<Int>]) {
        var merged: [ClosedRange<Int>] = []
        for range in ranges {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else { merged.append(range) }
        }
        var index = 0
        for (from, to) in zip(sequences, sequences.dropFirst()) {
            var cursor = from
            while index < merged.count, merged[index].upperBound <= cursor { index += 1 }
            while index < merged.count, merged[index].lowerBound < to {
                let lower = max(cursor, merged[index].lowerBound), upper = min(to, merged[index].upperBound)
                if lower > cursor { measuredIntervals += 1 }
                if upper > lower { matchedIntervals += 1 }
                cursor = max(cursor, upper)
                if merged[index].upperBound <= to { index += 1 } else { break }
            }
            if cursor < to { measuredIntervals += 1 }
        }
    }
}

/// Timeline of a private school replay, built once per loaded page set. Offsets are
/// seconds since the authorization; each fragment stays a separate polyline and the
/// time between fragments is a gap, never an interpolated route.
///
/// Four layers stay apart: `samples` are measured fixes kept by the display filter;
/// `paths` are what is drawn (those fixes, or the road-matched geometry between two of
/// them when the server supplied one); `position(at:)` is the display position between
/// two knots of a path. Nothing here changes a measurement.
struct SchoolReplayTimeline {
    typealias Fragment = SchoolMapRouteFragment

    struct Sample {
        let offset: TimeInterval
        /// The vehicle stood on this fix until then.
        let heldOffset: TimeInterval
        let coordinate: CLLocationCoordinate2D
        let fragmentIndex: Int
        let heading: Double?
    }

    struct Item: Identifiable {
        let id: UUID
        let offset: TimeInterval?
        let coordinate: CLLocationCoordinate2D?
        let status: ObservationStatus?
        let isMarker: Bool
        let text: String
        var themeKey: String? = nil

        var title: String { isMarker ? "Moment à revoir" : text }
        var statusLabel: String { status?.label ?? "Repère" }
        /// Thème si la clé ou le titre en désigne un, sinon l’appréciation, sinon repère ou note.
        var glyph: DrivyObservationGlyph {
            if isMarker { return .moment }
            return SchoolObservationPictogram(themeKey: themeKey, title: text)?.glyph ?? status?.glyph ?? .note
        }
        var tone: DrivyTone { status?.tone ?? .neutral }
    }

    let start: Date
    let duration: TimeInterval
    let fragments: [Fragment]
    /// Drawn geometry and timetable of each fragment, same indices as `fragments`.
    let paths: [SchoolReplayPath]
    let samples: [Sample]
    /// Sorted and disjoint.
    let gaps: [ClosedRange<TimeInterval>]
    /// Dashed map connections require a silence in the original measurements.
    /// Display-filter gaps remain gaps in playback, without inventing GPS loss.
    let mapGaps: [SchoolMapRouteGap]
    /// Observations with an instant, chronological; then those without an instant.
    let items: [Item]
    let timedItems: [Item]
    /// Part of the drawn route follows road-matched geometry.
    let usesMatchedRoute: Bool
    /// Coverage of the geometry actually accepted by the renderer, unrelated to upload quality.
    let matchingCoverage: SchoolReplayMatchingCoverage
    /// Prepared once for the map: nothing is rebuilt while the playhead moves.
    let mapLines: [DrivyRouteMapLine]

    init(fragments source: [SchoolCaptureReplayFragment], observations: [SchoolPrivateGeoObservation],
         startsAt: Date?, endsAt: Date?, maxPointAge: TimeInterval = 15, matched: SchoolMatchedRoute? = nil) {
        let observationDates = observations.compactMap(\.observedDate)
        let firstSequences = source.map { $0.points.map(\.sequence).min() ?? 0 }
        let orderedFragments = source.indices.sorted {
            source[$0].segmentIndex == source[$1].segmentIndex
                ? firstSequences[$0] < firstSequences[$1] : source[$0].segmentIndex < source[$1].segmentIndex
        }.map { source[$0] }
        // Page/chunk boundaries must not reset the selection policy. The original
        // sequence and elapsed-time gaps still split the resulting measured route.
        var orderedSource: [SchoolCaptureReplayFragment] = []
        for fragment in orderedFragments {
            if orderedSource.last?.segmentID == fragment.segmentID {
                orderedSource[orderedSource.count - 1].points.append(contentsOf: fragment.points)
            } else {
                orderedSource.append(fragment)
            }
        }
        let firstPointDate = orderedSource.first?.points.min(by: { $0.sequence < $1.sequence })
            .flatMap { SchoolLesson.date($0.capturedAt) }
        let origin = startsAt ?? firstPointDate ?? observationDates.min() ?? Date()
        var spansBySegment: [UUID: [SchoolMatchedRoute.Span]] = [:]
        if let matched, matched.isUsable {
            for span in matched.spans { spansBySegment[span.segmentId, default: []].append(span) }
            for key in spansBySegment.keys { spansBySegment[key]?.sort { $0.firstSequence < $1.firstSequence } }
        }
        var samples: [Sample] = []
        var paths: [SchoolReplayPath] = []
        var built: [Fragment] = []
        var coordinateByKey: [String: CLLocationCoordinate2D] = [:]
        var lastSourceOffset: TimeInterval = 0
        var filteredTails: [ClosedRange<TimeInterval>] = []
        var mapGaps: [SchoolMapRouteGap] = []
        var previousSource: SchoolCapturePoint?
        var previousDisplayed: SchoolCapturePoint?
        var usesMatched = false
        var coverage = SchoolReplayMatchingCoverage()
        for fragment in orderedSource {
            // One date parse per fragment; the other points follow their monotonic elapsed time.
            guard let first = fragment.points.min(by: { $0.sequence < $1.sequence }),
                  let base = SchoolLesson.date(first.capturedAt) else {
                previousSource = nil; previousDisplayed = nil
                continue
            }
            let baseOffset = base.timeIntervalSince(origin)
            func offset(_ elapsedMs: Int) -> TimeInterval { baseOffset + Double(elapsedMs - first.elapsedMs) / 1000 }
            let lastOffset = offset(fragment.points.map(\.elapsedMs).max() ?? first.elapsedMs)
            lastSourceOffset = max(lastSourceOffset, lastOffset)
            let selected = SchoolCaptureDisplayRoute.select(fragment.points, maximumGap: maxPointAge)
            mapGaps.append(contentsOf: SchoolMapRouteGap.withinSegment(fragment.points, displayed: selected,
                idPrefix: fragment.id, maximumGap: maxPointAge))
            if let previousSource, let previousDisplayed, let nextDisplayed = selected.first?.point,
               let gap = SchoolMapRouteGap.betweenSegments(id: "before:\(fragment.id)",
                    previousSource: previousSource, nextSource: first,
                    previousDisplayed: previousDisplayed, nextDisplayed: nextDisplayed, maximumGap: maxPointAge) {
                mapGaps.append(gap)
            }
            previousSource = fragment.points.max(by: { $0.sequence < $1.sequence })
            previousDisplayed = selected.last?.point

            let spans = spansBySegment[fragment.segmentID] ?? []
            var elapsedBySequence: [Int: Int] = [:]
            if !spans.isEmpty {
                elapsedBySequence.reserveCapacity(fragment.points.count)
                for point in fragment.points { elapsedBySequence[point.sequence] = point.elapsedMs }
            }
            var part = 0
            var index = 0
            while index < selected.count {
                // One display fragment: from a sample that starts it to the one before the next start.
                var end = index + 1
                while end < selected.count, !selected[end].startsFragment { end += 1 }
                let run = selected[index..<end]
                let fragmentIndex = built.count
                var course = SchoolMapCourse()
                var path = SchoolReplayPath()
                let lower = run[run.startIndex].point.sequence, upper = run[run.endIndex - 1].point.sequence
                // A matched span is used only inside one continuous stretch of measured fixes.
                var usable = spans.filter { $0.firstSequence >= lower && $0.lastSequence <= upper }
                // Two neighbouring spans may share their joining fix, never more.
                if zip(usable, usable.dropFirst()).contains(where: { $0.lastSequence > $1.firstSequence }) { usable = [] }
                var spanIndex = 0
                // Span whose geometry is laid on the path; a refused span leaves its fixes measured.
                var laidSpan = -1, triedSpan = -1
                var matchedCoordinates: [Int: CLLocationCoordinate2D] = [:]
                var renderedMatchedRanges: [ClosedRange<Int>] = []
                for sample in run {
                    let point = sample.point
                    let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                    let sampleOffset = offset(point.elapsedMs), heldOffset = offset(sample.heldUntilMs)
                    samples.append(Sample(offset: sampleOffset, heldOffset: heldOffset, coordinate: coordinate,
                        fragmentIndex: fragmentIndex,
                        heading: course.receive(coordinate, at: sampleOffset, accuracy: point.accuracyMeters)))
                    while spanIndex < usable.count, usable[spanIndex].lastSequence < point.sequence { spanIndex += 1 }
                    let within = spanIndex < usable.count && usable[spanIndex].firstSequence <= point.sequence
                    if within, triedSpan != spanIndex {
                        triedSpan = spanIndex
                        if let rendered = Self.append(usable[spanIndex], to: &path, offsetOf: { elapsedBySequence[$0].map(offset) }) {
                            laidSpan = spanIndex
                            usesMatched = true
                            renderedMatchedRanges.append(rendered)
                        }
                    }
                    if within, laidSpan == spanIndex {
                        // The pin of an observation follows the drawn line, at the instant of its own fix.
                        if let place = path.place(at: sampleOffset) {
                            matchedCoordinates[point.sequence] = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                        }
                    } else {
                        path.addVertex(latitude: point.latitude, longitude: point.longitude)
                        path.addKnot(offset: sampleOffset, meters: path.length)
                        if heldOffset > sampleOffset { path.addKnot(offset: heldOffset, meters: path.length) }
                    }
                    coordinateByKey["\(fragment.segmentID.uuidString):\(point.sequence)"] = matchedCoordinates[point.sequence] ?? coordinate
                }
                coverage.include(sequences: run.map { $0.point.sequence }, matched: renderedMatchedRanges)
                // Every measured fix of this stretch gives the timetable, not only the kept vertices.
                var fixes: [SchoolReplayPath.Fix] = []
                fixes.reserveCapacity(max(0, upper - lower + 1))
                for point in fragment.points where point.sequence > lower && point.sequence < upper
                    && point.accuracyMeters.isFinite && point.accuracyMeters <= SchoolCaptureDisplayRoute.maximumAccuracyMeters {
                    fixes.append(.init(offset: offset(point.elapsedMs), latitude: point.latitude, longitude: point.longitude))
                }
                path.refineTimetable(with: fixes)
                let coordinates = zip(path.latitudes, path.longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
                built.append(Fragment(id: "\(fragment.id):\(part)", coordinates: coordinates))
                paths.append(path)
                part += 1
                index = end
            }
            if let last = selected.last {
                let lastRetainedOffset = offset(last.heldUntilMs)
                if lastOffset > lastRetainedOffset { filteredTails.append(lastRetainedOffset...lastOffset) }
            }
        }
        samples.sort { $0.offset < $1.offset }
        let observationOffsets = observationDates.map { $0.timeIntervalSince(origin) }
        let end = max(endsAt.map { $0.timeIntervalSince(origin) } ?? 0, lastSourceOffset, observationOffsets.max() ?? 0)
        let total = max(1, end)

        var gaps: [ClosedRange<TimeInterval>] = []
        func clamp(_ value: TimeInterval) -> TimeInterval { min(total, max(0, value)) }
        for tail in filteredTails where clamp(tail.upperBound) > clamp(tail.lowerBound) {
            gaps.append(clamp(tail.lowerBound)...clamp(tail.upperBound))
        }
        if let first = samples.first, let last = samples.last {
            if clamp(first.offset) > 0 { gaps.append(0...clamp(first.offset)) }
            for (previous, next) in zip(samples, samples.dropFirst()) {
                let lower = clamp(previous.heldOffset), upper = clamp(next.offset)
                if upper > lower && (previous.fragmentIndex != next.fragmentIndex || upper - lower > maxPointAge) {
                    gaps.append(lower...upper)
                }
            }
            if total - clamp(last.heldOffset) > maxPointAge { gaps.append(clamp(last.heldOffset)...total) }
        } else {
            gaps = [0...total]
        }
        // Sorted and merged once: the playhead finds its gap by binary search.
        var merged: [ClosedRange<TimeInterval>] = []
        for gap in gaps.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, gap.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, gap.upperBound)
            } else {
                merged.append(gap)
            }
        }

        let items = observations.map { observation -> Item in
            var coordinate: CLLocationCoordinate2D?
            if let segment = observation.segmentId, let sequence = observation.pointSequence {
                coordinate = coordinateByKey["\(segment.uuidString):\(sequence)"]
            }
            return Item(id: observation.id, offset: observation.observedDate.map { $0.timeIntervalSince(origin) },
                        coordinate: coordinate, status: observation.eventStatus.flatMap { ObservationStatus(schoolValue: $0) },
                        isMarker: observation.isMarker, text: observation.text, themeKey: observation.themeKey)
        }
        start = origin
        duration = total
        fragments = built
        self.paths = paths
        self.samples = samples
        self.gaps = merged
        self.mapGaps = mapGaps
        let orderedItems = items.enumerated().sorted { left, right in
            switch (left.element.offset, right.element.offset) {
            case let (l?, r?): return l == r ? left.offset < right.offset : l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return left.offset < right.offset
            }
        }.map(\.element)
        self.items = orderedItems
        timedItems = orderedItems.filter { $0.offset != nil }
        usesMatchedRoute = usesMatched
        matchingCoverage = coverage
        var lines = mapGaps.map {
            DrivyRouteMapLine(id: "gap:\($0.id)", revision: 0, style: .gap, coordinates: [
                CLLocationCoordinate2D(latitude: $0.start.latitude, longitude: $0.start.longitude),
                CLLocationCoordinate2D(latitude: $0.end.latitude, longitude: $0.end.longitude)
            ])
        }
        for (index, path) in paths.enumerated() {
            lines.append(DrivyRouteMapLine(id: built[index].id, revision: path.vertexCount, style: .route,
                coordinates: zip(path.latitudes, path.longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }))
        }
        mapLines = lines
    }

    /// Lays the matched geometry of a span on the path, with the timetable of its anchors.
    /// Refused as a whole when it is not coherent: the measured fixes are then drawn instead.
    private static func append(_ span: SchoolMatchedRoute.Span, to path: inout SchoolReplayPath,
                               offsetOf: (Int) -> TimeInterval?) -> ClosedRange<Int>? {
        let geometry = SchoolEncodedPolyline.decode(span.geometry)
        guard geometry.count >= 2 else { return nil }
        var knots: [(sequence: Int, offset: TimeInterval, meters: Double)] = []
        var joinedSequence: Int?
        for anchor in span.anchors {
            let sequence = Int(anchor[0])
            guard sequence >= span.firstSequence, sequence <= span.lastSequence, let offset = offsetOf(sequence) else { return nil }
            // The vehicle may still have been held on the previous measured fix at that instant.
            if let last = path.knots.last, offset <= last.offset {
                if offset == last.offset && anchor[1] == 0 { joinedSequence = sequence }
                continue
            }
            if let last = knots.last, offset <= last.offset || anchor[1] < last.meters { continue }
            knots.append((sequence, offset, anchor[1]))
        }
        guard knots.count >= 2, let first = knots.first, let last = knots.last, last.sequence > first.sequence else { return nil }
        // The first vertex joins the previous measured fix to the road; distances along the
        // geometry start there.
        path.addVertex(latitude: geometry[0].latitude, longitude: geometry[0].longitude)
        let base = path.length
        for vertex in geometry.dropFirst() { path.addVertex(latitude: vertex.latitude, longitude: vertex.longitude) }
        let length = path.length - base
        for knot in knots { path.addKnot(offset: knot.offset, meters: base + min(length, knot.meters)) }
        return (joinedSequence ?? first.sequence)...last.sequence
    }

    /// Stable IDs survive a geometry refresh even when the observation's displayed coordinate changes.
    func retainedSelection(_ selectedID: UUID?) -> UUID? {
        guard let selectedID, items.contains(where: { $0.id == selectedID }) else { return nil }
        return selectedID
    }

    /// Measured position at an instant: the last sample at most `maxPointAge` old (binary search).
    func sample(at offset: TimeInterval, maxPointAge: TimeInterval = 15) -> Sample? {
        var low = 0, high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].offset <= offset { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        let candidate = samples[low - 1]
        if offset <= candidate.heldOffset { return candidate }
        if isInGap(offset) { return nil }
        // A known interruption is empty, even when the previous point is recent.
        if low < samples.count,
           samples[low].fragmentIndex != candidate.fragmentIndex || samples[low].offset - candidate.heldOffset > maxPointAge {
            return nil
        }
        return offset - candidate.heldOffset <= maxPointAge ? candidate : nil
    }

    private func isInGap(_ offset: TimeInterval) -> Bool {
        var low = 0, high = gaps.count
        while low < high {
            let middle = (low + high) / 2
            if gaps[middle].upperBound < offset { low = middle + 1 } else { high = middle }
        }
        return low < gaps.count && offset > gaps[low].lowerBound && offset <= gaps[low].upperBound
    }

    /// Display position at an instant, moving continuously along the drawn line between
    /// two measured instants. Nil exactly where `sample(at:)` is nil: a gap stays empty.
    /// Its heading looks a few metres ahead along the line, so the arrow turns with the road
    /// instead of with every short edge of it.
    func position(at offset: TimeInterval, lookAhead: Double = SchoolReplayTimeline.arrowLookAhead) -> SchoolReplayPath.Place? {
        guard let sample = sample(at: offset), paths.indices.contains(sample.fragmentIndex) else { return nil }
        let path = paths[sample.fragmentIndex]
        guard let meters = path.meters(at: offset), let place = path.place(atMeters: meters) else { return nil }
        return SchoolReplayPath.Place(latitude: place.latitude, longitude: place.longitude,
            heading: path.heading(atMeters: meters, ahead: lookAhead) ?? place.heading)
    }

    /// Direction of travel at an instant, seen from further ahead: what the camera turns to.
    func heading(at offset: TimeInterval, lookAhead: Double) -> Double? {
        guard let sample = sample(at: offset), paths.indices.contains(sample.fragmentIndex) else { return nil }
        let path = paths[sample.fragmentIndex]
        return path.meters(at: offset).flatMap { path.heading(atMeters: $0, ahead: lookAhead) }
    }

    /// Metres ahead that orient the arrow.
    static let arrowLookAhead = 8.0

    /// The same without movement between fixes (Reduce Motion): the playhead steps from fix to fix.
    func steppedPosition(at offset: TimeInterval) -> SchoolReplayPath.Place? {
        guard let sample = sample(at: offset), paths.indices.contains(sample.fragmentIndex),
              let place = paths[sample.fragmentIndex].place(at: sample.offset) else { return nil }
        return SchoolReplayPath.Place(latitude: place.latitude, longitude: place.longitude, heading: sample.heading ?? place.heading)
    }

    /// Last observation whose instant lies in `(after, upTo]`, by binary search.
    func lastTimedItem(after lower: TimeInterval, upTo upper: TimeInterval) -> Item? {
        var low = 0, high = timedItems.count
        while low < high {
            let middle = (low + high) / 2
            if (timedItems[middle].offset ?? 0) <= upper { low = middle + 1 } else { high = middle }
        }
        guard low > 0, let offset = timedItems[low - 1].offset, offset > lower else { return nil }
        return timedItems[low - 1]
    }
}

enum SchoolReplayFormatting {
    /// The replay uses the lesson's civil time, never the device's current time zone.
    static func startLabel(_ date: Date?, lessonTimeZone: String?) -> String? {
        guard let date, let lessonTimeZone, let zone = TimeZone(identifier: lessonTimeZone) else { return nil }
        return SchoolDateCache.shared.string(from: date, zone: zone, format: "d MMM 'à' HH:mm")
    }
}
