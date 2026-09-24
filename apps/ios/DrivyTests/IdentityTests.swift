import CryptoKit
import Foundation
import Security
import Testing
import UIKit
@preconcurrency import AppAuth
@testable import Drivy

@MainActor
struct IdentityTests {
    @Test func configurationRejectsMissingInsecureAndAmbiguousValues() {
        #expect(AppConfiguration.from(values: [:]) == nil)
        let valid: [String: Any] = ["DrivyAPIBaseURL": "https://api.example.test",
                                    "DrivyOIDCIssuer": "https://identity.example.test/realms/drivy",
                                    "DrivyOIDCClientID": "drivy-apple"]
        #expect(AppConfiguration.from(values: valid) != nil)
        for url in ["http://identity.example.test", "https://user:password@identity.example.test",
                    "https://identity.example.test/#fragment", "https://identity.example.test/?query=x", "$(DRIVY_OIDC_ISSUER)"] {
            var values = valid
            values["DrivyOIDCIssuer"] = url
            #expect(AppConfiguration.from(values: values) == nil)
        }
        var values = valid
        values["DrivyOIDCClientID"] = " "
        #expect(AppConfiguration.from(values: values) == nil)
        let invalidCallback = AppConfiguration(apiBaseURL: identityConfiguration.apiBaseURL,
            issuer: identityConfiguration.issuer, clientID: "drivy-apple", redirectURL: URL(string: "other:/callback")!)
        #expect(!invalidCallback.isValid)
    }

    @Test func discoveryRequiresExactIssuerAndSameHTTPSOrigin() {
        #expect(OIDCPolicy.accepts(identityService(), configuration: identityConfiguration))
        let trailingSlash = OIDServiceConfiguration(authorizationEndpoint: identityService().authorizationEndpoint,
            tokenEndpoint: identityService().tokenEndpoint, issuer: URL(string: identityConfiguration.issuer.absoluteString + "/"))
        #expect(!OIDCPolicy.accepts(trailingSlash, configuration: identityConfiguration))
        let foreignEndpoint = OIDServiceConfiguration(authorizationEndpoint: identityService().authorizationEndpoint,
            tokenEndpoint: URL(string: "https://foreign.example.test/token")!, issuer: identityConfiguration.issuer)
        #expect(!OIDCPolicy.accepts(foreignEndpoint, configuration: identityConfiguration))
    }

    @Test func appAuthCreatesCodeFlowWithRandomStateNonceAndPKCES256() throws {
        let first = OIDCPolicy.request(service: identityService(), configuration: identityConfiguration)
        let second = OIDCPolicy.request(service: identityService(), configuration: identityConfiguration)
        let verifier = try #require(first.codeVerifier)
        let expected = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(first.responseType == OIDResponseTypeCode)
        #expect(first.clientSecret == nil)
        #expect(first.codeChallengeMethod == "S256")
        #expect(first.codeChallenge == expected)
        #expect(first.state != nil && first.state != second.state)
        #expect(first.nonce != nil && first.nonce != second.nonce)
        #expect(first.codeVerifier != second.codeVerifier)
    }

    @Test func secureArchiveRoundTripIsBoundToConfiguration() throws {
        let state = try identityState()
        let data = try StoredIdentity.encode(state, configuration: identityConfiguration)
        let restored = try StoredIdentity.decode(data, configuration: identityConfiguration)
        #expect(restored.isAuthorized)
        #expect(restored.lastTokenResponse?.accessToken == state.lastTokenResponse?.accessToken)
        let other = AppConfiguration(apiBaseURL: URL(string: "https://other-api.example.test")!,
            issuer: identityConfiguration.issuer, clientID: identityConfiguration.clientID, redirectURL: AppConfiguration.callback)
        #expect(throws: IdentityFailure.self) { try StoredIdentity.decode(data, configuration: other) }
        #expect(throws: IdentityFailure.self) { try StoredIdentity.decode(Data("invalid".utf8), configuration: identityConfiguration) }
    }

    @Test func realKeychainSupportsProtectedWriteUpdateReadAndDelete() throws {
        let service = "ch.drivy.tests.identity." + UUID().uuidString
        let vault = KeychainIdentityVault(service: service)
        defer { try? vault.clear() }
        #expect(try vault.read() == nil)
        try vault.write(Data("synthetic-test-value".utf8))
        try vault.write(Data("synthetic-test-update".utf8))
        #expect(try vault.read() == Data("synthetic-test-update".utf8))
        var attributes: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true
        ] as CFDictionary, &attributes)
        #expect(status == errSecSuccess)
        let values = try #require(attributes as? [String: Any])
        #expect(values[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect((values[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue != true)
        try vault.clear()
        #expect(try vault.read() == nil)
    }

    @Test func noConfigurationAndStorageFailureNeverAcknowledgeLogin() async throws {
        let authorizer = TestIdentityAuthorizer(state: try identityState())
        let missing = IdentitySession(configuration: nil, vault: TestIdentityVault(), authorizer: authorizer)
        await missing.restore()
        await missing.signIn(presenting: UIViewController())
        #expect(!missing.isAuthenticated && authorizer.authorizationCount == 0)
        let vault = TestIdentityVault()
        vault.failWrites = true
        let session = IdentitySession(configuration: identityConfiguration, vault: vault, authorizer: authorizer)
        await session.signIn(presenting: UIViewController())
        #expect(!session.isAuthenticated)
        #expect(session.errorMessage == IdentityFailure.storage.localizedDescription)
        #expect(vault.data == nil)
    }

    @Test func concurrentTokenRequestsShareOneRefresh() async throws {
        let vault = TestIdentityVault()
        let authorizer = TestIdentityAuthorizer(state: try identityState())
        let session = IdentitySession(configuration: identityConfiguration, vault: vault, authorizer: authorizer)
        await session.signIn(presenting: UIViewController())
        authorizer.holdRefresh = true
        var requesters = 0
        let first = Task { requesters += 1; return try await session.accessToken() }
        let second = Task { requesters += 1; return try await session.accessToken() }
        try await waitForIdentity { requesters == 2 && authorizer.refreshCount == 1 }
        authorizer.completeRefresh()
        let firstToken = try await first.value
        let secondToken = try await second.value
        #expect(firstToken == secondToken)
        #expect(authorizer.refreshCount == 1)
        #expect(vault.writeCount == 2)
    }

    @Test func logoutRejectsLateRefreshAndCannotRestoreDeletedSession() async throws {
        let vault = TestIdentityVault()
        let authorizer = TestIdentityAuthorizer(state: try identityState())
        let session = IdentitySession(configuration: identityConfiguration, vault: vault, authorizer: authorizer)
        await session.signIn(presenting: UIViewController())
        authorizer.holdRefresh = true
        let token = Task { try await session.accessToken() }
        try await waitForIdentity { authorizer.refreshCount == 1 }
        await session.signOut()
        #expect(!session.isAuthenticated && vault.data == nil)
        authorizer.completeRefresh()
        do { _ = try await token.value; Issue.record("Une réponse tardive a traversé la déconnexion.") }
        catch { #expect(error is CancellationError) }
        #expect(vault.data == nil && vault.writeCount == 1)
        let reopened = IdentitySession(configuration: identityConfiguration, vault: vault, authorizer: authorizer)
        await reopened.restore()
        #expect(!reopened.isAuthenticated)
    }

    @Test func logoutRejectsLateAuthorizationWithoutSpuriousError() async throws {
        let vault = TestIdentityVault()
        let authorizer = TestIdentityAuthorizer(state: try identityState())
        authorizer.holdAuthorization = true
        let session = IdentitySession(configuration: identityConfiguration, vault: vault, authorizer: authorizer)
        let login = Task { await session.signIn(presenting: UIViewController()) }
        try await waitForIdentity { authorizer.authorizationCount == 1 }
        await session.signOut()
        authorizer.completeAuthorization()
        await login.value
        #expect(!session.isAuthenticated && vault.data == nil)
        #expect(session.errorMessage == nil)
    }

    @Test func providerErrorsAreSanitizedAndCancellationIsSilent() async throws {
        let authorizer = TestIdentityAuthorizer(state: try identityState())
        let session = IdentitySession(configuration: identityConfiguration, vault: TestIdentityVault(), authorizer: authorizer)
        authorizer.authorizationFailure = NSError(domain: "provider", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synthetic-sensitive-response"])
        await session.signIn(presenting: UIViewController())
        #expect(session.errorMessage == IdentityFailure.unavailable.localizedDescription)
        authorizer.authorizationFailure = CancellationError()
        await session.signIn(presenting: UIViewController())
        #expect(session.errorMessage == nil && !session.isAuthenticated && !session.isWorking)
    }

    @Test func restoreRejectsConfigurationDriftBeforeRefresh() async throws {
        let vault = TestIdentityVault()
        vault.data = try StoredIdentity.encode(identityState(), configuration: identityConfiguration)
        let authorizer = TestIdentityAuthorizer(state: try identityState())
        let other = AppConfiguration(apiBaseURL: identityConfiguration.apiBaseURL,
            issuer: identityConfiguration.issuer, clientID: "another-client", redirectURL: AppConfiguration.callback)
        let session = IdentitySession(configuration: other, vault: vault, authorizer: authorizer)
        await session.restore()
        #expect(!session.isAuthenticated && authorizer.refreshCount == 0)
        #expect(session.errorMessage == IdentityFailure.invalidProvider.localizedDescription)
    }
}

private let identityConfiguration = AppConfiguration(apiBaseURL: URL(string: "https://api.example.test")!,
    issuer: URL(string: "https://identity.example.test/realms/drivy")!, clientID: "drivy-apple", redirectURL: AppConfiguration.callback)

@MainActor
private func identityService() -> OIDServiceConfiguration {
    OIDServiceConfiguration(authorizationEndpoint: URL(string: "https://identity.example.test/realms/drivy/authorize")!,
        tokenEndpoint: URL(string: "https://identity.example.test/realms/drivy/token")!, issuer: identityConfiguration.issuer)
}

@MainActor
private func identityState() throws -> OIDAuthState {
    let request = OIDCPolicy.request(service: identityService(), configuration: identityConfiguration)
    let response = OIDAuthorizationResponse(request: request,
        parameters: ["code": "synthetic-test-code" as NSString, "state": (request.state ?? "") as NSString])
    let exchange = try #require(response.tokenExchangeRequest())
    let token = OIDTokenResponse(request: exchange, parameters: [
        "access_token": "synthetic-test-access" as NSString,
        "refresh_token": "synthetic-test-refresh" as NSString,
        "token_type": "Bearer" as NSString, "expires_in": NSNumber(value: 3600)
    ])
    return OIDAuthState(authorizationResponse: response, tokenResponse: token)
}

@MainActor
private final class TestIdentityVault: IdentityVault {
    var data: Data?
    var failWrites = false
    var writeCount = 0
    func read() throws -> Data? { data }
    func write(_ value: Data) throws {
        if failWrites { throw IdentityFailure.storage }
        data = value
        writeCount += 1
    }
    func clear() throws { data = nil }
}

@MainActor
private final class TestIdentityAuthorizer: IdentityAuthorizing {
    let state: OIDAuthState
    var holdAuthorization = false
    var holdRefresh = false
    var authorizationCount = 0
    var refreshCount = 0
    var authorizationFailure: Error?
    private var authorizationWaiter: CheckedContinuation<Void, Never>?
    private var refreshWaiter: CheckedContinuation<Void, Never>?
    init(state: OIDAuthState) { self.state = state }
    func authorize(configuration: AppConfiguration, presenting: UIViewController) async throws -> OIDAuthState {
        authorizationCount += 1
        if let authorizationFailure { throw authorizationFailure }
        if holdAuthorization { await withCheckedContinuation { authorizationWaiter = $0 } }
        return state
    }
    func freshToken(for state: OIDAuthState) async throws -> String {
        refreshCount += 1
        if holdRefresh { await withCheckedContinuation { refreshWaiter = $0 } }
        return "synthetic-test-access"
    }
    // Simule volontairement une réponse réseau qui arrive malgré l'annulation.
    func cancel() {}
    func handleRedirect(_ url: URL) -> Bool { false }
    func completeAuthorization() { authorizationWaiter?.resume(); authorizationWaiter = nil }
    func completeRefresh() { refreshWaiter?.resume(); refreshWaiter = nil }
}

@MainActor
private func waitForIdentity(_ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    throw IdentityFailure.unavailable
}
