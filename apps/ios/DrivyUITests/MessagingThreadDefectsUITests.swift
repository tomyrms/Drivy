import XCTest

/// Défaut du fil de Messages relevé pendant la fiabilisation des tests UI (#391), sur la fixture synthétique.
/// Le test échoue tant que le défaut existe : il ne contourne pas l'état qu'il vérifie.
@MainActor final class MessagingThreadDefectsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Bulle immobile à la bascule « en cours de synchronisation »

    /// Le texte de la bulle ne doit pas bouger quand « Synchronisation… » apparaît (5 s après l'ajout) : la liste est ancrée en bas,
    /// une ligne qui s'ajoute sous la bulle la remontait de 13 pt, sous le doigt qui retire la réaction (échecs des 28 et 31 octobre,
    /// tous à 5,0 à 5,8 s de l'ajout). Rouge sur master (run 41260444123). Le texte est mesuré, pas le cadre d'accessibilité de la
    /// bulle, qui englobe aussi l'indicateur.
    func testBubbleStaysInPlaceWhenTheSyncStateAppears() {
        let app = launch(delay: 15)
        _ = react(in: app)
        XCTAssertTrue(heart(in: app).waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Répondre"].firstMatch.waitForNonExistence(timeout: 3), "Menu fermé")
        let text = app.staticTexts["Rendez-vous à 14 h devant l'auto-école"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), app.debugDescription)
        let before = settledFrame(of: text)
        XCTAssertTrue(app.descendants(matching: .any)["messaging.mutation.slow"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
        let after = settledFrame(of: text)
        XCTAssertEqual(after.minY, before.minY, accuracy: 1,
                       "Le texte de la bulle a bougé de \(before.minY - after.minY) pt quand l'état de synchronisation est apparu")
        attach(app, "Bulle après l'apparition de la synchronisation")
    }

    // MARK: Aides

    private func launch(delay: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich", "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        if delay > 0 { app.launchArguments.append("-messaging-ui-mutation-delay=\(delay)") }
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
