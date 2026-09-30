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
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Camille Exemple"))
            .firstMatch.waitForExistence(timeout: 10))
        let back = app.navigationBars["Trajets"].buttons.firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(trips.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["profile-planning-settings"].exists)
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

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }
}
