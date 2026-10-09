import MapKit
import SwiftUI

/// Carte d’un trajet enregistré, avec les observations ancrées. Aucune position n’est inventée :
/// sans mesure, la section n’est pas affichée.
struct LessonTrackMap: View {
    struct Pin: Identifiable {
        let id: UUID
        let latitude: Double
        let longitude: Double
        let color: Color
        /// Observation touchée dans la liste : son épingle grossit, sa couleur ne change pas.
        var isSelected = false
        var symbol = "bookmark.fill"
        var label = "Repère"
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }
    private struct Line: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
    }
    let segments: [[SchoolCapturePoint]]
    let pins: [Pin]
    var height: CGFloat = DrivyMapLayout.previewHeight

    private var lines: [Line] {
        segments.enumerated().map { index, points in
            Line(id: index, coordinates: points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
        }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(lines) { line in
                if line.coordinates.count > 1 {
                    MapPolyline(coordinates: line.coordinates).stroke(DrivyTheme.routeHalo,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: line.coordinates).stroke(DrivyTheme.route,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                } else if let coordinate = line.coordinates.first {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.route).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            if let coordinate = lines.first(where: { !$0.coordinates.isEmpty })?.coordinates.first {
                Annotation("Début du tracé enregistré", coordinate: coordinate) {
                    SchoolMapEndpointMarker(kind: .start)
                }.annotationTitles(.hidden)
            }
            if segments.reduce(0, { $0 + $1.count }) > 1,
               let coordinate = lines.last(where: { !$0.coordinates.isEmpty })?.coordinates.last {
                Annotation("Fin du tracé enregistré", coordinate: coordinate) {
                    SchoolMapEndpointMarker(kind: .end)
                }.annotationTitles(.hidden)
            }
            ForEach(pins) { pin in
                Annotation(pin.label, coordinate: pin.coordinate) {
                    SchoolMapObservationMarker(symbol: pin.symbol, color: pin.color, isSelected: pin.isSelected)
                        .accessibilityLabel(pin.label)
                        .accessibilityAddTraits(pin.isSelected ? [.isSelected] : [])
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .frame(height: height)
        .accessibilityLabel("Trajet de la leçon")
    }
}
