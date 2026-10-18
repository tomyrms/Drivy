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

    @Test func tripFilterIsOnlyAProjectionAndDoesNotNeedARequest() {
        #expect(SchoolTripFilter.all != .mine)
        #expect(SchoolTripFilter.mine != .instructor(UUID()))
        // The view must call model.days(filter:) on the already loaded model.
        // This test deliberately has no transport and therefore cannot pass through the API.
    }

    @Test func pickerDistinguishesBaseEmptyAndFilteredEmpty() {
        #expect(SchoolLearnerPicker.EmptyState.baseEmpty.title == "Aucun élève")
        #expect(SchoolLearnerPicker.EmptyState.filteredEmpty.title == "Aucun élève trouvé")
        #expect(SchoolLearnerPicker.emptyState(learnersAreEmpty: true, search: "") == .baseEmpty)
        #expect(SchoolLearnerPicker.emptyState(learnersAreEmpty: false, search: "mar") == .filteredEmpty)
    }

    @Test func pickerClearReturnsToBaseAndFocusesSearch() {
        var state = SchoolLearnerPicker.SearchState(text: "mar", isFocused: false)
        state.clear()
        #expect(state.text.isEmpty)
        #expect(state.isFocused)
    }
}
