import XCTest

/// Deux défauts du fil de Messages relevés pendant la fiabilisation des tests UI (#391), sur la fixture synthétique.
/// Chaque test échoue tant que le défaut existe : il ne contourne pas l'état qu'il vérifie.
@MainActor final class MessagingThreadDefectsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Réaction retirée pendant la bascule « en cours de synchronisation »

    /// La bulle ne doit pas bouger quand « Synchronisation… » apparaît : un contenu qui se déplace sous le doigt à cet instant
    /// fait perdre l'appui sur la bande des réactions (échecs des 28 et 31 octobre, tous à 5,0 à 5,8 s de l'ajout).
    func testBubbleStaysInPlaceWhenTheSyncStateAppears() {
        let app = launch(delay: 15)
        _ = react(in: app)
        XCTAssertTrue(heart(in: app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Répondre"].firstMatch.waitForNonExistence(timeout: 3), "Menu fermé")
        let before = settledFrame(of: target(in: app))
        XCTAssertTrue(app.descendants(matching: .any)["messaging.mutation.slow"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
        let after = settledFrame(of: target(in: app))
        XCTAssertEqual(after.minY, before.minY, accuracy: 1,
                       "La bulle a bougé de \(before.minY - after.minY) pt quand l'état de synchronisation est apparu")
        XCTAssertEqual(after.height, before.height, accuracy: 1, "La hauteur de la bulle a changé")
        attach(app, "Bulle après l'apparition de la synchronisation")
    }

    /// L'appui de retrait part exactement à la bascule : 5 s après l'ajout, à une coordonnée fixée avant, sans relire l'écran.
    func testRemovalTappedAtTheSyncSwitchIsNotLost() {
        let app = launch(delay: 15)
        let started = react(in: app)
        XCTAssertTrue(heart(in: app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Répondre"].firstMatch.waitForNonExistence(timeout: 3), "Menu fermé")
        let frame = settledFrame(of: target(in: app))
        let point = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.minY + 12))
        while Date().timeIntervalSince(started) < 4.9 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        point.tap()
        let removedAfter = Date().timeIntervalSince(started)
        XCTAssertTrue(heart(in: app).waitForNonExistence(timeout: 4),
                      "Retrait perdu : appui parti \(removedAfter) s après l'ajout, la réaction est restée")
        attach(app, "Réaction retirée à la bascule")
    }

    // MARK: Bouton « Charger les messages précédents »

    /// Tant que la page ancienne est attendue, le bouton est en haut du fil : il doit être sous la barre de navigation
    /// et sous la pastille épinglée, donc atteignable au toucher.
    func testOlderMessagesButtonIsReachableAtTheTopOfTheThread() {
        let app = launch(delay: 0, olderDelay: 8)
        let older = app.buttons["Charger les messages précédents"]
        let list = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), app.debugDescription)
        var found = older.exists
        for _ in 0..<25 where !found {
            // Jamais depuis le haut de l'écran : à ce niveau, une feuille se ferme (voir la mémoire des tests de Messages).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
            found = older.exists
        }
        XCTAssertTrue(found, "Le bouton n'apparaît pas en haut du fil : \(app.debugDescription)")
        let bar = app.navigationBars.firstMatch.frame
        let pill = app.buttons["messaging.pinned"].firstMatch
        let button = older.frame
        attach(app, "Haut du fil, page ancienne attendue")
        XCTAssertGreaterThanOrEqual(button.minY, bar.maxY - 1, "Le bouton (\(button)) est derrière la barre de navigation (\(bar))")
        if pill.exists {
            XCTAssertFalse(button.intersects(pill.frame), "Le bouton (\(button)) est derrière la pastille épinglée (\(pill.frame))")
        }
        XCTAssertTrue(older.isHittable, "Le bouton existe mais ne reçoit pas le toucher : \(button)")
    }

    // MARK: Aides

    private func launch(delay: Int, olderDelay: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        if delay > 0 { app.launchArguments.append("-messaging-ui-mutation-delay=\(delay)") }
        if olderDelay > 0 { app.launchArguments.append("-messaging-ui-older-delay=\(olderDelay)") }
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

    /// Appui long sur le dernier message, puis « Réagir : Cœur » : renvoie l'instant de l'appui d'ajout.
    private func react(in app: XCUIApplication) -> Date {
        let message = target(in: app)
        XCTAssertTrue(wait(message, "hittable == true", timeout: 15), app.debugDescription)
        message.press(forDuration: 0.6)
        let action = app.buttons.matching(NSPredicate(format: "label == 'Réagir : Cœur'")).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
        let start = Date(); action.tap()
        return start
    }

    /// Cadre relu jusqu'à ce qu'il ne change plus : la mise en page de la bulle se stabilise après l'ajout de la capsule.
    private func settledFrame(of element: XCUIElement) -> CGRect {
        var frame = element.frame
        for _ in 0..<10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let next = element.frame
            if next == frame { return frame }
            frame = next
        }
        return frame
    }

    private func target(in app: XCUIApplication) -> XCUIElement {
        app.otherElements.matching(NSPredicate(
            format: "identifier == 'messaging.message' AND label CONTAINS %@", "Rendez-vous à 14 h devant l'auto-école")).firstMatch
    }

    private func heart(in app: XCUIApplication) -> XCUIElement {
        app.otherElements.matching(NSPredicate(
            format: "identifier == 'messaging.message' AND label CONTAINS %@", "Cœur 1, vous avez réagi")).firstMatch
    }

    private func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: timeout) == .completed
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
