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
    var followsPosition: Binding<Bool> = .constant(false)
    var showsOriginBadge = true
    /// Margin around the fitted route (1 = edge to edge). Small previews use a wider
    /// margin so markers never sit under the map attribution.
    var fitMargin: Double = 1.16
    /// Replay filter: only these observations get a marker (nil = all).
    var visibleObservationIDs: Set<UUID>? = nil
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
            if let visibleObservationIDs, !visibleObservationIDs.contains(observation.id) { return nil }
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
                    MapPolyline(coordinates: segment.coordinates).stroke(DrivyTheme.routeHalo, lineWidth: 9)
                    MapPolyline(coordinates: segment.coordinates).stroke(DrivyTheme.route, lineWidth: 5)
                }
            }
            ForEach(locatedObservations) { item in
                Annotation(item.observation.theme.label, coordinate: item.point.coordinate) {
                    Button { selectedObservationID = item.id } label: {
                        observationMarker(item.observation)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.observation.theme.label), \(item.observation.status.label)")
                    .accessibilityAddTraits(selectedObservationID == item.id ? [.isSelected] : [])
                    .accessibilityHint("Afficher cette observation")
                }.annotationTitles(.hidden)
            }
            if let currentPoint {
                Annotation(session.isExample ? "Position d’exemple" : replayDate == nil ? "Dernière position enregistrée" : "Position enregistrée", coordinate: currentPoint.coordinate) {
                    Circle().fill(DrivyTheme.route).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(DrivyTheme.routeHalo, lineWidth: 3)).padding(DrivySpacing.xs)
                        .background(DrivyTheme.route.opacity(0.18), in: Circle())
                        .accessibilityLabel(session.isExample ? "Position d’exemple" : "Position enregistrée")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .overlay(alignment: .topTrailing) {
            if session.isExample && showsOriginBadge {
                Label("Exemple · données fictives", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xs)
                    .background(DrivyTheme.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                    .padding(DrivySpacing.s)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsEmptyState && session.points.isEmpty {
                Label(session.usesGPS ? "En attente de position" : "Sans GPS", systemImage: "location.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .padding(.horizontal, DrivySpacing.s).padding(.vertical, DrivySpacing.xs)
                    .background(DrivyTheme.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                    .padding(DrivySpacing.m)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsControls && !session.points.isEmpty {
                Button { followsPosition.wrappedValue = false; fitRoute() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3).foregroundStyle(DrivyTheme.text).frame(width: 48, height: 48)
                        .drivyLegibleMapControl(in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Voir tout le trajet").padding(DrivySpacing.m)
            }
        }
        .onAppear { if followsPosition.wrappedValue { followPoint() } else { fitRoute() } }
        .onChange(of: camera.positionedByUser) { _, byUser in
            if byUser { followsPosition.wrappedValue = false }
        }
        .onChange(of: followsPosition.wrappedValue) { _, follows in
            if follows { followPoint() }
        }
        .onChange(of: currentPoint?.id) { _, _ in
            if followsPosition.wrappedValue && !camera.positionedByUser { followPoint() }
        }
        .onChange(of: session.points.isEmpty) { wasEmpty, isEmpty in
            if wasEmpty && !isEmpty {
                if followsPosition.wrappedValue { followPoint() } else { fitRoute() }
            }
        }
        .onChange(of: resetCameraID) { _, _ in
            followsPosition.wrappedValue = false
            fitRoute()
        }
        .accessibilityLabel(session.isExample ? "Carte d’un trajet fictif" : "Carte du trajet")
    }

    private func observationMarker(_ observation: LessonObservation) -> some View {
        let selected = selectedObservationID == observation.id
        return Image(systemName: selected ? observation.theme.journeySymbol : observation.status.symbol)
            .font(selected ? .body.weight(.semibold) : .caption.weight(.heavy))
            .foregroundStyle(selected ? DrivyTheme.onAccent : observation.status.color)
            .frame(width: selected ? 40 : 26, height: selected ? 40 : 26)
            .background(selected ? DrivyTheme.accent : DrivyTheme.surface, in: Circle())
            .overlay(Circle().strokeBorder(selected ? DrivyTheme.routeHalo : observation.status.color, lineWidth: selected ? 3 : 2))
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: observation.status.symbol)
                        .font(.caption2.weight(.heavy))
                        .imageScale(.small)
                        .foregroundStyle(DrivyTheme.surface)
                        .frame(width: 18, height: 18)
                        .background(observation.status.color, in: Circle())
                        .overlay(Circle().strokeBorder(DrivyTheme.routeHalo, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            // Map markers keep a fixed geometry; their text alternative is the VoiceOver label.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private func followPoint() {
        guard let point = currentPoint else { return }
        camera = .region(MKCoordinateRegion(center: point.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)))
    }

    private func fitRoute() {
        if session.points.isEmpty { camera = .region(JourneyMapRegion.overview) }
        else {
            let mapPoints = session.points.map { MKMapPoint($0.coordinate) }
            let minX = mapPoints.map(\.x).min() ?? 0
            let maxX = mapPoints.map(\.x).max() ?? minX
            let minY = mapPoints.map(\.y).min() ?? 0
            let maxY = mapPoints.map(\.y).max() ?? minY
            let center = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let minimumSpan = MKMapPointsPerMeterAtLatitude(center.coordinate.latitude) * 160
            let margin = max(1, fitMargin)
            let width = max(maxX - minX, minimumSpan) * margin
            let height = max(maxY - minY, minimumSpan) * margin
            // MapKit frames this rectangle inside the actual safe area supplied
            // by the native top and bottom controls, including enlarged text.
            camera = .rect(MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
        }
    }
}

extension RecordedPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
