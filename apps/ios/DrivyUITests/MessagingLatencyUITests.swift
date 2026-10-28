import XCTest

/// Vraies vues et décodeur, transport synthétique retardé : ne mesure ni réseau réel ni appareil physique.
@MainActor final class MessagingLatencyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFifteenSecondResponseKeepsReactionAndComposerUsable() {
        let app = launch(delay: 15)
        let started = react(in: app)
        let capsule = heart(in: app)
        XCTAssertTrue(capsule.waitForExistence(timeout: 3), app.debugDescription)
        let visualSeconds = Date().timeIntervalSince(started)
        XCTAssertLessThan(visualSeconds, 10, "Le retour local précède la réponse retardée de 15 secondes")
        XCTAssertTrue(capsule.label.contains("Cœur 1, vous avez réagi, en cours de synchronisation"), capsule.label)
        let composer = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        XCTAssertTrue(composer.isEnabled)
        let slow = app.descendants(matching: .any)["messaging.mutation.slow"].firstMatch
        let uncertain = app.buttons["messaging.mutation.retry"].firstMatch
        // XCTest peut observer le seuil de cinq secondes après celui de dix sur un runner chargé.
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            slow.exists || uncertain.exists
        }, object: nil)], timeout: 7) == .completed, app.debugDescription)
        XCTAssertTrue(uncertain.waitForExistence(timeout: 7), app.debugDescription)
        capture(app, "Réponse encore non confirmée — synthétique")
        composer.tap(); composer.typeText("Saisie conservée")
        XCTAssertTrue((composer.value as? String)?.contains("Saisie conservée") == true)

        // Confirmée : plus aucun état provisoire lu avec la réaction.
        XCTAssertTrue(wait(target(in: app), "label CONTAINS 'Cœur 1, vous avez réagi' AND NOT (label CONTAINS 'synchronisation')"
                           + " AND NOT (label CONTAINS 'non confirmée') AND NOT (label CONTAINS 'en attente de connexion')",
                           timeout: 12), app.debugDescription)
        XCTAssertFalse(uncertain.exists)
        XCTAssertTrue((composer.value as? String)?.contains("Saisie conservée") == true)
        record(visualSeconds: visualSeconds, confirmationSeconds: Date().timeIntervalSince(started), injectedDelay: 15)
        capture(app, "Réaction confirmée, saisie conservée — synthétique")
    }

    func testFiveSecondResponseCannotReintroduceAQuicklyRemovedReaction() {
        let app = launch(delay: 5)
        let started = react(in: app)
        let capsule = heart(in: app)
        XCTAssertTrue(capsule.waitForExistence(timeout: 3), app.debugDescription)
        let visualSeconds = Date().timeIntervalSince(started)
        target(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 12)).tap()
        XCTAssertTrue(heart(in: app).waitForNonExistence(timeout: 2), "Retrait local immédiat")
        // Deux réponses de cinq secondes : l'ajout ancien puis le retrait sérialisé.
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            XCTAssertFalse(heart(in: app).exists, "L'ancienne confirmation ne réaffiche pas la réaction")
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertFalse(app.buttons["messaging.mutation.retry"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["messaging.mutation.slow"].firstMatch.exists)
        XCTAssertFalse(app.buttons["messaging.mutation.rejected"].firstMatch.exists)
        record(visualSeconds: visualSeconds, confirmationSeconds: nil, injectedDelay: 5)
        capture(app, "Retrait conservé après réponses retardées — synthétique")
    }

    func testOneSecondRefusalRemovesOnlyTheRejectedProjection() {
        let app = launch(delay: 1, refused: true)
        _ = react(in: app)
        let rejection = app.buttons["messaging.mutation.rejected"].firstMatch
        XCTAssertTrue(rejection.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(rejection.label.contains("Réaction non enregistrée"))
        XCTAssertFalse(heart(in: app).exists)
        XCTAssertTrue(target(in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["messaging.compose.text"].firstMatch.isEnabled)
        capture(app, "Refus de réaction, conversation conservée — synthétique")
    }

    private func launch(delay: Int, refused: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich", "-messaging-ui-mutation-delay=\(delay)",
                               "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        if refused { app.launchArguments.append("-messaging-ui-mutation-refused") }
        app.launch()
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15), app.debugDescription)
        entry.tap()
        let general = app.buttons["messaging.general.open"].firstMatch
        XCTAssertTrue(wait(general, "exists == true AND hittable == true", timeout: 15), app.debugDescription)
        general.tap()
        XCTAssertTrue(target(in: app).waitForExistence(timeout: 10), app.debugDescription)
        return app
    }

    private func react(in app: XCUIApplication) -> Date {
        let message = target(in: app)
        XCTAssertTrue(wait(message, "hittable == true", timeout: 5), app.debugDescription)
        message.press(forDuration: 0.6)
        let action = app.buttons.matching(NSPredicate(format: "label == 'Cœur' OR label == '❤️'")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
        let menu = app.staticTexts["Répondre"].firstMatch
        let start = Date(); action.tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 3), "La palette se ferme sans attendre le réseau")
        return start
    }
    /// Bulle du fil Exyte (#182) : un seul élément « auteur, texte, heure, réactions ». Requête typée : parcourir
    /// toute la hiérarchie coûte plusieurs secondes sur le simulateur iPad et fausse la mesure de latence.
    private func target(in app: XCUIApplication) -> XCUIElement {
        app.otherElements.matching(NSPredicate(
            format: "identifier == 'messaging.message' AND label CONTAINS %@", "Rendez-vous à 14 h devant l'auto-école")).firstMatch
    }
    /// Ma réaction Cœur, lue dans l'étiquette de la bulle.
    private func heart(in app: XCUIApplication) -> XCUIElement {
        app.otherElements.matching(NSPredicate(
            format: "identifier == 'messaging.message' AND label CONTAINS %@", "Cœur 1, vous avez réagi")).firstMatch
    }
    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: timeout) == .completed
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func record(visualSeconds: Double, confirmationSeconds: Double?, injectedDelay: Int) {
        let text = "Mesure XCTest sur simulateur, transport synthétique. Délai injecté : \(injectedDelay) s. "
            + "Geste → capsule observée : \(visualSeconds) s. "
            + (confirmationSeconds.map { "Geste → confirmation observée : \($0) s." } ?? "Confirmation non chronométrée dans ce scénario.")
        let attachment = XCTAttachment(string: text)
        attachment.name = "Mesures de latence synthétique"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
