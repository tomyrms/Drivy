import Foundation
import Testing
@testable import Drivy

/// Boîtes de l'onglet Élèves (#447, #449) : liste complète au-delà de huit lignes, relecture par contexte, panne locale, réponses tardives.
/// Les lectures du serveur sont retenues puis libérées à la main ; aucun réseau.
@MainActor struct SchoolBoxesRefreshTests {
    /// Une lecture retenue : la réponse n'arrive que quand le test la libère.
    private actor Gate {
        private var continuation: CheckedContinuation<[Int], Error>?
        private var released: Result<[Int], Error>?
        func wait() async throws -> [Int] {
            if let released { return try released.get() }
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        func release(_ result: Result<[Int], Error>) {
            if let continuation { continuation.resume(with: result); self.continuation = nil } else { released = result }
        }
    }

    private func reading() -> SchoolBoxReading<Int> { SchoolBoxReading<Int>() }

    // MARK: Liste complète

    @Test func zeroToEightRowsNeverOfferAnExpansion() {
        for count in 0...8 {
            let items = Array(0..<count)
            #expect(!SchoolBoxExpansion.canExpand(count))
            #expect(SchoolBoxExpansion.visible(items, expanded: false).count == count)
            #expect(SchoolBoxExpansion.hiddenCount(count, expanded: false) == 0)
        }
    }

    @Test func nineAndTwentyRowsAreAllReachableOnceExpandedInOrder() {
        for count in [9, 20] {
            let items = Array(0..<count)
            #expect(SchoolBoxExpansion.canExpand(count))
            #expect(Array(SchoolBoxExpansion.visible(items, expanded: false)) == Array(0..<8))
            #expect(SchoolBoxExpansion.hiddenCount(count, expanded: false) == count - 8)
            #expect(Array(SchoolBoxExpansion.visible(items, expanded: true)) == items)
            #expect(SchoolBoxExpansion.hiddenCount(count, expanded: true) == 0)
        }
    }

    // MARK: Relecture, panne et contexte

    @Test func aReloadShowsAdditionsAndRemovalsMadeElsewhere() async {
        let box = reading()
        await box.load(context: "a", failure: "x") { [1, 2, 3] }
        #expect(box.items == [1, 2, 3])
        await box.load(context: "a", failure: "x") { [2, 3, 4, 5] }
        #expect(box.items == [2, 3, 4, 5] && box.errorMessage == nil)
        await box.load(context: "a", failure: "x") { [] }
        #expect(box.items.isEmpty && box.errorMessage == nil)
    }

    @Test func aFailureKeepsThePreviousReadingAndSaysSoUntilItWorksAgain() async {
        let box = reading()
        await box.load(context: "a", failure: "Panne") { [1, 2] }
        await box.load(context: "a", failure: "Panne") { throw SchoolPlanningFailure.unavailable }
        #expect(box.items == [1, 2])
        #expect(box.errorMessage == "Panne")
        await box.load(context: "a", failure: "Panne") { [1, 2, 3] }
        #expect(box.items == [1, 2, 3] && box.errorMessage == nil)
    }

    @Test func oneSectionFailingDoesNotStopTheOtherFromRefreshing() async {
        let requests = reading(), exams = reading()
        await requests.load(context: "a", failure: "R") { [1] }
        await exams.load(context: "a", failure: "E") { [9] }
        async let first: Void = requests.load(context: "a", failure: "R") { throw SchoolPlanningFailure.unavailable }
        async let second: Void = exams.load(context: "a", failure: "E") { [9, 10] }
        _ = await (first, second)
        #expect(requests.items == [1] && requests.errorMessage == "R")
        #expect(exams.items == [9, 10] && exams.errorMessage == nil)
    }

    @Test func lostAccessPurgesWhatWasReadBeforeInsteadOfKeepingIt() async {
        for failure in [SchoolPlanningFailure.forbidden, .notFound, .unauthorized] {
            let box = reading()
            await box.load(context: "a", failure: "Accès") { [1, 2] }
            await box.load(context: "a", failure: "Accès") { throw failure }
            #expect(box.items.isEmpty)
            #expect(box.errorMessage == "Accès")
        }
    }

    @Test func aNewContextDropsTheOldReadingBeforeItsOwnAnswerAndWithoutAClient() async {
        let box = reading()
        await box.load(context: "école A", failure: "x") { [1, 2] }
        await box.load(context: "école B", failure: "x", fetch: nil)
        #expect(box.items.isEmpty && box.errorMessage == nil)
    }

    @Test func aLateAnswerFromAnOlderContextIsIgnored() async {
        let box = reading()
        let slow = Gate()
        let late = Task { await box.load(context: "compte A", failure: "x") { try await slow.wait() } }
        while !box.isLoading { await Task.yield() }
        await box.load(context: "compte B", failure: "x") { [7] }
        #expect(box.items == [7])
        await slow.release(.success([1, 2, 3]))
        await late.value
        #expect(box.items == [7] && box.errorMessage == nil)
    }

    @Test func aLateFailureFromAnOlderContextDoesNotMarkTheNewOneAsFailed() async {
        let box = reading()
        let slow = Gate()
        let late = Task { await box.load(context: "école A", failure: "x") { try await slow.wait() } }
        while !box.isLoading { await Task.yield() }
        await box.load(context: "école B", failure: "x") { [7] }
        await slow.release(.failure(SchoolPlanningFailure.forbidden))
        await late.value
        #expect(box.items == [7] && box.errorMessage == nil)
    }

    @Test func anOlderAnswerArrivingAfterANewerReloadOfTheSameContextIsIgnored() async {
        let box = reading()
        let slow = Gate()
        let older = Task { await box.load(context: "a", failure: "x") { try await slow.wait() } }
        while !box.isLoading { await Task.yield() }
        await box.load(context: "a", failure: "x") { [5, 6] }
        await slow.release(.success([1]))
        await older.value
        #expect(box.items == [5, 6])
    }

    @Test func aConfirmedTreatmentAsksForOneReadingNotAPoll() {
        let signal = SchoolBoxesSignal()
        let before = signal.revision
        signal.settled()
        #expect(signal.revision == before + 1)
    }
}
