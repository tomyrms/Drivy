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
    var framingInsets = EdgeInsets()
    var showsOriginBadge = true
    @State private var camera: MapCameraPosition = .region(JourneyMapRegion.overview)
    @State private var viewport = CGSize.zero

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
                Annotation(session.isExample ? "Position d’exemple" : replayDate == nil ? "Dernière position enregistrée" : "Position enregistrée", coordinate: currentPoint.coordinate) {
                    Circle().fill(DrivyTheme.accent).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3)).padding(8)
                        .background(DrivyTheme.accent.opacity(0.18), in: Circle())
                        .accessibilityLabel(session.isExample ? "Position d’exemple" : "Position enregistrée")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            let changed = viewport != size
            viewport = size
            if changed { fitRoute() }
        }
        .overlay(alignment: .topTrailing) {
            if session.isExample && showsOriginBadge {
                Text("Exemple · données fictives")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(DrivyTheme.surface, in: Capsule()).padding(12)
            }
        }
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
        .accessibilityLabel(session.isExample ? "Carte d’un trajet fictif" : "Carte du trajet")
    }
    private func fitRoute() {
        if session.points.isEmpty { camera = .region(JourneyMapRegion.overview) }
        else if viewport.width > 0 && viewport.height > 0 {
            let mapPoints = session.points.map { MKMapPoint($0.coordinate) }
            let minX = mapPoints.map(\.x).min() ?? 0
            let maxX = mapPoints.map(\.x).max() ?? minX
            let minY = mapPoints.map(\.y).min() ?? 0
            let maxY = mapPoints.map(\.y).max() ?? minY
            let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let minimumSpan = MKMapPointsPerMeterAtLatitude(center.coordinate.latitude) * 160
            let horizontalPadding = 36.0
            let verticalPadding = 36.0
            let visibleWidth = max(80, Double(viewport.width - framingInsets.leading - framingInsets.trailing) - 2 * horizontalPadding)
            let visibleHeight = max(80, Double(viewport.height - framingInsets.top - framingInsets.bottom) - 2 * verticalPadding)
            let scale = max(max(maxX - minX, minimumSpan) / visibleWidth, max(maxY - minY, minimumSpan) / visibleHeight)
            let width = scale * Double(viewport.width)
            let height = scale * Double(viewport.height)
            // Move the camera south when a bottom dock covers the map so the
            // complete route is framed in the remaining visible rectangle.
            let offsetX = Double(framingInsets.trailing - framingInsets.leading) / 2 * scale
            let offsetY = Double(framingInsets.bottom - framingInsets.top) / 2 * scale
            camera = .rect(MKMapRect(x: center.x + offsetX - width / 2, y: center.y + offsetY - height / 2, width: width, height: height))
        } else { camera = .automatic }
    }
}

extension RecordedPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
