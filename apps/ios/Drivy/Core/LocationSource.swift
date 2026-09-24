import CoreLocation
import Foundation

enum LocationPermission: Equatable, Sendable {
    case notDetermined, allowed, denied
}

struct LocationSample: Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
}

enum LocationEvent: Sendable {
    case permission(LocationPermission)
    case samples([LocationSample])
    case unavailable
}

@MainActor
protocol LocationSource: AnyObject {
    var permission: LocationPermission { get }
    var onEvent: (@MainActor (LocationEvent) -> Void)? { get set }
    func requestPermission()
    func start()
    func stop()
}

// Le gestionnaire est créé sur la boucle principale, utilisée par ses callbacks.
// Cette conformité conserve cette isolation documentée à l’exécution.
@MainActor
final class NativeLocationSource: NSObject, LocationSource, @preconcurrency CLLocationManagerDelegate {
    var onEvent: (@MainActor (LocationEvent) -> Void)?
    private var manager: CLLocationManager?
    private let permissionManager = CLLocationManager()

    override init() {
        super.init()
        permissionManager.delegate = self
    }

    var permission: LocationPermission { Self.permission(permissionManager.authorizationStatus) }

    func requestPermission() { permissionManager.requestWhenInUseAuthorization() }

    func start() {
        stop()
        guard permission == .allowed else { onEvent?(.permission(permission)); return }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        self.manager = manager
        manager.startUpdatingLocation()
    }

    func stop() {
        let previous = manager
        manager = nil
        previous?.stopUpdatingLocation()
        previous?.delegate = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === permissionManager || manager === self.manager else { return }
        onEvent?(.permission(Self.permission(manager.authorizationStatus)))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager else { return }
        let samples = locations.map {
            LocationSample(timestamp: $0.timestamp, latitude: $0.coordinate.latitude,
                           longitude: $0.coordinate.longitude, horizontalAccuracy: $0.horizontalAccuracy)
        }
        onEvent?(.samples(samples))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === self.manager else { return }
        onEvent?(.unavailable)
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        onEvent?(.unavailable)
    }

    private static func permission(_ status: CLAuthorizationStatus) -> LocationPermission {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}

// Seules les valeurs mesurées sont admises. Les segments séparent explicitement
// les périodes anciennes, imprécises, interrompues ou retardées dans la relecture.
struct LocationAdmission {
    private(set) var segmentID = UUID()
    private(set) var lastTimestamp: Date?
    private var hasGap = false
    let startedAt: Date

    init(startedAt: Date) { self.startedAt = startedAt }

    mutating func interrupt() { hasGap = true }

    mutating func admit(_ sample: LocationSample, receivedAt: Date) -> RecordedPoint? {
        let age = receivedAt.timeIntervalSince(sample.timestamp)
        guard sample.latitude.isFinite, sample.longitude.isFinite, sample.horizontalAccuracy.isFinite,
              (-90...90).contains(sample.latitude), (-180...180).contains(sample.longitude),
              (0...100).contains(sample.horizontalAccuracy), sample.timestamp >= startedAt,
              age >= -2, age <= 30 else {
            hasGap = true
            return nil
        }
        if let lastTimestamp, sample.timestamp <= lastTimestamp { return nil }
        if hasGap || lastTimestamp.map({ sample.timestamp.timeIntervalSince($0) > 15 }) == true {
            segmentID = UUID()
        }
        hasGap = false
        lastTimestamp = sample.timestamp
        return RecordedPoint(id: UUID(), timestamp: sample.timestamp, receivedAt: receivedAt,
            latitude: sample.latitude, longitude: sample.longitude, accuracy: sample.horizontalAccuracy,
            segmentID: segmentID)
    }
}
