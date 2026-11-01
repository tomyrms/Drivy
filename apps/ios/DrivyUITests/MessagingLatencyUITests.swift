import XCTest

/// Vraies vues et décodeur, transport synthétique retardé : ne mesure ni réseau réel ni appareil physique.
@MainActor final class MessagingLatencyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFifteenSecondResponseKeepsReactionAndComposerUsable() {
        let app = launch(delay: 15)
        let started = react(in: app)
        let capsule = heart(in: app)
        XCTAssertTrue(capsule.waitForExistence(timeout: 5), app.debugDescription)
        let visualSeconds = Date().timeIntervalSince(started)
        XCTAssertLessThan(visualSeconds, 10, "Le retour local précède la réponse retardée de 15 secondes")
        XCTAssertTrue(capsule.label.contains("Cœur 1, vous avez réagi, en cours de synchronisation"), capsule.label)
        assertMenuClosed(app)
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

    /// Le nom garde l'ancien délai de 5 s : la réponse à l'ajout est retardée de 15 s pour que le retrait, que XCTest ne peut pas
    /// lancer avant 5 s, parte bien avant elle. Le retrait est tapé tout de suite, sans attendre l'état « synchronisation » :
    /// la bulle ne bouge plus à cet instant (docs/implementation/tests-ui-instables-20261101.md).
    func testFiveSecondResponseCannotReintroduceAQuicklyRemovedReaction() {
        let delay = 15
        let app = launch(delay: delay)
        let started = react(in: app)
        let capsule = heart(in: app)
        XCTAssertTrue(capsule.waitForExistence(timeout: 5), app.debugDescription)
        let visualSeconds = Date().timeIntervalSince(started)
        assertMenuClosed(app)
        target(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 12)).tap()
        let removalSeconds = Date().timeIntervalSince(started)
        XCTAssertTrue(heart(in: app).waitForNonExistence(timeout: 2), "Retrait local immédiat")
        // Deux réponses retardées : l'ajout ancien (à `delay`), puis le retrait sérialisé (à 2 × `delay`). La fenêtre part de
        // l'ajout et non du retrait : elle couvre les deux réponses quelle que soit la lenteur du runner avant la tape.
        let deadline = started.addingTimeInterval(Double(2 * delay) + 8)
        while Date() < deadline {
            XCTAssertFalse(heart(in: app).exists, "L'ancienne confirmation ne réaffiche pas la réaction")
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertFalse(app.buttons["messaging.mutation.retry"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["messaging.mutation.slow"].firstMatch.exists)
        XCTAssertFalse(app.buttons["messaging.mutation.rejected"].firstMatch.exists)
        record(visualSeconds: visualSeconds, confirmationSeconds: nil, injectedDelay: delay)
        // La preuve que le scénario visé a eu lieu : le retrait précède la réponse retardée de l'ajout.
        let order = XCTAttachment(string: "Retrait envoyé \(removalSeconds) s après l'ajout ; réponse retardée à \(delay) s.")
        order.name = "Ordre retrait / réponse"; order.lifetime = .keepAlways; add(order)
        capture(app, "Retrait conservé après réponses retardées — synthétique")
    }

    func testOneSecondRefusalRemovesOnlyTheRejectedProjection() {
        let app = launch(delay: 1, refused: true)
        _ = react(in: app)
        assertMenuClosed(app)
        let rejection = app.buttons["messaging.mutation.rejected"].firstMatch
        XCTAssertTrue(rejection.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(rejection.label.contains("Réaction non enregistrée"))
        XCTAssertFalse(heart(in: app).exists)
        XCTAssertTrue(target(in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["messaging.compose.text"].firstMatch.isEnabled)
        capture(app, "Refus de réaction, conversation conservée — synthétique")
        // #177 : l'appui ouvre la raison et les choix ; masquer est un choix distinct qui ne touche pas au fil.
        rejection.tap()
        let hide = app.buttons["Masquer"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 3), app.debugDescription)
        hide.tap()
        XCTAssertTrue(rejection.waitForNonExistence(timeout: 3))
        XCTAssertTrue(target(in: app).exists)
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
        // Même délai que le contrôle du fil : une lecture de la hiérarchie peut prendre 4 s sur un simulateur chargé.
        XCTAssertTrue(wait(message, "hittable == true", timeout: 15), app.debugDescription)
        message.press(forDuration: 0.6)
        // Le menu natif (77c02b7b) expose chaque réaction sous « Réagir : <nom> ».
        let action = app.buttons.matching(NSPredicate(format: "label == 'Réagir : Cœur'")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
        let start = Date(); action.tap()
        return start
    }
    /// Vérifiée après la mesure : la lecture de l'écran par XCTest ne doit pas entrer dans le chronomètre.
    private func assertMenuClosed(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Répondre"].firstMatch.waitForNonExistence(timeout: 3),
                      "La palette se ferme sans attendre le réseau")
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
