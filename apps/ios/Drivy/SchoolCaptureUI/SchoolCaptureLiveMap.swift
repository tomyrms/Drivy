import MapKit
import QuartzCore
import SwiftUI

/// Moving part of the live map, drawn like a navigation app: between two fixes the marker keeps
/// rolling at the speed and course iOS measured, and every fix (not only the vertices kept for
/// the line) corrects it smoothly. While the car moves, the heading mode turns the map with the
/// course of the road; the compass, disturbed inside a car, only orients it when stopped.
/// Display only.
@MainActor final class SchoolLiveMapMotion: DrivyRouteMapMotion {
    var wake: (() -> Void)?
    var followMode: DrivyMapFollowMode = .free
    var reduceMotion = false
    /// Ephemeral compass value, never a route point.
    var deviceHeading: Double? { didSet { if deviceHeading != oldValue { wake?() } } }

    private var predictor = SchoolMapPredictor()
    private var arrow = SchoolMapHeadingSmoother()
    private var cameraTurn = SchoolMapHeadingSmoother(timeConstant: 0.5)
    /// Direction of the measured movement: Doppler course while rolling, else the line's.
    private var course: Double?
    private var moving = false
    private var target: (segmentID: UUID, elapsedMs: Int)?

    var positionLabel: String {
        if course != nil { return "Position et direction du déplacement" }
        if deviceHeading != nil { return "Position et orientation de l’appareil" }
        return "Position enregistrée"
    }

    /// The heading the arrow and the heading mode follow: the road while rolling, the compass when stopped.
    private var travelHeading: Double? { moving ? course : (deviceHeading ?? course) }

    /// The latest admitted fix. The same fix given twice changes nothing.
    func show(_ position: SchoolLiveTrace.Position?, fix: SchoolCaptureMeasurement?) {
        guard let position else {
            if target != nil { target = nil; course = nil; moving = false; predictor.reset(); arrow.reset(); wake?() }
            return
        }
        // The freshest fix of the live segment; the last drawn vertex when none is newer.
        let latest = fix.flatMap { $0.elapsedMs >= position.point.elapsedMs ? $0 : nil }
        let elapsedMs = latest?.elapsedMs ?? position.point.elapsedMs
        if let target, target.segmentID == position.segmentID, target.elapsedMs == elapsedMs { return }
        // A new fragment is not a continuous movement: the marker is placed there, not dragged across the gap.
        let instant = reduceMotion || target?.segmentID != position.segmentID
            || (position.startsFragment && position.point.elapsedMs == elapsedMs)
        target = (position.segmentID, elapsedMs)
        let speed = latest?.speedMetersPerSecond
        moving = (speed ?? 0) >= SchoolMapPredictor.movingSpeed
        course = moving ? (latest?.courseDegrees ?? position.course) : position.course
        let now = CACurrentMediaTime()
        // Age of the fix when it reaches the map (storage round trip): the prediction catches it up.
        let age = latest.flatMap { SchoolLesson.date($0.capturedAt) }.map { Date().timeIntervalSince($0) }
        predictor.receive(latitude: latest?.latitude ?? position.point.latitude,
                          longitude: latest?.longitude ?? position.point.longitude,
                          speed: reduceMotion ? nil : speed, course: latest?.courseDegrees,
                          at: now, measuredAt: age.flatMap { $0.isFinite && $0 >= 0 ? now - $0 : nil }, instant: instant)
        wake?()
    }

    func pose(at now: TimeInterval) -> SchoolMapPose? {
        guard let place = predictor.position(at: now) else { return nil }
        return SchoolMapPose(latitude: place.latitude, longitude: place.longitude,
                             heading: arrow.advance(towards: travelHeading, at: now, instant: reduceMotion))
    }

    func cameraHeading(at now: TimeInterval) -> Double? {
        guard let wanted = followMode.cameraHeading(deviceHeading: travelHeading) else { return nil }
        return cameraTurn.advance(towards: wanted, at: now, instant: reduceMotion)
    }

    func isAnimating(at now: TimeInterval) -> Bool {
        if !predictor.isSettled(at: now) { return true }
        if predictor.hasFix, !arrow.isSettled(on: travelHeading) { return true }
        if let wanted = followMode.cameraHeading(deviceHeading: travelHeading), !cameraTurn.isSettled(on: wanted) { return true }
        return false
    }
}

/// Carte du trajet en cours : tracé mesuré, signalements ancrés et dernière position.
struct SchoolCaptureLiveMap: View {
    let segments: [SchoolCaptureMapSegment]
    let observations: [SchoolLiveMapObservation]
    /// Trajets précédents de la même leçon (relance après interruption), dessinés avant `segments`.
    var priorSegments: [SchoolCaptureMapSegment] = []
    var priorObservations: [SchoolLivePriorObservation] = []
    let resetCameraID: UUID
    let isRecording: Bool
    /// Départ sans position enregistrée : la position de l’appareil selon Plans, affichée et jamais enregistrée.
    var showsDevicePosition = false
    @Binding var followMode: DrivyMapFollowMode
    @State private var trace = SchoolLiveTrace()
    @State private var motion = SchoolLiveMapMotion()
    @State private var compass = SchoolLiveHeadingSource()
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var compassIsActive: Bool { followMode == .heading && isVisible && isRecording && scenePhase == .active }

    var body: some View {
        // Idempotent: unchanged segments cost a comparison, a new fix only its own vertex.
        let _ = synchronize()
        DrivyRouteMapView(lines: trace.lines, pins: pins, motion: motion,
            isFollowing: followMode.followsPosition, cameraRequest: resetCameraID,
            showsDevicePosition: showsDevicePosition && trace.position == nil,
            centersOnFirstPose: true,
            onUserMovedMap: { followMode = .free })
        .ignoresSafeArea()
        .background(SchoolLiveHeadingWindowReader(source: compass).accessibilityHidden(true))
        .onAppear {
            isVisible = true
            compass.onChange = { [motion] degrees in motion.deviceHeading = degrees }
            compass.setActive(compassIsActive)
        }
        .onDisappear { isVisible = false; compass.stop() }
        .onChange(of: compassIsActive) { _, active in compass.setActive(active) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carte du trajet enregistré")
        .accessibilityValue(followMode.label + (trace.hasGaps ? ", portions sans mesure indiquées en pointillé" : ""))
    }

    private func synchronize() {
        trace.update(priorSegments + segments, liveFrom: priorSegments.count)
        motion.followMode = followMode
        motion.reduceMotion = reduceMotion
        motion.show(trace.position, fix: liveSegment?.liveFix)
    }

    /// Segment being recorded, whose freshest fix moves the marker.
    private var liveSegment: SchoolCaptureMapSegment? {
        guard let id = trace.position?.segmentID else { return nil }
        return segments.last { $0.id == id }
    }

    private var pins: [DrivyRouteMapPin] {
        var result: [DrivyRouteMapPin] = []
        if let start = trace.start {
            result.append(DrivyRouteMapPin(id: "start", coordinate: start, signature: "start",
                label: SchoolMapEndpointMarker.Kind.start.label, side: 22, priority: 200,
                content: AnyView(SchoolMapEndpointMarker(kind: .start))))
        }
        for observation in priorObservations {
            let status = observation.eventStatus.flatMap(SchoolObservationStatus.init(rawValue:))
            let glyph: DrivyObservationGlyph = observation.eventKind == "MARKER" ? .moment
                : SchoolObservationPictogram(themeKey: observation.themeKey, title: observation.text)?.glyph ?? status?.glyph ?? .note
            result.append(DrivyRouteMapPin(id: observation.id.uuidString,
                coordinate: CLLocationCoordinate2D(latitude: observation.latitude, longitude: observation.longitude),
                signature: "\(glyph.key):\(status?.rawValue ?? "-"):false",
                label: "\(observation.text), \(status?.label ?? "Repère")",
                side: 40, priority: 400,
                content: AnyView(SchoolMapObservationMarker(glyph: glyph, tone: status?.tone ?? .neutral, badge: status?.glyph,
                    isPending: false))))
        }
        for observation in observations {
            guard let segmentID = observation.body.segmentId, let sequence = observation.body.pointSequence,
                  let coordinate = trace.coordinate(segmentID: segmentID, sequence: sequence) else { continue }
            let status = observation.body.eventStatus.flatMap(SchoolObservationStatus.init(rawValue:))
            let glyph: DrivyObservationGlyph = observation.body.eventKind == "MARKER" ? .moment
                : SchoolObservationPictogram(themeKey: observation.body.themeKey, title: observation.body.text)?.glyph ?? status?.glyph ?? .note
            result.append(DrivyRouteMapPin(id: observation.id.uuidString, coordinate: coordinate,
                signature: "\(glyph.key):\(status?.rawValue ?? "-"):\(observation.isPending)",
                label: "\(observation.body.text), \(status?.label ?? "Repère")\(observation.isPending ? ", envoi en attente" : "")",
                side: 40, priority: 400,
                content: AnyView(SchoolMapObservationMarker(glyph: glyph, tone: status?.tone ?? .neutral, badge: status?.glyph,
                    isPending: observation.isPending))))
        }
        return result
    }
}
