import XCTest
import CryptoKit
@testable import Drivy

/// Coordinateur média (#97) : ordre persistance/dépôt/attache, reprise, double geste,
/// recomposition et lecture. Tests écrits avant le coordinateur ; **NON EXÉCUTÉS** sur ce
/// poste Windows, sans Xcode ni `swift`. Aucun RED/GREEN natif n'est revendiqué.
///
/// Les primitives média réelles (AES-CTR/SHA-256) sont utilisées ; seuls les transports
/// (Megolm, dépôt binaire, POST message) et les frontières de persistance sont doublés.
/// Aucun sommeil n'est utilisé comme preuve : les suspensions passent par `Gate`.
@MainActor
final class MessagingMediaCoordinatorTests: XCTestCase {
    private let school = UUID()
    private let account = UUID()

    private func makeScope() -> MessagingScope {
        MessagingScope(accountID: account, schoolID: school, accessEpoch: 4,
                       apiBaseURL: "https://api.example.invalid/")
    }

    private func makePrepared(_ data: Data = Data([1, 2, 3, 4]),
                              mime: MessagingMediaAttachment.MIME = .png,
                              name: String = "photo.png",
                              width: Int? = 2, height: Int? = 2) -> MessagingPreparedMedia {
        MessagingPreparedMedia(data: data, mime: mime, name: name, width: width, height: height,
                               thumbnail: mime.isImage ? Data([0x89, 0x50, 0x4E, 0x47]) : nil)
    }

    private func makeSealedContent(
        _ plaintext: Data = Data([1, 2, 3, 4]),
        mime: MessagingMediaAttachment.MIME = .png,
        name: String = "photo.png",
        width: Int? = 2, height: Int? = 2
    ) throws -> (MessagingSealedMedia, MessagingMediaContentV3) {
        let sealed = try AESCTRMediaCryptography().seal(plaintext)
        let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
            mime: mime, name: name, width: width, height: height, file: sealed.info)
        return (sealed, try MessagingMediaContentV3(text: "Légende", media: attachment))
    }

    private func matrixBytes(_ content: MessagingMediaContentV3) throws -> Data {
        try MessagingMediaContent.messageContent(content, mentions: nil)
    }

    private func makeWire(_ messageID: UUID, conversationID: UUID,
                          media: MessagingMessageMediaReference?,
                          deletedForEveryone: Bool = false) -> MessagingWireMessage {
        var meta = MessagingMessageMeta()
        meta.sequence = 12
        meta.media = media
        meta.deletedForEveryone = deletedForEveryone
        return MessagingWireMessage(id: messageID, conversationID: conversationID,
            schoolID: school, senderID: UUID(), acceptedAt: Date(),
            ciphertext: deletedForEveryone ? nil : MessagingCiphertext(scheme: "TEST", keyID: "k",
                                                                       payload: Data("ENVELOPE".utf8)),
            meta: meta)
    }

    private func makeCoordinator(
        scope: MessagingScope,
        preparer: any MessagingMediaPreparing = StubPreparer(),
        outbox: FakeMediaOutbox,
        cache: FakeMediaCache = FakeMediaCache(),
        encryption: FakeMediaEncryption,
        sender: FakeMediaMessageSender,
        transport: FakeMediaTransport
    ) -> MessagingMediaCoordinator {
        MessagingMediaCoordinator(scope: scope, preparer: preparer,
            cryptography: AESCTRMediaCryptography(), outbox: outbox, cache: cache,
            encryption: encryption, sending: sender,
            transportFactory: { transport }, currentScope: { scope })
    }

    // MARK: Préparation et mise en file

    func testPrepareCallsThePrimitiveAndMapsOnlyClosedFailures() async throws {
        let scope = makeScope()
        let expected = makePrepared()
        let failing = StubPreparer(result: expected, failure: .lockedPDF)
        let coordinator = makeCoordinator(scope: scope,
            preparer: failing, outbox: FakeMediaOutbox(), encryption: FakeMediaEncryption(),
            sender: FakeMediaMessageSender(), transport: FakeMediaTransport())

        do {
            _ = try await coordinator.prepare(Data([1]), suggestedName: "contrat.pdf")
            XCTFail("Un PDF verrouillé doit être refusé.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .lockedPDF)
        }

        let cases: [(MessagingMediaPreparationFailure, MessagingMediaRuntimeFailure)] = [
            (.invalidSize, .invalidSize), (.invalidName, .invalidContent),
            (.invalidFormat, .invalidFormat), (.invalidDimensions, .invalidFormat),
            (.unreadable, .unreadable), (.lockedPDF, .lockedPDF),
            (.thumbnailUnavailable, .unreadable)
        ]
        for (source, target) in cases {
            let coordinator = makeCoordinator(scope: scope,
                preparer: StubPreparer(result: expected, failure: source),
                outbox: FakeMediaOutbox(), encryption: FakeMediaEncryption(),
                sender: FakeMediaMessageSender(), transport: FakeMediaTransport())
            do {
                _ = try await coordinator.prepare(Data([1]), suggestedName: "fichier")
                XCTFail("\(source) doit être refusé.")
            } catch let failure as MessagingMediaRuntimeFailure {
                XCTAssertEqual(failure, target, "\(source)")
            }
        }
    }

    func testEnqueuePersistsTheSealThenTheOnlyEnvelopeBeforeAnyUpload() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let client = UUID()
        let order = OrderRecorder()
        let outbox = FakeMediaOutbox(order: order)
        let encryption = FakeMediaEncryption(order: order)
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: encryption, sender: FakeMediaMessageSender(), transport: transport)

        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: client,
            conversationID: conversation, caption: "  ", mentionPersonIDs: [], replyToMessageID: nil)

        XCTAssertEqual(snapshot.clientMessageID, client)
        XCTAssertEqual(snapshot.conversationID, conversation)
        XCTAssertNil(snapshot.caption, "Une légende vide devient absente, sans texte inventé.")
        XCTAssertEqual(snapshot.mime, .png)
        XCTAssertEqual(snapshot.name, "photo.png")
        XCTAssertEqual(snapshot.byteSize, 4)

        let steps = await order.steps
        XCTAssertEqual(steps, ["put:nil", "encrypt", "replaceEnvelope"],
                       "Le sceau et le contenu sont durables avant le chiffrement, l'enveloppe avant tout dépôt.")
        let entries = await outbox.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertNotNil(entries.first?.messageCiphertext, "L'enveloppe Megolm est persistée via le CAS.")
        let uploads = await transport.uploadCount
        XCTAssertEqual(uploads, 0, "La mise en file ne dépose jamais le média.")
    }

    func testEnqueueRefusalAtPersistenceLeavesNoEnvelopeAndNoUpload() async throws {
        let scope = makeScope()
        let order = OrderRecorder()
        let outbox = FakeMediaOutbox(order: order)
        await outbox.putFailure = .protectionUnavailable
        let encryption = FakeMediaEncryption()
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: encryption, sender: FakeMediaMessageSender(), transport: transport)

        do {
            _ = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
                conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
            XCTFail("Une panne de coffre ne doit jamais être un succès.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .protectionUnavailable)
        }

        let encryptCount = await encryption.encryptionCount
        let steps = await order.steps
        let uploads = await transport.uploadCount
        XCTAssertEqual(encryptCount, 0)
        XCTAssertEqual(steps, ["put:nil"])
        XCTAssertEqual(uploads, 0)
    }

    func testEnqueueBoundsCaptionMentionsAndName() async throws {
        let scope = makeScope()
        let coordinator = makeCoordinator(scope: scope, outbox: FakeMediaOutbox(),
            encryption: FakeMediaEncryption(), sender: FakeMediaMessageSender(),
            transport: FakeMediaTransport())

        do {
            _ = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
                conversationID: UUID(), caption: String(repeating: "a", count: 1_001),
                mentionPersonIDs: [], replyToMessageID: nil)
            XCTFail("Une légende au-delà de la borne doit être refusée.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .invalidContent)
        }

        do {
            _ = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
                conversationID: UUID(), caption: nil,
                mentionPersonIDs: Array(repeating: UUID(), count: 9), replyToMessageID: nil)
            XCTFail("Plus de huit mentions doit être refusé.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .invalidContent)
        }

        do {
            _ = try await coordinator.enqueue(makePrepared(name: "   "), clientMessageID: UUID(),
                conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
            XCTFail("Un nom inutilisable doit être refusé.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .invalidContent)
        }
    }

    // MARK: Envoi et reprise

    func testSendUploadsThenPostsThenCleansUpTheDurableIntent() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let order = OrderRecorder()
        let outbox = FakeMediaOutbox(order: order)
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: encryption, sender: sender, transport: transport)
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: conversation, caption: "Bonjour", mentionPersonIDs: [],
            replyToMessageID: nil)

        let delivery = await coordinator.send(clientMessageID: snapshot.clientMessageID)

        guard case .confirmed(let ack, let cleanupPending) = delivery else {
            XCTFail("Un reçu serveur valide doit confirmer l'envoi."); return
        }
        XCTAssertEqual(ack.clientMessageID, snapshot.clientMessageID)
        XCTAssertEqual(ack.conversationID, conversation)
        XCTAssertFalse(cleanupPending)
        let uploads = await transport.uploadCount
        let sends = await sender.sends
        let remaining = await outbox.all()
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(sends.count, 1)
        XCTAssertEqual(sends.first?.media.mediaID, snapshot.mediaID)
        XCTAssertEqual(sends.first?.media.byteSize, snapshot.byteSize)
        XCTAssertTrue(remaining.isEmpty, "L'intention est retirée seulement après l'accusé.")
    }

    func testSendKeepsTheIntentWhenTheServerAnswerIsLost() async throws {
        let scope = makeScope()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        await sender.error = MessagingFailure.unavailable
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: encryption, sender: sender, transport: transport)
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let delivery = await coordinator.send(clientMessageID: snapshot.clientMessageID)

        guard case .pending(let failure) = delivery else {
            XCTFail("Une réponse perdue n'est jamais un succès ni un refus définitif."); return
        }
        XCTAssertEqual(failure, .resultUnknown)
        let remaining = await outbox.all()
        XCTAssertEqual(remaining.count, 1, "L'intention reste pour un renvoi explicite.")
        let encryptCount = await encryption.encryptionCount
        XCTAssertEqual(encryptCount, 1, "Aucun nouveau chiffrement après une réponse perdue.")
    }

    func testConfirmedServerReceiptWithCleanupFailureIsNotAFalseSendFailure() async throws {
        let scope = makeScope()
        let outbox = FakeMediaOutbox()
        await outbox.removeFailure = .protectionUnavailable
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: FakeMediaEncryption(), sender: FakeMediaMessageSender(),
            transport: FakeMediaTransport())
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let delivery = await coordinator.send(clientMessageID: snapshot.clientMessageID)

        guard case .confirmed(_, let cleanupPending) = delivery else {
            XCTFail("Un échec d'effacement local ne peut pas annuler l'accusé serveur."); return
        }
        XCTAssertTrue(cleanupPending)
        let remaining = await outbox.all()
        XCTAssertEqual(remaining.count, 1, "Rien n'est effacé quand l'effacement n'est pas prouvé.")
    }

    func testConcurrentSendOfTheSameGestureRunsOnce() async throws {
        let scope = makeScope()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        let transport = FakeMediaTransport()
        let gate = Gate()
        await transport.uploadGate = gate
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: encryption, sender: sender, transport: transport)
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let first = Task { await coordinator.send(clientMessageID: snapshot.clientMessageID) }
        await gate.waitUntilWaiting()
        let second = await coordinator.send(clientMessageID: snapshot.clientMessageID)
        guard case .pending(let failure) = second else {
            XCTFail("Le second geste concurrent ne doit pas repartir."); return
        }
        XCTAssertEqual(failure, .alreadyInFlight)
        await gate.open()
        let firstDelivery = await first.value
        guard case .confirmed = firstDelivery else {
            XCTFail("Le premier geste doit aboutir."); return
        }
        let uploads = await transport.uploadCount
        let sends = await sender.sends
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(sends.count, 1)
    }

    func testReopeningReusesTheSameRecordAndEnvelopeWithoutReencrypting() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        let transport = FakeMediaTransport()
        let first = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)
        let snapshot = try await first.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: conversation, caption: "Conservé", mentionPersonIDs: [],
            replyToMessageID: nil)
        let before = await outbox.all()
        XCTAssertEqual(before.count, 1)

        let reopened = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)
        let pending = try await reopened.pending(conversationID: conversation)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.mediaID, snapshot.mediaID)
        XCTAssertEqual(pending.first?.caption, "Conservé")

        let delivery = await reopened.send(clientMessageID: snapshot.clientMessageID)
        guard case .confirmed = delivery else {
            XCTFail("La reprise doit envoyer le même enregistrement."); return
        }
        let encryptCount = await encryption.encryptionCount
        XCTAssertEqual(encryptCount, 1, "La réouverture ne réchiffre pas une enveloppe déjà durable.")
        let uploads = await transport.uploaded
        XCTAssertEqual(uploads.first?.mediaID, snapshot.mediaID)
    }

    func testMembersChangedRecomposesOnlyTheEnvelopeAndDoesNotReupload() async throws {
        let scope = makeScope()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        await sender.error = MessagingFailure.membersChanged
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: encryption, sender: sender, transport: transport)
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let refused = await coordinator.send(clientMessageID: snapshot.clientMessageID)
        guard case .pending(let failure) = refused else {
            XCTFail("MEMBERS_CHANGED est un refus explicite."); return
        }
        XCTAssertEqual(failure, .membersChanged)
        let firstUploads = await transport.uploadCount
        let firstEncryptions = await encryption.encryptionCount
        XCTAssertEqual(firstUploads, 1)
        XCTAssertEqual(firstEncryptions, 1)

        await sender.error = nil
        let retried = await coordinator.recomposeAfterMembersChanged(clientMessageID: snapshot.clientMessageID)

        guard case .confirmed = retried else {
            XCTFail("La recomposition explicite doit pouvoir aboutir."); return
        }
        let uploads = await transport.uploadCount
        let encryptions = await encryption.encryptionCount
        XCTAssertEqual(uploads, 1, "Le média n'est pas re-déposé après MEMBERS_CHANGED.")
        XCTAssertEqual(encryptions, 2, "Seule l'enveloppe Megolm est recomposée.")
        let replaces = await outbox.replaceCalls
        XCTAssertEqual(replaces.count, 2)
        XCTAssertEqual(replaces.last?.expected, replaces.first?.replacement)
        let sends = await sender.sends
        XCTAssertEqual(sends.count, 2)
        XCTAssertEqual(sends.last?.pending.ciphertext, replaces.last?.replacement)
    }

    // MARK: Lecture

    func testOpenChecksServerMetadataDownloadsOnceThenServesTheValidatedCache() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let cache = FakeMediaCache()
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        await transport.downloadData = sealed.ciphertext
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), cache: cache, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        let expectedPlaintext = try AESCTRMediaCryptography().open(sealed.ciphertext, info: sealed.info)
        let first = try await coordinator.open(message)
        XCTAssertEqual(first.data, expectedPlaintext)
        XCTAssertEqual(first.mime, .png)
        XCTAssertEqual(first.name, "photo.png")
        XCTAssertEqual(first.width, 2)
        XCTAssertEqual(first.height, 2)

        let firstDownloads = await transport.downloadCount
        let storeCount = await cache.storeCount
        let thumbCount = await cache.thumbnailStoreCount
        XCTAssertEqual(firstDownloads, 1)
        XCTAssertEqual(storeCount, 1, "Le cache n'est écrit qu'après validation.")
        XCTAssertEqual(thumbCount, 1)

        let second = try await coordinator.open(message)
        let secondDownloads = await transport.downloadCount
        XCTAssertEqual(secondDownloads, 1, "Le second rendu vient du cache authentifié.")
        XCTAssertEqual(second.data, first.data)
        XCTAssertEqual(second.thumbnail, Data([9]))
    }

    func testOpenRefusesDeletedOrMismatchedServerMediaWithoutDownloading() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let encryption = FakeMediaEncryption()
        let transport = FakeMediaTransport()
        await transport.downloadData = sealed.ciphertext
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        let tombstone = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: true)
        let otherMedia = try MessagingMessageMediaReference(mediaID: UUID(),
            byteSize: sealed.byteSize, deleted: false)
        let otherSize = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize + 1, deleted: false)
        let cases: [(String, UUID, MessagingMessageMediaReference, MessagingMediaRuntimeFailure)] = [
            ("tombstone", UUID(), tombstone, .removed),
            ("autre média", UUID(), otherMedia, .integrity),
            ("autre taille", UUID(), otherSize, .integrity)
        ]
        for (label, messageID, reference, expected) in cases {
            await encryption.setMatrixContent(bytes, for: messageID)
            let message = makeWire(messageID, conversationID: conversation, media: reference)
            do {
                _ = try await coordinator.open(message)
                XCTFail("Lecture refusée : \(label)")
            } catch let failure as MessagingMediaRuntimeFailure {
                XCTAssertEqual(failure, expected, label)
            }
        }
        let downloads = await transport.downloadCount
        XCTAssertEqual(downloads, 0, "Aucun octet n'est demandé avant la vérification des métadonnées serveur.")
    }

    func testOpenRefusesCorruptedDownloadAndNeverCachesIt() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let cache = FakeMediaCache()
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        var corrupted = sealed.ciphertext
        corrupted[corrupted.startIndex] ^= 0xFF
        await transport.downloadData = corrupted
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), cache: cache, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        do {
            _ = try await coordinator.open(message)
            XCTFail("Un chiffré corrompu ne doit jamais être rendu.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .integrity)
        }
        let storeCount = await cache.storeCount
        XCTAssertEqual(storeCount, 0, "Aucune lecture invalide n'entre dans le cache.")
    }

    func testOpenRefusesAFormatThatDoesNotMatchTheAuthenticatedContent() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent(mime: .jpeg, name: "photo.jpg")
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let cache = FakeMediaCache()
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        await transport.downloadData = sealed.ciphertext
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), cache: cache, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        do {
            _ = try await coordinator.open(message)
            XCTFail("Le type réel doit correspondre au contenu authentifié.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .invalidFormat)
        }
        let storeCount = await cache.storeCount
        XCTAssertEqual(storeCount, 0)
    }

    // MARK: Contexte, annulation et panne de coffre

    func testInvalidatePurgesOnlyTheCacheAndClosesTheRuntime() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let cache = FakeMediaCache()
        await cache.putOriginal(Data([1]), for: UUID())
        let outbox = FakeMediaOutbox()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            cache: cache, encryption: FakeMediaEncryption(),
            sender: FakeMediaMessageSender(), transport: FakeMediaTransport())
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: conversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        await coordinator.invalidate()

        let purges = await cache.purgeAllCount
        let remaining = await outbox.all()
        XCTAssertEqual(purges, 1)
        XCTAssertEqual(remaining.count, 1, "Les intentions à vérifier ne sont jamais purgées par l'invalidation.")
        let delivery = await coordinator.send(clientMessageID: snapshot.clientMessageID)
        guard case .pending(let failure) = delivery else {
            XCTFail("Le runtime invalidé ne doit plus agir."); return
        }
        XCTAssertEqual(failure, .contextChanged)
    }

    func testPendingFailureIsNotAnEmptyList() async throws {
        let scope = makeScope()
        let outbox = FakeMediaOutbox()
        await outbox.entriesFailure = .protectionUnavailable
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: FakeMediaEncryption(), sender: FakeMediaMessageSender(),
            transport: FakeMediaTransport())

        do {
            _ = try await coordinator.pending(conversationID: UUID())
            XCTFail("Une panne de coffre ne doit pas ressembler à une liste vide.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .protectionUnavailable)
        }
    }

    func testPendingOnlyReturnsTheRequestedConversation() async throws {
        let scope = makeScope()
        let firstConversation = UUID()
        let secondConversation = UUID()
        let coordinator = makeCoordinator(scope: scope, outbox: FakeMediaOutbox(),
            encryption: FakeMediaEncryption(), sender: FakeMediaMessageSender(),
            transport: FakeMediaTransport())
        _ = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: firstConversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        _ = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: secondConversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let pending = try await coordinator.pending(conversationID: firstConversation)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.conversationID, firstConversation)
    }
}

// MARK: - Doubles contrôlés

private actor OrderRecorder {
    private(set) var steps: [String] = []
    func append(_ step: String) { steps.append(step) }
}

/// Suspension contrôlée : le test ouvre explicitement la barrière, aucun sommeil.
private actor Gate {
    private var isOpen = false
    private var isWaiting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        isWaiting = true
        for waiter in arrivalWaiters { waiter.resume() }
        arrivalWaiters.removeAll()
        if isOpen {
            isWaiting = false
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        isWaiting = false
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func waitUntilWaiting() async {
        if isWaiting { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }
}

private struct StubPreparer: MessagingMediaPreparing {
    var result: MessagingPreparedMedia = MessagingPreparedMedia(
        data: Data([1, 2, 3, 4]), mime: .png, name: "photo.png",
        width: 2, height: 2, thumbnail: Data([0x89, 0x50, 0x4E, 0x47]))
    var failure: MessagingMediaPreparationFailure?

    init() {}

    init(result: MessagingPreparedMedia, failure: MessagingMediaPreparationFailure? = nil) {
        self.result = result
        self.failure = failure
    }

    init(mime: MessagingMediaAttachment.MIME, width: Int?, height: Int?, thumbnail: Data?) {
        result = MessagingPreparedMedia(data: Data([1, 2, 3, 4]), mime: mime,
            name: mime == .pdf ? "document.pdf" : "photo." + (mime == .jpeg ? "jpg" : "png"),
            width: width, height: height, thumbnail: thumbnail)
    }

    func prepare(_ data: Data, suggestedName: String) throws -> MessagingPreparedMedia {
        if let failure { throw failure }
        return MessagingPreparedMedia(data: data, mime: result.mime,
            name: MessagingMediaName.sanitized(suggestedName) ?? result.name,
            width: result.width, height: result.height, thumbnail: result.thumbnail)
    }
}

private actor FakeMediaOutbox: MessagingMediaOutbox, MessagingMediaOutboxEnvelope {
    private var records: [UUID: MessagingPendingMedia] = [:]
    private let order: OrderRecorder?
    var putFailure: MessagingFailure?
    var entriesFailure: MessagingFailure?
    var removeFailure: MessagingFailure?
    var replaceFailure: MessagingFailure?
    private(set) var replaceCalls: [(expected: MessagingCiphertext?, replacement: MessagingCiphertext)] = []

    init(order: OrderRecorder? = nil) { self.order = order }

    func put(_ pending: MessagingPendingMedia, scope: MessagingScope) async throws {
        await order?.append("put:" + (pending.messageCiphertext == nil ? "nil" : "env"))
        if let putFailure { throw putFailure }
        if records.values.contains(where: {
            $0.clientMessageID == pending.clientMessageID && $0.mediaID != pending.mediaID
        }) { throw MessagingFailure.stateConflict }
        if let existing = records[pending.mediaID], existing != pending {
            throw MessagingFailure.stateConflict
        }
        records[pending.mediaID] = pending
    }

    func entries(scope: MessagingScope) async throws -> [MessagingPendingMedia] {
        if let entriesFailure { throw entriesFailure }
        return records.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.mediaID.uuidString < $1.mediaID.uuidString
        }
    }

    func remove(mediaID: UUID, scope: MessagingScope) async throws {
        if let removeFailure { throw removeFailure }
        records.removeValue(forKey: mediaID)
    }

    func replaceEnvelope(mediaID: UUID, expected: MessagingCiphertext?,
                         replacement: MessagingCiphertext, scope: MessagingScope) async throws {
        await order?.append("replaceEnvelope")
        if let replaceFailure { throw replaceFailure }
        guard let record = records[mediaID], record.messageCiphertext == expected else {
            throw MessagingFailure.stateConflict
        }
        let updated = MessagingPendingMedia(clientMessageID: record.clientMessageID,
            conversationID: record.conversationID, sealed: record.sealed, content: record.content,
            mentionPersonIDs: record.mentionPersonIDs, replyToMessageID: record.replyToMessageID,
            createdAt: record.createdAt, messageCiphertext: replacement)
        records[mediaID] = updated
        replaceCalls.append((expected: expected, replacement: replacement))
    }

    func all() -> [MessagingPendingMedia] {
        records.values.sorted { $0.mediaID.uuidString < $1.mediaID.uuidString }
    }
}

private actor FakeMediaCache: MessagingMediaCache {
    var originals: [UUID: Data] = [:]
    var thumbnails: [UUID: Data] = [:]
    var dataError: Error?
    var storeError: Error?
    private(set) var storeCount = 0
    private(set) var thumbnailStoreCount = 0
    private(set) var purgeAllCount = 0

    func store(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        if let storeError { throw storeError }
        storeCount += 1
        originals[mediaID] = data
    }

    func putOriginal(_ data: Data, for mediaID: UUID) { originals[mediaID] = data }

    func data(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        if let dataError { throw dataError }
        return originals[mediaID]
    }

    func thumbnail(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        thumbnails[mediaID]
    }

    func storeThumbnail(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        thumbnailStoreCount += 1
        thumbnails[mediaID] = data
    }

    func purge(mediaIDs: [UUID], scope: MessagingScope) async throws {
        for id in mediaIDs {
            originals.removeValue(forKey: id)
            thumbnails.removeValue(forKey: id)
        }
    }

    func purgeAll(scope: MessagingScope) async throws {
        purgeAllCount += 1
        originals.removeAll()
        thumbnails.removeAll()
    }
}

private actor FakeMediaEncryption: MessagingMatrixContentEncryption, MessagingContentProvenanceDecryption {
    var encryptFailure: MessagingFailure?
    var decryptFailure: Error?
    var matrixContentByMessage: [UUID: Data] = [:]
    private(set) var encryptionCount = 0
    private(set) var encryptedContents: [MessagingMediaContentV3] = []
    private var envelopeIndex = 0
    private let order: OrderRecorder?

    init(order: OrderRecorder? = nil) { self.order = order }

    func encryptMatrixContent(_ content: MessagingMediaContentV3, mentions: [UUID],
                              scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        await order?.append("encrypt")
        if let encryptFailure { throw encryptFailure }
        encryptionCount += 1
        encryptedContents.append(content)
        envelopeIndex += 1
        return MessagingCiphertext(scheme: "test.megolm", keyID: "cle-\(envelopeIndex)",
            payload: Data("ENVELOPPE-\(envelopeIndex)".utf8), expectedMembersEpoch: 1)
    }

    func setMatrixContent(_ data: Data, for messageID: UUID) {
        matrixContentByMessage[messageID] = data
    }

    func decryptContent(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> MessagingDecryptedContent {
        if let decryptFailure { throw decryptFailure }
        guard let bytes = matrixContentByMessage[message.id] else {
            throw MessagingFailure.protectionUnavailable
        }
        return .matrixContent(bytes)
    }
}

private actor FakeMediaMessageSender: MessagingMediaMessageSending {
    var error: Error?
    private(set) var sends: [(pending: MessagingPending, media: MessagingMediaMessageIntent)] = []

    func sendMedia(scope: MessagingScope, pending: MessagingPending,
                   media: MessagingMediaMessageIntent) async throws -> MessagingAcknowledgement {
        sends.append((pending: pending, media: media))
        if let error { throw error }
        return MessagingAcknowledgement(clientMessageID: pending.clientMessageID,
            serverMessageID: UUID(), conversationID: pending.conversationID,
            schoolID: scope.schoolID, acceptedAt: Date(), senderID: scope.accountID)
    }
}

private actor FakeMediaTransport: MessagingMediaTransport {
    var uploadReceipt: MessagingMediaReceipt?
    var uploadError: Error?
    var downloadData: Data?
    var downloadError: Error?
    var uploadGate: Gate?
    private(set) var uploadCount = 0
    private(set) var downloadCount = 0
    private(set) var uploaded: [MessagingSealedMedia] = []

    func upload(_ sealed: MessagingSealedMedia, scope: MessagingScope,
                conversationID: UUID) async throws -> MessagingMediaReceipt {
        uploadCount += 1
        uploaded.append(sealed)
        if let uploadGate { await uploadGate.wait() }
        if let uploadError { throw uploadError }
        if let uploadReceipt { return uploadReceipt }
        let digest = SHA256.hash(data: sealed.ciphertext)
            .map { String(format: "%02x", $0) }.joined()
        return MessagingMediaReceipt(mediaID: sealed.mediaID, byteSize: sealed.byteSize,
            sha256: digest, state: .uploaded)
    }

    func download(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        downloadCount += 1
        if let downloadError { throw downloadError }
        guard let downloadData else { throw MessagingMediaTransportFailure.unavailable }
        return downloadData
    }

    func cancel(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws {}
}
