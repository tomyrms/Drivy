import CoreLocation
import Foundation
import QuartzCore
import Testing
@testable import Drivy

/// Filtering, ordering, interpolation and reconstruction of a displayed trip.
/// Synthetic metres around the equator: no route or personal location is used.
struct SchoolTrackDisplayTests {
    private static let metre = 1.0 / 111_320
    private static let start = Date(timeIntervalSince1970: 1_790_755_200)

    private func fix(_ sequence: Int, second: Double, east: Double, north: Double = 0, accuracy: Double = 4) -> SchoolCapturePoint {
        SchoolCapturePoint(sequence: sequence, elapsedMs: Int((second * 1000).rounded()),
            capturedAt: SchoolCaptureLocationTime.timestamp(Self.start.addingTimeInterval(second)),
            latitude: north * Self.metre, longitude: east * Self.metre, accuracyMeters: accuracy)
    }

    private func noise(_ index: Int, _ amplitude: Double) -> Double { sin(Double(index) * 12.9898) * amplitude }

    private func replay(_ points: [SchoolCapturePoint], segmentID: UUID = UUID(), matched: SchoolMatchedRoute? = nil) -> SchoolReplayTimeline {
        SchoolReplayTimeline(fragments: [.init(id: "synthetic", segmentID: segmentID, segmentIndex: 0, points: points,
            hasGapBefore: false, qualityLabel: "AVAILABLE")], observations: [], startsAt: Self.start,
            endsAt: points.map(\.elapsedMs).max().map { Self.start.addingTimeInterval(Double($0) / 1000) }, matched: matched)
    }

    // MARK: Filtering and ordering

    @Test func oneFixAtATimeGivesTheSameSelectionAsTheWholeTrip() {
        var source: [SchoolCapturePoint] = []
        for index in 0..<400 {
            let stopped = (120..<170).contains(index)
            let east = stopped ? 1_200 + noise(index, 3) : Double(min(index, 120)) * 10 + Double(max(0, index - 170)) * 9
            source.append(fix(index, second: Double(index), east: east, north: noise(index + 3, stopped ? 3 : 1.5),
                              accuracy: index % 37 == 0 ? 60 : 5))
        }
        var selector = SchoolCaptureDisplayRoute.Selector()
        for point in source { selector.append(point) }
        let whole = SchoolCaptureDisplayRoute.select(source)
        #expect(selector.samples.map(\.point) == whole.map(\.point))
        #expect(selector.samples.map(\.startsFragment) == whole.map(\.startsFragment))
        #expect(selector.samples.map(\.heldUntilMs) == whole.map(\.heldUntilMs))
        // Durable order: sequences only ever grow, whatever was filtered out.
        #expect(zip(whole, whole.dropFirst()).allSatisfy { $0.point.sequence < $1.point.sequence })
    }

    @Test func aRedLightNeitherScribblesNorCutsTheRoute() {
        let arrive = (0..<5).map { fix($0, second: Double($0), east: Double($0) * 10) }
        let stop = (0..<40).map { fix(5 + $0, second: Double(5 + $0), east: 40 + noise($0, 3), north: noise($0 + 7, 3), accuracy: 6) }
        let leave = (0..<5).map { fix(45 + $0, second: Double(45 + $0), east: 50 + Double($0) * 10) }
        let selected = SchoolCaptureDisplayRoute.select(arrive + stop + leave)
        #expect(selected.map(\.point.sequence) == [0, 1, 2, 3, 4, 45, 46, 47, 48, 49])
        #expect(selected.filter(\.startsFragment).count == 1)
        #expect(selected[4].heldUntilMs == 44_000)
    }

    @Test func aFixThrownAsideAndBackIsWithdrawnWhileRealManoeuvresStay() {
        var selector = SchoolCaptureDisplayRoute.Selector()
        let spike = [fix(0, second: 0, east: 0), fix(1, second: 1, east: 10), fix(2, second: 2, east: 20),
                     fix(3, second: 3, east: 30, north: 35), fix(4, second: 4, east: 40), fix(5, second: 5, east: 50)]
        let changes = spike.map { selector.append($0) }
        #expect(changes == [.appended, .appended, .appended, .appended, .replacedLast, .appended])
        #expect(selector.samples.map(\.point.sequence) == [0, 1, 2, 4, 5])
        #expect(selector.samples.filter(\.startsFragment).count == 1)

        // U-turn: out and back on the same street, several seconds apart. Both ways are kept.
        let out = (0..<10).map { fix($0, second: Double($0), east: Double($0) * 8) }
        let turn = [fix(10, second: 13, east: 76, north: 4), fix(11, second: 16, east: 72, north: 7)]
        let back = (0..<10).map { fix(12 + $0, second: Double(19 + $0), east: 64 - Double($0) * 8, north: 8) }
        #expect(SchoolCaptureDisplayRoute.select(out + turn + back).count == 22)

        // Right-angle corner at a junction: the corner fix is a vertex, not a spike.
        let corner = [fix(0, second: 0, east: 0), fix(1, second: 1, east: 15), fix(2, second: 2, east: 30),
                      fix(3, second: 3, east: 30, north: 15), fix(4, second: 4, east: 30, north: 30)]
        #expect(SchoolCaptureDisplayRoute.select(corner).count == 5)
    }

    @Test func reverseAndParkingManoeuvresAreNotErasedAsNoise() {
        let forward = (0..<6).map { fix($0, second: Double($0), east: Double($0) * 6) }
        let reverse = (0..<8).map { fix(6 + $0, second: Double(7 + $0), east: 30 - Double($0 + 1) * 1.2) }
        let selected = SchoolCaptureDisplayRoute.select(forward + reverse)
        #expect(selected.prefix(6).map(\.point.sequence) == [0, 1, 2, 3, 4, 5])
        #expect((selected.last?.point.longitude ?? 1) < 26 * Self.metre)
        #expect(selected.filter(\.startsFragment).count == 1)

        var parking: [SchoolCapturePoint] = []
        for index in 0..<30 {
            let east = Double(min(index, 15)) * 2.5, north = Double(max(0, index - 15)) * 2.5
            parking.append(fix(index, second: Double(index) * 2, east: east, north: north, accuracy: 3))
        }
        let parked = SchoolCaptureDisplayRoute.select(parking)
        #expect(parked.count > 20 && parked.filter(\.startsFragment).count == 1)
    }

    @Test func motorwaySpeedIsNeverMistakenForAJump() {
        let points = (0..<60).map { fix($0, second: Double($0), east: Double($0) * 36.1, north: noise($0, 1.5)) }
        let selected = SchoolCaptureDisplayRoute.select(points)
        #expect(selected.count == 60 && selected.filter(\.startsFragment).count == 1)
    }

    @Test func aLongBlindStretchCutsTheRouteWhileOneBadFixDoesNot() {
        var blind: [SchoolCapturePoint] = [fix(0, second: 0, east: 0), fix(1, second: 1, east: 10)]
        for index in 0..<8 { blind.append(fix(2 + index, second: Double(2 + index), east: 20 + Double(index) * 10, accuracy: 90)) }
        blind.append(fix(10, second: 10, east: 100))
        blind.append(fix(11, second: 11, east: 110))
        #expect(SchoolCaptureDisplayRoute.select(blind).map(\.startsFragment) == [true, false, true, false])
        let single = [fix(0, second: 0, east: 0), fix(1, second: 1, east: 10), fix(2, second: 2, east: 20, accuracy: 90),
                      fix(3, second: 3, east: 30)]
        #expect(SchoolCaptureDisplayRoute.select(single).map(\.startsFragment) == [true, false, false])
    }

    @Test @MainActor func aLiveSegmentGrowsWithoutReplayingItsPast() {
        var segment = SchoolCaptureMapSegment(id: UUID(), measurements: [])
        var all: [SchoolCaptureMeasurement] = []
        var revisions: [Int] = []
        for index in 0..<120 {
            let point = fix(index, second: Double(index), east: index < 60 ? Double(index) * 9 : 540 + noise(index, 2))
            let measurement = SchoolCaptureMeasurement(capturedAt: point.capturedAt, elapsedMs: point.elapsedMs,
                latitude: point.latitude, longitude: point.longitude, accuracyMeters: point.accuracyMeters)
            all.append(measurement)
            segment.appendDurable([measurement])
            revisions.append(segment.displayRevision)
        }
        // The segment keeps no copy of its measurements: only their count and the filter's samples.
        #expect(segment.measurementCount == 120 && segment.lastElapsedMs == all.last?.elapsedMs)
        let points = all.enumerated().map { index, value in
            SchoolCapturePoint(sequence: index, elapsedMs: value.elapsedMs, capturedAt: value.capturedAt,
                latitude: value.latitude, longitude: value.longitude, accuracyMeters: value.accuracyMeters)
        }
        #expect(segment.displaySamples.map(\.point) == SchoolCaptureDisplayRoute.select(points).map(\.point))
        #expect(SchoolCaptureMapSegment(id: UUID(), measurements: all).displaySamples.count == segment.displaySamples.count)
        #expect(zip(revisions, revisions.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func theReplayTimelineIsRebuiltAtMostOncePerIntervalWhileItLoads() {
        var pacer = SchoolReplayRebuildPacer(interval: .seconds(1))
        let start = ContinuousClock.now
        // `#expect` ne peut pas appeler une méthode mutante : les réponses sont relevées d’abord.
        let offsets: [Duration] = [.zero, .milliseconds(10), .milliseconds(999), .seconds(1), .milliseconds(1_500), .seconds(3)]
        var admitted: [Bool] = []
        for offset in offsets { admitted.append(pacer.admits(at: start.advanced(by: offset))) }
        #expect(admitted == [true, false, false, true, false, true])
    }

    // MARK: Live trace

    @Test @MainActor func theLiveTraceIsBuiltInChunksAndOnlyItsTailChanges() {
        let trace = SchoolLiveTrace()
        var segment = SchoolCaptureMapSegment(id: UUID(), measurements: [])
        func append(_ index: Int) {
            let point = fix(index, second: Double(index), east: Double(index) * 10)
            segment.appendDurable([.init(capturedAt: point.capturedAt, elapsedMs: point.elapsedMs, latitude: point.latitude,
                longitude: point.longitude, accuracyMeters: point.accuracyMeters)])
        }
        for index in 0..<450 { append(index) }
        trace.update([segment])
        let routes = trace.lines.filter { $0.style == .route }
        #expect(routes.count == 3)
        #expect(routes.allSatisfy { $0.coordinates.count <= SchoolLiveTrace.chunkSize + 1 })
        // Chunks share their joining vertex: the line has no hole.
        #expect(routes[0].coordinates.last?.longitude == routes[1].coordinates.first?.longitude)
        #expect(trace.position?.point.sequence == 449)
        #expect(trace.start?.longitude == 0)
        #expect(trace.coordinate(segmentID: segment.id, sequence: 200) != nil)

        let before = Dictionary(uniqueKeysWithValues: trace.lines.map { ($0.id, $0.revision) })
        trace.update([segment])
        #expect(Dictionary(uniqueKeysWithValues: trace.lines.map { ($0.id, $0.revision) }) == before)
        append(450)
        trace.update([segment])
        let changed = trace.lines.filter { before[$0.id] != $0.revision }
        #expect(changed.count == 1 && changed.first?.id == routes.last?.id)
        #expect(trace.position?.course.map { abs($0 - 90) < 1 } == true)
    }

    @Test @MainActor func aSilenceLeavesADashedConnectorAndNoSolidLineAcrossIt() {
        let trace = SchoolLiveTrace()
        var segment = SchoolCaptureMapSegment(id: UUID(), measurements: [])
        for (index, second, east) in [(0, 0.0, 0.0), (1, 1.0, 10.0), (2, 2.0, 20.0), (3, 40.0, 900.0), (4, 41.0, 910.0), (5, 42.0, 920.0)] {
            let point = fix(index, second: second, east: east)
            segment.appendDurable([.init(capturedAt: point.capturedAt, elapsedMs: point.elapsedMs, latitude: point.latitude,
                longitude: point.longitude, accuracyMeters: point.accuracyMeters)])
        }
        trace.update([segment])
        #expect(trace.hasGaps)
        #expect(trace.lines.filter { $0.style == .gap }.count == 1)
        #expect(trace.lines.filter { $0.style == .route }.map(\.coordinates.count) == [3, 3])
    }

    // MARK: Display motion

    @Test func theMarkerGlidesToEachFixAndNeverPastIt() throws {
        var glide = SchoolMapGlide()
        #expect(glide.position(at: 0) == nil && glide.isSettled(at: 0))
        glide.move(toLatitude: 0, longitude: 0, at: 10, instant: true)
        #expect(glide.position(at: 10)?.longitude == 0 && glide.isSettled(at: 10))
        glide.move(toLatitude: 0, longitude: 10 * Self.metre, at: 11)
        let leaving = try #require(glide.position(at: 11))
        #expect(leaving.longitude == 0)
        let halfway = try #require(glide.position(at: 11.5))
        #expect(halfway.longitude > 0 && halfway.longitude < 10 * Self.metre)
        // A late frame never overshoots the measured fix.
        #expect(glide.position(at: 30)?.longitude == 10 * Self.metre)
        #expect(glide.isSettled(at: 30) && !glide.isSettled(at: 11.5))
    }

    @Test func aNewFixRestartsFromTheDrawnPositionSoNoDelayAccumulates() throws {
        var glide = SchoolMapGlide()
        glide.move(toLatitude: 0, longitude: 0, at: 0, instant: true)
        var drawn = 0.0
        for second in 1...20 {
            let now = Double(second)
            let before = try #require(glide.position(at: now)).longitude
            glide.move(toLatitude: 0, longitude: Double(second) * 10 * Self.metre, at: now)
            let after = try #require(glide.position(at: now)).longitude
            // No jump at the instant a fix arrives, and never behind by more than about one fix.
            #expect(abs(after - before) < 1e-12)
            #expect(before >= drawn)
            #expect(Double(second - 1) * 10 * Self.metre - before < 12 * Self.metre)
            drawn = before
        }
    }

    @Test func aFarFixIsPlacedNotDraggedAcrossTheMap() {
        var glide = SchoolMapGlide()
        glide.move(toLatitude: 0, longitude: 0, at: 0, instant: true)
        glide.move(toLatitude: 0, longitude: 5_000 * Self.metre, at: 1)
        #expect(glide.position(at: 1)?.longitude == 5_000 * Self.metre)
    }

    @Test func headingTurnsAlongTheShortestArcWithoutSpinning() throws {
        var smoother = SchoolMapHeadingSmoother()
        let first = smoother.advance(towards: 350, at: 0)
        #expect(first == 350)
        var previous = 350.0
        for frame in 1...120 {
            let advanced = smoother.advance(towards: 10, at: Double(frame) / 60)
            let value = try #require(advanced)
            // Through north: never anywhere near the long way round.
            #expect(value >= 350 || value <= 10.0001)
            #expect(SchoolTrackGeometry.angleDelta(from: previous, to: value) >= -1e-9)
            previous = value
        }
        #expect(smoother.isSettled(on: 10))
        let cleared = smoother.advance(towards: nil, at: 3)
        #expect(cleared == nil)
        #expect(SchoolTrackGeometry.angleDelta(from: 10, to: 350) == -20)
        #expect(SchoolTrackGeometry.normalizedHeading(-90) == 270)
    }

    @Test func aCameraBlendEasesFromStartToTarget() {
        let blend = SchoolMapCameraBlend(startedAt: 5, duration: 0.6)
        #expect(blend.progress(at: 5) == 0 && blend.progress(at: 6) == 1)
        #expect(abs(blend.progress(at: 5.3) - 0.5) < 1e-9)
        #expect(SchoolMapCameraBlend(startedAt: 5, duration: 0).progress(at: 5) == 1)
    }

    // MARK: Replay reconstruction and interpolation

    @Test func theReplayPlayheadMovesContinuouslyBetweenMeasuredFixes() throws {
        let points = (0...10).map { fix($0, second: Double($0), east: Double($0) * 10) }
        let timeline = replay(points)
        // The measured layer is unchanged: a sample is still one original fix.
        #expect(timeline.sample(at: 2.5)?.coordinate.longitude == points[2].longitude)
        let place = try #require(timeline.position(at: 2.5))
        #expect(abs(place.longitude - 25 * Self.metre) < 1e-9)
        #expect(abs((place.heading ?? 0) - 90) < 0.5)
        // Exactly on a fix, the displayed position is the measurement.
        let onFix = try #require(timeline.position(at: 4))
        #expect(abs(onFix.longitude - points[4].longitude) < 1e-12)
        // Reduce Motion: fix to fix, no movement in between.
        let stepped = try #require(timeline.steppedPosition(at: 2.9))
        #expect(abs(stepped.longitude - points[2].longitude) < 1e-12)
    }

    @Test func aStopKeepsThePlayheadInPlaceInsteadOfHidingIt() throws {
        var points: [SchoolCapturePoint] = []
        for index in 0..<5 { points.append(fix(index, second: Double(index), east: Double(index) * 10)) }
        for index in 0..<40 {
            points.append(fix(5 + index, second: Double(5 + index), east: 40 + noise(index, 2), north: noise(index + 5, 2)))
        }
        for index in 0..<5 { points.append(fix(45 + index, second: Double(45 + index), east: 50 + Double(index) * 10)) }
        let timeline = replay(points)
        #expect(timeline.fragments.count == 1)
        #expect(timeline.gaps.isEmpty)
        let waiting = try #require(timeline.position(at: 25))
        #expect(abs(waiting.longitude - points[4].longitude) < 1e-12)
        // It leaves when the vehicle does, not before.
        let stillThere = try #require(timeline.position(at: 44))
        #expect(abs(stillThere.longitude - points[4].longitude) < 1e-12)
        let leaving = try #require(timeline.position(at: 44.5))
        #expect(leaving.longitude > points[4].longitude + Self.metre)
    }

    @Test func aGapStaysEmptyForTheInterpolatedPositionToo() {
        let points = [fix(0, second: 0, east: 0), fix(1, second: 1, east: 10), fix(2, second: 40, east: 900), fix(3, second: 41, east: 910)]
        let timeline = replay(points)
        #expect(timeline.position(at: 0.5) != nil)
        #expect(timeline.position(at: 20) == nil && timeline.sample(at: 20) == nil)
        #expect(timeline.position(at: 40.5) != nil)
        #expect(timeline.gaps.count == 1)
        #expect(timeline.mapLines.filter { $0.style == .gap }.count == 1)
    }

    @Test func aLongReplayIsPreparedOnceAndSoughtByBinarySearch() throws {
        let count = 6_000
        let points = (0..<count).map { fix($0, second: Double($0), east: Double($0) * 12, north: noise($0, 1)) }
        let timeline = replay(points)
        #expect(timeline.samples.count == count)
        #expect(timeline.paths.first?.vertexCount == count)
        // Any instant, forwards or backwards, in a few steps each.
        for step in stride(from: 0, to: 4_000, by: 1) {
            let offset = Double((step * 7919) % (count - 1)) + 0.37
            let place = try #require(timeline.position(at: offset))
            #expect(abs(place.longitude / Self.metre - offset * 12) < 0.5)
        }
    }

    @Test func observationsAreFoundByInstantWithoutScanningTheList() {
        let segment = UUID()
        let points = (0...60).map { fix($0, second: Double($0), east: Double($0) * 10) }
        func observation(_ second: Double) -> SchoolPrivateGeoObservation {
            SchoolPrivateGeoObservation(id: UUID(), schoolId: UUID(), version: 1, lessonId: UUID(), trainingId: UUID(), draftId: nil,
                captureId: UUID(), segmentId: segment, pointSequence: Int(second), competencyId: nil, text: "Repère synthétique",
                origin: "LIVE", observedAt: SchoolCaptureLocationTime.timestamp(Self.start.addingTimeInterval(second)),
                eventKind: "MARKER", eventStatus: nil, authorMembershipId: nil)
        }
        let observations = [observation(10), observation(30), observation(50)]
        let timeline = SchoolReplayTimeline(fragments: [.init(id: "synthetic", segmentID: segment, segmentIndex: 0, points: points,
            hasGapBefore: false, qualityLabel: "AVAILABLE")], observations: observations, startsAt: Self.start,
            endsAt: Self.start.addingTimeInterval(60))
        #expect(timeline.timedItems.count == 3)
        #expect(timeline.lastTimedItem(after: 0, upTo: 9.9) == nil)
        #expect(timeline.lastTimedItem(after: 9.9, upTo: 10)?.id == observations[0].id)
        #expect(timeline.lastTimedItem(after: 10, upTo: 55)?.id == observations[2].id)
        #expect(timeline.items.first?.coordinate?.longitude == points[10].longitude)
    }

    // MARK: Road-matched layer

    private func matchedRoute(segment: UUID, capture: UUID = UUID(), first: Int, last: Int, north: Double,
                              fromEast: Double, toEast: Double, anchors: [[Double]]) -> SchoolMatchedRoute {
        // Road 3 m north of the measured fixes. Encoded with the same algorithm the server uses.
        let geometry = Self.encode([(north * Self.metre, fromEast * Self.metre), (north * Self.metre, toEast * Self.metre)])
        return SchoolMatchedRoute(captureId: capture, status: "READY", spans: [.init(segmentId: segment, firstSequence: first,
            lastSequence: last, confidence: 0.9, geometry: geometry, anchors: anchors)])
    }

    private static func encode(_ line: [(Double, Double)]) -> String {
        var output = "", previous = (0, 0)
        func write(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : value << 1
            while v >= 0x20 { output.append(Character(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63)))); v >>= 5 }
            output.append(Character(UnicodeScalar(UInt8(v + 63))))
        }
        for (latitude, longitude) in line {
            let a = Int((latitude * 1e6).rounded()), b = Int((longitude * 1e6).rounded())
            write(a - previous.0); write(b - previous.1); previous = (a, b)
        }
        return output
    }

    @Test func aPolylineIsDecodedAndInvalidTextGivesNothing() {
        let known = SchoolEncodedPolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
        #expect(known.count == 3)
        #expect(abs(known[0].latitude - 38.5) < 1e-9 && abs(known[0].longitude + 120.2) < 1e-9)
        #expect(abs(known[2].latitude - 43.252) < 1e-9 && abs(known[2].longitude + 126.453) < 1e-9)
        let line = [(46.5191, 6.6323), (46.52, 6.63301), (-33.865143, 151.2099)]
        let decoded = SchoolEncodedPolyline.decode(Self.encode(line))
        #expect(decoded.count == 3 && abs(decoded[2].longitude - 151.2099) < 1e-6)
        #expect(SchoolEncodedPolyline.decode("\u{01}").isEmpty)
        #expect(SchoolEncodedPolyline.decode("_p~iF").isEmpty)
    }

    @Test func theMatchedRouteIsDrawnOnItsRoadWhileMeasurementsStayUntouched() throws {
        let segment = UUID()
        let points = (0...20).map { fix($0, second: Double($0), east: Double($0) * 10, north: noise($0, 2)) }
        let anchors = stride(from: 0, through: 20, by: 2).map { [Double($0), Double($0) * 10] }
        let matched = matchedRoute(segment: segment, first: 0, last: 20, north: 3, fromEast: 0, toEast: 200, anchors: anchors)
        let timeline = replay(points, segmentID: segment, matched: matched)
        #expect(timeline.usesMatchedRoute)
        // Layer 1 and 2: every measured fix is still there, unchanged.
        #expect(timeline.samples.map(\.coordinate.latitude) == points.map(\.latitude))
        // Layer 3: the drawn line is the road.
        #expect(timeline.paths.count == 1 && timeline.paths[0].vertexCount == 2)
        #expect(timeline.fragments[0].line.pointCount == 2)
        // Layer 4: the playhead travels along the road, in step with the measured instants.
        let place = try #require(timeline.position(at: 7))
        // The encoded geometry is rounded to a millionth of a degree.
        #expect(abs(place.latitude - 3 * Self.metre) < 1e-6)
        #expect(abs(place.longitude - 70 * Self.metre) < 0.5 * Self.metre)
    }

    @Test func onlyTheMatchedStretchLeavesTheMeasuredLine() throws {
        let segment = UUID()
        let points = (0...30).map { fix($0, second: Double($0), east: Double($0) * 10) }
        let anchors = stride(from: 10, through: 20, by: 2).map { [Double($0), Double($0 - 10) * 10] }
        let matched = matchedRoute(segment: segment, first: 10, last: 20, north: 3, fromEast: 100, toEast: 200, anchors: anchors)
        let timeline = replay(points, segmentID: segment, matched: matched)
        #expect(timeline.usesMatchedRoute && timeline.fragments.count == 1)
        // Ten measured vertices, the road, ten measured vertices: a parking or a private road stays as measured.
        #expect(timeline.paths[0].vertexCount == 22)
        let before = try #require(timeline.position(at: 5)), inside = try #require(timeline.position(at: 15))
        let after = try #require(timeline.position(at: 26))
        #expect(before.latitude == 0 && after.latitude == 0)
        #expect(abs(inside.latitude - 3 * Self.metre) < 1e-6)
        #expect(timeline.gaps.isEmpty)
    }

    @Test func anIncoherentMatchedRouteIsIgnoredAndTheMeasuredReplayStillWorks() {
        let segment = UUID()
        let points = (0...20).map { fix($0, second: Double($0), east: Double($0) * 10) }
        let unknownFix = matchedRoute(segment: segment, first: 0, last: 20, north: 3, fromEast: 0, toEast: 200,
                                      anchors: [[0, 0], [15, 150], [99, 200]])
        let acrossAGap = matchedRoute(segment: segment, first: 0, last: 400, north: 3, fromEast: 0, toEast: 200, anchors: [[0, 0], [400, 200]])
        let pending = SchoolMatchedRoute(captureId: UUID(), status: "PENDING", spans: [])
        let broken = SchoolMatchedRoute(captureId: UUID(), status: "READY", spans: [.init(segmentId: segment, firstSequence: 0,
            lastSequence: 20, confidence: 0.9, geometry: "\u{01}", anchors: [[0, 0], [20, 200]])])
        for matched in [unknownFix, acrossAGap, pending, broken] {
            let timeline = replay(points, segmentID: segment, matched: matched)
            #expect(!timeline.usesMatchedRoute)
            #expect(timeline.paths.first?.vertexCount == 21)
            #expect(timeline.position(at: 7)?.latitude == 0)
        }
        #expect(pending.isPending && !pending.isUsable)
    }

    // MARK: Smooth replay and predicted live marker

    @Test func aSlowVehicleRollsSteadilyInsteadOfStoppingAndJumping() throws {
        // Walking pace (0,8 m/s) with 1,5 m of noise: the display filter keeps one vertex every
        // few seconds. The playhead must still advance at every fix, never stand for seconds.
        let points = (0..<120).map { fix($0, second: Double($0), east: Double($0) * 0.8 + noise($0, 1.5), north: noise($0 + 9, 1.5)) }
        #expect(SchoolCaptureDisplayRoute.select(points).count < 60)
        let timeline = replay(points)
        var previous = try #require(timeline.position(at: 5)).longitude
        var longestStill = 0.0, still = 0.0
        for frame in 1...(100 * 60) {
            let place = try #require(timeline.position(at: 5 + Double(frame) / 60))
            #expect(place.longitude >= previous - 1e-12)
            if place.longitude - previous < 1e-9 { still += 1.0 / 60 } else { longestStill = max(longestStill, still); still = 0 }
            previous = place.longitude
        }
        #expect(longestStill < 1.0)
    }

    @Test func theSpeedChangesSmoothlyAcrossAFixAndStillReachesIt() throws {
        // 5 m/s then 15 m/s: linear interpolation snaps the speed at the joining fix.
        var east = 0.0
        let points = (0...20).map { index -> SchoolCapturePoint in
            defer { east += index < 10 ? 5 : 15 }
            return fix(index, second: Double(index), east: east)
        }
        let timeline = replay(points)
        func speed(_ t: Double) throws -> Double {
            let a = try #require(timeline.position(at: t - 0.01)), b = try #require(timeline.position(at: t + 0.01))
            return (b.longitude - a.longitude) / Self.metre / 0.02
        }
        // Either side of the fix, the speed differs by much less than the 10 m/s step.
        #expect(abs(try speed(10 - 0.02) - speed(10 + 0.02)) < 1)
        // Every measured instant is still exactly its fix.
        for index in [3, 10, 17] {
            #expect(abs(try #require(timeline.position(at: Double(index))).longitude - points[index].longitude) < 1e-9)
        }
    }

    @Test func theArrowLooksAheadAlongTheRoadInsteadOfFollowingEachWiggle() throws {
        // Eastward line with a 2 m zigzag at every vertex: each short edge points 20° off.
        let points = (0...40).map { fix($0, second: Double($0), east: Double($0) * 6, north: $0 % 2 == 0 ? 0 : 2) }
        let timeline = replay(points)
        for t in stride(from: 3.0, through: 35, by: 0.37) {
            let heading = try #require(timeline.position(at: t)?.heading)
            #expect(abs(SchoolTrackGeometry.angleDelta(from: 90, to: heading)) < 12)
        }
        let camera = try #require(timeline.heading(at: 20, lookAhead: 22))
        #expect(abs(SchoolTrackGeometry.angleDelta(from: 90, to: camera)) < 5)
    }

    @Test func theLiveMarkerRollsOnBetweenFixesThenWaits() throws {
        var predictor = SchoolMapPredictor()
        predictor.receive(latitude: 0, longitude: 0, speed: 10, course: 90, at: 0, instant: true)
        // Half a second later the car is drawn 5 m further east, not still on the fix.
        let rolling = try #require(predictor.position(at: 0.5))
        #expect(abs(rolling.longitude / Self.metre - 5) < 0.05)
        #expect(!predictor.isSettled(at: 0.5))
        // No fix for a while: the marker stops after the extrapolation limit.
        let held = try #require(predictor.position(at: 5)).longitude
        #expect(abs(held / Self.metre - 10 * SchoolMapPredictor.maximumExtrapolation) < 0.05)
        #expect(predictor.isSettled(at: 5))
    }

    @Test func aNewFixCorrectsTheLiveMarkerWithoutAJump() throws {
        var predictor = SchoolMapPredictor()
        predictor.receive(latitude: 0, longitude: 0, speed: 10, course: 90, at: 0, instant: true)
        let before = try #require(predictor.position(at: 1)).longitude
        // The fix lands 3 m behind the prediction: the marker does not jump back.
        predictor.receive(latitude: 0, longitude: 7 * Self.metre, speed: 10, course: 90, at: 1)
        let after = try #require(predictor.position(at: 1)).longitude
        #expect(abs(after - before) < 1e-9)
        // The correction fades: a second later the marker is where the fix predicts.
        let settled = try #require(predictor.position(at: 2)).longitude / Self.metre
        #expect(abs(settled - 17) < 0.5)
        // Stopped: GPS speed noise does not crawl the marker.
        predictor.receive(latitude: 0, longitude: 20 * Self.metre, speed: 0.3, course: 90, at: 3, instant: true)
        #expect(abs(try #require(predictor.position(at: 4)).longitude / Self.metre - 20) < 1e-6)
    }

    @Test func theLivePredictionCatchesUpTheStorageDelay() throws {
        var predictor = SchoolMapPredictor()
        // A fix taken 0,4 s ago at 10 m/s is drawn 4 m ahead of where it was measured.
        predictor.receive(latitude: 0, longitude: 0, speed: 10, course: 0, at: 10, measuredAt: 9.6, instant: true)
        #expect(abs(try #require(predictor.position(at: 10)).latitude / Self.metre - 4) < 0.05)
    }

    // MARK: Player

    @Test @MainActor func seekingIsImmediateAndPlaybackFollowsOneClock() throws {
        let player = SchoolReplayPlayer()
        let timeline = replay((0...100).map { fix($0, second: Double($0), east: Double($0) * 10) })
        var woken = 0
        player.wake = { woken += 1 }
        player.load(timeline)
        #expect(player.duration == 100 && player.offset == 0)
        player.seek(to: 42)
        #expect(player.offset == 42 && woken == 2)
        let now = CACurrentMediaTime()
        // Paused: the frame clock does not advance the replay.
        #expect(player.time(at: now + 10) == 42)
        let pose = try #require(player.pose(at: now))
        #expect(abs(pose.longitude - 420 * Self.metre) < 1e-9)
        player.seek(to: 500)
        #expect(player.offset == 100)
        player.seek(to: 10)
        player.play()
        #expect(player.isPlaying)
        let started = CACurrentMediaTime()
        #expect(abs(player.time(at: started + 2) - 12) < 0.05)
        player.cycleSpeed()
        #expect(player.speed == 2)
        let faster = CACurrentMediaTime()
        #expect(abs(player.time(at: faster + 2) - player.time(at: faster) - 4) < 0.001)
        player.pause()
        #expect(!player.isPlaying && player.offset >= 10 && player.offset < 11)
        // ×2, ×5, ×10, puis retour à la vitesse réelle.
        var cycle: [Int] = []
        for _ in 0..<3 { player.cycleSpeed(); cycle.append(player.speed) }
        #expect(cycle == [5, 10, 1])
        #expect(player.time(at: CACurrentMediaTime() + 60) == player.offset)
    }
}
