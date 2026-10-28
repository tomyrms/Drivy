import XCTest

/// #99/#143 : vraies vues, données fictives, mutations coupées au transport.
@MainActor final class SchoolCourseJourneyUITests: XCTestCase {
    func testParticipantSearchFindsBothHomonymsAfterTheTwentiethLearner() {
        let app = launch("course-roster")
        defer { app.terminate() }
        let add = app.buttons["course-staff-enroll"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        add.tap()
        let search = app.descendants(matching: .any).matching(NSPredicate(format: "elementType == %lu OR elementType == %lu",
            XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.searchField.rawValue)).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        // Le cadre d'accessibilité du champ remonte sous la barre de navigation (fond du safeAreaInset) :
        // son centre tombe sur la barre. Toucher le champ visible, ancré en bas du cadre.
        focusForTyping(search, at: CGVector(dx: 0, dy: -(12 + 22)))
        search.typeText("Zoe")
        let candidates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Zoé Exemple", "Réf."))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(candidates.count, 2, app.debugDescription)
        XCTAssertNotEqual(candidates.element(boundBy: 0).label, candidates.element(boundBy: 1).label)
        candidates.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["Inscrire à toute la série"].waitForExistence(timeout: 10), app.debugDescription)
        dismissConfirmation(in: app, cancelLabel: "Annuler")
        XCTAssertTrue(search.exists)
    }

    func testMyStartedCourseOpensItsOwnDetail() {
        let app = launch("course-list")
        defer { app.terminate() }
        let enrolled = app.buttons["learner-course-progress"]
        XCTAssertTrue(enrolled.waitForExistence(timeout: 15), app.debugDescription)
        let named = expectation(for: NSPredicate(format: "label CONTAINS %@", "Sensibilisation du soir"), evaluatedWith: enrolled)
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 10), .completed, app.debugDescription)
        enrolled.tap()
        XCTAssertTrue(app.navigationBars["Sensibilisation du soir"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["course-learner-status"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["course-learner-status"].label, "Inscrit")
    }

    func testEnrollmentReviewsEverySessionAndConditionsBeforeSending() {
        let app = launch("course-learner")
        defer { app.terminate() }
        let enroll = app.buttons["course-enroll"]
        XCTAssertTrue(enroll.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(enroll.isHittable, app.debugDescription)
        enroll.tap()
        XCTAssertTrue(app.navigationBars["Vérifier l’inscription"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Inscription pour les 4 séances."].exists, app.debugDescription)
        let confirm = app.buttons["course-confirm-enrollment"]
        reveal(confirm, in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Apporte ton permis d’élève")).firstMatch.exists, app.debugDescription)
        app.navigationBars["Vérifier l’inscription"].buttons["Retour"].tap()
        XCTAssertTrue(enroll.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["course-learner-status"].label, "Disponible")
    }

    /// #126 : la confirmation se ferme aussitôt ; la fiche dit la demande à part, jamais « Inscrit » avant l’école.
    func testEnrollmentAnswersAtOnceWithoutClaimingTheSeat() {
        let app = launch("course-learner")
        defer { app.terminate() }
        let enroll = app.buttons["course-enroll"]
        XCTAssertTrue(enroll.waitForExistence(timeout: 15), app.debugDescription)
        enroll.tap()
        XCTAssertTrue(app.navigationBars["Vérifier l’inscription"].waitForExistence(timeout: 10), app.debugDescription)
        let confirm = app.buttons["course-confirm-enrollment"]
        reveal(confirm, in: app)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Vérifier l’inscription"].waitForNonExistence(timeout: 5), app.debugDescription)
        // Le transport synthétique n’écrit rien : la demande reste à reprendre, l’état de l’école ne change pas.
        XCTAssertTrue(app.buttons["course-learner-retry"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["course-learner-status"].label, "Disponible")
    }

    func testCancellationNamesTheEnrollmentRatherThanCancellingTheCourse() {
        let app = launch("course-enrolled")
        defer { app.terminate() }
        let cancel = app.buttons["course-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Ton inscription aux 4 séances sera annulée."].waitForExistence(timeout: 10), app.debugDescription)
        dismissConfirmation(in: app, cancelLabel: "Garder")
        XCTAssertTrue(app.staticTexts["Ton inscription aux 4 séances sera annulée."].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["course-learner-status"].label, "Inscrit")
    }

    func testPaymentsBeforeFirstSessionAndEditedAmountSurviveCloseAndFailure() throws {
        let app = launch("course-payments-before-start")
        defer { app.terminate() }
        let modes = app.segmentedControls["course-participant-mode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Aucune séance commencée"].exists)
        modes.buttons["Règlements"].tap()
        let pay = app.buttons.matching(identifier: "course-payment").firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 10), app.debugDescription)
        pay.tap()
        let amount = app.textFields["course-payment-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), app.debugDescription)
        amount.tap(); amount.typeText("80")
        app.navigationBars["Règlement sur place"].buttons["Fermer"].tap()
        XCTAssertTrue(app.alerts["Quitter sans conserver le montant ?"].waitForExistence(timeout: 5), app.debugDescription)
        try tapAlertAction(in: app, identifier: "Continuer")
        XCTAssertEqual(amount.value as? String, "80")
        app.buttons["course-payment-submit"].tap()
        // #129 : la feuille se ferme aussitôt ; le montant reste sur la ligne, à reprendre, jamais compté comme payé.
        XCTAssertTrue(app.navigationBars["Règlement sur place"].waitForNonExistence(timeout: 5), app.debugDescription)
        let pending = app.descendants(matching: .any)["course-payment-pending"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(pending.label.contains("80") && pending.label.hasPrefix("Règlement de"), pending.label)
        XCTAssertTrue(app.buttons["course-sheet-retry"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Payé :'")).firstMatch.exists)
    }

    func testCourseEditorProtectsOnlyAnActualChange() throws {
        let app = launch("course-editor")
        defer { app.terminate() }
        let title = app.textFields["course-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        app.navigationBars["Brouillon"].buttons["Fermer"].tap()
        XCTAssertFalse(app.alerts["Quitter sans enregistrer ?"].exists)
        title.tap(); title.typeText(" modifié")
        app.navigationBars["Brouillon"].buttons["Fermer"].tap()
        XCTAssertTrue(app.alerts["Quitter sans enregistrer ?"].waitForExistence(timeout: 5), app.debugDescription)
        try tapAlertAction(in: app, identifier: "Continuer")
        XCTAssertTrue((title.value as? String)?.contains("modifié") == true)
    }

    private func launch(_ screen: String) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    private func dismissConfirmation(in app: XCUIApplication, cancelLabel: String) {
        // iOS 26 expose parfois Button > Button : le conteneur ne déclenche pas l'action, viser le bouton terminal.
        let leaves = app.buttons.matching(identifier: cancelLabel).allElementsBoundByIndex.filter {
            $0.descendants(matching: .button).matching(identifier: cancelLabel).count == 0 && $0.isHittable
        }
        if let cancel = leaves.first { cancel.tap(); return }
        // iPad : le rôle Annuler d'un popover se joue hors de lui. Sur une feuille, deux régions existent :
        // la dernière est celle du popover, au premier plan ; la première fermerait la feuille.
        let regions = app.otherElements.matching(identifier: "PopoverDismissRegion")
        if regions.count > 0 { regions.element(boundBy: regions.count - 1).tap(); return }
        // iOS 26 peut présenter le rôle Annuler comme un toucher hors du popover, sans bouton nommé.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
    }
}
