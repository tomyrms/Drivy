import CoreLocation
import Foundation

/// Display policy only. Storage and transfer retain every measured point unchanged.
/// Thresholds are technical choices awaiting road qualification, not GPS guarantees.
struct SchoolCaptureDisplayRoute {
    struct Sample {
        let point: SchoolCapturePoint
        let startsFragment: Bool
    }

    static let maximumAccuracyMeters = 35.0
    static let maximumSpeedMetersPerSecond = 55.0
    static let maximumGapSeconds = 15.0

    static func fragments(_ samples: [Sample]) -> [[SchoolCapturePoint]] {
        var fragments: [[SchoolCapturePoint]] = []
        for sample in samples {
            if sample.startsFragment || fragments.isEmpty { fragments.append([]) }
            fragments[fragments.count - 1].append(sample.point)
        }
        return fragments
    }

    /// Select original measurements, preserving their durable sequence. Never smooth,
    /// interpolate, snap to a road, or move an observation to a neighbouring point.
    static func select(_ source: [SchoolCapturePoint], maximumGap: TimeInterval = maximumGapSeconds) -> [Sample] {
        let ordered = zip(source, source.dropFirst()).allSatisfy { previous, next in previous.sequence < next.sequence }
            ? source : source.sorted { $0.sequence < $1.sequence }
        var result: [Sample] = []
        var previousInput: SchoolCapturePoint?
        var retained: SchoolCapturePoint?
        var hasGap = true
        for point in ordered {
            defer { previousInput = point }
            guard point.sequence >= 0, point.elapsedMs >= 0,
                  point.latitude.isFinite, point.longitude.isFinite,
                  (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
                  point.accuracyMeters.isFinite, (0...maximumAccuracyMeters).contains(point.accuracyMeters) else {
                hasGap = true
                continue
            }
            if let previousInput {
                guard point.sequence > previousInput.sequence, point.elapsedMs > previousInput.elapsedMs else {
                    hasGap = true
                    continue
                }
                if point.sequence != previousInput.sequence + 1 { hasGap = true }
            }
            if let retained {
                let seconds = Double(point.elapsedMs - retained.elapsedMs) / 1000
                guard seconds > 0 else { hasGap = true; continue }
                if seconds > maximumGap { hasGap = true }
                let signalGap = previousInput.map { Double(point.elapsedMs - $0.elapsedMs) / 1000 > maximumGap } ?? true
                if !signalGap {
                    let distance = CLLocation(latitude: retained.latitude, longitude: retained.longitude)
                        .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                    // Allow the uncertainty of both real fixes when checking a jump.
                    let minimumDistance = max(0, distance - retained.accuracyMeters - point.accuracyMeters)
                    guard minimumDistance / seconds <= maximumSpeedMetersPerSecond else {
                        hasGap = true
                        continue
                    }
                    // Hold the last measured location inside a small uncertainty radius.
                    // Accumulated movement can leave it: a slow turn is not a speed filter.
                    let stationaryRadius = max(2, min(8, max(retained.accuracyMeters, point.accuracyMeters)))
                    if distance < stationaryRadius { continue }
                }
            }
            result.append(Sample(point: point, startsFragment: hasGap))
            retained = point
            hasGap = false
        }
        return result
    }
}
