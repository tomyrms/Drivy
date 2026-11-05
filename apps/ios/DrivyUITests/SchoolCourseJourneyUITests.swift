import XCTest

/// #37/#99/#143 : vraies vues et clients, réponses synthétiques au transport, aucun serveur réel.
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
        // Les deux homonymes viennent de la dernière page de l'annuaire, pas de la première lue par l'app : la lecture est finie.
        XCTAssertFalse(app.buttons["course-candidates-retry"].exists, app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["course-candidates-loading"].exists, app.debugDescription)
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

    func testPriorityOfferRequiresReviewAndExplicitAcceptance() {
        let app = launch("course-offered")
        defer { app.terminate() }
        let accept = app.buttons["course-accept-offer"]
        XCTAssertTrue(accept.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.staticTexts["course-learner-status"].label.hasPrefix("Place proposée jusqu’à"))
        assertWitness("mutations=0; events=; unexpected=0; mail=0; messages=0", in: app)
        XCTAssertFalse(app.buttons["course-payment"].exists)
        XCTAssertFalse(app.buttons["course-validate"].exists)
        accept.tap()
        XCTAssertTrue(app.navigationBars["Vérifier l’inscription"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Inscription pour les 4 séances."].exists)
        let confirm = app.buttons["course-confirm-enrollment"]
        reveal(confirm, in: app)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["Vérifier l’inscription"].waitForNonExistence(timeout: 5))
        assertStatus("Inscrit", in: app)
        assertWitness("mutations=1; events=accept; unexpected=0; mail=0; messages=0", in: app)
        XCTAssertFalse(app.buttons["course-accept-offer"].exists)
        XCTAssertTrue(app.buttons["course-cancel"].exists)
        attachScreen("offre-acceptée", in: app)
    }

    /// Une proposition restée affichée après son échéance ne peut plus être acceptée.
    func testExpiredPriorityOfferCannotSendAnAcceptance() {
        let app = launch("course-offer-expired")
        defer { app.terminate() }
        assertStatus("Délai de réponse passé", in: app)
        XCTAssertFalse(app.buttons["course-accept-offer"].exists)
        XCTAssertFalse(app.buttons["course-decline-offer"].exists)
        XCTAssertFalse(app.buttons["course-confirm-enrollment"].exists)
        assertWitness("mutations=0; events=; unexpected=0; mail=0; messages=0", in: app)
        attachScreen("offre-expirée", in: app)
    }

    func testCancellationBeforeDeadlineConfirmsOnlyTheEnrollment() throws {
        let app = launch("course-cancel-success")
        defer { app.terminate() }
        assertStatus("Inscrit", in: app)
        assertWitness("mutations=0; events=; unexpected=0; mail=0; messages=0", in: app)
        app.buttons["course-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Ton inscription aux 4 séances sera annulée."].waitForExistence(timeout: 10))
        try tapConfirmation("Annuler l’inscription", in: app)
        assertStatus("Annulé", in: app)
        assertWitness("mutations=1; events=cancel; unexpected=0; mail=0; messages=0", in: app)
        XCTAssertTrue(app.navigationBars["Sensibilisation du soir"].exists)
        XCTAssertFalse(app.buttons["course-cancel"].exists)
        attachScreen("inscription-annulée", in: app)
    }

    func testContactAfterDeadlineInLargeTextKeepsEnrollmentAndSendsNothing() {
        let app = launch("course-after-deadline", largeText: true)
        defer { app.terminate() }
        assertStatus("Inscrit", in: app)
        let contact = app.buttons["course-contact-school"]
        reveal(contact, in: app)
        XCTAssertFalse(app.buttons["course-cancel"].exists)
        XCTAssertTrue(app.staticTexts["Le délai d’annulation est passé."].exists)
        contact.tap() // OpenURL intercepté seulement dans cette fixture : aucun logiciel Mail lancé.
        assertWitness("mutations=0; events=; unexpected=0; mail=1; messages=0", in: app)
        let messages = app.buttons["messages-entry"]
        reveal(messages, in: app, upwards: false)
        messages.tap()
        XCTAssertTrue(app.staticTexts["course-fixture-messages"].waitForExistence(timeout: 10))
        app.navigationBars["Messages"].buttons["Fermer"].tap()
        XCTAssertTrue(app.staticTexts["course-fixture-messages"].waitForNonExistence(timeout: 5))
        assertWitness("mutations=0; events=; unexpected=0; mail=1; messages=1", in: app)
        reveal(app.staticTexts["course-learner-status"], in: app, upwards: false)
        assertStatus("Inscrit", in: app)
        XCTAssertFalse(app.buttons["course-cancel"].exists)
        attachScreen("contact-sans-annulation-grand-texte", in: app)
    }

    func testPaymentAttendanceAndCompletionRequireThreeDistinctActions() throws {
        let app = launch("course-facts")
        defer { app.terminate() }
        let modes = app.segmentedControls["course-participant-mode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 15), app.debugDescription)
        modes.buttons["Validation"].tap()
        let validate = app.buttons["course-validate"]
        XCTAssertTrue(validate.waitForExistence(timeout: 10))
        XCTAssertFalse(validate.isEnabled)
        XCTAssertTrue(app.staticTexts["3 sur 4 séances obligatoires"].exists)
        modes.buttons["Règlements"].tap()
        app.buttons["course-payment"].tap()
        let amount = app.textFields["course-payment-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap(); amount.typeText("80")
        XCTAssertEqual(amount.value as? String, "80")
        // Sur iPad, fermer explicitement le clavier avant que la feuille se recentre :
        // le premier toucher d'enregistrement de la campagne 42105462976 n'a fait que le masquer.
        let hideKeyboard = app.keyboards.buttons["Masquer le clavier"]
        if hideKeyboard.exists && hideKeyboard.isHittable {
            hideKeyboard.tap()
            let hidden = expectation(for: NSPredicate(format: "hittable == false"), evaluatedWith: hideKeyboard)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        }
        XCTAssertEqual(amount.value as? String, "80")
        let submit = app.buttons["course-payment-submit"]
        XCTAssertTrue(submit.isEnabled && submit.isHittable)
        submit.tap()
        XCTAssertTrue(app.navigationBars["Règlement sur place"].waitForNonExistence(timeout: 5))
        assertWitness("mutations=1; events=payment; unexpected=0; mail=0; messages=0", in: app)
        let paid = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Payé :")).firstMatch
        XCTAssertTrue(paid.waitForExistence(timeout: 10))
        XCTAssertTrue(paid.label.contains("80"))
        modes.buttons["Validation"].tap()
        XCTAssertTrue(app.staticTexts["3 sur 4 séances obligatoires"].exists)
        XCTAssertFalse(validate.isEnabled)
        XCTAssertFalse(app.staticTexts["Cours validé"].exists)
        modes.buttons["Appel"].tap()
        let present = app.buttons["course-attendance-present"]
        reveal(present, in: app)
        present.tap()
        assertWitness("mutations=2; events=payment,attendance; unexpected=0; mail=0; messages=0", in: app)
        modes.buttons["Validation"].tap()
        XCTAssertTrue(app.staticTexts["4 sur 4 séances obligatoires"].waitForExistence(timeout: 10))
        XCTAssertTrue(validate.isEnabled)
        XCTAssertFalse(app.staticTexts["Cours validé"].exists)
        validate.tap()
        try tapConfirmation("Valider", in: app)
        XCTAssertTrue(app.staticTexts["Cours validé"].waitForExistence(timeout: 10))
        assertWitness("mutations=3; events=payment,attendance,validation; unexpected=0; mail=0; messages=0", in: app)
        attachScreen("accomplissement-explicite", in: app)
        modes.buttons["Règlements"].tap()
        XCTAssertTrue(paid.exists && paid.label.contains("80"))
    }

    func testStaffRightsDoNotGrantTheOtherParticipantTasks() {
        for screen in ["course-attendance-only", "course-payments-history"] {
            let app = launch(screen)
            let target = app.buttons[screen == "course-attendance-only" ? "course-attendance-present" : "course-payment"].firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 15), app.debugDescription)
            XCTAssertFalse(app.segmentedControls["course-participant-mode"].exists)
            XCTAssertFalse(app.buttons["course-validate"].exists)
            XCTAssertFalse(app.buttons[screen == "course-attendance-only" ? "course-payment" : "course-attendance-present"].exists)
            attachScreen(screen, in: app)
            app.terminate()
        }
    }

    private func assertStatus(_ label: String, in app: XCUIApplication) {
        let status = app.staticTexts["course-learner-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), app.debugDescription)
        let matches = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 10), .completed, app.debugDescription)
    }
    private func assertWitness(_ label: String, in app: XCUIApplication) {
        let witness = app.staticTexts["course-fixture-witness"]
        XCTAssertTrue(witness.waitForExistence(timeout: 10), app.debugDescription)
        let matches = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: witness)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 10), .completed, app.debugDescription)
    }
    private func tapConfirmation(_ label: String, in app: XCUIApplication) throws {
        XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        // Bouton terminal du dialogue iOS 26 ; aucun repli sur une coordonnée supposée.
        let leaves = app.buttons.matching(identifier: label).allElementsBoundByIndex.filter {
            $0.descendants(matching: .button).matching(identifier: label).count == 0 && $0.isHittable
        }
        XCTAssertEqual(leaves.count, 1, app.debugDescription)
        try XCTUnwrap(leaves.first).tap()
    }
    private func attachScreen(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func launch(_ screen: String, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<8 { if element.exists && element.isHittable { return }; if upwards { app.swipeUp() } else { app.swipeDown() } }
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
