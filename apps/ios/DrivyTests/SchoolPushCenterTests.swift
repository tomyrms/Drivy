import Foundation
import Testing
import UIKit
@preconcurrency import AppAuth
@testable import Drivy

/// Révocation de l'appareil push à toute fin de session (#120/#74) : contrat de `apps/api/contracts/push-device-revocation.json`
/// et des routes de `apps/api/src/notification-preferences.ts`, sans réseau ni Trousseau réels.
/// Données synthétiques seulement : aucun jeton, secret ni position d'une personne réelle.
@MainActor
struct SchoolPushCenterTests {
    private let base = URL(string: "https://api.example.invalid")!
    /// Jeton APNs synthétique : 64 caractères hexadécimaux, la borne basse du contrat.
    private let deviceToken = String(repeating: "ab", count: 32)
    private let firstSecret = String(repeating: "A", count: 43)
    private let secondSecret = String(repeating: "B", count: 43)

    // MARK: Client : secret rendu une fois, route anonyme

    @Test func decodesTheRevocationSecretAndToleratesAnOlderAPI() async throws {
        let server = PushServer(secret: firstSecret)
        let client = notificationClient(token: "synthetic-push-access", server: server)
        #expect(try await client.register(token: deviceToken, environment: .sandbox) == firstSecret)
        // École plus ancienne : le champ manque, l'enregistrement réussit quand même.
        await server.setSecret(nil)
        #expect(try await client.register(token: deviceToken, environment: .sandbox) == nil)
        // Un secret hors du format du contrat n'est pas retenu.
        await server.setSecret(String(repeating: "!", count: 43))
        #expect(try await client.register(token: deviceToken, environment: .sandbox) == nil)
    }

    @Test func theAnonymousRevocationCarriesNeitherAuthorizationNorVersion() async throws {
        let server = PushServer()
        let client = notificationClient(token: "synthetic-stale-access", server: server)
        try await client.revokeAnonymously(token: deviceToken, secret: firstSecret)
        let call = try #require(await server.calls.last)
        #expect(call.method == "POST")
        // Même base que l'API, sans « me » : la route de l'école n'est pas dans l'espace de la personne.
        #expect(call.path == "/v1/push-devices/revoke")
        #expect(call.authorization == nil)
        let body = try #require(try JSONSerialization.jsonObject(with: Data(call.body.utf8)) as? [String: Any])
        #expect(Set(body.keys) == ["token", "revocationSecret"])
        #expect(body["token"] as? String == deviceToken && body["revocationSecret"] as? String == firstSecret)
        // Aucun jeton n'a été demandé à la session pour cette route.
        #expect(await server.calls.count == 1)
    }

    @Test func theAnonymousRevocationNeverRenewsASession() async throws {
        let server = PushServer(anonymousStatus: 401)
        let token = PushAccessToken(value: "synthetic-stale-access")
        let client = SchoolNotificationClient(baseURL: base, tokenSource: token, transport: server)
        await #expect(throws: SchoolPlanningFailure.unauthorized) {
            try await client.revokeAnonymously(token: deviceToken, secret: firstSecret)
        }
        // Un seul appel : ni lecture de jeton, ni nouvel essai après un refus.
        #expect(await server.calls.count == 1)
        #expect(token.requests == 0 && token.invalidations == 0)
    }

    @Test func refusesARevocationSecretOutsideTheContract() {
        #expect(SchoolPushRevocationSecret.valid(firstSecret))
        #expect(!SchoolPushRevocationSecret.valid(String(repeating: "A", count: 42)))
        #expect(!SchoolPushRevocationSecret.valid(String(repeating: "A", count: 44)))
        #expect(!SchoolPushRevocationSecret.valid(String(repeating: "+", count: 43)))
    }

    // MARK: Centre de notifications : secret gardé, remplacé, effacé

    @Test func keepsTheSecretWithItsDeviceTokenAndReplacesItAtEveryRegistration() async {
        let server = PushServer(secret: firstSecret)
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-push-access", server: server))

        #expect(await center.registerDevice(token: deviceToken))
        #expect(store.record == SchoolPushRevocationRecord(token: deviceToken, secret: firstSecret))

        await server.setSecret(secondSecret)
        #expect(await center.registerDevice(token: deviceToken))
        #expect(store.record == SchoolPushRevocationRecord(token: deviceToken, secret: secondSecret))
    }

    @Test func anOlderAPIWithoutSecretKeepsTheCurrentBehaviour() async {
        let server = PushServer(secret: nil)
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-push-access", server: server))
        // Jeton APNs reçu de l'appareil : l'app l'aurait en mémoire, même sans autorisation demandée dans ce test.
        center.didRegister(deviceToken: Data(repeating: 0xAB, count: 32))
        let token = String(repeating: "ab", count: 32)

        #expect(await center.registerDevice(token: token))
        // Rien à garder : aucune révocation anonyme n'est possible, comme avant #120.
        #expect(store.record == nil)
        await center.sessionEnding()
        #expect(store.record == nil)
        let calls = await server.calls
        // La révocation authentifiée reste la seule tentative ; l'école qui n'en rend pas le secret n'en reçoit aucune.
        #expect(calls.filter { $0.path == "/v1/me/push-devices/revoke" }.count == 1)
        #expect(!calls.map(\.path).contains("/v1/push-devices/revoke"))
    }

    @Test func anExplicitSignOutRevokesWithTheAccessTokenAndForgetsTheSecret() async {
        let server = PushServer(secret: firstSecret, validAccessToken: "synthetic-push-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-push-access", server: server))
        #expect(await center.registerDevice(token: deviceToken))

        await center.sessionEnding()

        let calls = await server.calls
        let authenticated = calls.filter { $0.path == "/v1/me/push-devices/revoke" }
        #expect(authenticated.count == 1)
        #expect(authenticated.first?.authorization == "Bearer synthetic-push-access")
        // Confirmée : le secret n'a plus d'usage et aucune requête anonyme n'a été nécessaire.
        #expect(store.record == nil)
        #expect(calls.allSatisfy { $0.path != "/v1/push-devices/revoke" })
    }

    @Test func aSessionEndWithoutAccessTokenRevokesWithTheSecret() async throws {
        // Jeton d'accès périmé et renouvellement impossible : l'école refuse, la session n'existe plus.
        let server = PushServer(secret: firstSecret, validAccessToken: nil)
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-stale-access", server: server))
        #expect(await center.registerDevice(token: deviceToken))

        await center.sessionEnding()

        let calls = await server.calls
        let anonymous = calls.filter { $0.path == "/v1/push-devices/revoke" }
        #expect(anonymous.count == 1)
        #expect(anonymous.first?.authorization == nil)
        let call = try #require(anonymous.first)
        let body = try #require(try JSONSerialization.jsonObject(with: Data(call.body.utf8)) as? [String: Any])
        #expect(body["token"] as? String == deviceToken)
        #expect(body["revocationSecret"] as? String == firstSecret)
        #expect(store.record == nil)
    }

    @Test func aNetworkFailureLeavesTheRevocationToDoAndItIsRetriedOnce() async {
        let server = PushServer(secret: firstSecret, validAccessToken: nil)
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-stale-access", server: server))
        #expect(await center.registerDevice(token: deviceToken))

        await server.setUnreachable(true)
        await center.sessionEnding()
        // Le secret reste : l'appareil est peut-être encore inscrit côté école, la révocation est due.
        #expect(store.record == SchoolPushRevocationRecord(token: deviceToken, secret: firstSecret))
        #expect(await anonymousCalls(server).isEmpty)

        await server.setUnreachable(false)
        // Reprise au premier plan : un essai, puis plus rien tant que le secret n'est pas revenu.
        await center.resumePendingRevocation(identityIsBusy: false)
        #expect(store.record == nil)
        #expect(await anonymousCalls(server).count == 1)
        await center.resumePendingRevocation(identityIsBusy: false)
        await center.resumePendingRevocation(identityIsBusy: false)
        #expect(await anonymousCalls(server).count == 1)
    }

    @Test func aSecretStoredAtLaunchWithoutASessionIsRevoked() async {
        let server = PushServer(secret: firstSecret, validAccessToken: nil)
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-push-access", server: server))
        // App arrêtée avec un appareil inscrit, relancée sans session : le secret désigne un appareil encore inscrit.
        try? store.save(SchoolPushRevocationRecord(token: deviceToken, secret: firstSecret))

        await center.resumePendingRevocation(identityIsBusy: false)

        #expect(store.record == nil)
        #expect(await anonymousCalls(server).count == 1)
        await center.resumePendingRevocation(identityIsBusy: false)
        #expect(await anonymousCalls(server).count == 1)
    }

    @Test func aRevocationWaitsWhileASessionIsOpenOrBeingRestored() async {
        let server = PushServer(secret: firstSecret, validAccessToken: nil)
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-push-access", server: server))
        try? store.save(SchoolPushRevocationRecord(token: deviceToken, secret: firstSecret))

        // Restauration ou connexion en cours : elle peut aboutir à une session à conserver.
        await center.resumePendingRevocation(identityIsBusy: true)
        #expect(store.record != nil)
        #expect(await anonymousCalls(server).isEmpty)

        // Session ouverte : elle se réenregistre d'elle-même, rien n'est dû.
        center.sessionStarted()
        await center.resumePendingRevocation(identityIsBusy: false)
        #expect(store.record != nil)
        #expect(await anonymousCalls(server).isEmpty)
    }

    @Test func aRestoredSessionReplacesTheSecretInsteadOfRevoking() async {
        let server = PushServer(secret: secondSecret, validAccessToken: "synthetic-push-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        center.configure(client: notificationClient(token: "synthetic-push-access", server: server))
        // Un ancien secret traîne depuis une session précédente, puis la session est retrouvée.
        try? store.save(SchoolPushRevocationRecord(token: deviceToken, secret: firstSecret))
        center.sessionStarted()

        // L'appareil se réenregistre : le secret est remplacé, rien n'est révoqué.
        #expect(await center.registerDevice(token: deviceToken))
        await center.resumePendingRevocation(identityIsBusy: false)

        #expect(store.record == SchoolPushRevocationRecord(token: deviceToken, secret: secondSecret))
        #expect(await anonymousCalls(server).isEmpty)
    }

    // MARK: Chaque fin de session d'identité, même sans jeton d'accès

    @Test func aFailedRestoreRevokesTheRegisteredDevice() async throws {
        let wiring = try await registeredCenter()
        let vault = PushIdentityVault()
        vault.failReads = true
        let session = IdentitySession(configuration: pushIdentityConfiguration, vault: vault,
                                      authorizer: PushIdentityAuthorizer(state: try pushIdentityState()))
        session.sessionEnded = { await wiring.center.sessionEnding() }

        await session.restore()

        #expect(!session.isAuthenticated)
        await expectRevokedWithoutAccessToken(wiring)
    }

    @Test func aSessionEndBeforeTheHookIsSetIsAnnouncedWhenItIsSet() async throws {
        let wiring = try await registeredCenter()
        let vault = PushIdentityVault()
        vault.failReads = true
        let session = IdentitySession(configuration: pushIdentityConfiguration, vault: vault,
                                      authorizer: PushIdentityAuthorizer(state: try pushIdentityState()))

        // Restauration du lancement échouée avant que l'app ait posé l'accroche : l'annonce est retenue, rien ne part.
        await session.restore()
        #expect(!session.isAuthenticated)
        #expect(wiring.store.record != nil)
        #expect(await anonymousCalls(wiring.server).isEmpty)

        // La pose de l'accroche annonce la fin de session retenue, une seule fois.
        session.sessionEnded = { await wiring.center.sessionEnding() }
        let revoked = await waitUntil { wiring.store.record == nil }
        #expect(revoked)
        #expect(wiring.store.record == nil)
        #expect(await anonymousCalls(wiring.server).count == 1)
    }

    @Test func aRefusedRefreshRevokesTheRegisteredDevice() async throws {
        let wiring = try await registeredCenter()
        let vault = PushIdentityVault()
        let authorizer = PushIdentityAuthorizer(state: try pushIdentityState())
        let session = IdentitySession(configuration: pushIdentityConfiguration, vault: vault, authorizer: authorizer)
        session.sessionEnded = { await wiring.center.sessionEnding() }
        await session.signIn(presenting: UIViewController())
        #expect(session.isAuthenticated)
        authorizer.refusal = NSError(domain: OIDOAuthTokenErrorDomain, code: 0)

        await #expect(throws: IdentityFailure.self) { try await session.accessToken() }

        #expect(!session.isAuthenticated)
        await expectRevokedWithoutAccessToken(wiring)
    }

    @Test func aKeychainWriteFailureRevokesTheRegisteredDevice() async throws {
        let wiring = try await registeredCenter()
        let vault = PushIdentityVault()
        let authorizer = PushIdentityAuthorizer(state: try pushIdentityState())
        let session = IdentitySession(configuration: pushIdentityConfiguration, vault: vault, authorizer: authorizer)
        session.sessionEnded = { await wiring.center.sessionEnding() }
        await session.signIn(presenting: UIViewController())
        #expect(session.isAuthenticated)
        vault.failWrites = true

        await #expect(throws: IdentityFailure.self) { try await session.accessToken() }

        #expect(!session.isAuthenticated)
        await expectRevokedWithoutAccessToken(wiring)
    }

    @Test func anExplicitSignOutIsAnnouncedByItsGestureAndNeverTwice() async throws {
        let wiring = try await registeredCenter()
        let session = IdentitySession(configuration: pushIdentityConfiguration, vault: PushIdentityVault(),
                                      authorizer: PushIdentityAuthorizer(state: try pushIdentityState()))
        var announcements = 0
        session.sessionEnded = { announcements += 1; await wiring.center.sessionEnding() }
        await session.signIn(presenting: UIViewController())

        // Les deux gestes de déconnexion appellent `sessionEnding()` avant `signOut()` : l'identité n'annonce rien.
        await session.signOut()

        #expect(!session.isAuthenticated)
        #expect(announcements == 0)
        #expect(await anonymousCalls(wiring.server).isEmpty)
        #expect(wiring.store.record != nil)
    }

    // MARK: Outils

    private func notificationClient(token: String?, server: PushServer) -> SchoolNotificationClient {
        SchoolNotificationClient(baseURL: base, tokenSource: PushAccessToken(value: token), transport: server)
    }

    /// Requêtes reçues par la route anonyme de révocation.
    private func anonymousCalls(_ server: PushServer) async -> [PushServer.Call] {
        let calls = await server.calls
        return calls.filter { $0.path == "/v1/push-devices/revoke" }
    }

    /// Attend le travail lancé dans une tâche par l'app (annonce retenue, pose de l'accroche) : au plus une seconde.
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    /// Centre avec un appareil déjà inscrit, porteur d'un secret : ce qu'une session laisse derrière elle.
    private func registeredCenter() async throws -> (center: SchoolPushCenter, server: PushServer, store: SchoolPushRevocationMemoryStore) {
        let server = PushServer(secret: firstSecret)
        let store = SchoolPushRevocationMemoryStore()
        let center = SchoolPushCenter(revocations: store)
        // L'école ne reconnaît plus la session (401 sans renouvellement possible) : seul le secret peut révoquer.
        center.configure(client: notificationClient(token: "synthetic-push-access", server: server))
        #expect(await center.registerDevice(token: deviceToken))
        #expect(store.record != nil)
        return (center, server, store)
    }

    private func expectRevokedWithoutAccessToken(_ wiring: (center: SchoolPushCenter, server: PushServer, store: SchoolPushRevocationMemoryStore)) async {
        let calls = await wiring.server.calls
        let anonymous = calls.filter { $0.path == "/v1/push-devices/revoke" }
        #expect(anonymous.count == 1)
        #expect(anonymous.first?.authorization == nil)
        #expect(anonymous.first?.method == "POST")
        // Révoqué et confirmé : plus aucun secret ne traîne sur l'appareil.
        #expect(wiring.store.record == nil)
    }
}

/// École simulée : enregistrement, route authentifiée et route anonyme, avec pannes et refus choisis par le test.
private actor PushServer: SchoolHTTPTransport {
    struct Call: Sendable, Equatable {
        let method: String
        let path: String
        let authorization: String?
        let body: String
    }

    private(set) var calls: [Call] = []
    private var secret: String?
    private var validAccessToken: String?
    private var unreachable = false
    private let anonymousStatus: Int

    init(secret: String? = String(repeating: "A", count: 43), validAccessToken: String? = nil,
         anonymousStatus: Int = 200, unreachable: Bool = false) {
        self.secret = secret; self.validAccessToken = validAccessToken
        self.anonymousStatus = anonymousStatus; self.unreachable = unreachable
    }

    func setSecret(_ value: String?) { secret = value }
    func setValidAccessToken(_ value: String?) { validAccessToken = value }
    func setUnreachable(_ value: Bool) { unreachable = value }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url ?? URL(string: "https://api.example.invalid")!
        calls.append(Call(method: request.httpMethod ?? "", path: url.path,
                          authorization: request.value(forHTTPHeaderField: "Authorization"),
                          body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""))
        if unreachable { throw URLError(.notConnectedToInternet) }
        switch (request.httpMethod, url.path) {
        case ("PUT", "/v1/me/push-devices"):
            let data = secret.map { #"{"registered":true,"revocationSecret":"\#($0)"}"# } ?? #"{"registered":true}"#
            return reply(envelope(data), status: 200, url: url)
        case ("POST", "/v1/me/push-devices/revoke"):
            if let validAccessToken, request.value(forHTTPHeaderField: "Authorization") == "Bearer \(validAccessToken)" {
                return reply(envelope(#"{"revoked":true}"#), status: 200, url: url)
            }
            return reply(Data(#"{"code":"UNAUTHORIZED","title":"Session expirée."}"#.utf8), status: 401, url: url,
                         contentType: "application/problem+json")
        case ("POST", "/v1/push-devices/revoke"):
            if anonymousStatus == 200 { return reply(envelope(#"{"revoked":true}"#), status: 200, url: url) }
            return reply(Data(#"{"code":"PUSH_REVOCATION_ATTEMPTS","title":"Trop de tentatives."}"#.utf8), status: anonymousStatus,
                         url: url, contentType: "application/problem+json")
        default:
            return reply(Data(), status: 404, url: url, contentType: "application/problem+json")
        }
    }

    private func envelope(_ data: String) -> Data {
        Data(#"{"data":\#(data),"requestId":"11111111-1111-4111-8111-111111111111","serverTime":"2026-11-04T10:00:00Z"}"#.utf8)
    }

    private func reply(_ data: Data, status: Int, url: URL,
                       contentType: String = "application/json; charset=utf-8") -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: data, status: status, url: url, contentType: contentType)
    }
}

/// Session d'accès simulée : jeton courant, ou aucune session (`nil`), comme après une fin de session.
@MainActor
private final class PushAccessToken: AccessTokenSource {
    var value: String?
    private(set) var requests = 0
    private(set) var invalidations = 0

    init(value: String?) { self.value = value }

    func accessToken() async throws -> String {
        requests += 1
        guard let value else { throw IdentityFailure.reauthentication }
        return value
    }
    /// Aucun jeton ne peut être renouvelé : l'école répond 401 et la session est perdue.
    func invalidateAccessToken(_ token: String) async -> Bool {
        invalidations += 1
        return false
    }
}

@MainActor
private final class PushIdentityVault: IdentityVault {
    var data: Data?
    var failReads = false
    var failWrites = false

    func read() throws -> Data? {
        if failReads { throw IdentityFailure.storage }
        return data
    }
    func write(_ value: Data) throws {
        if failWrites { throw IdentityFailure.storage }
        data = value
    }
    func clear() throws { data = nil }
}

/// Fournisseur d'identité simulé : `refusal` reproduit un renouvellement refusé, qui rend l'état non autorisé
/// comme `OIDAuthState.performAction` d'AppAuth (exemple Swift du paquet, `AuthManager`).
@MainActor
private final class PushIdentityAuthorizer: IdentityAuthorizing {
    let state: OIDAuthState
    var refusal: NSError?

    init(state: OIDAuthState) { self.state = state }

    func authorize(configuration: AppConfiguration, presenting: UIViewController) async throws -> OIDAuthState { state }

    func freshToken(for state: OIDAuthState) async throws -> String {
        if let refusal {
            state.update(withAuthorizationError: refusal)
            throw IdentityFailure.reauthentication
        }
        return "synthetic-refreshed-access"
    }

    func cancel() {}
    func handleRedirect(_ url: URL) -> Bool { false }
}

private let pushIdentityConfiguration = AppConfiguration(apiBaseURL: URL(string: "https://api.example.invalid")!,
    issuer: URL(string: "https://identity.example.invalid/realms/drivy")!, clientID: "drivy-apple",
    redirectURL: AppConfiguration.callback)

@MainActor
private func pushIdentityState() throws -> OIDAuthState {
    let service = OIDServiceConfiguration(
        authorizationEndpoint: URL(string: "https://identity.example.invalid/realms/drivy/authorize")!,
        tokenEndpoint: URL(string: "https://identity.example.invalid/realms/drivy/token")!,
        issuer: pushIdentityConfiguration.issuer)
    let request = OIDCPolicy.request(service: service, configuration: pushIdentityConfiguration)
    let response = OIDAuthorizationResponse(request: request,
        parameters: ["code": "synthetic-test-code" as NSString, "state": (request.state ?? "") as NSString])
    let exchange = try #require(response.tokenExchangeRequest())
    let token = OIDTokenResponse(request: exchange, parameters: [
        "access_token": "synthetic-test-access" as NSString,
        "refresh_token": "synthetic-test-refresh" as NSString,
        "token_type": "Bearer" as NSString, "expires_in": NSNumber(value: 3600)])
    return OIDAuthState(authorizationResponse: response, tokenResponse: token)
}
