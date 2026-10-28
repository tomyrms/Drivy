import Foundation
import QuartzCore
import Testing
@testable import Drivy

@MainActor struct SchoolReplayReadingTests {
    @Test func manualSelectionPausesLongNoteUntilPlaybackResumes() throws {
        let start = Date(timeIntervalSince1970: 1_790_755_200)
        let note = String(repeating: "Revoir la prise d'information avant l'insertion. ", count: 12)
        let first = observation(at: start.addingTimeInterval(10), text: note)
        let next = observation(at: start.addingTimeInterval(20), text: "Observation suivante")
        let timeline = SchoolReplayTimeline(fragments: [], observations: [first, next], startsAt: start,
            endsAt: start.addingTimeInterval(60))
        let item = try #require(timeline.items.first { $0.id == first.id })
        let player = SchoolReplayPlayer()
        player.load(timeline)
        var selected: UUID?
        player.onCross = { selected = $0 }
        player.play()
        #expect(player.isPlaying)

        // Même point d'entrée que pastille, liste, repère et carte de la vue.
        selected = player.selectObservation(item)
        #expect(!player.isPlaying && player.offset == 10)
        player.publish(at: CACurrentMediaTime() + 120)
        #expect(selected == first.id && player.offset == 10)
        #expect(timeline.items.first { $0.id == selected }?.text == note)

        player.play()
        player.publish(at: CACurrentMediaTime() + 11)
        #expect(player.isPlaying && selected == next.id)
        player.pause()
    }

    private func observation(at date: Date, text: String) -> SchoolPrivateGeoObservation {
        SchoolPrivateGeoObservation(id: UUID(), schoolId: UUID(), version: 1, lessonId: UUID(), trainingId: UUID(),
            draftId: nil, captureId: UUID(), segmentId: nil, pointSequence: nil, competencyId: nil, text: text,
            origin: "LIVE", observedAt: SchoolCaptureLocationTime.timestamp(date), eventKind: "MARKER",
            eventStatus: nil, authorMembershipId: nil)
    }
}
