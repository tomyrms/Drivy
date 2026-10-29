import XCTest

@MainActor final class SchoolSignInFeedbackUITests: XCTestCase {
    func testNetworkFailureStaysAtFormLevelWhenTheEmailChanges() {
        let app = launch("sign-in-network-error")
        let notice = app.descendants(matching: .any)["school-sign-in-error"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15))
        let email = app.textFields["school-sign-in-email"]
        email.tap(); email.typeText("camille@example.test")
        XCTAssertTrue(notice.exists)
        XCTAssertTrue(app.staticTexts["La connexion n’a pas abouti. Vérifie le réseau puis réessaie."].exists)
        XCTAssertEqual(app.secureTextFields["school-sign-in-password"].label, "Mot de passe")
    }

    func testCredentialFailureCanBeClearedByCorrectingTheEmail() {
        let app = launch("sign-in-error")
        let notice = app.descendants(matching: .any)["school-sign-in-error"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15))
        let email = app.textFields["school-sign-in-email"]
        email.tap(); email.typeText("camille@example.test")
        XCTAssertFalse(notice.exists)
        XCTAssertFalse(app.staticTexts["E-mail ou mot de passe incorrect."].exists)
    }

    func testRateLimitDoesNotDisappearWhenThePasswordChanges() {
        let app = launch("sign-in-attempts")
        let notice = app.descendants(matching: .any)["school-sign-in-error"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15))
        let password = app.secureTextFields["school-sign-in-password"]
        password.tap(); password.typeText("synthetic-password")
        XCTAssertTrue(notice.exists)
        XCTAssertTrue(app.staticTexts["Trop d’essais de connexion. Patiente quelques minutes avant de réessayer."].exists)
        XCTAssertFalse(app.staticTexts["E-mail ou mot de passe incorrect."].exists)
    }

    func testIncompleteEmailIsExplainedAfterLeavingItsFieldAndClearsWhenCorrected() {
        let app = launch("sign-in")
        let email = app.textFields["school-sign-in-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        XCTAssertFalse(message("Complète ton adresse e-mail avec @.", in: app).exists)
        email.tap(); email.typeText("camille")
        let password = app.secureTextFields["school-sign-in-password"]
        password.tap()
        XCTAssertTrue(message("Complète ton adresse e-mail avec @.", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["school-sign-in"].isEnabled)
        email.tap(); email.typeText("@example.test")
        XCTAssertFalse(message("Complète ton adresse e-mail avec @.", in: app).exists)
        XCTAssertTrue(message("Saisis ton mot de passe.", in: app).waitForExistence(timeout: 5))
        password.tap(); password.typeText("x")
        XCTAssertTrue(app.buttons["school-sign-in"].isEnabled)
    }

    private func message(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func launch(_ screen: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }
}
