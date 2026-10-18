import XCTest

/// Parcours réel du guide avec dossier synthétique déjà renseigné et progression en mémoire.
@MainActor final class SchoolPersonalWelcomeTests: XCTestCase {
    func testKnownIdentityGoesToFormationAndReviewEditingReturnsToReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "onboarding-known-identity"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()

        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        start.tap()
        let next = app.buttons["onboarding-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Ta formation"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["profile-save"].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["GPS pendant les leçons"].waitForExistence(timeout: 10), app.debugDescription)
        next.tap()

        let complete = app.buttons["onboarding-complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(complete.isEnabled)
        let edit = app.buttons["onboarding-edit-information"]
        XCTAssertTrue(edit.exists && edit.isHittable, app.debugDescription)
        edit.tap()
        let backToReview = app.buttons["profile-save"]
        XCTAssertTrue(backToReview.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(backToReview.label, "Revenir")
        XCTAssertTrue(app.textFields["profile-first-name"].exists, app.debugDescription)
        backToReview.tap()

        XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(complete.isEnabled)
        XCTAssertFalse(app.buttons["onboarding-continue"].exists)
        XCTAssertFalse(app.buttons["onboarding-done"].exists)

        edit.tap()
        let firstName = app.textFields["profile-first-name"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 10), app.debugDescription)
        let originalName = firstName.value as? String ?? ""
        firstName.tap()
        firstName.typeText(" Synthétique")
        let editedName = firstName.value as? String
        XCTAssertNotEqual(editedName, originalName)
        app.buttons["onboarding-back"].tap()
        let discard = app.alerts["Revenir sans enregistrer tes informations ?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        discard.buttons["Continuer à modifier"].tap()
        XCTAssertEqual(firstName.value as? String, editedName)
        XCTAssertEqual(backToReview.label, "Enregistrer")
        app.buttons["onboarding-back"].tap()
        discard.buttons["Revenir sans enregistrer"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
        edit.tap()
        XCTAssertTrue(firstName.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(firstName.value as? String, originalName)
        backToReview.tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "personal-welcome-known-identity-review-synthetic"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
