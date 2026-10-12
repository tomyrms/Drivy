import XCTest

/// Tirer pour actualiser le dossier d’un élève relit ce qu’il montre sans jamais afficher d’erreur :
/// une relecture n’est pas une panne, même répétée.
@MainActor final class DossierRefreshTests: XCTestCase {
    func testPullingToRefreshTheDossierNeverShowsAnInterruption() {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "learners"
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        let learner = app.descendants(matching: .any).matching(identifier: "school-learner-10000000-0000-4000-8000-000000000004").firstMatch
        XCTAssertTrue(learner.waitForExistence(timeout: 20), app.debugDescription)
        learner.tap()
        let dossier = app.scrollViews["learner-dossier"]
        XCTAssertTrue(dossier.waitForExistence(timeout: 30), app.debugDescription)
        let progression = app.segmentedControls.buttons["Progression"]
        XCTAssertTrue(progression.waitForExistence(timeout: 20), app.debugDescription)

        let retry = app.buttons.matching(NSPredicate(format: "label == %@", "Réessayer")).firstMatch
        let interrupted = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "interrompu")).firstMatch
        // Trois relectures de suite, la dernière lancée aussitôt après la précédente.
        for pause in [3.0, 3.0, 0.3] {
            pullToRefresh(dossier)
            Thread.sleep(forTimeInterval: pause)
            XCTAssertFalse(interrupted.exists, "Relecture présentée comme une interruption : \(app.debugDescription)")
            XCTAssertFalse(retry.exists, "Erreur affichée après une relecture : \(app.debugDescription)")
        }
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(interrupted.exists, app.debugDescription)
        XCTAssertFalse(retry.exists, app.debugDescription)
        // Le dossier reste en place : identité, sélecteur et leçons.
        XCTAssertTrue(app.descendants(matching: .any)["learner-profile-first-name"].exists, app.debugDescription)
        XCTAssertTrue(progression.exists, app.debugDescription)
    }

    private func pullToRefresh(_ scroll: XCUIElement) {
        let top = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        top.press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
    }
}
