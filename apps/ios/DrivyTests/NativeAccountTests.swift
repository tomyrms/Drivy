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

    @Test func openingUsesTheKnownAccountNameWithoutSplittingOrReplacingItsCreationName() {
        #expect(SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: " Camille Anne De la Tour-Roux ",
            knownPersonName: "Ancien affichage") == "Camille Anne De la Tour-Roux")
        #expect(SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: nil,
            knownPersonName: "  Camille Anne De la Tour-Roux\n") == "Camille Anne De la Tour-Roux")
        #expect(SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: "  ", knownPersonName: "Camille") == "Camille")
        #expect(SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: nil, knownPersonName: " \n") == nil)
        #expect(SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: nil, knownPersonName: "Nom public choisi",
            identityDisplayName: "Nom du fournisseur") == "Nom public choisi")
        #expect(SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: "Nom saisi", knownPersonName: nil,
            identityDisplayName: "Nom du fournisseur") == "Nom saisi")
    }

    @Test func anInterruptedOpeningReusesTheNameFromTheRestoredNativeSessionWithoutAPerson() async throws {
        let name = "Camille Anne De la Tour-Roux"
        let vault = MemoryVault()
        let state = try passwordState(configuration, idToken: accountIDToken(["name": name]))
        let session = IdentitySession(configuration: configuration, vault: vault, authorizer: UnusedAuthorizer(),
            passwordAuthorizer: PasswordStub(state: state))
        #expect(session.suggestedDisplayName == nil)
        #expect(await session.signIn(email: "camille@example.test", password: "synthetic-password"))
        #expect(session.suggestedDisplayName == name)

        let restored = IdentitySession(configuration: configuration, vault: vault, authorizer: UnusedAuthorizer())
        await restored.restore()
        #expect(restored.isAuthenticated)
        let proposed = SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: nil, knownPersonName: nil,
            identityDisplayName: restored.suggestedDisplayName)
        let model = opening(displayName: proposed)
        #expect(model.displayName == name)
        model.displayName = "Nom public choisi"
        model.prefillAccountDisplayName(restored.suggestedDisplayName)
        #expect(model.displayName == "Nom public choisi")
        await restored.signOut()
        #expect(restored.suggestedDisplayName == nil && vault.data == nil)
    }

    @Test func identityNameSuggestionKeepsWholeNamesAndNeedsTheSessionIssuerAndAudience() throws {
        let fullName = "Camille Anne De la Tour-Roux"
        let structured: [String: Any] = ["given_name": "Camille Anne", "family_name": "De la Tour-Roux"]
        #expect(IdentityDisplayName.suggestion(fromIDToken: try accountIDToken(structured), configuration: configuration) == fullName)
        var publicName = structured
        publicName["name"] = "Nom public distinct"
        #expect(IdentityDisplayName.suggestion(fromIDToken: try accountIDToken(publicName), configuration: configuration) == "Nom public distinct")
        let invalidClaims: [[String: Any]] = [
            ["name": fullName, "iss": "https://foreign.example.test"],
            ["name": fullName, "aud": "other-client"],
            ["name": fullName, "sub": ""],
            ["name": "Camille\nExemple"],
            ["name": String(repeating: "x", count: 201)],
            ["name": ["Camille"]],
            ["given_name": "Camille"]
        ]
        for values in invalidClaims {
            #expect(IdentityDisplayName.suggestion(fromIDToken: try accountIDToken(values), configuration: configuration) == nil)
        }
        let invalidTokens: [String?] = [nil, "invalid", "e30.invalid.signature", String(repeating: "x", count: 65_537)]
        for token in invalidTokens {
            #expect(IdentityDisplayName.suggestion(fromIDToken: token, configuration: configuration) == nil)
        }
    }

    @Test func aNameSuggestionIsNeverExposedWhenTheSessionCannotBeSaved() async throws {
        let vault = MemoryVault()
        vault.failWrites = true
        let state = try passwordState(configuration, idToken: accountIDToken(["name": "Camille Exemple"]))
        let session = IdentitySession(configuration: configuration, vault: vault, authorizer: UnusedAuthorizer(),
            passwordAuthorizer: PasswordStub(state: state))
        #expect(await session.signIn(email: "camille@example.test", password: "synthetic-password") == false)
        #expect(session.suggestedDisplayName == nil && !session.isAuthenticated)
    }

    @Test func schoolOpeningReusesAccountInformationAndDoesNotSelectInstructorByDefault() {
        let model = opening(displayName: "Camille Anne De la Tour-Roux")
        #expect(model.displayName == "Camille Anne De la Tour-Roux")
        #expect(model.contactEmail == "camille@example.test")
        #expect(!model.instructs)
        #expect(model.schoolName.isEmpty && !model.canSubmit)
        model.schoolName = "École synthétique"
        #expect(model.canSubmit)
        model.instructs = true
        #expect(model.instructs && model.canSubmit)
    }

    @Test func aLateAccountReadFillsOnlyTheUneditedOpeningName() {
        let untouched = opening(displayName: nil)
        untouched.prefillAccountDisplayName("Camille Anne De la Tour-Roux")
        #expect(untouched.displayName == "Camille Anne De la Tour-Roux")
        untouched.prefillAccountDisplayName("Autre affichage")
        #expect(untouched.displayName == "Camille Anne De la Tour-Roux")

        let edited = opening(displayName: nil)
        edited.displayName = "Nom choisi"
        edited.prefillAccountDisplayName("Nom du compte")
        #expect(edited.displayName == "Nom choisi")

        let cleared = opening(displayName: "Nom du compte")
        cleared.displayName = ""
        cleared.prefillAccountDisplayName("Nom du compte")
        #expect(cleared.displayName.isEmpty)
    }

    @Test(arguments: [SchoolAccessKind.learnerInvitation, .schoolOpening])
    func anExistingAccountKeepsTheInspectedCodeAndDestination(kind: SchoolAccessKind) async throws {
        let transport = AccessPreviewTransport(kind: kind)
        let model = try access(transport: transport)
        model.codeText = " k7q4 mx2p "
        await model.continueWithExistingAccount()
        #expect(model.step == .signIn)
        #expect(model.input == .code("K7Q4-MX2P"))
        #expect(model.preview?.kind == kind)
        #expect(await transport.codes == ["K7Q4-MX2P"])
        model.email = " camille@example.test "
        model.password = "synthetic-password"
        await model.signIn()
        #expect(model.isFinished)
        #expect(model.password.isEmpty)
        #expect(model.outcome == SchoolAccessOutcome(input: .code("K7Q4-MX2P"), kind: kind,
            displayName: nil, email: "camille@example.test"))
        #expect(await transport.codes == ["K7Q4-MX2P", "K7Q4-MX2P"])
    }

    @Test func editingAnInvitationClearsItsScopeButKeepsAccountFields() async throws {
        let model = try access(transport: AccessPreviewTransport(kind: .learnerInvitation))
        model.codeText = "K7Q4-MX2P"
        await model.inspect()
        model.firstName = "Camille"; model.email = "camille@example.test"; model.password = "synthetic-password"
        model.show(.code)
        #expect(model.input == nil && model.preview == nil && !model.canRegister)
        #expect(model.password.isEmpty && model.firstName == "Camille" && model.email == "camille@example.test")
        model.show(.register)
        #expect(model.step == .code)
    }

    @Test func recoveryKeepsTheInvitationAndEmailWithoutKeepingThePassword() async throws {
        let model = try access(transport: AccessPreviewTransport(kind: .learnerInvitation))
        model.codeText = "K7Q4-MX2P"
        await model.continueWithExistingAccount()
        model.email = "camille@example.test"; model.password = "synthetic-password"
        model.prepareRecovery()
        #expect(model.step == .signIn && model.input == .code("K7Q4-MX2P"))
        #expect(model.password.isEmpty && model.email == "camille@example.test")
        #expect(!model.isFinished && model.outcome == nil)
    }

    @Test func anInvalidCodeKeepsTheExistingAccountOnTheCodeStep() async throws {
        let transport = AccessPreviewTransport(kind: nil)
        let model = try access(transport: transport)
        model.codeText = "K7Q4-MX2P"
        await model.continueWithExistingAccount()
        #expect(model.step == .code && model.input == nil && model.preview == nil)
        #expect(model.errorMessage == SchoolAccountFailure.invalidCode.localizedDescription)
        #expect(!model.isFinished && model.outcome == nil)
        #expect(await transport.codes == ["K7Q4-MX2P"])
    }

    @Test func anExistingAccountWithoutCodeSignsInWithoutInventingAJoinDestination() async throws {
        let transport = AccessPreviewTransport(kind: .learnerInvitation)
        let model = try access(transport: transport)
        model.show(.register)
        #expect(model.step == .code)
        model.codeText = " \n"
        await model.continueWithExistingAccount()
        #expect(model.step == .signIn)
        #expect(await transport.codes.isEmpty)
        model.email = "camille@example.test"
        model.password = "synthetic-password"
        await model.signIn()
        #expect(model.isFinished && model.outcome == nil)
    }

    private func access(transport: AccessPreviewTransport) throws -> SchoolAccessWorkspace {
        let identity = IdentitySession(configuration: configuration, vault: MemoryVault(), authorizer: UnusedAuthorizer(),
            passwordAuthorizer: PasswordStub(state: try passwordState(configuration)))
        return SchoolAccessWorkspace(client: SchoolAccountClient(configuration: configuration, transport: transport), identity: identity)
    }

    private func opening(displayName: String?) -> SchoolOpeningWorkspace {
        SchoolOpeningWorkspace(client: SchoolOpeningClient(configuration: configuration, tokenSource: OpeningToken()),
            code: "K7Q4-MX2P", displayName: displayName, email: "camille@example.test")
    }

    private func accountIDToken(_ values: [String: Any]) throws -> String {
        let defaults: [String: Any] = ["iss": configuration.issuer.absoluteString, "aud": configuration.clientID,
                                      "sub": "synthetic-unlinked-account"]
        let claims = defaults.merging(values) { _, supplied in supplied }
        func encode(_ value: [String: Any]) throws -> String {
            try JSONSerialization.data(withJSONObject: value).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return try encode(["alg": "RS256"]) + "." + encode(claims) + ".synthetic-signature"
    }
}

private actor AccessPreviewTransport: SchoolHTTPTransport {
    let kind: SchoolAccessKind?
    private(set) var codes: [String] = []
    init(kind: SchoolAccessKind?) { self.kind = kind }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = try #require(request.url)
        #expect(url.path == "/v1/access-codes/preview")
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        codes.append(try #require(body["code"]))
        let payload: [String: Any]
        if let kind {
            payload = ["data": ["kind": kind.rawValue, "schoolName": "École synthétique", "expiresAt": "2026-10-22T10:00:00Z"],
                       "serverTime": "2026-10-17T10:00:00Z"]
        } else { payload = ["code": "ACCESS_CODE_INVALID"] }
        return .init(data: try JSONSerialization.data(withJSONObject: payload), status: kind == nil ? 404 : 200,
            url: url, contentType: "application/json")
    }
}

@MainActor private final class OpeningToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-unrequested-opening-token" }
}

@MainActor
private func passwordState(_ configuration: AppConfiguration, idToken: String? = nil) throws -> OIDAuthState {
    let service = OIDServiceConfiguration(authorizationEndpoint: URL(string: "https://drivy.example.test/identity/realms/drivy/auth")!,
        tokenEndpoint: URL(string: "https://drivy.example.test/identity/realms/drivy/token")!, issuer: configuration.issuer)
    let request = OIDCPolicy.request(service: service, configuration: configuration)
    let response = OIDAuthorizationResponse(request: request,
        parameters: ["code": "password-sign-in" as NSString, "state": (request.state ?? "") as NSString])
    let exchange = try #require(response.tokenExchangeRequest())
    var parameters: [String: NSObject & NSCopying] = [
        "access_token": "synthetic-test-access" as NSString, "refresh_token": "synthetic-test-refresh" as NSString,
        "token_type": "Bearer" as NSString, "expires_in": NSNumber(value: 300)
    ]
    if let idToken { parameters["id_token"] = idToken as NSString }
    let token = OIDTokenResponse(request: exchange, parameters: parameters)
    return OIDAuthState(authorizationResponse: response, tokenResponse: token)
}

@MainActor private final class MemoryVault: IdentityVault {
    var data: Data?
    var failWrites = false
    func read() throws -> Data? { data }
    func write(_ value: Data) throws {
        if failWrites { throw IdentityFailure.storage }
        data = value
    }
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
