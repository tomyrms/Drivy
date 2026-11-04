import XCTest
@testable import Drivy

/// Bornes du vrai wire média (#97, T2b2) : plafond déclaré, flux non déclaré, arrêt de la
/// tâche sur sortie prématurée, refus de redirection, configuration durcie.
///
/// Ces tests utilisent un `URLProtocol` local : aucun réseau réel n'est joint. Deux formes :
/// une réponse livrée d'un bloc, et un flux qui **reste ouvert** après ses en-têtes et son
/// prélude — seule l'annulation de la tâche provoque alors `stopLoading`, que le test observe.
///
/// Limite explicite : tant qu'un runner Apple ne les a pas exécutés, ils restent **préparés**.
/// Rien ici ne prouve l'arrêt natif de la consommation réseau sous Windows, et aucun test ne
/// mesure une fuite : `stopLoading` est le seul signal observable.
final class MessagingMediaURLSessionTransportTests: XCTestCase {
    override func tearDown() {
        MediaStubRegistry.shared.reset()
        MediaStreamRegistry.shared.reset()
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

    private func request(_ path: String = "/v1/schools/x") -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.invalid\(path)")!)
    }

    /// Attente conditionnelle bornée : jamais un délai fixe comme preuve.
    private func waitUntil(timeout: TimeInterval = 3, _ condition: @Sendable () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// Issue bornée d'un appel : un flux qui ne s'arrête pas fait échouer le test au lieu de le figer.
    private func outcome(of call: Task<MessagingMediaHTTPResponse, any Error>,
                         timeout: TimeInterval = 3) async -> String {
        await withTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    _ = try await call.value
                    return "returned"
                } catch is CancellationError {
                    return "cancelled"
                } catch {
                    return "other"
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return "timeout"
            }
            let first = await group.next() ?? "timeout"
            group.cancelAll()
            return first
        }
    }

    // MARK: Plafonds dérivés des constantes

    func testDeclaredLengthIsAcceptedUpToTheMediaCeilingAndRefusedAboveIt() async throws {
        // Dérivé du plafond, jamais saisi à la main : la première longueur refusée est plafond + 1.
        let ceiling = MessagingMediaResponseCeiling.mediaLimit
        MediaStubRegistry.shared.install { _ in
            (200, ["Content-Length": String(ceiling), "Content-Type": "application/octet-stream"], Data([1, 2, 3]))
        }
        let accepted = try await makeWire().send(request(), ceiling: .media)
        XCTAssertEqual(accepted.declaredByteSize, ceiling)
        XCTAssertEqual(accepted.body, Data([1, 2, 3]))

        MediaStubRegistry.shared.install { _ in
            (200, ["Content-Length": String(ceiling + 1), "Content-Type": "application/octet-stream"], Data([1, 2, 3]))
        }
        do {
            _ = try await makeWire().send(request(), ceiling: .media)
            XCTFail("Une taille annoncée au-delà du plafond ne doit pas être lue")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .tooLarge)
        }
    }

    func testStreamCeilingIsWiderThanTheBusinessMediaLimit() async throws {
        // La limite métier (4 Mio) et le plafond de flux (4 Mio + 8 Kio) sont deux bornes
        // distinctes : le wire ne refuse pas une taille que l'adaptateur doit qualifier.
        XCTAssertEqual(MessagingHTTPMediaTransport.maximumByteSize, AESCTRMediaCryptography.maximumByteSize)
        let aboveBusiness = MessagingHTTPMediaTransport.maximumByteSize + 1
        XCTAssertLessThan(aboveBusiness, MessagingMediaResponseCeiling.mediaLimit)

        MediaStubRegistry.shared.install { _ in
            (200, ["Content-Length": String(aboveBusiness)], Data([1, 2, 3]))
        }
        let response = try await makeWire().send(request(), ceiling: .media)
        XCTAssertEqual(response.declaredByteSize, aboveBusiness)
    }

    func testEnvelopeCeilingIsStricterThanTheMediaCeiling() async throws {
        let limit = MessagingMediaResponseCeiling.envelopeLimit
        XCTAssertLessThan(limit, MessagingMediaResponseCeiling.mediaLimit)

        MediaStubRegistry.shared.install { _ in (200, [:], Data(repeating: 0x41, count: 900)) }
        let small = try await makeWire().send(request(), ceiling: .envelope)
        XCTAssertEqual(small.body.count, 900)

        // Borne acceptée exactement, puis première valeur refusée.
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
        let ceiling = MessagingMediaResponseCeiling.mediaLimit
        MediaStreamRegistry.shared.install(.init(status: 200,
            headers: ["Content-Length": String(ceiling + 1), "Content-Type": "application/octet-stream"],
            prelude: Data(repeating: 0x41, count: 64), finishes: false))
        do {
            _ = try await makeStreamingWire().send(request(), ceiling: .media)
            XCTFail("Un en-tête au-delà du plafond ne doit pas être lu")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .tooLarge)
        }
        let stopped = await waitUntil { MediaStreamRegistry.shared.stopCount() >= 1 }
        XCTAssertTrue(stopped, "La tâche du flux doit être annulée sur en-tête refusé")
    }

    func testOverflowDuringReadingStopsTheOpenStream() async throws {
        let limit = MessagingMediaResponseCeiling.envelopeLimit
        MediaStreamRegistry.shared.install(.init(status: 200, headers: [:],
            prelude: Data(repeating: 0x41, count: limit + 1), finishes: false))
        do {
            _ = try await makeStreamingWire().send(request(), ceiling: .envelope)
            XCTFail("Un flux au-delà du plafond doit être refusé pendant la lecture")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .tooLarge)
        }
        let stopped = await waitUntil { MediaStreamRegistry.shared.stopCount() >= 1 }
        XCTAssertTrue(stopped, "La tâche du flux doit être annulée au dépassement")
    }

    func testCancellingTheCallerStopsTheOpenStream() async throws {
        MediaStreamRegistry.shared.install(.init(status: 200, headers: [:],
            prelude: Data(repeating: 0x41, count: 1_024), finishes: false))
        let wire = makeStreamingWire()
        let target = request()
        let call = Task { try await wire.send(target, ceiling: .media) }
        // Barrière : la requête est réellement ouverte avant l'annulation.
        let opened = await waitUntil { MediaStreamRegistry.shared.openCount() >= 1 }
        XCTAssertTrue(opened, "La requête doit s'ouvrir avant l'annulation")
        call.cancel()

        let result = await outcome(of: call)
        XCTAssertEqual(result, "cancelled", "Une annulation appelante doit rester une CancellationError")
        let stopped = await waitUntil { MediaStreamRegistry.shared.stopCount() >= 1 }
        XCTAssertTrue(stopped, "La tâche du flux doit être annulée à l'annulation appelante")
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

    func install(_ plan: Plan) {
        lock.withLock {
            self.plan = plan
            stops = 0
            opened = 0
        }
    }

    func reset() {
        lock.withLock {
            plan = nil
            stops = 0
            opened = 0
        }
    }

    func take() -> Plan? {
        lock.withLock {
            opened += 1
            return plan
        }
    }

    func recordStop() { lock.withLock { stops += 1 } }
    func stopCount() -> Int { lock.withLock { stops } }
    func openCount() -> Int { lock.withLock { opened } }
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
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !plan.prelude.isEmpty {
            client?.urlProtocol(self, didLoad: plan.prelude)
        }
        if plan.finishes {
            client?.urlProtocolDidFinishLoading(self)
        }
        // Sinon : le flux reste ouvert. Sans annulation de la tâche, aucune nouvelle donnée
        // n'arrive et `stopLoading` n'est jamais appelé — c'est ce que les tests observent.
    }

    override func stopLoading() { MediaStreamRegistry.shared.recordStop() }
}
