import XCTest

/// Fixtures existantes uniquement ; à exécuter après validation de l’IPA.
@MainActor final class SchoolProgressReadingUITests: XCTestCase {
    func testSearchKeepsTwoDetailsOpenAndShowsTheObservationDate() {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "progression"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()

        let search = app.textFields["Rechercher une compétence"]
        XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
        reveal(search, in: app)
        search.tap()
        search.typeText("PRIORITES\n")
        let observed = app.buttons["progress-competency-10000000-0000-4000-8000-000000000030"]
        XCTAssertTrue(observed.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue((observed.value as? String)?.contains("21 septembre 2026") == true, app.debugDescription)
        reveal(observed, in: app)
        observed.tap()
        XCTAssertTrue((observed.value as? String)?.contains("Détail affiché") == true, app.debugDescription)

        reveal(search, in: app, upwards: false)
        app.buttons["Effacer la recherche"].tap()
        search.tap()
        search.typeText("stationnement\n")
        let unseen = app.buttons["progress-competency-10000000-0000-4000-8000-000000000031"]
        XCTAssertTrue(unseen.waitForExistence(timeout: 10), app.debugDescription)
        reveal(unseen, in: app)
        unseen.tap()
        XCTAssertTrue((unseen.value as? String)?.contains("Pas encore vue") == true, app.debugDescription)
        XCTAssertFalse((unseen.value as? String)?.contains("Évaluation") == true, app.debugDescription)

        reveal(search, in: app, upwards: false)
        app.buttons["Effacer la recherche"].tap()
        // Le groupe non vu s’ouvre pour conserver la définition choisie ; le premier détail reste ouvert.
        XCTAssertTrue((observed.value as? String)?.contains("Détail affiché") == true, app.debugDescription)
        reveal(unseen, in: app)
        XCTAssertTrue((unseen.value as? String)?.contains("Détail affiché") == true, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Choisir les repères et contrôler l’environnement."].exists, app.debugDescription)
        unseen.tap()
        XCTAssertTrue((unseen.value as? String)?.contains("Détail masqué") == true, app.debugDescription)
        XCTAssertTrue((observed.value as? String)?.contains("Détail affiché") == true, app.debugDescription)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<8 where !element.isHittable {
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
}
