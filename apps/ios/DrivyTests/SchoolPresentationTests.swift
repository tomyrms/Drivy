import SwiftUI
import XCTest
@testable import Drivy

@MainActor
final class SchoolPresentationTests: XCTestCase {
    func testNativeSchoolViewsWithSyntheticServerResponses() async throws {
        let bundle = Bundle(for: Self.self)
        var fixtures: [String: Data] = [:]
        for name in ["me", "school", "learners", "learner", "trainings", "training"] {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") ??
                                    bundle.url(forResource: name, withExtension: "json"))
            fixtures[name] = try Data(contentsOf: url)
        }
        let api = DrivyAPIClient(baseURL: URL(string: "https://api.example.invalid")!,
            tokenSource: PresentationToken(), transport: PresentationTransport(fixtures: fixtures))
        let workspace = SchoolWorkspace(api: api)
        await workspace.loadAccount()
        let membership = try XCTUnwrap(workspace.person?.memberships.first)
        await workspace.selectSchool(membership)
        XCTAssertEqual(workspace.learners.first?.displayName, "Alice Exemple")

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = presentationWindow(scene: scene, workspace: workspace, style: .light)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }

        try await Task.sleep(for: .seconds(1))
        attach(window, name: "g1a-01-eleves-clair-fixtures")
        workspace.selectLearner(workspace.learners.first?.id)
        await workspace.loadSelectedLearner()
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(workspace.learner?.displayName, "Alice Exemple")
        XCTAssertEqual(workspace.trainings.count, 1)
        attach(window, name: "g1a-03-dossier-formation-fixtures")

        // A fresh hierarchy starts in dark mode. Changing a live window's
        // appearance can capture the system search material mid-transition.
        window.isHidden = true
        workspace.selectLearner(nil)
        let darkWindow = presentationWindow(scene: scene, workspace: workspace, style: .dark)
        defer { darkWindow.isHidden = true }
        try await Task.sleep(for: .seconds(1))
        attach(darkWindow, name: "g1a-02-eleves-sombre-fixtures")
    }

    private func presentationWindow(scene: UIWindowScene, workspace: SchoolWorkspace,
                                    style: UIUserInterfaceStyle) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: SchoolBrowserView(workspace: workspace, openAccount: {})
            .tint(DrivyTheme.accent).foregroundStyle(DrivyTheme.text))
        host.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        return window
    }

    private func attach(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        XCTAssertGreaterThan(window.bounds.width, 0)
        var rendered = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class PresentationToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-test-token" }
}

private struct PresentationTransport: SchoolHTTPTransport {
    let fixtures: [String: Data]
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url else { throw SchoolAPIError.invalidResponse }
        let parts = url.pathComponents
        let name: String
        if parts.last == "me" { name = "me" }
        else if parts.last == "learners" { name = "learners" }
        else if parts.last == "trainings" { name = "trainings" }
        else if parts.dropLast().last == "learners" { name = "learner" }
        else if parts.dropLast().last == "trainings" { name = "training" }
        else { name = "school" }
        guard let data = fixtures[name] else { throw SchoolAPIError.invalidResponse }
        return SchoolHTTPResponse(data: data, status: 200, url: url, contentType: "application/json")
    }
}
