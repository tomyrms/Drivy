import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolPresentationIdleTests {
    @Test func returnsAtOnceWhenNothingIsPresented() async {
        #expect(await SchoolPresentationIdle.wait(isPresenting: { false }, attempts: 3, pause: .milliseconds(1)))
    }

    @Test func waitsUntilThePresentedSheetCloses() async {
        var polls = 0
        let idle = await SchoolPresentationIdle.wait(isPresenting: { polls += 1; return polls < 4 }, attempts: 10, pause: .milliseconds(1))
        #expect(idle && polls == 4)
    }

    @Test func givesUpWhenTheSheetStaysOpen() async {
        var polls = 0
        let idle = await SchoolPresentationIdle.wait(isPresenting: { polls += 1; return true }, attempts: 3, pause: .milliseconds(1))
        #expect(!idle && polls == 4)
    }
}
