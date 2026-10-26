import XCTest

/// Parcours représentatif du bilan V4. À exécuter sur runner Apple avec les fixtures visuelles existantes.
@MainActor final class SchoolReportFlowUITests: XCTestCase {
    func testKeepDraftClosesAndReopensTheSameText() {
        continueAfterFailure = false
        let app = launch("lesson-draft")
        editDraft(in: app, text: " Brouillon conservé après fermeture")
        closeReport(in: app)
        let keep = app.buttons["Conserver le brouillon et quitter"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5), app.debugDescription)
        keep.tap()
        let open = app.buttons["Ouvrir la leçon"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
        open.tap()
        XCTAssertTrue(waitUntil(timeout: 15) {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Brouillon conservé après fermeture")).firstMatch.exists
        }, app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Bilan repris — données synthétiques"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFailedDraftWriteDoesNotCloseOrDiscardTheText() {
        continueAfterFailure = false
        let app = launch("lesson-draft-error")
        editDraft(in: app, text: " Texte gardé malgré la panne")
        closeReport(in: app)
        let keep = app.buttons["Conserver le brouillon et quitter"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5), app.debugDescription)
        keep.tap()
        XCTAssertTrue(app.buttons["Fermer"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["Ouvrir la leçon"].isHittable)
        XCTAssertTrue(waitUntil {
            app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Le brouillon n’a pas pu être conservé")).firstMatch.exists
        }, app.debugDescription)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Écriture locale refusée — données synthétiques"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func editDraft(in app: XCUIApplication, text: String) {
        let more = app.buttons["lesson-more-actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 20), app.debugDescription)
        more.tap()
        let edit = app.buttons["lesson-report-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), app.debugDescription)
        edit.tap()
        let field = reportField("Travail réalisé", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        field.tap(); field.typeText(text)
        app.buttons["lesson-report-dismiss-keyboard"].tapIfExists()
    }

    private func closeReport(in app: XCUIApplication) {
        let close = app.buttons["Fermer"]
        if !close.isHittable {
            let back = app.navigationBars.buttons["Leçon"]
            if back.waitForExistence(timeout: 2), back.isHittable { back.tap() }
        }
        XCTAssertTrue(waitUntil { close.exists && close.isHittable }, app.debugDescription)
        close.tap()
    }

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

        XCTAssertTrue(waitUntil(timeout: 20) { stepShown("Bilan", in: app) }, app.debugDescription)
        XCTAssertFalse(app.buttons["lesson-save-report"].exists)
        let workedOn = reportField("Travail réalisé", in: app)
        XCTAssertTrue(workedOn.waitForExistence(timeout: 5), app.debugDescription)
        workedOn.tap()
        workedOn.typeText("Créneaux et contrôles")
        app.buttons["lesson-report-dismiss-keyboard"].tapIfExists()

        let next = app.buttons["lesson-report-next"]
        // En portrait, le clavier reste ouvert sous le bouton : seul compte que « Continuer » soit touchable.
        XCTAssertTrue(waitUntil { next.exists && next.isHittable }, app.debugDescription)
        next.tap()
        // Pendant la transition, ancienne et nouvelle étape coexistent : on attend que « Bilan » ait disparu.
        XCTAssertTrue(waitUntil { !stepShown("Bilan", in: app) }, app.debugDescription)
        if stepShown("Compétences", in: app) {
            XCTAssertFalse(app.buttons["lesson-save-report"].exists)
            XCTAssertTrue(waitUntil { next.exists && next.isHittable }, app.debugDescription)
            next.tap()
        }

        XCTAssertTrue(waitUntil(timeout: 10) { stepShown("Récapitulatif", in: app) }, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["lesson-report-review-text"].exists)
        // Chaque ligne du récapitulatif combine libellé et valeur pour VoiceOver : on cherche la valeur dans l'élément fusionné.
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Créneaux et contrôles"))
            .firstMatch.exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["lesson-report-review-visibility"].exists)
        XCTAssertTrue(app.buttons["lesson-save-report"].exists)
        XCTAssertEqual(app.buttons["lesson-save-report"].label, "Enregistrer et fermer")
    }

    /// Vrai si une étape portant ce titre est à l'écran, même si une autre est encore en train de sortir.
    private func stepShown(_ prefix: String, in app: XCUIApplication) -> Bool {
        app.descendants(matching: .any).matching(identifier: "lesson-report-step")
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).count > 0
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
