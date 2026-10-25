import XCTest

/// Parcours UI synthétiques locaux (#78/#84), sans réseau, session réelle ni chiffrement simulé.
/// Exécutables sur iPhone et iPad. Aucun résultat VoiceOver physique n'en découle.
@MainActor
final class MessagingThreadUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-messaging-ui-fixture"]
        app.launch()
        return app
    }

    func testGeneralMembersOpenProfileWithNameAndPhotoOnly() throws {
        let app = launch()
        let list = openGeneralMembers(in: app)
        let first = list.buttons["Léa Fixture"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let profile = app.descendants(matching: .any)["messaging.member.profile"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(profile.label.contains("Léa Fixture"))
        XCTAssertFalse(app.buttons["learner-send-message"].exists)
        XCTAssertFalse(app.buttons["Appeler"].exists)
        XCTAssertFalse(app.buttons["Envoyer un e-mail"].exists)
    }

    /// Administrateur seulement : retirer puis réintégrer, chaque fois après confirmation.
    func testAdminReinstatesRemovedMemberAfterConfirmation() throws {
        let app = launch()
        let list = openGeneralMembers(in: app)
        let row = list.buttons["Léa Fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "La fixture contient deux membres")
        row.press(forDuration: 1)
        let remove = app.buttons["Retirer du général"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3), "La fixture est administratrice du groupe")
        remove.tap()
        let confirmRemove = try confirmationButton(in: app, identifier: "messaging.members.confirmRemove")
        XCTAssertEqual(confirmRemove.label, "Retirer Léa Fixture")
        confirmRemove.tap()
        let reinstate = app.buttons["messaging.members.reinstate"]
        XCTAssertTrue(reinstate.waitForExistence(timeout: 5))
        XCTAssertTrue(reinstate.label.hasPrefix("Réintégrer "))
        reinstate.tap()
        let confirmReinstate = try confirmationButton(in: app, identifier: "messaging.members.confirmReinstate")
        XCTAssertEqual(confirmReinstate.label, "Réintégrer Léa Fixture")
        confirmReinstate.tap()
        XCTAssertTrue(reinstate.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Le membre réintégré retrouve sa ligne active")
    }

    private func openGeneralMembers(in app: XCUIApplication,
                                    file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "La fixture Messages doit être composée",
                      file: file, line: line)
        entry.tap()
        // Le run 40198021398 reste dans Messages après le tap Membres sur iPhone.
        // Synchroniser la feuille et le chargement initial avant l'unique action de navigation.
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5),
                      "La feuille Messages doit être présentée", file: file, line: line)
        XCTAssertTrue(app.staticTexts["Aucune conversation"].waitForExistence(timeout: 5),
                      "La fixture doit avoir terminé le chargement des discussions", file: file, line: line)
        let open = app.buttons["messaging.members.open"]
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                       "L'entrée Membres doit être actionnable", file: file, line: line)
        open.tap()
        let list = app.descendants(matching: .any)["messaging.members"]
        XCTAssertTrue(list.waitForExistence(timeout: 5),
                      "L'unique appui doit ouvrir les membres du général", file: file, line: line)
        return list
    }

    private func confirmationButton(in app: XCUIApplication, identifier: String,
                                    file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        let matches = app.buttons.matching(identifier: identifier)
        let appeared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in matches.count > 0 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 5), .completed,
                       "La confirmation doit apparaître", file: file, line: line)
        // Le run 40194237882 expose Button > Button avec le même identifiant sur iPhone/iPad.
        // Garder le bouton terminal, pas son conteneur. Deux actions distinctes restent un échec.
        let actions = matches.allElementsBoundByIndex.filter {
            $0.descendants(matching: .button).matching(identifier: identifier).count == 0
        }
        let action = try XCTUnwrap(actions.count == 1 ? actions[0] : nil,
                                  "Une seule action terminale attendue pour \(identifier), trouvé : \(actions.count)",
                                  file: file, line: line)
        XCTAssertTrue(action.isHittable, "La confirmation doit être actionnable", file: file, line: line)
        return action
    }

    func testPollComposerRequiresQuestionAndTwoOptions() throws {
        let app = launch()
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "La fixture Messages doit être composée")
        entry.tap()
        app.buttons["Général de l'école"].tap()
        let more = app.buttons["messaging.compose.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "La fixture autorise la composition")
        more.tap()
        app.buttons["Sondage"].tap()
        let send = app.buttons["messaging.poll.send"]
        XCTAssertFalse(send.isEnabled)
        app.descendants(matching: .any)["messaging.poll.question"].firstMatch.tap()
        app.typeText("Créneau ?")
        app.textFields["messaging.poll.option.0"].tap(); app.typeText("Lundi")
        XCTAssertFalse(send.isEnabled)
        app.textFields["messaging.poll.option.1"].tap(); app.typeText("Mardi")
        XCTAssertTrue(send.isEnabled)
    }

    func testSearchOpensFromConversation() throws {
        let app = launch()
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "La fixture Messages doit être composée")
        entry.tap()
        app.buttons["Général de l'école"].tap()
        app.buttons["messaging.search.open"].tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
    }

    func testKeyBackupReachableFromSettingsWithoutLateBadgeByDefault() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-messaging-ui-fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "La fixture Messages doit être composée")
        entry.tap()
        app.buttons["messaging.settings.open"].tap()
        let open = app.buttons["messaging.backup.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.buttons["messaging.backup.create"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["messaging.backup.restore"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["messaging.backup.notRestored"].exists)
    }

    func testReadOnlyConversationHasNoComposerOrSendAction() {
        let app = XCUIApplication()
        app.launchArguments = ["-messaging-ui-fixture", "-messaging-ui-readonly"]
        app.launch()
        XCTAssertTrue(app.buttons["messages-entry"].waitForExistence(timeout: 10))
        app.buttons["messages-entry"].tap()
        XCTAssertTrue(app.buttons["Général de l'école"].waitForExistence(timeout: 5))
        app.buttons["Général de l'école"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["messaging.readonly"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["messaging.compose.text"].exists)
        XCTAssertFalse(app.buttons["Envoyer"].exists)
        XCTAssertFalse(app.buttons["messaging.compose.more"].exists)
    }

    func testUnavailableProtectionPreservesDraftWithoutFalseReceipt() {
        let app = launch()
        XCTAssertTrue(app.buttons["messages-entry"].waitForExistence(timeout: 10))
        app.buttons["messages-entry"].tap()
        XCTAssertTrue(app.buttons["Général de l'école"].waitForExistence(timeout: 5))
        app.buttons["Général de l'école"].tap()
        let composer = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("Message de qualification")
        let send = app.buttons["Envoyer"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: send)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        send.tap()
        let failure = app.staticTexts["messaging.delivery"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(failure.label.contains("Aucun envoi en clair"))
        XCTAssertEqual(composer.value as? String, "Message de qualification")
        XCTAssertFalse(app.staticTexts["En attente d'envoi"].exists)
    }

    func testDynamicTypeAccessibilitySizeKeepsComposerReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-messaging-ui-fixture", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let entry = app.buttons["messages-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "La fixture Messages doit être composée")
        entry.tap()
        app.buttons["Général de l'école"].tap()
        let composer = app.descendants(matching: .any)["messaging.compose.text"].firstMatch
        let readOnly = app.descendants(matching: .any)["messaging.readonly"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(readOnly.exists)
        XCTAssertTrue(composer.isHittable)
    }
}
