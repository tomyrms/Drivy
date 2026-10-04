import MapKit
import SwiftUI

/// Carte du trajet en cours : tracé mesuré, signalements ancrés et dernière position.
struct SchoolCaptureLiveMap: View {
    let segments: [SchoolCaptureMapSegment]
    let observations: [SchoolLiveMapObservation]
    let resetCameraID: UUID
    @Binding var followsPosition: Bool
    @State private var camera: MapCameraPosition = .automatic
    @State private var mapHeading = 0.0
    @State private var followDistance = 650.0
    @State private var heading: Double?
    @State private var drawnSegments: [SchoolMapRouteFragment] = []
    @State private var selectedSamples: [UUID: [SchoolCaptureDisplayRoute.Sample]] = [:]
    @State private var cachedCounts: [UUID: Int] = [:]
    @State private var last: SchoolCapturePoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { segments.reduce(0) { $0 + $1.measurements.count } }
    private var contentKey: String { segments.map { "\($0.id):\($0.measurements.count)" }.joined(separator: ",") }

    var body: some View {
        Map(position: $camera) {
            ForEach(drawnSegments) { segment in
                if segment.line.pointCount > 1 {
                    // Trait épais : lisible d’un regard, en plein soleil comme de nuit.
                    MapPolyline(segment.line).stroke(DrivyTheme.routeHalo, lineWidth: 11)
                    MapPolyline(segment.line).stroke(DrivyTheme.route, lineWidth: 6)
                } else if let coordinate = segment.firstCoordinate {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.route).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            ForEach(observations) { observation in
                if let coordinate = coordinate(for: observation) {
                    Annotation(observation.body.text, coordinate: coordinate) {
                        observationMarker(observation)
                    }.annotationTitles(.hidden)
                }
            }
            if let last {
                Annotation("Dernière position enregistrée", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                    SchoolMapPositionMarker(course: heading, mapHeading: mapHeading)
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onAppear { updateRoute(); updateCourse(); if followsPosition { followPoint() } else if count > 0 { camera = .automatic } }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
            if camera.positionedByUser { followDistance = min(2500, max(180, context.camera.distance)) }
        }
        .onChange(of: camera.positionedByUser) { _, byUser in if byUser { followsPosition = false } }
        .onChange(of: followsPosition) { _, follows in if follows { followPoint() } }
        .onChange(of: contentKey) { _, _ in
            let hadPosition = last != nil
            updateRoute()
            updateCourse()
            if followsPosition && !camera.positionedByUser { followPoint() }
            else if !hadPosition && last != nil { camera = .automatic }
        }
        .onChange(of: resetCameraID) { _, _ in
            if followsPosition { followPoint() }
            else { camera = .automatic }
        }
        .accessibilityLabel("Carte du trajet enregistré")
        .accessibilityValue(followsPosition ? "Suivi dans le sens du trajet" : "Carte libre")
    }

    private func coordinate(for observation: SchoolLiveMapObservation) -> CLLocationCoordinate2D? {
        guard let segmentID = observation.body.segmentId, let sequence = observation.body.pointSequence,
              let point = selectedSamples[segmentID]?.first(where: { $0.point.sequence == sequence })?.point else { return nil }
        return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    private func observationMarker(_ observation: SchoolLiveMapObservation) -> some View {
        let status = observation.body.eventStatus.flatMap(SchoolObservationStatus.init(rawValue:))
        let color: Color = switch status {
        case .attention: DrivyTone.warning.foreground
        case .toWorkOn: DrivyTone.danger.foreground
        case .positive: DrivyTone.success.foreground
        case nil: DrivyTheme.text
        }
        return Image(systemName: status?.symbol ?? "bookmark.fill")
            .font(DrivyMapGlyph.compactObservation)
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(DrivyTheme.surface, in: Circle())
            .overlay(Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: observation.isPending ? [3, 2] : [])))
            .accessibilityLabel("\(observation.body.text), \(status?.label ?? "Repère")\(observation.isPending ? ", envoi en attente" : "")")
    }

    private func updateCourse() {
        heading = nil; last = nil
        guard let segment = segments.last(where: { selectedSamples[$0.id]?.isEmpty == false }),
              let samples = selectedSamples[segment.id] else { return }
        var course = SchoolMapCourse()
        for sample in samples {
            if sample.startsFragment { course = SchoolMapCourse() }
            let point = sample.point
            heading = course.receive(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                at: Double(point.elapsedMs) / 1000, accuracy: point.accuracyMeters)
            last = point
        }
    }

    private func updateRoute() {
        drawnSegments = segments.flatMap { segment -> [SchoolMapRouteFragment] in
            let prefix = segment.id.uuidString + ":"
            let previous = drawnSegments.filter { $0.id.hasPrefix(prefix) }
            if cachedCounts[segment.id] == segment.measurements.count { return previous }
            let samples = segment.displaySamples
            selectedSamples[segment.id] = samples
            cachedCounts[segment.id] = segment.measurements.count
            var fragments: [SchoolMapRouteFragment] = []
            var coordinates: [CLLocationCoordinate2D] = []
            for sample in samples {
                let point = sample.point
                if sample.startsFragment && !coordinates.isEmpty {
                    fragments.append(.init(id: "\(prefix)\(fragments.count)", coordinates: coordinates))
                    coordinates = []
                }
                coordinates.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            if !coordinates.isEmpty { fragments.append(.init(id: "\(prefix)\(fragments.count)", coordinates: coordinates)) }
            return fragments
        }
    }

    private func followPoint() {
        guard let last else { return }
        withAnimation(reduceMotion ? nil : .linear(duration: 0.35)) {
            camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                distance: followDistance, heading: heading ?? mapHeading, pitch: 0))
        }
    }
}
