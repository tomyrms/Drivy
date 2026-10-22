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
            assertNoFieldActions(app)
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
            assertNoFieldActions(app)
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
        // Sur iPad, le TabView adaptatif expose ses onglets comme des boutons sans élément XCUI TabBar.
        let learners = app.buttons.matching(identifier: "Élèves").firstMatch
        XCTAssertTrue(learners.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(learners.isHittable)
        XCTAssertTrue(app.buttons.matching(identifier: "Aujourd’hui").firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "Profil").firstMatch.exists)
        XCTAssertFalse(app.buttons["school-open-portal"].exists)
        learners.tap()
        XCTAssertTrue(app.staticTexts["Aucun élève"].waitForExistence(timeout: 10), app.debugDescription)
        capture(app, name: "school-entry-activated-instructor")
    }

    func testAdminLearnerFindsOwnDossierBeyondTheFirstDirectoryPage() {
        let app = launch("school-entry-learner-admin")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Aucune formation"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Dossier pas encore ouvert"].exists)
        XCTAssertTrue(app.buttons.matching(identifier: "Leçons").firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "Progression").firstMatch.exists)
        XCTAssertFalse(app.buttons["school-open-portal"].exists)
        let profile = app.buttons.matching(identifier: "Profil").firstMatch
        XCTAssertTrue(profile.isHittable)
        profile.tap()
        XCTAssertTrue(app.buttons["profile-open-my-profile"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["profile-no-permit"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["profile-no-permit"].label, "Aucune formation pour l’instant.")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "account-heading").firstMatch.label.contains("Responsable exemple"))
        XCTAssertFalse(app.staticTexts["Autre élève 1"].exists)
        capture(app, name: "school-entry-admin-learner-personal-dossier")
    }

    private func assertNoFieldActions(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for title in ["Aujourd’hui", "Agenda", "Élèves"] {
            XCTAssertFalse(app.buttons.matching(identifier: title).firstMatch.exists, file: file, line: line)
        }
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
