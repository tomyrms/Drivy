import XCTest
@testable import Drivy

final class MessagingInboxFilterTests: XCTestCase {
    func testUnknownCounterIsNeverClassifiedAsReadOrUnread() {
        XCTAssertEqual(MessagingInboxReadCategory(serverUnreadCount: nil), .unknown)
        XCTAssertEqual(MessagingInboxReadCategory(serverUnreadCount: -1), .unknown)
        XCTAssertEqual(MessagingInboxReadCategory(serverUnreadCount: 0), .read)
        XCTAssertEqual(MessagingInboxReadCategory(serverUnreadCount: 2), .unread)
        XCTAssertTrue(MessagingInboxFilter.unread.includes(serverUnreadCount: nil))
        XCTAssertFalse(MessagingInboxFilter.unread.includes(serverUnreadCount: 0))
        XCTAssertTrue(MessagingInboxFilter.all.includes(serverUnreadCount: 0))
    }

    func testSearchComposesWithServerCounterForGeneralPrivateAndUnknown() {
        let rows: [(title: String, preview: String?, count: Int?)] = [
            ("Général", "Leçon demain", 0), ("Léa", "La leçon", 3), ("Marc", "La leçon", nil),
            ("Autre", "Bonjour", 1)
        ]
        let selected = rows.filter {
            MessagingInboxFilter.unread.includes(serverUnreadCount: $0.count)
                && MessagingInboxFilter.matches(query: " LECON ", title: $0.title, preview: $0.preview)
        }
        XCTAssertEqual(selected.map(\.title), ["Léa", "Marc"])
        XCTAssertTrue(MessagingInboxFilter.matches(query: "general", title: "Général", preview: nil))
        XCTAssertTrue(MessagingInboxFilter.matches(query: "  ", title: "Léa", preview: nil))
    }
}
