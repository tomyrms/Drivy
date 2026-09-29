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
        capture(app, name: "gps-document")
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
        capture(app, name: "signal-themes")
        priority.tap()
        let attention = app.buttons["live-observation-status-ATTENTION"]
        XCTAssertTrue(attention.waitForExistence(timeout: 5))
        capture(app, name: "signal-status")
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
        capture(app, name: "lesson-empty-report")
        save.tap()
        XCTAssertTrue(app.staticTexts["field-lesson-closed"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testLiveSignalCanGoBackCancelAndReopenWithoutRecording() {
        let app = launch("live")
        let signal = app.buttons["capture-signal-observation"]
        XCTAssertTrue(signal.waitForExistence(timeout: 20), app.debugDescription)
        signal.tap()
        let priority = app.buttons["live-observation-theme-Priorité à droite"]
        XCTAssertTrue(priority.waitForExistence(timeout: 10), app.debugDescription)
        priority.tap()
        XCTAssertTrue(app.buttons["live-observation-status-ATTENTION"].waitForExistence(timeout: 5))
        app.buttons["live-observation-back"].tap()
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        app.buttons["live-observation-close"].tap()
        XCTAssertTrue(priority.waitForNonExistence(timeout: 5))
        XCTAssertTrue(signal.isEnabled)
        signal.tap()
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["live-observation-status-ATTENTION"].exists)
        capture(app, name: "live-signal-reopened")
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
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
