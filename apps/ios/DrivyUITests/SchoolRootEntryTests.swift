import XCTest

/// Real SchoolRootView, IdentitySession.restore, scenePhase and AppCoverPresenter; only I/O is synthetic.
@MainActor final class SchoolRootEntryTests: XCTestCase {
    func testDraftBlocksPersonalWelcomeUntilForegroundConfirmsActiveStaff() {
        let app = launch("draft-to-staff")
        defer { app.terminate() }
        assertDraft(app)
        capture(app, name: "root-entry-draft-before-staff-activation")

        returnFromBackground(app)
        // Same person, membership, roles and epoch: school activation alone must offer the real STAFF welcome.
        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 25), app.debugDescription)
        XCTAssertTrue(start.isHittable)
        XCTAssertTrue(app.buttons["onboarding-later"].isHittable)
        XCTAssertFalse(app.buttons["school-open-portal"].exists)
        capture(app, name: "root-entry-foreground-staff-welcome")
    }

    func testForegroundRereadsRightsAndKeepsAdminOnlyInTheWebEntry() {
        let app = launch("draft-to-administration")
        defer { app.terminate() }
        assertDraft(app)
        capture(app, name: "root-entry-draft-before-role-change")

        returnFromBackground(app)
        let portal = app.buttons["school-open-portal"]
        let updated = NSPredicate(format: "exists == true AND label == %@", "Ouvrir le portail web")
        expectation(for: updated, evaluatedWith: portal)
        waitForExpectations(timeout: 25)
        XCTAssertTrue(portal.isHittable)
        XCTAssertTrue(app.staticTexts["Gestion de votre école"].exists)
        XCTAssertFalse(app.buttons["onboarding-start"].waitForExistence(timeout: 2))
        assertNoFieldActions(app)
        capture(app, name: "root-entry-foreground-administration-only")
    }

    private func assertDraft(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let portal = app.buttons["school-open-portal"]
        XCTAssertTrue(portal.waitForExistence(timeout: 25), app.debugDescription, file: file, line: line)
        XCTAssertEqual(portal.label, "Continuer la préparation sur le web", file: file, line: line)
        XCTAssertTrue(portal.isHittable, file: file, line: line)
        XCTAssertFalse(app.buttons["onboarding-start"].waitForExistence(timeout: 2), file: file, line: line)
        assertNoFieldActions(app, file: file, line: line)
    }

    private func assertNoFieldActions(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for title in ["Aujourd’hui", "Agenda", "Élèves"] {
            XCTAssertFalse(app.buttons.matching(identifier: title).firstMatch.exists, file: file, line: line)
        }
    }

    private func returnFromBackground(_ app: XCUIApplication) {
        // No refresh button and no test-only lifecycle callback: exercise the real OS scene transition.
        XCUIDevice.shared.press(.home)
        let background = NSPredicate(format: "state == %d OR state == %d",
            XCUIApplication.State.runningBackground.rawValue, XCUIApplication.State.runningBackgroundSuspended.rawValue)
        expectation(for: background, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DRIVY_ROOT_ENTRY_SCENARIO"] = scenario
        app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH"]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
