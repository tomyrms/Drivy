import XCTest

/// Le thème se choisit dans Paramètres, pour le moniteur comme pour l’élève, et reste choisi au relancement.
@MainActor final class AppearanceSettingsTests: XCTestCase {
    /// Le choix est gardé sur le simulateur : il revient à « Automatique » pour les captures qui suivent.
    private func restoreAutomaticAtTheEnd() {
        addTeardownBlock { @MainActor in
            let app = self.launch("profile-tab")
            self.openInstructorSettings(app)
            let automatic = self.appearanceButton(app, "Automatique")
            if automatic.waitForExistence(timeout: 20) { automatic.tap() }
            app.terminate()
        }
    }

    func testInstructorChoosesATheme_itPersistsAfterRelaunch() {
        restoreAutomaticAtTheEnd()
        var app = launch("profile-tab")
        openInstructorSettings(app)
        let dark = appearanceButton(app, "Sombre")
        XCTAssertTrue(dark.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(appearanceButton(app, "Automatique").isSelected, "Automatique par défaut : \(app.debugDescription)")
        dark.tap()
        XCTAssertTrue(dark.isSelected, app.debugDescription)
        // Le fond de page change aussitôt, sans relancer l’app.
        XCTAssertLessThan(pageLuminance(), 0.25, "Thème sombre non appliqué")
        appearanceButton(app, "Clair").tap()
        XCTAssertTrue(appearanceButton(app, "Clair").isSelected, app.debugDescription)
        XCTAssertGreaterThan(pageLuminance(), 0.8, "Thème clair non appliqué")
        dark.tap()
        app.terminate()
        app = launch("profile-tab")
        openInstructorSettings(app)
        let kept = appearanceButton(app, "Sombre")
        XCTAssertTrue(kept.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(kept.isSelected, "Choix perdu au relancement : \(app.debugDescription)")
        XCTAssertLessThan(pageLuminance(), 0.25, "Thème sombre perdu au relancement")
    }

    func testLearnerFindsTheSameChoiceInSettings() {
        restoreAutomaticAtTheEnd()
        let app = launch("learner-profile")
        let settings = app.buttons["profile-open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), app.debugDescription)
        settings.tap()
        let light = appearanceButton(app, "Clair")
        XCTAssertTrue(light.waitForExistence(timeout: 10), app.debugDescription)
        light.tap()
        XCTAssertTrue(light.isSelected, app.debugDescription)
    }

    /// Le Profil du moniteur ouvre ses Paramètres par l’engrenage de la barre de navigation.
    private func openInstructorSettings(_ app: XCUIApplication) {
        let settings = app.buttons["profile-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20), app.debugDescription)
        settings.tap()
        XCTAssertTrue(app.navigationBars["Paramètres"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func appearanceButton(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        let control = app.segmentedControls["settings-appearance"]
        // La section est en bas des Paramètres : la liste défile jusqu’à elle.
        for _ in 0..<4 where !control.waitForExistence(timeout: 5) { app.swipeUp() }
        return control.buttons[title]
    }

    /// Luminance du fond de page, au bord gauche (marge de la liste groupée), à mi-hauteur.
    private func pageLuminance() -> Double {
        Thread.sleep(forTimeInterval: 0.6)
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return -1 }
        let x = 3, y = image.height / 2
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = screen
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }
}
