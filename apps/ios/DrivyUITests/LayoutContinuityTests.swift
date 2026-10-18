import XCTest
import UIKit

/// Une rotation ne doit pas remplacer le modèle qui possède la saisie du bilan.
@MainActor final class LayoutContinuityTests: XCTestCase {
    func testUnsavedReportTextSurvivesPortraitLandscapeAndBack() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "lesson"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        // La fiche s’ouvre en lecture ; la rédaction se pousse, et l’enregistrement est à sa dernière étape.
        // « Modifier le bilan » vit dans le menu de la barre quand un bilan est déjà enregistré.
        let edit = app.buttons["lesson-report-edit"]
        XCTAssertTrue(app.descendants(matching: .any)["lesson-summary"].waitForExistence(timeout: 20), app.debugDescription)
        if !edit.exists {
            let more = app.descendants(matching: .any)["lesson-more-actions"]
            XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
            more.tap()
        }
        XCTAssertTrue(edit.waitForExistence(timeout: 10), app.debugDescription)
        edit.tap()
        let save = app.buttons["lesson-save-report"]
        let next = app.buttons["lesson-report-next"]
        XCTAssertTrue(stepTitle(in: app).waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(stepTitle(in: app).label.hasPrefix("Bilan"), app.debugDescription)
        XCTAssertFalse(save.exists)

        let field = reportField(in: app)
        // Chercher aussi les cellules pas encore créées par Form.
        for _ in 0..<6 {
            if field.exists && field.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.85))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(field.exists, app.debugDescription)
        XCTAssertTrue(field.isHittable)
        let original = try XCTUnwrap(field.value as? String)
        field.tap()
        field.typeText(" Rotation 29")
        var expected = try XCTUnwrap(field.value as? String)
        XCTAssertNotEqual(expected, original)
        XCTAssertTrue(expected.contains("Rotation 29"))

        rotate(app, to: .landscapeLeft)
        XCTAssertTrue(reportField(in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(reportField(in: app).value as? String, expected)
        if app.frame.height < 500 {
            // La fenêtre iPhone en paysage doit laisser une vraie ligne de saisie entre la barre de navigation
            // et le clavier. L’existence et la valeur du champ seules ne prouvent pas qu’on peut encore l’utiliser.
            let closeKeyboard = app.buttons["lesson-report-dismiss-keyboard"]
            XCTAssertTrue(waitUntil { closeKeyboard.exists && closeKeyboard.isHittable && !save.exists }, app.debugDescription)
            XCTAssertTrue(waitUntil { reportFieldIsVisibleAboveKeyboard(in: app, save: save) }, app.debugDescription)
            let beforeLandscapeInput = expected
            reportField(in: app).typeText(" Paysage")
            expected = try XCTUnwrap(reportField(in: app).value as? String)
            XCTAssertTrue(expected.contains(" Paysage"))
            XCTAssertEqual(expected.replacingOccurrences(of: " Paysage", with: ""), beforeLandscapeInput)
            XCTAssertTrue(waitUntil { reportFieldIsVisibleAboveKeyboard(in: app, save: save) }, app.debugDescription)
            capture(name: "lesson-unsaved-landscape")

            closeKeyboard.tap()
            XCTAssertTrue(waitUntil { !app.keyboards.firstMatch.exists && next.exists && next.isHittable && !save.exists }, app.debugDescription)
            XCTAssertEqual(reportField(in: app).value as? String, expected)
            capture(name: "lesson-unsaved-landscape-keyboard-closed")
        } else {
            XCTAssertFalse(save.exists)
            capture(name: "lesson-unsaved-landscape")
        }

        rotate(app, to: .portrait)
        XCTAssertTrue(reportField(in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(reportField(in: app).value as? String, expected)
        XCTAssertFalse(save.exists)
        capture(name: "lesson-unsaved-portrait")

        // La sauvegarde n’apparaît qu’au récapitulatif, qui montre exactement la valeur encore non enregistrée.
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        next.tap()
        XCTAssertTrue(waitUntil { !stepTitle(in: app).label.hasPrefix("Bilan") }, app.debugDescription)
        let hasCompetencies = stepTitle(in: app).label.hasPrefix("Compétences")
        if hasCompetencies {
            XCTAssertFalse(save.exists)
            XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
            next.tap()
        }
        XCTAssertTrue(waitUntil(timeout: 10) { stepTitle(in: app).label.hasPrefix("Récapitulatif") }, app.debugDescription)
        XCTAssertTrue(app.staticTexts[expected].exists, app.debugDescription)
        XCTAssertTrue(save.exists && save.isEnabled)

        // Retour au texte, correction, puis nouvel aperçu : le modèle reste le même et le récap se met à jour.
        back(in: app)
        if hasCompetencies { back(in: app) }
        XCTAssertTrue(waitUntil { stepTitle(in: app).label.hasPrefix("Bilan") }, app.debugDescription)
        let correctedField = reportField(in: app)
        XCTAssertEqual(correctedField.value as? String, expected)
        correctedField.tap()
        correctedField.typeText(" Corrigé")
        expected = try XCTUnwrap(correctedField.value as? String)
        app.buttons["lesson-report-dismiss-keyboard"].tapIfExists()
        XCTAssertTrue(next.waitForExistence(timeout: 5), app.debugDescription)
        next.tap()
        if hasCompetencies {
            XCTAssertTrue(waitUntil { stepTitle(in: app).label.hasPrefix("Compétences") }, app.debugDescription)
            next.tap()
        }
        XCTAssertTrue(waitUntil(timeout: 10) { stepTitle(in: app).label.hasPrefix("Récapitulatif") }, app.debugDescription)
        XCTAssertTrue(app.staticTexts[expected].exists, app.debugDescription)
        XCTAssertTrue(save.exists && save.isEnabled)
        // La sauvegarde n’est jamais appelée : on vérifie la saisie, pas une relecture serveur.
        app.terminate()
    }

    private func stepTitle(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["lesson-report-step"]
    }

    private func reportField(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %lu OR elementType == %lu)",
            "Travail réalisé", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue
        )).firstMatch
    }

    private func reportFieldIsVisibleAboveKeyboard(in app: XCUIApplication, save: XCUIElement) -> Bool {
        let field = reportField(in: app)
        let keyboard = app.keyboards.firstMatch
        guard field.exists, field.isHittable, keyboard.exists, field.frame.height > 0 else { return false }
        let navigation = app.navigationBars.firstMatch
        let top = navigation.exists ? max(app.frame.minY, navigation.frame.maxY) : app.frame.minY
        let bottom = save.exists && save.isHittable ? min(keyboard.frame.minY, save.frame.minY) : keyboard.frame.minY
        let viewport = CGRect(x: app.frame.minX, y: top, width: app.frame.width, height: max(0, bottom - top))
        let visible = field.frame.intersection(viewport)
        return !visible.isNull && visible.height >= min(24, field.frame.height) && visible.width >= min(44, field.frame.width)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    private func back(in app: XCUIApplication) {
        let button = app.navigationBars.firstMatch.buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), app.debugDescription)
        button.tap()
    }

    private func rotate(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let landscape = orientation.isLandscape
        let deadline = Date().addingTimeInterval(10)
        while (app.frame.width > app.frame.height) != landscape, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(app.frame.width, 0)
        XCTAssertGreaterThan(app.frame.height, 0)
        XCTAssertEqual(app.frame.width > app.frame.height, landscape,
                       "La fenêtre doit réellement adopter l’orientation demandée.")
    }

    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func tapIfExists() {
        if waitForExistence(timeout: 2), isHittable { tap() }
    }
}
