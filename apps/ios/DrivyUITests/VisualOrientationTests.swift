import XCTest

/// Campagne opt-in : les captures conservent l’orientation réelle du simulateur.
@MainActor final class VisualOrientationTests: XCTestCase {
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
        XCTAssertTrue(["iPhone", "iPad"].contains(device))
        XCTAssertTrue(["light", "dark"].contains(appearance))
        defer { XCUIDevice.shared.orientation = .portrait }

        for orientation in orientations {
            XCTAssertTrue(["portrait", "landscape"].contains(orientation))
            let landscape = orientation == "landscape"
            for screen in screens {
                XCTContext.runActivity(named: "\(device) · \(screen) · \(appearance) · \(orientation)") { _ in
                    let app = XCUIApplication()
                    let interactiveSignal = ["live-signal", "signal-status"].contains(screen)
                    app.launchEnvironment["DRIVY_VISUAL_SCREEN"] = interactiveSignal ? "live" : screen
                    app.launchEnvironment["DRIVY_VISUAL_LARGE_TEXT"] = environment["DRIVY_VISUAL_LARGE_TEXT"] ?? "0"
                    app.launchArguments = ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_CH",
                                           "-AppleInterfaceStyle", appearance == "dark" ? "Dark" : "Light"]
                    XCUIDevice.shared.orientation = .portrait
                    app.launch()
                    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
                    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
                    XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
                    let deadline = Date().addingTimeInterval(10)
                    while !matchesOrientation(app.frame.size, landscape: landscape), Date() < deadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    }
                    XCTAssertTrue(matchesOrientation(app.frame.size, landscape: landscape),
                                  "La fenêtre n’a pas pris l’orientation demandée.")
                    // Même délai de stabilisation des fixtures/MapKit que la voie simctl.
                    RunLoop.current.run(until: Date().addingTimeInterval(10))
                    if interactiveSignal {
                        let signal = app.buttons["capture-signal-observation"]
                        XCTAssertTrue(signal.waitForExistence(timeout: 10))
                        signal.tap()
                        let priority = app.buttons["live-observation-theme-Priorité à droite"]
                        XCTAssertTrue(priority.waitForExistence(timeout: 10))
                        if screen == "signal-status" {
                            priority.tap()
                            XCTAssertTrue(app.buttons["live-observation-status-ATTENTION"].waitForExistence(timeout: 10))
                        }
                        RunLoop.current.run(until: Date().addingTimeInterval(1))
                    }
                    XCTAssertEqual(XCUIDevice.shared.orientation.isLandscape, landscape)
                    let screenshot = XCUIScreen.main.screenshot()
                    XCTAssertTrue(matchesOrientation(screenshot.image.size, landscape: landscape),
                                  "La capture système n’a pas les dimensions de l’orientation demandée.")
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = "\(device)-\(screen)-\(appearance)-\(orientation)-synthetic"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    app.terminate()
                }
            }
        }
    }

    private func matchesOrientation(_ size: CGSize, landscape: Bool) -> Bool {
        guard size.width > 0, size.height > 0, size.width != size.height else { return false }
        return (size.width > size.height) == landscape
    }
}
