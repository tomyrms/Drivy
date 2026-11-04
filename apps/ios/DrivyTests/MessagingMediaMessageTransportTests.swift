import XCTest
@testable import Drivy

/// #97 — raccord du média au POST message, côté transport HTTP.
///
/// Ces tests sont ecrits avant l'implementation. Ils ne compilent pas sur Windows :
/// aucune preuve RED/GREEN native n'est revendiquee par ce fichier.
@MainActor
final class MessagingMediaMessageTransportTests: XCTestCase {
    private let baseURL = MediaMessageFixture.baseURL

    private func makeScope(account: UUID, school: UUID) -> MessagingScope {
        MessagingScope(accountID: account, schoolID: school, accessEpoch: 3, apiBaseURL: baseURL.absoluteString)
    }

    private func makePending(intent: UUID, conversation: UUID, payload: Data = Data([1, 2, 3]),
                             mentions: [UUID] = [], poll: MessagingPollDraftMeta? = nil) -> MessagingPending {
        MessagingPending(clientMessageID: intent, conversationID: conversation,
            ciphertext: MessagingCiphertext(scheme: "megolm.v1", keyID: "fixture", payload: payload,
                                            expectedMembersEpoch: 3),
            mentionPersonIDs: mentions, poll: poll)
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
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire,
            token: { "synthetic-token" },
            invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: mediaID, byteSize: 1_234)
        let ack = try await transport.sendMedia(scope: scope,
            pending: makePending(intent: intent, conversation: conversation), media: media)
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
            body: MessagingSendDTO(clientMessageId: intent,
                ciphertext: MessagingCiphertext(scheme: "megolm.v1", keyID: "fixture",
                    payload: Data([1, 2, 3]), expectedMembersEpoch: 3),
                mentionPersonIds: []))
        XCTAssertNil(ack.media)
    }

    func testPollAndMediaAreRefusedBeforeTokenAndRequest() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let wire = RecordingMediaMessageHTTP { request in
            XCTFail("Aucune requete ne doit partir pour un sondage porte par un media")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMediaMessageToken()
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { try await token.accessToken() }, invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)
        do {
            _ = try await transport.sendMedia(scope: scope,
                pending: makePending(intent: UUID(), conversation: conversation,
                    poll: MessagingPollDraftMeta(allowsMultiple: false, optionIDs: ["o1", "o2"])),
                media: media)
            XCTFail("Un message ne peut pas porter un sondage et un media")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .invalidIntent)
        }
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(token.requests, 0)
    }

    // MARK: Recu du POST media

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
                _ = try await transport.sendMedia(scope: scope,
                    pending: makePending(intent: intent, conversation: conversation), media: media)
                XCTFail("Un recu sans le meme media ne peut pas acquitter l'envoi")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, .invalidResponse, variant ?? "media absent")
            }
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
        let ack = try await transport.sendMedia(scope: scope,
            pending: makePending(intent: intent, conversation: conversation), media: media)
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
        XCTAssertNil(page.items[3].ciphertext, "Un message supprime pour tous ne garde aucun ciphertext")
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
                XCTFail("Un media present invalide doit echouer ferme, pas devenir nil")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, .invalidResponse, media)
            }
        }
    }

    // MARK: Bornes reelles du corps avec media

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
        _ = try await transport.sendMedia(scope: scope,
            pending: makePending(intent: intent, conversation: conversation, payload: payload), media: media)
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testMediaSendBeyondTheEnvelopeBoundIsRefusedBeforeTokenAndRequest() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let payload = Data(repeating: 0x41, count: 9_001)
        let wire = RecordingMediaMessageHTTP { request in
            XCTFail("Aucune requete ne doit partir au-dela de 12 000 caracteres base64")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMediaMessageToken()
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { try await token.accessToken() }, invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 9_001)
        do {
            _ = try await transport.sendMedia(scope: scope,
                pending: makePending(intent: UUID(), conversation: conversation, payload: payload), media: media)
            XCTFail("Un payload au-dela de 12 000 caracteres base64 doit etre refuse")
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
            XCTFail("Aucune requete ne doit partir pour un corps au-dela de 16 Kio")
            return SchoolHTTPResponse(data: Data(), status: 200, url: request.url!, contentType: "application/json")
        }
        let token = CountingMediaMessageToken()
        let transport = MessagingHTTPTransport(baseURL: baseURL,
            transport: wire, token: { try await token.accessToken() }, invalidate: { _ in false },
            currentScope: { scope })
        let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 9_000)
        let mentions = (0..<400).map { _ in UUID() }
        do {
            _ = try await transport.sendMedia(scope: scope,
                pending: makePending(intent: UUID(), conversation: conversation,
                    payload: Data(repeating: 0x41, count: 9_000), mentions: mentions), media: media)
            XCTFail("Un corps au-dela de 16 Kio doit etre refuse")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(token.requests, 0)
    }

    // MARK: Refus serveur et preservation des chemins existants

    func testMediaRefusalsMapToTheExistingMediaFailures() async throws {
        let account = UUID(), school = UUID(), conversation = UUID()
        let scope = makeScope(account: account, school: school)
        let cases: [(Int, String, MessagingMediaTransportFailure)] = [
            (400, "INVALID_MEDIA", .invalidIntent),
            (404, "MEDIA_NOT_FOUND", .notFound),
            (409, "MEDIA_INTENT_CONFLICT", .intentConflict),
            (409, "MEDIA_ALREADY_ATTACHED", .alreadyAttached),
            (409, "MEDIA_SIZE_MISMATCH", .sizeConflict),
            (409, "MEDIA_PURGED", .purged),
            (403, "MESSAGING_DEVICE_REQUIRED", .deviceRequired)
        ]
        for (status, code, expected) in cases {
            let wire = RecordingMediaMessageHTTP { request in
                MediaMessageFixture.errorResponse(status, code: code, url: request.url!)
            }
            let transport = MessagingHTTPTransport(baseURL: baseURL,
                transport: wire, token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
            let media = try MessagingMediaMessageIntent(mediaID: UUID(), byteSize: 10)
            do {
                _ = try await transport.sendMedia(scope: scope,
                    pending: makePending(intent: UUID(), conversation: conversation), media: media)
                XCTFail("Un refus media n'est pas un succes : \(code)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, code)
            }
        }
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
            _ = try await membersTransport.sendMedia(scope: scope,
                pending: makePending(intent: UUID(), conversation: conversation), media: media)
            XCTFail("Le changement de membres doit rester un refus specifique")
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
                    body: MessagingSendDTO(clientMessageId: UUID(),
                        ciphertext: MessagingCiphertext(scheme: "megolm.v1", keyID: "fixture",
                            payload: Data([1, 2, 3]), expectedMembersEpoch: 3),
                        mentionPersonIds: []))
                XCTFail("Un refus ordinaire doit rester un MessagingFailure")
            } catch let failure as MessagingFailure {
                XCTAssertEqual(failure, expected, code)
            }
        }
    }

    // MARK: Origine, scope, 401 et en-tetes

    func testMediaSendRetriesOnceAfter401WithTheSameIntentAndWithoutDeviceHeader() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), intent = UUID(), mediaID = UUID()
        let scope = makeScope(account: account, school: school)
        let token = MediaSequenceToken(["token-one", "token-two"])
        let wire = RecordingMediaMessageHTTP { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Drivy-Device-Id"),
                         "Le POST message reel n'exige aucun header d'appareil")
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
        _ = try await transport.sendMedia(scope: scope,
            pending: makePending(intent: intent, conversation: conversation), media: media)
        let requests = await wire.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody,
                       "Le meme clientMessageID, le meme ciphertext et le meme media partent au retry")
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
            _ = try await transport.sendMedia(scope: scope,
                pending: makePending(intent: UUID(), conversation: conversation), media: media)
            XCTFail("Un contexte d'une autre ecole ne peut pas acquitter l'envoi")
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
