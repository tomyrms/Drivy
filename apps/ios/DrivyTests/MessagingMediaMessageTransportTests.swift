import XCTest
@testable import Drivy

/// #97 — raccord du média au POST message, côté transport HTTP.
///
/// Correction 1/2 : le mode média est déduit du contenu émis (`body.media != nil`), le mapping
/// des refus exige la paire exacte (statut, code) du contrat T1, et un reçu média est symétrique
/// de l'intention. Tests écrits avant le code ; non compilés sous Windows, aucun RED/GREEN inventé.
@MainActor
final class MessagingMediaMessageTransportTests: XCTestCase {
    private let baseURL = MediaMessageFixture.baseURL

    private func makeScope(account: UUID, school: UUID) -> MessagingScope {
        MessagingScope(accountID: account, schoolID: school, accessEpoch: 3, apiBaseURL: baseURL.absoluteString)
    }

    private func ciphertext(payload: Data = Data([1, 2, 3])) -> MessagingCiphertext {
        MessagingCiphertext(scheme: "megolm.v1", keyID: "fixture", payload: payload, expectedMembersEpoch: 3)
    }

    private func mediaSend(intent: UUID, payload: Data = Data([1, 2, 3]), mentions: [UUID] = [],
                           poll: MessagingPollDraftMeta? = nil,
                           media: MessagingMediaMessageIntent) -> MessagingSendDTO {
        MessagingSendDTO(clientMessageId: intent, ciphertext: ciphertext(payload: payload),
                         mentionPersonIds: mentions, replyToMessageId: nil, poll: poll, media: media)
    }

    // MARK: Contrats de valeur

    func testMediaIntentEncodesOnlyIdentifierAndSizeAndRoundTrips() throws {
        let mediaID = UUID()
        let intent = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 1_234)
        let raw = try JSONEncoder().encode(intent)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["mediaId", "byteSize"]))
        XCTAssertEqual(object["mediaId"] as? String, mediaID.uuidString)
        XCTAssertEqual(object["byteSize"] as? Int, 1_234)
        XCTAssertFalse(object.keys.contains("mime"))
        XCTAssertFalse(object.keys.contains("name"))
        XCTAssertFalse(object.keys.contains("key"))
        XCTAssertFalse(object.keys.contains("iv"))
        XCTAssertFalse(object.keys.contains("hash"))
        XCTAssertFalse(object.keys.contains("deleted"))
        let decoded = try JSONDecoder().decode(MessagingMediaMessageIntent.self, from: raw)
        XCTAssertEqual(decoded, intent)
    }

    func testMediaReferenceEncodesIdentifierSizeAndServerDeletedFact() throws {
        let mediaID = UUID()
        let reference = try MessagingMessageMediaReference(mediaID: mediaID, byteSize: 4_194_304, deleted: true)
        let raw = try JSONEncoder().encode(reference)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["mediaId", "byteSize", "deleted"]))
        XCTAssertEqual(object["deleted"] as? Bool, true)
        let decoded = try JSONDecoder().decode(MessagingMessageMediaReference.self, from: raw)
        XCTAssertEqual(decoded, reference)
    }

    func testMediaIntentBoundsAcceptOneByteAndFourMebibytesAndRejectZeroAndAbove() throws {
        XCTAssertNoThrow(try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 1))
        XCTAssertNoThrow(try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 4_194_304))

        for invalid in [0, 4_194_305, -1] {
            XCTAssertThrowsError(try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: invalid)) { error in
                XCTAssertEqual(error as? MessagingFailure, .invalidResponse)
            }
            let json = "{\"mediaId\":\"\(UUID().uuidString)\",\"byteSize\":\(invalid)}"
            XCTAssertThrowsError(try JSONDecoder().decode(MessagingMediaMessageIntent.self,
                                                          from: Data(json.utf8))) { error in
                XCTAssertEqual(error as? MessagingFailure, .invalidResponse)
            }
        }
    }

    func testMediaReferenceRejectsZeroAndAboveTheCapThroughDecoding() {
        for invalid in [0, 4_194_305] {
            let json = "{\"mediaId\":\"\(UUID().uuidString)\",\"byteSize\":\(invalid),\"deleted\":false}"
            XCTAssertThrowsError(try JSONDecoder().decode(MessagingMessageMediaReference.self,
                                                          from: Data(json.utf8))) { error in
                XCTAssertEqual(error as? MessagingFailure, .invalidResponse)
            }
        }
    }

    func testMediaReferenceRequiresAnExplicitDeletedFlag() {
        let missing = "{\"mediaId\":\"\(UUID().uuidString)\",\"byteSize\":12}"
        XCTAssertThrowsError(try JSONDecoder().decode(MessagingMessageMediaReference.self,
                                                      from: Data(missing.utf8)))
        let broken = "{\"mediaId\":\"pas-un-uuid\",\"byteSize\":12,\"deleted\":false}"
        XCTAssertThrowsError(try JSONDecoder().decode(MessagingMessageMediaReference.self,
                                                      from: Data(broken.utf8)))
    }

    func testLegacySendDTOWithoutMediaStillDecodesAndMetaDefaultsToNoMedia() throws {
        let json = """
        {"clientMessageId":"\(UUID().uuidString)","ciphertext":{"scheme":"megolm.v1","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[]}
        """
        let dto = try JSONDecoder().decode(MessagingSendDTO.self, from: Data(json.utf8))
        XCTAssertNil(dto.media)
        XCTAssertNil(MessagingMessageMeta().media)
    }

    // MARK: Encodage du POST

    func testMediaMessageEncodesOnlyIdentifierAndSizeWithoutSecretFields() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            let raw = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            XCTAssertEqual(Set(body.keys),
                           Set(["clientMessageId", "ciphertext", "expectedMembersEpoch", "mentionPersonIds", "media"]))
            let media = try XCTUnwrap(body["media"] as? [String: Any])
            XCTAssertEqual(Set(media.keys), Set(["mediaId", "byteSize"]))
            XCTAssertEqual(media["mediaId"] as? String, mediaID.uuidString)
            XCTAssertEqual(media["byteSize"] as? Int, 1_234)
            let envelope = try XCTUnwrap(body["ciphertext"] as? [String: Any])
            XCTAssertEqual(Set(envelope.keys), Set(["scheme", "keyId", "payload"]))
            let response = MediaMessageFixture.receiptJSON(intent: intent, message: UUID(),
                conversation: conversation, account: account, school: school, payload: Data([1, 2, 3]),
                media: "{\"mediaId\":\"\(mediaID)\",\"byteSize\":1234,\"deleted\":false}")
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!,
                                      contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL, transport: wire,
            token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 1_234)
        let ack = try await transport.send(scope: scope, conversationID: conversation,
            body: mediaSend(intent: intent, media: media))
        XCTAssertEqual(ack.media?.mediaID, mediaID)
        XCTAssertEqual(ack.media?.byteSize, 1_234)
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testOrdinaryTextMessageOmitsTheMediaKey() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertFalse(body.keys.contains("media"))
            let response = MediaMessageFixture.receiptJSON(intent: intent, message: UUID(),
                conversation: conversation, account: account, school: school, payload: Data([1, 2, 3]))
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!,
                                      contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let ack = try await transport.send(scope: scope, conversationID: conversation,
            body: MessagingSendDTO(clientMessageId: intent, ciphertext: ciphertext(), mentionPersonIds: []))
        XCTAssertNil(ack.media)
    }

    /// Le chemin direct `send` refuse un sondage + média avant jeton et requête, sans dépendre
    /// de l'entrée `sendMedia` du client.
    func testDirectSendWithPollAndMediaIsRefusedBeforeTokenAndRequest() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            XCTFail("Aucune requête ne doit partir pour un sondage porté par un média")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMediaMessageToken()
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { try await token.accessToken() }, invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)
        do {
            _ = try await transport.send(scope: scope, conversationID: conversation,
                body: mediaSend(intent: UUID(),
                    poll: MessagingPollDraftMeta(allowsMultiple: false, optionIDs: ["o1", "o2"]), media: media))
            XCTFail("Un message ne peut pas porter un sondage et un média")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(token.requests, 0)
    }

    // MARK: Reçu du POST média

    func testMediaReceiptMustCarryTheSameMediaAndSize() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let media = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 1_234)
        let variants: [String?] = [
            nil,
            "{\"mediaId\":\"\(UUID())\",\"byteSize\":1234,\"deleted\":false}",
            "{\"mediaId\":\"\(mediaID)\",\"byteSize\":1235,\"deleted\":false}",
            "{\"mediaId\":\"\(mediaID)\",\"byteSize\":1234}"
        ]
        for variant in variants {
            let wire = RecordingMediaMessageHTTP { request in
                let response = MediaMessageFixture.receiptJSON(intent: intent, message: UUID(),
                    conversation: conversation, account: account, school: school,
                    payload: Data([1, 2, 3]), media: variant)
                return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!,
                                          contentType: "application/json")
            }
            let transport = MessagingHTTPTransport(baseURL: baseURL,
                transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
            do {
                _ = try await transport.send(scope: scope, conversationID: conversation,
                    body: mediaSend(intent: intent, media: media))
                XCTFail("Un reçu sans le même média ne peut pas acquitter l'envoi")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, .invalidResponse, variant ?? "média absent")
            }
        }
    }

    /// Symétrie : une intention SANS média ne peut pas recevoir un reçu qui en porte un.
    func testOrdinarySendRejectsAnUnexpectedMediaReceipt() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            let response = MediaMessageFixture.receiptJSON(intent: intent, message: UUID(),
                conversation: conversation, account: account, school: school, payload: Data([1, 2, 3]),
                media: "{\"mediaId\":\"\(mediaID)\",\"byteSize\":12,\"deleted\":false}")
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!,
                                      contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        do {
            _ = try await transport.send(scope: scope, conversationID: conversation,
                body: MessagingSendDTO(clientMessageId: intent, ciphertext: ciphertext(), mentionPersonIds: []))
            XCTFail("Un reçu média ne correspond pas à une intention sans média")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testMatchingMediaReceiptKeepsTheServerDeletedFactAndReturnsIt() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let media = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 1_234)
        let wire = RecordingMediaMessageHTTP { request in
            let response = MediaMessageFixture.receiptJSON(intent: intent, message: UUID(),
                conversation: conversation, account: account, school: school, payload: Data([1, 2, 3]),
                media: "{\"mediaId\":\"\(mediaID)\",\"byteSize\":1234,\"deleted\":false}")
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!,
                                      contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let ack = try await transport.send(scope: scope, conversationID: conversation,
            body: mediaSend(intent: intent, media: media))
        XCTAssertEqual(ack.clientMessageId, intent)
        let reference = try MessagingMessageMediaReference(mediaID: mediaID, byteSize: 1_234, deleted: false)
        XCTAssertEqual(ack.media, reference)
    }

    // MARK: Historique

    func testHistoryKeepsLegacyNullActiveAndPurgedMediaAndDeletedMessageWithoutCiphertext() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let legacy = UUID(), active = UUID(), purged = UUID(), removed = UUID()
        let activeMedia = UUID(), purgedMedia = UUID(), removedMedia = UUID()
        let item = MediaMessageFixture.itemJSON
        let body = """
        {"data":{"items":[
          \(item(legacy, 1, school, conversation, account, "")),
          \(item(active, 2, school, conversation, account, ",\"media\":{\"mediaId\":\"\(activeMedia)\",\"byteSize\":12,\"deleted\":false}")),
          \(item(purged, 3, school, conversation, account, ",\"media\":{\"mediaId\":\"\(purgedMedia)\",\"byteSize\":34,\"deleted\":true}")),
          {"id":"\(removed)","schoolId":"\(school)","conversationId":"\(conversation)","sequence":4,"clientMessageId":"\(UUID())","senderId":"\(account)","ciphertext":null,"mentionPersonIds":[],"acceptedAt":"2026-11-04T00:00:00Z","deletedForEveryone":true,"media":{"mediaId":"\(removedMedia)","byteSize":56,"deleted":true}}
        ],"nextCursor":null},"context":{"schoolId":"\(school)","actorPersonId":"\(account)","accessEpoch":3}}
        """
        let wire = RecordingMediaMessageHTTP { request in
            SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let page = try await transport.messages(scope: scope, conversationID: conversation, before: nil)
        XCTAssertEqual(page.items.count, 4)
        XCTAssertNil(page.items[0].meta.media)
        let activeReference = try MessagingMessageMediaReference(mediaID: activeMedia, byteSize: 12, deleted: false)
        let purgedReference = try MessagingMessageMediaReference(mediaID: purgedMedia, byteSize: 34, deleted: true)
        let removedReference = try MessagingMessageMediaReference(mediaID: removedMedia, byteSize: 56, deleted: true)
        XCTAssertEqual(page.items[1].meta.media, activeReference)
        XCTAssertEqual(page.items[2].meta.media, purgedReference)
        XCTAssertEqual(page.items[3].meta.media, removedReference)
        XCTAssertNil(page.items[3].ciphertext, "Un message supprimé pour tous ne garde aucun ciphertext")
        XCTAssertTrue(page.items[3].meta.deletedForEveryone)
    }

    func testMediaNullInHistoryMeansNoMedia() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let body = """
        {"data":{"items":[{"id":"\(UUID())","schoolId":"\(school)","conversationId":"\(conversation)","sequence":1,"clientMessageId":"\(UUID())","senderId":"\(account)","ciphertext":{"scheme":"synthetic","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[],"acceptedAt":"2026-11-04T00:00:00Z","media":null}],"nextCursor":null},"context":{"schoolId":"\(school)","actorPersonId":"\(account)","accessEpoch":3}}
        """
        let wire = RecordingMediaMessageHTTP { request in
            SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let page = try await transport.messages(scope: scope, conversationID: conversation, before: nil)
        XCTAssertNil(page.items.first?.meta.media)
    }

    func testInvalidMediaInHistoryFailsClosedWithoutInventingDeleted() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let invalidMedia = [
            "{\"mediaId\":\"\(UUID())\"}",
            "{\"mediaId\":\"\(UUID())\",\"byteSize\":0,\"deleted\":false}",
            "{\"mediaId\":\"\(UUID())\",\"byteSize\":12}",
            "{\"mediaId\":\"pas-un-uuid\",\"byteSize\":12,\"deleted\":false}"
        ]
        for media in invalidMedia {
            let body = """
            {"data":{"items":[{"id":"\(UUID())","schoolId":"\(school)","conversationId":"\(conversation)","sequence":1,"clientMessageId":"\(UUID())","senderId":"\(account)","ciphertext":{"scheme":"synthetic","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[],"acceptedAt":"2026-11-04T00:00:00Z","media":\(media)}],"nextCursor":null},"context":{"schoolId":"\(school)","actorPersonId":"\(account)","accessEpoch":3}}
            """
            let wire = RecordingMediaMessageHTTP { request in
                SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!, contentType: "application/json")
            }
            let transport = MessagingHTTPTransport(baseURL: baseURL,
                transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
            do {
                _ = try await transport.messages(scope: scope, conversationID: conversation, before: nil)
                XCTFail("Un média présent invalide doit échouer fermé, pas devenir nil")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, .invalidResponse, media)
            }
        }
    }

    // MARK: Bornes réelles du corps avec média

    func testMediaSendAtTheEnvelopeBoundStaysUnderTheSixteenKilobyteBody() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let payload = Data(repeating: 0x41, count: 9_000)
        let wire = RecordingMediaMessageHTTP { request in
            let raw = try XCTUnwrap(request.httpBody)
            XCTAssertLessThanOrEqual(raw.count, 16_384)
            XCTAssertGreaterThan(raw.count, 12_000)
            let response = MediaMessageFixture.receiptJSON(intent: intent, message: UUID(),
                conversation: conversation, account: account, school: school, payload: payload,
                media: "{\"mediaId\":\"\(mediaID)\",\"byteSize\":9000,\"deleted\":false}")
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!,
                                      contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 9_000)
        _ = try await transport.send(scope: scope, conversationID: conversation,
            body: mediaSend(intent: intent, payload: payload, media: media))
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testMediaSendBeyondTheEnvelopeBoundIsRefusedBeforeTokenAndRequest() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let payload = Data(repeating: 0x41, count: 9_001)
        let wire = RecordingMediaMessageHTTP { request in
            XCTFail("Aucune requête ne doit partir au-delà de 12 000 caractères base64")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMediaMessageToken()
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { try await token.accessToken() }, invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 9_001)
        do {
            _ = try await transport.send(scope: scope, conversationID: conversation,
                body: mediaSend(intent: UUID(), payload: payload, media: media))
            XCTFail("Un payload au-delà de 12 000 caractères base64 doit être refusé")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(token.requests, 0)
    }

    func testMediaSendBodyBeyondSixteenKilobytesIsRefusedBeforeAnyRequest() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            XCTFail("Aucune requête ne doit partir pour un corps au-delà de 16 Kio")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMediaMessageToken()
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { try await token.accessToken() }, invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 9_000)
        let mentions = (0..<400).map { _ in UUID() }
        do {
            _ = try await transport.send(scope: scope, conversationID: conversation,
                body: mediaSend(intent: UUID(), payload: Data(repeating: 0x41, count: 9_000),
                                mentions: mentions, media: media))
            XCTFail("Un corps au-delà de 16 Kio doit être refusé")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(token.requests, 0)
    }

    // MARK: Refus serveur, paires exactes et chemins existants

    func testMediaRefusalsMapToTheExistingMediaFailuresThroughDirectSend() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let cases: [(Int, String, MessagingMediaTransportFailure)] = [
            (400, "INVALID_MEDIA", .invalidIntent),
            (404, "MEDIA_NOT_FOUND", .notFound),
            (409, "MEDIA_INTENT_CONFLICT", .intentConflict),
            (409, "MEDIA_ALREADY_ATTACHED", .alreadyAttached),
            (409, "MEDIA_SIZE_MISMATCH", .sizeConflict),
            (409, "MEDIA_PURGED", .purged),
            (403, "MESSAGING_DEVICE_REQUIRED", .deviceRequired),
            (503, "MESSAGING_NOT_ENABLED", .unavailable),
            (503, "SERVICE_UNAVAILABLE", .unavailable)
        ]
        for (status, code, expected) in cases {
            let wire = RecordingMediaMessageHTTP { request in
                MediaMessageFixture.errorResponse(status, code: code, url: request.url!)
            }
            let transport = MessagingHTTPTransport(baseURL: baseURL,
                transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
            let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)
            do {
                _ = try await transport.send(scope: scope, conversationID: conversation,
                    body: mediaSend(intent: UUID(), media: media))
                XCTFail("Un refus média n'est pas un succès : \(status) \(code)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, "\(status) \(code)")
            }
        }
    }

    /// Une paire (statut, code) hors contrat ne devient jamais un fait média final : le refus
    /// reste celui du statut HTTP.
    func testMediaMappingRequiresAnExactStatusAndCodePair() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let cases: [(Int, String, MessagingFailure)] = [
            (400, "MEDIA_NOT_FOUND", .unavailable),
            (404, "NOT_FOUND", .conversationUnavailable),
            (409, "MEDIA_NOT_FOUND", .stateConflict),
            (403, "MEDIA_PURGED", .accessChanged),
            (500, "MEDIA_PURGED", .unavailable),
            (503, "MEDIA_PURGED", .unavailable)
        ]
        for (status, code, expected) in cases {
            let wire = RecordingMediaMessageHTTP { request in
                MediaMessageFixture.errorResponse(status, code: code, url: request.url!)
            }
            let transport = MessagingHTTPTransport(baseURL: baseURL,
                transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
            let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)
            do {
                _ = try await transport.send(scope: scope, conversationID: conversation,
                    body: mediaSend(intent: UUID(), media: media))
                XCTFail("Une paire incohérente doit rester un refus : \(status) \(code)")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, expected, "\(status) \(code)")
            }
        }
    }

    /// Un statut 2xx ne déclenche aucun mapping média : le corps doit être un reçu valide.
    func testErrorCodeOnASuccessStatusIsNotAReceiptAndIsNotMapped() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            SchoolHTTPResponse(data: Data("{\"code\":\"MEDIA_PURGED\"}".utf8), status: 200,
                               url: request.url!, contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)
        do {
            _ = try await transport.send(scope: scope, conversationID: conversation,
                body: mediaSend(intent: UUID(), media: media))
            XCTFail("Un corps 200 sans reçu n'est pas un succès média")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .invalidResponse)
        } catch let failure as MessagingMediaTransportFailure {
            XCTFail("Aucun mapping média ne doit s'appliquer sur 2xx : \(failure)")
        }
    }

    /// 401 garde sa priorité : un renouvellement refusé n'est jamais converti en refus média.
    func testMediaCodeOn401AfterRefusedRenewalKeepsAccessChanged() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let token = CountingMediaMessageToken()
        let wire = RecordingMediaMessageHTTP { request in
            MediaMessageFixture.errorResponse(401, code: "MEDIA_PURGED", url: request.url!)
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { try await token.accessToken() }, invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)
        do {
            _ = try await transport.send(scope: scope, conversationID: conversation,
                body: mediaSend(intent: UUID(), media: media))
            XCTFail("Un 401 n'est pas un reçu média")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .accessChanged)
        }
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(token.requests, 1)
    }

    func testMembersChangedAndOrdinaryMessageErrorsKeepTheirExistingMeaning() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)

        let membersWire = RecordingMediaMessageHTTP { request in
            MediaMessageFixture.errorResponse(409, code: "MESSAGING_MEMBERS_CHANGED", url: request.url!)
        }
        let membersTransport = MessagingHTTPTransport(baseURL: baseURL,
            transport: membersWire, token: { "synthetic-token" }, invalidate: { _ in false },
            currentScope: { scope })
        do {
            _ = try await membersTransport.send(scope: scope, conversationID: conversation,
                body: mediaSend(intent: UUID(), media: media))
            XCTFail("Le changement de membres doit rester un refus spécifique")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .membersChanged)
        }

        for (status, code, expected) in [(400, "INVALID_MEDIA", MessagingFailure.unavailable),
                                         (404, "MEDIA_NOT_FOUND", MessagingFailure.conversationUnavailable)] {
            let wire = RecordingMediaMessageHTTP { request in
                MediaMessageFixture.errorResponse(status, code: code, url: request.url!)
            }
            let transport = MessagingHTTPTransport(baseURL: baseURL,
                transport: wire, token: { "synthetic-token" }, invalidate: { _ in false },
                currentScope: { scope })
            do {
                _ = try await transport.send(scope: scope, conversationID: conversation,
                    body: MessagingSendDTO(clientMessageId: UUID(), ciphertext: ciphertext(),
                                           mentionPersonIds: []))
                XCTFail("Un refus ordinaire doit rester un MessagingFailure")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, expected, code)
            }
        }
    }

    // MARK: Origine, scope, 401 et en-têtes

    func testMediaSendRetriesOnceAfter401WithTheSameIntentAndWithoutDeviceHeader() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let token = MediaSequenceToken(["token-one", "token-two"])
        let wire = RecordingMediaMessageHTTP { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Drivy-Device-Id"),
                         "Le POST message réel n'exige aucun header d'appareil")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Drivy-Expected-Person-Id"),
                           account.uuidString.lowercased())
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Drivy-Expected-Access-Epoch"), "3")
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer token-one" {
                return MediaMessageFixture.errorResponse(401, code: "AUTHENTICATION_REQUIRED", url: request.url!)
            }
            let response = MediaMessageFixture.receiptJSON(intent: intent, message: UUID(),
                conversation: conversation, account: account, school: school, payload: Data([1, 2, 3]),
                media: "{\"mediaId\":\"\(mediaID)\",\"byteSize\":1234,\"deleted\":false}")
            return SchoolHTTPResponse(data: Data(response.utf8), status: 200, url: request.url!,
                                      contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire,
            token: { try await token.accessToken() },
            invalidate: { _ in true },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 1_234)
        _ = try await transport.send(scope: scope, conversationID: conversation,
            body: mediaSend(intent: intent, media: media))
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody,
                       "Le même clientMessageID, le même ciphertext et le même média partent au retry")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer token-one")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer token-two")
        XCTAssertEqual(token.requests, 2)
    }

    func testMediaSendRejectsAContextFromAnotherSchool() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            let wrongSchool = UUID()
            let body = """
            {"data":{"id":"\(UUID())","schoolId":"\(wrongSchool)","conversationId":"\(conversation)","sequence":1,"clientMessageId":"\(UUID())","senderId":"\(account)","ciphertext":{"scheme":"megolm.v1","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[],"acceptedAt":"2026-11-04T00:00:00Z","media":{"mediaId":"\(mediaID)","byteSize":10,"deleted":false}},"context":{"schoolId":"\(wrongSchool)","actorPersonId":"\(account)","accessEpoch":3}}
            """
            return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: request.url!,
                                      contentType: "application/json")
        }
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 10)
        do {
            _ = try await transport.send(scope: scope, conversationID: conversation,
                body: mediaSend(intent: UUID(), media: media))
            XCTFail("Un contexte d'une autre école ne peut pas acquitter l'envoi")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
    }
}

private enum MediaMessageFixture {
    static let baseURL = URL(string: "https://api.example.invalid/")!

    static func receiptJSON(intent: UUID, message: UUID, conversation: UUID, account: UUID, school: UUID,
                            payload: Data, media: String? = nil) -> String {
        let mediaPart = media.map { ",\"media\":\($0)" } ?? ""
        return """
        {"data":{"id":"\(message)","schoolId":"\(school)","conversationId":"\(conversation)","sequence":1,"clientMessageId":"\(intent)","senderId":"\(account)","ciphertext":{"scheme":"megolm.v1","keyId":"fixture","payload":"\(payload.base64EncodedString())"},"mentionPersonIds":[],"acceptedAt":"2026-11-04T00:00:00Z"\(mediaPart)},"context":{"schoolId":"\(school)","actorPersonId":"\(account)","accessEpoch":3}}
        """
    }

    static func errorResponse(_ status: Int, code: String, url: URL) -> SchoolHTTPResponse {
        SchoolHTTPResponse(data: Data("{\"code\":\"\(code)\"}".utf8), status: status, url: url,
                           contentType: "application/problem+json")
    }

    static func itemJSON(_ id: UUID, _ sequence: Int, _ school: UUID, _ conversation: UUID,
                         _ account: UUID, _ extra: String) -> String {
        """
        {"id":"\(id)","schoolId":"\(school)","conversationId":"\(conversation)","sequence":\(sequence),"clientMessageId":"\(UUID())","senderId":"\(account)","ciphertext":{"scheme":"synthetic","keyId":"fixture","payload":"AQID"},"mentionPersonIds":[],"acceptedAt":"2026-11-04T00:00:00Z"\(extra)}
        """
    }
}

@MainActor private final class CountingMediaMessageToken: AccessTokenSource {
    private(set) var requests = 0
    func accessToken() async throws -> String {
        requests += 1
        return "synthetic-token"
    }
}

@MainActor private final class MediaSequenceToken: AccessTokenSource {
    private var remaining: [String]
    private(set) var requests = 0
    init(_ tokens: [String]) { remaining = tokens }
    func accessToken() async throws -> String {
        requests += 1
        return remaining.isEmpty ? "synthetic-token" : remaining.removeFirst()
    }
}

private actor RecordingMediaMessageHTTP: SchoolHTTPTransport {
    private let responder: @Sendable (URLRequest) throws -> SchoolHTTPResponse
    private var received: [URLRequest] = []
    init(_ responder: @escaping @Sendable (URLRequest) throws -> SchoolHTTPResponse) {
        self.responder = responder
    }
    func send(_ request: URLRequest) throws -> SchoolHTTPResponse {
        received.append(request)
        return try responder(request)
    }
    func requests() -> [URLRequest] { received }
}
