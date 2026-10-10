import Foundation
import Testing
@testable import Drivy

struct SchoolMapRouteGapTests {
    @Test func silenceConnectsOnlyOriginalRetainedEndpoints() throws {
        let source = [point(0, second: 0, east: 0), point(1, second: 1, east: 10),
                      point(2, second: 30, east: 200), point(3, second: 31, east: 210)]
        let displayed = SchoolCaptureDisplayRoute.select(source)
        let gaps = SchoolMapRouteGap.withinSegment(source, displayed: displayed, idPrefix: "synthetic")
        let gap = try #require(gaps.first)
        #expect(gaps.count == 1)
        #expect(gap.start == source[1] && gap.end == source[2])
        #expect(gap.line.pointCount == 2)
        #expect(SchoolCaptureDisplayRoute.fragments(displayed).map(\.count) == [2, 2])
    }

    @Test func stationaryThinningIsNotMisrepresentedAsGPSSilence() {
        var source = (0...30).map { point($0, second: $0, east: 0) }
        source.append(point(31, second: 31, east: 10))
        let displayed = SchoolCaptureDisplayRoute.select(source)
        #expect(displayed.map(\.point.sequence) == [0, 31])
        #expect(displayed.last?.startsFragment == true)
        #expect(SchoolMapRouteGap.withinSegment(source, displayed: displayed, idPrefix: "synthetic").isEmpty)
    }

    @Test func missingSequenceAndRejectedPositionDoNotInventASignalOutage() {
        let source = [point(0, second: 0, east: 0), point(2, second: 2, east: 20),
                      point(3, second: 3, east: 30, accuracy: 100), point(4, second: 4, east: 40)]
        let displayed = SchoolCaptureDisplayRoute.select(source)
        #expect(displayed.filter(\.startsFragment).count == 3)
        #expect(SchoolMapRouteGap.withinSegment(source, displayed: displayed, idPrefix: "synthetic").isEmpty)
    }

    @Test func exactThresholdDoesNotCreateAGapAndInputOrderDoesNotMatter() {
        let source = [point(0, second: 0, east: 0), point(1, second: 15, east: 10),
                      point(2, second: 31, east: 20)]
        let shuffled = [source[2], source[0], source[1]]
        let gaps = SchoolMapRouteGap.withinSegment(shuffled,
            displayed: SchoolCaptureDisplayRoute.select(shuffled), idPrefix: "synthetic")
        #expect(gaps.count == 1)
        #expect(gaps.first?.start == source[1] && gaps.first?.end == source[2])
    }

    @Test func segmentBoundaryUsesRecordedDatesDespiteRestartedElapsedClock() throws {
        let previous = point(8, second: 10, east: 10)
        let next = point(0, second: 40, east: 100, elapsedSecond: 0)
        let gap = SchoolMapRouteGap.betweenSegments(id: "synthetic", previousSource: previous, nextSource: next,
            previousDisplayed: previous, nextDisplayed: next)
        let connector = try #require(gap)
        #expect(connector.start == previous)
        let quickResume = point(0, second: 20, east: 50, elapsedSecond: 0)
        #expect(SchoolMapRouteGap.betweenSegments(id: "quick", previousSource: previous, nextSource: quickResume,
            previousDisplayed: previous, nextDisplayed: quickResume) == nil)
    }

    @Test func replayGapNeverSuppliesAPositionToThePlayhead() throws {
        let source = [point(0, second: 0, east: 0), point(1, second: 1, east: 10),
                      point(2, second: 30, east: 200), point(3, second: 31, east: 210)]
        let timeline = SchoolReplayTimeline(fragments: [SchoolCaptureReplayFragment(id: "synthetic",
            segmentID: UUID(), segmentIndex: 0, points: source, hasGapBefore: false, qualityLabel: "AVAILABLE")],
            observations: [], startsAt: SchoolLesson.date(source[0].capturedAt),
            endsAt: SchoolLesson.date(source[3].capturedAt))
        #expect(timeline.mapGaps.count == 1)
        #expect(timeline.samples.count == source.count)
        #expect(timeline.fragments.map { $0.line.pointCount } == [2, 2])
        #expect(timeline.sample(at: 15) == nil)
        #expect(timeline.sample(at: 30)?.coordinate.longitude == source[2].longitude)
    }

    private func point(_ sequence: Int, second: Int, east: Double, accuracy: Double = 3,
                       elapsedSecond: Int? = nil) -> SchoolCapturePoint {
        // Synthetic equatorial offsets; no lesson or personal location is used.
        let start = Date(timeIntervalSince1970: 1_790_755_200)
        return SchoolCapturePoint(sequence: sequence, elapsedMs: (elapsedSecond ?? second) * 1000,
            capturedAt: SchoolCaptureLocationTime.timestamp(start.addingTimeInterval(Double(second))),
            latitude: 0, longitude: east / 111_320, accuracyMeters: accuracy)
    }
}
