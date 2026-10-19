import XCTest

/// Parcours représentatif du bilan V4. À exécuter sur runner Apple avec les fixtures visuelles existantes.
@MainActor final class SchoolReportFlowUITests: XCTestCase {
    func testCompactReportEditsTextBeforeCompetenciesAndSavesOnlyFromReview() {
        continueAfterFailure = false
        let app = launch("lesson-finish")

        let start = app.buttons["lesson-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), app.debugDescription)
        start.tap()
        let finish = app.buttons["lesson-complete"]
        XCTAssertTrue(finish.waitForExistence(timeout: 20), app.debugDescription)
        finish.tap()
        let confirmation = completionConfirmation(in: app)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
        confirmation.tap()

        XCTAssertTrue(stepTitle(in: app).waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(stepTitle(in: app).label.hasPrefix("Bilan"), app.debugDescription)
        XCTAssertFalse(app.buttons["lesson-save-report"].exists)
        let workedOn = reportField("Travail réalisé", in: app)
        XCTAssertTrue(workedOn.waitForExistence(timeout: 5), app.debugDescription)
        workedOn.tap()
        workedOn.typeText("Créneaux et contrôles")
        app.buttons["lesson-report-dismiss-keyboard"].tapIfExists()

        let next = app.buttons["lesson-report-next"]
        XCTAssertTrue(waitUntil { !app.keyboards.firstMatch.exists && next.exists && next.isHittable }, app.debugDescription)
        next.tap()
        XCTAssertTrue(waitUntil { !stepTitle(in: app).label.hasPrefix("Bilan") }, app.debugDescription)
        if stepTitle(in: app).label.hasPrefix("Compétences") {
            XCTAssertFalse(app.buttons["lesson-save-report"].exists)
            XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
            next.tap()
        }

        XCTAssertTrue(waitUntil(timeout: 10) { stepTitle(in: app).label.hasPrefix("Récapitulatif") }, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["lesson-report-review-text"].exists)
        // Chaque ligne du récapitulatif combine libellé et valeur pour VoiceOver : on cherche la valeur dans l'élément fusionné.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Créneaux et contrôles"))
            .firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["lesson-report-review-visibility"].exists)
        XCTAssertTrue(app.buttons["lesson-save-report"].exists)
    }

    private func stepTitle(in app: XCUIApplication) -> XCUIElement {
        // Pendant la transition entre deux étapes, l'ancienne et la nouvelle coexistent un instant.
        // On lit l'étape affichée à l'écran plutôt que d'exiger un élément unique.
        let steps = app.descendants(matching: .any).matching(identifier: "lesson-report-step")
        let shown = steps.allElementsBoundByIndex.last { $0.exists && $0.isHittable }
        return shown ?? steps.firstMatch
    }

    private func completionConfirmation(in app: XCUIApplication) -> XCUIElement {
        // iOS 26 n'expose pas toujours l'identifiant d'une action de confirmationDialog : même règle que FieldFlowTests.
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
            "lesson-confirm-completion", "Terminer")).firstMatch
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return condition()
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }

    private func reportField(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %lu OR elementType == %lu)", label,
            XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue
        )).firstMatch
    }
}

private extension XCUIElement {
    func tapIfExists() {
        if waitForExistence(timeout: 2), isHittable { tap() }
    }
}
