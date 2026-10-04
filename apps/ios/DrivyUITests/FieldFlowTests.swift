import XCTest

@MainActor final class FieldFlowTests: XCTestCase {
    func testLeavingLiveThroughTabsKeepsTheLessonAndCancellationIsInTheMenu() {
        let app = launch("live")
        let signal = app.buttons["capture-signal-observation"]
        XCTAssertTrue(signal.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["capture-cancel-lesson"].exists)
        XCTAssertFalse(app.buttons["Revenir à la leçon"].exists)
        app.buttons["capture-more"].tap()
        XCTAssertTrue(app.buttons["Annuler la leçon"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Voir la leçon"].exists)
        // Dismiss the menu outside its actions, then leave through the actual tab bar.
        app.tabBars.buttons["Agenda"].tap()
        if signal.exists { app.tabBars.buttons["Agenda"].tap() }
        XCTAssertTrue(signal.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["Aujourd’hui"].tap()
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

    func testPermitReasonSurvivesCancelledDiscardAndClearsOnlyAfterAbandon() {
        continueAfterFailure = false
        let app = launch("lesson-permit")
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
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertFalse((reason.value as? String ?? "").contains(text))
        XCTAssertFalse(finish.isEnabled)
        capture(app, name: "lesson-permit-reopened-empty")
        // Aucune confirmation de fin n’est envoyée ; ce cas refuse aussi toute écriture fictive.
        app.terminate()
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
