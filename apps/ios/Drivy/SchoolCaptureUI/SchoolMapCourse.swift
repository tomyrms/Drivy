import MapKit
import SwiftUI

/// Retain the measured polyline while only the camera or playback cursor moves.
/// Rebuilding thousands of coordinates on every animation frame stalls the map.
struct SchoolMapRouteFragment: Identifiable {
    let id: String
    let line: MKPolyline
    let firstCoordinate: CLLocationCoordinate2D?

    init(id: String, coordinates: [CLLocationCoordinate2D]) {
        self.id = id
        line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        firstCoordinate = coordinates.first
    }
}

/// Orientation inferred only from measured movement. Small GPS drift does not turn
/// the map while stopped; a gap or a new segment starts a fresh direction.
struct SchoolMapCourse {
    private var origin: CLLocationCoordinate2D?
    private var originAccuracy: Double = 0
    private var previousTime: TimeInterval?
    private(set) var heading: Double?

    mutating func receive(_ coordinate: CLLocationCoordinate2D, at time: TimeInterval, accuracy: Double) -> Double? {
        if let previousTime, time <= previousTime || time - previousTime > 15 {
            origin = nil; heading = nil
        }
        defer { previousTime = time }
        guard let origin else {
            self.origin = coordinate; originAccuracy = accuracy
            return nil
        }
        let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        let threshold = max(3, min(15, max(originAccuracy, accuracy)))
        guard distance >= threshold else { return heading }
        heading = Self.bearing(from: origin, to: coordinate)
        self.origin = coordinate; originAccuracy = accuracy
        return heading
    }

    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let latitude1 = from.latitude * .pi / 180, latitude2 = to.latitude * .pi / 180
        let longitude = (to.longitude - from.longitude) * .pi / 180
        let y = sin(longitude) * cos(latitude2)
        let x = cos(latitude1) * sin(latitude2) - sin(latitude1) * cos(latitude2) * cos(longitude)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Arrow points along the recorded movement, including when the map is rotated
/// manually. With no trustworthy course, the ordinary measured-position dot stays.
struct SchoolMapPositionMarker: View {
    let course: Double?
    let mapHeading: Double

    var body: some View {
        Group {
            if let course {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 22, weight: .bold))
                    .rotationEffect(.degrees(course - mapHeading))
            } else {
                Circle().frame(width: 15, height: 15)
            }
        }
        .foregroundStyle(DrivyTheme.route)
        .frame(width: 34, height: 34)
        .background(DrivyTheme.surface, in: Circle())
        .overlay(Circle().strokeBorder(DrivyTheme.routeHalo, lineWidth: 2))
        .shadow(color: DrivyTheme.shadow.opacity(0.2), radius: 3, y: 1)
        .accessibilityLabel(course == nil ? "Position enregistrée" : "Position et direction du déplacement")
    }
}
