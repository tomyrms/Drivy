import XCTest

/// Scénario explicite DEBUG simulateur, aucune identité réelle ni réseau.
@MainActor final class SchoolPlanningCancellationUITests: XCTestCase {
    func testCancelAtTokenKeepsTheForm() throws { try exercise(mode: "token") }
    func testCancelAtMeKeepsTheForm() throws { try exercise(mode: "me") }
    func testRemovalCanBeRetriedInLargeText() throws { try exercise(mode: "token", failsRemoval: true, largeText: true) }

    private func exercise(mode: String, failsRemoval: Bool = false, largeText: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "planning"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH", "-planning-l2-cancellation-" + mode]
        if failsRemoval { app.launchArguments.append("-planning-l2-cancellation-storage-failure") }
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let plan = app.buttons["planning-confirm"]
        XCTAssertTrue(plan.waitForExistence(timeout: 20))
        reveal(plan, app: app, up: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: plan)], timeout: 5), .completed)
        plan.tap()
        let cancel = app.buttons["planning-cancel-send"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        reveal(cancel, app: app, up: false)
        XCTAssertEqual(cancel.label, "Annuler l’envoi")
        XCTAssertFalse(app.buttons["Annuler la leçon"].exists)
        XCTAssertTrue(app.buttons["Fermer"].isEnabled, "Fermer reste une action distincte du retrait")
        cancel.tap()
        let error = app.descendants(matching: .any)["planning-send-cancellation-error"].firstMatch
        if failsRemoval {
            XCTAssertTrue(error.waitForExistence(timeout: 5))
            XCTAssertTrue(cancel.isEnabled)
            cancel.tap()
        }
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Seul le retrait réussi rend la saisie disponible")
        XCTAssertFalse(error.exists)
        XCTAssertTrue(app.navigationBars["Planifier une leçon"].exists)
        reveal(plan, app: app, up: true)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: plan)], timeout: 5), .completed)
        for _ in 0..<10 {
            if app.textFields.matching(NSPredicate(format: "value == %@", "Gare de Cernier")).firstMatch.isHittable
                || app.textViews.matching(NSPredicate(format: "value == %@", "Gare de Cernier")).firstMatch.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(app.staticTexts["Gare de Cernier"].exists || app.textFields.matching(NSPredicate(format: "value == %@", "Gare de Cernier")).count > 0
            || app.textViews.matching(NSPredicate(format: "value == %@", "Gare de Cernier")).count > 0)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "L2 saisie conservée — fixture synthétique"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool) {
        for _ in 0..<10 {
            if element.isHittable { break }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }
}
