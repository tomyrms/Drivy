import MapKit
import SwiftUI

/// A geographic overview is only a map camera, never a recorded location.
enum JourneyMapRegion {
    static let overview = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.8, longitude: 8.2),
        span: MKCoordinateSpan(latitudeDelta: 2.7, longitudeDelta: 4.5))
}

struct RouteMapView: View {
    let session: DrivingSession
    @Binding var selectedObservationID: UUID?
    var replayDate: Date? = nil
    var showsControls = true
    var showsEmptyState = true
    var resetCameraID: UUID? = nil
    @State private var camera: MapCameraPosition = .region(JourneyMapRegion.overview)

    private struct Segment: Identifiable {
        let id: UUID
        let coordinates: [CLLocationCoordinate2D]
    }
    private struct LocatedObservation: Identifiable {
        let observation: LessonObservation
        let point: RecordedPoint
        var id: UUID { observation.id }
    }
    private var segments: [Segment] {
        Dictionary(grouping: session.points, by: \.segmentID)
            .map { id, points in Segment(id: id, coordinates: points.sorted { $0.timestamp < $1.timestamp }.map(\.coordinate)) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private var locatedObservations: [LocatedObservation] {
        let points = Dictionary(session.points.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return session.observations.compactMap { observation in
            guard let anchor = observation.anchorPointID, let point = points[anchor] else { return nil }
            return LocatedObservation(observation: observation, point: point)
        }
    }
    private var currentPoint: RecordedPoint? {
        guard let replayDate else { return session.points.last }
        return session.points.last { $0.timestamp <= replayDate && replayDate.timeIntervalSince($0.timestamp) <= 15 }
    }

    var body: some View {
        Map(position: $camera) {
            ForEach(segments) { segment in
                if segment.coordinates.count > 1 {
                    MapPolyline(coordinates: segment.coordinates).stroke(DrivyTheme.surface, lineWidth: 9)
                    MapPolyline(coordinates: segment.coordinates).stroke(DrivyTheme.accent, lineWidth: 5)
                }
            }
            ForEach(locatedObservations) { item in
                Annotation(item.observation.theme.label, coordinate: item.point.coordinate) {
                    Button { selectedObservationID = item.id } label: {
                        Image(systemName: selectedObservationID == item.id ? item.observation.theme.journeySymbol : item.observation.status.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(item.observation.status.color)
                            .frame(width: 38, height: 38)
                            .background(DrivyTheme.surface, in: Circle())
                            .overlay(Circle().stroke(item.observation.status.color, lineWidth: 2))
                            .padding(3)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.observation.theme.label), \(item.observation.status.label)")
                    .accessibilityHint("Afficher cette observation")
                }.annotationTitles(.hidden)
            }
            if let currentPoint {
                Annotation(replayDate == nil ? "Dernière position enregistrée" : "Position enregistrée", coordinate: currentPoint.coordinate) {
                    Circle().fill(DrivyTheme.accent).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3)).padding(8)
                        .background(DrivyTheme.accent.opacity(0.18), in: Circle())
                        .accessibilityLabel("Position enregistrée")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .overlay(alignment: .topLeading) {
            if showsEmptyState && session.points.isEmpty {
                Label(session.usesGPS ? "En attente de position" : "Sans GPS", systemImage: "location.slash")
                    .font(.caption.weight(.medium)).padding(12)
                    .background(DrivyTheme.surface, in: Capsule()).padding(16)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsControls && !session.points.isEmpty {
                Button { fitRoute() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3).frame(width: 48, height: 48)
                        .background(DrivyTheme.surface, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Voir tout le trajet").padding(16)
            }
        }
        .onAppear { fitRoute() }
        .onChange(of: selectedObservationID) { _, id in
            guard let item = locatedObservations.first(where: { $0.id == id }) else { return }
            camera = .region(MKCoordinateRegion(center: item.point.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
        }
        .onChange(of: session.points.isEmpty) { wasEmpty, isEmpty in if wasEmpty && !isEmpty { fitRoute() } }
        .onChange(of: resetCameraID) { _, _ in fitRoute() }
        .accessibilityLabel("Carte du trajet")
    }
    private func fitRoute() {
        if session.points.isEmpty { camera = .region(JourneyMapRegion.overview) }
        else { camera = .automatic }
    }
}

extension RecordedPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
