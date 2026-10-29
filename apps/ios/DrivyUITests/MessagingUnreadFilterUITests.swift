import XCTest

@MainActor
final class MessagingUnreadFilterUITests: XCTestCase {
    func testUnreadFilterKeepsUnknownAndSearchCanContinueToNextPage() {
        let app = XCUIApplication()
        app.launchArguments += ["-messaging-ui-fixture", "-messaging-ui-rich", "-messaging-ui-unread-filter"]
        app.launch()
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let filter = app.segmentedControls["messaging.inbox.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.buttons["Non lus"].tap()
        let lea = app.buttons["messaging.conversation.A0000000-0000-4000-8000-000000000002"]
        XCTAssertTrue(lea.waitForExistence(timeout: 5))
        XCTAssertTrue(lea.label.contains("État de lecture à vérifier"))
        XCTAssertFalse(app.buttons["messaging.general.open"].exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Marc")
        let partial = app.descendants(matching: .any)["messaging.unread.partial"].firstMatch
        XCTAssertTrue(partial.waitForExistence(timeout: 5))
        app.buttons["Charger d’autres conversations"].tap()
        let marc = app.buttons["messaging.conversation.A0000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(marc.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "Marc")
        XCTAssertTrue(filter.buttons["Non lus"].isSelected)
    }
}
