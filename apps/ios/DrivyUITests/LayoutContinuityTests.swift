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
        let edit = app.buttons["lesson-report-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20), app.debugDescription)
        edit.tap()
        let save = app.buttons["lesson-save-report"]
        let next = app.buttons["lesson-report-next"]
        for _ in 0..<3 where !save.waitForExistence(timeout: 5) { if next.exists { next.tap() } }
        XCTAssertTrue(save.waitForExistence(timeout: 10), app.debugDescription)

        let field = reportField(in: app)
        // Sur une petite fenêtre, la carte précède le formulaire dans le même défilement.
        // Chercher aussi les cellules pas encore créées par Form ; le bord droit évite
        // d’envoyer le geste à MapKit au centre de la carte.
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
        let expected = try XCTUnwrap(field.value as? String)
        XCTAssertNotEqual(expected, original)
        XCTAssertTrue(expected.contains("Rotation 29"))

        rotate(app, to: .landscapeLeft)
        XCTAssertTrue(reportField(in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(reportField(in: app).value as? String, expected)
        XCTAssertTrue(save.exists)
        capture(name: "lesson-unsaved-landscape")

        rotate(app, to: .portrait)
        XCTAssertTrue(reportField(in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(reportField(in: app).value as? String, expected)
        XCTAssertTrue(save.exists)
        capture(name: "lesson-unsaved-portrait")
        // La sauvegarde n’est jamais appelée : on vérifie la saisie, pas une relecture serveur.
        app.terminate()
    }

    private func reportField(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND (elementType == %lu OR elementType == %lu)",
            "Travail réalisé", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue
        )).firstMatch
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
