import XCTest

@MainActor final class SchoolAccountRecoveryUITests: XCTestCase {
    func testUnconfiguredRecoveryExplainsTheAbsenceOfEmailAndReturnsToSignIn() {
        continueAfterFailure = false
        let app = launch("sign-in")
        let forgot = app.buttons["school-forgot-password"]
        XCTAssertTrue(forgot.waitForExistence(timeout: 15), app.debugDescription)
        forgot.tap()
        let unavailable = app.descendants(matching: .any)["account-recovery-unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["account-recovery-open"].exists)
        XCTAssertFalse(app.buttons["school-error-retry"].exists)
        XCTAssertFalse(app.staticTexts["E-mail envoyé"].exists)
        capture(app, "Récupération indisponible — données synthétiques")
        app.buttons["account-recovery-return"].tap()
        XCTAssertTrue(forgot.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["school-sign-in"].exists)
    }

    func testTemporaryRecoveryFailureKeepsRetryWithoutInventingConfigurationOrEmail() {
        continueAfterFailure = false
        let app = launch("sign-in-recovery-error")
        let forgot = app.buttons["school-forgot-password"]
        XCTAssertTrue(forgot.waitForExistence(timeout: 15), app.debugDescription)
        forgot.tap()
        XCTAssertTrue(app.descendants(matching: .any)["account-recovery-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["school-error-retry"].exists)
        XCTAssertFalse(app.buttons["account-recovery-return"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["account-recovery-unavailable"].exists)
        XCTAssertFalse(app.buttons["account-recovery-open"].exists)
        XCTAssertFalse(app.staticTexts["E-mail envoyé"].exists)
        app.buttons["Fermer"].tap()
        XCTAssertTrue(forgot.waitForExistence(timeout: 5))
    }

    func testConfiguredRecoveryOffersTheBrowserWithoutClaimingAnEmailWasSent() {
        continueAfterFailure = false
        let app = launch("sign-in-recovery-ready")
        let forgot = app.buttons["school-forgot-password"]
        XCTAssertTrue(forgot.waitForExistence(timeout: 15), app.debugDescription)
        forgot.tap()
        let open = app.buttons["account-recovery-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(open.isHittable)
        XCTAssertFalse(app.descendants(matching: .any)["account-recovery-unavailable"].exists)
        XCTAssertFalse(app.staticTexts["E-mail envoyé"].exists)
        capture(app, "Entrée récupération — données synthétiques")
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
