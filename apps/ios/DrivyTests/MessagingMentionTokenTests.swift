import XCTest
@testable import Drivy

final class MessagingMentionTokenTests: XCTestCase {
    struct P { let name: String }
    let people = [P(name: "Dylan Martin"), P(name: "Élodie Durand"), P(name: "Sam Leroy")]

    func testAtAloneListsEveryone() {
        XCTAssertEqual(MessagingMentionToken.query(in: "Salut @"), "")
        XCTAssertEqual(MessagingMentionToken.filter(people, query: "", name: \.name).count, 3)
    }

    func testPrefixFiltersCaseAndAccentInsensitive() {
        XCTAssertEqual(MessagingMentionToken.filter(people, query: "d", name: \.name).map(\.name), ["Dylan Martin", "Élodie Durand"])
        XCTAssertEqual(MessagingMentionToken.filter(people, query: "elo", name: \.name).map(\.name), ["Élodie Durand"])
    }

    func testNoTokenInsideWordOrAfterNewline() {
        XCTAssertNil(MessagingMentionToken.query(in: "mail@exemple"))
        XCTAssertNil(MessagingMentionToken.query(in: "@D\nsuite"))
        XCTAssertNil(MessagingMentionToken.query(in: "rien"))
        XCTAssertNil(MessagingMentionToken.query(in: "@ "))
    }

    func testReplacingInsertsNameAndKeepsPrefix() {
        XCTAssertEqual(MessagingMentionToken.replacing(in: "Bonjour @D", with: "Dylan Martin"), "Bonjour @Dylan Martin ")
        XCTAssertEqual(MessagingMentionToken.replacing(in: "@", with: "Sam Leroy"), "@Sam Leroy ")
        XCTAssertNil(MessagingMentionToken.replacing(in: "Bonjour", with: "Sam"))
    }

    func testInsertedMentionClosesSuggestions() {
        let inserted = MessagingMentionToken.replacing(in: "Bonjour @D", with: "Dylan Martin")!
        XCTAssertNil(MessagingMentionToken.query(in: inserted))
        XCTAssertEqual(MessagingMentionToken.query(in: "@Dylan M"), "Dylan M")
    }
}
