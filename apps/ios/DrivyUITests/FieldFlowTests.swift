import XCTest

@MainActor final class FieldFlowTests: XCTestCase {
    func testLeavingLiveThroughTabsKeepsTheLessonAndCancellationIsInTheMenu() {
        continueAfterFailure = false
        let app = launch("live")
        let signal = app.buttons["capture-signal-observation"]
        XCTAssertTrue(signal.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["capture-cancel-lesson"].exists)
        XCTAssertFalse(app.buttons["Revenir à la leçon"].exists)
        app.buttons["capture-more"].tap()
        XCTAssertTrue(app.buttons["Annuler la leçon"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Voir la leçon"].exists)
        // Dismiss the menu outside its actions, then leave through the actual tab bar.
        nativeTab("Agenda", in: app).tap()
        if signal.exists { nativeTab("Agenda", in: app).tap() }
        XCTAssertTrue(signal.waitForNonExistence(timeout: 5))
        nativeTab("Aujourd’hui", in: app).tap()
        XCTAssertTrue(signal.waitForExistence(timeout: 5))
        XCTAssertTrue(signal.isEnabled)
    }

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
        XCTAssertTrue(allow.waitForNonExistence(timeout: 5))
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
        XCTAssertTrue(attention.isEnabled)
        XCTAssertTrue(priority.exists && priority.isSelected)
        XCTAssertTrue(app.buttons["live-observation-theme-Signalisation"].exists)
        capture(app, name: "signal-status")
        attention.tap()
        XCTAssertTrue(app.staticTexts["field-observation-saved"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(attention.exists)
    }

    func testFinishingALessonRequiresConfirmationButNoDatesOrReportText() {
        continueAfterFailure = false
        let app = launch("lesson-finish")
        let finish = app.buttons["lesson-complete"]
        XCTAssertTrue(finish.waitForExistence(timeout: 20), app.debugDescription)
        finish.tap()
        let confirm = completionConfirmation(in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        let save = app.buttons["lesson-save-report"]
        XCTAssertFalse(save.exists)
        let keepLesson = app.buttons["Continuer"]
        XCTAssertTrue(keepLesson.waitForExistence(timeout: 5), app.debugDescription)
        keepLesson.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(finish.exists && finish.isEnabled)
        XCTAssertFalse(save.exists)
        XCTAssertFalse(app.staticTexts["field-lesson-closed"].exists)
        finish.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        // La rédaction s’ouvre sur sa première étape ; l’enregistrement est à la dernière.
        let next = app.buttons["lesson-report-next"]
        for _ in 0..<3 where !save.waitForExistence(timeout: 5) { if next.exists { next.tap() } }
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.datePickers.count, 0)
        XCTAssertTrue(save.isEnabled)
        capture(app, name: "lesson-empty-report")
        save.tap()
        XCTAssertTrue(app.staticTexts["field-lesson-closed"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testLiveSignalKeepsThemesVisibleWhenSelectingAndCancelling() {
        continueAfterFailure = false
        let app = launch("live")
        let signal = app.buttons["capture-signal-observation"]
        XCTAssertTrue(signal.waitForExistence(timeout: 20), app.debugDescription)
        signal.tap()
        let priority = app.buttons["live-observation-theme-Priorité à droite"]
        XCTAssertTrue(priority.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(priority.isSelected)
        priority.tap()
        let attention = app.buttons["live-observation-status-ATTENTION"]
        XCTAssertTrue(attention.waitForExistence(timeout: 5))
        XCTAssertTrue(attention.isEnabled)
        XCTAssertTrue(priority.exists && priority.isSelected)
        XCTAssertTrue(app.buttons["live-observation-theme-Signalisation"].exists)
        XCTAssertTrue(app.buttons["live-observation-marker"].exists)
        // Cette action efface la sélection dans la même palette ; elle ne change plus de page.
        app.buttons["live-observation-back"].tap()
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        XCTAssertFalse(priority.isSelected)
        XCTAssertTrue(app.buttons["live-observation-theme-Signalisation"].exists)
        app.buttons["live-observation-close"].tap()
        XCTAssertTrue(priority.waitForNonExistence(timeout: 5))
        XCTAssertTrue(signal.isEnabled)
        signal.tap()
        XCTAssertTrue(priority.waitForExistence(timeout: 5))
        XCTAssertFalse(priority.isSelected)
        XCTAssertTrue(app.buttons["live-observation-theme-Signalisation"].exists)
        capture(app, name: "live-signal-reopened")
    }

    func testPermitReasonSurvivesCancelledDiscardAndClearsOnlyAfterAbandon() {
        continueAfterFailure = false
        let app = launch("lesson-permit")
        let confirm = completionConfirmation(in: app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), app.debugDescription)
        confirm.tap()
        let reason = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND (elementType == %lu OR elementType == %lu)",
            "lesson-permit-reason", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue
        )).firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 20), app.debugDescription)
        let finish = app.buttons["lesson-complete-permit"]
        XCTAssertTrue(finish.exists)
        XCTAssertFalse(finish.isEnabled)
        let text = "Permis oublié, contrôle à reprendre."
        reason.tap()
        reason.typeText(text)
        XCTAssertEqual(reason.value as? String, text)
        XCTAssertTrue(finish.isEnabled)

        let cancel = app.navigationBars["Permis d’élève"].buttons["Annuler"]
        cancel.tap()
        let discard = app.buttons["Quitter sans enregistrer"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), app.debugDescription)
        let keepEditing = app.buttons["Continuer"]
        if keepEditing.waitForExistence(timeout: 2) {
            keepEditing.tap()
        } else {
            // iOS 26 peut omettre l’action d’annulation d’un confirmationDialog
            // dans l’arbre d’accessibilité. Taper réellement hors du popover.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.45)).tap()
        }
        XCTAssertTrue(discard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(reason.value as? String, text)
        XCTAssertTrue(finish.isEnabled)
        capture(app, name: "lesson-permit-draft-preserved")

        cancel.tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(reason.waitForNonExistence(timeout: 5))
        let reopen = app.buttons["lesson-complete"]
        XCTAssertTrue(reopen.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["lesson-save-report"].exists)
        reopen.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertFalse((reason.value as? String ?? "").contains(text))
        XCTAssertFalse(finish.isEnabled)
        capture(app, name: "lesson-permit-reopened-empty")
        // Aucune commande de clôture n’est envoyée ; ce cas refuse aussi toute écriture fictive.
        app.terminate()
    }

    private func completionConfirmation(in app: XCUIApplication) -> XCUIElement {
        // Le libellé reste la référence si iOS n’expose pas l’identifiant de l’action native.
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
            "lesson-confirm-completion", "Terminer")).firstMatch
    }

    private func nativeTab(_ title: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        // iPhone exposes a Button; iPad's _UIFloatingTabBarItemCell is a Cell, without a TabBar ancestor.
        let tab = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %lu OR elementType == %lu)",
            title, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue
        )).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        return tab
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
