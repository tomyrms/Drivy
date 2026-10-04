import CoreLocation
import Observation
import SwiftUI
import UIKit

/// Ephemeral compass values for the live camera only. They are never route points.
enum SchoolLiveHeading {
    static func degrees(trueHeading: Double, magneticHeading: Double, accuracy: Double,
                        timestamp: Date, now: Date) -> Double? {
        let age = now.timeIntervalSince(timestamp)
        guard accuracy.isFinite, (0...45).contains(accuracy),
              age.isFinite, (-1...5).contains(age) else { return nil }
        if trueHeading.isFinite, (0..<360).contains(trueHeading) { return trueHeading }
        if magneticHeading.isFinite, (0..<360).contains(magneticHeading) { return magneticHeading }
        return nil
    }

    /// Interface landscape names are opposite to the physical device names.
    static func orientation(for interface: UIInterfaceOrientation) -> CLDeviceOrientation? {
        switch interface {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        default: nil
        }
    }
}

/// Owned by the visible live map, independent of the durable GPS collector.
/// A fresh manager per run also rejects callbacks queued before pause/disappearance.
@MainActor @Observable
final class SchoolLiveHeadingSource: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var degrees: Double?
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private weak var windowScene: UIWindowScene?
    @ObservationIgnored private var lastTimestamp: Date?
    @ObservationIgnored private var startedAt: Date?

    func setWindowScene(_ scene: UIWindowScene?) {
        windowScene = scene
    }

    func setActive(_ active: Bool) {
        guard active else { stop(); return }
        guard manager == nil, CLLocationManager.headingAvailable() else { return }
        let candidate = CLLocationManager()
        guard candidate.authorizationStatus == .authorizedWhenInUse
                || candidate.authorizationStatus == .authorizedAlways else { return }
        candidate.delegate = self
        candidate.headingFilter = 2
        if let orientation = interfaceOrientation { candidate.headingOrientation = orientation }
        manager = candidate
        startedAt = Date()
        candidate.startUpdatingHeading()
    }

    func stop() {
        manager?.stopUpdatingHeading()
        manager?.delegate = nil
        manager = nil
        lastTimestamp = nil
        startedAt = nil
        degrees = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard manager === self.manager, let startedAt, newHeading.timestamp >= startedAt else { return }
        if let orientation = interfaceOrientation, manager.headingOrientation != orientation {
            manager.headingOrientation = orientation
            degrees = nil
            // This callback was measured against the previous screen edge.
            return
        }
        guard lastTimestamp.map({ newHeading.timestamp > $0 }) ?? true else { return }
        lastTimestamp = newHeading.timestamp
        degrees = SchoolLiveHeading.degrees(trueHeading: newHeading.trueHeading,
            magneticHeading: newHeading.magneticHeading, accuracy: newHeading.headingAccuracy,
            timestamp: newHeading.timestamp, now: Date())
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        if manager.authorizationStatus != .authorizedWhenInUse && manager.authorizationStatus != .authorizedAlways {
            stop()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard manager === self.manager else { return }
        degrees = nil
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }

    private var interfaceOrientation: CLDeviceOrientation? {
        windowScene.flatMap { SchoolLiveHeading.orientation(for: $0.effectiveGeometry.interfaceOrientation) }
    }
}

/// Resolve the map's actual window, including iPad multiwindow and rotation lock.
/// No global scene selection or device-orientation notification stream is needed.
struct SchoolLiveHeadingWindowReader: UIViewRepresentable {
    let source: SchoolLiveHeadingSource

    func makeUIView(context: Context) -> WindowView {
        let view = WindowView()
        view.source = source
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: WindowView, context: Context) {
        uiView.source = source
        source.setWindowScene(uiView.window?.windowScene)
    }

    final class WindowView: UIView {
        weak var source: SchoolLiveHeadingSource?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            source?.setWindowScene(window?.windowScene)
        }
    }
}
