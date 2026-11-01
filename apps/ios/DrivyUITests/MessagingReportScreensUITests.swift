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

    /// Sélectionne la ligne d'un message pour le signalement. Le fil n'est pas toujours calé en bas : on revient d'abord
    /// en bas par le bouton prévu pour cela (un balayage ne fait pas défiler la liste d'Exyte, et un balayage vers le bas
    /// fermerait la feuille), puis on appuie et on vérifie que la ligne est bien devenue sélectionnée, sinon on recommence.
    private func selectReportRow(containing text: String, app: XCUIApplication, rows: XCUIElementQuery) {
        for _ in 0..<3 {
            let bottom = app.buttons["messaging.scroll.bottom"]
            if bottom.waitForExistence(timeout: 2) {
                bottom.tap()
                _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: bottom)],
                                   timeout: 8)
            }
            // Une bulle simple porte le texte dans le libellé de sa ligne ; une réponse (citation et bulle) le porte
            // dans un élément fils, la ligne elle-même n'a alors pas de libellé.
            let own = rows.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            let nested = rows.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            let row = own.exists ? own : nested
            guard row.waitForExistence(timeout: 10) else { continue }
            if row.isSelected { return }
            if row.isHittable { row.tap() }
            let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: row)
            if XCTWaiter.wait(for: [chosen], timeout: 4) == .completed { return }
        }
        XCTFail(text + " : la ligne n'a pas pu être sélectionnée : " + app.debugDescription)
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
        // répète le texte du message et ne le sélectionne pas. Deux messages du bas du fil, hors de la pastille : un de
        // l'autre personne (rond à droite) et un des miens (rond à gauche).
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "messaging.report.select."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        selectReportRow(containing: "Leçon de conduite confirmée", app: app, rows: rows)
        selectReportRow(containing: "Merci, je les apporte", app: app, rows: rows)
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
