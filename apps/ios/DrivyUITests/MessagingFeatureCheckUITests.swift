import XCTest

/// Contrôle fonctionnel de la messagerie sur la fixture synthétique enrichie (`-messaging-ui-rich`).
/// Données fictives en mémoire, déchiffrement fixture seulement, aucun envoi possible.
/// Une capture par fonctionnalité. Ne qualifie ni le chiffrement réel, ni les droits serveur, ni VoiceOver physique.
@MainActor
final class MessagingFeatureCheckUITests: XCTestCase {
    private enum ID {
        static let lea = "messaging.conversation.A0000000-0000-4000-8000-000000000002"
        static let marc = "messaging.conversation.A0000000-0000-4000-8000-000000000003"
        static let general = "messaging.general.open"
    }

    override func setUp() { continueAfterFailure = false }

    override func tearDown() {
        if #available(iOS 17.0, *) { XCUIDevice.shared.appearance = .unspecified }
        super.tearDown()
    }

    // MARK: Aides

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich"] + extra
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitFor(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @discardableResult
    private func openInbox(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Entrée Messages", file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5), "Liste Messages", file: file, line: line)
        let general = app.buttons[ID.general].firstMatch
        XCTAssertTrue(waitFor(general, "exists == true AND hittable == true"), "Ligne du général", file: file, line: line)
        return general
    }

    private func text(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", value)).firstMatch
    }

    private func openGeneral(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        openInbox(app, file: file, line: line).tap()
        XCTAssertTrue(text(app, "Rendez-vous à 14 h devant l'auto-école").waitForExistence(timeout: 8),
                      "Dernier message déchiffré du général", file: file, line: line)
    }

    private func backToInbox(_ app: XCUIApplication) {
        // iPhone : retour de pile. iPad : la liste reste visible à côté.
        let back = app.navigationBars.buttons["Messages"].firstMatch
        if back.exists && back.isHittable { back.tap() }
    }

    // MARK: Entrée et liste

    func testMessagesEntryOpensInbox() {
        let app = launch()
        openInbox(app)
        capture("01-entree-messages")
    }

    func testInboxShowsPreviewsDatesUnreadAndSingleGeneral() {
        let app = launch()
        let general = openInbox(app)
        XCTAssertEqual(app.buttons.matching(identifier: ID.general).count, 1, "Un seul général")
        let lea = app.buttons[ID.lea]
        let marc = app.buttons[ID.marc]
        XCTAssertTrue(lea.waitForExistence(timeout: 5))
        XCTAssertTrue(marc.exists)
        XCTAssertTrue(waitFor(lea, "label CONTAINS 'À demain pour la leçon'"), "Aperçu Léa : \(lea.label)")
        XCTAssertTrue(lea.label.contains("1 message non lu"), "Non-lus Léa : \(lea.label)")
        XCTAssertTrue(marc.label.contains("Je décale mon examen"), "Aperçu Marc : \(marc.label)")
        XCTAssertTrue(waitFor(general, "label CONTAINS '2 messages non lus'"), "Non-lus général : \(general.label)")
        XCTAssertTrue(general.label.contains("Rendez-vous à 14 h"), "Aperçu général : \(general.label)")
        // Date : le libellé accessible se termine par une date relative après l'aperçu.
        XCTAssertGreaterThan(lea.label.components(separatedBy: ", ").count, 3, "Date attendue : \(lea.label)")
        capture("02-liste-apercus-non-lus")
    }

    func testInboxSearchFiltersConversations() {
        let app = launch()
        openInbox(app)
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 2) { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Champ de recherche de conversation")
        field.tap()
        field.typeText("Marc")
        XCTAssertTrue(app.buttons[ID.marc].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[ID.lea].waitForNonExistence(timeout: 5), "Léa filtrée")
        capture("03-recherche-conversation")
    }

    // MARK: Fil

    func testConversationOpensAtNewestMessageNearComposer() {
        let app = launch()
        openGeneral(app)
        let newest = text(app, "Rendez-vous à 14 h devant l'auto-école")
        XCTAssertTrue(waitFor(newest, "hittable == true"), "Le plus récent est visible")
        let composer = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertLessThan(composer.frame.minY - newest.frame.maxY, 260, "Récent près du composeur")
        let oldest = text(app, "Bonjour à tous, nouvelle semaine")
        XCTAssertFalse(oldest.exists && oldest.isHittable, "Le plus ancien chargé n'est pas à l'écran")
        capture("04-ouverture-fil-en-bas")
    }

    func testLoadOlderMessages() {
        let app = launch()
        openGeneral(app)
        let older = app.buttons["Charger les messages précédents"]
        for _ in 0..<12 where !(older.exists && older.isHittable) { app.swipeDown() }
        XCTAssertTrue(older.isHittable, "Bouton de chargement des précédents")
        older.tap()
        XCTAssertTrue(text(app, "Premier message du général").waitForExistence(timeout: 8), "Page 2 chargée")
        capture("05-messages-precedents")
    }

    func testReactionFromLongPressClosesMenuAndUpdatesCapsule() {
        let app = launch()
        openGeneral(app)
        let target = text(app, "Leçon de conduite confirmée")
        XCTAssertTrue(waitFor(target, "hittable == true"))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pouce levé, 2, vous avez réagi'")).firstMatch.exists,
                      "Ma réaction existante est marquée")
        target.press(forDuration: 1.2)
        let heart = app.buttons.matching(NSPredicate(format: "label == 'Cœur' OR label == '❤️'")).firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 5), "Palette de réactions dans le menu")
        capture("06a-menu-reactions")
        heart.tap()
        XCTAssertTrue(app.buttons["Répondre"].waitForNonExistence(timeout: 3), "#102 : le menu se ferme après le choix")
        let capsule = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cœur, 1, vous avez réagi'")).firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: 5), "Capsule Cœur mise à jour")
        capture("06b-reaction-appliquee")
    }

    func testQuotedReplyShowsAndJumps() {
        let app = launch()
        openGeneral(app)
        let quote = app.buttons.matching(NSPredicate(format: "label == 'En réponse à : Pensez aux papiers du permis'")).firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 5), "Citation du message 20")
        capture("07-reponse-citee")
        quote.tap()
        XCTAssertTrue(waitFor(text(app, "Pensez aux papiers du permis"), "hittable == true"), "Saut vers le message cité")
    }

    func testPinnedBannerShowsPinnedMessage() {
        let app = launch()
        openGeneral(app)
        let pinned = app.buttons["messaging.pinned"]
        XCTAssertTrue(pinned.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(pinned, "label CONTAINS 'Pensez aux papiers du permis'"), "Épinglé : \(pinned.label)")
        pinned.tap()
        XCTAssertTrue(waitFor(text(app, "Pensez aux papiers du permis"), "hittable == true"))
        capture("08-epingle")
    }

    func testSearchInsideConversationFindsMessage() {
        let app = launch()
        openGeneral(app)
        app.buttons["messaging.search.open"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("papiers")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pensez aux papiers du permis'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Résultat de recherche dans le fil")
        capture("09-recherche-fil")
        result.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "La recherche se ferme sur le résultat")
    }

    func testPollIsDisplayed() {
        let app = launch()
        openGeneral(app)
        let poll = app.descendants(matching: .any)["messaging.poll"].firstMatch
        XCTAssertTrue(poll.waitForExistence(timeout: 5), "Sondage déchiffré")
        XCTAssertTrue(text(app, "Créneau du code ?").exists || app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Créneau du code ?'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Lundi, 1 vote"].exists)
        XCTAssertTrue(app.buttons["Mardi, 1 vote"].exists)
        capture("10-sondage")
    }

    func testMentionSuggestionsFilterInsertAndKeepKeyboard() {
        let app = launch()
        openGeneral(app)
        XCTAssertFalse(app.buttons["Mentionner"].exists, "#101 : plus de bouton Mentionner")
        let composer = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        composer.tap()
        composer.typeText("Salut @")
        let suggestions = app.descendants(matching: .any)["messaging.mention.suggestions"].firstMatch
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5), "Suggestions après @")
        XCTAssertTrue(app.buttons["Mentionner Léa Fixture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mentionner Marc Fixture"].exists)
        capture("11a-mention-suggestions")
        composer.typeText("L")
        XCTAssertTrue(app.buttons["Mentionner Marc Fixture"].waitForNonExistence(timeout: 3), "@L filtre")
        app.buttons["Mentionner Léa Fixture"].tap()
        XCTAssertTrue(waitFor(composer, "value == 'Salut @Léa Fixture '"), "Insertion : \(String(describing: composer.value))")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "#101 : le clavier reste ouvert")
        XCTAssertFalse(suggestions.exists, "Suggestions fermées après choix")
        capture("11b-mention-inseree")
    }

    func testUnreadCountDropsAfterReading() {
        let app = launch()
        let general = openInbox(app)
        XCTAssertTrue(waitFor(general, "label CONTAINS '2 messages non lus'"), "Avant lecture : \(general.label)")
        general.tap()
        XCTAssertTrue(text(app, "Rendez-vous à 14 h devant l'auto-école").waitForExistence(timeout: 8))
        capture("12a-fil-lu")
        backToInbox(app)
        let row = app.buttons[ID.general].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(row, "NOT (label CONTAINS 'non lu')", timeout: 8), "#103 : compteur après lecture : \(row.label)")
        capture("12b-non-lus-retombes")
    }

    // MARK: Apparence, accessibilité, lecture seule

    func testDarkModeCapture() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Apparence pilotable à partir d'iOS 17") }
        XCUIDevice.shared.appearance = .dark
        let app = launch()
        openInbox(app)
        capture("13a-sombre-liste")
        app.buttons[ID.general].firstMatch.tap()
        XCTAssertTrue(text(app, "Rendez-vous à 14 h devant l'auto-école").waitForExistence(timeout: 8))
        capture("13b-sombre-fil")
    }

    func testLargeTextCapture() {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openInbox(app)
        capture("14a-grand-texte-liste")
        app.buttons[ID.general].firstMatch.tap()
        let composer = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 8))
        XCTAssertTrue(composer.isHittable, "Composeur atteignable en grand texte")
        capture("14b-grand-texte-fil")
    }

    func testReadOnlyConversationShowsHistoryWithoutComposer() {
        let app = launch(["-messaging-ui-readonly"])
        openInbox(app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.readonly"].waitForExistence(timeout: 8))
        XCTAssertTrue(text(app, "Pensez aux papiers du permis").waitForExistence(timeout: 5), "Historique lisible jusqu'à la limite")
        XCTAssertFalse(text(app, "Rendez-vous à 14 h devant l'auto-école").exists, "Rien au-delà de la limite")
        XCTAssertFalse(app.descendants(matching: .any)["messaging.compose.text"].exists)
        XCTAssertFalse(app.buttons["messaging.compose.more"].exists)
        capture("15-lecture-seule")
    }

    // MARK: Diagnostic #confirmation membres

    /// Même confirmation que testAdminReinstatesRemovedMemberAfterConfirmation, ouverte par l'action de balayage
    /// plutôt que par le menu contextuel : sépare un défaut de présentation depuis le menu d'un défaut du dialogue.
    func testAdminRemoveConfirmationFromSwipeAction() {
        let app = launch()
        openInbox(app).tap()
        let options = app.buttons["messaging.options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["Membres"].tap()
        let list = app.descendants(matching: .any)["messaging.members"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let row = list.buttons["Léa Fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let remove = app.buttons["Retirer"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3), "Action de balayage Retirer")
        remove.tap()
        let confirm = app.buttons.matching(identifier: "messaging.members.confirmRemove").firstMatch
        let byLabel = app.buttons["Retirer Léa Fixture"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5) || byLabel.exists,
                      "Confirmation depuis le balayage (identifiant ou libellé)")
        capture("16-confirmation-balayage")
    }

    func testAdminRemoveConfirmationFromContextMenuByLabel() {
        let app = launch()
        openInbox(app).tap()
        app.buttons["messaging.options"].tap()
        app.buttons["Membres"].tap()
        let list = app.descendants(matching: .any)["messaging.members"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let row = list.buttons["Léa Fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1)
        let remove = app.buttons["Retirer du général"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        let byLabel = app.buttons["Retirer Léa Fixture"]
        let byID = app.buttons.matching(identifier: "messaging.members.confirmRemove").firstMatch
        let shown = byLabel.waitForExistence(timeout: 5)
        capture("17-confirmation-menu")
        XCTAssertTrue(shown || byID.exists, "Confirmation après le menu contextuel (libellé \(byLabel.exists), identifiant \(byID.exists))")
    }
}
