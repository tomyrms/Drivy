import XCTest

@MainActor
final class QualificationFlowTests: XCTestCase {
    func testOfflineSessionPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        try openLocalTrials(app)
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
        try openLocalTrials(app)
        try openLatestSession(app)
        XCTAssertTrue(app.staticTexts["Séance sans GPS"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Priorité à droite")).firstMatch.exists)
        attach(app, name: "03-historique-apres-relance")
        try tapWhenHittable(app.buttons["edit-summary"])
        let summary = app.textViews["summary-text"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        summary.tap()
        summary.typeText("Revoir les priorités à droite.")
        app.buttons["save-summary"].tap()
        XCTAssertTrue(app.staticTexts["saved-summary"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        try openLocalTrials(app)
        try openLatestSession(app)
        XCTAssertTrue(app.staticTexts["saved-summary"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["saved-summary"].label, "Revoir les priorités à droite.")
        attach(app, name: "04-bilan-local-apres-relance")
    }

    private func openLocalTrials(_ app: XCUIApplication) throws {
        let trials = app.buttons["open-local-trials"]
        try tapWhenHittable(trials)
        _ = try waitUntilHittable(app.buttons["new-session"])
    }

    private func openLatestSession(_ app: XCUIApplication) throws {
        try tapWhenHittable(app.buttons["Historique"].firstMatch)
        XCTAssertTrue(app.navigationBars["Historique"].waitForExistence(timeout: 10))
        let session = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "history-session-")).firstMatch
        _ = try waitUntilHittable(session)
        attach(app, name: "historique-avant-ouverture")
        session.tap()
        let detail = app.navigationBars["Relire la séance"]
        _ = try XCTUnwrap(detail.waitForExistence(timeout: 15) ? detail : nil,
                         "Le tap sur la séance doit ouvrir sa relecture.\n\(app.debugDescription)")
    }

    private func tapWhenHittable(_ element: XCUIElement) throws {
        try waitUntilHittable(element).tap()
    }

    private func waitUntilHittable(_ element: XCUIElement) throws -> XCUIElement {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        let result = XCTWaiter.wait(for: [ready], timeout: 15)
        return try XCTUnwrap(result == .completed ? element : nil,
                             "Élément inaccessible après la navigation : \(element.debugDescription)")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
