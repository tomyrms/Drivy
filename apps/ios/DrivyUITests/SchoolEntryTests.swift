import XCTest

/// Les vrais gardes d'entrée sont rendus avec une API fictive, sans ouverture d'un navigateur ni mot de passe.
@MainActor final class SchoolEntryTests: XCTestCase {
    func testDraftAdminAndOfficeAdminHaveAWebActionWithoutFieldTabs() {
        for (screen, action) in [("school-entry-draft-admin", "Continuer la préparation sur le web"),
                                 ("school-entry-management", "Ouvrir le portail web")] {
            let app = launch(screen)
            let portal = app.buttons["school-open-portal"]
            XCTAssertTrue(portal.waitForExistence(timeout: 20), app.debugDescription)
            XCTAssertEqual(portal.label, action)
            XCTAssertTrue(portal.isHittable)
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            XCTAssertFalse(app.buttons["onboarding-start"].exists)
            XCTAssertTrue(app.buttons["school-account"].exists)
            capture(app, name: screen)
            app.terminate()
        }
    }

    func testNonAdminDraftAndArchivedSchoolHaveNoPortalOrFieldActions() {
        for (screen, title) in [("school-entry-draft-member", "L’école se prépare"), ("school-entry-archived", "École archivée")] {
            let app = launch(screen)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 20), app.debugDescription)
            XCTAssertFalse(app.buttons["school-open-portal"].exists)
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            XCTAssertFalse(app.buttons["onboarding-start"].exists)
            XCTAssertTrue(app.buttons["school-entry-refresh"].isHittable)
            capture(app, name: screen)
            app.terminate()
        }
    }

    func testConfirmedActivationReplacesTheGuideWithInstructorTabs() {
        let app = launch("school-entry-resume")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["school-open-portal"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["school-entry-refresh"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["school-open-portal"].exists)
        XCTAssertTrue(app.tabBars.buttons["Élèves"].exists)
        capture(app, name: "school-entry-activated-instructor")
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
