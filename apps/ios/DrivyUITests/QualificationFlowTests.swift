import XCTest

@MainActor
final class QualificationFlowTests: XCTestCase {
    func testOfflineSessionPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        openLocalTrials(app)
        let newSession = app.buttons["new-session"]
        XCTAssertTrue(newSession.waitForExistence(timeout: 15))
        attach(app, name: "01-accueil")
        XCTAssertTrue(newSession.isEnabled, app.debugDescription)
        guard newSession.isEnabled else { return }
        newSession.tap()
        let withoutGPS = app.buttons["start-without-gps"]
        XCTAssertTrue(withoutGPS.waitForExistence(timeout: 5))
        withoutGPS.tap()
        let report = app.buttons["report-observation"]
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        report.tap()
        app.buttons["category-priorities"].tap()
        let status = app.buttons["status-attention"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.tap()
        XCTAssertTrue(status.waitForNonExistence(timeout: 10))
        let observations = app.buttons["observation-list"]
        let saved = NSPredicate(format: "label CONTAINS %@", "(1)")
        expectation(for: saved, evaluatedWith: observations)
        waitForExpectations(timeout: 10)
        attach(app, name: "02-observation-sauvegardee")
        app.buttons["session-stop"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
            "stop-session-confirm", "Terminer la séance")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openLocalTrials(app)
        let history = app.buttons["Historique"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-session-")).firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.staticTexts["Séance sans GPS"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Priorité à droite")).firstMatch.exists)
        attach(app, name: "03-historique-apres-relance")
        app.buttons["edit-summary"].tap()
        let summary = app.textViews["summary-text"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        summary.tap()
        summary.typeText("Revoir les priorités à droite.")
        app.buttons["save-summary"].tap()
        XCTAssertTrue(app.staticTexts["saved-summary"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        openLocalTrials(app)
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        history.tap()
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        session.tap()
        XCTAssertTrue(app.staticTexts["saved-summary"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["saved-summary"].label, "Revoir les priorités à droite.")
        attach(app, name: "04-bilan-local-apres-relance")
    }

    private func openLocalTrials(_ app: XCUIApplication) {
        let trials = app.buttons["open-local-trials"]
        XCTAssertTrue(trials.waitForExistence(timeout: 15))
        trials.tap()
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
