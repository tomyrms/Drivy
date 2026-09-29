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
        let save = app.buttons["lesson-save-report"]
        XCTAssertTrue(save.waitForExistence(timeout: 20), app.debugDescription)

        let field = reportField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        // Sur une petite fenêtre, la carte précède le formulaire dans le même défilement.
        for _ in 0..<6 where !field.isHittable { app.swipeUp() }
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
