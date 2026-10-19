import Foundation
import Testing
@testable import Drivy

struct SchoolLearnersTripsV4Tests {
    @Test func tripFilterStateResetsToAllWhenScopeChanges() {
        var state = SchoolLearnerTripsFilterState(scopeKey: "school-a:membership-a:1")
        state.filter = .mine
        #expect(state.filter == .mine)

        state.updateScope("school-b:membership-b:2")

        #expect(state.scopeKey == "school-b:membership-b:2")
        #expect(state.filter == .all)
    }

    @Test func pickerDistinguishesBaseEmptyFilteredEmptyAndResultPresent() {
        #expect(SchoolLearnerPicker.EmptyState.baseEmpty.title == "Aucun élève")
        #expect(SchoolLearnerPicker.EmptyState.filteredEmpty.title == "Aucun élève trouvé")
        #expect(SchoolLearnerPicker.emptyState(learnersAreEmpty: true, hasResults: false, search: "") == .baseEmpty)
        #expect(SchoolLearnerPicker.emptyState(learnersAreEmpty: false, hasResults: false, search: "mar") == .filteredEmpty)
        #expect(SchoolLearnerPicker.emptyState(learnersAreEmpty: false, hasResults: true, search: "mar") == nil)
        #expect(SchoolLearnerPicker.emptyState(learnersAreEmpty: false, hasResults: true, search: "") == nil)
    }
}
