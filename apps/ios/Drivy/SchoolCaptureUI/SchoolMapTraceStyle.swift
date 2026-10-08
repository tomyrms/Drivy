import MapKit
import SwiftUI

/// A visual indication of an unmeasured interval, never a route or replay sample.
/// Endpoints are retained original fixes; no point is inserted into the capture.
struct SchoolMapRouteGap: Identifiable {
    let id: String
    let start: SchoolCapturePoint
    let end: SchoolCapturePoint
    let line: MKPolyline

    init(id: String, start: SchoolCapturePoint, end: SchoolCapturePoint) {
        self.id = id; self.start = start; self.end = end
        let coordinates = [start, end].map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        line = MKPolyline(coordinates: coordinates, count: coordinates.count)
    }

    /// Look for silence in the original measurements, not in the thinned display
    /// samples: a stationary car can have a long interval between displayed fixes.
    static func withinSegment(_ source: [SchoolCapturePoint], displayed: [SchoolCaptureDisplayRoute.Sample],
                              idPrefix: String, maximumGap: TimeInterval = SchoolCaptureDisplayRoute.maximumGapSeconds) -> [Self] {
        let isOrdered = zip(source, source.dropFirst()).allSatisfy { previous, next in previous.sequence < next.sequence }
        let ordered = isOrdered ? source : source.sorted { $0.sequence < $1.sequence }
        let silenceEnds = zip(ordered, ordered.dropFirst()).compactMap { previous, next -> Int? in
            guard next.sequence > previous.sequence, next.elapsedMs > previous.elapsedMs,
                  Double(next.elapsedMs - previous.elapsedMs) / 1000 > maximumGap else { return nil }
            return next.sequence
        }
        var silenceIndex = 0
        var result: [Self] = []
        for (previous, next) in zip(displayed, displayed.dropFirst()) {
            var hasSilence = false
            while silenceIndex < silenceEnds.count, silenceEnds[silenceIndex] <= next.point.sequence {
                if silenceEnds[silenceIndex] > previous.point.sequence { hasSilence = true }
                silenceIndex += 1
            }
            if next.startsFragment && hasSilence {
                result.append(Self(id: "\(idPrefix):\(next.point.sequence)", start: previous.point, end: next.point))
            }
        }
        return result
    }

    /// Elapsed clocks restart at segment boundaries; only their recorded dates
    /// can establish silence between two segments of the same capture.
    static func betweenSegments(id: String, previousSource: SchoolCapturePoint, nextSource: SchoolCapturePoint,
                                previousDisplayed: SchoolCapturePoint, nextDisplayed: SchoolCapturePoint,
                                maximumGap: TimeInterval = SchoolCaptureDisplayRoute.maximumGapSeconds) -> Self? {
        guard let previousDate = SchoolLesson.date(previousSource.capturedAt),
              let nextDate = SchoolLesson.date(nextSource.capturedAt),
              nextDate.timeIntervalSince(previousDate) > maximumGap else { return nil }
        return Self(id: id, start: previousDisplayed, end: nextDisplayed)
    }
}

struct SchoolMapEndpointMarker: View {
    enum Kind {
        case start, end
        var label: String { self == .start ? "Début du tracé enregistré" : "Fin du tracé enregistré" }
    }
    let kind: Kind

    var body: some View {
        Circle()
            .fill(kind == .start ? DrivyTheme.surface : DrivyTheme.text)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(DrivyTheme.text, lineWidth: 3))
            .padding(2)
            .background(DrivyTheme.routeHalo, in: Circle())
            .accessibilityLabel(kind.label)
    }
}

/// One marker grammar in live capture, replay and the lesson preview.
struct SchoolMapObservationMarker: View {
    let symbol: String
    let color: Color
    var isSelected = false
    var isPending = false

    var body: some View {
        Image(systemName: symbol)
            .font(isSelected ? .body.weight(.bold) : DrivyMapGlyph.compactObservation)
            .foregroundStyle(color)
            .frame(width: isSelected ? 40 : 28, height: isSelected ? 40 : 28)
            .background(DrivyTheme.surface, in: Circle())
            .overlay(Circle().strokeBorder(isSelected ? DrivyTheme.accent : color,
                style: StrokeStyle(lineWidth: 3, dash: isPending ? [3, 2] : [])))
            .padding(2)
            .background(DrivyTheme.routeHalo, in: Circle())
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
