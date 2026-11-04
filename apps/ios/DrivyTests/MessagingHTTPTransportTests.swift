import XCTest
@testable import Drivy

@MainActor
final class MessagingHTTPTransportTests: XCTestCase {
    func testDurableMutationsCarryTheirReceiptIdentityOnEveryRoute() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let conversation = UUID(), message = UUID()
        let cases: [(MessagingMutationKind, MessagingMutationValue, String)] = [
            (.reaction("👍"), .active(true), "PUT"), (.reaction("👍"), .active(false), "DELETE"),
            (.pin, .active(true), "PUT"), (.pin, .active(false), "DELETE"),
            (.vote, .options(["o2", "o1"]), "PUT"), (.hideForMe, .active(true), "DELETE"),
            (.deleteForEveryone, .active(true), "DELETE")
        ]
        for (kind, value, method) in cases {
            let requestID = UUID()
            let wire = RecordingMessagingHTTP { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), requestID.uuidString.lowercased())
                XCTAssertEqual(request.httpMethod, method)
                if kind == .vote {
                    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                    XCTAssertEqual(body["optionIndexes"] as? [Int], [0, 1])
                }
                let response = """
                {"data":{},"context":{"schoolId":"\(scope.schoolID)","actorPersonId":"\(scope.accountID)","accessEpoch":4},"mutationReceipt":{"operationId":"\(requestID)"}}
                """
                return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
            }
            let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                transport: wire, currentScope: { scope })
            try await client.mutate(scope: scope, key: .init(conversationID: conversation, messageID: message, kind: kind),
                                    value: value, requestID: requestID)
        }
    }

    func testMissingOrDifferentReceiptIsNeverAcceptedAsAConfirmation() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        for missing in [true, false] {
            let wire = RecordingMessagingHTTP { request in
                let receipt = missing ? "" : ",\"mutationReceipt\":{\"operationId\":\"\(UUID())\"}"
                let response = """
                {"data":{},"context":{"schoolId":"\(scope.schoolID)","actorPersonId":"\(scope.accountID)","accessEpoch":4}\(receipt)}
                """
                return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
            }
            let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                transport: wire, currentScope: { scope })
            do {
                try await client.mutate(scope: scope, key: .init(conversationID: UUID(), messageID: UUID(), kind: .pin),
                                        value: .active(true), requestID: UUID())
                XCTFail("Une réponse sans reçu correspondant n'acquitte pas l'intention")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, missing ? .mutationReceiptUnavailable : .invalidResponse)
            }
        }
    }

    func testSendCarriesOriginalEpochOutsideCiphertextAndNeverRecoveryContent() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), message = UUID()
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            let raw = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            XCTAssertEqual(body["expectedMembersEpoch"] as? Int, 7)
            let envelope = try XCTUnwrap(body["ciphertext"] as? [String: Any])
            XCTAssertEqual(Set(envelope.keys), Set(["scheme", "keyId", "payload"]))
            XCTAssertNil(body["recoveryContent"])
            XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("sentinelle-récupération"))
            XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains(Data("sentinelle-récupération".utf8).base64EncodedString()))
            let response = """
            {"data":{"id":"\(message)","schoolId":"\(school)","conversationId":"\(conversation)","sequence":1,"clientMessageId":"\(intent)","senderId":"\(account)","ciphertext":{"scheme":"synthetic","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[],"acceptedAt":"2026-10-23T00:00:00Z"},"context":{"schoolId":"\(school)","actorPersonId":"\(account)","accessEpoch":1}}
            """
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
            transport: wire, currentScope: { scope })
        let client = MessagingAPIClient(transport: transport)
        let entry = MessagingPending(clientMessageID: intent, conversationID: conversation,
            ciphertext: MessagingCiphertext(scheme: "synthetic", keyID: "fixture", payload: Data([1, 2, 3]), expectedMembersEpoch: 7),
            recoveryContent: Data("sentinelle-récupération".utf8))
        let ack = try await client.send(scope: scope, pending: entry)
        XCTAssertEqual(ack.serverMessageID, message)
    }

    func testMembersEpochConflictHasSpecificFailureNotGenericRetryAdvice() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            SchoolHTTPResponse(data: Data("{\"code\":\"MESSAGING_MEMBERS_CHANGED\"}".utf8), status: 409,
                               url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
            transport: wire, currentScope: { scope })
        do {
            _ = try await transport.send(scope: scope, conversationID: UUID(), body: MessagingSendDTO(
                clientMessageId: UUID(), ciphertext: MessagingCiphertext(scheme: "synthetic", keyID: "fixture",
                    payload: Data([1, 2, 3]), expectedMembersEpoch: 7), mentionPersonIds: []))
            XCTFail("L'enveloppe périmée doit être refusée")
        } catch MessagingFailure.membersChanged {}
    }

    func testReportsNeverLeakLocalEncryptionEpochIntoOpaqueEnvelope() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            let raw = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            let items = try XCTUnwrap(body["items"] as? [[String: Any]])
            let envelope = try XCTUnwrap(items.first?["ciphertext"] as? [String: Any])
            XCTAssertEqual(Set(envelope.keys), Set(["scheme", "keyId", "payload"]))
            let response = """
            {"data":{},"context":{"schoolId":"\(scope.schoolID)","actorPersonId":"\(scope.accountID)","accessEpoch":1}}
            """
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
            transport: wire, currentScope: { scope })
        try await transport.report(scope: scope, conversationID: UUID(), clientReportID: UUID(), items: [
            MessagingReportItem(messageID: UUID(), ciphertext: MessagingCiphertext(scheme: "synthetic", keyID: "fixture",
                payload: Data([1, 2, 3]), expectedMembersEpoch: 9))
        ])
    }

    func testSchoolRouteBearerAndOpaqueMessageDecode() async throws {
        let school = UUID(), conversation = UUID(), sender = UUID(), message = UUID(), intent = UUID()
        let url = URL(string: "https://api.example.invalid/")!
        let scopeAccount = UUID()
        let wire = RecordingMessagingHTTP { request in
            let path = request.url!.path
            guard path == "/v1/schools/\(school.uuidString)/messaging/conversations/\(conversation.uuidString)/messages",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token",
                  request.value(forHTTPHeaderField: "Cache-Control") == "no-store" else {
                throw MessagingFailure.invalidResponse
            }
            guard request.value(forHTTPHeaderField: "X-Drivy-Expected-Person-Id") == scopeAccount.uuidString.lowercased(),
                  request.value(forHTTPHeaderField: "X-Drivy-Expected-Access-Epoch") == "1" else {
                throw MessagingFailure.invalidResponse
            }
            let body = """
            {"data":{"items":[{"id":"\(message.uuidString)","schoolId":"\(school.uuidString)","conversationId":"\(conversation.uuidString)","sequence":1,"clientMessageId":"\(intent.uuidString)","senderId":"\(sender.uuidString)","ciphertext":{"scheme":"synthetic","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[],"acceptedAt":"2026-10-23T00:00:00Z"}],"nextCursor":null},"context":{"schoolId":"\(school.uuidString)","actorPersonId":"\(scopeAccount.uuidString)","accessEpoch":1}}
            """
            return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let scope = MessagingScope(accountID: scopeAccount, schoolID: school, accessEpoch: 1, apiBaseURL: url.absoluteString)
        let client = MessagingHTTPTransport.using(baseURL: url, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let page = try await client.messages(scope: scope, conversationID: conversation, before: nil)
        XCTAssertEqual(page.items.count, 1)
        let ciphertext = try XCTUnwrap(page.items.first?.ciphertext)
        XCTAssertEqual(ciphertext.payload, Data([1, 2, 3]))
        XCTAssertEqual(page.items.first?.schoolId, school)
    }

    func testReadProgressDoesNotClearMuteAndMuteRequiresVersion() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 4,
                                   apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            guard request.httpMethod == "PUT" else { throw MessagingFailure.invalidResponse }
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            guard json["mutedUntil"] == nil, json["expectedVersion"] == nil,
                  json["lastReadSequence"] as? Int == 2 else { throw MessagingFailure.invalidResponse }
            let body = """
            {"data":{"lastReadSequence":2,"mutedUntil":"2026-10-23T05:00:00Z","readStateVersion":8},"context":{"schoolId":"\(school.uuidString)","actorPersonId":"\(account.uuidString)","accessEpoch":4}}
            """
            return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let state = try await client.readState(scope: scope, conversationID: conversation,
                                               sequence: 2, mutedUntil: nil, expectedVersion: nil)
        XCTAssertEqual(state.version, 8)
        XCTAssertNotNil(state.mutedUntil)
    }

    func testClearingMuteEncodesExplicitNullWithExpectedVersion() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 4,
                                   apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            guard json["mutedUntil"] is NSNull, json["expectedVersion"] as? Int == 8,
                  json["lastReadSequence"] as? Int == 2 else { throw MessagingFailure.invalidResponse }
            let body = """
            {"data":{"lastReadSequence":2,"mutedUntil":null,"readStateVersion":9},"context":{"schoolId":"\(school.uuidString)","actorPersonId":"\(account.uuidString)","accessEpoch":4}}
            """
            return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let state = try await client.readState(scope: scope, conversationID: conversation,
                                               sequence: 2, mutedUntil: nil, expectedVersion: 8)
        XCTAssertNil(state.mutedUntil)
        XCTAssertEqual(state.version, 9)
    }

    func testDifferentAPIURLRejectedBeforeNetwork() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let wire = RecordingMessagingHTTP { _ in throw MessagingFailure.invalidResponse }
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                   apiBaseURL: "https://different.example.invalid/")
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        do {
            _ = try await client.contacts(scope: scope)
            XCTFail("API URL différente")
        } catch MessagingFailure.contextChanged { }
        let requests = await wire.requests()
        XCTAssertEqual(requests, 0)
    }

    // MARK: Bornes du protocole sur l'enveloppe réellement émise (#97, T2b1)

    private func sendFixture(payload: Data, mentions: [UUID] = [], intent: UUID = UUID()) -> MessagingSendDTO {
        MessagingSendDTO(clientMessageId: intent,
            ciphertext: MessagingCiphertext(scheme: "megolm.v1", keyID: "fixture", payload: payload,
                                            expectedMembersEpoch: 3),
            mentionPersonIds: mentions)
    }

    /// 9 000 octets → 12 000 caractères base64 : la frontière exacte du serveur, corps sous 16 Kio.
    func testSendPayloadAtTheTwelveThousandBoundIsAccepted() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID()
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 3, apiBaseURL: baseURL.absoluteString)
        let payload = Data(repeating: 0x41, count: 9_000)
        XCTAssertEqual(payload.base64EncodedString().utf8.count, 12_000)
        let wire = RecordingMessagingHTTP { request in
            let raw = try XCTUnwrap(request.httpBody)
            XCTAssertLessThanOrEqual(raw.count, 16_384)
            let response = """
            {"data":{"id":"\(UUID())","schoolId":"\(school)","conversationId":"\(conversation)","sequence":1,"clientMessageId":"\(intent)","senderId":"\(account)","ciphertext":{"scheme":"megolm.v1","keyId":"fixture","payload":"\(payload.base64EncodedString())"},"mentionPersonIds":[],"acceptedAt":"2026-11-04T00:00:00Z"},"context":{"schoolId":"\(school)","actorPersonId":"\(account)","accessEpoch":3}}
            """
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                     transport: wire, currentScope: { scope })
        let ack = try await transport.send(scope: scope, conversationID: conversation,
                                           body: sendFixture(payload: payload, intent: intent))
        XCTAssertEqual(ack.clientMessageId, intent)
        let requests = await wire.requests()
        XCTAssertEqual(requests, 1)
    }

    /// 9 001 octets → 12 004 caractères : au-delà du plafond serveur, donc refusé avant émission.
    /// Le corps seul (≈ 12,3 Kio) serait pourtant sous les 16 Kio : c'est bien la borne du payload qui tranche.
    func testSendPayloadBeyondTheTwelveThousandBoundIsRefusedBeforeTokenAndRequest() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 3, apiBaseURL: baseURL.absoluteString)
        let payload = Data(repeating: 0x41, count: 9_001)
        XCTAssertEqual(payload.base64EncodedString().utf8.count, 12_004)
        let wire = RecordingMessagingHTTP { request in
            XCTFail("Aucune requête ne doit partir pour une enveloppe au-delà de 12 000 caractères")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMessagingToken()
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: token,
                                                     transport: wire, currentScope: { scope })
        do {
            _ = try await transport.send(scope: scope, conversationID: UUID(), body: sendFixture(payload: payload))
            XCTFail("Un payload au-delà de 12 000 caractères base64 doit être refusé avant émission")
        } catch { XCTAssertEqual(error as? MessagingFailure, .invalidResponse) }
        let requests = await wire.requests()
        XCTAssertEqual(requests, 0, "Aucune requête réseau au refus")
        let tokens = token.requests
        XCTAssertEqual(tokens, 0, "Aucun jeton consommé au refus")
    }

    /// Garde défensive du corps : même avec un payload sous 12 000 caractères, un `SendBody` au-delà de
    /// 16 Kio ne part pas. Le cas est fabriqué (mentions hors plafond serveur) : c'est la garde client
    /// qui est éprouvée, pas la validité du message.
    func testSendBodyBeyondSixteenKilobytesIsRefusedBeforeAnyRequest() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 3, apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            XCTFail("Aucune requête ne doit partir pour un corps au-delà de 16 Kio")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMessagingToken()
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: token,
                                                     transport: wire, currentScope: { scope })
        let payload = Data(repeating: 0x41, count: 9_000)
        let mentions = (0..<400).map { _ in UUID() }
        do {
            _ = try await transport.send(scope: scope, conversationID: UUID(),
                                         body: sendFixture(payload: payload, mentions: mentions))
            XCTFail("Un corps au-delà de 16 Kio doit être refusé avant émission")
        } catch { XCTAssertEqual(error as? MessagingFailure, .invalidResponse) }
        let requests = await wire.requests()
        XCTAssertEqual(requests, 0)
        let tokens = token.requests
        XCTAssertEqual(tokens, 0)
    }

    /// Signalement : le lot garde sa limite de 640 Kio, donc un corps au-delà de 16 Kio reste valide
    /// quand chaque item respecte 12 000 caractères base64 (4 × 9 000 octets ici).
    func testReportAcceptsSeveralItemsWhoseBodyExceedsSixteenKilobytes() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            let raw = try XCTUnwrap(request.httpBody)
            XCTAssertGreaterThan(raw.count, 16_384, "Le corps du signalement dépasse la borne d'un message ordinaire")
            XCTAssertLessThanOrEqual(raw.count, 655_360)
            let response = """
            {"data":{},"context":{"schoolId":"\(scope.schoolID)","actorPersonId":"\(scope.accountID)","accessEpoch":1}}
            """
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                     transport: wire, currentScope: { scope })
        try await transport.report(scope: scope, conversationID: UUID(), clientReportID: UUID(),
                                   items: (0..<4).map { _ in reportItem(bytes: 9_000) })
        let requests = await wire.requests()
        XCTAssertEqual(requests, 1)
    }

    /// Le plafond de 12 000 s'applique aussi à **chaque** item de signalement : un seul item trop grand
    /// suffit à refuser le lot avant émission, même si le corps reste sous 640 Kio.
    func testReportItemBeyondTwelveThousandBase64IsRefusedBeforeRequest() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            XCTFail("Aucune requête ne doit partir pour un item au-delà de 12 000 caractères")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMessagingToken()
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: token,
                                                     transport: wire, currentScope: { scope })
        let items = [reportItem(bytes: 9_000), reportItem(bytes: 9_001)]
        do {
            try await transport.report(scope: scope, conversationID: UUID(), clientReportID: UUID(), items: items)
            XCTFail("Un item au-delà de 12 000 caractères base64 doit être refusé")
        } catch { XCTAssertEqual(error as? MessagingFailure, .invalidResponse) }
        let requests = await wire.requests()
        XCTAssertEqual(requests, 0)
        let tokens = token.requests
        XCTAssertEqual(tokens, 0)
    }

    /// Frontière haute admissible : 50 items de 9 000 octets tiennent sous 640 Kio et partent.
    func testReportBodyBoundAcceptsTheProtocolMaximum() async throws {
        let baseURL = URL(string: "https://api.example.invalid/")!
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
        let wire = RecordingMessagingHTTP { request in
            let raw = try XCTUnwrap(request.httpBody)
            XCTAssertLessThanOrEqual(raw.count, 655_360)
            XCTAssertGreaterThan(raw.count, 500_000)
            let response = """
            {"data":{},"context":{"schoolId":"\(scope.schoolID)","actorPersonId":"\(scope.accountID)","accessEpoch":1}}
            """
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                     transport: wire, currentScope: { scope })
        try await transport.report(scope: scope, conversationID: UUID(), clientReportID: UUID(),
                                   items: (0..<50).map { _ in reportItem(bytes: 9_000) })
        let requests = await wire.requests()
        XCTAssertEqual(requests, 1)
    }

    private func reportItem(bytes: Int) -> MessagingReportItem {
        MessagingReportItem(messageID: UUID(),
            ciphertext: MessagingCiphertext(scheme: "megolm.v1", keyID: "fixture",
                                            payload: Data(repeating: 0x42, count: bytes), expectedMembersEpoch: 9))
    }
}

@MainActor private final class MessagingFixtureToken: AccessTokenSource {
    func accessToken() async throws -> String { "synthetic-token" }
}

/// Jeton compteur : prouve qu'un refus avant émission ne consomme aucun jeton.
@MainActor private final class CountingMessagingToken: AccessTokenSource {
    private(set) var requests = 0
    func accessToken() async throws -> String {
        requests += 1
        return "synthetic-token"
    }
}

private actor RecordingMessagingHTTP: SchoolHTTPTransport {
    private let responder: @Sendable (URLRequest) throws -> SchoolHTTPResponse
    private var count = 0
    init(_ responder: @escaping @Sendable (URLRequest) throws -> SchoolHTTPResponse) { self.responder = responder }
    func send(_ request: URLRequest) throws -> SchoolHTTPResponse { count += 1; return try responder(request) }
    func requests() -> Int { count }
}

/// Signalements (#77) : lecture de la boîte, changement de statut, cadence refusée.
@MainActor
final class MessagingReportTransportTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.invalid/")!

    func testReportListReadsStatusesAndPostgresMicrosecondDates() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2, apiBaseURL: baseURL.absoluteString)
        let report = UUID(), conversation = UUID(), reporter = UUID(), author = UUID(), message = UUID(), admin = UUID()
        let wire = RecordingMessagingHTTP { [scope] request in
            XCTAssertEqual(request.httpMethod, "GET")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "status" }?.value, "OPEN")
            XCTAssertEqual(query.first { $0.name == "limit" }?.value, "50")
            XCTAssertTrue(request.url!.path.hasSuffix("/messaging/reports"))
            let response = """
            {"data":{"reports":[{"id":"\(report)","conversationId":"\(conversation)","conversationKind":"PRIVATE","reporterPersonId":"\(reporter)","reporterDisplayName":"Léa Fixture","createdAt":"2026-10-31T12:00:00.123Z","status":"OPEN","statusUpdatedAt":"2026-10-31T12:00:00.123Z","items":[{"messageId":"\(message)","ciphertext":{"scheme":"synthetic","keyId":"fixture","payload":"AQID"},"senderPersonId":"\(author)","senderDisplayName":"Marc Fixture","sequence":4,"acceptedAt":"2026-10-31T13:05:00.123456+01:00"}],"history":[{"actorPersonId":"\(admin)","actorDisplayName":"Admin Fixture","fromStatus":"HANDLED","toStatus":"OPEN","createdAt":"2026-10-31T13:10:00.654321+01:00"}]}],"nextCursor":null,"openCount":1},"context":{"schoolId":"\(scope.schoolID)","actorPersonId":"\(scope.accountID)","accessEpoch":2}}
            """
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let page = try await client.reports(scope: scope, status: .open, before: nil)
        XCTAssertEqual(page.openCount, 1)
        XCTAssertNil(page.nextCursor)
        let first = try XCTUnwrap(page.reports.first)
        XCTAssertEqual(first.id, report)
        XCTAssertEqual(first.status, .open)
        XCTAssertEqual(first.conversationKind, "PRIVATE")
        XCTAssertEqual(first.reporterName, "Léa Fixture")
        let item = try XCTUnwrap(first.items.first)
        XCTAssertEqual(item.messageID, message)
        XCTAssertEqual(item.senderName, "Marc Fixture")
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Microsecondes ramenées aux millisecondes, fuseau conservé.
        let accepted = try XCTUnwrap(item.acceptedAt)
        let expectedAccepted = try XCTUnwrap(fractional.date(from: "2026-10-31T12:05:00.123Z"))
        XCTAssertEqual(accepted.timeIntervalSince1970, expectedAccepted.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(first.history.first?.from, .handled)
        XCTAssertEqual(first.history.first?.to, .open)
        let changed = try XCTUnwrap(first.history.first?.at)
        let expectedChange = try XCTUnwrap(fractional.date(from: "2026-10-31T12:10:00.654Z"))
        XCTAssertEqual(changed.timeIntervalSince1970, expectedChange.timeIntervalSince1970, accuracy: 0.001)
    }

    func testStatusChangeSendsTheStatusItExpectsAndReadsTheAnswer() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2, apiBaseURL: baseURL.absoluteString)
        let report = UUID()
        let wire = RecordingMessagingHTTP { [scope] request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertTrue(request.url!.path.hasSuffix("/messaging/reports/\(report.uuidString.lowercased())/status"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
            XCTAssertEqual(body, ["status": "HANDLED", "expectedStatus": "OPEN"])
            let response = """
            {"data":{"reportId":"\(report)","status":"HANDLED","statusUpdatedAt":"2026-10-31T13:10:00.000Z","history":[]},"context":{"schoolId":"\(scope.schoolID)","actorPersonId":"\(scope.accountID)","accessEpoch":2}}
            """
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                  transport: wire, currentScope: { scope })
        let change = try await client.setReportStatus(scope: scope, reportID: report, status: .handled, expected: .open)
        XCTAssertEqual(change.status, .handled)
        XCTAssertEqual(change.reportID, report)
    }

    func testRateLimitIsNamedAndOtherRefusalsKeepTheirMeaning() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2, apiBaseURL: baseURL.absoluteString)
        let cases: [(Int, String, MessagingFailure)] = [
            (429, "REPORT_RATE_LIMITED", .reportRateLimited),
            (409, "REPORT_STATUS_CONFLICT", .stateConflict),
            (403, "METRIC_SCOPE_FORBIDDEN", .accessChanged),
            (429, "OTHER_LIMIT", .unavailable),
        ]
        for (status, code, expected) in cases {
            let wire = RecordingMessagingHTTP { request in
                SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\"}".utf8), status: status, url: request.url!,
                                   contentType: "application/problem+json")
            }
            let client = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: MessagingFixtureToken(),
                                                      transport: wire, currentScope: { scope })
            do {
                _ = try await client.reports(scope: scope, status: nil, before: nil)
                XCTFail("Un refus n'est jamais une liste")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, expected, "\(status) \(code)")
            }
        }
    }
}
