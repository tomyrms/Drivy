import Foundation
import Testing
@testable import Drivy

/// Reprise d’une leçon après une fermeture, un crash ou un redémarrage : libellé, durée et tracé antérieur.
@MainActor
struct SchoolLessonRecoveryTests {
    @Test func aLessonWithATripOffersToContinueIt() {
        let lesson = HubFixture.lessonID
        #expect(!SchoolLessonHubRules.continuesTrip(captures: [], lessonID: lesson))
        #expect(SchoolLessonHubRules.startTripTitle(captures: [], lessonID: lesson) == "Démarrer le trajet")
        let interrupted = HubFixture.capture(authorizedAt: "2026-09-28T13:00:00Z", stoppedAt: nil, state: .authorized)
        #expect(SchoolLessonHubRules.continuesTrip(captures: [interrupted], lessonID: lesson))
        #expect(SchoolLessonHubRules.startTripTitle(captures: [interrupted], lessonID: lesson) == "Continuer le trajet")
        // Le trajet d’une autre leçon ne compte pas.
        let other = HubFixture.capture(authorizedAt: "2026-09-28T13:00:00Z", stoppedAt: nil, state: .stopped, lesson: UUID())
        #expect(SchoolLessonHubRules.startTripTitle(captures: [other], lessonID: lesson) == "Démarrer le trajet")
    }

    @Test func lessonDurationIsReadFromItsDurableStart() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(SchoolLessonElapsed.seconds(lessonStartedAt: start, now: start.addingTimeInterval(900)) == 900)
        // Heure de l’appareil en retard : jamais de durée négative.
        #expect(SchoolLessonElapsed.seconds(lessonStartedAt: start, now: start.addingTimeInterval(-30)) == 0)
        #expect(SchoolLessonElapsed.label(0) == "00:00")
        #expect(SchoolLessonElapsed.label(15 * 60 + 7) == "15:07")
        #expect(SchoolLessonElapsed.label(3_600 + 62) == "1:01:02")
    }

    @Test func priorTripsKeepTheirPointsAndOnlyAnchoredSignals() {
        let segment = UUID()
        let points = (0..<3).map { index in
            SchoolCapturePoint(sequence: index, elapsedMs: index * 5_000, capturedAt: "2026-09-28T13:00:\(String(format: "%02d", index * 5)).000Z",
                latitude: 46.52 + Double(index) * 0.001, longitude: 6.63, accuracyMeters: 5)
        }
        let anchored = observation(segment: segment, sequence: 2)
        let unanchored = observation(segment: segment, sequence: 9)
        let temporal = observation(segment: nil, sequence: nil)
        let prior = SchoolCapturePriorTrack.make([
            (segments: [points, []], observations: [anchored, unanchored, temporal],
             pointsByAnchor: ["\(segment.uuidString.lowercased()):2": points[2]])
        ])
        // Le fragment vide n’ajoute rien ; les trois positions mesurées sont gardées.
        #expect(prior.segments.count == 1)
        #expect(prior.segments.first?.measurementCount == 3)
        // Seul le signalement dont la position est affichée est placé ; les autres gardent leur heure, sans lieu.
        #expect(prior.observations.map(\.id) == [anchored.id])
        #expect(prior.observations.first?.latitude == points[2].latitude)
    }

    @Test func theCurrentPositionNeverComesFromAPreviousTrip() {
        let earlier = SchoolCaptureMapSegment(id: UUID(), measurements: [
            .init(capturedAt: "2026-09-28T13:00:00.000Z", elapsedMs: 0, latitude: 46.52, longitude: 6.63, accuracyMeters: 5),
            .init(capturedAt: "2026-09-28T13:00:05.000Z", elapsedMs: 5_000, latitude: 46.5202, longitude: 6.63, accuracyMeters: 5)
        ])
        let current = SchoolCaptureMapSegment(id: UUID(), measurements: [])
        let trace = SchoolLiveTrace()
        trace.update([earlier, current], liveFrom: 1)
        // Le départ réel de la leçon reste dessiné ; aucune position courante tant que ce trajet n’en a pas mesuré.
        #expect(trace.start != nil)
        #expect(trace.position == nil)
        #expect(!trace.lines.isEmpty)
        trace.update([earlier, current], liveFrom: 0)
        #expect(trace.position != nil)
    }

    private func observation(segment: UUID?, sequence: Int?) -> SchoolPrivateGeoObservation {
        SchoolPrivateGeoObservation(id: UUID(), schoolId: HubFixture.schoolID, version: 1, lessonId: HubFixture.lessonID,
            trainingId: UUID(), draftId: nil, captureId: segment == nil ? nil : UUID(), segmentId: segment, pointSequence: sequence,
            competencyId: nil, text: "Priorité", origin: "LIVE", observedAt: "2026-09-28T13:00:10.000Z", eventKind: "OBSERVATION",
            eventStatus: nil, authorMembershipId: nil)
    }
}
