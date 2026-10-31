import XCTest
@testable import Drivy

@MainActor
final class MessagingSendPresentationTests: XCTestCase {
    func testUnknownOutcomeNeverLooksLikeAnActiveSendOrARefusal() {
        let pending = MessagingSendPresentation(status: .unconfirmed)
        let uncertain = MessagingSendPresentation(status: .uncertain)
        let refused = MessagingSendPresentation(status: .failed(.accessChanged))
        for presentation in [pending, uncertain] {
            XCTAssertFalse(presentation.showsSendingIndicator)
            XCTAssertFalse(presentation.isAccepted)
            XCTAssertNil(presentation.failure)
            XCTAssertNotEqual(presentation.symbol, refused.symbol)
            XCTAssertTrue(presentation.accessibilityLabel.contains("non confirmé"))
        }
        XCTAssertFalse(pending.canRetry, "Une réponse lente ne justifie pas une seconde requête en vol")
        XCTAssertTrue(uncertain.canRetry, "La réponse perdue terminée autorise la reprise de la même intention")
    }

    func testRetryPolicyKeepsRefusalsRequiringACorrectionOutOfEveryAction() {
        for failure in [MessagingFailure.accessChanged, .contextChanged, .protectionUnavailable,
                        .conversationUnavailable, .deviceLimitReached] {
            let presentation = MessagingSendPresentation(status: .failed(failure))
            XCTAssertFalse(presentation.canRetry)
            XCTAssertEqual(presentation.failure, failure)
            XCTAssertFalse(presentation.isAccepted)
        }
        XCTAssertTrue(MessagingSendPresentation(status: .failed(.stateConflict)).canRetry)
    }

    func testOnlyAnAcknowledgementShowsSuccessAndOnlyInFlightShowsSending() {
        let waiting: [MessagingWorkspace.SendStatus?] = [nil, .queued, .offline, .unconfirmed, .uncertain]
        for state in waiting {
            let presentation = MessagingSendPresentation(status: state)
            XCTAssertFalse(presentation.showsSendingIndicator)
            XCTAssertFalse(presentation.isAccepted)
            XCTAssertNotNil(presentation.label)
        }
        XCTAssertTrue(MessagingSendPresentation(status: .sending).showsSendingIndicator)
        XCTAssertTrue(MessagingSendPresentation(status: .slow).showsSendingIndicator)
        let accepted = MessagingSendPresentation(status: .accepted(serverMessageID: UUID()))
        XCTAssertTrue(accepted.isAccepted)
        XCTAssertFalse(accepted.canRetry)
    }
}
