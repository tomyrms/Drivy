import CoreLocation
import Foundation
import Testing
@testable import Drivy

struct SchoolMapCourseTests {
    @Test func movementOrientsTheMapWhileStationaryDriftDoesNot() throws {
        var course = SchoolMapCourse()
        let origin = CLLocationCoordinate2D(latitude: 47, longitude: 7)
        let initialHeading = course.receive(origin, at: 0, accuracy: 5)
        let driftHeading = course.receive(.init(latitude: 47.000005, longitude: 7.000005), at: 1, accuracy: 5)
        #expect(initialHeading == nil && driftHeading == nil)
        let eastHeading = course.receive(.init(latitude: 47, longitude: 7.001), at: 2, accuracy: 5)
        let east = try #require(eastHeading)
        #expect(abs(east - 90) < 1)
        let stationary = course.receive(.init(latitude: 47.000001, longitude: 7.001001), at: 3, accuracy: 5)
        #expect(stationary == east)
        let northHeading = course.receive(.init(latitude: 47.001, longitude: 7.001), at: 4, accuracy: 5)
        let north = try #require(northHeading)
        #expect(north < 1 || north > 359)
        let afterGap = course.receive(.init(latitude: 47.02, longitude: 7.02), at: 30, accuracy: 5)
        #expect(afterGap == nil)
    }

    @Test func bearingUsesTheShortestDirectionAcrossTheDateLine() {
        let bearing = SchoolMapCourse.bearing(from: .init(latitude: 0, longitude: 179.99),
            to: .init(latitude: 0, longitude: -179.99))
        #expect(abs(bearing - 90) < 0.001)
    }

    @Test func replayKeepsMeasuredCoordinatesAndHidesTheCursorAcrossPauses() throws {
        let start = try #require(SchoolLesson.date("2026-09-30T08:00:00Z"))
        func point(_ sequence: Int, second: Int, longitude: Double) -> SchoolCapturePoint {
            .init(sequence: sequence, elapsedMs: second * 1000,
                capturedAt: SchoolCaptureLocationTime.timestamp(start.addingTimeInterval(Double(second))),
                latitude: 47, longitude: longitude, accuracyMeters: 5)
        }
        let first = SchoolCaptureReplayFragment(id: "first", segmentID: UUID(), segmentIndex: 0,
            points: [point(0, second: 0, longitude: 7), point(1, second: 1, longitude: 7.001)],
            hasGapBefore: false, qualityLabel: "COMPLETE")
        let second = SchoolCaptureReplayFragment(id: "second", segmentID: UUID(), segmentIndex: 1,
            points: [point(0, second: 10, longitude: 7.002), point(1, second: 11, longitude: 7.001)],
            hasGapBefore: true, qualityLabel: "COMPLETE")
        let timeline = SchoolReplayTimeline(fragments: [first, second], observations: [], startsAt: start,
            endsAt: start.addingTimeInterval(11))
        #expect(timeline.samples.count == 4)
        #expect(timeline.sample(at: 0.5)?.coordinate.longitude == 7)
        #expect(timeline.sample(at: 2) == nil && timeline.sample(at: 9.9) == nil)
        #expect(timeline.sample(at: 10)?.heading == nil)
        let east = try #require(timeline.sample(at: 1)?.heading)
        let west = try #require(timeline.sample(at: 11)?.heading)
        #expect(abs(east - 90) < 1 && abs(west - 270) < 1)
    }

    @Test func silenceWithinASegmentDoesNotDrawAStraightLineAcrossTheGap() throws {
        let start = try #require(SchoolLesson.date("2026-09-30T08:00:00Z"))
        let points = [0, 1, 30, 31].enumerated().map { index, second in
            SchoolCapturePoint(sequence: index, elapsedMs: second * 1000,
                capturedAt: SchoolCaptureLocationTime.timestamp(start.addingTimeInterval(Double(second))),
                latitude: 47, longitude: 7 + Double(index) / 1000, accuracyMeters: 5)
        }
        let timeline = SchoolReplayTimeline(fragments: [.init(id: "one-segment", segmentID: UUID(), segmentIndex: 0,
            points: points, hasGapBefore: false, qualityLabel: "COMPLETE")], observations: [], startsAt: start,
            endsAt: start.addingTimeInterval(31))
        #expect(timeline.fragments.count == 2)
        #expect(timeline.fragments.map { $0.line.pointCount } == [2, 2])
        #expect(timeline.sample(at: 2) == nil && timeline.sample(at: 29) == nil)
        #expect(timeline.sample(at: 30)?.heading == nil)
    }
}
