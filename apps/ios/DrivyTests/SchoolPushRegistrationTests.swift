import Foundation
import Testing
import UIKit
@testable import Drivy

/// Enregistrement APNs de l'appareil (#441) : PUT sérialisés, secret de révocation conservé durablement avant tout
/// « enregistré », et révocation qui ne retire que le record qu'elle visait. Transport, Trousseau et autorisation système
/// sont injectés : aucun réseau, aucun Trousseau, aucune demande APNs réelle. Données synthétiques seulement.
@MainActor
struct SchoolPushRegistrationTests {
    private let base = URL(string: "https://api.example.invalid")!
    private let tokenA = String(repeating: "ab", count: 32)
    private let tokenB = String(repeating: "cd", count: 32)
    private var dataA: Data { Data(repeating: 0xAB, count: 32) }
    private var dataB: Data { Data(repeating: 0xCD, count: 32) }

    private func makeCenter(_ server: RotatingPushServer, store: SchoolPushRevocationMemoryStore = SchoolPushRevocationMemoryStore(),
                            accessToken: String? = "synthetic-access") -> SchoolPushCenter {
        let center = SchoolPushCenter(revocations: store, systemStatus: { .authorized }, registersForRemote: {})
        center.configure(client: SchoolNotificationClient(baseURL: base, tokenSource: RotatingAccessToken(value: accessToken),
                                                          transport: server))
        return center
    }

    /// Ouvre une session autorisée, sans jeton APNs ni requête : la suite pilote elle-même l'arrivée du jeton.
    private func openSession(_ center: SchoolPushCenter) async {
        center.sessionStarted()
        await center.refreshAuthorization()
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return await condition()
    }

    // MARK: Callbacks rapprochés

    @Test func closeCallbacksCoalesceIntoASingleSerializedPut() async {
        let server = RotatingPushServer(validAccessToken: "synthetic-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = makeCenter(server, store: store)
        await openSession(center)
        await server.hold("/v1/me/push-devices")

        center.didRegister(deviceToken: dataA)                  // retour APNs
        let extra = [Task { await center.upload() }, Task { await center.upload() }, Task { await center.upload() }]
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })
        await server.releaseOne("/v1/me/push-devices")
        for task in extra { await task.value }
        #expect(await eventually { center.registeredToken == tokenA })

        // Un seul PUT : les autres déclenchements ont trouvé le jeton déjà enregistré dans leur tour.
        let sentPuts = await server.puts, maxParallel = await server.maxConcurrentPuts
        #expect(sentPuts == 1 && maxParallel == 1)
        let secret = await server.currentSecret
        #expect(secret != nil && store.record == SchoolPushRevocationRecord(token: tokenA, secret: secret ?? ""))
    }

    @Test func overlappingRegistrationsNeverRunTogetherAndTheKeptSecretIsTheLastOne() async {
        let server = RotatingPushServer(validAccessToken: "synthetic-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = makeCenter(server, store: store)
        await server.hold("/v1/me/push-devices")

        let first = Task { await center.registerDevice(token: tokenA) }
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })
        let second = Task { await center.registerDevice(token: tokenA) }
        // Le second attend la réponse du premier : un seul PUT en vol.
        for _ in 0..<50 { await Task.yield() }
        #expect(await server.puts == 1)

        await server.releaseOne("/v1/me/push-devices")
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })
        #expect(await server.puts == 2)
        await server.releaseOne("/v1/me/push-devices")
        let firstDone = await first.value, secondDone = await second.value
        #expect(firstDone && secondDone)

        #expect(await server.maxConcurrentPuts == 1)
        // Preuve centrale : le secret conservé est celui que l'école tient pour courant (le dernier enregistrement).
        let current = await server.currentSecret
        #expect(current != nil && store.record?.secret == current && store.record?.token == tokenA)
    }

    // MARK: Réponse tardive, changement de session ou de jeton

    @Test func aLateResponseAfterTheSessionEndedDoesNotMarkTheTokenRegisteredAndTheRevocationResumes() async {
        let server = RotatingPushServer(validAccessToken: "synthetic-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = makeCenter(server, store: store)
        await openSession(center)
        await server.hold("/v1/me/push-devices")
        center.didRegister(deviceToken: dataA)
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })

        await center.sessionEnding()
        await server.releaseOne("/v1/me/push-devices")
        #expect(await eventually { store.record != nil })

        // La réponse est arrivée hors session : le secret est gardé, mais l'appareil n'est pas « enregistré ».
        #expect(center.registeredToken == nil)
        let keptSecret = await server.currentSecret
        #expect(store.record?.secret == keptSecret)

        // La reprise (relance de l'app ou retour au premier plan) révoque ce qui reste inscrit.
        await center.resumePendingRevocation(identityIsBusy: false)
        // Deux révocations authentifiées : celle de la fin de session, puis la reprise qui efface le record resté.
        let revocations = await server.authenticatedRevocations
        #expect(store.record == nil && revocations == 2)
    }

    @Test func aNewSessionOpenedDuringAPutRegistersAgainInsteadOfTrustingTheOldResponse() async {
        let server = RotatingPushServer(validAccessToken: "synthetic-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = makeCenter(server, store: store)
        await openSession(center)
        await server.hold("/v1/me/push-devices")
        center.didRegister(deviceToken: dataA)
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })

        await center.sessionEnding()
        await openSession(center)                               // autre session, même appareil
        await server.releaseOne("/v1/me/push-devices")
        // La réponse de l'ancienne génération ne vaut pas pour la nouvelle : un second PUT est fait.
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })
        await server.releaseOne("/v1/me/push-devices")
        #expect(await eventually { center.registeredToken == tokenA })

        let sentPuts = await server.puts, maxParallel = await server.maxConcurrentPuts
        let keptSecret = await server.currentSecret
        #expect(sentPuts == 2 && maxParallel == 1)
        #expect(store.record?.secret == keptSecret)
    }

    @Test func aTokenChangeDuringAPutEndsOnTheNewTokenWithItsOwnSecret() async {
        let server = RotatingPushServer(validAccessToken: "synthetic-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = makeCenter(server, store: store)
        await openSession(center)
        await server.hold("/v1/me/push-devices")
        center.didRegister(deviceToken: dataA)
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })

        center.didRegister(deviceToken: dataB)                  // APNs rend un autre jeton pendant le PUT
        await server.releaseOne("/v1/me/push-devices")
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })
        await server.releaseOne("/v1/me/push-devices")
        #expect(await eventually { center.registeredToken == tokenB })

        let sentPuts = await server.puts, maxParallel = await server.maxConcurrentPuts
        #expect(sentPuts == 2 && maxParallel == 1)
        let secret = await server.currentSecret
        #expect(secret != nil && store.record == SchoolPushRevocationRecord(token: tokenB, secret: secret ?? ""))
    }

    // MARK: Panne du Trousseau et reprise

    @Test func aKeychainThatCannotStoreLeavesTheDeviceUnregisteredUntilItWorksAgain() async {
        let server = RotatingPushServer(validAccessToken: "synthetic-access")
        let store = SchoolPushRevocationMemoryStore()
        store.refusesToStore = true
        let center = makeCenter(server, store: store)
        await openSession(center)
        await server.hold("/v1/me/push-devices")

        center.didRegister(deviceToken: dataA)
        // Barrière : le premier PUT est retenu en vol. Les envois sont sérialisés, donc aucun autre ne peut le précéder
        // (la tâche de `sessionStarted` et celle de `didRegister` passent l'une après l'autre, jamais ensemble).
        #expect(await eventually { await server.waiting("/v1/me/push-devices") == 1 })
        #expect(await server.puts == 1)
        #expect(center.registeredToken == nil && store.record == nil)

        // Le Trousseau refuse : réponse reçue mais secret perdu, donc jamais « enregistré ». Les envois en file et l'essai
        // explicite refont chacun leur PUT ; `upload()` passe après toute la file, tout est donc terminé à son retour.
        await server.unhold("/v1/me/push-devices")
        await center.upload()
        #expect(center.registeredToken == nil && store.record == nil)
        #expect(await server.puts >= 2)
        #expect(await server.maxConcurrentPuts == 1)

        store.refusesToStore = false
        await center.upload()
        #expect(center.registeredToken == tokenA)
        let keptSecret = await server.currentSecret
        #expect(keptSecret != nil && store.record == SchoolPushRevocationRecord(token: tokenA, secret: keptSecret ?? ""))
        let puts = await server.puts
        await center.upload()                                   // enregistré : plus rien à envoyer
        #expect(await server.puts == puts)
    }

    // MARK: Révocation

    @Test func aRecordRenewedWhileTheRevocationWaitsIsKept() async {
        let server = RotatingPushServer(validAccessToken: "synthetic-access")
        let store = SchoolPushRevocationMemoryStore()
        let center = makeCenter(server, store: store)
        #expect(await center.registerDevice(token: tokenA))
        let old = store.record
        await server.hold("/v1/me/push-devices/revoke")

        let ending = Task { await center.sessionEnding() }
        #expect(await eventually { await server.waiting("/v1/me/push-devices/revoke") == 1 })
        // Un enregistrement renouvelé pendant l'attente (même jeton, autre secret).
        let renewed = SchoolPushRevocationRecord(token: tokenA, secret: String(repeating: "Z", count: 43))
        try? store.save(renewed)
        await server.releaseOne("/v1/me/push-devices/revoke")
        await ending.value

        #expect(old != renewed && store.record == renewed)
    }

    @Test func anExpiredSessionStillRevokesAnonymouslyWithTheLatestSecret() async {
        let server = RotatingPushServer(validAccessToken: nil)       // jeton d'accès périmé : 401 authentifié
        let store = SchoolPushRevocationMemoryStore()
        let center = makeCenter(server, store: store, accessToken: "synthetic-stale")
        #expect(await center.registerDevice(token: tokenA))
        let first = store.record?.secret
        #expect(await center.registerDevice(token: tokenA))          // l'école a fait tourner le secret
        #expect(store.record?.secret != first)

        await center.sessionEnding()

        // La route anonyme répond 200 même à un secret périmé : seul l'état du serveur simulé prouve l'effet.
        #expect(await server.revoked)
        let attempts = await server.anonymousAttempts
        #expect(attempts == 1 && store.record == nil)
    }

    @Test func aStaleSecretWouldNotRevokeSoTheTestsProveTheOracleIsReal() async {
        let server = RotatingPushServer(validAccessToken: nil)
        let client = SchoolNotificationClient(baseURL: base, tokenSource: RotatingAccessToken(value: "synthetic-access"),
                                              transport: server)
        let first = try? await client.register(token: tokenA, environment: .sandbox)
        _ = try? await client.register(token: tokenA, environment: .sandbox)
        try? await client.revokeAnonymously(token: tokenA, secret: first ?? "")
        let attempts = await server.anonymousAttempts, revoked = await server.revoked
        #expect(attempts == 1 && !revoked)
    }
}

/// École simulée dont le secret de révocation tourne à chaque PUT : la révocation anonyme n'a d'effet que si le secret
/// reçu est le courant, mais la réponse reste un 200 générique, comme le contrat.
private actor RotatingPushServer: SchoolHTTPTransport {
    private(set) var puts = 0
    private(set) var maxConcurrentPuts = 0
    private(set) var currentSecret: String?
    private(set) var revoked = false
    private(set) var anonymousAttempts = 0
    private(set) var authenticatedRevocations = 0
    private var concurrent = 0
    private let validAccessToken: String?
    private var held: Set<String> = []
    private var waiters: [(path: String, continuation: CheckedContinuation<Void, Never>)] = []

    init(validAccessToken: String?) { self.validAccessToken = validAccessToken }

    func hold(_ path: String) { held.insert(path) }
    func waiting(_ path: String) -> Int { waiters.filter { $0.path == path }.count }
    /// Lève la retenue et libère toutes les requêtes en attente ; les suivantes passent sans attendre.
    func unhold(_ path: String) {
        held.remove(path)
        let released = waiters.filter { $0.path == path }
        waiters.removeAll { $0.path == path }
        for waiter in released { waiter.continuation.resume() }
    }
    /// Laisse passer une seule requête retenue ; la retenue reste active pour les suivantes.
    func releaseOne(_ path: String) {
        guard let index = waiters.firstIndex(where: { $0.path == path }) else { return }
        waiters.remove(at: index).continuation.resume()
    }

    private func suspendIfHeld(_ path: String) async {
        guard held.contains(path) else { return }
        await withCheckedContinuation { waiters.append((path, $0)) }
    }

    private func secret(_ n: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        return String(repeating: letters[(n - 1) % letters.count], count: 43)
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let url = request.url ?? URL(string: "https://api.example.invalid")!
        switch (request.httpMethod, url.path) {
        case ("PUT", "/v1/me/push-devices"):
            puts += 1; concurrent += 1; maxConcurrentPuts = max(maxConcurrentPuts, concurrent)
            let issued = secret(puts)
            currentSecret = issued                                   // validé à l'arrivée, répondu après la retenue
            await suspendIfHeld(url.path)
            concurrent -= 1
            return reply(envelope(#"{"registered":true,"revocationSecret":"\#(issued)"}"#), url: url)
        case ("POST", "/v1/me/push-devices/revoke"):
            await suspendIfHeld(url.path)
            if let validAccessToken, request.value(forHTTPHeaderField: "Authorization") == "Bearer \(validAccessToken)" {
                authenticatedRevocations += 1; revoked = true
                return reply(envelope(#"{"revoked":true}"#), url: url)
            }
            return reply(Data(#"{"code":"UNAUTHORIZED","title":"Session expirée."}"#.utf8), url: url, status: 401,
                         contentType: "application/problem+json")
        case ("POST", "/v1/push-devices/revoke"):
            anonymousAttempts += 1
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if body?["revocationSecret"] as? String == currentSecret { revoked = true }
            return reply(envelope(#"{"revoked":true}"#), url: url)
        default:
            return reply(Data(), url: url, status: 404, contentType: "application/problem+json")
        }
    }

    private func envelope(_ data: String) -> Data {
        Data(#"{"data":\#(data),"requestId":"11111111-1111-4111-8111-111111111111","serverTime":"2026-11-10T10:00:00Z"}"#.utf8)
    }

    private func reply(_ data: Data, url: URL, status: Int = 200,
                       contentType: String = "application/json; charset=utf-8") -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: data, status: status, url: url, contentType: contentType)
    }
}

@MainActor
private final class RotatingAccessToken: AccessTokenSource {
    let value: String?
    init(value: String?) { self.value = value }
    func accessToken() async throws -> String {
        guard let value else { throw IdentityFailure.reauthentication }
        return value
    }
    func invalidateAccessToken(_ token: String) async -> Bool { false }
}
