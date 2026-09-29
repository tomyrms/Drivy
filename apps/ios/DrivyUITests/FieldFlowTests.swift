import XCTest

@MainActor final class FieldFlowTests: XCTestCase {
    func testGPSChoiceShowsDocumentsOnDemandAndClosesAfterOneChoice() {
        let app = launch("gps-choice")
        let allow = app.buttons["recording-allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Document de contrôle : le trajet sert à revoir la leçon avec l’élève et son moniteur. Les positions ne sont pas publiques."].exists)
        XCTAssertFalse(app.buttons["recording-review-choice"].exists)
        app.buttons["recording-notice-link"].tap()
        XCTAssertTrue(app.staticTexts["Document de contrôle : le trajet sert à revoir la leçon avec l’élève et son moniteur. Les positions ne sont pas publiques."].waitForExistence(timeout: 5))
        app.buttons["Fermer"].tap()
        allow.tap()
        XCTAssertTrue(app.staticTexts["field-choice-saved"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(allow.exists)
    }

    func testAnObservationUsesAPreciseThemeAndAnExplicitStatus() {
        let app = launch("signal")
        let priority = app.buttons["live-observation-theme-Priorité à droite"]
        XCTAssertTrue(priority.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["live-observation-theme-Signalisation"].exists)
        priority.tap()
        let attention = app.buttons["live-observation-status-ATTENTION"]
        XCTAssertTrue(attention.waitForExistence(timeout: 5))
        attention.tap()
        XCTAssertTrue(app.staticTexts["field-observation-saved"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(attention.exists)
    }

    func testFinishingALessonNeedsNoDateConfirmationOrReportText() {
        let app = launch("lesson-finish")
        let finish = app.buttons["lesson-complete"]
        XCTAssertTrue(finish.waitForExistence(timeout: 20), app.debugDescription)
        finish.tap()
        let save = app.buttons["lesson-save-report"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.datePickers.count, 0)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.staticTexts["field-lesson-closed"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launch()
        return app
    }
}
