import XCTest

/// Boîtes de l'onglet Élèves (#447, #449) sur le vrai écran : au-delà de huit lignes, la liste complète s'ouvre, chaque ligne ouvre un
/// dossier et le retour retrouve la liste dépliée ; tirer pour actualiser garde les lignes et n'affiche aucune erreur.
@MainActor final class SchoolBoxesUITests: XCTestCase {
    private func launch(count: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "learners-boxes-\(count)"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, prefix: String, number: Int) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(prefix) \(number),")).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<25 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    func testNineRowsAreAllReachableAndOpenThenReturnToTheExpandedList() {
        verifyFullList(count: 9)
    }

    func testTwentyRowsAreAllReachableAndOpenThenReturnToTheExpandedList() {
        verifyFullList(count: 20)
    }

    private func verifyFullList(count: Int) {
        let app = launch(count: count)
        let requestsToggle = app.buttons["pending-requests-expansion"]
        XCTAssertTrue(requestsToggle.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertEqual(requestsToggle.value as? String, "Liste réduite")
        // Sans dépliage, la neuvième demande n'existe pas à l'écran.
        XCTAssertFalse(row(app, prefix: "Élève demande", number: 9).exists)
        requestsToggle.tap()
        XCTAssertEqual(requestsToggle.value as? String, "Liste complète")

        let last = row(app, prefix: "Élève demande", number: count)
        XCTAssertTrue(scrollTo(last, in: app), "Dernière demande inaccessible : \(app.debugDescription)")
        last.tap()
        XCTAssertTrue(app.scrollViews["learner-dossier"].waitForExistence(timeout: 30), app.debugDescription)

        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { back.tap() }
        XCTAssertTrue(app.buttons["pending-requests-expansion"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertEqual(app.buttons["pending-requests-expansion"].value as? String, "Liste complète", "Le retour a perdu le dépliage")
    }

    func testPullingToRefreshKeepsTheBoxesAndShowsNoError() {
        let app = launch(count: 9)
        let toggle = app.buttons["pending-requests-expansion"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), app.debugDescription)
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        let top = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        top.press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(toggle.exists, app.debugDescription)
        XCTAssertFalse(app.buttons["pending-requests-retry"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["pending-exams-retry"].exists, app.debugDescription)
        XCTAssertTrue(row(app, prefix: "Élève demande", number: 1).exists, app.debugDescription)
    }
}
