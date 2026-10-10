import MapKit
import SwiftUI

/// Carte du trajet en cours : tracé mesuré, signalements ancrés et dernière position.
struct SchoolCaptureLiveMap: View {
    let segments: [SchoolCaptureMapSegment]
    let observations: [SchoolLiveMapObservation]
    let resetCameraID: UUID
    let isRecording: Bool
    /// Départ sans position enregistrée : la position de l’appareil selon Plans, affichée et jamais enregistrée.
    var showsDevicePosition = false
    @Binding var followMode: DrivyMapFollowMode
    @State private var camera: MapCameraPosition = .automatic
    @State private var mapHeading = 0.0
    @State private var followDistance = 650.0
    @State private var heading: Double?
    @State private var drawnSegments: [SchoolMapRouteFragment] = []
    @State private var drawnGaps: [SchoolMapRouteGap] = []
    @State private var gapsBySegment: [UUID: [SchoolMapRouteGap]] = [:]
    @State private var sourceBounds: [UUID: (first: SchoolCapturePoint, last: SchoolCapturePoint)] = [:]
    @State private var selectedSamples: [UUID: [SchoolCaptureDisplayRoute.Sample]] = [:]
    @State private var cachedCounts: [UUID: Int] = [:]
    @State private var last: SchoolCapturePoint?
    @State private var compass = SchoolLiveHeadingSource()
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var count: Int { segments.reduce(0) { $0 + $1.measurements.count } }
    private var contentKey: String { segments.map { "\($0.id):\($0.measurements.count)" }.joined(separator: ",") }
    private var compassIsActive: Bool { followMode == .heading && isVisible && isRecording && scenePhase == .active }
    private var displayedHeading: Double? { compass.degrees ?? heading }

    var body: some View {
        Map(position: $camera) {
            ForEach(drawnGaps) { gap in
                MapPolyline(gap.line).stroke(DrivyTheme.controlBorder,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 5]))
            }
            ForEach(drawnSegments) { segment in
                if segment.line.pointCount > 1 {
                    // Trait épais : lisible d’un regard, en plein soleil comme de nuit.
                    MapPolyline(segment.line).stroke(DrivyTheme.routeHalo,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                    MapPolyline(segment.line).stroke(DrivyTheme.route,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                } else if let coordinate = segment.firstCoordinate {
                    Annotation("Position enregistrée", coordinate: coordinate) {
                        Circle().fill(DrivyTheme.route).frame(width: 8, height: 8)
                    }.annotationTitles(.hidden)
                }
            }
            if let coordinate = drawnSegments.first?.firstCoordinate {
                Annotation("Début du tracé enregistré", coordinate: coordinate) {
                    SchoolMapEndpointMarker(kind: .start)
                }.annotationTitles(.hidden)
            }
            ForEach(observations) { observation in
                if let coordinate = coordinate(for: observation) {
                    Annotation(observation.body.text, coordinate: coordinate) {
                        observationMarker(observation)
                    }.annotationTitles(.hidden)
                }
            }
            if showsDevicePosition && last == nil { UserAnnotation() }
            if let last {
                Annotation("Dernière position enregistrée", coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)) {
                    SchoolMapPositionMarker(course: displayedHeading, mapHeading: mapHeading)
                        .accessibilityLabel(compass.degrees == nil
                            ? (heading == nil ? "Dernière position enregistrée" : "Dernière position et direction du déplacement")
                            : "Dernière position enregistrée et orientation de l’appareil")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .background(SchoolLiveHeadingWindowReader(source: compass).accessibilityHidden(true))
        .onAppear {
            isVisible = true
            updateRoute(); updateCourse()
            compass.setActive(compassIsActive)
            if last == nil && showsDevicePosition { camera = .userLocation(fallback: .automatic) }
            else if followMode.followsPosition { followPoint() } else if count > 0 { camera = .automatic }
        }
        .onDisappear { isVisible = false; compass.stop() }
        .onChange(of: compassIsActive) { _, active in compass.setActive(active) }
        .onChange(of: compass.degrees) { _, degrees in
            guard degrees != nil, followMode == .heading, !camera.positionedByUser else { return }
            followPoint()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
            if camera.positionedByUser { followDistance = min(2500, max(180, context.camera.distance)) }
        }
        .onChange(of: camera.positionedByUser) { _, byUser in if byUser { followMode = .free } }
        .onChange(of: followMode) { _, mode in if mode.followsPosition { followPoint() } }
        .onChange(of: contentKey) { _, _ in
            let hadPosition = last != nil
            updateRoute()
            updateCourse()
            if followMode.followsPosition && !camera.positionedByUser { followPoint() }
            else if !hadPosition && last != nil && !camera.positionedByUser { camera = .automatic }
        }
        .onChange(of: resetCameraID) { _, _ in
            if followMode.followsPosition { followPoint() }
            else { camera = .automatic }
        }
        .accessibilityLabel("Carte du trajet enregistré")
        .accessibilityValue((followMode == .heading && compass.degrees == nil
            ? "Suivi de position, orientation du téléphone indisponible" : followMode.label)
            + (drawnGaps.isEmpty ? "" : ", portions sans mesure indiquées en pointillé"))
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
        return SchoolMapObservationMarker(symbol: status?.symbol ?? "bookmark.fill", color: color, isPending: observation.isPending)
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
        let currentIDs = Set(segments.map(\.id))
        selectedSamples = selectedSamples.filter { currentIDs.contains($0.key) }
        cachedCounts = cachedCounts.filter { currentIDs.contains($0.key) }
        gapsBySegment = gapsBySegment.filter { currentIDs.contains($0.key) }
        sourceBounds = sourceBounds.filter { currentIDs.contains($0.key) }
        drawnSegments = segments.flatMap { segment -> [SchoolMapRouteFragment] in
            let prefix = segment.id.uuidString + ":"
            let previous = drawnSegments.filter { $0.id.hasPrefix(prefix) }
            if cachedCounts[segment.id] == segment.measurements.count { return previous }
            let samples = segment.displaySamples
            let source = segment.points
            selectedSamples[segment.id] = samples
            gapsBySegment[segment.id] = SchoolMapRouteGap.withinSegment(source, displayed: samples, idPrefix: prefix)
            if let first = source.first, let last = source.last { sourceBounds[segment.id] = (first, last) }
            else { sourceBounds.removeValue(forKey: segment.id) }
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
        drawnGaps = segments.flatMap { gapsBySegment[$0.id] ?? [] }
        for (previous, next) in zip(segments, segments.dropFirst()) {
            guard let previousSource = sourceBounds[previous.id]?.last, let nextSource = sourceBounds[next.id]?.first,
                  let previousDisplayed = selectedSamples[previous.id]?.last?.point,
                  let nextDisplayed = selectedSamples[next.id]?.first?.point,
                  let gap = SchoolMapRouteGap.betweenSegments(id: "between:\(previous.id):\(next.id)",
                    previousSource: previousSource, nextSource: nextSource,
                    previousDisplayed: previousDisplayed, nextDisplayed: nextDisplayed) else { continue }
            drawnGaps.append(gap)
        }
    }

    private func followPoint() {
        guard followMode.followsPosition, let last else { return }
        withAnimation(reduceMotion ? nil : .linear(duration: 0.35)) {
            camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                distance: followDistance, heading: followMode.cameraHeading(deviceHeading: compass.degrees) ?? mapHeading, pitch: 0))
        }
    }
}
