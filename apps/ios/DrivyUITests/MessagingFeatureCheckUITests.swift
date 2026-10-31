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

    private var darkModeSet = false

    override func setUp() { continueAfterFailure = false }

    override func tearDown() {
        // `.unspecified` est refusé par le simulateur CI (« appearance value (0) is not valid »).
        if #available(iOS 17.0, *), darkModeSet { XCUIDevice.shared.appearance = .light }
        super.tearDown()
    }

    // MARK: Aides

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich"] + extra
        // Le runner refuse parfois l'assertion d'arrière-plan juste après un test précédent : une
        // seconde tentative suffit et évite un échec sans rapport avec l'écran testé.
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

    private func waitFor(_ element: XCUIElement, _ format: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: format)
        let needsLayout = format.contains("hittable")
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            // Une ligne de liste pas encore posée a pour cadre {inf, inf} : interroger sa « hittability » fait signaler à XCTest
            // « Failed to determine hittability » comme un échec du test (run 41202131542). Elle n'est interrogée qu'une fois placée.
            let frame = needsLayout && element.exists ? element.frame : .zero
            let placed = !needsLayout || (frame.minX.isFinite && frame.minY.isFinite && !frame.isEmpty)
            if placed && predicate.evaluate(with: element) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

    @discardableResult
    private func openInbox(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Entrée Messages", file: file, line: line)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5), "Liste Messages", file: file, line: line)
        let general = app.buttons[ID.general].firstMatch
        // La liste finit son premier chargement avant que la ligne ne devienne actionnable.
        if !waitFor(general, "exists == true AND hittable == true", timeout: 15) {
            app.swipeDown()
            XCTAssertTrue(waitFor(general, "exists == true AND hittable == true", timeout: 15),
                          "Ligne du général", file: file, line: line)
        }
        return general
    }

    /// Texte exact, ou bulle du fil (#182) : une bulle Exyte est un seul élément « auteur, texte, heure… ».
    private func text(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR (identifier == 'messaging.message' AND label CONTAINS %@)", value, value)).firstMatch
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
        // Simulateur iPad chargé : une lecture de la hiérarchie y prend jusqu'à 4 s.
        XCTAssertTrue(waitFor(newest, "hittable == true", timeout: 15), "Le plus récent est visible")
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
        let first = text(app, "Premier message du général")
        // Remonter le fil : Exyte charge la page suivante en atteignant le haut, le bouton reste un secours.
        for _ in 0..<20 where !(older.exists && older.isHittable) && !first.exists { app.swipeDown(velocity: .fast) }
        capture("05a-haut-du-fil")
        if older.exists && older.isHittable { older.tap() }
        // La liste ne garde que les cellules visibles : la page 2 apparaît une fois remontée à l'écran.
        for _ in 0..<8 where !first.waitForExistence(timeout: 1) { app.swipeDown() }
        XCTAssertTrue(first.waitForExistence(timeout: 8), "Page 2 chargée (bouton \(older.exists))")
        capture("05-messages-precedents")
    }

    func testReactionFromLongPressClosesMenuAndUpdatesCapsule() {
        let app = launch()
        openGeneral(app)
        let target = text(app, "Leçon de conduite confirmée")
        XCTAssertTrue(waitFor(target, "hittable == true"))
        capture("06-avant-reaction")
        XCTAssertTrue(waitFor(target, "label CONTAINS 'Pouce levé 2, vous avez réagi'"), "Ma réaction existante : \(target.label)")
        target.press(forDuration: 0.6)
        // Le menu natif (77c02b7b) expose chaque réaction sous « Réagir : <nom> », plus sous son seul nom.
        let heart = app.buttons.matching(NSPredicate(format: "label == 'Réagir : Cœur'")).firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 5), "Palette de réactions dans le menu")
        let reply = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Répondre'")).firstMatch
        XCTAssertTrue(reply.exists, "Actions du menu")
        capture("06a-menu-reactions")
        heart.tap()
        XCTAssertTrue(reply.waitForNonExistence(timeout: 3), "#102 : le menu se ferme après le choix")
        XCTAssertTrue(waitFor(text(app, "Leçon de conduite confirmée"), "label CONTAINS 'Cœur 1, vous avez réagi'"),
                      "Réaction Cœur appliquée sur la bulle")
        capture("06b-reaction-appliquee")
    }

    func testQuotedReplyShowsAndJumps() {
        let app = launch()
        openGeneral(app)
        let quote = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH 'En réponse à' AND label CONTAINS 'Pensez aux papiers du permis'")).firstMatch
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

    func testOpeningAPinKeepsItsPreviewAndNextIsAnExplicitAction() {
        let app = launch(["-messaging-ui-two-pins"])
        openGeneral(app)
        let pinned = app.buttons["messaging.pinned"]
        let next = app.buttons["messaging.pinned.next"]
        XCTAssertTrue(waitFor(pinned, "label CONTAINS 'Pensez aux papiers du permis'"))
        XCTAssertTrue(next.exists)
        let firstPreview = pinned.label
        pinned.tap()
        XCTAssertTrue(waitFor(text(app, "Pensez aux papiers du permis"), "hittable == true"))
        XCTAssertEqual(pinned.label, firstPreview, "Ouvrir le message ne doit pas afficher une autre épingle")
        next.tap()
        XCTAssertTrue(waitFor(pinned, "label CONTAINS 'Rendez-vous à 14 h'"))
        let secondPreview = pinned.label
        pinned.tap()
        XCTAssertTrue(waitFor(text(app, "Rendez-vous à 14 h devant l'auto-école"), "hittable == true"), app.debugDescription)
        XCTAssertEqual(pinned.label, secondPreview)
        next.tap()
        XCTAssertEqual(pinned.label, firstPreview, "Le parcours explicite boucle sans ouvrir de message")
    }

    func testSearchInsideConversationFindsMessage() {
        let app = launch()
        openGeneral(app)
        app.buttons["messaging.search.open"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("papiers")
        // L'épinglé du fil, resté derrière la feuille, porte le même texte : viser la ligne de résultat.
        let result = app.buttons.matching(NSPredicate(format: "identifier == 'messaging.search.result' AND label CONTAINS 'Pensez aux papiers du permis'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Résultat de recherche dans le fil")
        capture("09-recherche-fil")
        result.tap()
        // La liste des discussions garde son propre champ de recherche derrière la feuille :
        // vérifier le retour au fil sur le message, pas la disparition d'un champ.
        XCTAssertTrue(waitFor(text(app, "Pensez aux papiers du permis"), "hittable == true"),
                      "Retour au fil sur le message trouvé")
        XCTAssertTrue(app.descendants(matching: .any)["messaging.compose.text"].firstMatch.exists,
                      "La recherche se ferme sur le résultat")
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

    /// #73 : voter, changer de choix, puis clore. La fixture applique vraiment les votes et la clôture (extension DEBUG du
    /// simulateur) ; le fil est relu après chaque geste, donc un total qui tient prouve l'état renvoyé et pas seulement l'affichage provisoire.
    func testPollVoteThenCloseKeepsTotalsAndLocksTheChoices() {
        let app = launch()
        openGeneral(app)
        XCTAssertTrue(app.descendants(matching: .any)["messaging.poll"].firstMatch.waitForExistence(timeout: 8), "Sondage déchiffré")
        let pendingNote = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'messaging.poll.pending' OR label CONTAINS 'Vote en cours'")).firstMatch

        // Au départ : Léa a voté Lundi, Marc Mardi, moi aucun choix.
        let monday = app.buttons["Lundi, 1 vote"]
        XCTAssertTrue(reveal(monday, in: app), "Option Lundi actionnable")
        XCTAssertNotEqual(monday.value as? String, "Choisi", "Aucun choix de ma part au départ")
        capture("10a-sondage-avant-vote")

        // Vote : mon choix s'ajoute au total, puis le serveur le confirme sans le changer.
        monday.tap()
        let mondayVoted = app.buttons["Lundi, 2 votes"]
        XCTAssertTrue(mondayVoted.waitForExistence(timeout: 8), "Mon vote est compté : \(app.debugDescription)")
        XCTAssertTrue(waitFor(mondayVoted, "value == 'Choisi'", timeout: 8), "Lundi est marqué comme choisi")
        XCTAssertTrue(pendingNote.waitForNonExistence(timeout: 10), "Le vote n'est plus « en cours d'enregistrement »")
        XCTAssertTrue(app.buttons["Lundi, 2 votes"].exists, "Le total tient après la confirmation")
        XCTAssertTrue(app.buttons["Mardi, 1 vote"].exists, "Le vote de Marc n'a pas bougé")
        capture("10b-sondage-vote")

        // Changement : le sondage est à choix unique, le vote passe de Lundi à Mardi.
        let tuesday = app.buttons["Mardi, 1 vote"]
        XCTAssertTrue(reveal(tuesday, in: app), "Option Mardi actionnable")
        tuesday.tap()
        XCTAssertTrue(app.buttons["Mardi, 2 votes"].waitForExistence(timeout: 8), "Le vote passe sur Mardi")
        XCTAssertTrue(app.buttons["Lundi, 1 vote"].waitForExistence(timeout: 8), "Lundi retrouve le seul vote de Léa")
        XCTAssertTrue(pendingNote.waitForNonExistence(timeout: 10), "Le changement est confirmé")
        XCTAssertTrue(waitFor(app.buttons["Mardi, 2 votes"], "value == 'Choisi'", timeout: 8), "Mardi est le choix retenu")
        XCTAssertNotEqual(app.buttons["Lundi, 1 vote"].value as? String, "Choisi")

        // Clôture : confirmation explicite, puis plus de vote ni de bouton « Clore ».
        let close = app.buttons["Clore"].firstMatch
        XCTAssertTrue(reveal(close, in: app), "Le créateur du sondage peut le clore")
        close.tap()
        let confirm = app.buttons["Clore le sondage"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Confirmation avant la clôture")
        capture("10c-confirmation-cloture")
        confirm.tap()
        let closedNote = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Sondage clos'")).firstMatch
        XCTAssertTrue(closedNote.waitForExistence(timeout: 10), "Le sondage est annoncé clos")
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "Plus de bouton Clore")
        XCTAssertTrue(app.buttons["Mardi, 2 votes"].exists && app.buttons["Lundi, 1 vote"].exists, "Les totaux sont conservés")
        // Voter n'est plus possible. Ces lignes n'exposent pas l'état « désactivé » à l'accessibilité (isEnabled reste vrai sur le
        // simulateur, constat du run 41202131542) : le test vérifie donc le comportement, pas ce trait. Un appui sur l'autre choix
        // ne crée aucun vote en attente et ne déplace ni les totaux ni le choix retenu.
        app.buttons["Lundi, 1 vote"].tap()
        XCTAssertFalse(pendingNote.waitForExistence(timeout: 3), "Aucun vote n'est enregistré sur un sondage clos")
        XCTAssertTrue(app.buttons["Mardi, 2 votes"].exists && app.buttons["Lundi, 1 vote"].exists, "Les totaux ne bougent pas : \(app.debugDescription)")
        XCTAssertEqual(app.buttons["Mardi, 2 votes"].value as? String, "Choisi", "Le choix retenu ne change pas")
        XCTAssertNotEqual(app.buttons["Lundi, 1 vote"].value as? String, "Choisi", "Lundi n'est pas devenu le choix retenu")
        capture("10d-sondage-clos")
    }

    /// Amène un élément du fil à l'écran sans jamais glisser depuis le haut : à ce niveau une feuille se ferme (voir la mémoire des tests de Messages).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<4 {
            if waitFor(element, "exists == true AND hittable == true", timeout: 4) { return true }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)))
        }
        return element.exists && element.isHittable
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
        darkModeSet = true
        let app = launch()
        capture("13-sombre-avant-entree")
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
