import Testing
@testable import Drivy

struct SchoolJoinPendingPresentationTests {
    @Test func missingReplyPanelWaitsForTheSendToEnd() {
        #expect(!SchoolJoinPendingPresentation.showsMissingReply(isPending: true, isBusy: true))
        #expect(SchoolJoinPendingPresentation.showsMissingReply(isPending: true, isBusy: false))
        #expect(!SchoolJoinPendingPresentation.showsMissingReply(isPending: false, isBusy: false))
        #expect(!SchoolJoinPendingPresentation.showsMissingReply(isPending: false, isBusy: true))
    }
}
