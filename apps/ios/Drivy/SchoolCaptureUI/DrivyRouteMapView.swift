import MapKit
import SwiftUI
import UIKit

/// One polyline of the map. Same `id` and `revision`: the overlay already drawn is kept,
/// so a new GPS fix never rebuilds the whole route.
struct DrivyRouteMapLine: Identifiable {
    enum Style { case route, gap }
    let id: String
    let revision: Int
    let style: Style
    let coordinates: [CLLocationCoordinate2D]
}

/// A fixed marker (start, end, observation). Its SwiftUI content is the shared marker grammar.
struct DrivyRouteMapPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    /// Changes whenever the drawn content must be rebuilt.
    let signature: String
    let label: String
    var isSelected = false
    var isSelectable = false
    var side: CGFloat = 44
    var priority: Float = 500
    let content: AnyView
}

/// Supplies the moving part of the map, one frame at a time. Nothing it returns is a
/// measurement: it is the display position between measured fixes.
@MainActor protocol DrivyRouteMapMotion: AnyObject {
    /// Pose of the position marker for this frame; nil hides it.
    func pose(at now: TimeInterval) -> SchoolMapPose?
    /// Heading the camera takes while it follows; nil keeps the current one.
    func cameraHeading(at now: TimeInterval) -> Double?
    /// False once nothing moves until new data arrives: the frame clock rests.
    func isAnimating(at now: TimeInterval) -> Bool
    var positionLabel: String { get }
    /// Set by the map: call it when new data must be drawn.
    var wake: (() -> Void)? { get set }
}

/// Map shared by the live lesson and the replay. MapKit draws; a display link moves the
/// marker and the camera every frame without going through SwiftUI, and overlays are
/// added or replaced one by one instead of rebuilding the map.
struct DrivyRouteMapView: UIViewRepresentable {
    let lines: [DrivyRouteMapLine]
    let pins: [DrivyRouteMapPin]
    let motion: any DrivyRouteMapMotion
    let isFollowing: Bool
    /// A new value recentres: on the marker when following, on the whole route otherwise.
    let cameraRequest: UUID
    /// Before any recorded fix: the device position as Plans shows it, never recorded.
    var showsDevicePosition = false
    /// The camera joins the first drawn position once, unless the user already moved the map.
    var centersOnFirstPose = false
    var onUserMovedMap: () -> Void = {}
    var onSelectPin: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> DrivyMapCanvas {
        let map = DrivyMapCanvas(frame: .zero)
        context.coordinator.attach(map)
        return map
    }

    func updateUIView(_ map: DrivyMapCanvas, context: Context) {
        context.coordinator.update(self, reduceMotion: context.environment.accessibilityReduceMotion)
    }

    static func dismantleUIView(_ map: DrivyMapCanvas, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        private struct DrawnLine {
            let revision: Int
            let style: DrivyRouteMapLine.Style
            let overlays: [DrivyRoutePolyline]
            let dot: DrivyPinAnnotation?
            let bounds: MKMapRect
        }
        private struct CameraState {
            var latitude: Double, longitude: Double, heading: Double, distance: Double
        }

        private weak var map: DrivyMapCanvas?
        private var link: CADisplayLink?
        private var linkProxy: DisplayLinkProxy?
        private var motion: (any DrivyRouteMapMotion)?
        private var drawnLines: [String: DrawnLine] = [:]
        private var drawnPins: [String: DrivyPinAnnotation] = [:]
        private let position = DrivyPositionAnnotation()
        private var positionShown = false
        private var isFollowing = false
        private var cameraRequest: UUID?
        private var showsDevicePosition = false
        private var centersOnFirstPose = false
        private var reduceMotion = false
        private var onUserMovedMap: () -> Void = {}
        private var onSelectPin: (String) -> Void = { _ in }
        private var followDistance = 650.0
        private var blend: SchoolMapCameraBlend?
        private var blendOrigin: CameraState?
        private var applied: CameraState?
        private var isApplyingCamera = false
        private var hasInitialCamera = false
        private var userMovedMap = false
        private var lastGestureAt: TimeInterval = -.infinity
        private var activeGestures = 0
        private var hadPose = false
        private var showedPose = false

        // MARK: Lifecycle

        func attach(_ map: DrivyMapCanvas) {
            self.map = map
            map.delegate = self
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            configuration.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = configuration
            map.showsCompass = false
            map.showsScale = false
            map.isPitchEnabled = false
            map.register(DrivyPositionAnnotationView.self, forAnnotationViewWithReuseIdentifier: DrivyPositionAnnotationView.reuseID)
            map.register(DrivyPinAnnotationView.self, forAnnotationViewWithReuseIdentifier: DrivyPinAnnotationView.reuseID)
            // Own recognizers, simultaneous with MapKit's: a finger on the map is known
            // without relying on MapKit internals.
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            doubleTap.numberOfTapsRequired = 2
            let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            twoFingerTap.numberOfTouchesRequired = 2
            let recognizers: [UIGestureRecognizer] = [
                UIPanGestureRecognizer(target: self, action: #selector(userGesture(_:))),
                UIPinchGestureRecognizer(target: self, action: #selector(userGesture(_:))),
                UIRotationGestureRecognizer(target: self, action: #selector(userGesture(_:))),
                doubleTap, twoFingerTap
            ]
            for recognizer in recognizers {
                recognizer.delegate = self
                recognizer.cancelsTouchesInView = false
                recognizer.delaysTouchesEnded = false
                map.addGestureRecognizer(recognizer)
            }
            map.onLayout = { [weak self] in self?.placeInitialCamera() }
            map.onWindowChange = { [weak self] visible in
                if visible { self?.wake() } else { self?.link?.isPaused = true }
            }
            _ = map.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: DrivyMapCanvas, _: UITraitCollection) in
                self?.restyleOverlays()
            }
            let proxy = DisplayLinkProxy()
            proxy.owner = self
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link; linkProxy = proxy
        }

        func detach() {
            link?.invalidate(); link = nil; linkProxy = nil
            motion?.wake = nil; motion = nil
            map?.delegate = nil
        }

        func update(_ view: DrivyRouteMapView, reduceMotion: Bool) {
            guard let map else { return }
            if motion !== view.motion {
                motion?.wake = nil
                motion = view.motion
                view.motion.wake = { [weak self] in self?.wake() }
            }
            self.reduceMotion = reduceMotion
            onUserMovedMap = view.onUserMovedMap
            onSelectPin = view.onSelectPin
            centersOnFirstPose = view.centersOnFirstPose
            sync(lines: view.lines, on: map)
            sync(pins: view.pins, on: map)
            if showsDevicePosition != view.showsDevicePosition {
                showsDevicePosition = view.showsDevicePosition
                map.showsUserLocation = showsDevicePosition
                if !showsDevicePosition, map.userTrackingMode != .none { map.setUserTrackingMode(.none, animated: false) }
            }
            let startsFollowing = view.isFollowing && !isFollowing
            isFollowing = view.isFollowing
            let requested = cameraRequest != nil && cameraRequest != view.cameraRequest
            cameraRequest = view.cameraRequest
            if hasInitialCamera {
                if isFollowing, startsFollowing || requested { startBlend() }
                else if requested, !isFollowing { fitRoute(animated: !reduceMotion) }
            }
            placeInitialCamera()
            wake()
        }

        private func wake() {
            guard map?.window != nil else { return }
            link?.isPaused = false
        }

        // MARK: Frame

        fileprivate func frame(_ link: CADisplayLink) {
            guard let map, let motion else { link.isPaused = true; return }
            let now = link.targetTimestamp
            let pose = motion.pose(at: now)
            drawPosition(pose, on: map)
            if let pose {
                if isFollowing {
                    // The position appears (first fix, end of a gap): the camera joins it, it does not jump there.
                    if !showedPose, hasInitialCamera { startBlend() }
                    follow(pose, on: map, at: now)
                } else if centersOnFirstPose, !hadPose, hasInitialCamera, !userMovedMap {
                    // First recorded fix: the camera glides from the device position to it, once.
                    if map.userTrackingMode != .none { map.setUserTrackingMode(.none, animated: false) }
                    let camera = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: pose.latitude, longitude: pose.longitude),
                        fromDistance: followDistance, pitch: 0, heading: map.camera.heading)
                    map.setCamera(camera, animated: !reduceMotion)
                }
                hadPose = true
            }
            showedPose = pose != nil
            if !motion.isAnimating(at: now), blend == nil { link.isPaused = true }
        }

        private func drawPosition(_ pose: SchoolMapPose?, on map: DrivyMapCanvas) {
            guard let pose else {
                if positionShown { map.removeAnnotation(position); positionShown = false }
                return
            }
            let coordinate = CLLocationCoordinate2D(latitude: pose.latitude, longitude: pose.longitude)
            if position.coordinate.latitude != coordinate.latitude || position.coordinate.longitude != coordinate.longitude {
                position.coordinate = coordinate
            }
            position.heading = pose.heading
            if !positionShown { map.addAnnotation(position); positionShown = true }
            orientPosition(on: map)
        }

        /// The arrow keeps pointing along the movement whatever the map rotation.
        private func orientPosition(on map: DrivyMapCanvas) {
            guard positionShown, let view = map.view(for: position) as? DrivyPositionAnnotationView else { return }
            view.show(heading: position.heading, mapHeading: map.camera.heading, label: motion?.positionLabel)
        }

        private func follow(_ pose: SchoolMapPose, on map: DrivyMapCanvas, at now: TimeInterval) {
            guard hasInitialCamera, activeGestures == 0 else { return }
            if map.userTrackingMode != .none { map.setUserTrackingMode(.none, animated: false) }
            var target = CameraState(latitude: pose.latitude, longitude: pose.longitude,
                heading: motion?.cameraHeading(at: now) ?? map.camera.heading, distance: followDistance)
            if let blend, let origin = blendOrigin {
                let progress = blend.progress(at: now)
                if progress >= 1 {
                    self.blend = nil; blendOrigin = nil
                } else {
                    let place = SchoolTrackGeometry.interpolate(latitude1: origin.latitude, longitude1: origin.longitude,
                        latitude2: target.latitude, longitude2: target.longitude, fraction: progress)
                    target.latitude = place.latitude; target.longitude = place.longitude
                    target.heading = SchoolTrackGeometry.normalizedHeading(origin.heading
                        + SchoolTrackGeometry.angleDelta(from: origin.heading, to: target.heading) * progress)
                    // Zoom is perceived on a logarithmic scale.
                    target.distance = origin.distance * pow(target.distance / origin.distance, progress)
                }
            }
            apply(target, on: map)
        }

        private func apply(_ state: CameraState, on map: DrivyMapCanvas) {
            if let applied, abs(applied.latitude - state.latitude) < 1e-8, abs(applied.longitude - state.longitude) < 1e-8,
               abs(SchoolTrackGeometry.angleDelta(from: applied.heading, to: state.heading)) < 0.02,
               abs(applied.distance - state.distance) < 0.05 { return }
            let camera = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: state.latitude, longitude: state.longitude),
                fromDistance: state.distance, pitch: 0, heading: state.heading)
            isApplyingCamera = true
            map.setCamera(camera, animated: false)
            isApplyingCamera = false
            applied = state
        }

        private func startBlend() {
            guard let map else { return }
            applied = nil
            // No finger is on the map when the camera is sent back to the position.
            activeGestures = 0
            guard !reduceMotion else { blend = nil; blendOrigin = nil; return }
            let camera = map.camera
            blendOrigin = CameraState(latitude: camera.centerCoordinate.latitude, longitude: camera.centerCoordinate.longitude,
                heading: camera.heading, distance: max(1, camera.centerCoordinateDistance))
            blend = SchoolMapCameraBlend(startedAt: CACurrentMediaTime(), duration: 0.6)
        }

        // MARK: Camera placement

        /// Once, as soon as the map has a size: a camera set on an empty view is lost.
        private func placeInitialCamera() {
            guard !hasInitialCamera, let map, let motion, map.bounds.width > 0, map.bounds.height > 0 else { return }
            let pose = motion.pose(at: CACurrentMediaTime())
            if pose == nil, drawnLines.isEmpty {
                guard showsDevicePosition else { return }
                map.setUserTrackingMode(.follow, animated: false)
            } else if isFollowing, let pose {
                apply(CameraState(latitude: pose.latitude, longitude: pose.longitude,
                    heading: motion.cameraHeading(at: CACurrentMediaTime()) ?? 0, distance: followDistance), on: map)
            } else {
                fitRoute(animated: false)
            }
            hasInitialCamera = true
        }

        /// Whole route on screen; a single point still gets a street-level frame.
        private func fitRoute(animated: Bool) {
            guard let map else { return }
            var rect = MKMapRect.null
            for line in drawnLines.values where line.style == .route { rect = rect.union(line.bounds) }
            if rect.isNull, positionShown {
                rect = MKMapRect(origin: MKMapPoint(position.coordinate), size: MKMapSize(width: 0, height: 0))
            }
            guard !rect.isNull else { return }
            let center = MKMapPoint(x: rect.midX, y: rect.midY)
            let minimumSpan = MKMapPointsPerMeterAtLatitude(center.coordinate.latitude) * 160
            let width = max(rect.width, minimumSpan) * 1.2, height = max(rect.height, minimumSpan) * 1.2
            if map.userTrackingMode != .none { map.setUserTrackingMode(.none, animated: false) }
            applied = nil
            map.setVisibleMapRect(MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height),
                                  animated: animated)
        }

        // MARK: Overlays and pins

        private func sync(lines: [DrivyRouteMapLine], on map: DrivyMapCanvas) {
            var kept = Set<String>()
            kept.reserveCapacity(lines.count)
            for line in lines {
                kept.insert(line.id)
                if let drawn = drawnLines[line.id] {
                    if drawn.revision == line.revision { continue }
                    remove(drawn, from: map)
                }
                drawnLines[line.id] = drawLine(line, on: map)
            }
            for (id, drawn) in drawnLines where !kept.contains(id) {
                remove(drawn, from: map)
                drawnLines.removeValue(forKey: id)
            }
        }

        private func drawLine(_ line: DrivyRouteMapLine, on map: DrivyMapCanvas) -> DrawnLine {
            var bounds = MKMapRect.null
            for coordinate in line.coordinates {
                bounds = bounds.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
            }
            guard line.coordinates.count > 1 else {
                // A lone measured fix is still shown: a dot, never a line to somewhere else.
                var dot: DrivyPinAnnotation?
                if line.style == .route, let coordinate = line.coordinates.first {
                    let annotation = DrivyPinAnnotation(pin: DrivyRouteMapPin(id: "dot:\(line.id)", coordinate: coordinate,
                        signature: "dot", label: "Position enregistrée", side: 12, priority: 100,
                        content: AnyView(Circle().fill(DrivyTheme.route).frame(width: 8, height: 8))))
                    map.addAnnotation(annotation)
                    dot = annotation
                }
                return DrawnLine(revision: line.revision, style: line.style, overlays: [], dot: dot, bounds: bounds)
            }
            var overlays: [DrivyRoutePolyline] = []
            switch line.style {
            case .gap:
                let gap = DrivyRoutePolyline(coordinates: line.coordinates, count: line.coordinates.count)
                gap.role = .gap
                // Dashed connectors stay under every drawn route.
                if let lowest = map.overlays.first { map.insertOverlay(gap, below: lowest) } else { map.addOverlay(gap, level: .aboveRoads) }
                overlays = [gap]
            case .route:
                let halo = DrivyRoutePolyline(coordinates: line.coordinates, count: line.coordinates.count)
                halo.role = .halo
                let route = DrivyRoutePolyline(coordinates: line.coordinates, count: line.coordinates.count)
                route.role = .route
                // Every halo below every blue line: two chunks of one trace join without a notch.
                if let lowestRoute = map.overlays.first(where: { ($0 as? DrivyRoutePolyline)?.role == .route }) {
                    map.insertOverlay(halo, below: lowestRoute)
                } else {
                    map.addOverlay(halo, level: .aboveRoads)
                }
                map.addOverlay(route, level: .aboveRoads)
                overlays = [halo, route]
            }
            return DrawnLine(revision: line.revision, style: line.style, overlays: overlays, dot: nil, bounds: bounds)
        }

        private func remove(_ drawn: DrawnLine, from map: DrivyMapCanvas) {
            if !drawn.overlays.isEmpty { map.removeOverlays(drawn.overlays) }
            if let dot = drawn.dot { map.removeAnnotation(dot) }
        }

        private func sync(pins: [DrivyRouteMapPin], on map: DrivyMapCanvas) {
            var kept = Set<String>()
            kept.reserveCapacity(pins.count)
            for pin in pins {
                kept.insert(pin.id)
                if let annotation = drawnPins[pin.id] {
                    let changed = annotation.pin.signature != pin.signature || annotation.pin.isSelected != pin.isSelected
                        || annotation.pin.label != pin.label
                    if annotation.coordinate.latitude != pin.coordinate.latitude || annotation.coordinate.longitude != pin.coordinate.longitude {
                        annotation.coordinate = pin.coordinate
                    }
                    annotation.pin = pin
                    if changed { (map.view(for: annotation) as? DrivyPinAnnotationView)?.show(pin) }
                } else {
                    let annotation = DrivyPinAnnotation(pin: pin)
                    drawnPins[pin.id] = annotation
                    map.addAnnotation(annotation)
                }
            }
            for (id, annotation) in drawnPins where !kept.contains(id) {
                map.removeAnnotation(annotation)
                drawnPins.removeValue(forKey: id)
            }
        }

        private func restyleOverlays() {
            guard let map else { return }
            for overlay in map.overlays {
                guard let line = overlay as? DrivyRoutePolyline, let renderer = map.renderer(for: line) as? MKPolylineRenderer else { continue }
                renderer.strokeColor = line.role.color.resolvedColor(with: map.traitCollection)
                renderer.setNeedsDisplay()
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? DrivyRoutePolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = line.role.color.resolvedColor(with: mapView.traitCollection)
            renderer.lineWidth = line.role.width
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if line.role == .gap { renderer.lineDashPattern = [5, 5] }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation === position {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: DrivyPositionAnnotationView.reuseID, for: annotation)
                (view as? DrivyPositionAnnotationView)?.show(heading: position.heading, mapHeading: mapView.camera.heading,
                                                             label: motion?.positionLabel)
                return view
            }
            if let pin = annotation as? DrivyPinAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: DrivyPinAnnotationView.reuseID, for: annotation)
                (view as? DrivyPinAnnotationView)?.show(pin.pin)
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            mapView.deselectAnnotation(annotation, animated: false)
            guard let pin = annotation as? DrivyPinAnnotation, pin.pin.isSelectable else { return }
            onSelectPin(pin.pin.id)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard let map = mapView as? DrivyMapCanvas else { return }
            orientPosition(on: map)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isApplyingCamera else { return }
            // The zoom chosen by hand is the one the follow mode takes back.
            if CACurrentMediaTime() - lastGestureAt < 1.5 {
                followDistance = min(2500, max(180, mapView.camera.centerCoordinateDistance))
            }
        }

        // MARK: Gestures

        @objc private func userGesture(_ recognizer: UIGestureRecognizer) {
            lastGestureAt = CACurrentMediaTime()
            switch recognizer.state {
            case .began:
                activeGestures += 1
                userMoved()
            case .ended:
                // A tap ends without ever beginning.
                if recognizer is UITapGestureRecognizer { userMoved() } else { activeGestures = max(0, activeGestures - 1) }
            case .cancelled, .failed:
                if !(recognizer is UITapGestureRecognizer) { activeGestures = max(0, activeGestures - 1) }
            default: break
            }
        }

        private func userMoved() {
            userMovedMap = true
            blend = nil; blendOrigin = nil; applied = nil
            if isFollowing { isFollowing = false; onUserMovedMap() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

/// MKMapView that reports its first layout and its window: the camera and the frame
/// clock depend on both.
final class DrivyMapCanvas: MKMapView {
    var onLayout: (() -> Void)?
    var onWindowChange: ((Bool) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
}

/// The display link retains its target: this proxy keeps the coordinator free to go.
@MainActor private final class DisplayLinkProxy: NSObject {
    weak var owner: DrivyRouteMapView.Coordinator?
    @objc func tick(_ link: CADisplayLink) { owner?.frame(link) }
}

final class DrivyRoutePolyline: MKPolyline {
    enum Role {
        case route, halo, gap
        var color: UIColor {
            switch self {
            case .route: UIColor(DrivyTheme.route)
            case .halo: UIColor(DrivyTheme.routeHalo)
            case .gap: UIColor(DrivyTheme.controlBorder)
            }
        }
        var width: CGFloat {
            switch self { case .route: 6; case .halo: 11; case .gap: 3 }
        }
    }
    var role: Role = .route
}

final class DrivyPositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    var heading: Double?
}

final class DrivyPinAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var pin: DrivyRouteMapPin

    init(pin: DrivyRouteMapPin) {
        self.pin = pin
        coordinate = pin.coordinate
    }
}

/// Position marker: an arrow along the movement, or the plain dot without a trustworthy
/// direction. UIKit layers only, because it is repositioned and rotated every frame.
final class DrivyPositionAnnotationView: MKAnnotationView {
    static let reuseID = "drivy-position"
    private let arrow = UIImageView()
    private let dot = UIView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
        layer.cornerRadius = 17
        layer.borderWidth = 2
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        arrow.image = UIImage(systemName: "location.north.fill",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold))
        arrow.contentMode = .center
        arrow.frame = bounds
        arrow.tintColor = UIColor(DrivyTheme.route)
        dot.frame = CGRect(x: 9.5, y: 9.5, width: 15, height: 15)
        dot.layer.cornerRadius = 7.5
        dot.backgroundColor = UIColor(DrivyTheme.route)
        addSubview(arrow)
        addSubview(dot)
        displayPriority = .required
        zPriority = .max
        canShowCallout = false
        isAccessibilityElement = true
        applyColors()
        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: DrivyPositionAnnotationView, _: UITraitCollection) in
            view.applyColors()
        }
    }

    private func applyColors() {
        backgroundColor = UIColor(DrivyTheme.surface)
        layer.borderColor = UIColor(DrivyTheme.routeHalo).resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor(DrivyTheme.shadow).resolvedColor(with: traitCollection).cgColor
    }

    func show(heading: Double?, mapHeading: Double, label: String?) {
        arrow.isHidden = heading == nil
        dot.isHidden = heading != nil
        if let heading {
            arrow.transform = CGAffineTransform(rotationAngle: (heading - mapHeading) * .pi / 180)
        }
        if let label, accessibilityLabel != label { accessibilityLabel = label }
    }
}

/// Fixed marker drawn with the shared SwiftUI marker views. MapKit handles the tap.
final class DrivyPinAnnotationView: MKAnnotationView {
    static let reuseID = "drivy-pin"
    private var host: UIHostingController<AnyView>?

    func show(_ pin: DrivyRouteMapPin) {
        bounds = CGRect(x: 0, y: 0, width: pin.side, height: pin.side)
        if let host {
            host.rootView = pin.content
        } else {
            let controller = UIHostingController(rootView: pin.content)
            controller.view.backgroundColor = .clear
            controller.view.isUserInteractionEnabled = false
            controller.safeAreaRegions = []
            addSubview(controller.view)
            host = controller
        }
        host?.view.frame = bounds
        canShowCallout = false
        displayPriority = .required
        zPriority = MKAnnotationViewZPriority(rawValue: pin.priority)
        isEnabled = pin.isSelectable
        isAccessibilityElement = true
        accessibilityLabel = pin.label
        var traits: UIAccessibilityTraits = pin.isSelectable ? .button : .image
        if pin.isSelected { traits.insert(.selected) }
        accessibilityTraits = traits
    }
}
