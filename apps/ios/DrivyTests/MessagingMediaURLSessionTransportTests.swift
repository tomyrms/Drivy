import XCTest
@testable import Drivy

/// Bornes du vrai wire média (#97, T2b2) : plafond déclaré, flux non déclaré, arrêt de la
/// tâche sur sortie prématurée, refus de redirection, configuration durcie.
///
/// Ces tests utilisent un `URLProtocol` local : aucun réseau réel n'est joint. Trois formes :
/// une réponse cohérente livrée d'un bloc, une réponse livrée d'un bloc avec un corps plus
/// court que son `Content-Length`, et un flux qui **reste ouvert** après ses en-têtes et son
/// prélude — seule l'annulation de la tâche provoque alors `stopLoading`, que le test observe.
///
/// Aucune attente n'est structurée autour d'une tâche non coopérative : chaque attente a une
/// échéance et rend toujours la main. Un flux retenu est libéré explicitement (`abortAll`) en
/// fin de test — ce nettoyage n'est **pas** une preuve d'annulation : seul l'état observé
/// avant lui fait foi.
///
/// Limite explicite : tant qu'un runner Apple ne les a pas exécutés, ils restent **préparés**.
/// Rien ici ne prouve l'arrêt natif de la consommation réseau sous Windows, et `stopLoading`
/// n'est pas une preuve de fermeture de socket.
final class MessagingMediaURLSessionTransportTests: XCTestCase {
    override func tearDown() {
        MediaStreamRegistry.shared.abortAll()
        MediaStreamRegistry.shared.reset()
        MediaSilentRegistry.shared.failAll()
        MediaSilentRegistry.shared.reset()
        MediaStubRegistry.shared.reset()
        super.tearDown()
    }

    private func makeWire() -> MessagingMediaURLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaStubURLProtocol.self]
        return MessagingMediaURLSessionTransport(configuration: configuration)
    }

    private func makeStreamingWire() -> MessagingMediaURLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaStreamURLProtocol.self]
        return MessagingMediaURLSessionTransport(configuration: configuration)
    }

    /// Wire branché sur un stub qui n'envoie **aucun** en-tête : l'attente d'ouverture de
    /// `bytes(for:)` reste suspendue jusqu'à l'abandon.
    private func makeSilentWire() -> MessagingMediaURLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaSilentURLProtocol.self]
        return MessagingMediaURLSessionTransport(configuration: configuration)
    }

    private func request(_ path: String = "/v1/schools/x") -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.invalid\(path)")!)
    }

    /// Attente conditionnelle bornée : jamais un délai fixe comme preuve, jamais d'attente
    /// sur une tâche qui pourrait ne pas coopérer.
    private func waitUntil(timeout: TimeInterval, _ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// Issue d'un appel lancé dans une tâche non structurée, observée par drapeau : l'échéance
    /// rend la main même si l'appel reste suspendu.
    private func waitForOutcome(_ box: MediaOutcomeBox, timeout: TimeInterval = 3) async -> MediaOutcome? {
        _ = await waitUntil(timeout: timeout) { box.current != nil }
        return box.current
    }

    /// Lance `send` dans une tâche non structurée et consigne son issue réelle.
    /// `rawCancel` signale une `URLError(.cancelled)` brute, c'est-à-dire une frontière
    /// **non** normalisée par le wire ; `transport` conserve le code exact de l'erreur.
    private func startSend(_ wire: MessagingMediaURLSessionTransport, _ request: URLRequest,
                           ceiling: MessagingMediaResponseCeiling) -> (Task<Void, Never>, MediaOutcomeBox) {
        let box = MediaOutcomeBox()
        let call = Task {
            do {
                _ = try await wire.send(request, ceiling: ceiling)
                box.set(.returned)
            } catch let failure as MessagingMediaTransportFailure {
                box.set(.failure(failure))
            } catch is CancellationError {
                box.set(.cancelled)
            } catch let error as URLError where error.code == .cancelled {
                box.set(.rawCancel)
            } catch let error as URLError {
                box.set(.transport(error.code.rawValue))
            } catch {
                box.set(.other)
            }
        }
        return (call, box)
    }

    /// Libération d'un flux retenu : annulation de l'appel, puis, **seulement** si l'issue
    /// n'est toujours pas consignée, fin forcée du chargement par le `URLProtocol` contrôlé.
    /// Ce n'est jamais une preuve d'annulation : l'état lu avant cet appel fait foi.
    private func releaseStream(_ call: Task<Void, Never>, _ outcome: MediaOutcomeBox) async {
        call.cancel()
        let resolved = await waitUntil(timeout: 1) { outcome.current != nil }
        if !resolved { MediaStreamRegistry.shared.abortAll() }
    }

    /// Même libération pour le stub qui n'envoie aucun en-tête.
    private func releaseSilent(_ call: Task<Void, Never>, _ outcome: MediaOutcomeBox) async {
        call.cancel()
        let resolved = await waitUntil(timeout: 1) { outcome.current != nil }
        if !resolved { MediaSilentRegistry.shared.failAll() }
    }

    // MARK: Plafonds dérivés des constantes

    func testDeclaredLengthAtTheMediaCeilingIsAcceptedWithACoherentBody() async throws {
        // Borne ACCEPTÉE et réponse cohérente : le corps a exactement la taille annoncée.
        // Le coût (~4 Mio lus octet par octet) est assumé pour prouver la borne.
        let ceiling = MessagingMediaResponseCeiling.mediaLimit
        let body = Data(repeating: 0x41, count: ceiling)
        MediaStubRegistry.shared.install { _ in
            (200, ["Content-Length": String(ceiling), "Content-Type": "application/octet-stream"], body)
        }
        let accepted = try await makeWire().send(request(), ceiling: .media)
        XCTAssertEqual(accepted.declaredByteSize, ceiling)
        XCTAssertEqual(accepted.body.count, ceiling)
        XCTAssertEqual(accepted.status, 200)
    }

    func testStreamCeilingIsWiderThanTheBusinessMediaLimit() async throws {
        // Deux bornes distinctes : la limite métier (4 Mio) et le plafond de flux (4 Mio + 8 Kio).
        // Une taille au-dessus de la limite métier reste donc lisible par le wire.
        XCTAssertEqual(MessagingHTTPMediaTransport.maximumByteSize, AESCTRMediaCryptography.maximumByteSize)
        let aboveBusiness = MessagingHTTPMediaTransport.maximumByteSize + 1
        XCTAssertLessThan(aboveBusiness, MessagingMediaResponseCeiling.mediaLimit)

        let body = Data(repeating: 0x42, count: aboveBusiness)
        MediaStubRegistry.shared.install { _ in
            (200, ["Content-Length": String(aboveBusiness)], body)
        }
        let response = try await makeWire().send(request(), ceiling: .media)
        XCTAssertEqual(response.declaredByteSize, aboveBusiness)
        XCTAssertEqual(response.body.count, aboveBusiness)
    }

    func testEnvelopeCeilingIsStricterThanTheMediaCeiling() async throws {
        let limit = MessagingMediaResponseCeiling.envelopeLimit
        XCTAssertLessThan(limit, MessagingMediaResponseCeiling.mediaLimit)

        MediaStubRegistry.shared.install { _ in (200, [:], Data(repeating: 0x41, count: 900)) }
        let small = try await makeWire().send(request(), ceiling: .envelope)
        XCTAssertEqual(small.body.count, 900)

        // Borne acceptée exactement, corps de la même taille, puis première valeur refusée.
        MediaStubRegistry.shared.install { _ in (200, [:], Data(repeating: 0x41, count: limit)) }
        let atLimit = try await makeWire().send(request(), ceiling: .envelope)
        XCTAssertEqual(atLimit.body.count, limit)

        MediaStubRegistry.shared.install { _ in (200, [:], Data(repeating: 0x41, count: limit + 1)) }
        do {
            _ = try await makeWire().send(request(), ceiling: .envelope)
            XCTFail("Le plafond de l'enveloppe n'est pas appliqué")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .tooLarge)
        }
    }

    func testStreamWithoutADeclaredLengthIsAlsoBounded() async throws {
        let beyond = Data(repeating: 0x41, count: MessagingMediaResponseCeiling.mediaLimit + 1)
        MediaStubRegistry.shared.install { _ in (200, [:], beyond) }
        do {
            _ = try await makeWire().send(request(), ceiling: .media)
            XCTFail("Un flux non déclaré au-delà du plafond doit être refusé pendant la lecture")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .tooLarge)
        }
    }

    func testHeaderAndBodyOfTheResponseAreReadWithoutSerialisingEveryHeader() async throws {
        MediaStubRegistry.shared.install { _ in
            (200, ["Content-Length": "3", "Content-Type": "application/octet-stream; charset=binary",
                   "Cache-Control": "private, no-store",
                   "X-Drivy-School-Id": "11111111-1111-1111-1111-111111111111",
                   "X-Drivy-Access-Epoch": "7",
                   "X-Drivy-Media-Sha256": String(repeating: "a", count: 64),
                   "Set-Cookie": "synthetic=1"], Data([1, 2, 3]))
        }
        let response = try await makeWire().send(request(), ceiling: .media)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data([1, 2, 3]))
        XCTAssertEqual(response.declaredByteSize, 3)
        XCTAssertEqual(response.schoolID, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(response.accessEpoch, "7")
        XCTAssertEqual(response.sha256, String(repeating: "a", count: 64))
        XCTAssertEqual(response.contentType, "application/octet-stream; charset=binary")
    }

    // MARK: Flux laissé ouvert : la tâche doit être annulée

    func testRefusedHeaderStopsTheOpenStream() async throws {
        // Refus AVANT consommation : petit prélude seulement, flux maintenu ouvert.
        let ceiling = MessagingMediaResponseCeiling.mediaLimit
        MediaStreamRegistry.shared.install(.init(status: 200,
            headers: ["Content-Length": String(ceiling + 1), "Content-Type": "application/octet-stream"],
            prelude: Data(repeating: 0x41, count: 64), finishes: false))
        let (call, outcome) = startSend(makeStreamingWire(), request(), ceiling: .media)

        let refused = await waitForOutcome(outcome)
        XCTAssertEqual(refused, MediaOutcome.failure(.tooLarge))
        let stopped = await waitUntil(timeout: 3) { MediaStreamRegistry.shared.stopCount() >= 1 }
        XCTAssertTrue(stopped, "La tâche du flux doit être annulée sur en-tête refusé")
        await releaseStream(call, outcome)
    }

    func testOverflowDuringReadingStopsTheOpenStream() async throws {
        let limit = MessagingMediaResponseCeiling.envelopeLimit
        MediaStreamRegistry.shared.install(.init(status: 200, headers: [:],
            prelude: Data(repeating: 0x41, count: limit + 1), finishes: false))
        let (call, outcome) = startSend(makeStreamingWire(), request(), ceiling: .envelope)

        let overflowed = await waitForOutcome(outcome)
        XCTAssertEqual(overflowed, MediaOutcome.failure(.tooLarge))
        let stopped = await waitUntil(timeout: 3) { MediaStreamRegistry.shared.stopCount() >= 1 }
        XCTAssertTrue(stopped, "La tâche du flux doit être annulée au dépassement")
        await releaseStream(call, outcome)
    }

    func testCancellingTheCallerStopsTheOpenStream() async throws {
        // Aucun nouvel octet après le prélude : l'arrêt ne peut venir que de l'annulation.
        MediaStreamRegistry.shared.install(.init(status: 200, headers: [:],
            prelude: Data(repeating: 0x41, count: 1_024), finishes: false))
        let wire = makeStreamingWire()
        let (call, outcome) = startSend(wire, request(), ceiling: .media)
        // Le prélude a été **remis à Foundation** (`didLoad` du URLProtocol). Cela ne prouve pas
        // que la routine du wire a repris `bytes(for:)` ni qu'elle a consommé un premier octet :
        // ce cas est donc « annulation après prélude remis », pas « annulation pendant la lecture ».
        // La frontière d'ouverture, elle, est couverte de façon déterministe par le stub muet.
        let delivered = await waitUntil(timeout: 3) { MediaStreamRegistry.shared.deliveredCount() >= 1_024 }
        XCTAssertTrue(delivered, "Le prélude doit être remis avant l'annulation")

        call.cancel()

        // L'état observé AVANT nettoyage fait foi.
        let verdict = await waitForOutcome(outcome)
        XCTAssertEqual(verdict, MediaOutcome.cancelled,
                       "Une annulation appelante doit rester une CancellationError")
        let stopped = await waitUntil(timeout: 3) { MediaStreamRegistry.shared.stopCount() >= 1 }
        XCTAssertTrue(stopped, "La tâche du flux doit être annulée à l'annulation appelante")
        await releaseStream(call, outcome)
    }

    // MARK: Annulation pendant l'ouverture, avant tout en-tête

    func testCancellingBeforeHeadersIsACancellation() async throws {
        // Flux muet : aucun en-tête n'est délivré, donc `bytes(for:)` est encore suspendu.
        // C'est la frontière qui laissait sortir l'erreur brute de Foundation en qualification.
        MediaSilentRegistry.shared.install()
        let (call, outcome) = startSend(makeSilentWire(), request(), ceiling: .media)
        let ready = await waitUntil(timeout: 3) { MediaSilentRegistry.shared.readyCount() >= 1 }
        XCTAssertTrue(ready, "Le chargement doit être prêt avant l'annulation")

        call.cancel()

        let verdict = await waitForOutcome(outcome)
        XCTAssertEqual(verdict, MediaOutcome.cancelled,
                       "Une annulation pendant l'ouverture reste une CancellationError")
        let stopped = await waitUntil(timeout: 3) { MediaSilentRegistry.shared.stopCount() >= 1 }
        XCTAssertTrue(stopped, "La tâche d'ouverture doit être arrêtée")
        await releaseSilent(call, outcome)
    }

    func testTransportErrorBeforeHeadersIsPreserved() async throws {
        // Témoin non annulé : une panne d'ouverture ne doit pas être requalifiée en annulation.
        let injected = URLError(.timedOut)
        MediaSilentRegistry.shared.install(failure: injected)
        let (call, outcome) = startSend(makeSilentWire(), request(), ceiling: .media)
        // `readyCount` n'avance qu'avec l'enregistrement de la poignée, dans la même section
        // critique : le signal garantit que l'échec injecté sera réellement remis à CE chargement.
        let ready = await waitUntil(timeout: 3) { MediaSilentRegistry.shared.readyCount() >= 1 }
        XCTAssertTrue(ready, "Le chargement doit être prêt à recevoir l'échec injecté")

        MediaSilentRegistry.shared.failAll()

        let verdict = await waitForOutcome(outcome)
        XCTAssertEqual(verdict, MediaOutcome.transport(injected.code.rawValue),
                       "Une panne d'ouverture garde son type et son code exacts, pas un texte libre")
        await releaseSilent(call, outcome)
    }

    func testCompletedStreamIsReadAndClosedNormally() async throws {
        let body = Data(repeating: 0x42, count: 512)
        MediaStreamRegistry.shared.install(.init(status: 200,
            headers: ["Content-Length": "512", "Content-Type": "application/octet-stream"],
            prelude: body, finishes: true))
        let response = try await makeStreamingWire().send(request(), ceiling: .media)
        XCTAssertEqual(response.body, body)
        XCTAssertEqual(response.declaredByteSize, 512)
        XCTAssertEqual(response.status, 200)
    }

    // MARK: Contrôle du harnais lui-même

    func testTheBoundedHarnessEndsWhenTheStreamIsNeverResolved() async throws {
        // Opération volontairement retenue : le flux reste ouvert et personne ne l'annule.
        MediaStreamRegistry.shared.install(.init(status: 200, headers: [:],
            prelude: Data(repeating: 0x41, count: 8), finishes: false))
        let (call, outcome) = startSend(makeStreamingWire(), request(), ceiling: .media)
        let opened = await waitUntil(timeout: 3) { MediaStreamRegistry.shared.openCount() >= 1 }
        XCTAssertTrue(opened)

        // L'attente du harnais est bornée : elle expire et rend la main, sans figer la suite
        // et sans dépendre du délai réseau de 30 s de la session.
        let settled = await waitUntil(timeout: 0.3) { outcome.current != nil }
        XCTAssertFalse(settled, "Le harnais doit expirer sur une opération retenue")
        XCTAssertNil(outcome.current)

        // Nettoyage explicite : libère la tâche suspendue. Ce n'est pas une preuve d'annulation.
        await releaseStream(call, outcome)
        _ = await waitUntil(timeout: 3) { outcome.current != nil }
    }

    // MARK: Garanties indépendantes de la configuration injectée

    func testInjectedConfigurationCannotReEnableCacheOrCookies() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = URLCache.shared
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad

        _ = MessagingMediaURLSessionTransport(configuration: configuration)

        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testRedirectDelegateNeverAllowsANewRequest() throws {
        let delegate = MessagingMediaNoRedirects()
        let session = URLSession.shared
        let origin = try XCTUnwrap(URL(string: "https://api.example.invalid/v1/schools/x"))
        let target = try XCTUnwrap(URL(string: "https://evil.example.invalid/collect"))
        let redirect = try XCTUnwrap(HTTPURLResponse(url: origin, statusCode: 302, httpVersion: "HTTP/1.1",
                                                     headerFields: ["Location": target.absoluteString]))
        let flag = MediaFlag()
        delegate.urlSession(session, task: session.dataTask(with: origin), willPerformHTTPRedirection: redirect,
                            newRequest: URLRequest(url: target)) { allowed in
            if allowed != nil { flag.set() }
        }
        XCTAssertFalse(flag.isSet, "Aucune redirection n'est suivie, même vers un autre hôte")
    }
}

// MARK: - Fixtures du wire

/// Compteur partagé sans verrou de test.
private final class MediaFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Issue d'un appel, telle que la tâche appelante l'a réellement observée.
///
/// Aucune erreur n'est réduite à un texte libre : le type et le code exact sont conservés
/// pour que le témoin puisse exiger `URLError.timedOut` et rien d'autre.
private enum MediaOutcome: Equatable, Sendable {
    case returned
    case failure(MessagingMediaTransportFailure)
    case cancelled
    /// `URLError(.cancelled)` brute : frontière non normalisée par le wire.
    case rawCancel
    /// `URLError` non liée à une annulation, avec son code exact.
    case transport(Int)
    case other
}

/// Issue d'un appel consignée par la tâche elle-même : le test lit un drapeau, il n'attend
/// jamais une tâche qui pourrait rester suspendue.
private final class MediaOutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MediaOutcome?

    var current: MediaOutcome? { lock.withLock { value } }
    func set(_ outcome: MediaOutcome) { lock.withLock { if value == nil { value = outcome } } }
}

/// Réponses locales livrées d'un bloc. Aucune requête ne sort de la machine.
private final class MediaStubRegistry: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, [String: String], Data)
    static let shared = MediaStubRegistry()

    private let lock = NSLock()
    private var handler: Handler?
    private var seen: [String] = []

    func install(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            self.seen = []
        }
    }

    func reset() {
        lock.withLock {
            handler = nil
            seen = []
        }
    }

    func take(_ request: URLRequest) -> Handler? {
        lock.withLock {
            seen.append(request.url?.absoluteString ?? "")
            return handler
        }
    }

    func requests() -> [String] { lock.withLock { seen } }
}

private final class MediaStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MediaStubRegistry.shared.take(request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let (status, headers, data) = handler(request)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Poignée de libération d'un flux retenu : le test peut forcer la fin d'un chargement
/// qu'il ne peut pas annuler lui-même. Sert uniquement au nettoyage.
private final class MediaStreamHandle: @unchecked Sendable {
    private let deliver: () -> Void
    init(_ deliver: @escaping () -> Void) { self.deliver = deliver }
    func abort() { deliver() }
}

/// Plan d'un flux qui reste ouvert : en-têtes et prélude livrés, puis plus rien.
/// Aucune fin de chargement n'est annoncée : seul `stopLoading` peut clore la requête.
private final class MediaStreamRegistry: @unchecked Sendable {
    struct Plan: Sendable {
        let status: Int
        let headers: [String: String]
        let prelude: Data
        let finishes: Bool
    }

    static let shared = MediaStreamRegistry()

    private let lock = NSLock()
    private var plan: Plan?
    private var stops = 0
    private var opened = 0
    private var delivered = 0
    private var live: [MediaStreamHandle] = []

    func install(_ plan: Plan) {
        lock.withLock {
            self.plan = plan
            stops = 0
            opened = 0
            delivered = 0
            live = []
        }
    }

    func reset() {
        lock.withLock {
            plan = nil
            stops = 0
            opened = 0
            delivered = 0
            live = []
        }
    }

    func take() -> Plan? {
        lock.withLock {
            opened += 1
            return plan
        }
    }

    func register(_ handle: MediaStreamHandle) { lock.withLock { live.append(handle) } }
    func recordStop() { lock.withLock { stops += 1 } }
    /// Appelé **après** `didLoad` du `URLProtocol` : atteste que le prélude a été remis à
    /// Foundation, pas que la routine du wire a repris `bytes(for:)` ni consommé un octet.
    func recordDelivered(_ count: Int) { lock.withLock { delivered += count } }
    func stopCount() -> Int { lock.withLock { stops } }
    func openCount() -> Int { lock.withLock { opened } }
    func deliveredCount() -> Int { lock.withLock { delivered } }

    /// Libération explicite des flux encore ouverts (échec d'assertion, fin de test).
    func abortAll() {
        let handles: [MediaStreamHandle] = lock.withLock {
            let copy = live
            live = []
            return copy
        }
        for handle in handles { handle.abort() }
    }
}

private final class MediaStreamURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let plan = MediaStreamRegistry.shared.take(), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: plan.status, httpVersion: "HTTP/1.1",
                                             headerFields: plan.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        MediaStreamRegistry.shared.register(MediaStreamHandle { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
        })
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !plan.prelude.isEmpty {
            client?.urlProtocol(self, didLoad: plan.prelude)
            MediaStreamRegistry.shared.recordDelivered(plan.prelude.count)
        }
        if plan.finishes {
            client?.urlProtocolDidFinishLoading(self)
        }
        // Sinon : le flux reste ouvert. Sans annulation de la tâche, aucune nouvelle donnée
        // n'arrive et `stopLoading` n'est jamais appelé — c'est ce que les tests observent.
    }

    override func stopLoading() { MediaStreamRegistry.shared.recordStop() }
}

/// Registre d'un stub **muet** : le chargement s'ouvre mais aucun en-tête n'est délivré, donc
/// `URLSession.bytes(for:)` reste suspendu. Seul un abandon (annulation appelante ou échec
/// injecté) termine la requête.
private final class MediaSilentRegistry: @unchecked Sendable {
    static let shared = MediaSilentRegistry()

    private let lock = NSLock()
    private var failure: URLError?
    private var stops = 0
    private var opened = 0
    private var live: [MediaStreamHandle] = []

    func install(failure: URLError? = nil) {
        lock.withLock {
            self.failure = failure
            stops = 0
            opened = 0
            live = []
        }
    }

    func reset() { install() }

    /// Ne compte rien : le signal « prêt » n'avance qu'avec l'enregistrement de la poignée
    /// (`register`), dans la même section critique, pour que le test ne puisse pas injecter
    /// un échec avant que le chargement soit en état de le recevoir.
    func take() -> URLError? {
        lock.withLock { failure }
    }

    func register(_ handle: MediaStreamHandle) {
        lock.withLock {
            live.append(handle)
            opened += 1
        }
    }

    func recordStop() { lock.withLock { stops += 1 } }
    func stopCount() -> Int { lock.withLock { stops } }
    func readyCount() -> Int { lock.withLock { opened } }

    /// Termine les chargements encore muets : nettoyage, ou échec injecté du témoin.
    func failAll() {
        let handles: [MediaStreamHandle] = lock.withLock {
            let copy = live
            live = []
            return copy
        }
        for handle in handles { handle.abort() }
    }
}

private final class MediaSilentURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // Aucun en-tête, aucune donnée : `bytes(for:)` ne peut pas rendre la main.
        let failure = MediaSilentRegistry.shared.take()
        MediaSilentRegistry.shared.register(MediaStreamHandle { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didFailWithError: failure ?? URLError(.cancelled))
        })
    }

    override func stopLoading() { MediaSilentRegistry.shared.recordStop() }
}
