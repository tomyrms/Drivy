import CoreLocation
import Foundation
import Testing
import UIKit
@testable import Drivy

struct SchoolLiveHeadingTests {
    private let now = Date(timeIntervalSince1970: 1_790_755_200)

    @Test func validTrueNorthWinsIncludingZeroDegrees() {
        #expect(value(trueHeading: 0, magnetic: 12) == 0)
        #expect(value(trueHeading: 270, magnetic: 258) == 270)
    }

    @Test func magneticHeadingWorksWithoutAMovingGPSFix() {
        // Rotating an otherwise stationary device needs no coordinate or course.
        #expect(value(trueHeading: -1, magnetic: 270) == 270)
        #expect(value(trueHeading: -1, magnetic: 0) == 0)
        #expect(value(trueHeading: .nan, magnetic: 180) == 180)
    }

    @Test func invalidOrUnreliableMeasurementsNeverBecomeNorth() {
        #expect(value(accuracy: -1) == nil)
        #expect(value(accuracy: 46) == nil)
        #expect(value(accuracy: .nan) == nil)
        #expect(value(trueHeading: -1, magnetic: -1) == nil)
        #expect(value(trueHeading: .infinity, magnetic: .nan) == nil)
        #expect(value(trueHeading: 360, magnetic: 360) == nil)
    }

    @Test func staleAndFutureCallbacksAreRejected() {
        #expect(value(age: 6) == nil)
        #expect(value(age: -2) == nil)
        #expect(value(age: 5) == 90)
    }

    @Test func headingReferenceFollowsTheDisplayedScreenEdge() {
        #expect(SchoolLiveHeading.orientation(for: .portrait) == .portrait)
        #expect(SchoolLiveHeading.orientation(for: .portraitUpsideDown) == .portraitUpsideDown)
        #expect(SchoolLiveHeading.orientation(for: .landscapeLeft) == .landscapeRight)
        #expect(SchoolLiveHeading.orientation(for: .landscapeRight) == .landscapeLeft)
        #expect(SchoolLiveHeading.orientation(for: .unknown) == nil)
    }

    @Test func centeringFirstKeepsNorthUpAndOnlyTheSecondTapUsesDeviceHeading() {
        let centered = DrivyMapFollowMode.free.next
        #expect(centered == .position && centered.cameraHeading(deviceHeading: 270) == 0)
        let oriented = centered.next
        #expect(oriented == .heading && oriented.cameraHeading(deviceHeading: 270) == 270)
        #expect(oriented.next == .free && !oriented.next.followsPosition)
        #expect(oriented.next.cameraHeading(deviceHeading: 270) == nil)
    }

    @Test func unavailableCompassDoesNotInventAnOrientationForHeadingMode() {
        #expect(DrivyMapFollowMode.heading.cameraHeading(deviceHeading: nil) == nil)
        #expect(DrivyMapFollowMode.heading.cameraHeading(deviceHeading: .nan) == nil)
        #expect(DrivyMapFollowMode.heading.cameraHeading(deviceHeading: 360) == nil)
    }

    private func value(trueHeading: Double = 90, magnetic: Double = 85,
                       accuracy: Double = 5, age: TimeInterval = 0) -> Double? {
        SchoolLiveHeading.degrees(trueHeading: trueHeading, magneticHeading: magnetic,
            accuracy: accuracy, timestamp: now.addingTimeInterval(-age), now: now)
    }
}
