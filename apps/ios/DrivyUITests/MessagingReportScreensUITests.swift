import XCTest

/// Captures réelles (simulateur, iPhone, clair) des écrans de signalement (#77) sur la fixture synthétique
/// `-messaging-ui-reports` : entrée « Signalements » de Messages, boîte, détail déchiffré, statut et historique, puis la
/// confirmation avant transmission. Données fictives en mémoire ; ne qualifie ni les droits serveur ni le chiffrement
/// (voir `MatrixMessagingSealedReportRelayTests`). Les images sont des pièces jointes du test, jamais une preuve physique.
@MainActor
final class MessagingReportScreensUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Aides

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich", "-messaging-ui-reports",
                               "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        for attempt in 0..<2 {
            app.launch()
            if app.wait(for: .runningForeground, timeout: 20) { return app }
            if attempt == 0 { app.terminate() }
        }
        return app
    }

    private func capture(_ name: String) {
        // Le simulateur affiche parfois une bannière système (« Ready for Apple Intelligence ») qui masque l'en-tête de
        // l'app : on attend qu'elle disparaisse avant de photographier.
        let banner = XCUIApplication(bundleIdentifier: "com.apple.springboard").otherElements["NotificationShortLookView"]
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: banner)],
                           timeout: 8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// Sélectionne, parmi les lignes proposées, la première qui est entièrement visible (hors de la pastille épinglée en
    /// haut et de la barre du bas). Le fil n'est pas toujours calé en bas à l'ouverture (il peut rester plus d'un écran
    /// au-dessus), et un balayage ne fait pas défiler la liste d'Exyte : on prend ce qui est à l'écran, puis on vérifie que
    /// la ligne est devenue sélectionnée, sinon on essaie la suivante.
    private func selectVisibleRow(_ candidates: XCUIElementQuery, _ description: String, app: XCUIApplication) {
        for _ in 0..<3 {
            for row in candidates.allElementsBoundByIndex where row.exists && row.isHittable {
                let frame = row.frame
                guard frame.minY > 190, frame.maxY < 790, frame.height > 40 else { continue }
                row.tap()
                let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: row)
                if XCTWaiter.wait(for: [chosen], timeout: 4) == .completed { return }
            }
        }
        XCTFail(description + " : aucune ligne visible n'a pu être sélectionnée : " + app.debugDescription)
    }

    private func openMessages(_ app: XCUIApplication) {
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15), app.debugDescription)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 10), app.debugDescription)
    }

    // MARK: Boîte des administrateurs

    func testAdministratorInboxDetailAndStatus() {
        let app = launch()
        openMessages(app)
        // L'entrée n'apparaît qu'une fois la lecture de la boîte confirmée par le serveur de la fixture.
        let entry = app.buttons["messaging.reports.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20), app.debugDescription)
        capture("01-messages-entree-signalements")

        entry.tap()
        XCTAssertTrue(app.navigationBars["Signalements"].waitForExistence(timeout: 10), app.debugDescription)
        let firstRow = element("messaging.reports.row.", in: app)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), app.debugDescription)
        capture("02-boite-signalements")

        firstRow.tap()
        XCTAssertTrue(app.navigationBars["Signalement"].waitForExistence(timeout: 10), app.debugDescription)
        let line = element("messaging.reports.line.", in: app)
        XCTAssertTrue(line.waitForExistence(timeout: 15), "Les messages signalés se déchiffrent : " + app.debugDescription)
        capture("03-signalement-messages-dechiffres")

        // Le statut et l'historique sont plus bas : on fait défiler la page, jamais glisser vers le bas (feuille).
        app.swipeUp()
        let handle = app.buttons["messaging.reports.set.handled"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10), app.debugDescription)
        capture("04-signalement-statut")
        handle.tap()
        let status = element("messaging.reports.status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 10), app.debugDescription)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Traité'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed, app.debugDescription)
        app.swipeUp()
        capture("05-statut-traite-et-historique")
    }

    // MARK: Confirmation avant transmission

    func testConfirmationBeforeSendingAReport() {
        let app = launch()
        openMessages(app)
        let general = app.buttons["messaging.general.open"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 20), app.debugDescription)
        general.tap()
        let options = app.buttons["messaging.options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15), app.debugDescription)
        options.tap()
        let startReport = app.buttons["Signaler des messages"]
        XCTAssertTrue(startReport.waitForExistence(timeout: 10), app.debugDescription)
        startReport.tap()

        // Les lignes de sélection portent un identifiant propre : un libellé seul vise aussi la pastille épinglée, qui
        // répète le texte du message et ne le sélectionne pas.
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "messaging.report.select."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        // Un message des miens (rond à gauche), puis un de l'autre personne (rond à droite). La ligne d'une réponse (citation
        // et bulle) n'a pas de libellé propre : le texte est dans un élément fils.
        selectVisibleRow(rows.matching(NSPredicate(format: "label BEGINSWITH %@ OR label == %@", "Vous,", "")), "message envoyé",
                         app: app)
        selectVisibleRow(rows.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Léa Fixture,", "Marc Fixture,")),
                         "message reçu", app: app)
        let selectedRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isSelected == true",
                                                            "messaging.report.select."))
        // Les deux ronds ont fini leur transition avant la capture ; la capture précède le contrôle pour survivre à un échec.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: selectedRows)],
                           timeout: 5)
        capture("06-selection-des-messages")
        XCTAssertEqual(selectedRows.count, 2, "Les deux messages choisis sont sélectionnés : " + app.debugDescription)

        let send = app.buttons["messaging.report.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), app.debugDescription)
        send.tap()
        let confirm = app.buttons["messaging.report.confirm"]
        let shown = confirm.waitForExistence(timeout: 10)
        capture("07-confirmation-avant-transmission")
        XCTAssertTrue(shown, "La confirmation doit s'afficher avant tout envoi : " + app.debugDescription)
        // Annuler : rien n'est transmis.
        app.buttons["Annuler"].firstMatch.tap()
    }

    // MARK: Message illisible

    /// Le troisième signalement de la fixture porte un message qu'aucun appareil ne peut déchiffrer : l'écran le dit au
    /// lieu d'afficher un texte vide ou inventé.
    func testUnreadableReportedMessageIsStatedPlainly() {
        let app = launch()
        openMessages(app)
        let entry = app.buttons["messaging.reports.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20), app.debugDescription)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Signalements"].waitForExistence(timeout: 10), app.debugDescription)
        let row = app.descendants(matching: .any)["messaging.reports.row.d0000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(app.navigationBars["Signalement"].waitForExistence(timeout: 10), app.debugDescription)
        let line = element("messaging.reports.line.", in: app)
        XCTAssertTrue(line.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(line.label.contains("ne peut pas être lu"), "Le message illisible est dit : " + line.label)
        capture("05b-message-illisible")
    }
}
