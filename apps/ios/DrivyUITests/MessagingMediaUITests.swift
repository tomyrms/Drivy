import XCTest

/// Vraies vues, octets et runtime synthétiques en mémoire. Aucune preuve E2EE/serveur.
/// À exécuter sur iPhone et iPad ; NON EXÉCUTÉ sur le poste Windows de rédaction.
@MainActor
final class MessagingMediaUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    override func tearDown() {
        XCUIDevice.shared.appearance = .light
        super.tearDown()
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-rich", "-messaging-ui-media",
                               "-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"] + extra
        app.launch()
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let general = app.buttons["messaging.general.open"]
        XCTAssertTrue(general.waitForExistence(timeout: 10))
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
