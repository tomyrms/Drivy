import XCTest

/// Les mêmes textes scolaires sont consultables pendant l’accueil et depuis le dossier, sans mutation.
@MainActor final class SchoolPrivacyTests: XCTestCase {
    func testSchoolTextsOpenAndCloseFromThePersonalWelcomeAndBothProfilePerspectives() {
        continueAfterFailure = false
        for (screen, identifier, title) in [
            ("onboarding-information", "onboarding-privacy-link", "Tes données"),
            ("profile", "profile-privacy-link", "Tes données"),
            ("profile-instructor", "profile-privacy-link", "Confidentialité")
        ] {
            let app = XCUIApplication()
            app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
            app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
            app.launch()
            let link = app.buttons[identifier]
            // Le formulaire du dossier peut virtualiser les dernières lignes sur iPhone.
            for _ in 0..<6 where !link.waitForExistence(timeout: 3) || !link.isHittable { app.swipeUp() }
            XCTAssertTrue(link.exists && link.isHittable, app.debugDescription)
            XCTAssertEqual(link.label, title)
            XCTAssertFalse(app.buttons["profile-save"].exists)
            link.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(app.staticTexts["Notice fictive : l’école utilise ces informations pour préparer les leçons."].exists)
            XCTAssertTrue(app.staticTexts["La durée de conservation est fixée par l’école."].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(screen)-privacy-synthetic"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.navigationBars[title].buttons["Fermer"].tap()
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["profile-save"].exists)
            if screen == "onboarding-information" {
                XCTAssertTrue(app.staticTexts["Tes informations"].exists)
            }
            app.terminate()
        }
    }
}
