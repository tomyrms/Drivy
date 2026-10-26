import XCTest

@MainActor final class SchoolFormProtectionUITests: XCTestCase {
    func testProfileAsksOnlyAfterEditingAndContinueKeepsTheEntry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "profile"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        let close = app.buttons["my-profile-close"]
        let name = app.textFields["self-display-name"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(name.waitForExistence(timeout: 10), app.debugDescription)
        // Cette fixture présente le profil à la racine : le geste propre ne crée aucun dialogue.
        close.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        for _ in 0..<3 where !name.isHittable { app.swipeUp() }
        XCTAssertTrue(name.isHittable, app.debugDescription)
        name.tap(); name.typeText(" Test fermeture")
        close.tap()
        let stay = app.alerts.buttons.matching(identifier: "Continuer").firstMatch
        XCTAssertTrue(stay.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.alerts.buttons.matching(identifier: "Quitter sans enregistrer").firstMatch.exists)
        stay.tap()
        XCTAssertTrue((name.value as? String)?.contains("Test fermeture") == true)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Profil conservé après Continuer — données synthétiques"
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
