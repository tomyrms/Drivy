import MapKit
import QuartzCore
import SwiftUI

/// Moving part of the live map: the marker glides to each recorded fix and turns
/// smoothly; the camera heading follows the chosen mode. Display only.
@MainActor final class SchoolLiveMapMotion: DrivyRouteMapMotion {
    var wake: (() -> Void)?
    var followMode: DrivyMapFollowMode = .free
    var reduceMotion = false
    /// Ephemeral compass value, never a route point.
    var deviceHeading: Double? { didSet { if deviceHeading != oldValue { wake?() } } }

    private var glide = SchoolMapGlide()
    private var arrow = SchoolMapHeadingSmoother()
    private var cameraTurn = SchoolMapHeadingSmoother(timeConstant: 0.35)
    private var course: Double?
    private var target: (segmentID: UUID, sequence: Int)?

    var positionLabel: String {
        if deviceHeading != nil { return "Dernière position enregistrée et orientation de l’appareil" }
        return course == nil ? "Dernière position enregistrée" : "Dernière position et direction du déplacement"
    }

    /// The latest recorded position. The same fix given twice changes nothing.
    func show(_ position: SchoolLiveTrace.Position?) {
        guard let position else {
            if target != nil { target = nil; course = nil; glide.reset(); arrow.reset(); wake?() }
            return
        }
        course = position.course
        if let target, target.segmentID == position.segmentID, target.sequence == position.point.sequence { return }
        // A new fragment is not a continuous movement: the marker is placed there, not dragged across the gap.
        let instant = reduceMotion || position.startsFragment || target?.segmentID != position.segmentID
        target = (position.segmentID, position.point.sequence)
        glide.move(toLatitude: position.point.latitude, longitude: position.point.longitude, at: CACurrentMediaTime(), instant: instant)
        wake?()
    }

    func pose(at now: TimeInterval) -> SchoolMapPose? {
        guard let place = glide.position(at: now) else { return nil }
        return SchoolMapPose(latitude: place.latitude, longitude: place.longitude,
                             heading: arrow.advance(towards: deviceHeading ?? course, at: now, instant: reduceMotion))
    }

    func cameraHeading(at now: TimeInterval) -> Double? {
        guard let wanted = followMode.cameraHeading(deviceHeading: deviceHeading) else { return nil }
        return cameraTurn.advance(towards: wanted, at: now, instant: reduceMotion)
    }

    func isAnimating(at now: TimeInterval) -> Bool {
        if !glide.isSettled(at: now) { return true }
        if glide.hasTarget, !arrow.isSettled(on: deviceHeading ?? course) { return true }
        if let wanted = followMode.cameraHeading(deviceHeading: deviceHeading), !cameraTurn.isSettled(on: wanted) { return true }
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
        .accessibilityValue((followMode == .heading && !compass.isAvailable
            ? "Suivi de position, orientation du téléphone indisponible" : followMode.label)
            + (trace.hasGaps ? ", portions sans mesure indiquées en pointillé" : ""))
    }

    private func synchronize() {
        trace.update(priorSegments + segments, liveFrom: priorSegments.count)
        motion.followMode = followMode
        motion.reduceMotion = reduceMotion
        motion.show(trace.position)
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
