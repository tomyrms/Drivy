import XCTest

/// Les destinations déplacées restent accessibles depuis leur vrai écran parent.
@MainActor final class NativeNavigationTests: XCTestCase {
    func testProfileOpensLessonsAndReturnsToAccount() {
        let app = launch("profile-tab")
        let trips = app.descendants(matching: .any)["profile-open-lessons"]
        XCTAssertTrue(trips.waitForExistence(timeout: 20), app.debugDescription)
        trips.tap()
        let list = app.descendants(matching: .any)["lessons-history"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)
        let back = app.navigationBars["Leçons"].buttons.firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(trips.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-planning-settings"].exists)
        let resume = app.buttons["resume-school-onboarding"]
        XCTAssertTrue(resume.exists)
        resume.tap()
        XCTAssertTrue(app.buttons["onboarding-start"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["onboarding-later"].exists)
    }

    func testObservationListShowsEachStatusWithoutGPS() {
        let app = launch("observations")
        for text in ["Priorité à droite · regard tardif", "Stationnement · contrôle de l’angle mort", "Insertion · bonne anticipation"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text))
                .firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        }
        for status in ["À retravailler", "Attention", "Point positif"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", status))
                .firstMatch.exists, app.debugDescription)
        }
        XCTAssertFalse(app.staticTexts["Aucune observation"].exists)
    }

    func testOpeningALearnerShowsItsProfileThenLessonsAndProgressionInPlace() {
        let app = launch("learners")
        let learner = app.descendants(matching: .any).matching(identifier: "school-learner-10000000-0000-4000-8000-000000000004").firstMatch
        XCTAssertTrue(learner.waitForExistence(timeout: 20), app.debugDescription)
        learner.tap()
        let dossier = app.scrollViews["learner-dossier"]
        XCTAssertTrue(dossier.waitForExistence(timeout: 30), app.debugDescription)
        let firstName = app.descendants(matching: .any)["learner-profile-first-name"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(firstName.label.contains("Camille"), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["learner-profile-email"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dossier-section"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["learner-start-now"].exists)
        XCTAssertTrue(app.buttons["learner-plan-lesson"].exists)
        // Leçons et Progression changent le contenu en place : l’identité de l’élève reste à l’écran.
        XCTAssertTrue(app.descendants(matching: .any)["training-lessons-menu"].waitForExistence(timeout: 20), app.debugDescription)
        let progression = app.segmentedControls.buttons["Progression"]
        XCTAssertTrue(progression.waitForExistence(timeout: 10), app.debugDescription)
        progression.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Avec accompagnement"))
            .firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(dossier.exists, app.debugDescription)
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }
}
