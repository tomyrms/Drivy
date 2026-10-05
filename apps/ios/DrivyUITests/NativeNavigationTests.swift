import XCTest

/// Les destinations déplacées restent accessibles depuis leur vrai écran parent.
@MainActor final class NativeNavigationTests: XCTestCase {
    func testProfileOpensTripsAndReturnsToAccount() {
        let app = launch("profile-tab")
        let trips = app.buttons["profile-open-trips"]
        XCTAssertTrue(trips.waitForExistence(timeout: 20), app.debugDescription)
        trips.tap()
        let list = app.descendants(matching: .any)["trips-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Camille Perret"))
            .firstMatch.waitForExistence(timeout: 10))
        let back = app.navigationBars["Trajets"].buttons.firstMatch
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

    func testOpeningALearnerShowsItsProfileAndReturnsFromLessonsAndProgression() {
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
        XCTAssertFalse(app.segmentedControls.buttons["Leçons"].exists)
        XCTAssertTrue(app.buttons["learner-start-now"].exists)
        XCTAssertTrue(app.buttons["learner-plan-lesson"].exists)
        for (page, identifier) in [("Leçons", "learner-lessons-10000000-0000-4000-8000-000000000005"),
                                   ("Progression", "learner-progress-10000000-0000-4000-8000-000000000005")] {
            let row = app.descendants(matching: .any)[identifier]
            for _ in 0..<10 {
                if row.exists && row.isHittable { break }
                dossier.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8))
                    .press(forDuration: 0.05, thenDragTo: dossier.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.25)))
            }
            XCTAssertTrue(row.exists && row.isHittable, app.debugDescription)
            row.tap()
            XCTAssertTrue(app.navigationBars[page].waitForExistence(timeout: 10), app.debugDescription)
            if page == "Leçons" {
                XCTAssertTrue(app.descendants(matching: .any)["training-lessons-menu"].waitForExistence(timeout: 20), app.debugDescription)
            } else {
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Avec accompagnement"))
                    .firstMatch.waitForExistence(timeout: 20), app.debugDescription)
            }
            let back = app.navigationBars[page].buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Dossier", "Retour")).firstMatch
            XCTAssertTrue(back.exists, app.debugDescription)
            back.tap()
            XCTAssertTrue(dossier.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(firstName.exists && firstName.label.contains("Camille"), app.debugDescription)
        }
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }
}
