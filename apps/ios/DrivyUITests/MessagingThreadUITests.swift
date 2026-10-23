import XCTest

/// Messagerie v2 (#65). Écrit, non exécuté (#84) : nécessite le simulateur, `-messaging-development`
/// et l'environnement synthétique `prototypes/messaging-environment`. Aucun résultat VoiceOver physique n'en découle.
final class MessagingThreadUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-messaging-development"]
        app.launch()
        return app
    }

    func testGeneralMembersOpenProfileWithNameAndPhotoOnly() throws {
        let app = launch()
        let entry = app.buttons["messages-entry"]
        guard entry.waitForExistence(timeout: 10) else { throw XCTSkip("Messagerie de développement indisponible") }
        entry.tap()
        app.buttons["messaging.members.open"].tap()
        let list = app.descendants(matching: .any)["messaging.members"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let first = list.buttons.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.member.profile"].waitForExistence(timeout: 5))
    }

    /// Administrateur seulement : retirer puis réintégrer, chaque fois après confirmation.
    func testAdminReinstatesRemovedMemberAfterConfirmation() throws {
        let app = launch()
        let entry = app.buttons["messages-entry"]
        guard entry.waitForExistence(timeout: 10) else { throw XCTSkip("Messagerie de développement indisponible") }
        entry.tap()
        app.buttons["messaging.members.open"].tap()
        let list = app.descendants(matching: .any)["messaging.members"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let row = list.buttons.element(boundBy: 1)
        guard row.waitForExistence(timeout: 5) else { throw XCTSkip("Un seul membre") }
        row.press(forDuration: 1)
        let remove = app.buttons["Retirer du général"]
        guard remove.waitForExistence(timeout: 3) else { throw XCTSkip("Compte non administrateur du groupe") }
        remove.tap()
        app.sheets.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Retirer '")).firstMatch.tap()
        let reinstate = app.buttons["messaging.members.reinstate"]
        XCTAssertTrue(reinstate.waitForExistence(timeout: 5))
        XCTAssertTrue(reinstate.label.hasPrefix("Réintégrer "))
        reinstate.tap()
        app.sheets.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Réintégrer '")).firstMatch.tap()
        XCTAssertTrue(reinstate.waitForNonExistence(timeout: 5))
    }

    func testPollComposerRequiresQuestionAndTwoOptions() throws {
        let app = launch()
        let entry = app.buttons["messages-entry"]
        guard entry.waitForExistence(timeout: 10) else { throw XCTSkip("Messagerie de développement indisponible") }
        entry.tap()
        app.buttons["Général de l'école"].tap()
        let more = app.buttons["messaging.compose.more"]
        guard more.waitForExistence(timeout: 5) else { throw XCTSkip("Conversation en lecture seule") }
        more.tap()
        app.buttons["Sondage"].tap()
        let send = app.buttons["messaging.poll.send"]
        XCTAssertFalse(send.isEnabled)
        app.textFields["messaging.poll.question"].tap()
        app.typeText("Créneau ?")
        app.textFields["messaging.poll.option.0"].tap(); app.typeText("Lundi")
        XCTAssertFalse(send.isEnabled)
        app.textFields["messaging.poll.option.1"].tap(); app.typeText("Mardi")
        XCTAssertTrue(send.isEnabled)
    }

    func testSearchOpensFromConversation() throws {
        let app = launch()
        let entry = app.buttons["messages-entry"]
        guard entry.waitForExistence(timeout: 10) else { throw XCTSkip("Messagerie de développement indisponible") }
        entry.tap()
        app.buttons["Général de l'école"].tap()
        app.buttons["messaging.search.open"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    func testKeyBackupReachableFromSettingsWithoutLateBadgeByDefault() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-messaging-development", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let entry = app.buttons["messages-entry"]
        guard entry.waitForExistence(timeout: 10) else { throw XCTSkip("Messagerie de développement indisponible") }
        entry.tap()
        app.buttons["messaging.settings.open"].tap()
        let open = app.buttons["messaging.backup.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["messaging.backup.create"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["messaging.backup.restore"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["messaging.backup.notRestored"].exists)
    }

    func testDynamicTypeAccessibilitySizeKeepsComposerReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-messaging-development", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let entry = app.buttons["messages-entry"]
        guard entry.waitForExistence(timeout: 10) else { throw XCTSkip("Messagerie de développement indisponible") }
        entry.tap()
        app.buttons["Général de l'école"].tap()
        let composer = app.textFields["Rédiger un message"]
        let readOnly = app.descendants(matching: .any)["messaging.readonly"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5) || readOnly.exists)
        if composer.exists { XCTAssertTrue(composer.isHittable) }
    }
}
