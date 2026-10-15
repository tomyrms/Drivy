import Foundation
import Testing
import UIKit
@preconcurrency import AppAuth
@testable import Drivy

/// Connexion par le formulaire de l’app et « J’ai un code » : aucun appel réseau, des fournisseurs simulés.
@MainActor
struct NativeAccountTests {
    private let configuration = AppConfiguration(apiBaseURL: URL(string: "https://drivy.example.test")!,
        issuer: URL(string: "https://drivy.example.test/identity/realms/drivy")!, clientID: "drivy-apple", redirectURL: AppConfiguration.callback)

    @Test func passwordSignInIsDurableBeforeBeingAnnounced() async throws {
        let vault = MemoryVault()
        let password = PasswordStub(state: try passwordState(configuration))
        let session = IdentitySession(configuration: configuration, vault: vault, authorizer: UnusedAuthorizer(), passwordAuthorizer: password)
        let connected = await session.signIn(email: "  camille@example.test ", password: "secret-value")
        #expect(connected)
        #expect(session.isAuthenticated)
        #expect(vault.data != nil)
        #expect(password.lastEmail == "camille@example.test")
        // La session rangée se relit comme une connexion par navigateur.
        let restored = try StoredIdentity.decode(try #require(vault.data), configuration: configuration)
        #expect(restored.isAuthorized)
    }

    @Test func refusedCredentialsSayItWithoutDetailAndKeepNothing() async {
        let vault = MemoryVault()
        let password = PasswordStub(state: nil, failure: IdentityFailure.invalidCredentials)
        let session = IdentitySession(configuration: configuration, vault: vault, authorizer: UnusedAuthorizer(), passwordAuthorizer: password)
        let connected = await session.signIn(email: "camille@example.test", password: "wrong")
        #expect(!connected)
        #expect(!session.isAuthenticated)
        #expect(vault.data == nil)
        #expect(session.errorMessage == "E-mail ou mot de passe incorrect.")
        session.clearError()
        #expect(session.errorMessage == nil)
    }

    @Test func providerErrorsMapToCredentialsOrUnavailable() {
        let refused = NSError(domain: OIDOAuthTokenErrorDomain, code: -10)
        let network = NSError(domain: OIDGeneralErrorDomain, code: OIDErrorCode.networkError.rawValue)
        #expect(AppAuthPasswordAuthorization.failure(refused) == .invalidCredentials)
        #expect(AppAuthPasswordAuthorization.failure(network) == .unavailable)
        #expect(AppAuthPasswordAuthorization.failure(nil) == .unavailable)
    }

    @Test func accessInputReadsCodesAndLinksOfThisOriginOnly() {
        #expect(SchoolAccessInput.parse(" k7q4 mx2p ", configuration: configuration) == .code("K7Q4-MX2P"))
        #expect(SchoolAccessInput.parse("https://drivy.example.test/app/ouvrir#token=K7Q4-MX2P", configuration: configuration) == .openingLink("K7Q4-MX2P"))
        let token = String(repeating: "a", count: 42) + "A"
        #expect(SchoolAccessInput.parse("https://drivy.example.test/app/invitation#token=\(token)", configuration: configuration) == .invitationLink(token))
        #expect(SchoolAccessInput.parse("https://other.example.test/app/ouvrir#token=K7Q4-MX2P", configuration: configuration) == nil)
        #expect(SchoolAccessInput.parse("http://drivy.example.test/app/ouvrir#token=K7Q4-MX2P", configuration: configuration) == nil)
        #expect(SchoolAccessInput.parse("K7Q4-MX21", configuration: configuration) == nil)
        #expect(SchoolAccessInput.code("K7Q4-MX2P").secret == "K7Q4-MX2P")
    }

    @Test func accountFailuresAreToldInPlainWords() {
        #expect(SchoolAccountClient.failure(404, code: "ACCESS_CODE_INVALID") == .invalidCode)
        #expect(SchoolAccountClient.failure(409, code: "ACCOUNT_EXISTS") == .accountExists)
        #expect(SchoolAccountClient.failure(400, code: "ACCOUNT_PASSWORD_REJECTED") == .passwordRejected)
        #expect(SchoolAccountClient.failure(429, code: "ACCESS_CODE_ATTEMPTS") == .attempts)
        #expect(SchoolAccountClient.failure(503, code: "ACCOUNT_CREATION_UNAVAILABLE") == .unavailable)
        #expect(SchoolAccountClient.failure(400, code: "INVALID_REQUEST") == .invalidRequest)
    }

    @Test func openingCommandSendsAnExplicitNullPhone() throws {
        let command = SchoolOpeningCommand(operationId: UUID(), token: "K7Q4-MX2P", schoolName: "École", displayName: "Camille",
                                           contactEmail: "ecole@example.test", contactPhone: nil, timeZone: "Europe/Zurich", instructs: true)
        let json = try #require(String(data: try JSONEncoder().encode(command), encoding: .utf8))
        #expect(json.contains("\"contactPhone\":null"))
    }
}

@MainActor
private func passwordState(_ configuration: AppConfiguration) throws -> OIDAuthState {
    let service = OIDServiceConfiguration(authorizationEndpoint: URL(string: "https://drivy.example.test/identity/realms/drivy/auth")!,
        tokenEndpoint: URL(string: "https://drivy.example.test/identity/realms/drivy/token")!, issuer: configuration.issuer)
    let request = OIDCPolicy.request(service: service, configuration: configuration)
    let response = OIDAuthorizationResponse(request: request,
        parameters: ["code": "password-sign-in" as NSString, "state": (request.state ?? "") as NSString])
    let exchange = try #require(response.tokenExchangeRequest())
    let token = OIDTokenResponse(request: exchange, parameters: [
        "access_token": "synthetic-test-access" as NSString, "refresh_token": "synthetic-test-refresh" as NSString,
        "token_type": "Bearer" as NSString, "expires_in": NSNumber(value: 300)
    ])
    return OIDAuthState(authorizationResponse: response, tokenResponse: token)
}

@MainActor private final class MemoryVault: IdentityVault {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ value: Data) throws { data = value }
    func clear() throws { data = nil }
}

@MainActor private final class PasswordStub: PasswordAuthorizing {
    let state: OIDAuthState?
    let failure: Error?
    var lastEmail: String?
    init(state: OIDAuthState?, failure: Error? = nil) { self.state = state; self.failure = failure }
    func signIn(email: String, password: String, configuration: AppConfiguration) async throws -> OIDAuthState {
        lastEmail = email
        if let failure { throw failure }
        guard let state else { throw IdentityFailure.unavailable }
        return state
    }
}

@MainActor private final class UnusedAuthorizer: IdentityAuthorizing {
    func authorize(configuration: AppConfiguration, presenting: UIViewController) async throws -> OIDAuthState { throw IdentityFailure.unavailable }
    func freshToken(for state: OIDAuthState) async throws -> String { "synthetic-test-access" }
    func cancel() {}
    func handleRedirect(_ url: URL) -> Bool { false }
}
