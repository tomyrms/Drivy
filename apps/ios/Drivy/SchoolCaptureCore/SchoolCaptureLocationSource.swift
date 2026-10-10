import CoreLocation
import Darwin
import Foundation
import UIKit

@MainActor
protocol SchoolCaptureLocationProviding: AnyObject {
    var onEvent: (@MainActor (SchoolCaptureLocationEvent) -> Void)? { get set }
    var permission: SchoolCaptureLocationPermission { get }
    var isRunning: Bool { get }
    func requestPermission()
    func requestDiagnosticSample() throws
    /// Réveille le récepteur GPS pendant les vérifications du départ, sans rien lire ni conserver.
    func warmUp()
    /// Arrête ce réveil quand le départ n’aura pas lieu.
    func coolDown()
    func diagnosticSnapshot() throws -> SchoolCaptureDeviceSnapshot
    func diagnosticBody(operationID: UUID, networkAvailable: Bool) throws -> SchoolDeviceAssessmentBody
    func updateScope(_ scope: SchoolCommandScope?)
    func prepareSegment(authorization: SchoolCaptureAuthorization, lease: SchoolCaptureLease,
                        scope: SchoolCommandScope, clockReference: SchoolCaptureClockReference,
                        policy: SchoolCaptureLocationPolicy) throws -> SchoolCaptureLocationSegment
    func start(segment: SchoolCaptureLocationSegment, handle: SchoolCaptureSegmentHandle) throws
    @discardableResult func stop() -> SchoolCaptureLocationStop?
}

extension SchoolCaptureLocationProviding {
    func warmUp() {}
    func coolDown() {}
}

// Les managers sont construits sur la boucle principale et y livrent leur delegate.
// Aucun objet CLLocation/CLLocationManager n'est transféré à un acteur de stockage.
@MainActor
final class SchoolCaptureLocationSource: NSObject, SchoolCaptureLocationProviding, @preconcurrency CLLocationManagerDelegate {
    var onEvent: (@MainActor (SchoolCaptureLocationEvent) -> Void)? {
        didSet { if onEvent == nil && isRunning { _ = stop() } }
    }
    private let permissionManager = CLLocationManager()
    private var manager: CLLocationManager?
    /// Récepteur tenu éveillé entre le geste de départ et la première position du trajet.
    private var warmManager: CLLocationManager?
    private var warmTask: Task<Void, Never>?
    private var currentScope: SchoolCommandScope?
    private var preparedSegmentID: UUID?
    private var segment: SchoolCaptureLocationSegment?
    private var handle: SchoolCaptureSegmentHandle?
    private var stoppedBoundary: SchoolCaptureLocationStop?
    private var armedWallTime: Date?
    private var lastElapsedMs: Int?
    private var deadlineTask: Task<Void, Never>?
    private var gapTask: Task<Void, Never>?
    private var gapGeneration = UUID()
    private var lastStorageCheck: ContinuousClock.Instant?
    private var lastDiagnostic: (ageAtReceipt: TimeInterval, accuracy: Double, receivedAt: ContinuousClock.Instant)?
    private var diagnosticRequested = false
    private var startGate = SchoolCaptureLocationStartGate()
    private var startedBatteryMonitoring = false
    private(set) var discardedCallbackCount = 0

    override init() {
        super.init()
        permissionManager.delegate = self
        permissionManager.desiredAccuracy = kCLLocationAccuracyBest
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged),
            name: UIApplication.significantTimeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged),
            name: UIDevice.batteryStateDidChangeNotification, object: nil)
    }

    var permission: SchoolCaptureLocationPermission { Self.permission(permissionManager.authorizationStatus) }
    var isRunning: Bool { manager != nil && segment != nil && handle != nil }

    func requestPermission() {
        if permission == .notDetermined { permissionManager.requestWhenInUseAuthorization() }
    }

    // Un récepteur GPS endormi met plusieurs secondes à donner sa première position. Ce flux le tient éveillé
    // pendant les vérifications du départ : ses positions ne sont ni lues, ni conservées, ni envoyées, et seules
    // les mesures postérieures à l’ouverture du segment entrent dans le trajet. Il s’arrête à la première
    // position du trajet, à l’arrêt, au changement de portée, au passage en arrière-plan ou après trente secondes.
    func warmUp() {
        guard warmManager == nil, !isRunning, CLLocationManager.locationServicesEnabled(), permission.permitsLocation,
              UIApplication.shared.applicationState == .active else { return }
        let warm = CLLocationManager()
        warm.delegate = self
        warm.desiredAccuracy = kCLLocationAccuracyBest
        warm.activityType = .automotiveNavigation
        warm.startUpdatingLocation()
        warmManager = warm
        warmTask?.cancel()
        warmTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, !self.isRunning else { return }
            self.coolDown()
        }
    }

    func coolDown() {
        warmTask?.cancel(); warmTask = nil
        warmManager?.stopUpdatingLocation()
        warmManager?.delegate = nil
        warmManager = nil
    }

    // Diagnostic ponctuel explicite, mémoire seulement. Il ne crée ni point scolaire
    // ni séance vide et ne tourne jamais en parallèle d'un flux scolaire continu.
    func requestDiagnosticSample() throws {
        guard CLLocationManager.locationServicesEnabled() else { throw SchoolCaptureLocationFailure.servicesDisabled }
        guard permission.permitsLocation else { throw SchoolCaptureLocationFailure.permissionRequired }
        guard UIApplication.shared.applicationState == .active else { throw SchoolCaptureLocationFailure.foregroundRequired }
        if isRunning { onEvent?(.diagnosticChanged); return }
        diagnosticRequested = true
        permissionManager.requestLocation()
    }

    func diagnosticSnapshot() throws -> SchoolCaptureDeviceSnapshot {
        let device = UIDevice.current
        guard device.userInterfaceIdiom == .phone || device.userInterfaceIdiom == .pad,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else { throw SchoolCaptureLocationFailure.diagnosticUnavailable }
        var system = utsname()
        guard uname(&system) == 0 else { throw SchoolCaptureLocationFailure.diagnosticUnavailable }
        let machine = Mirror(reflecting: system.machine).children.compactMap { $0.value as? Int8 }
        let model = String(bytes: machine.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, encoding: .utf8)
        guard let model, !model.isEmpty else { throw SchoolCaptureLocationFailure.diagnosticUnavailable }
        var age: Int?, accuracy: Double?
        if let sample = lastDiagnostic {
            let seconds = sample.ageAtReceipt + SchoolCaptureLocationTime.seconds(sample.receivedAt.duration(to: .now))
            if seconds.isFinite, (0...3600).contains(seconds), sample.accuracy <= 10_000 {
                age = Int(ceil(seconds)); accuracy = sample.accuracy
            }
        }
        return SchoolCaptureDeviceSnapshot(permission: permission,
            preciseLocation: permissionManager.accuracyAuthorization == .fullAccuracy,
            deviceClass: device.userInterfaceIdiom == .pad ? "TABLET" : "PHONE", modelCode: model,
            osVersion: device.systemVersion, appBuild: build, sampleAgeSeconds: age,
            horizontalAccuracyMeters: accuracy, availableBytesLocally: Self.availableBytes())
    }

    func diagnosticBody(operationID: UUID, networkAvailable: Bool) throws -> SchoolDeviceAssessmentBody {
        let snapshot = try diagnosticSnapshot()
        return SchoolDeviceAssessmentBody(operationId: operationID, platform: "IOS", deviceClass: snapshot.deviceClass,
            modelCode: snapshot.modelCode, osVersion: snapshot.osVersion, appBuild: snapshot.appBuild,
            permission: snapshot.permission.assessmentValue, preciseLocation: snapshot.preciseLocation,
            sampleAgeSeconds: snapshot.sampleAgeSeconds, horizontalAccuracyMeters: snapshot.horizontalAccuracyMeters,
            freeBytes: nil, networkAvailable: networkAvailable)
    }

    func updateScope(_ scope: SchoolCommandScope?) {
        let changed = currentScope != scope
        currentScope = scope
        if changed {
            startGate.reset()
            preparedSegmentID = nil
            diagnosticRequested = false
            lastDiagnostic = nil
            permissionManager.stopUpdatingLocation()
            coolDown()
            if isRunning { interrupt(.scopeChanged) }
        }
    }

    func prepareSegment(authorization: SchoolCaptureAuthorization, lease: SchoolCaptureLease,
                        scope: SchoolCommandScope, clockReference: SchoolCaptureClockReference,
                        policy: SchoolCaptureLocationPolicy) throws -> SchoolCaptureLocationSegment {
        guard !isRunning else { throw SchoolCaptureLocationFailure.alreadyRunning }
        preparedSegmentID = nil
        let now = ContinuousClock.now, capture = authorization.capture
        guard scope == currentScope, capture.captureState == .authorized, capture.publicationState == .privateCapture,
              capture.schoolId == scope.schoolID, capture.instructorMembershipId == scope.membershipID,
              lease.captureID == capture.id, lease.personID == scope.personID, lease.schoolID == scope.schoolID,
              lease.deviceID == capture.deviceId, lease.permitsCollection(at: now),
              clockReference.serverTime == SchoolLesson.date(authorization.serverTime), now >= clockReference.receivedAt,
              let authorized = SchoolLesson.date(capture.authorizedAt), let expiry = SchoolLesson.date(capture.expiresAt) else {
            throw SchoolCaptureLocationFailure.invalidContext
        }
        try requirePermission(policy)
        let mapped = SchoolCaptureLocationTime.millisecondDate(clockReference.serverTime.addingTimeInterval(
            SchoolCaptureLocationTime.seconds(clockReference.receivedAt.duration(to: now))))
        guard mapped >= authorized, mapped < expiry else { throw SchoolCaptureLocationFailure.invalidContext }
        let id = UUID()
        preparedSegmentID = id
        stoppedBoundary = nil
        return SchoolCaptureLocationSegment(id: id, captureID: capture.id, scope: scope,
            startedAt: SchoolCaptureLocationTime.timestamp(mapped), lease: lease, policy: policy,
            wallStartedAt: Date(), monotonicStartedAt: now, mappedStartedAt: mapped)
    }

    // L'appelant a déjà écrit beginSegment dans SQLCipher. Aucun await ne sépare les
    // derniers contrôles de l'ouverture de la source ; un départ n'est jamais repris.
    func start(segment: SchoolCaptureLocationSegment, handle: SchoolCaptureSegmentHandle) throws {
        guard !isRunning else { throw SchoolCaptureLocationFailure.alreadyRunning }
        let now = ContinuousClock.now
        guard onEvent != nil, segment.id == preparedSegmentID, segment.scope == currentScope, handle.captureID == segment.captureID,
              segment.lease.permitsCollection(at: now), now >= segment.monotonicStartedAt else {
            throw SchoolCaptureLocationFailure.invalidContext
        }
        let isForeground = UIApplication.shared.applicationState == .active
        guard startGate.permits(captureID: segment.captureID, scope: segment.scope, currentScope: currentScope,
            isForeground: isForeground, allowsBackground: segment.policy.allowsBackground,
            leasePermitsCollection: segment.lease.permitsCollection(at: now)) else {
            throw SchoolCaptureLocationFailure.foregroundRequired
        }
        try requirePermission(segment.policy)
        guard let bytes = Self.availableBytes(), bytes >= segment.policy.minimumFreeBytes else {
            throw SchoolCaptureLocationFailure.insufficientStorage
        }
        if segment.policy.allowsBackground {
            guard (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true else {
                throw SchoolCaptureLocationFailure.invalidContext
            }
        }
        guard coherentClock(segment, at: now, wall: Date()) else { throw SchoolCaptureLocationFailure.invalidContext }
        diagnosticRequested = false
        permissionManager.stopUpdatingLocation()
        let manager = CLLocationManager()
        manager.delegate = self
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
            startedBatteryMonitoring = true
        }
        manager.desiredAccuracy = Self.navigationAccuracy(power: UIDevice.current.batteryState)
        // Zéro signifie sans filtre : un premier callback issu du cache peut être
        // refusé sans devoir attendre ensuite un déplacement de plusieurs mètres.
        manager.distanceFilter = segment.policy.distanceFilterMeters == 0 ? kCLDistanceFilterNone : segment.policy.distanceFilterMeters
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = segment.policy.allowsBackground
        manager.showsBackgroundLocationIndicator = segment.policy.allowsBackground
        self.segment = segment; self.handle = handle; self.manager = manager
        preparedSegmentID = nil
        armedWallTime = Date(); lastElapsedMs = nil; lastMappedMeasurement = nil; lastStorageCheck = now
        armDeadline(segment)
        armGap(segment, lastMeasurement: now)
        onEvent?(.signalChanged(.acquiring))
        manager.startUpdatingLocation()
        if isForeground { startGate.didStartInForeground(captureID: segment.captureID, scope: segment.scope) }
    }

    @discardableResult
    func stop() -> SchoolCaptureLocationStop? {
        let now = ContinuousClock.now
        let previous = manager, context = segment, previousHandle = handle
        // Barrière avant tout effet utilisateur : un callback ancien ne voit plus sa
        // source et la minuterie ne peut pas ressusciter sa génération.
        manager = nil; segment = nil; handle = nil; preparedSegmentID = nil; armedWallTime = nil; lastElapsedMs = nil
        if startedBatteryMonitoring {
            UIDevice.current.isBatteryMonitoringEnabled = false
            startedBatteryMonitoring = false
        }
        diagnosticRequested = false
        permissionManager.stopUpdatingLocation()
        coolDown()
        deadlineTask?.cancel(); deadlineTask = nil
        gapTask?.cancel(); gapTask = nil
        gapGeneration = UUID()
        previous?.stopUpdatingLocation()
        previous?.delegate = nil
        guard let context, let previousHandle else { return stoppedBoundary }
        var ended = context.mappedDate(at: min(now, context.lease.collectionDeadline))
        // Une borne exclusive doit suivre le dernier point admis, même si l'arrêt
        // et le callback ont eu lieu dans la même milliseconde.
        if let last = lastMappedMeasurement { ended = max(ended, last.addingTimeInterval(0.001)) }
        lastMappedMeasurement = nil
        let stopped = SchoolCaptureLocationStop(handle: previousHandle, stoppedAt: SchoolCaptureLocationTime.timestamp(ended))
        stoppedBoundary = stopped
        return stopped
    }

    private var lastMappedMeasurement: Date?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === permissionManager || manager === self.manager else { return }
        if let segment {
            if !Self.permission(manager.authorizationStatus).permitsLocation { interrupt(.permissionLost) }
            else if segment.policy.requiresPreciseLocation && manager.accuracyAuthorization != .fullAccuracy { interrupt(.precisionReduced) }
        }
        if !permission.permitsLocation { lastDiagnostic = nil; diagnosticRequested = false; coolDown() }
        // Un changement d’autorisation (y compris le rappel initial du système ou le retour au premier
        // plan) ne termine pas une mesure ponctuelle en cours : seule sa réponse ou son échec le fait.
        // Sinon le départ en un geste croyait la mesure finie et envoyait un diagnostic sans mesure.
        if diagnosticRequested && segment == nil { return }
        onEvent?(.diagnosticChanged)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Flux de réveil : rien n’est lu.
        if manager === warmManager { return }
        let wall = Date(), now = ContinuousClock.now
        if manager === permissionManager {
            guard diagnosticRequested, !isRunning else { return }
            diagnosticRequested = false
            if let latest = locations.last(where: { Self.usableSource($0) }) { recordDiagnostic(latest, wall: wall, now: now) }
            onEvent?(.diagnosticChanged)
            return
        }
        guard manager === self.manager, let segment, let handle, let armedWallTime else {
            discard(locations.count); return
        }
        guard segment.scope == currentScope else { interrupt(.scopeChanged); return }
        guard segment.lease.permitsCollection(at: now) else { interrupt(.expired); return }
        guard Self.permission(manager.authorizationStatus).permitsLocation else { interrupt(.permissionLost); return }
        guard !segment.policy.requiresPreciseLocation || manager.accuracyAuthorization == .fullAccuracy else {
            interrupt(.precisionReduced); return
        }
        guard coherentClock(segment, at: now, wall: wall) else { interrupt(.clockChanged); return }
        if lastStorageCheck.map({ SchoolCaptureLocationTime.seconds($0.duration(to: now)) >= 10 }) ?? true {
            lastStorageCheck = now
            guard let bytes = Self.availableBytes(), bytes >= segment.policy.minimumFreeBytes else { interrupt(.storageLow); return }
        }
        guard locations.count <= 1000 else { discard(locations.count); interrupt(.deviceFailure); return }
        var admitted: [SchoolCaptureMeasurement] = []
        var lastMeasurementInstant: ContinuousClock.Instant?
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let age = wall.timeIntervalSince(location.timestamp)
            guard Self.usableSource(location), location.timestamp >= armedWallTime, age >= 0,
                  age <= segment.policy.maximumCallbackAgeSeconds else { discard(1); continue }
            let elapsed = location.timestamp.timeIntervalSince(segment.wallStartedAt)
            guard elapsed >= 0, elapsed <= 10_800 else { discard(1); continue }
            let elapsedMs = Int((elapsed * 1000).rounded())
            guard lastElapsedMs.map({ elapsedMs > $0 }) ?? true else { discard(1); continue }
            if segment.policy.requiresNewSegment(previousElapsedMs: lastElapsedMs, nextElapsedMs: elapsedMs) {
                if !admitted.isEmpty { onEvent?(.measurements(handle: handle, values: admitted)) }
                discard(1)
                interrupt(.signalLost)
                return
            }
            let measuredAt = segment.monotonicStartedAt.advanced(by: .milliseconds(elapsedMs))
            guard measuredAt <= now, measuredAt < segment.lease.collectionDeadline else { discard(1); continue }
            let captured = segment.mappedStartedAt.addingTimeInterval(Double(elapsedMs) / 1000)
            admitted.append(SchoolCaptureMeasurement(capturedAt: SchoolCaptureLocationTime.timestamp(captured), elapsedMs: elapsedMs,
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracyMeters: location.horizontalAccuracy))
            lastElapsedMs = elapsedMs; lastMappedMeasurement = captured; lastMeasurementInstant = measuredAt
            recordDiagnostic(location, wall: wall, now: now)
        }
        guard !admitted.isEmpty else { return }
        // Le trajet reçoit ses positions : le réveil n’a plus d’utilité.
        coolDown()
        if let lastMeasurementInstant { armGap(segment, lastMeasurement: lastMeasurementInstant) }
        onEvent?(.signalChanged(.receiving))
        onEvent?(.measurements(handle: handle, values: admitted))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if manager === permissionManager { diagnosticRequested = false; lastDiagnostic = nil; onEvent?(.diagnosticChanged); return }
        guard manager === self.manager else { return }
        let code = (error as? CLError)?.code
        // Core Location peut ne pas avoir de fix pour l'instant. Arrêter ici
        // empêchait la première position, et toute récupération du signal.
        if code == .locationUnknown {
            onEvent?(.signalChanged(.temporarilyUnavailable))
            return
        }
        interrupt(code == .denied ? .permissionLost : .deviceFailure)
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        interrupt(.systemPaused)
    }

    private func interrupt(_ reason: SchoolCaptureLocationInterruption) {
        guard isRunning, let stopped = stop() else { return }
        onEvent?(.interrupted(reason, stopped))
    }

    private func armDeadline(_ segment: SchoolCaptureLocationSegment) {
        deadlineTask?.cancel()
        deadlineTask = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: segment.lease.collectionDeadline, tolerance: .zero) }
            catch { return }
            guard !Task.isCancelled, let self, self.segment?.id == segment.id else { return }
            self.interrupt(.expired)
        }
    }

    private func armGap(_ segment: SchoolCaptureLocationSegment, lastMeasurement: ContinuousClock.Instant) {
        gapTask?.cancel()
        let generation = UUID()
        gapGeneration = generation
        let delay = lastElapsedMs == nil ? min(15, segment.policy.signalGapSeconds) : segment.policy.signalGapSeconds
        let deadline = min(lastMeasurement.advanced(by: .seconds(delay)), segment.lease.collectionDeadline)
        gapTask = Task { [weak self] in
            do { try await ContinuousClock().sleep(until: deadline, tolerance: .zero) }
            catch { return }
            guard !Task.isCancelled, let self, self.segment?.id == segment.id,
                  self.gapGeneration == generation else { return }
            if !segment.lease.permitsCollection() { self.interrupt(.expired) }
            else {
                // Un silence du capteur ne prouve pas une fin de trajet, notamment
                // à l'arrêt. Le manager reste actif, sans générer de point.
                self.onEvent?(.signalChanged(.waitingForPosition))
            }
        }
    }

    private func recordDiagnostic(_ location: CLLocation, wall: Date, now: ContinuousClock.Instant) {
        let age = wall.timeIntervalSince(location.timestamp)
        guard Self.usableSource(location), age.isFinite, (0...3600).contains(age) else { return }
        lastDiagnostic = (age, location.horizontalAccuracy, now)
    }

    private func requirePermission(_ policy: SchoolCaptureLocationPolicy) throws {
        guard CLLocationManager.locationServicesEnabled() else { throw SchoolCaptureLocationFailure.servicesDisabled }
        guard permission.permitsLocation,
              !policy.requiresPreciseLocation || permissionManager.accuracyAuthorization == .fullAccuracy else {
            throw SchoolCaptureLocationFailure.permissionRequired
        }
    }

    private func coherentClock(_ segment: SchoolCaptureLocationSegment, at now: ContinuousClock.Instant, wall: Date) -> Bool {
        let monotonic = SchoolCaptureLocationTime.seconds(segment.monotonicStartedAt.duration(to: now))
        return monotonic >= 0 && abs(wall.timeIntervalSince(segment.wallStartedAt) - monotonic) <= segment.policy.maximumClockDriftSeconds
    }

    private static func usableSource(_ location: CLLocation) -> Bool {
        location.timestamp.timeIntervalSince1970.isFinite && CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy.isFinite && location.horizontalAccuracy >= 0
            && location.sourceInformation?.isSimulatedBySoftware != true
            && location.sourceInformation?.isProducedByAccessory != true
    }

    private static func availableBytes() -> Int64? {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let bytes = values.volumeAvailableCapacity, bytes >= 0 else { return nil }
        return Int64(bytes)
    }

    private static func permission(_ status: CLAuthorizationStatus) -> SchoolCaptureLocationPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorizedWhenInUse: .foreground
        case .authorizedAlways: .background
        @unknown default: .denied
        }
    }

    private func discard(_ count: Int) { discardedCallbackCount = min(1_000_000, discardedCallbackCount + min(count, 1000)) }

    /// Apple reserves the extra sensors of BestForNavigation for external power.
    /// On battery, retain Best and the same unfiltered stream of measurements.
    static func navigationAccuracy(power: UIDevice.BatteryState) -> CLLocationAccuracy {
        power == .charging || power == .full ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
    }

    @objc private func powerChanged() {
        manager?.desiredAccuracy = Self.navigationAccuracy(power: UIDevice.current.batteryState)
    }

    @objc private func clockChanged() {
        lastDiagnostic = nil
        if isRunning { interrupt(.clockChanged) }
    }
    @objc private func enteredBackground() {
        // Jamais de GPS en arrière-plan sans trajet en cours.
        if segment == nil { coolDown() }
        if let segment, !segment.policy.allowsBackground { interrupt(.systemPaused) }
    }
    @objc private func becameActive() {
        if let segment, !segment.lease.permitsCollection() { interrupt(.expired) }
        locationManagerDidChangeAuthorization(permissionManager)
    }
}
