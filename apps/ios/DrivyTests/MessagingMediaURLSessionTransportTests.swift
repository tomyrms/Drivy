import XCTest
@testable import Drivy

/// Bornes du vrai wire média (#97, T2b2) : plafond déclaré, flux non déclaré, refus de
/// redirection. Ces tests utilisent un `URLProtocol` local : aucun réseau réel n'est joint.
///
/// Limite explicite : un `URLProtocol` remet le corps déjà présent en mémoire locale. Ces
/// tests prouvent donc la **boucle de lecture bornée** du wire (refus avant accumulation,
/// refus pendant la lecture, jamais `data(for:)`), pas la cadence réelle du réseau.
final class MessagingMediaURLSessionTransportTests: XCTestCase {
    override func tearDown() {
        MediaStubRegistry.shared.reset()
        super.tearDown()
    }

    private func makeWire() -> MessagingMediaURLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MediaStubURLProtocol.self]
        return MessagingMediaURLSessionTransport(configuration: configuration)
    }

    private func request(_ path: String = "/v1/schools/x") -> URLRequest {
        URLRequest(url: URL(string: "https://api.example.invalid\(path)")!)
    }

    func testDeclaredLengthAboveTheMediaCeilingIsRefusedBeforeAnyAccumulation() async throws {
        MediaStubRegistry.shared.install { _ in
            (200, ["Content-Length": "4200000", "Content-Type": "application/octet-stream"], Data([1, 2, 3]))
        }
        do {
            _ = try await makeWire().send(request(), ceiling: .media)
            XCTFail("Une taille annoncée au-delà du plafond ne doit pas être lue")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .tooLarge)
        }
    }

    func testEnvelopeCeilingIsStricterThanTheMediaCeiling() async throws {
        let small = Data(repeating: 0x41, count: 900)
        MediaStubRegistry.shared.install { _ in (200, [:], small) }
        let response = try await makeWire().send(request(), ceiling: .envelope)
        XCTAssertEqual(response.body.count, 900)

        let beyond = Data(repeating: 0x41, count: MessagingMediaResponseCeiling.envelopeLimit + 1)
        MediaStubRegistry.shared.install { _ in (200, [:], beyond) }
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

/// Réponses locales du `URLProtocol`. Aucune requête ne sort de la machine.
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
