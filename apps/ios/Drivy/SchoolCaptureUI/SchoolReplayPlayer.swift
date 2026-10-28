import Foundation
import Observation
import QuartzCore

/// Clock of a replay. The exact instant is derived from one time base whenever a frame
/// asks for it, so the map moves at the display rate; the observed `offset` is published
/// a few times per second only, which is all the timeline thumb and the clock need.
@MainActor @Observable
final class SchoolReplayPlayer: DrivyRouteMapMotion {
    /// Vitesses du replay, dans l’ordre du bouton : vitesse réelle, puis ×2, ×5 et ×10.
    static let speeds = [1, 2, 5, 10]

    private(set) var offset: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var speed = 1

    @ObservationIgnored var wake: (() -> Void)?
    @ObservationIgnored var reduceMotion = false
    /// An observation was passed during playback.
    @ObservationIgnored var onCross: ((UUID) -> Void)?
    @ObservationIgnored private(set) var timeline: SchoolReplayTimeline?
    @ObservationIgnored private var base: TimeInterval = 0
    @ObservationIgnored private var startedAt: TimeInterval?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var arrow = SchoolMapHeadingSmoother()
    @ObservationIgnored private var cameraTurn = SchoolMapHeadingSmoother(timeConstant: 0.6)
    @ObservationIgnored private var routeHeading: Double?
    @ObservationIgnored private var cameraTarget: Double?
    @ObservationIgnored private var cameraAskedAt: TimeInterval = -.infinity
    /// After a seek the marker and the camera are placed, not swept across the route.
    @ObservationIgnored private var placesArrow = true
    @ObservationIgnored private var placesCamera = true
    /// A frame is owed even while paused: the timeline moved under the map.
    @ObservationIgnored private var owesFrame = true

    var positionLabel: String { routeHeading == nil ? "Position enregistrée" : "Position et direction du déplacement" }
    var duration: TimeInterval { timeline?.duration ?? 0 }

    /// Exact playback instant for a frame.
    func time(at now: TimeInterval) -> TimeInterval {
        guard let startedAt else { return base }
        return min(duration, max(0, base + max(0, now - startedAt) * Double(speed)))
    }

    func load(_ timeline: SchoolReplayTimeline) {
        let current = time(at: CACurrentMediaTime())
        self.timeline = timeline
        base = min(timeline.duration, current)
        if isPlaying { startedAt = CACurrentMediaTime() }
        offset = base
        owesFrame = true
        wake?()
    }

    func play() {
        guard !isPlaying, let timeline else { return }
        if base >= timeline.duration { base = 0; offset = 0; placesArrow = true; placesCamera = true }
        startedAt = CACurrentMediaTime()
        isPlaying = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                guard let self, self.isPlaying else { return }
                self.publish(at: CACurrentMediaTime())
            }
        }
        wake?()
    }

    func pause() {
        guard isPlaying else { return }
        base = time(at: CACurrentMediaTime())
        startedAt = nil
        isPlaying = false
        ticker?.cancel(); ticker = nil
        offset = base
    }

    func toggle() { if isPlaying { pause() } else { play() } }

    /// Geste de lecture d'une observation : l'instant et sa note restent stables jusqu'à « Lecture ».
    @discardableResult func selectObservation(_ item: SchoolReplayTimeline.Item) -> UUID {
        pause()
        if let value = item.offset { seek(to: value) }
        return item.id
    }

    /// The map shows the new instant on its very next frame, playing or not.
    func seek(to value: TimeInterval) {
        base = min(duration, max(0, value))
        if isPlaying { startedAt = CACurrentMediaTime() }
        offset = base
        placesArrow = true; placesCamera = true; owesFrame = true
        wake?()
    }

    func cycleSpeed() {
        let now = CACurrentMediaTime()
        base = time(at: now)
        if isPlaying { startedAt = now }
        let index = Self.speeds.firstIndex(of: speed) ?? 0
        speed = Self.speeds[(index + 1) % Self.speeds.count]
    }

    func publish(at now: TimeInterval) {
        guard isPlaying, let timeline else { return }
        let before = offset
        let after = time(at: now)
        offset = after
        if after > before, let crossed = timeline.lastTimedItem(after: before, upTo: after) { onCross?(crossed.id) }
        if after >= timeline.duration { pause() }
    }

    // MARK: DrivyRouteMapMotion

    func pose(at now: TimeInterval) -> SchoolMapPose? {
        guard let timeline else { return nil }
        owesFrame = false
        let instant = time(at: now)
        guard let place = reduceMotion ? timeline.steppedPosition(at: instant) : timeline.position(at: instant) else {
            routeHeading = nil
            cameraTarget = nil
            arrow.reset()
            placesArrow = true
            return nil
        }
        routeHeading = place.heading
        // The arrow keeps a steady pace whatever the speed: at ×10 a bend still reads as a turn,
        // not as a snap. The look-ahead already smooths what the line itself would make jerky.
        arrow.timeConstant = 0.22 / Double(speed).squareRoot()
        let heading = arrow.advance(towards: place.heading, at: now, instant: reduceMotion || placesArrow)
        placesArrow = false
        // The camera turns towards the road further ahead, more so when the replay runs faster.
        cameraTarget = timeline.heading(at: instant, lookAhead: Self.cameraLookAhead * Double(speed).squareRoot()) ?? place.heading
        return SchoolMapPose(latitude: place.latitude, longitude: place.longitude, heading: heading)
    }

    /// Metres ahead along the route that orient the camera at real speed.
    static let cameraLookAhead = 22.0

    func cameraHeading(at now: TimeInterval) -> Double? {
        cameraAskedAt = now
        guard let cameraTarget else { return nil }
        cameraTurn.timeConstant = max(0.3, 0.7 / Double(speed).squareRoot())
        let heading = cameraTurn.advance(towards: cameraTarget, at: now, instant: reduceMotion || placesCamera)
        placesCamera = false
        return heading
    }

    func isAnimating(at now: TimeInterval) -> Bool {
        if isPlaying || owesFrame { return true }
        if !arrow.isSettled(on: routeHeading) { return true }
        return now - cameraAskedAt < 0.25 && !cameraTurn.isSettled(on: cameraTarget)
    }
}
