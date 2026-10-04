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
            points: [point(0, second: 0, longitude: 7), point(1, second: 1, longitude: 7.0001)],
            hasGapBefore: false, qualityLabel: "COMPLETE")
        let second = SchoolCaptureReplayFragment(id: "second", segmentID: UUID(), segmentIndex: 1,
            points: [point(0, second: 10, longitude: 7.0002), point(1, second: 11, longitude: 7.0001)],
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
                latitude: 47, longitude: 7 + Double(index) / 10_000, accuracyMeters: 5)
        }
        let timeline = SchoolReplayTimeline(fragments: [.init(id: "one-segment", segmentID: UUID(), segmentIndex: 0,
            points: points, hasGapBefore: false, qualityLabel: "COMPLETE")], observations: [], startsAt: start,
            endsAt: start.addingTimeInterval(31))
        #expect(timeline.fragments.count == 2)
        #expect(timeline.fragments.map { $0.line.pointCount } == [2, 2])
        #expect(timeline.sample(at: 2) == nil && timeline.sample(at: 29) == nil)
        #expect(timeline.sample(at: 30)?.heading == nil)
    }

    @Test func impreciseDepartureKeepsTheOriginalSequenceAndMeasurement() {
        let source = [measured(0, second: 0, east: 100, accuracy: 80), measured(1, second: 1, east: 0),
                      measured(2, second: 2, east: 10)]
        let selected = SchoolCaptureDisplayRoute.select(source)
        #expect(selected.map(\.point) == Array(source.dropFirst()))
        #expect(selected.map(\.point.sequence) == [1, 2])
        #expect(selected.map(\.startsFragment) == [true, false])
    }

    @Test func isolatedJumpIsNeverUsedForPositionHeadingOrRouteContinuity() {
        let source = [measured(0, second: 0, east: 0), measured(1, second: 1, east: 10),
                      measured(2, second: 2, east: 1_000), measured(3, second: 3, east: 30),
                      measured(4, second: 4, east: 40)]
        let selected = SchoolCaptureDisplayRoute.select(source)
        #expect(selected.map(\.point.sequence) == [0, 1, 3, 4])
        #expect(selected.map(\.startsFragment) == [true, false, true, false])
        let timeline = replay(source)
        #expect(timeline.fragments.map { $0.line.pointCount } == [2, 2])
        #expect(timeline.sample(at: 2) == nil)
        #expect(timeline.sample(at: 3)?.heading == nil)
    }

    @Test func prolongedStationaryDriftDoesNotWalkTheDisplayedPosition() {
        let source = (0...60).map { second in
            measured(second, second: second, east: second == 0 ? 0 : Double(second % 3 - 1),
                     north: second == 0 ? 0 : Double(second % 2), accuracy: 5)
        }
        let selected = SchoolCaptureDisplayRoute.select(source)
        #expect(selected.map(\.point) == [source[0]])
    }

    @Test func slowRoundaboutRetainsRealCurvatureWithoutSmoothing() {
        let source = (0...12).map { index in
            let angle = Double(index) * .pi / 6
            return measured(index, second: index * 5, east: 12 * cos(angle), north: 12 * sin(angle), accuracy: 3)
        }
        let selected = SchoolCaptureDisplayRoute.select(source)
        #expect(selected.map(\.point) == source)
        #expect(selected.filter(\.startsFragment).count == 1)
    }

    @Test func tunnelReacquisitionStartsANewFragmentAndDirection() {
        let source = [measured(0, second: 0, east: 0), measured(1, second: 1, east: 10),
                      measured(2, second: 40, east: 3_000), measured(3, second: 41, east: 3_010)]
        let timeline = replay(source)
        #expect(timeline.fragments.map { $0.line.pointCount } == [2, 2])
        #expect(timeline.sample(at: 20) == nil)
        #expect(timeline.sample(at: 40)?.heading == nil)
    }

    @Test func outOfOrderBatchesUseDurableSequenceRatherThanArrayIndex() {
        let source = (0...3).map { measured($0, second: $0, east: Double($0) * 10) }
        let shuffled = [source[2], source[3], source[0], source[1]]
        #expect(SchoolCaptureDisplayRoute.select(shuffled).map(\.point) == source)
        #expect(replay(shuffled).samples.map(\.offset) == [0, 1, 2, 3])
    }

    @Test func missingSequenceDoesNotJoinTwoAvailableChunks() {
        let selected = SchoolCaptureDisplayRoute.select([measured(0, second: 0, east: 0), measured(2, second: 2, east: 20)])
        #expect(selected.map(\.startsFragment) == [true, true])
        #expect(selected.map(\.point.sequence) == [0, 2])
    }

    @Test func rejectedTailDoesNotLeaveACursorAtAnOldFix() {
        let timeline = replay([measured(0, second: 0, east: 0), measured(1, second: 1, east: 1_000)])
        #expect(timeline.sample(at: 0) != nil)
        #expect(timeline.sample(at: 1) == nil)
        #expect(timeline.gaps.contains(0...1))
    }

    @Test func filteredAnchorKeepsItsTimeWithoutMovingToAnotherPosition() {
        let segmentID = UUID()
        let points = [measured(0, second: 0, east: 0), measured(1, second: 1, east: 1_000),
                      measured(2, second: 2, east: 20)]
        let observation = SchoolPrivateGeoObservation(id: UUID(), schoolId: UUID(), version: 1, lessonId: UUID(),
            trainingId: UUID(), draftId: nil, captureId: UUID(), segmentId: segmentID, pointSequence: 1,
            competencyId: nil, text: "Repère synthétique", origin: "LIVE", observedAt: points[1].capturedAt,
            eventKind: "MARKER", eventStatus: nil, authorMembershipId: nil)
        let timeline = SchoolReplayTimeline(fragments: [.init(id: "anchor", segmentID: segmentID, segmentIndex: 0,
            points: points, hasGapBefore: false, qualityLabel: "AVAILABLE")], observations: [observation],
            startsAt: SchoolLesson.date(points[0].capturedAt), endsAt: SchoolLesson.date(points[2].capturedAt))
        #expect(timeline.items.count == 1)
        #expect(timeline.items.first?.offset == 1)
        #expect(timeline.items.first?.coordinate == nil)
    }

    private func measured(_ sequence: Int, second: Int, east: Double, north: Double = 0, accuracy: Double = 3) -> SchoolCapturePoint {
        // Synthetic metres around the equator: no route or personal location is used.
        let start = Date(timeIntervalSince1970: 1_790_755_200)
        return SchoolCapturePoint(sequence: sequence, elapsedMs: second * 1000,
            capturedAt: SchoolCaptureLocationTime.timestamp(start.addingTimeInterval(Double(second))),
            latitude: north / 111_320, longitude: east / 111_320, accuracyMeters: accuracy)
    }

    private func replay(_ points: [SchoolCapturePoint]) -> SchoolReplayTimeline {
        SchoolReplayTimeline(fragments: [.init(id: "synthetic", segmentID: UUID(), segmentIndex: 0, points: points,
            hasGapBefore: false, qualityLabel: "AVAILABLE")], observations: [],
            startsAt: points.min(by: { $0.sequence < $1.sequence }).flatMap { SchoolLesson.date($0.capturedAt) },
            endsAt: points.max(by: { $0.sequence < $1.sequence }).flatMap { SchoolLesson.date($0.capturedAt) })
    }
}
