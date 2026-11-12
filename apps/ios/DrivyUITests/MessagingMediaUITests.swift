import XCTest

/// Vraies vues, octets et runtime synthétiques en mémoire. Aucune preuve E2EE/serveur.
/// À exécuter sur iPhone et iPad ; NON EXÉCUTÉ sur le poste Windows de rédaction. Les captures sont des pièces jointes
/// du résultat (`capture`), nommées `media-<état>-<clair|sombre>` ; aucune donnée hors fixture.
@MainActor
final class MessagingMediaUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich", "-messaging-ui-media",
                               "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"] + extra
        app.launch()
        // En mode sombre et AccessibilityXXXL le runner met 10 à 20 s à se stabiliser entre deux écrans (journal du run
        // 43278793085 : « Wait for … to idle » de 7 à 12 s) ; on attend donc davantage, et on fait défiler la liste
        // des conversations au cas où l'entrée serait hors écran (les lignes hors écran n'existent pas dans la hiérarchie).
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()
        let general = app.buttons["messaging.general.open"]
        if !general.waitForExistence(timeout: 30) {
            for _ in 0..<5 where !general.exists {
                app.swipeUp()
                _ = general.waitForExistence(timeout: 3)
            }
        }
        XCTAssertTrue(general.exists, "Entrée « Général » introuvable après attente et défilement")
        general.tap()
        XCTAssertTrue(app.buttons["messaging.compose.more"].waitForExistence(timeout: 10))
        return app
    }

    private func select(_ kind: String, in app: XCUIApplication) {
        app.buttons["messaging.compose.more"].tap()
        let sample = app.buttons["messaging.media.fixture.\(kind)"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        XCTAssertTrue(app.buttons["messaging.media.selection.open"].waitForExistence(timeout: 10))
    }

    func testPhotoSelectionCanBePreviewedAndRemovedBeforeSend() {
        let app = launch()
        select("photo", in: app)
        app.buttons["messaging.media.selection.open"].tap()
        XCTAssertTrue(app.buttons["Fermer"].waitForExistence(timeout: 5))
        capture("media-photo-preview")
        app.buttons["Fermer"].tap()
        app.buttons["messaging.media.selection.remove"].tap()
        XCTAssertTrue(app.buttons["messaging.media.selection.open"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Envoyé"].exists)
    }

    func testPDFPreviewInDarkModeAndLargestText() {
        XCUIDevice.shared.appearance = .dark
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        select("pdf", in: app)
        XCTAssertTrue(app.buttons["messaging.media.selection.remove"].isHittable)
        capture("media-pdf-selection-dark-large")
        app.buttons["messaging.media.selection.open"].tap()
        XCTAssertTrue(app.buttons["Fermer"].waitForExistence(timeout: 5))
        capture("media-pdf-preview-dark-large")
        app.buttons["Fermer"].tap()
    }

    func testEmptyCaptionCanSendAndUnknownResultOffersExplicitRetry() {
        let app = launch(extra: ["-messaging-ui-media-unknown-once"])
        select("photo", in: app)
        let send = app.buttons["messaging.media.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let retry = app.buttons["messaging.media.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        capture("media-result-unknown")
        retry.tap()
        XCTAssertTrue(app.staticTexts["Envoyé"].waitForExistence(timeout: 10))
        capture("media-confirmed")
    }

    func testCaptionKeyboardAndPreparationWait() {
        let app = launch(extra: ["-messaging-ui-media-slow"])
        app.buttons["messaging.compose.more"].tap()
        app.buttons["messaging.media.fixture.pdf"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.media.preparing"].firstMatch.waitForExistence(timeout: 5))
        capture("media-preparing")
        XCTAssertTrue(app.buttons["messaging.media.selection.open"].waitForExistence(timeout: 10))
        let caption = app.descendants(matching: .any)["messaging.media.caption"].firstMatch
        XCTAssertTrue(caption.exists)
        caption.tap()
        caption.typeText("Document pour la leçon")
        XCTAssertTrue(app.buttons["messaging.media.send"].isHittable)
        capture("media-caption-keyboard")
    }

    /// #475 : le champ reste visible pendant la sélection, sert de légende et revient intact au retrait.
    func testCaptionIsTheDraftAndSurvivesRemoval() {
        let app = launch()
        let main = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 10))
        main.tap()
        main.typeText("Bonjour")
        select("photo", in: app)
        let caption = app.descendants(matching: .any)["messaging.media.caption"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        XCTAssertEqual(caption.value as? String, "Bonjour")
        capture("media-caption-from-draft")
        app.buttons["messaging.media.selection.remove"].tap()
        XCTAssertTrue(app.buttons["messaging.media.selection.open"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(main.value as? String, "Bonjour")
    }

    func testReceivedPieceOpensInExistingThread() {
        let app = launch()
        let received = app.buttons["messaging.media.received.open"].firstMatch
        XCTAssertTrue(received.waitForExistence(timeout: 10))
        received.tap()
        XCTAssertTrue(app.buttons["Fermer"].waitForExistence(timeout: 5))
        capture("media-received-preview")
        app.buttons["Fermer"].tap()
        XCTAssertTrue(app.buttons["messaging.compose.more"].exists)
    }

    // MARK: Parcours de bout en bout (#478)

    /// Bouton d'ouverture d'une pièce reçue par son début de libellé (« Photo, » ou « Document PDF ») : les deux
    /// partagent l'identifiant `messaging.media.received.open`.
    private func received(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@",
                                         "messaging.media.received.open", prefix)).firstMatch
    }

    /// Ramène un élément à l'écran sans supposer le sens du défilement de la liste (retournée par Exyte).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // `isHittable` signale un échec (et non `false`) quand le cadre est invalide (hors écran, taille nulle, rotation en
        // cours : run 43287772177, paysage iPhone). On juge donc sur le cadre : non vide, centre dans la fenêtre.
        _ = element.waitForExistence(timeout: 15)
        if isReachable(element, in: app) { return }
        for _ in 0..<3 where !isReachable(element, in: app) { app.swipeDown() }
        for _ in 0..<6 where !isReachable(element, in: app) { app.swipeUp() }
        XCTAssertTrue(isReachable(element, in: app), "Pièce introuvable à l'écran après défilement")
    }

    private func isReachable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame, window = app.windows.firstMatch.frame
        guard !frame.isEmpty, !window.isEmpty else { return false }
        return window.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Attend la fin de la rotation : la fenêtre est plus large que haute en paysage.
    private func waitForLandscape(_ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let frame = app.windows.firstMatch.frame
            if frame.width > frame.height { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("La rotation en paysage ne s'est pas terminée")
    }

    private func closeButton(_ app: XCUIApplication) -> XCUIElement { app.buttons["messaging.media.close"] }

    /// Photo reçue : miniature visible dans le fil, plein écran, fermeture au même endroit ; PDF reçu : idem, plusieurs pages.
    private func runThreadJourney(appearance: XCUIDevice.Appearance, label: String) {
        XCUIDevice.shared.appearance = appearance
        let app = launch()
        let photo = received("Photo, ", in: app), pdf = received("Document PDF", in: app)
        reveal(pdf, in: app)
        reveal(photo, in: app)
        XCTAssertTrue(photo.exists && pdf.exists, "Photo et PDF reçus absents du fil")
        // La miniature a remplacé l'attente : ni « Chargement » ni « Aperçu indisponible ».
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, (photo.value as? String) == "Chargement" { Thread.sleep(forTimeInterval: 0.5) }
        XCTAssertNotEqual(photo.value as? String, "Chargement")
        XCTAssertNotEqual(photo.value as? String, "Aperçu indisponible")
        XCTAssertGreaterThanOrEqual(photo.frame.height, 44)
        XCTAssertGreaterThanOrEqual(pdf.frame.height, 44)
        capture("media-thread-photo-pdf-\(label)")

        photo.tap()
        let close = closeButton(app)
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["messaging.media.preview"].firstMatch.exists)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        capture("media-viewer-photo-\(label)")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
        XCTAssertTrue(photo.exists, "Le fil a perdu la photo à la fermeture")
        XCTAssertTrue(app.buttons["messaging.compose.more"].exists)

        reveal(pdf, in: app)
        pdf.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["messaging.media.page"].firstMatch.waitForExistence(timeout: 15),
                      "Indicateur de pages absent : le PDF de la fixture a deux pages")
        capture("media-viewer-pdf-\(label)")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
        XCTAssertTrue(pdf.exists)
    }

    func testReceivedPhotoAndPDFOpenFullScreenAndCloseLight() { runThreadJourney(appearance: .light, label: "clair") }

    func testReceivedPhotoAndPDFOpenFullScreenAndCloseDark() { runThreadJourney(appearance: .dark, label: "sombre") }

    /// Légende dans le champ principal → envoi → bulle en attente → échec confirmé avec reprise ciblée → confirmée.
    /// `slow` rend l'attente observable ; `fail-once` refuse le premier envoi (échec, pas résultat inconnu).
    private func runSendJourney(appearance: XCUIDevice.Appearance, label: String) {
        XCUIDevice.shared.appearance = appearance
        let app = launch(extra: ["-messaging-ui-media-slow", "-messaging-ui-media-fail-once"])
        app.buttons["messaging.compose.more"].tap()
        let sample = app.buttons["messaging.media.fixture.pdf"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        XCTAssertTrue(app.buttons["messaging.media.selection.open"].waitForExistence(timeout: 20))
        let caption = app.descendants(matching: .any)["messaging.media.caption"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        caption.tap()
        caption.typeText("Consignes de la leçon")
        XCTAssertEqual(caption.value as? String, "Consignes de la leçon")
        capture("media-composer-attachment-caption-\(label)")

        let send = app.buttons["messaging.media.send"]
        XCTAssertTrue(send.isHittable)
        send.tap()
        let pending = app.descendants(matching: .any)["messaging.media.pending"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 10), "Bulle en attente absente du fil")
        capture("media-pending-sending-\(label)")

        let retry = app.buttons["messaging.media.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 20), "Reprise ciblée absente après l'échec")
        XCTAssertEqual(retry.label, "Réessayer")
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertFalse(app.staticTexts["Envoyé"].exists, "Succès annoncé avant l'accusé")
        capture("media-failed-retry-\(label)")

        retry.tap()
        XCTAssertTrue(app.staticTexts["Envoyé"].waitForExistence(timeout: 20))
        XCTAssertTrue(retry.waitForNonExistence(timeout: 10), "Reprise encore proposée après la confirmation")
        capture("media-confirmed-\(label)")
    }

    func testCaptionSendPendingFailureRetryConfirmedLight() { runSendJourney(appearance: .light, label: "clair") }

    func testCaptionSendPendingFailureRetryConfirmedDark() { runSendJourney(appearance: .dark, label: "sombre") }

    /// Retrait de la pièce : la légende saisie reste dans le champ (aucune perte de texte), cibles d'au moins 44 pt.
    func testRemovingTheAttachmentKeepsTheCaptionAndTapTargets() {
        let app = launch()
        select("photo", in: app)
        let caption = app.descendants(matching: .any)["messaging.media.caption"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        caption.tap()
        caption.typeText("Légende à garder")
        let open = app.buttons["messaging.media.selection.open"], remove = app.buttons["messaging.media.selection.remove"]
        XCTAssertGreaterThanOrEqual(open.frame.height, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.width, 44)
        remove.tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 5))
        let main = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        XCTAssertTrue(main.waitForExistence(timeout: 5))
        XCTAssertEqual(main.value as? String, "Légende à garder")
    }

    /// Paysage (iPhone) ou fenêtre pivotée (iPad) : la visionneuse reste dans l'écran et se ferme.
    func testViewerStaysUsableInLandscape() {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForLandscape(app)
        let photo = received("Photo, ", in: app)
        reveal(photo, in: app)
        XCTAssertTrue(photo.exists)
        photo.tap()
        let close = closeButton(app)
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(close.frame), "Fermer sort de l'écran en paysage")
        capture("media-viewer-photo-landscape")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
