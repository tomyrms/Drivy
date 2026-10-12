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
        // Les gestes de contact sont rangés dans le menu de la carte de l’élève.
        let contact = app.descendants(matching: .any)["learner-profile-actions"].firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 10), app.debugDescription)
        contact.tap()
        XCTAssertTrue(app.buttons["learner-profile-email"].waitForExistence(timeout: 10), app.debugDescription)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["dossier-section"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["learner-start-now"].exists)
        XCTAssertTrue(app.buttons["learner-plan-lesson"].exists)
        // Leçons et Progression changent le contenu en place : l’identité de l’élève reste à l’écran.
        XCTAssertTrue(app.descendants(matching: .any)["training-lessons-menu"].waitForExistence(timeout: 20), app.debugDescription)
        let progression = app.segmentedControls.buttons["Progression"]
        XCTAssertTrue(progression.waitForExistence(timeout: 10), app.debugDescription)
        progression.tap()
        // « Où j’en suis » dit les autres niveaux en une ligne (« 1 avec accompagnement »).
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "avec accompagnement"))
            .firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(dossier.exists, app.debugDescription)
    }

    /// L’école fictive laisse ce compte gérer les signalements : l’entrée existe dans le Profil, l’écran montre
    /// les thèmes du catalogue, leur compteur et l’aperçu de la grille. Captures en clair et en sombre.
    func testProfileOpensObservationThemesWithItsCounterAndPreview() {
        for appearance in ["Light", "Dark"] {
            let app = launch("profile-tab", appearance: appearance)
            let entry = app.descendants(matching: .any)["profile-observation-themes"]
            XCTAssertTrue(entry.waitForExistence(timeout: 20), app.debugDescription)
            entry.tap()
            XCTAssertTrue(app.navigationBars["Signalements"].waitForExistence(timeout: 10), app.debugDescription)
            for key in ["vehicle", "indicators"] {
                XCTAssertTrue(app.descendants(matching: .any)["observation-theme-\(key)"].waitForExistence(timeout: 10), app.debugDescription)
            }
            let counter = app.descendants(matching: .any)["observation-themes-count"]
            XCTAssertTrue(counter.waitForExistence(timeout: 10), app.debugDescription)
            // Le total vient du catalogue de l’école fictive : seul le nombre affiché à l’origine est fixé ici.
            XCTAssertTrue(counter.label.contains("12 affichés sur "), counter.label)
            capture(app, name: "observation-themes-\(appearance.lowercased())")
            app.buttons["observation-themes-preview"].tap()
            XCTAssertTrue(app.navigationBars["Aperçu"].waitForExistence(timeout: 10), app.debugDescription)
            capture(app, name: "observation-themes-preview-\(appearance.lowercased())")
            app.terminate()
        }
    }

    private func launch(_ screen: String, appearance: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        if let appearance { app.launchArguments += ["-AppleInterfaceStyle", appearance] }
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
