import XCTest

/// Vérifie la présentation native avec la langue déclarée par le bundle.
/// Le nom accessible du collage est explicite : seule l'image prouve son libellé visible.
@MainActor final class SystemLanguageTests: XCTestCase {
    func testInvitationPasteUsesTheBundlesLanguageWithoutLaunchOverrides() {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = "join-link"
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.textFields["join-invitation-link"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Coller le lien"].waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "system-language-join-link-no-language-overrides"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
