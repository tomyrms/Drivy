import XCTest

/// Campagne opt-in : les captures conservent l’orientation réelle du simulateur.
@MainActor final class VisualOrientationTests: XCTestCase {
    // Keep aligned with capture-screens.sh; test_visual_capture.py checks both.
    // Unknown legacy names must not silently capture the default dossier.
    private let supportedScreens: Set<String> = [
        "dossier", "progression", "home-tabs", "school-choice", "no-school",
        "profile-tab", "learner-home", "learner-progress", "start-now", "planning-settings",
        "agenda", "learners", "learner", "lesson", "lesson-planned",
        "lesson-observations", "lesson-evidence", "lesson-permit", "invitation-code", "trips",
        "replay", "design-system", "skeletons", "gps-choice", "signal", "live-signal",
        "signal-status", "observations", "capture-preparation", "live", "live-waiting",
        "planning", "planning-details", "planning-confirmation", "invitations", "invitation-create",
        "invitation-detail", "lesson-finish", "lesson-modal", "lesson-tariff", "sign-in",
        "sign-in-error", "sign-in-loading", "sign-in-unconfigured", "account", "app-lock",
        "join-code", "join-code-preview", "join-code-error", "join-code-pending", "join-code-confirmed",
        "join-link", "join-link-preview", "profile", "profile-error", "onboarding-welcome",
        "onboarding-information", "onboarding-formation", "onboarding-gps", "onboarding-review", "onboarding-ready",
        "onboarding-staff",
    ]

    func testRequestedScreensAtRealOrientations() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DRIVY_VISUAL_ORIENTATION_TEST"] == "1" else {
            throw XCTSkip("Les captures orientées sont exécutées seulement par la campagne visuelle dédiée.")
        }
        continueAfterFailure = false
        let screens = (environment["DRIVY_VISUAL_SCREENS"] ?? "").split(separator: " ").map(String.init)
        let orientations = (environment["DRIVY_VISUAL_ORIENTATIONS"] ?? "").split(separator: " ").map(String.init)
        let device = try XCTUnwrap(environment["DRIVY_VISUAL_DEVICE"])
        let appearance = try XCTUnwrap(environment["DRIVY_VISUAL_APPEARANCE"])
        XCTAssertFalse(screens.isEmpty)
        XCTAssertFalse(orientations.isEmpty)
        let unknownScreens = screens.filter { !supportedScreens.contains($0) }
        guard unknownScreens.isEmpty else {
            XCTFail("Écrans non pris en charge par cette version : \(unknownScreens.joined(separator: ", ")). Vérifiez la version du code et la sélection de captures.")
            return
        }
        XCTAssertTrue(["iPhone", "iPad"].contains(device))
        XCTAssertTrue(["light", "dark"].contains(appearance))
        defer { XCUIDevice.shared.orientation = .portrait }

        for orientation in orientations {
            XCTAssertTrue(["portrait", "landscape"].contains(orientation))
            let landscape = orientation == "landscape"
            for screen in screens {
                XCTContext.runActivity(named: "\(device) · \(screen) · \(appearance) · \(orientation)") { _ in
                    let app = XCUIApplication()
                    let captureName = "\(device)-\(screen)-\(appearance)-\(orientation)-synthetic"
                    defer { app.terminate() }
                    print("DRIVY_VISUAL_BEGIN \(captureName)")
                    let interactiveSignal = ["live-signal", "signal-status"].contains(screen)
                    let lessonEvidence = screen == "lesson-evidence"
                    let planningDetails = ["planning-details", "planning-confirmation"].contains(screen)
                    app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = interactiveSignal ? "live" : (lessonEvidence ? "lesson-observations" : (planningDetails ? "planning" : screen))
                    app.launchEnvironment["DRIVY_VISUAL_LARGE_TEXT"] = environment["DRIVY_VISUAL_LARGE_TEXT"] ?? "0"
                    app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH",
                                           "-AppleInterfaceStyle", appearance == "dark" ? "Dark" : "Light"]
                    XCUIDevice.shared.orientation = .portrait
                    app.launch()
                    guard requireVisual(app.wait(for: .runningForeground, timeout: 20),
                        "L’application n’est pas au premier plan.", app: app, name: captureName) else { return }
                    guard requireVisual(app.windows.firstMatch.waitForExistence(timeout: 10),
                        "La fenêtre de l’application est absente.", app: app, name: captureName) else { return }
                    XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                    let deadline = Date().addingTimeInterval(10)
                    while !matchesOrientation(app.frame.size, landscape: landscape), Date() < deadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    }
                    guard requireVisual(matchesOrientation(app.frame.size, landscape: landscape),
                        "La fenêtre n’a pas pris l’orientation demandée.", app: app, name: captureName) else { return }
                    // Même délai de stabilisation des fixtures/MapKit que la voie simctl.
                    RunLoop.current.run(until: Date().addingTimeInterval(10))
                    let readyIdentifier: String? = switch screen {
                    case "learner", "dossier": "training-lessons-menu"
                    case "account": "account-heading"
                    case "profile-tab": "profile-open-trips"
                    case "onboarding-staff": "onboarding-start"
                    case "home-tabs": "today-day-list"
                    case "live", "live-waiting": "capture-signal-observation"
                    case "replay": "replay-play"
                    case "signal": "live-observation-theme-Priorité à droite"
                    case "sign-in": "school-sign-in"
                    default: nil
                    }
                    if let readyIdentifier {
                        guard requireVisual(app.descendants(matching: .any)[readyIdentifier].waitForExistence(timeout: 30),
                            "Élément de l’écran absent : \(readyIdentifier).", app: app, name: captureName) else { return }
                    }
                    if screen == "progression" {
                        guard requireVisual(app.descendants(matching: .any).matching(NSPredicate(
                            format: "label CONTAINS %@", "Avec accompagnement")).firstMatch.waitForExistence(timeout: 30),
                            "La progression n’est pas chargée.", app: app, name: captureName) else { return }
                    }
                    if interactiveSignal {
                        let signal = app.buttons["capture-signal-observation"]
                        guard requireVisual(signal.waitForExistence(timeout: 10),
                            "Bouton de signalement absent.", app: app, name: captureName) else { return }
                        signal.tap()
                        let priority = app.buttons["live-observation-theme-Priorité à droite"]
                        guard requireVisual(priority.waitForExistence(timeout: 10),
                            "Thème de signalement absent.", app: app, name: captureName) else { return }
                        if screen == "signal-status" {
                            priority.tap()
                            let attention = app.buttons["live-observation-status-ATTENTION"]
                            guard requireVisual(attention.waitForExistence(timeout: 10),
                                "Statut du signalement absent.", app: app, name: captureName) else { return }
                            guard requireVisual(attention.isEnabled && priority.exists && priority.isSelected,
                                "La palette de signalement n’a pas conservé le thème sélectionné.", app: app, name: captureName) else { return }
                        }
                        RunLoop.current.run(until: Date().addingTimeInterval(1))
                    }
                    if lessonEvidence {
                        let observation = app.descendants(matching: .any).matching(NSPredicate(
                            format: "label CONTAINS %@", "Priorité à droite · regard tardif")).firstMatch
                        let contextForm = app.collectionViews.firstMatch
                        guard requireVisual(contextForm.waitForExistence(timeout: 5),
                            "Formulaire des observations absent.", app: app, name: captureName) else { return }
                        for _ in 0..<10 {
                            if observation.exists && observation.isHittable { break }
                            // Stay inside the scrolling form, above the sticky action bar in landscape.
                            let start = contextForm.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85))
                            let end = contextForm.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2))
                            start.press(forDuration: 0.05, thenDragTo: end)
                        }
                        guard requireVisual(observation.exists && observation.isHittable,
                            "Observation attendue absente ou inaccessible.", app: app, name: captureName) else { return }
                    }
                    if screen == "lesson-permit" {
                        let confirm = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
                            "lesson-confirm-completion", "Terminer")).firstMatch
                        guard requireVisual(confirm.waitForExistence(timeout: 10),
                            "Confirmation de fin de leçon absente.", app: app, name: captureName) else { return }
                        confirm.tap()
                        let reason = app.descendants(matching: .any)["lesson-permit-reason"]
                        guard requireVisual(reason.waitForExistence(timeout: 10),
                            "Motif du permis absent.", app: app, name: captureName) else { return }
                        let finish = app.buttons["lesson-complete-permit"]
                        guard requireVisual(finish.waitForExistence(timeout: 5),
                            "Bouton de validation du permis absent.", app: app, name: captureName) else { return }
                        guard requireVisual(!finish.isEnabled,
                            "La validation du permis devrait être désactivée.", app: app, name: captureName) else { return }
                        guard requireVisual(app.navigationBars["Permis d’élève"].exists,
                            "Le détail du permis n’est pas ouvert.", app: app, name: captureName) else { return }
                    }
                    if planningDetails {
                        let target = screen == "planning-confirmation" ? app.buttons["planning-confirm"] : app.buttons["Conditions tarifaires"]
                        let form = app.collectionViews.firstMatch
                        guard requireVisual(form.waitForExistence(timeout: 10),
                            "Formulaire de planification absent.", app: app, name: captureName) else { return }
                        for _ in 0..<10 {
                            if target.exists && target.isHittable { break }
                            form.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85))
                                .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2)))
                        }
                        guard requireVisual(target.exists && target.isHittable,
                            "Action de planification absente ou inaccessible.", app: app, name: captureName) else { return }
                        if screen == "planning-details" {
                            guard requireVisual(!app.switches["Prix et conditions acceptés"].exists,
                                "La planification demande encore une acceptation supplémentaire.", app: app, name: captureName) else { return }
                            guard requireVisual(app.buttons["planning-confirm"].isEnabled,
                                "Planifier devrait être disponible avec ce tarif valable.", app: app, name: captureName) else { return }
                        }
                    }
                    guard requireVisual(XCUIDevice.shared.orientation.isLandscape == landscape,
                        "Le simulateur a changé d’orientation.", app: app, name: captureName) else { return }
                    let screenshot = XCUIScreen.main.screenshot()
                    guard requireVisual(matchesOrientation(screenshot.image.size, landscape: landscape),
                        "La capture système n’a pas les dimensions de l’orientation demandée.", app: app, name: captureName) else { return }
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = captureName
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    print("DRIVY_VISUAL_PASS \(captureName)")
                }
            }
        }
    }

    /// Capture the failure BEFORE XCTFail: continueAfterFailure is false.
    /// Only this opt-in, synthetic-fixture campaign calls this helper.
    private func requireVisual(_ condition: @autoclosure () -> Bool, _ message: String,
                               app: XCUIApplication, name: String,
                               file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard !condition() else { return true }
        print("DRIVY_VISUAL_FAILURE \(name): \(message)")
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        // Never let the exporter count a failure image as a successful capture.
        screenshot.name = "FAILED-\(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let details = XCTAttachment(string: "Capture : \(name)\nÉchec : \(message)\n\n\(app.debugDescription)")
        details.name = "FAILED-\(name)-hierarchy"
        details.lifetime = .keepAlways
        add(details)
        XCTFail("[\(name)] \(message)", file: file, line: line)
        return false
    }

    private func matchesOrientation(_ size: CGSize, landscape: Bool) -> Bool {
        guard size.width > 0, size.height > 0, size.width != size.height else { return false }
        return (size.width > size.height) == landscape
    }
}
