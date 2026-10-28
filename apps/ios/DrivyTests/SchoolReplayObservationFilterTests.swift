import CoreLocation
import Foundation
import Testing
@testable import Drivy

/// Filtre des observations du replay (#236) : il ne porte que sur elles.
struct SchoolReplayObservationFilterTests {
    private let items = [
        SchoolReplayTimeline.Item(id: UUID(), offset: 10, coordinate: nil, status: .attention, isMarker: false, text: "Priorité à droite"),
        SchoolReplayTimeline.Item(id: UUID(), offset: 20, coordinate: nil, status: .positive, isMarker: false, text: "Giratoire fluide"),
        SchoolReplayTimeline.Item(id: UUID(), offset: 30, coordinate: nil, status: nil, isMarker: true, text: "Revoir l’insertion sur l’autoroute"),
        SchoolReplayTimeline.Item(id: UUID(), offset: nil, coordinate: nil, status: nil, isMarker: false, text: "Note sans heure"),
    ]

    @Test func inactiveFilterKeepsEveryObservationInOrder() {
        let filter = SchoolReplayObservationFilter()
        #expect(!filter.isActive)
        #expect(filter.apply(items).map(\.id) == items.map(\.id))
        #expect(!SchoolReplayObservationFilter(query: "   ").isActive)
    }

    @Test func searchIgnoresCaseAndAccentsAndReadsTheMarkerNote() {
        #expect(SchoolReplayObservationFilter(query: "PRIORITE").apply(items).map(\.id) == [items[0].id])
        #expect(SchoolReplayObservationFilter(query: "autoroute").apply(items).map(\.id) == [items[2].id])
        #expect(SchoolReplayObservationFilter(query: "positif").apply(items).map(\.id) == [items[1].id])
        #expect(SchoolReplayObservationFilter(query: "introuvable").apply(items).isEmpty)
    }

    @Test func kindsCombineWithTheSearchAndOnlyListWhatTheTripHas() {
        let kinds = SchoolReplayObservationFilter(kinds: [.attention, .moment])
        #expect(kinds.apply(items).map(\.id) == [items[0].id, items[2].id])
        #expect(SchoolReplayObservationFilter(query: "revoir", kinds: [.attention]).apply(items).isEmpty)
        let present = SchoolReplayObservationFilter.kinds(in: items)
        #expect(present.map { $0.kind } == [.attention, .positive, .moment, .note])
        #expect(present.allSatisfy { $0.count == 1 })
    }
}
