import Foundation
import Testing
@testable import Drivy

@MainActor struct SchoolAccountRecoveryTests {
    private let configuration = AppConfiguration(apiBaseURL: URL(string: "https://drivy.example.test")!,
        issuer: URL(string: "https://drivy.example.test/identity/realms/drivy")!,
        clientID: "drivy-apple", redirectURL: AppConfiguration.callback)

    @Test func anUnconfiguredRelayNeverProducesALinkOrSendsAnIdentity() async throws {
        let transport = RecoveryTransport(payload: Self.payload(available: false))
        let client = SchoolAccountRecoveryClient(configuration: configuration, transport: transport)
        let result = try await client.options()
        #expect(!result.available && result.recoveryUrl == nil)
        let request = try #require(await transport.lastRequest)
        #expect(request.httpMethod == "GET" && request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(request.url?.absoluteString == "https://drivy.example.test/v1/account-recovery/options")
    }

    @Test func recoveryOpensOnlyTheControlledPortalWithoutAuthenticatingTheApp() async throws {
        let transport = RecoveryTransport(payload: Self.payload(available: true, url: "https://drivy.example.test/app/recover"))
        let result = try await SchoolAccountRecoveryClient(configuration: configuration, transport: transport).options()
        #expect(result.recoveryUrl?.absoluteString == "https://drivy.example.test/app/recover")
        #expect(await transport.lastRequest?.httpBody == nil)
    }

    @Test(arguments: ["https://foreign.example.test/app/recover", "http://drivy.example.test/app/recover",
        "https://drivy.example.test:444/app/recover", "https://user@drivy.example.test/app/recover",
        "https://drivy.example.test/app/recover?email=someone", "https://drivy.example.test/app/recover#token=secret",
        "https://drivy.example.test/other", "https://drivy.example.test/app/%72ecover", "/app/recover"])
    func anUntrustedDestinationCannotBeOpened(_ url: String) async {
        let client = SchoolAccountRecoveryClient(configuration: configuration,
            transport: RecoveryTransport(payload: Self.payload(available: true, url: url)))
        await #expect(throws: SchoolAccountRecoveryFailure.invalidResponse) { try await client.options() }
    }

    @Test func inconsistentAvailabilityAndRedirectedResponsesAreRejected() async {
        for payload in [Self.payload(available: true), Self.payload(available: false, url: "https://drivy.example.test/app/recover") ] {
            let client = SchoolAccountRecoveryClient(configuration: configuration, transport: RecoveryTransport(payload: payload))
            await #expect(throws: SchoolAccountRecoveryFailure.invalidResponse) { try await client.options() }
        }
        let redirected = RecoveryTransport(payload: Self.payload(available: false), responseURL: URL(string: "https://drivy.example.test/other")!)
        await #expect(throws: SchoolAccountRecoveryFailure.invalidResponse) {
            try await SchoolAccountRecoveryClient(configuration: configuration, transport: redirected).options()
        }
    }

    @Test func networkRateLimitAndCancellationNeverBecomeAvailability() async {
        let offline = RecoveryTransport(payload: Data(), failure: URLError(.notConnectedToInternet))
        await #expect(throws: SchoolAccountRecoveryFailure.unavailable) {
            try await SchoolAccountRecoveryClient(configuration: configuration, transport: offline).options()
        }
        let limited = RecoveryTransport(payload: Data(), status: 429)
        await #expect(throws: SchoolAccountRecoveryFailure.attempts) {
            try await SchoolAccountRecoveryClient(configuration: configuration, transport: limited).options()
        }
        let cancelled = RecoveryTransport(payload: Data(), failure: URLError(.cancelled))
        await #expect(throws: CancellationError.self) {
            try await SchoolAccountRecoveryClient(configuration: configuration, transport: cancelled).options()
        }
    }

    private static func payload(available: Bool, url: String? = nil) -> Data {
        let link: Any = url.map { $0 as Any } ?? NSNull()
        return try! JSONSerialization.data(withJSONObject: ["data": ["available": available, "recoveryUrl": link],
                                                    "serverTime": "2026-10-26T12:00:00Z"])
    }
}

private actor RecoveryTransport: SchoolHTTPTransport {
    let payload: Data
    let status: Int
    let responseURL: URL?
    let failure: URLError?
    private(set) var lastRequest: URLRequest?
    init(payload: Data, status: Int = 200, responseURL: URL? = nil, failure: URLError? = nil) {
        self.payload = payload; self.status = status; self.responseURL = responseURL; self.failure = failure
    }
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        lastRequest = request
        if let failure { throw failure }
        return .init(data: payload, status: status, url: responseURL ?? request.url!, contentType: "application/json")
    }
}
