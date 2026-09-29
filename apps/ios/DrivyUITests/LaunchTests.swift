import XCTest

/// Lancement réel : sans session, l’app ouvre la connexion. Aucun trajet local ni essai hors école n’est proposé.
@MainActor
final class LaunchTests: XCTestCase {
    func testLaunchOpensSignInWithoutLocalTrials() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Tes leçons, tes trajets, ton école."].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["open-local-trials"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "01-connexion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
