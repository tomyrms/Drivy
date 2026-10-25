import XCTest

final class MessagingOwnDevicesUITests: XCTestCase {
    @MainActor
    func testComparisonRequiredAndRefusedSignatureNeverShowsSuccess() {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["messages-entry"].waitForExistence(timeout: 10))
        app.buttons["messages-entry"].tap()
        app.buttons["messaging.settings.open"].tap()
        let open = app.buttons["messaging.devices.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.staticTexts["messaging.devices.localFingerprint"].waitForExistence(timeout: 5))
        let other = app.buttons["messaging.devices.device.FIXTUREOTHER"]
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()
        let confirm = app.buttons["messaging.devices.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled)
        app.buttons["messaging.devices.cancel"].tap()
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()
        let comparison = app.switches["messaging.devices.compared"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 5))
        comparison.tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.devices.error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["messaging.devices.verified"].exists)
    }
}
