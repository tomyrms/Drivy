import Foundation

/// Plane geometry on short distances, without allocation: the display filter and the
/// animation call it for every point and every frame.
enum SchoolTrackGeometry {
    static let earthRadiusMeters = 6_371_008.8

    /// Equirectangular distance. Its error stays far below GPS accuracy up to a few kilometres.
    static func meters(latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double) -> Double {
        let middle = (latitude1 + latitude2) / 2 * .pi / 180
        let x = longitudeDelta(from: longitude1, to: longitude2) * .pi / 180 * cos(middle)
        let y = (latitude2 - latitude1) * .pi / 180
        return (x * x + y * y).squareRoot() * earthRadiusMeters
    }

    /// Distance from a point to the segment joining two others.
    static func metersFromSegment(latitude: Double, longitude: Double, startLatitude: Double, startLongitude: Double,
                                  endLatitude: Double, endLongitude: Double) -> Double {
        let cosine = cos(startLatitude * .pi / 180)
        let scale = cosine == 0 ? 1 : cosine
        let ax = startLongitude * scale, bx = endLongitude * scale, px = longitude * scale
        let dx = bx - ax, dy = endLatitude - startLatitude, square = dx * dx + dy * dy
        let t = square > 0 ? min(1, max(0, ((px - ax) * dx + (latitude - startLatitude) * dy) / square)) : 0
        return meters(latitude1: latitude, longitude1: longitude,
                      latitude2: startLatitude + dy * t, longitude2: (ax + dx * t) / scale)
    }

    /// Initial bearing in degrees, 0 = north, clockwise, in [0, 360).
    static func bearing(latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double) -> Double {
        let phi1 = latitude1 * .pi / 180, phi2 = latitude2 * .pi / 180
        let lambda = (longitude2 - longitude1) * .pi / 180
        let y = sin(lambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(lambda)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Signed shortest rotation from one heading to another, in (-180, 180].
    static func angleDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 } else if delta <= -180 { delta += 360 }
        return delta
    }

    static func normalizedHeading(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    /// Shortest way across the antimeridian.
    static func longitudeDelta(from: Double, to: Double) -> Double {
        var delta = to - from
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        return delta
    }

    static func interpolate(latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double,
                            fraction: Double) -> (latitude: Double, longitude: Double) {
        let t = min(1, max(0, fraction))
        var longitude = longitude1 + longitudeDelta(from: longitude1, to: longitude2) * t
        if longitude > 180 { longitude -= 360 } else if longitude < -180 { longitude += 360 }
        return (latitude1 + (latitude2 - latitude1) * t, longitude)
    }
}
