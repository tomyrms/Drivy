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
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
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
        // Le fil avant la sélection : sert de référence pour juger la mise en page de la sélection.
        capture("06a-fil-avant-selection")
        options.tap()
        let startReport = app.buttons["Signaler des messages"]
        XCTAssertTrue(startReport.waitForExistence(timeout: 10), app.debugDescription)
        startReport.tap()

        // Les lignes de sélection portent un identifiant propre : un libellé seul vise aussi la pastille épinglée, qui
        // répète le texte du message et ne le sélectionne pas.
        for text in ["Pensez aux papiers du permis", "Leçon de conduite confirmée"] {
            let predicate = NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "messaging.report.select.", text)
            let row = app.buttons.matching(predicate).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15), text + " : " + app.debugDescription)
            row.tap()
        }
        capture("06-selection-des-messages")
        let selectedRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isSelected == true",
                                                            "messaging.report.select."))
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
