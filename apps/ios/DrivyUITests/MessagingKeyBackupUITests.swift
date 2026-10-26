import XCTest

/// Sauvegarde des clés (#169, #170, #141) sur la fixture synthétique : aucune vraie clé, aucun service.
final class MessagingKeyBackupUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    private func openBackup(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-backup"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["messages-entry"].waitForExistence(timeout: 10))
        app.buttons["messages-entry"].tap()
        XCTAssertTrue(app.buttons["messaging.inbox.more"].waitForExistence(timeout: 5))
        app.buttons["messaging.inbox.more"].tap(); app.buttons["messaging.settings.open"].tap()
        let open = app.buttons["messaging.backup.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.backup.pending"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func restore(_ app: XCUIApplication, _ text: String) {
        let field = app.secureTextFields["messaging.backup.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24) + text)
        let button = app.buttons["messaging.backup.restore"]
        if !button.isHittable { app.swipeUp() }
        button.tap()
        // L'erreur est en tête du formulaire : la ramener à l'écran (liste paresseuse).
        app.swipeDown(); app.swipeDown()
    }

    /// #170 : retour, glissement et balayage de la feuille ne font pas disparaître la clé ; sortie explicite avertie.
    @MainActor
    func testUnconfirmedKeyGuardsExitAndKeepsExplicitWayOut() {
        let app = openBackup()
        app.buttons["messaging.backup.create"].tap()
        let key = app.staticTexts["messaging.backup.key"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["messaging.backup.key.once"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Réglages"].exists, "Pas de retour silencieux")
        attach(app, "backup-cle-affichee")

        // Glissement depuis le bord gauche et balayage vers le bas de la feuille.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertTrue(key.waitForExistence(timeout: 2), "Le glissement de retour ne retire pas la clé")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(key.waitForExistence(timeout: 2), "Le balayage de la feuille ne retire pas la clé")

        // Sortie explicite : avertissement, puis on peut revenir à la clé.
        app.buttons["messaging.backup.exit"].tap()
        XCTAssertTrue(app.buttons["messaging.backup.exit.confirm"].waitForExistence(timeout: 5))
        attach(app, "backup-sortie-avertie")
        let back = app.buttons["messaging.backup.exit.cancel"]
        // iOS 26 peut présenter la feuille d'action sans bouton d'annulation visible : toucher hors de la feuille.
        if back.exists && back.isHittable { back.tap() }
        else if app.otherElements["PopoverDismissRegion"].exists { app.otherElements["PopoverDismissRegion"].tap() }
        else { window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap() }
        XCTAssertFalse(app.buttons["messaging.backup.exit.confirm"].waitForExistence(timeout: 1))
        XCTAssertTrue(key.waitForExistence(timeout: 2))

        // Quitter sans la clé : retour aux réglages, la clé ne réapparaît jamais.
        app.buttons["messaging.backup.exit"].tap()
        app.buttons["messaging.backup.exit.confirm"].tap()
        let open = app.buttons["messaging.backup.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["messaging.backup.create"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["messaging.backup.key"].exists)
    }

    /// #170 : la confirmation purge la clé et rend le retour normal.
    @MainActor
    func testConfirmationPurgesKeyAndRestoresBack() {
        let app = openBackup()
        app.buttons["messaging.backup.create"].tap()
        XCTAssertTrue(app.staticTexts["messaging.backup.key"].waitForExistence(timeout: 5))
        app.buttons["messaging.backup.key.done"].tap()
        XCTAssertTrue(app.buttons["messaging.backup.create"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["messaging.backup.key"].exists)
        XCTAssertFalse(app.buttons["messaging.backup.exit"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["messaging.backup.open"].waitForExistence(timeout: 5))
    }

    /// #169 + #141 : réseau, session, clé refusée et restauration partielle ont leur message, en grand texte.
    @MainActor
    func testRestoreErrorsAreDistinctWithLargeText() {
        let app = openBackup(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let error = app.descendants(matching: .any)["messaging.backup.error"]

        restore(app, "reseau")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("injoignable"), error.label)
        XCTAssertFalse(error.label.contains("refusée"), "Une panne n'accuse pas la clé")
        XCTAssertTrue(app.buttons["messaging.backup.retry"].exists)
        attach(app, "backup-reseau-grand-texte")

        restore(app, "session")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("session"), error.label)
        XCTAssertFalse(error.label.contains("refusée"))

        restore(app, "mauvaise")
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("refusée"), error.label)
        XCTAssertFalse(app.buttons["messaging.backup.retry"].exists)
        attach(app, "backup-cle-refusee-grand-texte")

        restore(app, "partielle")
        let partial = app.descendants(matching: .any)["messaging.backup.notRestored"]
        XCTAssertTrue(partial.waitForExistence(timeout: 5))
        XCTAssertFalse(error.exists)
        XCTAssertFalse(app.descendants(matching: .any)["messaging.backup.restored"].exists, "Pas de faux succès complet")
        attach(app, "backup-partielle-grand-texte")
    }

    /// #141 : mêmes états en sombre Soft Charcoal (captures de revue, données synthétiques).
    @MainActor
    func testAlertsInDarkAppearance() {
        let app = openBackup(["-drivy.appearance", "dark"])
        attach(app, "backup-retard-sombre")
        restore(app, "reseau")
        XCTAssertTrue(app.descendants(matching: .any)["messaging.backup.error"].waitForExistence(timeout: 5))
        attach(app, "backup-reseau-sombre")
        restore(app, "mauvaise")
        XCTAssertTrue(app.descendants(matching: .any)["messaging.backup.error"].waitForExistence(timeout: 5))
        attach(app, "backup-cle-refusee-sombre")
    }
}
