import Foundation

/// Display policy only. Storage and transfer retain every measured point unchanged.
/// Thresholds are technical choices awaiting road qualification, not GPS guarantees.
struct SchoolCaptureDisplayRoute {
    struct Sample {
        let point: SchoolCapturePoint
        let startsFragment: Bool
        /// A silence of the original measurements precedes this sample (dashed connector).
        let followsSilence: Bool
        /// Elapsed time of the last measurement received while the vehicle stood on this position.
        /// Equal to the point's own time when it left at once.
        var heldUntilMs: Int
    }

    static let maximumAccuracyMeters = 30.0
    static let maximumSpeedMetersPerSecond = 50.0
    static let maximumGapSeconds = 15.0
    /// Uncertainty granted to a jump: two honest fixes never excuse more than this.
    static let maximumJumpSlackMeters = 20.0
    /// A rejected fix or two do not cut the line; a longer blind stretch does.
    static let bridgeSeconds = 4.0

    static func fragments(_ samples: [Sample]) -> [[SchoolCapturePoint]] {
        var fragments: [[SchoolCapturePoint]] = []
        for sample in samples {
            if sample.startsFragment || fragments.isEmpty { fragments.append([]) }
            fragments[fragments.count - 1].append(sample.point)
        }
        return fragments
    }

    /// Select original measurements, preserving their durable sequence. Never smooth,
    /// snap to a road, or move an observation to a neighbouring point: a retained
    /// sample is always one measured fix, unchanged.
    static func select(_ source: [SchoolCapturePoint], maximumGap: TimeInterval = maximumGapSeconds) -> [Sample] {
        let ordered = zip(source, source.dropFirst()).allSatisfy { previous, next in previous.sequence < next.sequence }
            ? source : source.sorted { $0.sequence < $1.sequence }
        var selector = Selector(maximumGap: maximumGap)
        for point in ordered { selector.append(point) }
        return selector.samples
    }

    /// The same policy, one measurement at a time: a live trip costs a constant amount
    /// of work per fix whatever its length. Only the last sample may still change
    /// (held longer, or withdrawn as a spike); every earlier one is final.
    struct Selector {
        enum Change: Equatable {
            /// Nothing to redraw.
            case none
            /// The vehicle is still on the last sample.
            case held
            case appended
            /// The last sample was a spike: it is withdrawn and this fix takes its place.
            case replacedLast
        }

        private(set) var samples: [Sample] = []
        let maximumGap: TimeInterval
        private var previousInput: (sequence: Int, elapsedMs: Int)?
        private var forcedGap = true
        private var silenceSinceRetained = false
        private var rejectedSinceRetained = false
        private var moving = false
        private var lastBearing: Double?

        init(maximumGap: TimeInterval = SchoolCaptureDisplayRoute.maximumGapSeconds) {
            self.maximumGap = maximumGap
        }

        @discardableResult
        mutating func append(_ point: SchoolCapturePoint) -> Change {
            let prior = previousInput
            defer { previousInput = (point.sequence, point.elapsedMs) }
            var silence = prior == nil
            if let prior, point.sequence > prior.sequence, point.elapsedMs > prior.elapsedMs,
               Double(point.elapsedMs - prior.elapsedMs) / 1000 > maximumGap {
                silence = true
                silenceSinceRetained = true
            }
            guard point.sequence >= 0, point.elapsedMs >= 0,
                  point.latitude.isFinite, point.longitude.isFinite,
                  (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
                  point.accuracyMeters.isFinite, (0...SchoolCaptureDisplayRoute.maximumAccuracyMeters).contains(point.accuracyMeters) else {
                rejectedSinceRetained = true
                return .none
            }
            if let prior {
                // Chronology is the durable sequence: a fix that does not advance is never drawn.
                guard point.sequence > prior.sequence, point.elapsedMs > prior.elapsedMs else {
                    forcedGap = true
                    return .none
                }
                if point.sequence != prior.sequence + 1 { forcedGap = true }
            }
            guard let retained = samples.last else { return start(point) }
            let seconds = Double(point.elapsedMs - retained.heldUntilMs) / 1000
            guard seconds > 0 else { forcedGap = true; return .none }
            if silence { return start(point) }

            let distance = Self.distance(retained.point, point)
            // Allow the uncertainty of both real fixes when checking a jump, within reason.
            let slack = min(SchoolCaptureDisplayRoute.maximumJumpSlackMeters, retained.point.accuracyMeters + point.accuracyMeters)
            guard max(0, distance - slack) / seconds <= SchoolCaptureDisplayRoute.maximumSpeedMetersPerSecond else {
                rejectedSinceRetained = true
                return .none
            }
            // Hold the last measured location inside the uncertainty radius. Accumulated
            // movement leaves it, and a vehicle already rolling keeps its vertices as long
            // as it goes on the same way: a slow turn or a manoeuvre is not noise.
            let radius = max(3, min(15, max(retained.point.accuracyMeters, point.accuracyMeters)))
            if distance < radius {
                let bearing = Self.bearing(retained.point, point)
                let continues = moving && distance >= 1.5 && distance / seconds >= 1
                    && (lastBearing.map { abs(SchoolTrackGeometry.angleDelta(from: $0, to: bearing)) <= 60 } ?? false)
                if !continues {
                    moving = false
                    samples[samples.count - 1].heldUntilMs = point.elapsedMs
                    rejectedSinceRetained = false
                    return .held
                }
            }
            if samples.count >= 2, !forcedGap, !rejectedSinceRetained, !retained.startsFragment,
               retained.heldUntilMs == retained.point.elapsedMs,
               Self.isSpike(before: samples[samples.count - 2], spike: retained.point, after: point) {
                samples.removeLast()
                rejectedSinceRetained = true
                moving = false; lastBearing = nil
                accept(point, after: samples[samples.count - 1])
                return .replacedLast
            }
            accept(point, after: retained)
            return .appended
        }

        private mutating func start(_ point: SchoolCapturePoint) -> Change {
            samples.append(Sample(point: point, startsFragment: true, followsSilence: silenceSinceRetained && !samples.isEmpty,
                                  heldUntilMs: point.elapsedMs))
            forcedGap = false; silenceSinceRetained = false; rejectedSinceRetained = false
            moving = false; lastBearing = nil
            return .appended
        }

        private mutating func accept(_ point: SchoolCapturePoint, after anchor: Sample) {
            let span = Double(point.elapsedMs - anchor.heldUntilMs) / 1000
            let starts = forcedGap || span > maximumGap
                || (rejectedSinceRetained && span > SchoolCaptureDisplayRoute.bridgeSeconds)
            samples.append(Sample(point: point, startsFragment: starts, followsSilence: starts && silenceSinceRetained,
                                  heldUntilMs: point.elapsedMs))
            if starts {
                moving = false; lastBearing = nil
            } else {
                let distance = Self.distance(anchor.point, point)
                moving = span > 0 && distance / span >= 1
                lastBearing = Self.bearing(anchor.point, point)
            }
            forcedGap = false; silenceSinceRetained = false; rejectedSinceRetained = false
        }

        /// One fix thrown far aside and back within a few seconds: no car leaves a
        /// street and returns to it that fast. A U-turn or a reverse takes longer.
        private static func isSpike(before: Sample, spike: SchoolCapturePoint, after: SchoolCapturePoint) -> Bool {
            let seconds = Double(after.elapsedMs - before.heldUntilMs) / 1000
            guard seconds > 0, seconds <= 4 else { return false }
            // Far from the line joining its two neighbours, for a detour at least twice the direct way.
            let leg = max(12, 2.5 * spike.accuracyMeters)
            let aside = SchoolTrackGeometry.metersFromSegment(latitude: spike.latitude, longitude: spike.longitude,
                startLatitude: before.point.latitude, startLongitude: before.point.longitude,
                endLatitude: after.latitude, endLongitude: after.longitude)
            return aside >= leg && distance(before.point, spike) + distance(spike, after) >= 2 * distance(before.point, after)
        }

        private static func distance(_ a: SchoolCapturePoint, _ b: SchoolCapturePoint) -> Double {
            SchoolTrackGeometry.meters(latitude1: a.latitude, longitude1: a.longitude, latitude2: b.latitude, longitude2: b.longitude)
        }

        private static func bearing(_ a: SchoolCapturePoint, _ b: SchoolCapturePoint) -> Double {
            SchoolTrackGeometry.bearing(latitude1: a.latitude, longitude1: a.longitude, latitude2: b.latitude, longitude2: b.longitude)
        }
    }
}
