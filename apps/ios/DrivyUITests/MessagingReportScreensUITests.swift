import XCTest

/// Captures réelles (simulateur, iPhone, clair) des écrans de signalement (#77) sur la fixture synthétique
/// `-messaging-ui-reports` : entrée « Signalements » de Messages, boîte, détail déchiffré, statut et historique, puis la
/// confirmation avant transmission. Données fictives en mémoire ; ne qualifie ni les droits serveur ni le chiffrement
/// (voir `MatrixMessagingSealedReportRelayTests`). Les images sont des pièces jointes du test, jamais une preuve physique.
@MainActor
final class MessagingReportScreensUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    // MARK: Aides

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich", "-messaging-ui-reports",
                               "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"] + extra
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
        dismissReportConfirmation(in: app)
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

    // MARK: Médias signalés (#97), frontières synthétiques et vrais workspace/vues

    private func reportMessageID(_ sequence: Int) -> String {
        "b0000001-0000-4000-8000-" + String(format: "%012x", sequence)
    }

    private func assertReportWitness(_ expected: String, in app: XCUIApplication) {
        let witness = app.staticTexts["messaging.report.fixture"]
        XCTAssertTrue(witness.waitForExistence(timeout: 10))
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: witness)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed, "Témoin attendu \(expected), relevé \(witness.label)")
    }

    private func dismissReportConfirmation(in app: XCUIApplication) {
        let cancel = app.buttons["Annuler"].firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap(); return }
        // Native iPad confirmation popovers can omit the cancel action: dismiss outside their bounds.
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.exists)
        let navigation = app.navigationBars.firstMatch
        let point = CGPoint(x: navigation.frame.midX, y: navigation.frame.midY)
        XCTAssertFalse(popover.frame.contains(point))
        navigation.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func waitForMediaReportConfirmation(_ confirm: XCUIElement, phase: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            confirm.exists && confirm.isHittable
        }, object: confirm)
        let result = XCTWaiter.wait(for: [ready], timeout: 10)
        if result != .completed {
            let exists = confirm.exists
            let state = exists
                ? "id=\(confirm.identifier);label=\(confirm.label);frame=\(confirm.frame);enabled=\(confirm.isEnabled);hittable=\(confirm.isHittable)"
                : "exists=false; contrôle non résolu"
            let diagnostic = XCTAttachment(string: "Confirmation média \(phase); attente=\(result.rawValue); \(state)")
            diagnostic.name = "report-confirmation-refusal-\(phase)"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "report-confirmation-refusal-\(phase)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(result, .completed, "La confirmation doit exister et être atteignable dans la même borne de 10 s")
        XCTAssertTrue(confirm.isHittable)
    }

    private func inspectMediaReportConfirmation(in app: XCUIApplication, largeText: Bool) {
        let content = app.scrollViews.containing(.staticText, identifier: "messaging.report.disclosure.recipients").firstMatch
        XCTAssertTrue(content.exists)
        let confirm = app.buttons["messaging.report.confirm"]
        let cancel = app.buttons["messaging.report.confirm.cancel"]
        XCTAssertTrue(cancel.isHittable)
        let expected = [
            ("recipients", "administrateurs de l’école", "pourront lire"),
            ("selection", "Ces 3 messages", "auteur et leur date"),
            ("metadata", "nature, nom", "légende éventuelle"),
            ("file", "Pièce jointe non transmise aux administrateurs", ""),
            ("privacy", "Le reste de la conversation ne leur est pas montré", "")
        ]
        for (part, first, second) in expected {
            let text = app.staticTexts["messaging.report.disclosure." + part]
            XCTAssertTrue(text.exists)
            XCTAssertTrue(text.label.contains(first))
            // `contains("")` est faux : un second repère vide (blocs « file » et « privacy ») n'en exige aucun.
            XCTAssertTrue(second.isEmpty || text.label.contains(second), text.label)
            // A partially hittable paragraph is not proof that its complete disclosure was visible.
            var visible = false
            for gesture in 0...10 {
                let bounds = content.frame.intersection(app.windows.firstMatch.frame)
                let top = max(bounds.minY, app.navigationBars["Signalement"].frame.maxY)
                let bottom = min(bounds.maxY, confirm.frame.minY)
                let frame = text.frame
                visible = text.isHittable && frame.minY >= top && frame.maxY <= bottom
                    && frame.minX >= bounds.minX && frame.maxX <= bounds.maxX
                if visible || gesture == 10 { break }
                XCTAssertGreaterThan(bottom - top, frame.height, "Le bloc doit tenir dans la zone de lecture")
                let downward = frame.minY < top
                let overflow = downward ? top - frame.minY : frame.maxY - bottom
                let distance = min(max(overflow + 12, 24), (bottom - top) * 0.6)
                let startY = downward ? top + 12 : bottom - 12
                let endY = startY + (downward ? distance : -distance)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: bounds.midX, dy: startY)).press(forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: bounds.midX, dy: endY)))
            }
            capture("report-mixed-\(largeText ? "large" : "normal")-\(part)")
            XCTAssertTrue(visible, "Le bloc \(part) doit être entièrement visible après défilement borné")
        }
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(cancel.isHittable)
    }

    /// Gestes natifs bornés dans la liste, sans toucher de modèle ni supposer qu'un élément AX est visible.
    private func revealReportElement(_ target: XCUIElement, in app: XCUIApplication, towardOlder: Bool = false,
                                     contentPrefix: String = "messaging.reports.line.") {
        // iPad also has an inbox list: scope the gesture to the list containing the relevant rows.
        let lists = app.descendants(matching: .any).matching(NSPredicate(format:
            "elementType == %d OR elementType == %d OR elementType == %d",
            XCUIElement.ElementType.collectionView.rawValue, XCUIElement.ElementType.table.rawValue,
            XCUIElement.ElementType.scrollView.rawValue))
        let list = lists.containing(NSPredicate(format: "identifier BEGINSWITH %@",
            towardOlder ? "messaging.report.select." : contentPrefix)).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        for _ in 0..<10 {
            if target.exists && target.isHittable { return }
            let frame = list.frame.intersection(app.windows.firstMatch.frame)
            XCTAssertGreaterThan(frame.height, 100)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * (towardOlder ? 0.3 : 0.8)))
            let end = origin.withOffset(CGVector(dx: frame.midX, dy: frame.minY + frame.height * (towardOlder ? 0.8 : 0.3)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(target.exists && target.isHittable, "Le contrôle doit être visible et atteignable après défilement")
    }

    func testMediaReportDetailInLargeTextDoesNotOpenFiles() {
        let app = launch(extra: ["-messaging-ui-report-media", "-UIPreferredContentSizeCategoryName",
                                 "UICTContentSizeCategoryAccessibilityXXXL"])
        openMessages(app)
        let entry = app.buttons["messaging.reports.open"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        entry.tap()
        let report = element("messaging.reports.row.d0000000-0000-4000-8000-000000000004", in: app)
        XCTAssertTrue(report.waitForExistence(timeout: 10))
        revealReportElement(report, in: app, contentPrefix: "messaging.reports.row.")
        XCTAssertTrue(report.label.contains("6 messages"))
        report.tap()
        XCTAssertTrue(app.navigationBars["Signalement"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("messaging.reports.line.", in: app).waitForExistence(timeout: 15))
        let expected: [(Int, String, String?)] = [
            (23, "Photo · Photo synthétique.png", "Photo de l’exercice fictif"),
            (24, "PDF · Document synthétique.pdf", nil),
            (25, "Photo · Photo synthétique.png", nil),
            (26, "PDF · Document synthétique.pdf", "Consignes du cours fictif")
        ]
        for (sequence, title, caption) in expected {
            let line = element("messaging.reports.line." + reportMessageID(sequence), in: app)
            revealReportElement(line, in: app)
            XCTAssertTrue(line.label.contains("Marc Fixture"))
            XCTAssertTrue(line.label.contains(title), line.label)
            XCTAssertTrue(line.label.contains("Pièce jointe non transmise aux administrateurs"), line.label)
            if let caption { XCTAssertTrue(line.label.contains(caption), line.label) }
            else {
                XCTAssertFalse(line.label.contains("Photo de l’exercice fictif"))
                XCTAssertFalse(line.label.contains("Consignes du cours fictif"))
            }
            XCTAssertNotNil(line.label.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression), "Date et heure conservées")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Ouvrir ' OR label CONTAINS 'Télécharger'")).count, 0)
            capture("report-media-large-\(sequence)")
        }
        let text = element("messaging.reports.line." + reportMessageID(19), in: app)
        revealReportElement(text, in: app)
        XCTAssertTrue(text.label.contains("Texte synthétique conservé"))
        XCTAssertFalse(text.label.contains("Pièce jointe non transmise"))
        let unreadable = element("messaging.reports.line." + reportMessageID(7), in: app)
        revealReportElement(unreadable, in: app)
        XCTAssertTrue(unreadable.label.contains("ne peut pas être lu"))
        XCTAssertFalse(unreadable.label.contains("Photo ·"))
        capture("report-media-large-text-unreadable")
        assertReportWitness("prepared=0;post=0;ack=0;removed=0;files=0;selection=-", in: app)
    }

    func testMixedMediaReportCancellationAndConfirmedSelection() {
        mixedMediaReport(largeText: false)
    }

    func testMixedMediaReportConfirmationInLargeText() {
        mixedMediaReport(largeText: true)
    }

    private func mixedMediaReport(largeText: Bool) {
        var extra = ["-messaging-ui-report-media"]
        if largeText { extra += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        let app = launch(extra: extra)
        openMessages(app)
        let general = app.buttons["messaging.general.open"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 20))
        general.tap()
        let options = app.buttons["messaging.options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        options.tap()
        let start = app.buttons["Signaler des messages"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(element("messaging.report.select.", in: app).waitForExistence(timeout: 15))
        let titles = [24: "PDF", 23: "Photo de l’exercice fictif", 21: "Leçon de conduite confirmée"]
        for sequence in [24, 23, 21] {
            let row = app.buttons["messaging.report.select." + reportMessageID(sequence)]
            revealReportElement(row, in: app, towardOlder: true)
            // Wait for the real decryption before selecting, never seed a selection in the model.
            let readable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", titles[sequence]!), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [readable], timeout: 10), .completed)
            row.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }
        let send = app.buttons["messaging.report.send"]
        XCTAssertTrue(send.isHittable)
        XCTAssertEqual(send.label, "Transmettre (3)")
        assertReportWitness("prepared=0;post=0;ack=0;removed=0;files=0;selection=-", in: app)
        send.tap()
        let confirm = app.buttons["messaging.report.confirm"]
        waitForMediaReportConfirmation(confirm, phase: "first")
        inspectMediaReportConfirmation(in: app, largeText: largeText)
        capture(largeText ? "report-mixed-confirm-large" : "report-mixed-confirm")
        app.buttons["messaging.report.confirm.cancel"].tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertEqual(send.label, "Transmettre (3)")
        assertReportWitness("prepared=0;post=0;ack=0;removed=0;files=0;selection=-", in: app)
        send.tap()
        waitForMediaReportConfirmation(confirm, phase: "second")
        confirm.tap()
        let acknowledgement = app.alerts["Signalement transmis"]
        XCTAssertTrue(acknowledgement.waitForExistence(timeout: 15))
        capture(largeText ? "report-mixed-ack-large" : "report-mixed-ack")
        acknowledgement.buttons["OK"].tap()
        assertReportWitness("prepared=1;post=1;ack=1;removed=1;files=0;selection=21,23,24", in: app)
        XCTAssertFalse(send.exists)
        capture(largeText ? "report-mixed-result-large" : "report-mixed-result")
    }
}
