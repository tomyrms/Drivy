import XCTest
import CryptoKit
@testable import Drivy

/// Transport binaire des médias (#97, T2b2) : ce que l'adaptateur émet, ce qu'il refuse
/// et ce qu'il ne rend jamais. Le fil est injecté : aucun test ne touche le réseau.
@MainActor
final class MessagingHTTPMediaTransportTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.invalid/")!
    private let device = "DEVICE1234A"

    // MARK: Dépôt

    func testUploadDepositsOnlyTheSealedCiphertextUnderTheMediaPath() async throws {
        let account = UUID(), school = UUID(), conversation = UUID(), media = UUID()
        let scope = MessagingScope(accountID: account, schoolID: school, accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2, 3, 255, 7]), mediaID: media)
        let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))
        let wire = MediaWireRecorder { request, _ in
            mediaJSONReply(request, mediaUploadEnvelope(mediaID: media, byteSize: 5, sha256: digest,
                                                        state: "UPLOADED", scope: scope))
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })

        let receipt = try await transport.upload(sealed, scope: scope, conversationID: conversation)

        XCTAssertEqual(receipt.mediaID, media)
        XCTAssertEqual(receipt.byteSize, 5)
        XCTAssertEqual(receipt.sha256, digest)
        XCTAssertEqual(receipt.state, .uploaded)

        let sent = await wire.recorded()
        XCTAssertEqual(sent.count, 1)
        let only = try XCTUnwrap(sent.first)
        XCTAssertEqual(only.method, "PUT")
        XCTAssertEqual(only.url.absoluteString,
                       "https://api.example.invalid/v1/schools/\(school.uuidString)/messaging/conversations/\(conversation.uuidString)/media/\(media.uuidString)")
        XCTAssertEqual(only.ceiling, .envelope)
        XCTAssertEqual(only.body, sealed.ciphertext)
        XCTAssertEqual(only.headers["Authorization"], "Bearer synthetic-token")
        XCTAssertEqual(only.headers["X-Drivy-Expected-Person-Id"], account.uuidString.lowercased())
        XCTAssertEqual(only.headers["X-Drivy-Expected-Access-Epoch"], "4")
        XCTAssertEqual(only.headers["X-Drivy-Device-Id"], device)
        XCTAssertEqual(only.headers["Content-Type"], "application/octet-stream")
        XCTAssertEqual(only.headers["Content-Length"], "5")
        XCTAssertEqual(only.headers["Accept"], "application/json")
        XCTAssertEqual(only.headers["Cache-Control"], "no-store")
        // Ni nom, ni type MIME, ni clé, ni IV : les octets déposés sont le chiffré seul.
        XCTAssertFalse(only.url.absoluteString.contains(sealed.info.key.k))
        XCTAssertFalse(only.url.absoluteString.contains(sealed.info.iv))
        XCTAssertFalse(only.headers.values.contains { $0.contains(sealed.info.key.k) })
        XCTAssertFalse(String(decoding: only.body, as: UTF8.self).contains("A256CTR"))
        XCTAssertFalse(String(decoding: only.body, as: UTF8.self).contains(sealed.info.key.k))
    }

    func testUploadAcceptsOneByteAndTheFourMebibyteLimitAndRefusesZeroOrBeyond() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let conversation = UUID()

        for size in [1, 4_194_304] {
            let sealed = mediaSealed(Data(repeating: 0x5A, count: size), mediaID: UUID())
            let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))
            let wire = MediaWireRecorder { request, _ in
                mediaJSONReply(request, mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: size,
                                                            sha256: digest, state: "UPLOADED", scope: scope))
            }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            let receipt = try await transport.upload(sealed, scope: scope, conversationID: conversation)
            XCTAssertEqual(receipt.byteSize, size, "\(size)")
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 1, "\(size)")
        }

        for bytes in [Data(), Data(repeating: 0x5A, count: 4_194_305)] {
            let sealed = mediaSealed(bytes, mediaID: UUID())
            let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: conversation)
                XCTFail("\(bytes.count) octets ne sont pas déposables")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .invalidIntent, "\(bytes.count)")
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 0, "\(bytes.count)")
        }
    }

    func testUploadRecognisesAnAttachedReceiptAsADepositAcknowledgementOnly() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([9, 8, 7]), mediaID: UUID())
        let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))
        let wire = MediaWireRecorder { request, _ in
            mediaJSONReply(request, mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 3,
                                                        sha256: digest, state: "ATTACHED", scope: scope))
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
        let receipt = try await transport.upload(sealed, scope: scope, conversationID: UUID())
        XCTAssertEqual(receipt.state, .attached)
    }

    func testUploadRefusesAReceiptWhoseIdentitySizeHashOrStateDiffers() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([4, 5, 6, 7]), mediaID: UUID())
        let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))

        let cases: [(String, String, MessagingMediaTransportFailure)] = [
            ("identifiant",
             mediaUploadEnvelope(mediaID: UUID(), byteSize: 4, sha256: digest, state: "UPLOADED", scope: scope), .invalidResponse),
            ("taille",
             mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 5, sha256: digest, state: "UPLOADED", scope: scope), .invalidResponse),
            ("hash",
             mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 4, sha256: String(repeating: "0", count: 64),
                                 state: "UPLOADED", scope: scope), .integrityMismatch),
            ("hash mal formé",
             mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 4, sha256: "ABC", state: "UPLOADED", scope: scope), .invalidResponse),
            ("état purgé",
             mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 4, sha256: digest, state: "PURGED", scope: scope), .purged),
            ("état inconnu",
             mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 4, sha256: digest, state: "DONE", scope: scope), .invalidResponse),
        ]
        for (label, body, expected) in cases {
            let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, body) }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
                XCTFail("reçu refusé : \(label)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, label)
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 1, label)
        }
    }

    func testUploadRefusesAReceiptFromAnotherContext() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))
        let foreignScope = MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
                                          accessEpoch: scope.accessEpoch + 1, apiBaseURL: baseURL.absoluteString)
        let wire = MediaWireRecorder { request, _ in
            mediaJSONReply(request, mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 2,
                                                        sha256: digest, state: "UPLOADED", scope: foreignScope))
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
        do {
            _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
            XCTFail("Un reçu d'une autre époque ne confirme rien")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
    }

    func testUploadRefusesAnInconsistentSealBeforeAnyNetworkCall() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let inconsistent = MessagingSealedMedia(mediaID: UUID(), ciphertext: Data([1, 2, 3]),
            info: MessagingMediaEncryptionInfo(key: Data(repeating: 0x2A, count: 32),
                                               iv: Data(repeating: 0, count: 16),
                                               sha256: Data(SHA256.hash(data: Data([9, 9, 9])))))
        let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") }
        let diagnostics = MessagingDiagnostics()
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, diagnostics: diagnostics, currentScope: { scope })
        do {
            _ = try await transport.upload(inconsistent, scope: scope, conversationID: UUID())
            XCTFail("Un sceau dont le hash ne couvre pas le chiffré ne part pas")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .invalidIntent)
        }
        let attempts = await wire.count()
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(diagnostics.last, "MEDIA-PUT-M-HASH")
    }

    func testUploadDownloadAndCancelRefuseAnInvalidDeviceIdentifierBeforeNetwork() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1]), mediaID: UUID())
        for identifier in ["device1234a", "SHORT", String(repeating: "A", count: 33), "DEVICE-1234"] {
            let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") }
            let diagnostics = MessagingDiagnostics()
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: identifier,
                tokenSource: MediaTokenFixture(), wire: wire, diagnostics: diagnostics, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
                XCTFail("device refusé : \(identifier)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .invalidIntent, identifier)
            }
            do {
                _ = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
                XCTFail("device refusé : \(identifier)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .invalidIntent, identifier)
            }
            do {
                try await transport.cancel(mediaID: UUID(), scope: scope, conversationID: UUID())
                XCTFail("device refusé : \(identifier)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .invalidIntent, identifier)
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 0, identifier)
            XCTAssertEqual(diagnostics.last, "MEDIA-PUT-M-DEVICE", identifier)
        }
    }

    func testUploadMapsEveryServerRefusalToADistinctFailureWithoutRetrying() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let cases: [(Int, String, MessagingMediaTransportFailure)] = [
            (400, "INVALID_MEDIA", .invalidIntent),
            (413, "PAYLOAD_TOO_LARGE", .tooLarge),
            (415, "UNSUPPORTED_MEDIA_TYPE", .invalidIntent),
            (403, "ACCESS_DENIED", .accessChanged),
            (403, "MESSAGING_DEVICE_REQUIRED", .deviceRequired),
            (404, "MEDIA_NOT_FOUND", .notFound),
            (409, "MEDIA_PURGED", .purged),
            (409, "MEDIA_INTENT_CONFLICT", .intentConflict),
            (409, "MEDIA_SIZE_MISMATCH", .sizeConflict),
            (409, "MEDIA_ALREADY_ATTACHED", .alreadyAttached),
            (409, "CONCURRENT_REQUEST", .stateConflict),
            (503, "MESSAGING_NOT_ENABLED", .unavailable),
        ]
        for (status, code, expected) in cases {
            let wire = MediaWireRecorder { request, _ in
                mediaJSONReply(request, "{\"code\":\"\(code)\"}", status: status,
                               contentType: "application/problem+json")
            }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
                XCTFail("\(status) \(code)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, "\(status) \(code)")
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 1, "\(status) \(code)")
        }
    }

    func testUploadRefusesInvalidStatusContentTypeOrBody() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))
        let envelope = mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 2, sha256: digest,
                                           state: "UPLOADED", scope: scope)
        let replies: [(String, @Sendable (URLRequest) -> MessagingMediaHTTPResponse)] = [
            ("statut 201", { mediaJSONReply($0, envelope, status: 201) }),
            ("type texte", { mediaJSONReply($0, envelope, contentType: "text/plain") }),
            ("corps vide", { mediaJSONReply($0, "") }),
            ("enveloppe partielle", { mediaJSONReply($0, "{\"data\":{}}") }),
        ]
        for (label, reply) in replies {
            let wire = MediaWireRecorder { request, _ in reply(request) }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
                XCTFail("réponse refusée : \(label)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .invalidResponse, label)
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 1, label)
        }
    }

    func testUploadRenewsOnceOnUnauthorizedWithTheSameBytesAndIdentifier() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2, 3, 4]), mediaID: UUID())
        let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))
        let token = MediaTokenFixture()
        let wire = MediaWireRecorder { request, index in
            if index == 0 {
                return mediaJSONReply(request, "{\"code\":\"AUTHENTICATION_REQUIRED\"}", status: 401,
                                      contentType: "application/problem+json")
            }
            return mediaJSONReply(request, mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 4,
                                                               sha256: digest, state: "UPLOADED", scope: scope))
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: token, wire: wire, currentScope: { scope })
        let receipt = try await transport.upload(sealed, scope: scope, conversationID: UUID())
        XCTAssertEqual(receipt.mediaID, sealed.mediaID)

        let sent = await wire.recorded()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].body, sealed.ciphertext)
        XCTAssertEqual(sent[1].body, sealed.ciphertext)
        XCTAssertEqual(sent[0].url, sent[1].url)
        XCTAssertEqual(sent[0].headers["Authorization"], "Bearer synthetic-token")
        XCTAssertEqual(sent[1].headers["Authorization"], "Bearer synthetic-renewed")
        XCTAssertEqual(token.invalidated, ["synthetic-token"])
    }

    func testNoRetryWhenTheTokenCannotBeRenewedOrTheServerRefusesTwice() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())

        for renews in [false, true] {
            let wire = MediaWireRecorder { request, _ in
                mediaJSONReply(request, "{\"code\":\"AUTHENTICATION_REQUIRED\"}", status: 401,
                               contentType: "application/problem+json")
            }
            let token = MediaTokenFixture(renews: renews)
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: token, wire: wire, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
                XCTFail("Un 401 n'est pas un dépôt")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .accessChanged, "\(renews)")
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, renews ? 2 : 1, "\(renews)")
        }
    }

    func testTransportFailureBecomesUnavailableAndIsNeverRetried() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let wire = MediaWireRecorder { _, _ in throw URLError(.timedOut) }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
        do {
            _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
            XCTFail("Un délai dépassé n'est pas un succès")
        } catch let error as MessagingMediaTransportFailure {
            XCTAssertEqual(error, .unavailable)
        }
        let attempts = await wire.count()
        XCTAssertEqual(attempts, 1)
    }

    func testCancellationStaysACancellationAndNotAFailure() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let failures: [(String, @Sendable (URLRequest, Int) throws -> MessagingMediaHTTPResponse)] = [
            ("CancellationError", { _, _ in throw CancellationError() }),
            ("URLError.cancelled", { _, _ in throw URLError(.cancelled) }),
        ]
        for (label, failure) in failures {
            let wire = MediaWireRecorder(failure)
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
                XCTFail("Une annulation n'est pas une réponse : \(label)")
            } catch is CancellationError {
            } catch {
                XCTFail("Une annulation reste une CancellationError : \(label)")
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 1, label)
        }
    }

    func testForeignOriginOrBaseURLIsRefusedBeforeNetwork() async throws {
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let conversation = UUID()
        let otherBase = URL(string: "https://other.example.invalid/")!
        let insecureBase = URL(string: "http://api.example.invalid/")!
        let cases: [(URL, MessagingScope)] = [
            (baseURL, MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                     apiBaseURL: otherBase.absoluteString)),
            (insecureBase, MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                          apiBaseURL: insecureBase.absoluteString)),
        ]
        for (base, scope) in cases {
            let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") }
            let transport = MessagingHTTPMediaTransport.using(baseURL: base, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: conversation)
                XCTFail("origine refusée")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .contextChanged)
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 0)
        }
    }

    func testLeavingAccountSchoolOrEpochDuringTheTransferNeverReturnsTheResponse() async throws {
        let sealed = mediaSealed(Data([1, 2, 3]), mediaID: UUID())
        let conversation = UUID()

        for moved in ["compte", "école", "époque"] {
            let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4,
                                       apiBaseURL: baseURL.absoluteString)
            let digest = mediaHex(SHA256.hash(data: sealed.ciphertext))
            let box = MediaScopeBox(scope)
            let next: MessagingScope
            switch moved {
            case "compte":
                next = MessagingScope(accountID: UUID(), schoolID: scope.schoolID, accessEpoch: 4,
                                      apiBaseURL: baseURL.absoluteString)
            case "école":
                next = MessagingScope(accountID: scope.accountID, schoolID: UUID(), accessEpoch: 4,
                                      apiBaseURL: baseURL.absoluteString)
            default:
                next = MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
                                      accessEpoch: scope.accessEpoch + 1, apiBaseURL: baseURL.absoluteString)
            }
            let wire = MediaWireRecorder { request, _ in
                box.value = next
                return mediaJSONReply(request, mediaUploadEnvelope(mediaID: sealed.mediaID, byteSize: 3,
                                                                   sha256: digest, state: "UPLOADED", scope: scope))
            }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { box.value })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: conversation)
                XCTFail("réponse tardive rendue : \(moved)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, .contextChanged, moved)
            }
        }
    }

    func testScopeChangeDuringTokenRenewalRefusesTheSecondAttempt() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let box = MediaScopeBox(scope)
        let token = MediaTokenFixture(box: box)
        let wire = MediaWireRecorder { request, _ in
            mediaJSONReply(request, "{\"code\":\"AUTHENTICATION_REQUIRED\"}", status: 401,
                           contentType: "application/problem+json")
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: token, wire: wire, currentScope: { box.value })
        do {
            _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
            XCTFail("Le contexte a changé pendant le renouvellement")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
        let attempts = await wire.count()
        XCTAssertEqual(attempts, 1, "Aucun second paquet après un changement pendant l'invalidation")
        XCTAssertEqual(token.requests, 1, "Aucun renouvellement demandé après un changement pendant l'invalidation")
        XCTAssertEqual(token.invalidated, ["synthetic-token"])
    }

    func testAnAlreadyCancelledTaskNeverReachesTheTokenSource() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let token = MediaTokenFixture()
        let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: token, wire: wire, currentScope: { scope })
        // Annulation posée avant le premier `await` de la tâche : la source de jeton n'est
        // pas consultée et aucun paquet ne part.
        let call = Task { () -> Void in
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
        }
        do {
            try await call.value
            XCTFail("Une tâche annulée ne dépose rien")
        } catch is CancellationError {
        } catch {
            XCTFail("L'annulation reste une CancellationError")
        }
        XCTAssertEqual(token.requests, 0)
        let sent = await wire.count()
        XCTAssertEqual(sent, 0)
    }

    func testTokenFailuresAreMappedClosedWithoutTransportingTheirPayload() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let sentinel = "SENTINEL-TOKEN-LEAK-42"
        let cases: [(String, @MainActor @Sendable () async throws -> String, MessagingMediaTransportFailure, String)] = [
            ("panne",
             { throw NSError(domain: "sentinel-domain", code: 7,
                             userInfo: [NSLocalizedDescriptionKey: sentinel]) },
             .unavailable, "MEDIA-PUT"),
            ("réauthentification", { throw IdentityFailure.reauthentication }, .accessChanged, "MEDIA-PUT"),
        ]
        for (label, source, expected, code) in cases {
            let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") }
            let diagnostics = MessagingDiagnostics()
            let transport = MessagingHTTPMediaTransport(baseURL: baseURL, deviceID: device, wire: wire,
                diagnostics: diagnostics, token: source, invalidate: { _ in false }, currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
                XCTFail("Une source de jeton en échec n'est pas un dépôt : \(label)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, label)
                XCTAssertFalse(String(describing: failure).contains(sentinel), label)
                XCTAssertFalse(String(reflecting: failure).contains(sentinel), label)
            }
            let sent = await wire.count()
            XCTAssertEqual(sent, 0, label)
            XCTAssertEqual(diagnostics.last, code, label)
            assertFixedCode(diagnostics.last, scope: scope, sealed: sealed)
        }
    }

    func testCancellationFromTheTokenSourceStaysACancellation() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2]), mediaID: UUID())
        let cases: [(String, @MainActor @Sendable () async throws -> String)] = [
            ("CancellationError", { throw CancellationError() }),
            ("URLError.cancelled", { throw URLError(.cancelled) }),
        ]
        for (label, source) in cases {
            let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") }
            let transport = MessagingHTTPMediaTransport(baseURL: baseURL, deviceID: device, wire: wire,
                diagnostics: MessagingDiagnostics(), token: source, invalidate: { _ in false },
                currentScope: { scope })
            do {
                _ = try await transport.upload(sealed, scope: scope, conversationID: UUID())
                XCTFail("Une annulation de la source de jeton n'est pas un dépôt : \(label)")
            } catch is CancellationError {
            } catch {
                XCTFail("L'annulation reste une CancellationError : \(label)")
            }
            let sent = await wire.count()
            XCTAssertEqual(sent, 0, label)
        }
    }

    // MARK: Téléchargement

    func testDownloadVerifiesHeadersSizeAndHashBeforeReturningTheCiphertext() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let conversation = UUID(), media = UUID()
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 1, 2, 3])
        let digest = mediaHex(SHA256.hash(data: bytes))
        let wire = MediaWireRecorder { request, _ in
            mediaBinaryReply(request, bytes, declared: bytes.count, school: scope.schoolID.uuidString,
                             epoch: "4", sha: digest)
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
        let data = try await transport.download(mediaID: media, scope: scope, conversationID: conversation)
        XCTAssertEqual(data, bytes)

        let sent = await wire.recorded()
        XCTAssertEqual(sent.count, 1)
        let only = try XCTUnwrap(sent.first)
        XCTAssertEqual(only.method, "GET")
        XCTAssertEqual(only.url.absoluteString,
                       "https://api.example.invalid/v1/schools/\(scope.schoolID.uuidString)/messaging/conversations/\(conversation.uuidString)/media/\(media.uuidString)")
        XCTAssertEqual(only.ceiling, .media)
        XCTAssertEqual(only.headers["Accept"], "application/octet-stream")
        XCTAssertEqual(only.headers["X-Drivy-Device-Id"], device)
        XCTAssertTrue(only.body.isEmpty)
    }

    func testDownloadRefusesMissingOrInconsistentContextHeaders() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let bytes = Data([1, 2, 3])
        let digest = mediaHex(SHA256.hash(data: bytes))
        let cases: [(String, String?, String?, String?, MessagingMediaTransportFailure)] = [
            ("école absente", nil, "4", digest, .invalidResponse),
            ("école étrangère", UUID().uuidString, "4", digest, .contextChanged),
            ("époque absente", scope.schoolID.uuidString, nil, digest, .invalidResponse),
            ("époque étrangère", scope.schoolID.uuidString, "5", digest, .contextChanged),
            ("époque illisible", scope.schoolID.uuidString, "quatre", digest, .invalidResponse),
            ("hash absent", scope.schoolID.uuidString, "4", nil, .invalidResponse),
            ("hash mal formé", scope.schoolID.uuidString, "4", "ABC", .invalidResponse),
        ]
        for (label, school, epoch, sha, expected) in cases {
            let wire = MediaWireRecorder { request, _ in
                mediaBinaryReply(request, bytes, declared: bytes.count, school: school, epoch: epoch, sha: sha)
            }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
                XCTFail("en-tête refusé : \(label)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, label)
            }
        }
    }

    func testDownloadRefusesAnAbsentWrongOrOutOfRangeDeclaredSize() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let digest = mediaHex(SHA256.hash(data: Data([1, 2, 3])))
        let cases: [(String, Int?, Int, MessagingMediaTransportFailure)] = [
            ("taille absente", nil, 3, .invalidResponse),
            ("taille différente", 2, 3, .invalidResponse),
            ("taille nulle", 0, 0, .invalidResponse),
            ("au-delà du plafond", 4_194_305, 3, .tooLarge),
        ]
        for (label, declared, bodyCount, expected) in cases {
            let body = Data(repeating: 0x11, count: bodyCount)
            let wire = MediaWireRecorder { request, _ in
                mediaBinaryReply(request, body, declared: declared, school: scope.schoolID.uuidString,
                                 epoch: "4", sha: digest)
            }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
                XCTFail("taille refusée : \(label)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, label)
            }
        }
    }

    func testDownloadRefusesACorruptedBodyAndReturnsNothing() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let bytes = Data([1, 2, 3])
        let otherDigest = mediaHex(SHA256.hash(data: Data([9, 9, 9])))
        let diagnostics = MessagingDiagnostics()
        let wire = MediaWireRecorder { request, _ in
            mediaBinaryReply(request, bytes, declared: bytes.count, school: scope.schoolID.uuidString,
                             epoch: "4", sha: otherDigest)
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, diagnostics: diagnostics, currentScope: { scope })
        do {
            let data = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
            XCTFail("Données partielles rendues : \(data.count)")
        } catch let failure as MessagingMediaTransportFailure {
            XCTAssertEqual(failure, .integrityMismatch)
        }
        XCTAssertEqual(diagnostics.last, "MEDIA-GET-M-INTEGRITY")
    }

    func testDownloadRefusesAnotherContentTypeAForeignFinalURLOrAStatus() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let bytes = Data([1, 2, 3])
        let digest = mediaHex(SHA256.hash(data: bytes))
        let jsonReply = MediaWireRecorder { request, _ in
            mediaJSONReply(request, "{}", contentType: "application/json")
        }
        let foreignURL = URL(string: "https://api.example.invalid/v1/other")!
        let wrongURL = MediaWireRecorder { request, _ in
            mediaBinaryReply(request, bytes, declared: 3, school: scope.schoolID.uuidString,
                             epoch: "4", sha: digest, url: foreignURL)
        }
        let refused = MediaWireRecorder { request, _ in
            mediaJSONReply(request, "{\"code\":\"MEDIA_NOT_FOUND\"}", status: 404,
                           contentType: "application/problem+json")
        }
        let cases: [(String, any MessagingMediaHTTPWire, MessagingMediaTransportFailure)] = [
            ("type JSON", jsonReply, .invalidResponse),
            ("URL finale étrangère", wrongURL, .invalidResponse),
            ("statut 404", refused, .notFound),
        ]
        for (label, wire, expected) in cases {
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
                XCTFail("réponse refusée : \(label)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, label)
            }
        }
    }

    func testDownloadRenewsOnceOnUnauthorizedAndKeepsTheSameRequest() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let bytes = Data([7, 7])
        let digest = mediaHex(SHA256.hash(data: bytes))
        let wire = MediaWireRecorder { request, index in
            if index == 0 {
                return mediaJSONReply(request, "{\"code\":\"AUTHENTICATION_REQUIRED\"}", status: 401,
                                      contentType: "application/problem+json")
            }
            return mediaBinaryReply(request, bytes, declared: 2, school: scope.schoolID.uuidString,
                                    epoch: "4", sha: digest)
        }
        let token = MediaTokenFixture()
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: token, wire: wire, currentScope: { scope })
        let data = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
        XCTAssertEqual(data, bytes)
        let sent = await wire.recorded()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].url, sent[1].url)
        XCTAssertEqual(token.invalidated.count, 1)
    }

    func testDownloadRefusesADeviceRefusalDistinctlyFromAnAccessChange() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let cases: [(Int, String, MessagingMediaTransportFailure)] = [
            (403, "MESSAGING_DEVICE_REQUIRED", .deviceRequired),
            (403, "ACCESS_DENIED", .accessChanged),
            (503, "MESSAGING_NOT_ENABLED", .unavailable),
        ]
        for (status, code, expected) in cases {
            let wire = MediaWireRecorder { request, _ in
                mediaJSONReply(request, "{\"code\":\"\(code)\"}", status: status,
                               contentType: "application/problem+json")
            }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                _ = try await transport.download(mediaID: UUID(), scope: scope, conversationID: UUID())
                XCTFail(code)
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, code)
            }
        }
    }

    // MARK: Annulation

    func testCancelSucceedsOnlyAfterACoherentTwoHundred() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let conversation = UUID(), media = UUID()
        let wire = MediaWireRecorder { request, _ in
            mediaJSONReply(request, mediaCancelEnvelope(mediaID: media, deleted: true, scope: scope))
        }
        let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
        try await transport.cancel(mediaID: media, scope: scope, conversationID: conversation)

        let sent = await wire.recorded()
        XCTAssertEqual(sent.count, 1)
        let only = try XCTUnwrap(sent.first)
        XCTAssertEqual(only.method, "DELETE")
        XCTAssertEqual(only.ceiling, .envelope)
        XCTAssertEqual(only.url.absoluteString,
                       "https://api.example.invalid/v1/schools/\(scope.schoolID.uuidString)/messaging/conversations/\(conversation.uuidString)/media/\(media.uuidString)")
        XCTAssertEqual(only.headers["X-Drivy-Device-Id"], device)
        XCTAssertEqual(only.headers["Accept"], "application/json")
    }

    func testCancelNeverTreatsAnAttachedConflictAsCancellation() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let media = UUID()
        let cases: [(Int, String, MessagingMediaTransportFailure)] = [
            (409, "MEDIA_ALREADY_ATTACHED", .alreadyAttached),
            (409, "MEDIA_PURGED", .purged),
            (404, "MEDIA_NOT_FOUND", .notFound),
            (503, "SERVICE_UNAVAILABLE", .unavailable),
        ]
        for (status, code, expected) in cases {
            let wire = MediaWireRecorder { request, _ in
                mediaJSONReply(request, "{\"code\":\"\(code)\"}", status: status,
                               contentType: "application/problem+json")
            }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                try await transport.cancel(mediaID: media, scope: scope, conversationID: UUID())
                XCTFail("\(status) \(code) n'est pas une annulation")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, "\(status) \(code)")
            }
            let attempts = await wire.count()
            XCTAssertEqual(attempts, 1)
        }
    }

    func testCancelRefusesAnIncoherentEnvelopeOrAForeignContext() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let media = UUID()
        let foreignScope = MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
                                          accessEpoch: 9, apiBaseURL: baseURL.absoluteString)
        let cases: [(String, Int, String, MessagingMediaTransportFailure)] = [
            ("deleted faux", 200, mediaCancelEnvelope(mediaID: media, deleted: false, scope: scope), .invalidResponse),
            ("identifiant étranger", 200, mediaCancelEnvelope(mediaID: UUID(), deleted: true, scope: scope), .invalidResponse),
            ("contexte étranger", 200, mediaCancelEnvelope(mediaID: media, deleted: true, scope: foreignScope), .contextChanged),
            ("statut 204", 204, "", .invalidResponse),
        ]
        for (label, status, body, expected) in cases {
            let wire = MediaWireRecorder { request, _ in mediaJSONReply(request, body, status: status) }
            let transport = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
                tokenSource: MediaTokenFixture(), wire: wire, currentScope: { scope })
            do {
                try await transport.cancel(mediaID: media, scope: scope, conversationID: UUID())
                XCTFail("enveloppe refusée : \(label)")
            } catch let failure as MessagingMediaTransportFailure {
                XCTAssertEqual(failure, expected, label)
            }
        }
    }

    // MARK: Diagnostics

    func testDiagnosticsStayInsideTheFixedVocabularyAndCarryNoIdentifier() async throws {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 4, apiBaseURL: baseURL.absoluteString)
        let sealed = mediaSealed(Data([1, 2, 3]), mediaID: UUID())
        let otherDigest = mediaHex(SHA256.hash(data: Data([9, 9, 9])))

        // Dépôt refusé pour cause de purge côté serveur.
        let purgeDiagnostics = MessagingDiagnostics()
        let purged = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: MediaWireRecorder { request, _ in
                mediaJSONReply(request, "{\"code\":\"MEDIA_PURGED\"}", status: 409,
                               contentType: "application/problem+json")
            }, diagnostics: purgeDiagnostics, currentScope: { scope })
        _ = try? await purged.upload(sealed, scope: scope, conversationID: UUID())
        XCTAssertEqual(purgeDiagnostics.last, "MEDIA-PUT-M-PURGED")
        assertFixedCode(purgeDiagnostics.last, scope: scope, sealed: sealed)

        // Annulation refusée parce que le média est déjà rattaché : jamais un succès.
        let cancelDiagnostics = MessagingDiagnostics()
        let attached = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: MediaWireRecorder { request, _ in
                mediaJSONReply(request, "{\"code\":\"MEDIA_ALREADY_ATTACHED\"}", status: 409,
                               contentType: "application/problem+json")
            }, diagnostics: cancelDiagnostics, currentScope: { scope })
        _ = try? await attached.cancel(mediaID: sealed.mediaID, scope: scope, conversationID: UUID())
        XCTAssertEqual(cancelDiagnostics.last, "MEDIA-DELETE-M-STATE")
        assertFixedCode(cancelDiagnostics.last, scope: scope, sealed: sealed)

        // Téléchargement corrompu : l'intégrité n'est pas celle annoncée.
        let integrityDiagnostics = MessagingDiagnostics()
        let corrupted = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: MediaWireRecorder { request, _ in
                mediaBinaryReply(request, sealed.ciphertext, declared: 3,
                                 school: scope.schoolID.uuidString, epoch: "4", sha: otherDigest)
            }, diagnostics: integrityDiagnostics, currentScope: { scope })
        _ = try? await corrupted.download(mediaID: sealed.mediaID, scope: scope, conversationID: UUID())
        XCTAssertEqual(integrityDiagnostics.last, "MEDIA-GET-M-INTEGRITY")
        assertFixedCode(integrityDiagnostics.last, scope: scope, sealed: sealed)

        // Taille refusée avant réseau : la cause est la taille, pas le réseau.
        let sizeDiagnostics = MessagingDiagnostics()
        let oversized = MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: device,
            tokenSource: MediaTokenFixture(), wire: MediaWireRecorder { request, _ in mediaJSONReply(request, "{}") },
            diagnostics: sizeDiagnostics, currentScope: { scope })
        _ = try? await oversized.upload(mediaSealed(Data(), mediaID: sealed.mediaID), scope: scope,
                                        conversationID: UUID())
        XCTAssertEqual(sizeDiagnostics.last, "MEDIA-PUT-M-SIZE")
        assertFixedCode(sizeDiagnostics.last, scope: scope, sealed: sealed)
    }

    // MARK: Aides

    private func assertFixedCode(_ code: String?, scope: MessagingScope, sealed: MessagingSealedMedia) {
        let value = code ?? ""
        XCTAssertFalse(value.isEmpty)
        XCTAssertTrue(MessagingDiagnostics.isSafe(value), value)
        XCTAssertFalse(value.contains(scope.schoolID.uuidString.lowercased()))
        XCTAssertFalse(value.contains(scope.accountID.uuidString.lowercased()))
        XCTAssertFalse(value.contains(sealed.mediaID.uuidString.lowercased()))
        XCTAssertFalse(value.contains(sealed.info.hashes.sha256))
        XCTAssertFalse(value.contains("/"))
        XCTAssertFalse(value.contains("http"))
    }
}

// MARK: - Fixtures non isolées (capturables par les closures @Sendable)

private func mediaSealed(_ ciphertext: Data, mediaID: UUID) -> MessagingSealedMedia {
    MessagingSealedMedia(mediaID: mediaID, ciphertext: ciphertext,
        info: MessagingMediaEncryptionInfo(key: Data(repeating: 0x2A, count: 32),
                                           iv: Data(repeating: 0, count: 16),
                                           sha256: Data(SHA256.hash(data: ciphertext))))
}

private func mediaHex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

private func mediaUploadEnvelope(mediaID: UUID, byteSize: Int, sha256: String, state: String,
                                 scope: MessagingScope) -> String {
    """
    {"data":{"mediaId":"\(mediaID.uuidString.lowercased())","byteSize":\(byteSize),"sha256":"\(sha256)","state":"\(state)"},"context":{"schoolId":"\(scope.schoolID.uuidString)","actorPersonId":"\(scope.accountID.uuidString)","accessEpoch":\(scope.accessEpoch)},"requestId":"\(UUID().uuidString)","serverTime":"2026-11-04T12:00:00.000Z"}
    """
}

private func mediaCancelEnvelope(mediaID: UUID, deleted: Bool, scope: MessagingScope) -> String {
    """
    {"data":{"mediaId":"\(mediaID.uuidString.lowercased())","deleted":\(deleted)},"context":{"schoolId":"\(scope.schoolID.uuidString)","actorPersonId":"\(scope.accountID.uuidString)","accessEpoch":\(scope.accessEpoch)},"requestId":"\(UUID().uuidString)","serverTime":"2026-11-04T12:00:00.000Z"}
    """
}

private func mediaJSONReply(_ request: URLRequest, _ body: String, status: Int = 200,
                            contentType: String = "application/json",
                            url: URL? = nil) -> MessagingMediaHTTPResponse {
    let data = Data(body.utf8)
    return MessagingMediaHTTPResponse(status: status, url: url ?? request.url!, contentType: contentType,
        declaredByteSize: data.count, schoolID: nil, accessEpoch: nil, sha256: nil, body: data)
}

private func mediaBinaryReply(_ request: URLRequest, _ data: Data, declared: Int?, school: String?,
                              epoch: String?, sha: String?, status: Int = 200,
                              contentType: String = "application/octet-stream",
                              url: URL? = nil) -> MessagingMediaHTTPResponse {
    MessagingMediaHTTPResponse(status: status, url: url ?? request.url!, contentType: contentType,
        declaredByteSize: declared, schoolID: school, accessEpoch: epoch, sha256: sha, body: data)
}

private actor MediaWireRecorder: MessagingMediaHTTPWire {
    struct Sent: Sendable, Equatable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
        let ceiling: MessagingMediaResponseCeiling
    }

    private var sent: [Sent] = []
    private let responder: @Sendable (URLRequest, Int) throws -> MessagingMediaHTTPResponse

    init(_ responder: @escaping @Sendable (URLRequest, Int) throws -> MessagingMediaHTTPResponse) {
        self.responder = responder
    }

    func send(_ request: URLRequest, ceiling: MessagingMediaResponseCeiling) async throws -> MessagingMediaHTTPResponse {
        sent.append(Sent(method: request.httpMethod ?? "", url: request.url!,
                         headers: request.allHTTPHeaderFields ?? [:],
                         body: request.httpBody ?? Data(), ceiling: ceiling))
        return try responder(request, sent.count - 1)
    }

    func recorded() -> [Sent] { sent }
    func count() -> Int { sent.count }
}

@MainActor
private final class MediaTokenFixture: AccessTokenSource {
    private var current: String
    private let renews: Bool
    private weak var box: MediaScopeBox?
    private(set) var invalidated: [String] = []
    /// Nombre d'entrées réellement effectuées dans la source : sert de barrière aux tests.
    private(set) var requests = 0

    init(_ value: String = "synthetic-token", renews: Bool = true, box: MediaScopeBox? = nil) {
        current = value
        self.renews = renews
        self.box = box
    }

    func accessToken() async throws -> String {
        requests += 1
        return current
    }

    func invalidateAccessToken(_ token: String) async -> Bool {
        invalidated.append(token)
        if let box, let scope = box.value {
            box.value = MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
                                       accessEpoch: scope.accessEpoch + 1, apiBaseURL: scope.apiBaseURL)
        }
        guard renews, token == current else { return false }
        current = "synthetic-renewed"
        return true
    }
}

/// Contexte mutable partagé entre le test, le fil et la source de jeton : changement de compte,
/// d'école ou d'époque pendant une attente réelle.
private final class MediaScopeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: MessagingScope?

    init(_ scope: MessagingScope?) { stored = scope }

    var value: MessagingScope? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
