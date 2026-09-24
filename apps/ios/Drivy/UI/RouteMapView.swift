import MapKit
import SwiftUI

struct RouteMapView: View {
    let session: DrivingSession
    @Binding var selectedObservationID: UUID?
    var replayDate: Date? = nil
    @State private var camera: MapCameraPosition = .automatic

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
            .map { id, points in
                Segment(id: id, coordinates: points.sorted { $0.timestamp < $1.timestamp }.map(\.coordinate))
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private var locatedObservations: [LocatedObservation] {
        let points = Dictionary(uniqueKeysWithValues: session.points.map { ($0.id, $0) })
        return session.observations.compactMap { observation in
            guard let anchor = observation.anchorPointID, let point = points[anchor] else { return nil }
            return LocatedObservation(observation: observation, point: point)
        }
    }

    private var currentPoint: RecordedPoint? {
        guard let replayDate else { return session.points.last }
        // Never invent a position or interpolate across a recording interruption.
        return session.points.last { point in
            point.timestamp <= replayDate && replayDate.timeIntervalSince(point.timestamp) <= 15
        }
    }

    var body: some View {
        Map(position: $camera) {
            ForEach(segments) { segment in
                if segment.coordinates.count > 1 {
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(DrivyTheme.canvas, lineWidth: 9)
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(DrivyTheme.accent, lineWidth: 5)
                }
            }
            ForEach(locatedObservations) { item in
                Annotation(item.observation.theme.label, coordinate: item.point.coordinate) {
                    Button {
                        selectedObservationID = item.id
                    } label: {
                        Image(systemName: selectedObservationID == item.id ? item.observation.theme.symbol : item.observation.status.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(item.observation.status.color)
                            .frame(width: 44, height: 44)
                            .background(DrivyTheme.surface, in: Circle())
                            .overlay(Circle().stroke(item.observation.status.color, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.observation.theme.label), \(item.observation.status.label)")
                    .accessibilityHint("Afficher cette observation")
                }
                .annotationTitles(.hidden)
            }
            if let currentPoint {
                Annotation(replayDate == nil ? "Dernière position enregistrée" : "Position enregistrée", coordinate: currentPoint.coordinate) {
                    Circle()
                        .fill(DrivyTheme.accent)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .padding(8)
                        .background(DrivyTheme.accent.opacity(0.18), in: Circle())
                        .accessibilityLabel("Position enregistrée")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topLeading) {
            if session.points.isEmpty {
                Label("Aucune position enregistrée", systemImage: "location.slash")
                    .font(.subheadline)
                    .padding(12)
                    .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .padding(16)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !session.points.isEmpty {
                Button { camera = .automatic } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .frame(width: 48, height: 48)
                        .background(DrivyTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voir tout le trajet")
                .padding(.trailing, 16)
                .padding(.bottom, 28)
            }
        }
        .onChange(of: selectedObservationID) { _, id in
            guard let item = locatedObservations.first(where: { $0.id == id }) else { return }
            camera = .region(MKCoordinateRegion(
                center: item.point.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            ))
        }
        .onChange(of: session.points.isEmpty) { wasEmpty, isEmpty in
            if wasEmpty && !isEmpty { camera = .automatic }
        }
        .accessibilityLabel("Carte du trajet d’essai")
    }
}

extension RecordedPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
