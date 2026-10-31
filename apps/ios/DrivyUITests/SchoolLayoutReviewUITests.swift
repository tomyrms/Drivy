import XCTest
import UIKit

/// Contrôles opt-in des vraies vues, avec données synthétiques et sans écriture réseau.
@MainActor final class SchoolLayoutReviewUITests: XCTestCase {
    func testNarrowNameFieldsPreserveInputAndFocusThroughRotation() throws {
        let app = launch("access-register-narrow")
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let first = app.textFields["access-first-name"], last = app.textFields["access-last-name"]
        XCTAssertTrue(first.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(waitUntil { last.exists && last.frame.minY >= first.frame.maxY }, app.debugDescription)
        XCTAssertEqual(first.frame.width, last.frame.width, accuracy: 2)
        let initialLast = try XCTUnwrap(last.value as? String)
        first.tap(); first.typeText(" Rotation")
        let initialFirst = try XCTUnwrap(first.value as? String)
        rotate(app, to: .landscapeLeft)
        XCTAssertEqual(first.value as? String, initialFirst)
        XCTAssertEqual(last.value as? String, initialLast)
        // Saisir sans retoucher le champ vérifie que le focus n’a pas changé avec AnyLayout.
        first.typeText(" Suite")
        let updated = try XCTUnwrap(first.value as? String)
        XCTAssertTrue(updated.contains(" Suite"))
        rotate(app, to: .portrait)
        XCTAssertEqual(first.value as? String, updated)
        XCTAssertEqual(last.value as? String, initialLast)
        first.typeText("\n")
        last.typeText(" Nom")
        XCTAssertTrue((last.value as? String)?.contains(" Nom") == true)
        XCTAssertEqual(first.value as? String, updated)
    }

    func testAccessibleNameFieldsUseTwoRows() {
        let app = launch("access-register-long", largeText: true)
        defer { app.terminate() }
        let first = app.textFields["access-first-name"], last = app.textFields["access-last-name"]
        XCTAssertTrue(first.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(waitUntil { last.exists && last.frame.minY >= first.frame.maxY }, app.debugDescription)
        XCTAssertEqual(first.frame.width, last.frame.width, accuracy: 2)
        XCTAssertEqual(last.value as? String, "De la Roche Montferrand")
        capture("access-register-large-text-synthetic")
    }

    func testPaymentHistoryKeepsVoidedEntriesAndTargetsTheChosenCorrection() {
        let app = launch("course-payments-history")
        defer { app.terminate() }
        let chosenID = "10000000-0000-4000-8000-000000000750"
        let voidedID = "10000000-0000-4000-8000-000000000751"
        let options = app.buttons["course-payment-options-\(chosenID)"]
        XCTAssertTrue(options.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["course-payment-history-\(voidedID)"].exists)
        XCTAssertFalse(app.buttons["course-payment-options-\(voidedID)"].exists)
        reveal(options, in: app)
        XCTAssertTrue(options.label.contains("30") && options.label.contains("Alex Exemple"), options.label)
        options.tap()
        let correction = app.buttons["course-payment-void"]
        XCTAssertTrue(correction.waitForExistence(timeout: 5), app.debugDescription)
        correction.tap()
        let reason = app.descendants(matching: .any)["course-reversal-reason"]
        let submit = app.buttons["course-reversal-submit"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(submit.isEnabled)
        reason.tap(); reason.typeText("Erreur dans l’exemple")
        XCTAssertTrue(submit.isEnabled)
        reveal(submit, in: app)
        submit.tap()
        let confirmation = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "Annuler le règlement de", "30", "Alex Exemple")).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5), app.debugDescription)
        // Le test s’arrête avant l’envoi ; le motif et la confirmation restent ceux du parcours existant.
        capture("course-payment-correction-synthetic")
    }

    func testPendingInvitationHasOneVerificationControlAcrossOrientationsAndBack() {
        let app = launch("invitation-feedback")
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let verification = app.buttons.matching(identifier: "invitation-verify-command")
        XCTAssertTrue(waitUntil(timeout: 15) { verification.count == 1 }, app.debugDescription)
        rotate(app, to: .landscapeLeft)
        XCTAssertTrue(waitUntil { verification.count == 1 }, app.debugDescription)
        rotate(app, to: .portrait)
        XCTAssertTrue(waitUntil { verification.count == 1 }, app.debugDescription)
        // En fenêtre compacte, le retour à la liste ne perd pas le suivi de la demande.
        let back = app.navigationBars.buttons["Invitations"]
        if back.exists && back.isHittable {
            back.tap()
            XCTAssertTrue(waitUntil { verification.count == 1 }, app.debugDescription)
        }
        capture("invitation-pending-single-feedback-synthetic")
    }

    func testInvitationSuccessHasOnePrimaryMessage() {
        let app = launch("invitation-success")
        defer { app.terminate() }
        // Un Label combiné expose son texte deux fois à XCUITest (l'élément combiné et son enfant) :
        // l'unicité se vérifie sur le bloc d'avis, présent une seule fois quelle que soit la colonne.
        let feedback = app.descendants(matching: .any).matching(identifier: "invitations-feedback-success")
        XCTAssertTrue(waitUntil(timeout: 15) { feedback.count == 1 }, app.debugDescription)
        XCTAssertTrue(feedback.firstMatch.staticTexts["Code révoqué."].exists, app.debugDescription)
        capture("invitation-success-single-feedback-synthetic")
    }

    private func launch(_ screen: String, largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchEnvironment["DRIVY_VISUAL_LARGE_TEXT"] = largeText ? "1" : "0"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH", "-AppleInterfaceStyle", "Light"]
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        XCTAssertTrue(waitUntil(timeout: 10) { (app.frame.width > app.frame.height) == orientation.isLandscape })
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return condition()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
