import XCTest
@testable import Drivy

final class MessagingActiveConversationTests: XCTestCase {
    func testSuppressesOnlyActiveConversationAtBottom() {
        let school = UUID(), conversation = UUID(), other = UUID()
        func info(_ c: UUID, kind: String = "MESSAGING") -> [AnyHashable: Any] { ["kind": kind, "schoolId": school.uuidString.lowercased(), "conversationId": c.uuidString.lowercased()] }
        let bottom = MessagingActiveConversation.State(schoolID: school, conversationID: conversation, atBottom: true)
        XCTAssertTrue(MessagingActiveConversation.suppresses(info(conversation), state: bottom))
        XCTAssertFalse(MessagingActiveConversation.suppresses(info(other), state: bottom))
        XCTAssertFalse(MessagingActiveConversation.suppresses(info(conversation, kind: "COURSE"), state: bottom))
        XCTAssertFalse(MessagingActiveConversation.suppresses(info(conversation), state: nil))
        let reading = MessagingActiveConversation.State(schoolID: school, conversationID: conversation, atBottom: false)
        XCTAssertFalse(MessagingActiveConversation.suppresses(info(conversation), state: reading))
    }
}
