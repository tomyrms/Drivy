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

    /// Une opération retenue ne bloque jamais le test : la course rend un résultat ou
    /// une échéance explicite, sans joindre le travail qui ignorerait l'annulation.
    /// La tâche et le watcher sont annulés, la barrière ouverte sur tous les chemins.
    private func boundedValue<T: Sendable>(_ task: Task<T, Never>, gate: Gate,
                                           timeout: Duration = .seconds(2)) async throws -> T {
        let box = DeadlineBox<DeadlineOutcome<T>>()
        let watcher = Task { @MainActor in
            let value = await task.value
            box.finish(.value(value))
        }
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            box.finish(.timedOut)
        }
        let outcome = await box.wait()
        deadline.cancel()
        watcher.cancel()
        switch outcome {
        case .value(let value): return value
        case .error(let errorBox): throw errorBox.error
        case .timedOut:
            await gate.open()
            task.cancel()
            watcher.cancel()
            throw BoundedTimeout()
        }
    }

    private func boundedValue<T: Sendable>(_ task: Task<T, Error>, gate: Gate,
                                           timeout: Duration = .seconds(2)) async throws -> T {
        let box = DeadlineBox<DeadlineOutcome<T>>()
        let watcher = Task { @MainActor in
            switch await task.result {
            case .success(let value): box.finish(.value(value))
            case .failure(let error): box.finish(.error(ErrorBox(error)))
            }
        }
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            box.finish(.timedOut)
        }
        let outcome = await box.wait()
        deadline.cancel()
        watcher.cancel()
        switch outcome {
        case .value(let value): return value
        case .error(let errorBox): throw errorBox.error
        case .timedOut:
            await gate.open()
            task.cancel()
            watcher.cancel()
            throw BoundedTimeout()
        }
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
        await outbox.setPutFailure(.protectionUnavailable)
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
        await sender.setError(MessagingFailure.unavailable)
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

        let premature = await coordinator.recomposeAfterMembersChanged(clientMessageID: snapshot.clientMessageID)
        guard case .pending(let rejected) = premature else {
            XCTFail("Une réponse perdue n'ouvre pas la recomposition d'enveloppe."); return
        }
        XCTAssertEqual(rejected, .membersChanged)
        let encryptAfterRecompose = await encryption.encryptionCount
        XCTAssertEqual(encryptAfterRecompose, 1, "Aucune recomposition n'est tentée sans refus avéré.")
    }

    func testConfirmedServerReceiptWithCleanupFailureIsNotAFalseSendFailure() async throws {
        let scope = makeScope()
        let outbox = FakeMediaOutbox()
        await outbox.setRemoveFailure(.protectionUnavailable)
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
        await transport.setUploadGate(gate)
        let coordinator = makeCoordinator(scope: scope, outbox: outbox,
            encryption: encryption, sender: sender, transport: transport)
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let first = Task { await coordinator.send(clientMessageID: snapshot.clientMessageID) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(first, gate: gate)
            XCTFail("Le premier envoi n'a pas atteint la frontière attendue."); return
        }
        let second = await coordinator.send(clientMessageID: snapshot.clientMessageID)
        guard case .pending(let failure) = second else {
            await gate.open()
            _ = try? await boundedValue(first, gate: gate)
            XCTFail("Le second geste concurrent ne doit pas repartir."); return
        }
        XCTAssertEqual(failure, .alreadyInFlight)
        await gate.open()
        let firstDelivery = try await boundedValue(first, gate: gate)
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
        await sender.setError(MessagingFailure.membersChanged)
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

        await sender.setError(nil)
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
        await transport.setDownloadData(sealed.ciphertext)
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
        await transport.setDownloadData(sealed.ciphertext)
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
        await transport.setDownloadData(corrupted)
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
        await transport.setDownloadData(sealed.ciphertext)
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
        await outbox.setEntriesFailure(.protectionUnavailable)
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

    // MARK: Reprise idempotente (F1)

    func testEnqueueAfterEncryptionFailureReusesTheDurableSeal() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let clientMessageID = UUID()
        let prepared = makePrepared()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        await encryption.setEncryptFailure(.protectionUnavailable)
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        do {
            _ = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
                conversationID: conversation, caption: "Légende", mentionPersonIDs: [],
                replyToMessageID: nil)
            XCTFail("L'échec de chiffrement doit être rendu.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .protectionUnavailable)
        }
        let firstEntries = await outbox.all()
        let first = try XCTUnwrap(firstEntries.first)
        XCTAssertNil(first.messageCiphertext)

        await encryption.setEncryptFailure(nil)
        let snapshot = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
            conversationID: conversation, caption: "Légende", mentionPersonIDs: [],
            replyToMessageID: nil)
        XCTAssertEqual(snapshot.mediaID, first.mediaID, "La reprise réutilise le sceau durable.")
        XCTAssertEqual(snapshot.createdAt, first.createdAt)
        let encryptionAfterReenqueue = await encryption.encryptionCount
        let entriesAfterReenqueue = await outbox.all()
        let uploadsAfterReenqueue = await transport.uploadCount
        XCTAssertEqual(encryptionAfterReenqueue, 1, "Aucun second chiffrement à la reprise.")
        XCTAssertEqual(entriesAfterReenqueue.count, 1)
        XCTAssertEqual(uploadsAfterReenqueue, 0)

        let delivery = await coordinator.send(clientMessageID: clientMessageID)
        guard case .confirmed = delivery else {
            XCTFail("Le renvoi explicite doit aboutir."); return
        }
        let encryptionAfterSend = await encryption.encryptionCount
        let uploadsAfterSend = await transport.uploadCount
        let remaining = await outbox.all()
        XCTAssertEqual(encryptionAfterSend, 2, "L'enveloppe manquante est créée par send, pas par la reprise.")
        XCTAssertEqual(uploadsAfterSend, 1)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testEnqueueAfterPutWriteFailureReusesTheDurableSeal() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let clientMessageID = UUID()
        let prepared = makePrepared()
        let outbox = FakeMediaOutbox()
        await outbox.setPutFailureAfterWrite(.protectionUnavailable)
        let encryption = FakeMediaEncryption()
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        do {
            _ = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
                conversationID: conversation, caption: nil, mentionPersonIDs: [],
                replyToMessageID: nil)
            XCTFail("L'échec de synchronisation après put doit être rendu.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .protectionUnavailable)
        }
        let firstEntries = await outbox.all()
        let first = try XCTUnwrap(firstEntries.first)
        let encryptionsBefore = await encryption.encryptionCount
        XCTAssertEqual(encryptionsBefore, 0)

        await outbox.setPutFailureAfterWrite(nil)
        let snapshot = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
            conversationID: conversation, caption: nil, mentionPersonIDs: [],
            replyToMessageID: nil)
        XCTAssertEqual(snapshot.mediaID, first.mediaID)
        XCTAssertEqual(snapshot.createdAt, first.createdAt)
        let encryptionsAfterReenqueue = await encryption.encryptionCount
        let entriesAfterReenqueue = await outbox.all()
        XCTAssertEqual(encryptionsAfterReenqueue, 0)
        XCTAssertEqual(entriesAfterReenqueue.count, 1)

        let delivery = await coordinator.send(clientMessageID: clientMessageID)
        guard case .confirmed = delivery else {
            XCTFail("Le renvoi explicite doit aboutir."); return
        }
        let encryptionsAfterSend = await encryption.encryptionCount
        let uploads = await transport.uploadCount
        XCTAssertEqual(encryptionsAfterSend, 1)
        XCTAssertEqual(uploads, 1)
    }

    func testEnqueueAfterEnvelopeWriteFailureReusesTheDurableEnvelope() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let clientMessageID = UUID()
        let prepared = makePrepared()
        let outbox = FakeMediaOutbox()
        await outbox.setReplaceFailureAfterWrite(.protectionUnavailable)
        let encryption = FakeMediaEncryption()
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        do {
            _ = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
                conversationID: conversation, caption: nil, mentionPersonIDs: [],
                replyToMessageID: nil)
            XCTFail("L'échec après remplacement doit être rendu.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .protectionUnavailable)
        }
        let firstEntries = await outbox.all()
        let first = try XCTUnwrap(firstEntries.first)
        let firstEnvelope = try XCTUnwrap(first.messageCiphertext,
            "Le CAS a écrit l'enveloppe avant l'échec de synchronisation.")

        await outbox.setReplaceFailureAfterWrite(nil)
        let snapshot = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
            conversationID: conversation, caption: nil, mentionPersonIDs: [],
            replyToMessageID: nil)
        XCTAssertEqual(snapshot.mediaID, first.mediaID)
        let encryptionAfterReenqueue = await encryption.encryptionCount
        let replacesAfterReenqueue = await outbox.replaceCalls.count
        let entriesAfterReenqueue = await outbox.all()
        XCTAssertEqual(encryptionAfterReenqueue, 1, "L'enveloppe durable n'est pas rechiffrée.")
        XCTAssertEqual(replacesAfterReenqueue, 1, "La reprise reconfirme le record, sans nouveau CAS.")
        XCTAssertEqual(entriesAfterReenqueue.first?.messageCiphertext, firstEnvelope)

        let delivery = await coordinator.send(clientMessageID: clientMessageID)
        guard case .confirmed = delivery else {
            XCTFail("Le renvoi explicite doit aboutir."); return
        }
        let encryptionAfterSend = await encryption.encryptionCount
        let uploads = await transport.uploadCount
        XCTAssertEqual(encryptionAfterSend, 1)
        XCTAssertEqual(uploads, 1)
    }

    func testEnqueueRefusesDifferentContentUnderTheSameGesture() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let clientMessageID = UUID()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: FakeMediaTransport())
        let first = try await coordinator.enqueue(makePrepared(Data([1, 2, 3, 4])),
            clientMessageID: clientMessageID, conversationID: conversation, caption: "Légende",
            mentionPersonIDs: [], replyToMessageID: nil)

        do {
            _ = try await coordinator.enqueue(makePrepared(Data([9, 9, 9, 9])),
                clientMessageID: clientMessageID, conversationID: conversation, caption: "Légende",
                mentionPersonIDs: [], replyToMessageID: nil)
            XCTFail("Un autre contenu sous le même geste doit être refusé.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .invalidContent)
        }
        let entries = await outbox.all()
        let encryptionCount = await encryption.encryptionCount
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.mediaID, first.mediaID)
        XCTAssertEqual(encryptionCount, 1, "Aucun nouveau sceau ni chiffrement n'est créé.")
    }

    func testEnqueueAdoptsAConcurrentRecordAfterPutConflict() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let clientMessageID = UUID()
        let prepared = makePrepared()
        let (sealed, content) = try makeSealedContent()
        let existing = MessagingPendingMedia(clientMessageID: clientMessageID,
            conversationID: conversation, sealed: sealed, content: content,
            mentionPersonIDs: [], replyToMessageID: nil, createdAt: Date())
        let outbox = FakeMediaOutbox()
        await outbox.setConflictOnPut(existing)
        let encryption = FakeMediaEncryption()
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        let snapshot = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
            conversationID: conversation, caption: "Légende", mentionPersonIDs: [],
            replyToMessageID: nil)
        XCTAssertEqual(snapshot.mediaID, sealed.mediaID)
        let entries = await outbox.all()
        let encryptions = await encryption.encryptionCount
        let uploads = await transport.uploadCount
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(encryptions, 0, "Aucun second chiffrement après adoption du record concurrent.")
        XCTAssertEqual(uploads, 0)
    }

    func testSecondInstanceReusesTheSameDurableIntent() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let clientMessageID = UUID()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        let transport = FakeMediaTransport()
        let first = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)
        let second = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)

        let original = try await first.enqueue(makePrepared(), clientMessageID: clientMessageID,
            conversationID: conversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        let reused = try await second.enqueue(makePrepared(), clientMessageID: clientMessageID,
            conversationID: conversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        XCTAssertEqual(reused.mediaID, original.mediaID)
        XCTAssertEqual(reused.createdAt, original.createdAt)
        let entries = await outbox.all()
        let encryptionCount = await encryption.encryptionCount
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(encryptionCount, 1)
    }

    // MARK: Réponse perdue après recomposition (F2)

    func testLostRecomposeResponseForbidsSecondRecomposeAndReplaysSameEnvelope() async throws {
        let scope = makeScope()
        let clientMessageID = UUID()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        await sender.setQueuedErrors([MessagingFailure.membersChanged,
                                      MessagingFailure.unavailable, nil])
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)
        _ = try await coordinator.enqueue(makePrepared(), clientMessageID: clientMessageID,
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let refused = await coordinator.send(clientMessageID: clientMessageID)
        guard case .pending(let refusedFailure) = refused else {
            XCTFail("MEMBERS_CHANGED est un refus explicite."); return
        }
        XCTAssertEqual(refusedFailure, .membersChanged)

        let recomposed = await coordinator.recomposeAfterMembersChanged(clientMessageID: clientMessageID)
        guard case .pending(let lostFailure) = recomposed else {
            XCTFail("Une réponse perdue doit rester inconnue."); return
        }
        XCTAssertEqual(lostFailure, .resultUnknown)
        let afterLost = await outbox.all()
        let envelope = try XCTUnwrap(afterLost.first?.messageCiphertext)
        let encryptionsAfterLost = await encryption.encryptionCount
        let replacesAfterLost = await outbox.replaceCalls.count
        let sendsAfterLost = await sender.sends.count
        XCTAssertEqual(encryptionsAfterLost, 2)
        XCTAssertEqual(replacesAfterLost, 2)
        XCTAssertEqual(sendsAfterLost, 2)

        let secondRecompose = await coordinator.recomposeAfterMembersChanged(clientMessageID: clientMessageID)
        guard case .pending(let secondFailure) = secondRecompose else {
            XCTFail("Une enveloppe émise au résultat inconnu ne se recompose pas."); return
        }
        XCTAssertEqual(secondFailure, .resultUnknown)
        let encryptionsAfterSecond = await encryption.encryptionCount
        let replacesAfterSecond = await outbox.replaceCalls.count
        let sendsAfterSecond = await sender.sends.count
        XCTAssertEqual(encryptionsAfterSecond, 2, "Aucun nouveau chiffrement.")
        XCTAssertEqual(replacesAfterSecond, 2, "Aucun nouveau CAS.")
        XCTAssertEqual(sendsAfterSecond, 2, "Aucun nouveau POST.")

        let replay = await coordinator.send(clientMessageID: clientMessageID)
        guard case .confirmed = replay else {
            XCTFail("Le renvoi explicite de la même enveloppe doit aboutir."); return
        }
        let finalSends = await sender.sends
        let finalEncryptions = await encryption.encryptionCount
        let finalReplaces = await outbox.replaceCalls.count
        XCTAssertEqual(finalSends.count, 3)
        XCTAssertEqual(finalSends.last?.pending.ciphertext, envelope,
                       "Le replay réutilise exactement l'enveloppe émise.")
        XCTAssertEqual(finalEncryptions, 2)
        XCTAssertEqual(finalReplaces, 2)
        let remaining = await outbox.all()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testNewMembersChangedRefusalReopensRecomposition() async throws {
        let scope = makeScope()
        let clientMessageID = UUID()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        await sender.setQueuedErrors([MessagingFailure.membersChanged,
                                      MessagingFailure.membersChanged, nil])
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)
        _ = try await coordinator.enqueue(makePrepared(), clientMessageID: clientMessageID,
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)

        let firstSend = await coordinator.send(clientMessageID: clientMessageID)
        guard case .pending(.membersChanged) = firstSend else {
            XCTFail("Premier refus membres attendu."); return
        }
        let firstRecompose = await coordinator.recomposeAfterMembersChanged(clientMessageID: clientMessageID)
        guard case .pending(.membersChanged) = firstRecompose else {
            XCTFail("Un nouveau refus membres doit rouvrir le chemin."); return
        }
        let secondRecompose = await coordinator.recomposeAfterMembersChanged(clientMessageID: clientMessageID)
        guard case .confirmed = secondRecompose else {
            XCTFail("La seconde recomposition, fondée sur le nouveau refus, doit aboutir."); return
        }
        let encryptions = await encryption.encryptionCount
        let replaces = await outbox.replaceCalls.count
        let sends = await sender.sends.count
        XCTAssertEqual(encryptions, 3)
        XCTAssertEqual(replaces, 3)
        XCTAssertEqual(sends, 3)
    }

    func testSendReconfirmsTheExactRecordBeforeUpload() async throws {
        let scope = makeScope()
        let order = OrderRecorder()
        let outbox = FakeMediaOutbox(order: order)
        let encryption = FakeMediaEncryption(order: order)
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: FakeMediaTransport())
        let snapshot = try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        let before = await order.steps
        let delivery = await coordinator.send(clientMessageID: snapshot.clientMessageID)
        guard case .confirmed = delivery else {
            XCTFail("Envoi attendu confirmé."); return
        }
        let after = await order.steps
        guard after.count > before.count else {
            XCTFail("Aucune reconfirmation avant le dépôt."); return
        }
        XCTAssertEqual(after[before.count], "put:env",
                       "Le record exact est reconfirmé durablement avant le dépôt réseau.")
    }

    // MARK: Invalidation pendant les attentes (F4)

    func testInvalidateDuringPutDoesNotEncryptOrUpload() async throws {
        let scope = makeScope()
        let outbox = FakeMediaOutbox()
        let gate = Gate()
        await outbox.setPutGate(gate)
        let encryption = FakeMediaEncryption()
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)
        let task = Task {
            try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
                conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("La mise en file n'a pas atteint le put attendu."); return
        }
        await coordinator.invalidate()
        await gate.open()
        do {
            _ = try await boundedValue(task, gate: gate)
            XCTFail("Une invalidation pendant le put doit fermer le geste.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
        let encryptions = await encryption.encryptionCount
        let uploads = await transport.uploadCount
        let entries = await outbox.all()
        XCTAssertEqual(encryptions, 0, "Aucun chiffrement après l'invalidation.")
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(entries.count, 1, "L'intention déjà admise reste durable.")
    }

    func testContextChangeDuringPutClosesTheGesture() async throws {
        let scope = makeScope()
        let box = ScopeBox(scope)
        let outbox = FakeMediaOutbox()
        let gate = Gate()
        await outbox.setPutGate(gate)
        let encryption = FakeMediaEncryption()
        let transport = FakeMediaTransport()
        let coordinator = MessagingMediaCoordinator(scope: scope, preparer: StubPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: outbox, cache: FakeMediaCache(),
            encryption: encryption, sending: FakeMediaMessageSender(),
            transportFactory: { transport }, currentScope: { box.value })
        let task = Task {
            try await coordinator.enqueue(makePrepared(), clientMessageID: UUID(),
                conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("La mise en file n'a pas atteint le put attendu."); return
        }
        box.value = nil
        await gate.open()
        do {
            _ = try await boundedValue(task, gate: gate)
            XCTFail("Un changement de contexte pendant le put doit fermer le geste.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
        let encryptions = await encryption.encryptionCount
        let uploads = await transport.uploadCount
        let entries = await outbox.all()
        XCTAssertEqual(encryptions, 0)
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(entries.count, 1, "L'intention déjà admise reste durable.")
    }

    func testInvalidateDuringCacheStorePurgesTheLateWrite() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let cache = FakeMediaCache()
        let otherID = UUID()
        await cache.putOriginal(Data([7]), for: otherID)
        let gate = Gate()
        await cache.setStoreGate(gate)
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        await transport.setDownloadData(sealed.ciphertext)
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), cache: cache, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)
        let task = Task { try await coordinator.open(message) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("L'ouverture n'a pas atteint l'écriture de cache."); return
        }
        await coordinator.invalidate()
        await gate.open()
        do {
            _ = try await boundedValue(task, gate: gate)
            XCTFail("Une invalidation pendant l'écriture doit purger la copie tardive.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
        let originals = await cache.originals
        let purges = await cache.purgeCount
        let downloads = await transport.downloadCount
        XCTAssertNil(originals[sealed.mediaID], "Aucune copie tardive ne survit à l'invalidation.")
        XCTAssertNil(originals[otherID], "L'invalidation du scope purge aussi les autres médias.")
        XCTAssertGreaterThanOrEqual(purges, 1)
        XCTAssertEqual(downloads, 1)
    }

    func testInvalidateDuringThumbnailStorePurgesTheLateWrite() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let plaintext = try AESCTRMediaCryptography().open(sealed.ciphertext, info: sealed.info)
        let cache = FakeMediaCache()
        await cache.putOriginal(plaintext, for: sealed.mediaID)
        let gate = Gate()
        await cache.setThumbnailGate(gate)
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        await transport.setDownloadData(sealed.ciphertext)
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), cache: cache, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)
        let task = Task { try await coordinator.open(message) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("L'ouverture n'a pas atteint l'écriture de miniature."); return
        }
        await coordinator.invalidate()
        await gate.open()
        do {
            _ = try await boundedValue(task, gate: gate)
            XCTFail("Une invalidation pendant la miniature doit purger la copie tardive.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
        let thumbnails = await cache.thumbnails
        let downloads = await transport.downloadCount
        XCTAssertNil(thumbnails[sealed.mediaID])
        XCTAssertEqual(downloads, 0, "Le cache original évite le téléchargement.")
    }

    func testRevokePurgesKnownMediaAndBlocksOpen() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let cache = FakeMediaCache()
        await cache.putOriginal(Data([1, 2, 3, 4]), for: sealed.mediaID)
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        await transport.setDownloadData(sealed.ciphertext)
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), cache: cache, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)

        await coordinator.revoke(mediaIDs: [sealed.mediaID], conversationID: conversation)
        let originals = await cache.originals
        XCTAssertNil(originals[sealed.mediaID], "La copie connue est purgée.")
        do {
            _ = try await coordinator.open(message)
            XCTFail("Un média révoqué ne doit plus être servi.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .removed)
        }
        let downloads = await transport.downloadCount
        XCTAssertEqual(downloads, 0)
    }

    // MARK: Contenu périmé après une attente (F3)

    func testDelayedDecryptCannotResurrectContentAfterTombstonePage() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let live = makeWire(messageID, conversationID: conversation, media: reference)
        let deletedReference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: true)
        let tombstone = makeWire(messageID, conversationID: conversation, media: deletedReference,
                                 deletedForEveryone: true)
        let crypto = HeldWorkspaceCrypto(payload: try matrixBytes(content))
        let service = WorkspacePageService(page: MessagingPage<MessagingWireMessage>(items: [live], nextCursor: nil))
        let history = RecordingHistory()
        let revocation = RevocationRecordingRuntime()
        let workspace = MessagingWorkspace(scope: scope, service: service, cryptography: crypto,
            history: history, mediaRuntime: revocation, currentScope: { scope })
        await workspace.loadMessages(conversation)

        let task = Task { await workspace.content(for: live) }
        let arrived = await crypto.gate.waitUntilWaiting()
        guard arrived else {
            await crypto.gate.open()
            _ = try? await boundedValue(task, gate: crypto.gate)
            XCTFail("Le déchiffrement n'a pas atteint la barrière."); return
        }
        await service.setPage(MessagingPage<MessagingWireMessage>(items: [tombstone], nextCursor: nil))
        await workspace.loadMessages(conversation)
        await crypto.gate.open()
        let value = try await boundedValue(task, gate: crypto.gate)

        XCTAssertNil(value, "Un tombstone reçu pendant le déchiffrement ne ressuscite pas le clair.")
        XCTAssertNil(workspace.contents[messageID])
        let upserts = await history.upserted
        XCTAssertTrue(upserts.isEmpty, "Aucun historique tardif n'est réinscrit.")
        let revoked = await revocation.revoked
        XCTAssertEqual(revoked, [sealed.mediaID])
    }

    func testDelayedDecryptCannotResurrectContentAfterLowerReadLimit() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let live = makeWire(messageID, conversationID: conversation, media: reference)
        let crypto = HeldWorkspaceCrypto(payload: try matrixBytes(content))
        let service = WorkspacePageService(page: MessagingPage<MessagingWireMessage>(items: [live], nextCursor: nil))
        let history = RecordingHistory()
        let revocation = RevocationRecordingRuntime()
        let workspace = MessagingWorkspace(scope: scope, service: service, cryptography: crypto,
            history: history, mediaRuntime: revocation, currentScope: { scope })
        await workspace.loadMessages(conversation)

        let task = Task { await workspace.content(for: live) }
        let arrived = await crypto.gate.waitUntilWaiting()
        guard arrived else {
            await crypto.gate.open()
            _ = try? await boundedValue(task, gate: crypto.gate)
            XCTFail("Le déchiffrement n'a pas atteint la barrière."); return
        }
        let access = MessagingConversationAccess(canWrite: false,
            readableUntilSequence: live.meta.sequence - 1, isGroupAdmin: false)
        await service.setPage(MessagingPage<MessagingWireMessage>(items: [live], nextCursor: nil, access: access))
        await workspace.loadMessages(conversation)
        await crypto.gate.open()
        let value = try await boundedValue(task, gate: crypto.gate)

        XCTAssertNil(value, "Une limite lisible abaissée ne ressuscite pas le clair.")
        XCTAssertNil(workspace.contents[messageID])
        let upserts = await history.upserted
        XCTAssertTrue(upserts.isEmpty)
        let revoked = await revocation.revoked
        XCTAssertEqual(revoked, [sealed.mediaID])
    }

    // MARK: Sorties d'attente et révocation ciblée (R1/R2)

    func testInvalidateDuringSendReconfirmationDoesNotEncryptOrUpload() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let clientMessageID = UUID()
        let prepared = makePrepared()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        await encryption.setEncryptFailure(.protectionUnavailable)
        let sender = FakeMediaMessageSender()
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)
        do {
            _ = try await coordinator.enqueue(prepared, clientMessageID: clientMessageID,
                conversationID: conversation, caption: nil, mentionPersonIDs: [],
                replyToMessageID: nil)
            XCTFail("L'échec de chiffrement doit laisser un record sans enveloppe.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .protectionUnavailable)
        }
        await encryption.setEncryptFailure(nil)

        let gate = Gate()
        await outbox.setPutGate(gate)
        let task = Task { await coordinator.send(clientMessageID: clientMessageID) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("La reconfirmation n'a pas atteint le put attendu."); return
        }
        await coordinator.invalidate()
        await gate.open()
        let delivery = try await boundedValue(task, gate: gate)
        guard case .pending(let failure) = delivery else {
            XCTFail("Une invalidation pendant la reconfirmation doit fermer le geste."); return
        }
        XCTAssertEqual(failure, .contextChanged)
        let encryptions = await encryption.encryptionCount
        let uploads = await transport.uploadCount
        let sends = await sender.sends.count
        let entries = await outbox.all()
        XCTAssertEqual(encryptions, 1, "Seule la tentative de enqueue a chiffré.")
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(entries.count, 1, "L'intention durable reste.")
    }

    func testInvalidateDuringCacheReadDoesNotCreateTransport() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let cache = FakeMediaCache()
        let gate = Gate()
        await cache.setDataGate(gate)
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        let factory = FactoryBox()
        let coordinator = MessagingMediaCoordinator(scope: scope, preparer: StubPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: FakeMediaOutbox(), cache: cache,
            encryption: encryption, sending: FakeMediaMessageSender(),
            transportFactory: { factory.calls += 1; return transport }, currentScope: { scope })
        let task = Task { try await coordinator.open(message) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("La lecture de cache n'a pas atteint la barrière."); return
        }
        await coordinator.invalidate()
        await gate.open()
        do {
            _ = try await boundedValue(task, gate: gate)
            XCTFail("Une invalidation pendant la lecture de cache doit fermer le chemin.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .contextChanged)
        }
        let downloads = await transport.downloadCount
        XCTAssertEqual(factory.calls, 0, "Aucune nouvelle factory après invalidation.")
        XCTAssertEqual(downloads, 0)
    }

    func testCancellationDuringCacheReadStopsBeforeTransport() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let bytes = try matrixBytes(content)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, conversationID: conversation, media: reference)
        let cache = FakeMediaCache()
        let gate = Gate()
        await cache.setDataGate(gate)
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(bytes, for: messageID)
        let transport = FakeMediaTransport()
        let factory = FactoryBox()
        let coordinator = MessagingMediaCoordinator(scope: scope, preparer: StubPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: FakeMediaOutbox(), cache: cache,
            encryption: encryption, sending: FakeMediaMessageSender(),
            transportFactory: { factory.calls += 1; return transport }, currentScope: { scope })
        let task = Task { try await coordinator.open(message) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("La lecture de cache n'a pas atteint la barrière."); return
        }
        task.cancel()
        await gate.open()
        do {
            _ = try await boundedValue(task, gate: gate)
            XCTFail("Une annulation ne doit pas poursuivre après l'attente.")
        } catch is CancellationError {
            // Attendu.
        }
        let downloads = await transport.downloadCount
        XCTAssertEqual(factory.calls, 0, "Aucune factory après annulation.")
        XCTAssertEqual(downloads, 0)
    }

    func testCancelledPostInvalidatesMembersChangedAuthorization() async throws {
        let scope = makeScope()
        let clientMessageID = UUID()
        let outbox = FakeMediaOutbox()
        let encryption = FakeMediaEncryption()
        let sender = FakeMediaMessageSender()
        await sender.setQueuedErrors([MessagingFailure.membersChanged])
        let transport = FakeMediaTransport()
        let coordinator = makeCoordinator(scope: scope, outbox: outbox, encryption: encryption,
            sender: sender, transport: transport)
        _ = try await coordinator.enqueue(makePrepared(), clientMessageID: clientMessageID,
            conversationID: UUID(), caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        let first = await coordinator.send(clientMessageID: clientMessageID)
        guard case .pending(.membersChanged) = first else {
            XCTFail("Premier refus membres attendu."); return
        }

        let gate = Gate()
        await sender.setSendGate(gate)
        let task = Task { await coordinator.send(clientMessageID: clientMessageID) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(task, gate: gate)
            XCTFail("Le POST n'a pas atteint la barrière."); return
        }
        task.cancel()
        await gate.open()
        let delivery = try await boundedValue(task, gate: gate)
        guard case .pending(let failure) = delivery else {
            XCTFail("Un POST annulé n'est pas une confirmation."); return
        }
        XCTAssertEqual(failure, .resultUnknown)

        let secondRecompose = await coordinator.recomposeAfterMembersChanged(clientMessageID: clientMessageID)
        guard case .pending(let noAuthorization) = secondRecompose else {
            XCTFail("L'ancienne autorisation ne doit pas survivre à un POST annulé."); return
        }
        XCTAssertEqual(noAuthorization, .resultUnknown)
        let encryptions = await encryption.encryptionCount
        let replaces = await outbox.replaceCalls.count
        let sends = await sender.sends.count
        let entries = await outbox.all()
        XCTAssertEqual(encryptions, 1, "Aucun nouveau chiffrement après le POST annulé.")
        XCTAssertEqual(replaces, 1, "Aucun nouveau CAS.")
        XCTAssertEqual(sends, 2, "Le replay a bien émis une seconde fois, pas la recomposition.")
        XCTAssertEqual(entries.count, 1, "L'intention durable reste.")
    }

    func testRevokeDuringStoreReturnsRemovedAndKeepsAnotherMedia() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let (aSealed, aContent) = try makeSealedContent()
        let (bSealed, bContent) = try makeSealedContent()
        let aReference = try MessagingMessageMediaReference(mediaID: aSealed.mediaID,
            byteSize: aSealed.byteSize, deleted: false)
        let bReference = try MessagingMessageMediaReference(mediaID: bSealed.mediaID,
            byteSize: bSealed.byteSize, deleted: false)
        let aMessage = makeWire(UUID(), conversationID: conversation, media: aReference)
        let bMessage = makeWire(UUID(), conversationID: UUID(), media: bReference)
        let cache = FakeMediaCache()
        let gate = Gate()
        await cache.setStoreGate(gate)
        let encryption = FakeMediaEncryption()
        await encryption.setMatrixContent(try matrixBytes(aContent), for: aMessage.id)
        await encryption.setMatrixContent(try matrixBytes(bContent), for: bMessage.id)
        let transport = FakeMediaTransport()
        await transport.setDownloadData(aSealed.ciphertext, for: aSealed.mediaID)
        await transport.setDownloadData(bSealed.ciphertext, for: bSealed.mediaID)
        let coordinator = makeCoordinator(scope: scope,
            preparer: StubPreparer(mime: .png, width: 2, height: 2, thumbnail: Data([9])),
            outbox: FakeMediaOutbox(), cache: cache, encryption: encryption,
            sender: FakeMediaMessageSender(), transport: transport)
        let aTask = Task { try await coordinator.open(aMessage) }
        let arrived = await gate.waitUntilWaiting()
        guard arrived else {
            await gate.open()
            _ = try? await boundedValue(aTask, gate: gate)
            XCTFail("L'ouverture de A n'a pas atteint son store."); return
        }
        await coordinator.revoke(mediaIDs: [aSealed.mediaID], conversationID: conversation)
        await cache.setStoreGate(nil)

        let bPrepared = try await coordinator.open(bMessage)
        let bPlaintext = try AESCTRMediaCryptography().open(bSealed.ciphertext, info: bSealed.info)
        XCTAssertEqual(bPrepared.data, bPlaintext)
        let bCached = await cache.originals[bSealed.mediaID]
        XCTAssertEqual(bCached, bPlaintext, "B reste utilisable malgré la révocation de A.")

        await gate.open()
        do {
            _ = try await boundedValue(aTask, gate: gate)
            XCTFail("Le média A révoqué pendant son store doit échouer.")
        } catch let failure as MessagingMediaRuntimeFailure {
            XCTAssertEqual(failure, .removed)
        }
        let originals = await cache.originals
        XCTAssertNil(originals[aSealed.mediaID], "La copie tardive de A est purgée.")
        XCTAssertEqual(originals[bSealed.mediaID], bPlaintext)
        let downloads = await transport.downloadCount
        XCTAssertEqual(downloads, 2)
    }

    // MARK: Faits négatifs du workspace (R3)

    func testWorkspaceTombstoneArgumentOverridesOlderLiveProjection() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let deletedReference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: true)
        let live = makeWire(messageID, conversationID: conversation, media: reference)
        let tombstone = makeWire(messageID, conversationID: conversation,
                                 media: deletedReference, deletedForEveryone: true)
        let crypto = HeldWorkspaceCrypto(payload: try matrixBytes(content))
        let service = WorkspacePageService(page: MessagingPage<MessagingWireMessage>(items: [live], nextCursor: nil))
        let history = RecordingHistory()
        let revocation = RevocationRecordingRuntime()
        let workspace = MessagingWorkspace(scope: scope, service: service, cryptography: crypto,
            history: history, mediaRuntime: revocation, currentScope: { scope })
        await workspace.loadMessages(conversation)
        await crypto.gate.open()
        let first = await workspace.content(for: live)
        XCTAssertNotNil(first)

        let value = await workspace.content(for: tombstone)
        XCTAssertNil(value, "Un tombstone fourni ne peut pas reprendre le live chargé.")
        XCTAssertNil(workspace.contents[messageID])
        let revoked = await revocation.revoked
        XCTAssertTrue(revoked.contains(sealed.mediaID))
        let removed = await history.removed
        XCTAssertTrue(removed.contains(messageID))
    }

    func testWorkspacePageWithDeletedMediaReferenceRevokesKnownID() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let deletedReference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: true)
        let live = makeWire(messageID, conversationID: conversation, media: reference)
        let mediaDeleted = makeWire(messageID, conversationID: conversation, media: deletedReference)
        let crypto = HeldWorkspaceCrypto(payload: try matrixBytes(content))
        let service = WorkspacePageService(page: MessagingPage<MessagingWireMessage>(items: [live], nextCursor: nil))
        let history = RecordingHistory()
        let revocation = RevocationRecordingRuntime()
        let workspace = MessagingWorkspace(scope: scope, service: service, cryptography: crypto,
            history: history, mediaRuntime: revocation, currentScope: { scope })
        await workspace.loadMessages(conversation)
        await crypto.gate.open()
        _ = await workspace.content(for: live)

        await service.setPage(MessagingPage<MessagingWireMessage>(items: [mediaDeleted], nextCursor: nil))
        await workspace.loadMessages(conversation)
        XCTAssertNil(workspace.contents[messageID])
        let revoked = await revocation.revoked
        XCTAssertTrue(revoked.contains(sealed.mediaID))
    }

    func testWorkspacePageWithDisappearedMediaReferenceRevokesKnownID() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let live = makeWire(messageID, conversationID: conversation, media: reference)
        let withoutReference = makeWire(messageID, conversationID: conversation, media: nil)
        let crypto = HeldWorkspaceCrypto(payload: try matrixBytes(content))
        let service = WorkspacePageService(page: MessagingPage<MessagingWireMessage>(items: [live], nextCursor: nil))
        let history = RecordingHistory()
        let revocation = RevocationRecordingRuntime()
        let workspace = MessagingWorkspace(scope: scope, service: service, cryptography: crypto,
            history: history, mediaRuntime: revocation, currentScope: { scope })
        await workspace.loadMessages(conversation)
        await crypto.gate.open()
        _ = await workspace.content(for: live)

        await service.setPage(MessagingPage<MessagingWireMessage>(items: [withoutReference], nextCursor: nil))
        await workspace.loadMessages(conversation)
        XCTAssertNil(workspace.contents[messageID])
        let revoked = await revocation.revoked
        XCTAssertTrue(revoked.contains(sealed.mediaID))
    }

    func testWorkspaceOldLiveSnapshotAfterTombstoneIsRefused() async throws {
        let scope = makeScope()
        let conversation = UUID()
        let messageID = UUID()
        let (sealed, content) = try makeSealedContent()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let deletedReference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: true)
        let live = makeWire(messageID, conversationID: conversation, media: reference)
        let tombstone = makeWire(messageID, conversationID: conversation,
                                 media: deletedReference, deletedForEveryone: true)
        let crypto = HeldWorkspaceCrypto(payload: try matrixBytes(content))
        let service = WorkspacePageService(page: MessagingPage<MessagingWireMessage>(items: [live], nextCursor: nil))
        let history = RecordingHistory()
        let revocation = RevocationRecordingRuntime()
        let workspace = MessagingWorkspace(scope: scope, service: service, cryptography: crypto,
            history: history, mediaRuntime: revocation, currentScope: { scope })
        await workspace.loadMessages(conversation)
        await crypto.gate.open()
        _ = await workspace.content(for: live)

        await service.setPage(MessagingPage<MessagingWireMessage>(items: [tombstone], nextCursor: nil))
        await workspace.loadMessages(conversation)
        let value = await workspace.content(for: live)
        XCTAssertNil(value, "Un ancien live ne doit pas contourner le tombstone chargé.")
        XCTAssertNil(workspace.contents[messageID])
        let revoked = await revocation.revoked
        XCTAssertTrue(revoked.contains(sealed.mediaID))
    }

    func testBoundedValueTimesOutWithoutJoiningNonCooperativeTask() async throws {
        let gate = Gate()
        let retained = Task<Int, Never> {
            // Ignore l'annulation et ne se termine jamais : le helper ne doit pas le joindre.
            await withUnsafeContinuation { (_: UnsafeContinuation<Int, Never>) in }
        }
        let completion = expectation(description: "Échéance explicite du helper")
        let started = Date()
        Task {
            do {
                _ = try await boundedValue(retained, gate: gate, timeout: .milliseconds(100))
                XCTFail("Une opération non coopérative ne doit pas rendre de valeur.")
            } catch is BoundedTimeout {
                completion.fulfill()
            } catch {
                XCTFail("Échéance explicite attendue, reçu \(type(of: error)).")
            }
        }
        await fulfillment(of: [completion], timeout: 2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testGateArrivalTimeoutDoesNotHang() async {
        let gate = Gate()
        let arrived = await gate.waitUntilWaiting(timeout: .milliseconds(50))
        XCTAssertFalse(arrived)
        await gate.open()
    }
}

// MARK: - Doubles contrôlés

@MainActor
private final class ScopeBox {
    var value: MessagingScope?
    init(_ value: MessagingScope?) { self.value = value }
}

@MainActor
private final class FactoryBox {
    var calls = 0
}

private struct ErrorBox: @unchecked Sendable {
    let error: Error
}

private enum DeadlineOutcome<Value: Sendable>: Sendable {
    case value(Value)
    case error(ErrorBox)
    case timedOut
}

private struct BoundedTimeout: Error, CustomStringConvertible {
    var description: String { "opération retenue au-delà de l'échéance" }
}

/// Résultat unique d'une course entre une opération et son échéance. `finish` est
/// idempotent : la première issue gagne, l'autre est ignorée sans double reprise.
@MainActor
private final class DeadlineBox<Value> {
    private var outcome: Value?
    private var continuation: CheckedContinuation<Value, Never>?

    func wait() async -> Value {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ value: Value) {
        guard outcome == nil else { return }
        outcome = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private actor OrderRecorder {
    private(set) var steps: [String] = []
    func append(_ step: String) { steps.append(step) }
}

/// Suspension contrôlée : le test ouvre explicitement la barrière. L'arrivée est
/// bornée par une échéance et l'ouverture libère tous les chemins, sans task group
/// attendant un enfant non coopératif.
private actor Gate {
    private var isOpen = false
    private var isWaiting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func wait() async {
        isWaiting = true
        resumeArrivals(true)
        if isOpen {
            isWaiting = false
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        isWaiting = false
    }

    func open() {
        isOpen = true
        resumeArrivals(true)
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func waitUntilWaiting(timeout: Duration = .seconds(2)) async -> Bool {
        if isWaiting { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            arrivals[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expireArrival(id)
            }
        }
    }

    private func resumeArrivals(_ value: Bool) {
        let pending = arrivals
        arrivals.removeAll()
        for continuation in pending.values { continuation.resume(returning: value) }
    }

    private func expireArrival(_ id: UUID) {
        guard let continuation = arrivals.removeValue(forKey: id) else { return }
        continuation.resume(returning: false)
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
    var replaceFailureAfterWrite: MessagingFailure?
    var putFailureAfterWrite: MessagingFailure?
    var putGate: Gate?
    var conflictOnPut: MessagingPendingMedia?
    private(set) var replaceCalls: [(expected: MessagingCiphertext?, replacement: MessagingCiphertext)] = []

    init(order: OrderRecorder? = nil) { self.order = order }

    func setPutFailure(_ failure: MessagingFailure?) { putFailure = failure }
    func setEntriesFailure(_ failure: MessagingFailure?) { entriesFailure = failure }
    func setRemoveFailure(_ failure: MessagingFailure?) { removeFailure = failure }
    func setReplaceFailure(_ failure: MessagingFailure?) { replaceFailure = failure }
    func setReplaceFailureAfterWrite(_ failure: MessagingFailure?) { replaceFailureAfterWrite = failure }
    func setPutFailureAfterWrite(_ failure: MessagingFailure?) { putFailureAfterWrite = failure }
    func setPutGate(_ gate: Gate?) { putGate = gate }
    func setConflictOnPut(_ pending: MessagingPendingMedia?) { conflictOnPut = pending }

    func put(_ pending: MessagingPendingMedia, scope: MessagingScope) async throws {
        await order?.append("put:" + (pending.messageCiphertext == nil ? "nil" : "env"))
        if let conflictOnPut {
            self.conflictOnPut = nil
            records[conflictOnPut.mediaID] = conflictOnPut
            throw MessagingFailure.stateConflict
        }
        if let putGate { await putGate.wait() }
        if let putFailure { throw putFailure }
        if records.values.contains(where: {
            $0.clientMessageID == pending.clientMessageID && $0.mediaID != pending.mediaID
        }) { throw MessagingFailure.stateConflict }
        if let existing = records[pending.mediaID], existing != pending {
            throw MessagingFailure.stateConflict
        }
        records[pending.mediaID] = pending
        if let failure = putFailureAfterWrite {
            self.putFailureAfterWrite = nil
            throw failure
        }
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
        if let failure = replaceFailureAfterWrite {
            self.replaceFailureAfterWrite = nil
            throw failure
        }
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
    var storeGate: Gate?
    var thumbnailGate: Gate?
    var dataGate: Gate?
    private(set) var storeCount = 0
    private(set) var thumbnailStoreCount = 0
    private(set) var purgeAllCount = 0
    private(set) var purgeCount = 0

    func setDataError(_ error: Error?) { dataError = error }
    func setStoreError(_ error: Error?) { storeError = error }
    func setStoreGate(_ gate: Gate?) { storeGate = gate }
    func setThumbnailGate(_ gate: Gate?) { thumbnailGate = gate }
    func setDataGate(_ gate: Gate?) { dataGate = gate }

    func store(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        if let storeGate { await storeGate.wait() }
        if let storeError { throw storeError }
        storeCount += 1
        originals[mediaID] = data
    }

    func putOriginal(_ data: Data, for mediaID: UUID) { originals[mediaID] = data }

    func data(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        if let dataGate { await dataGate.wait() }
        if let dataError { throw dataError }
        return originals[mediaID]
    }

    func thumbnail(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        thumbnails[mediaID]
    }

    func storeThumbnail(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        if let thumbnailGate { await thumbnailGate.wait() }
        thumbnailStoreCount += 1
        thumbnails[mediaID] = data
    }

    func purge(mediaIDs: [UUID], scope: MessagingScope) async throws {
        purgeCount += 1
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

    func setEncryptFailure(_ failure: MessagingFailure?) { encryptFailure = failure }
    func setDecryptFailure(_ failure: Error?) { decryptFailure = failure }

    func encryptMatrixContent(_ content: MessagingMediaContentV3, mentions: [UUID],
                              scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        await order?.append("encrypt")
        encryptionCount += 1
        if let encryptFailure { throw encryptFailure }
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
    var queuedErrors: [Error?] = []
    var sendGate: Gate?
    private(set) var sends: [(pending: MessagingPending, media: MessagingMediaMessageIntent)] = []

    func setError(_ error: Error?) { self.error = error }
    func setQueuedErrors(_ errors: [Error?]) { queuedErrors = errors }
    func setSendGate(_ gate: Gate?) { sendGate = gate }

    func sendMedia(scope: MessagingScope, pending: MessagingPending,
                   media: MessagingMediaMessageIntent) async throws -> MessagingAcknowledgement {
        sends.append((pending: pending, media: media))
        if let sendGate { await sendGate.wait() }
        try Task.checkCancellation()
        if !queuedErrors.isEmpty {
            if let queued = queuedErrors.removeFirst() { throw queued }
        } else if let error {
            throw error
        }
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
    var downloadDataByMediaID: [UUID: Data] = [:]
    var uploadGate: Gate?
    private(set) var uploadCount = 0
    private(set) var downloadCount = 0
    private(set) var uploaded: [MessagingSealedMedia] = []

    func setUploadGate(_ gate: Gate?) { uploadGate = gate }
    func setUploadError(_ error: Error?) { uploadError = error }
    func setUploadReceipt(_ receipt: MessagingMediaReceipt?) { uploadReceipt = receipt }
    func setDownloadData(_ data: Data?) { downloadData = data }
    func setDownloadData(_ data: Data, for mediaID: UUID) { downloadDataByMediaID[mediaID] = data }
    func setDownloadError(_ error: Error?) { downloadError = error }

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
        if let data = downloadDataByMediaID[mediaID] { return data }
        guard let downloadData else { throw MessagingMediaTransportFailure.unavailable }
        return downloadData
    }

    func cancel(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws {}
}

/// Déchiffrement retenu pour prouver qu'un résultat tardif ne réinscrit rien.
private final class HeldWorkspaceCrypto: MessagingCryptography, MessagingContentProvenanceDecryption, @unchecked Sendable {
    let gate = Gate()
    let payload: Data

    init(payload: Data) { self.payload = payload }

    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope,
                 conversationID: UUID) async throws -> MessagingCiphertext {
        throw MessagingFailure.protectionUnavailable
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope,
                 conversationID: UUID) async throws -> Data {
        ciphertext.payload
    }
    func decrypt(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> Data {
        throw MessagingFailure.protectionUnavailable
    }
    func decryptContent(_ message: MessagingWireMessage,
                        scope: MessagingScope) async throws -> MessagingDecryptedContent {
        await gate.wait()
        return .matrixContent(payload)
    }
}

/// Page serveur contrôlée : le test remplace la page pendant un déchiffrement retenu.
private actor WorkspacePageService: MessagingService {
    private var page: MessagingPage<MessagingWireMessage>

    init(page: MessagingPage<MessagingWireMessage>) { self.page = page }
    func setPage(_ page: MessagingPage<MessagingWireMessage>) { self.page = page }

    func conversations(scope: MessagingScope,
                       cursor: String?) async throws -> MessagingPage<MessagingConversation> {
        MessagingPage(items: [], nextCursor: nil)
    }
    func messages(scope: MessagingScope, conversationID: UUID,
                  before: String?) async throws -> MessagingPage<MessagingWireMessage> {
        page
    }
    func send(scope: MessagingScope,
              pending: MessagingPending) async throws -> MessagingAcknowledgement {
        throw MessagingFailure.unavailable
    }
}

/// Historique de test : prouve qu'aucune entrée tardive n'est réinscrite.
private actor RecordingHistory: MessagingHistoryStore {
    private(set) var upserted: [UUID] = []
    private(set) var removed: [UUID] = []

    func upsert(_ entries: [MessagingHistoryEntry], scope: MessagingScope) async throws {
        upserted.append(contentsOf: entries.map(\.messageID))
    }
    func entries(conversationID: UUID, scope: MessagingScope) async throws -> [MessagingHistoryEntry] {
        []
    }
    func remove(messageIDs: [UUID], scope: MessagingScope) async throws {
        removed.append(contentsOf: messageIDs)
    }
    func truncate(conversationID: UUID, after sequence: Int,
                  scope: MessagingScope) async throws {}
}

/// Runtime de workspace qui enregistre les médias révoqués par une page serveur.
private actor RevocationRecordingRuntime: MessagingMediaRuntime, MessagingMediaRevocationReceiving {
    private(set) var revoked: [UUID] = []

    func revoke(mediaIDs: [UUID], conversationID: UUID) async {
        revoked.append(contentsOf: mediaIDs)
    }
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        throw MessagingMediaRuntimeFailure.unavailable
    }
    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID,
                 conversationID: UUID, caption: String?, mentionPersonIDs: [UUID],
                 replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot {
        throw MessagingMediaRuntimeFailure.unavailable
    }
    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot] { [] }
    func send(clientMessageID: UUID) async -> MessagingMediaDelivery { .pending(.unavailable) }
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery {
        .pending(.unavailable)
    }
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        throw MessagingMediaRuntimeFailure.unavailable
    }
    func invalidate() async {}
}
