import XCTest

/// #99/#143 : vraies vues, données fictives, mutations coupées au transport.
@MainActor final class SchoolCourseJourneyUITests: XCTestCase {
    func testParticipantSearchFindsBothHomonymsAfterTheTwentiethLearner() {
        let app = launch("course-roster")
        defer { app.terminate() }
        let add = app.buttons["course-staff-enroll"]
        XCTAssertTrue(add.waitForExistence(timeout: 15), app.debugDescription)
        add.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), app.debugDescription)
        search.tap(); search.typeText("Zoe")
        let candidates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Zoé Exemple", "Réf."))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(candidates.count, 2, app.debugDescription)
        XCTAssertNotEqual(candidates.element(boundBy: 0).label, candidates.element(boundBy: 1).label)
        candidates.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["Inscrire à toute la série"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons.matching(identifier: "Annuler").firstMatch.tap()
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

    func testCancellationNamesTheEnrollmentRatherThanCancellingTheCourse() {
        let app = launch("course-enrolled")
        defer { app.terminate() }
        let cancel = app.buttons["course-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Ton inscription aux 4 séances sera annulée."].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons.matching(identifier: "Garder").firstMatch.tap()
        XCTAssertEqual(app.staticTexts["course-learner-status"].label, "Inscrit")
    }

    func testPaymentsBeforeFirstSessionAndEditedAmountSurviveCloseAndFailure() {
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
        app.navigationBars["Payé sur place"].buttons["Fermer"].tap()
        XCTAssertTrue(app.alerts["Quitter sans conserver le montant ?"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons.matching(identifier: "Continuer").firstMatch.tap()
        XCTAssertEqual(amount.value as? String, "80")
        app.buttons["course-payment-submit"].tap()
        XCTAssertTrue(app.navigationBars["Payé sur place"].exists)
        XCTAssertEqual(amount.value as? String, "80")
    }

    func testCourseEditorProtectsOnlyAnActualChange() {
        let app = launch("course-editor")
        defer { app.terminate() }
        let title = app.textFields["course-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15), app.debugDescription)
        app.navigationBars["Brouillon"].buttons["Fermer"].tap()
        XCTAssertFalse(app.alerts["Quitter sans enregistrer ?"].exists)
        title.tap(); title.typeText(" modifié")
        app.navigationBars["Brouillon"].buttons["Fermer"].tap()
        XCTAssertTrue(app.alerts["Quitter sans enregistrer ?"].waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.buttons.matching(identifier: "Continuer").firstMatch.tap()
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
}
