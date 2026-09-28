import SwiftUI
import XCTest
@testable import Drivy

@MainActor
final class SchoolPresentationTests: XCTestCase {
    func testNativeAdministrativeProfileAndPolicyUseRealViewsWithSyntheticResponses() async throws {
        let api = ProfileAPIStub()
        api.profileValue = ProfileFixture.profile(firstName: nil, lastName: nil)
        let profile = ProfileFixture.workspace(api: api)
        let policy = SchoolProfileWorkspace(scope: ConfigurationFixture.scope(), roles: ["ADMIN"], api: api, outbox: ConfigurationOutboxStub())
        await profile.load(); await policy.load()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        var windows: [UIWindow] = []
        defer { windows.forEach { $0.isHidden = true }; previous?.makeKeyAndVisible(); profile.invalidate(); policy.invalidate() }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let window = contentWindow(scene: scene, style: style, content: SchoolProfileView(model: profile))
            windows.append(window)
            try await Task.sleep(for: .seconds(1))
            attach(window, name: style == .light ? "g1d-01-profil-clair-fixtures" : "g1d-02-profil-sombre-fixtures")
            window.isHidden = true
        }
        let policyWindow = contentWindow(scene: scene, style: .light,
            content: SchoolProfilePolicyView(model: policy).environment(\.dynamicTypeSize, .accessibility1))
        windows.append(policyWindow)
        try await Task.sleep(for: .seconds(1))
        attach(policyWindow, name: "g1d-03-politique-grand-texte-fixtures")
        XCTAssertTrue(api.commands.isEmpty)
        XCTAssertTrue(profile.draft.firstName.isEmpty && profile.draft.lastName.isEmpty)
    }
    func testNativeInvitationsListFormAndUncertainCommand() async throws {
        let api = InvitationAPIStub()
        api.items = [InvitationFixture.invitation(),
            InvitationFixture.invitation(id: UUID(), email: "m***@example.invalid", roles: [.instructor], status: .expired),
            InvitationFixture.invitation(id: UUID(), email: "r***@example.invalid", status: .accepted)]
        let outbox = ConfigurationOutboxStub()
        let model = InvitationFixture.workspace(api: api, outbox: outbox)
        await model.load()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        var windows: [UIWindow] = []
        defer { windows.forEach { $0.isHidden = true }; previous?.makeKeyAndVisible(); model.invalidate() }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let window = contentWindow(scene: scene, style: style, content: SchoolInvitationsView(model: model))
            windows.append(window)
            try await Task.sleep(for: .seconds(1))
            attach(window, name: style == .light ? "f02-01-invitations-clair-fixtures" : "f02-02-invitations-sombre-fixtures")
            window.isHidden = true
        }
        model.email = "personne@example.invalid"
        let form = contentWindow(scene: scene, style: .light, content: InvitationCreationView(model: model)
            .environment(\.dynamicTypeSize, .accessibility1))
        windows.append(form)
        try await Task.sleep(for: .seconds(1))
        attach(form, name: "f02-03-formulaire-grand-texte-fixtures")
        form.isHidden = true
        XCTAssertTrue(api.commands.isEmpty)
        outbox.value = try InvitationFixture.command()
        await model.load()
        let pending = contentWindow(scene: scene, style: .light, content: SchoolInvitationsView(model: model))
        windows.append(pending)
        try await Task.sleep(for: .seconds(1))
        attach(pending, name: "f02-04-demande-incertaine-fixtures")
        XCTAssertFalse(model.mayEdit)
        XCTAssertEqual(model.invitations.count, 3)
        XCTAssertTrue(api.commands.isEmpty)
    }

    func testNativeSchoolConfigurationKeepsDraftTextsUnapproved() async throws {
        let api = ConfigurationAPIStub()
        let model = SchoolConfigurationWorkspace(scope: ConfigurationFixture.scope(), api: api, outbox: ConfigurationOutboxStub())
        await model.load()
        XCTAssertFalse(model.canActivate)
        XCTAssertTrue(api.commands.isEmpty)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .light
        let host = UIHostingController(rootView: SchoolConfigurationView(model: model, openSchool: {}))
        host.overrideUserInterfaceStyle = .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible(); model.invalidate() }
        try await Task.sleep(for: .seconds(1))
        attach(window, name: "g1b-01-configuration-non-approuvee-fixtures")
        XCTAssertTrue(api.commands.isEmpty)
        XCTAssertFalse(model.canActivate)
    }

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
        darkWindow.isHidden = true
        let controller = SessionController()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let mapWindow = contentWindow(scene: scene, style: style,
                content: SchoolHomeView(workspace: workspace, localController: controller, openAccount: {}, signOut: {}, selectedTab: .constant(.session)))
            try await Task.sleep(for: .seconds(3))
            attach(mapWindow, name: style == .light ? "home-carte-clair-fixtures" : "home-carte-sombre-fixtures")
            mapWindow.isHidden = true
        }
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

    private func contentWindow<Content: View>(scene: UIWindowScene, style: UIUserInterfaceStyle, content: Content) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: content.environment(\.locale, Locale(identifier: "fr_CH")))
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
