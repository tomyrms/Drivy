#if DEBUG && targetEnvironment(simulator)
import Foundation
import UIKit
@preconcurrency import AppAuth

/// Opt-in UI fixture for the real application root, identity restoration and foreground callback.
/// Only the identity provider and school responses are synthetic. It never opens a network connection.
@MainActor final class SchoolRootEntryFixture: NSObject {
    private enum Scenario: String { case staff = "draft-to-staff", administration = "draft-to-administration" }
    static let current: SchoolRootEntryFixture? = {
        guard let value = ProcessInfo.processInfo.environment["DRIVY_ROOT_ENTRY_SCENARIO"] else { return nil }
        guard let scenario = Scenario(rawValue: value) else {
            preconditionFailure("Unknown root entry fixture scenario.")
        }
        precondition(ProcessInfo.processInfo.environment["DRIVY_VISUAL_SCREEN"] == nil,
                     "Root entry tests must use the real application root.")
        return SchoolRootEntryFixture(scenario: scenario)
    }()

    let configuration = AppConfiguration(apiBaseURL: URL(string: "https://root-entry.example.invalid")!,
        issuer: URL(string: "https://identity.example.invalid/realms/fixture")!,
        clientID: "root-entry-fixture", redirectURL: AppConfiguration.callback)
    private let scenario: Scenario
    // A fresh membership avoids the real seven-day welcome deferral from a previous UI test.
    private let membershipID = UUID()
    private let personID = UUID()
    private let schoolID = UUID()
    private let policyID = UUID()
    private let onboardingID = UUID()
    private var activated = false
    private let date = "2026-01-01T00:00:00Z"

    private init(scenario: Scenario) {
        self.scenario = scenario
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// Simulates a server change while the user is outside the app. No workspace refresh is called here.
    @objc private func enteredBackground() { activated = true }

    func makeAppLock() -> AppLock {
        let store = UserDefaults(suiteName: "drivy.root-entry-fixture.\(membershipID.uuidString)")!
        let lock = AppLock(store: store)
        lock.answerOffer(enable: false)
        return lock
    }

    func makeIdentity() -> IdentitySession {
        let service = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://identity.example.invalid/authorize")!,
            tokenEndpoint: URL(string: "https://identity.example.invalid/token")!, issuer: configuration.issuer)
        let request = OIDCPolicy.request(service: service, configuration: configuration)
        let response = OIDAuthorizationResponse(request: request,
            parameters: ["code": "synthetic-test-code" as NSString, "state": (request.state ?? "") as NSString])
        guard let exchange = response.tokenExchangeRequest() else { preconditionFailure("Invalid fixture identity request.") }
        let token = OIDTokenResponse(request: exchange, parameters: [
            "access_token": "synthetic-test-access" as NSString,
            "refresh_token": "synthetic-test-refresh" as NSString,
            "token_type": "Bearer" as NSString, "expires_in": NSNumber(value: 3600)
        ])
        let state = OIDAuthState(authorizationResponse: response, tokenResponse: token)
        guard let encoded = try? StoredIdentity.encode(state, configuration: configuration) else {
            preconditionFailure("Invalid fixture identity archive.")
        }
        return IdentitySession(configuration: configuration, vault: RootEntryIdentityVault(encoded),
                               authorizer: RootEntryIdentityAuthorizer())
    }

    func send(_ request: URLRequest) throws -> SchoolHTTPResponse {
        precondition(request.httpMethod == "GET", "The root entry fixture forbids business mutations.")
        guard let url = request.url, url.scheme == "https", url.host == configuration.apiBaseURL.host else {
            preconditionFailure("The root entry fixture forbids external requests.")
        }
        let path = url.path.lowercased()
        if path == "/v1/me" { return try response(person, url: url) }
        let schoolPath = "/v1/schools/\(schoolID.uuidString.lowercased())"
        switch path {
        case schoolPath:
            return try response(school, url: url, requiredNulls: ["contactPhone", "logoAssetId"])
        case schoolPath + "/learners":
            return try response(SchoolPage<SchoolLearner>(items: [], nextCursor: nil), url: url, requiredNulls: ["nextCursor"])
        case schoolPath + "/lessons":
            return try response(SchoolPage<SchoolLesson>(items: [], nextCursor: nil), url: url, requiredNulls: ["nextCursor"])
        case schoolPath + "/profile-field-policies":
            return try response(SchoolPage(items: [policy], nextCursor: nil), url: url, requiredNulls: ["nextCursor"])
        case schoolPath + "/my-onboarding":
            // An early AP172 read is a test failure even if a later guard would hide its result.
            precondition(activated && scenario == .staff, "Personal onboarding was requested before an eligible active entry.")
            let kind = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "kind" }?.value
            precondition(kind == "STAFF", "The root entry fixture expected staff onboarding.")
            return try response(onboarding, url: url, requiredNulls: ["returnDestinationKey", "returnResourceId"])
        case schoolPath + "/data-policy":
            return try response(notice, url: url)
        default:
            // Unsupported optional reads fail closed; they never fall through to the real URLSession.
            throw SchoolAPIError.invalidResponse
        }
    }

    private var membership: SchoolMembership {
        .init(membershipId: membershipID, schoolId: schoolID, schoolName: "École exemple",
              roles: activated && scenario == .administration ? ["ADMIN"] : ["ADMIN", "INSTRUCTOR"], grants: [],
              accessEpoch: activated && scenario == .administration ? 2 : 1)
    }
    private var person: SchoolPerson {
        .init(personId: personID, version: 1, displayName: "Responsable exemple", locale: "fr", memberships: [membership])
    }
    private var school: SchoolDetails {
        .init(id: schoolID, schoolId: schoolID, version: activated ? 2 : 1, name: "École exemple", timeZone: "Europe/Zurich",
              status: activated ? "ACTIVE" : "DRAFT", contactEmail: "contact@example.invalid", contactPhone: nil, logoAssetId: nil,
              modules: .init(gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false),
              configurationVersion: 1)
    }
    private var policy: SchoolProfilePolicy {
        .init(id: policyID, schoolId: schoolID, version: 1, status: "PUBLISHED", effectiveFrom: date,
              fields: [.init(field: .firstName, requirement: .required, stage: .join, purposeCode: .identification,
                             explanation: "Identifier le dossier scolaire."),
                       .init(field: .lastName, requirement: .required, stage: .join, purposeCode: .identification,
                             explanation: "Identifier le dossier scolaire.")],
              noticeVersionId: policyID, approvedByMembershipId: membershipID)
    }
    private var notice: SchoolDataPolicy {
        .init(id: policyID, schoolId: schoolID, version: 1, status: "APPROVED",
              noticeText: "Notice fictive de l’école exemple.", retentionText: "Durée fictive définie par l’école.",
              contactEmail: "contact@example.invalid", approvedAt: date, approvedByMembershipId: membershipID, noticeVersionId: policyID)
    }
    private var onboarding: SchoolOnboarding {
        .init(id: onboardingID, schoolId: schoolID, version: 1, personId: personID, membershipId: membershipID,
              kind: .staff, status: "IN_PROGRESS", currentStep: .identity, skippedOptionalSteps: [], policyVersionId: policyID,
              lastSavedAt: date, pendingActions: [], returnDestinationKey: nil, returnResourceId: nil)
    }
    private struct Envelope<Value: Codable>: Codable {
        let data: Value
        let requestId: UUID
        let serverTime: String
    }
    private func response<Value: Codable>(_ value: Value, url: URL, requiredNulls: [String] = []) throws -> SchoolHTTPResponse {
        let encoded = try JSONEncoder().encode(Envelope(data: value, requestId: UUID(), serverTime: date))
        guard var envelope = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var payload = envelope["data"] as? [String: Any] else {
            preconditionFailure("Invalid root entry fixture payload.")
        }
        // The read contract requires these keys even when null; synthesized Encodable omits nil properties.
        for key in requiredNulls where payload[key] == nil { payload[key] = NSNull() }
        envelope["data"] = payload
        let data = try JSONSerialization.data(withJSONObject: envelope)
        // Exercise the actual DTO decoder before handing the response to its client.
        guard (try? JSONDecoder().decode(Envelope<Value>.self, from: data)) != nil else {
            preconditionFailure("The root entry fixture does not satisfy its response contract.")
        }
        return .init(data: data, status: 200, url: url, contentType: "application/json")
    }
}

@MainActor private final class RootEntryIdentityVault: IdentityVault {
    private var data: Data?
    init(_ data: Data) { self.data = data }
    func read() throws -> Data? { data }
    func write(_ value: Data) throws { data = value }
    func clear() throws { data = nil }
}

@MainActor private final class RootEntryIdentityAuthorizer: IdentityAuthorizing {
    func authorize(configuration: AppConfiguration, presenting: UIViewController) async throws -> OIDAuthState {
        preconditionFailure("The root entry fixture must restore its memory-only identity.")
    }
    func freshToken(for state: OIDAuthState) async throws -> String { "synthetic-test-access" }
    func cancel() {}
    func handleRedirect(_ url: URL) -> Bool { false }
}
#endif
