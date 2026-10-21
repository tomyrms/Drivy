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

/// Live marker the way navigation apps draw it: between two fixes the vehicle keeps moving at
/// the speed and course iOS measured (dead reckoning), and each new fix corrects the drawn
/// position smoothly instead of teleporting it. The marker is therefore where the car most
/// likely is now, not where it was a second ago. Display only: a predicted pose is never
/// stored, sent, nor used as an anchor; the recorded line stays made of measured fixes.
struct SchoolMapPredictor {
    /// The prediction runs this long past the last fix, then waits: a lost signal does not send
    /// the marker down the road on its own.
    static let maximumExtrapolation: TimeInterval = 1.6
    /// Below this the vehicle is treated as stopped: GPS speed noise does not crawl the marker.
    static let movingSpeed = 0.6
    /// Beyond this correction the marker is placed, not dragged across the map.
    static let maximumCorrectionMeters = 80.0
    /// Time for a correction to fade to about a third.
    var correctionTimeConstant: TimeInterval = 0.45

    private var fix: (latitude: Double, longitude: Double, at: TimeInterval)?
    /// Metres per second eastward and northward.
    private var velocity: (east: Double, north: Double) = (0, 0)
    /// Optional route displacement of the current real fix. Never changes the fix or its clock.
    private var roadOffset: (east: Double, north: Double) = (0, 0)
    /// Drawn minus predicted when the last fix arrived, in metres; fades away.
    private var correction: (east: Double, north: Double, at: TimeInterval) = (0, 0, 0)
    private(set) var course: Double?

    var hasFix: Bool { fix != nil }

    /// `instant` places the marker on the fix: first fix, new fragment, Reduce Motion.
    /// `measuredAt` is when the fix was taken, on the same clock as `now`: the time spent in
    /// storage before the fix reaches the map is caught up by the prediction, not shown as lag.
    mutating func receive(latitude: Double, longitude: Double, speed: Double?, course: Double?, at now: TimeInterval,
                          measuredAt: TimeInterval? = nil, instant: Bool = false) {
        let drawn = position(at: now)
        let moving = (speed ?? 0) >= Self.movingSpeed
        if let course, course.isFinite, moving { self.course = SchoolTrackGeometry.normalizedHeading(course) }
        if let speed, let course, speed.isFinite, course.isFinite, moving {
            let radians = course * .pi / 180
            velocity = (speed * sin(radians), speed * cos(radians))
        } else {
            velocity = (0, 0)
        }
        let taken = min(now, max(now - Self.maximumExtrapolation, measuredAt ?? now))
        fix = (latitude, longitude, taken)
        roadOffset = (0, 0)
        correction = (0, 0, now)
        guard !instant, let drawn, let predicted = position(at: now) else { return }
        let offset = Self.offset(from: predicted, to: drawn)
        if (offset.east * offset.east + offset.north * offset.north).squareRoot() <= Self.maximumCorrectionMeters {
            correction = (offset.east, offset.north, now)
        }
    }

    /// Corrects the display towards a route position for the same fix, without resetting
    /// velocity, extrapolation time, or the real fix. Rejected offsets never teleport the marker.
    /// `instant` (Reduce Motion) places the marker on the road at once instead of gliding there.
    @discardableResult
    mutating func correctRoadPosition(latitude: Double, longitude: Double, at now: TimeInterval, instant: Bool = false) -> Bool {
        guard let fix, latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
              (-180...180).contains(longitude), let drawn = position(at: now) else { return false }
        let offset = Self.offset(from: (fix.latitude, fix.longitude), to: (latitude, longitude))
        guard hypot(offset.east, offset.north) <= 25 else { return false }
        roadOffset = offset
        if instant { correction = (0, 0, now) } else { preserveDrawnPosition(drawn, at: now) }
        return true
    }

    mutating func clearRoadCorrection(at now: TimeInterval, instant: Bool = false) {
        guard roadOffset.east != 0 || roadOffset.north != 0, let drawn = position(at: now) else { return }
        roadOffset = (0, 0)
        if instant { correction = (0, 0, now) } else { preserveDrawnPosition(drawn, at: now) }
    }

    private mutating func preserveDrawnPosition(_ drawn: (latitude: Double, longitude: Double), at now: TimeInterval) {
        correction = (0, 0, now)
        guard let predicted = position(at: now) else { return }
        let offset = Self.offset(from: predicted, to: drawn)
        correction = (offset.east, offset.north, now)
    }

    mutating func reset() {
        fix = nil; velocity = (0, 0); correction = (0, 0, 0); course = nil
        roadOffset = (0, 0)
    }

    func position(at now: TimeInterval) -> (latitude: Double, longitude: Double)? {
        guard let fix else { return nil }
        let ahead = min(Self.maximumExtrapolation, max(0, now - fix.at))
        let fade = correctionTimeConstant > 0 ? exp(-max(0, now - correction.at) / correctionTimeConstant) : 0
        let east = velocity.east * ahead + roadOffset.east + correction.east * fade
        let north = velocity.north * ahead + roadOffset.north + correction.north * fade
        return Self.move((fix.latitude, fix.longitude), east: east, north: north)
    }

    /// Nothing moves any more until the next fix: the frame clock may rest.
    func isSettled(at now: TimeInterval) -> Bool {
        guard let fix else { return true }
        let predicting = (velocity.east != 0 || velocity.north != 0) && now - fix.at < Self.maximumExtrapolation
        let residual = (correction.east * correction.east + correction.north * correction.north).squareRoot()
            * exp(-max(0, now - correction.at) / max(0.001, correctionTimeConstant))
        return !predicting && residual < 0.05
    }

    private static func offset(from origin: (latitude: Double, longitude: Double),
                               to point: (latitude: Double, longitude: Double)) -> (east: Double, north: Double) {
        let metresPerDegree = SchoolTrackGeometry.earthRadiusMeters * .pi / 180
        let east = SchoolTrackGeometry.longitudeDelta(from: origin.longitude, to: point.longitude)
            * metresPerDegree * cos(origin.latitude * .pi / 180)
        return (east, (point.latitude - origin.latitude) * metresPerDegree)
    }

    private static func move(_ origin: (latitude: Double, longitude: Double), east: Double,
                             north: Double) -> (latitude: Double, longitude: Double) {
        let metresPerDegree = SchoolTrackGeometry.earthRadiusMeters * .pi / 180
        let cosine = max(0.01, cos(origin.latitude * .pi / 180))
        var longitude = origin.longitude + east / (metresPerDegree * cosine)
        if longitude > 180 { longitude -= 360 } else if longitude < -180 { longitude += 360 }
        return (min(90, max(-90, origin.latitude + north / metresPerDegree)), longitude)
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
