import Foundation

/// What the map draws at one instant. Display only: a pose is never stored, sent,
/// nor used to anchor an observation.
struct SchoolMapPose: Equatable {
    var latitude: Double
    var longitude: Double
    /// Direction of the arrow, degrees clockwise from north. Nil draws the plain dot.
    var heading: Double?
}

/// Glides the position marker from where it is drawn to the latest measured fix.
/// It always travels towards a real measurement and never past it: the marker is at
/// most one fix interval late, never ahead of the vehicle. A new fix restarts the
/// glide from the current drawn position, so no delay accumulates.
struct SchoolMapGlide {
    /// Beyond this, the marker is placed rather than dragged across the map.
    static let maximumGlideMeters = 250.0
    static let intervalRange = 0.2...1.6

    private var origin: (latitude: Double, longitude: Double)?
    private var target: (latitude: Double, longitude: Double)?
    private var startedAt: TimeInterval = 0
    private var duration: TimeInterval = 0
    private var lastTargetAt: TimeInterval?
    /// Smoothed time between fixes: the glide lasts a little longer, so the marker is
    /// still rolling when the next fix arrives instead of stopping at each one.
    private(set) var interval: TimeInterval = 1

    var hasTarget: Bool { target != nil }

    /// `instant` places the marker at once: first fix, new fragment, Reduce Motion.
    mutating func move(toLatitude latitude: Double, longitude: Double, at now: TimeInterval, instant: Bool = false) {
        let current = position(at: now)
        if let lastTargetAt, now > lastTargetAt {
            let observed = min(Self.intervalRange.upperBound, max(Self.intervalRange.lowerBound, now - lastTargetAt))
            interval += (observed - interval) * 0.3
        }
        lastTargetAt = now
        target = (latitude, longitude)
        guard !instant, let current,
              SchoolTrackGeometry.meters(latitude1: current.latitude, longitude1: current.longitude,
                                         latitude2: latitude, longitude2: longitude) <= Self.maximumGlideMeters else {
            origin = nil; duration = 0; startedAt = now
            return
        }
        origin = current
        startedAt = now
        duration = interval * 1.15
    }

    mutating func reset() {
        origin = nil; target = nil; lastTargetAt = nil; duration = 0; interval = 1
    }

    func position(at now: TimeInterval) -> (latitude: Double, longitude: Double)? {
        guard let target else { return nil }
        guard let origin, duration > 0 else { return target }
        let fraction = (now - startedAt) / duration
        if fraction >= 1 { return target }
        return SchoolTrackGeometry.interpolate(latitude1: origin.latitude, longitude1: origin.longitude,
            latitude2: target.latitude, longitude2: target.longitude, fraction: fraction)
    }

    /// Nothing moves any more until the next fix: the frame clock may rest.
    func isSettled(at now: TimeInterval) -> Bool {
        guard target != nil else { return true }
        return origin == nil || duration <= 0 || now - startedAt >= duration
    }
}

/// Turns towards a target heading along the shortest arc, at a pace independent of
/// the frame rate. 359° to 1° is a 2° turn, never a full spin.
struct SchoolMapHeadingSmoother {
    /// Time to cover about two thirds of a turn.
    var timeConstant: TimeInterval
    private(set) var value: Double?
    private var updatedAt: TimeInterval?

    init(timeConstant: TimeInterval = 0.28) { self.timeConstant = timeConstant }

    mutating func reset() { value = nil; updatedAt = nil }

    mutating func advance(towards target: Double?, at now: TimeInterval, instant: Bool = false) -> Double? {
        defer { updatedAt = now }
        guard let target, target.isFinite else { value = nil; return nil }
        guard let current = value, let updatedAt, !instant, timeConstant > 0 else {
            value = SchoolTrackGeometry.normalizedHeading(target)
            return value
        }
        let delta = SchoolTrackGeometry.angleDelta(from: current, to: target)
        let step = 1 - exp(-max(0, now - updatedAt) / timeConstant)
        value = SchoolTrackGeometry.normalizedHeading(current + delta * step)
        return value
    }

    func isSettled(on target: Double?) -> Bool {
        guard let target, let value else { return true }
        return abs(SchoolTrackGeometry.angleDelta(from: value, to: target)) < 0.3
    }
}

/// A camera move that eases from where the camera is to where the follow mode wants
/// it (recentring, first fix). While it runs the target keeps moving: the blend
/// converges on the live target instead of chasing a stale one.
struct SchoolMapCameraBlend {
    let startedAt: TimeInterval
    let duration: TimeInterval

    /// 0 at the start, 1 once the camera has joined its target.
    func progress(at now: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(1, max(0, (now - startedAt) / duration))
        return t * t * (3 - 2 * t)
    }
}
