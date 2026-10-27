import Foundation
import XCTest
@testable import Drivy

/// #103 : nettoyage ciblé des alertes et compteurs après lecture confirmée.
final class MessagingReadNotificationTests: XCTestCase {
    private let school = UUID(), conversation = UUID(), other = UUID(), me = UUID(), peer = UUID()

    private func info(_ school: UUID, _ conversation: UUID, _ sequence: Int, kind: String = "MESSAGING") -> [AnyHashable: Any] {
        ["kind": kind, "schoolId": school.uuidString.lowercased(), "conversationId": conversation.uuidString.lowercased(), "sequence": sequence]
    }

    func testRemovesOnlyThisConversationUpToConfirmedSequence() {
        let delivered: [(String, [AnyHashable: Any])] = [
            ("a", info(school, conversation, 3)),
            ("b", info(school, conversation, 5)),
            ("later", info(school, conversation, 6)),
            ("other", info(school, other, 2)),
            ("otherSchool", info(UUID(), conversation, 2)),
            ("course", ["seriesId": UUID().uuidString, "category": "COURSE"]),
            ("noSeq", ["kind": "MESSAGING", "schoolId": school.uuidString, "conversationId": conversation.uuidString]),
        ]
        let ids = SystemMessagingNotifications.identifiersToRemove(delivered, schoolID: school, conversationID: conversation, upTo: 5)
        XCTAssertEqual(ids, ["a", "b"])
    }

    func testUnreadAfterReadIgnoresOwnMessagesAndClearsAtEnd() {
        func message(_ seq: Int, from sender: UUID) -> MessagingWireMessage {
            MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: sender,
                                 acceptedAt: Date(), ciphertext: nil, meta: MessagingMessageMeta(sequence: seq))
        }
        let loaded = [message(1, from: peer), message(2, from: peer), message(3, from: me), message(4, from: peer)]
        XCTAssertEqual(MessagingWorkspace.unreadAfterRead(lastSequence: 4, readSequence: 4, serverUnread: 3, loaded: loaded, accountID: me), 0)
        XCTAssertEqual(MessagingWorkspace.unreadAfterRead(lastSequence: 4, readSequence: 2, serverUnread: 3, loaded: loaded, accountID: me), 1)
        XCTAssertEqual(MessagingWorkspace.unreadAfterRead(lastSequence: 4, readSequence: 0, serverUnread: 2, loaded: loaded, accountID: me), 2)
    }

    func testBadgeKeepsOtherSources() async {
        let badge = DrivyBadge()
        _ = await badge.set(.other("courses"), 2)
        let total = await badge.set(.messaging, 3)
        XCTAssertEqual(total, 5)
        let cleared = await badge.set(.messaging, 0)
        XCTAssertEqual(cleared, 2)
    }
}
