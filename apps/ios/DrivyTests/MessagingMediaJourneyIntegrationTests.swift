import XCTest
import CryptoKit
@testable import Drivy

/// Parcours média complet (#97) : préparation réelle, file et cache réels sur un répertoire
/// temporaire, transports Megolm/dépôt/POST doublés. Tests écrits avant le coordinateur ;
/// **NON EXÉCUTÉS** sur ce poste Windows. Les fixtures sont synthétiques (PNG 1×1) et aucune
/// donnée de personne, clé d'hôte ou Keychain système n'est utilisée.
@MainActor
final class MessagingMediaJourneyIntegrationTests: XCTestCase {
    private let school = UUID()
    private let account = UUID()
    private let conversation = UUID()

    private var scope: MessagingScope {
        MessagingScope(accountID: account, schoolID: school, accessEpoch: 7,
                       apiBaseURL: "https://api.example.invalid/")
    }

    /// PNG synthétique 1×1, sans métadonnée personnelle.
    private var tinyPNG: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nWQAAAAASUVORK5CYII=")!
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-journey-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeOutbox(scope: MessagingScope, root: URL,
                            keys: SyntheticMediaKeyStore) throws -> MessagingProtectedMediaOutbox {
        try MessagingProtectedMediaOutbox(scope: scope, root: root, keyStore: keys,
            fileSystem: SystemMediaOutboxFileSystem(), limits: .standard)
    }

    private func makeCache(scope: MessagingScope, anchor: URL,
                           keys: SyntheticMediaKeyStore) throws -> MessagingProtectedMediaCache {
        try MessagingProtectedMediaCache(scope: scope, anchor: anchor,
            maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
            keyProvider: { mayCreate in try keys.key(create: mayCreate) })
    }

    private func makeWire(_ messageID: UUID,
                          media: MessagingMessageMediaReference,
                          deletedForEveryone: Bool = false) -> MessagingWireMessage {
        var meta = MessagingMessageMeta()
        meta.sequence = 21
        meta.media = media
        meta.deletedForEveryone = deletedForEveryone
        return MessagingWireMessage(id: messageID, conversationID: conversation,
            schoolID: school, senderID: UUID(), acceptedAt: Date(),
            ciphertext: deletedForEveryone ? nil : MessagingCiphertext(scheme: "TEST", keyID: "k",
                                                                       payload: Data("ENVELOPE".utf8)),
            meta: meta)
    }

    // MARK: Parcours émetteur avec file et cache réels

    func testPreparedMediaSurvivesReopeningAndSendsWithTheSameSeal() async throws {
        let scope = scope
        let root = try makeRoot()
        let keys = SyntheticMediaKeyStore()
        let encryption = JourneyEncryption()
        let sender = JourneySender(scope: scope)
        let transport = JourneyTransport()
        let firstOutbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let cache = try makeCache(scope: scope, anchor: root, keys: keys)
        let first = MessagingMediaCoordinator(scope: scope, preparer: MessagingMediaPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: firstOutbox, cache: cache,
            encryption: encryption, sending: sender,
            transportFactory: { transport }, currentScope: { scope })

        let prepared = try await first.prepare(tinyPNG, suggestedName: "photo.png")
        XCTAssertEqual(prepared.mime, .png)
        XCTAssertEqual(prepared.width, 1)
        XCTAssertEqual(prepared.height, 1)
        XCTAssertNotNil(prepared.thumbnail, "La miniature locale est produite en mémoire.")
        XCTAssertEqual(prepared.data, tinyPNG, "L'original reste octet pour octet.")

        let clientMessageID = UUID()
        let snapshot = try await first.enqueue(prepared, clientMessageID: clientMessageID,
            conversationID: conversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        XCTAssertNil(snapshot.caption)
        let before = try await firstOutbox.entries(scope: scope)
        XCTAssertEqual(before.count, 1)
        let persisted = try XCTUnwrap(before.first)
        XCTAssertEqual(persisted.mediaID, snapshot.mediaID)
        XCTAssertNotNil(persisted.messageCiphertext)

        let reopenedOutbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let reopened = MessagingMediaCoordinator(scope: scope, preparer: MessagingMediaPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: reopenedOutbox, cache: cache,
            encryption: encryption, sending: sender,
            transportFactory: { transport }, currentScope: { scope })
        let pending = try await reopened.pending(conversationID: conversation)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.mediaID, snapshot.mediaID)
        XCTAssertEqual(pending.first?.byteSize, snapshot.byteSize)

        let delivery = await reopened.send(clientMessageID: clientMessageID)
        guard case .confirmed(_, let cleanupPending) = delivery else {
            XCTFail("L'envoi doit être confirmé par le reçu serveur."); return
        }
        XCTAssertFalse(cleanupPending)
        let encryptCount = await encryption.encryptionCount
        XCTAssertEqual(encryptCount, 1, "La réouverture ne réchiffre pas l'enveloppe durable.")
        let uploads = await transport.uploads
        XCTAssertEqual(uploads.count, 1)
        XCTAssertEqual(uploads.first?.mediaID, snapshot.mediaID)
        XCTAssertEqual(uploads.first?.ciphertext, persisted.sealed.ciphertext)
        let after = try await reopenedOutbox.entries(scope: scope)
        XCTAssertTrue(after.isEmpty, "L'intention est retirée après l'accusé.")
    }

    // MARK: Réception, validation et cache réels

    func testReceivedMediaIsDownloadedValidatedCachedThenServedFromCache() async throws {
        let scope = scope
        let root = try makeRoot()
        let keys = SyntheticMediaKeyStore()
        let sealed = try AESCTRMediaCryptography().seal(tinyPNG)
        let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
            mime: .png, name: "photo.png", width: 1, height: 1, file: sealed.info)
        let content = try MessagingMediaContentV3(text: "Légende", media: attachment)
        let messageID = UUID()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, media: reference)
        let encryption = JourneyEncryption()
        await encryption.setMatrixContent(
            try MessagingMediaContent.messageContent(content, mentions: nil), for: messageID)
        let transport = JourneyTransport()
        await transport.downloadData = sealed.ciphertext
        let cache = try makeCache(scope: scope, anchor: root, keys: keys)
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let coordinator = MessagingMediaCoordinator(scope: scope, preparer: MessagingMediaPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: outbox, cache: cache,
            encryption: encryption, sending: JourneySender(scope: scope),
            transportFactory: { transport }, currentScope: { scope })

        let first = try await coordinator.open(message)
        XCTAssertEqual(first.data, tinyPNG)
        XCTAssertEqual(first.mime, .png)
        XCTAssertEqual(first.name, "photo.png")
        XCTAssertEqual(first.width, 1)
        XCTAssertEqual(first.height, 1)
        XCTAssertNotNil(first.thumbnail)
        let downloads = await transport.downloads
        XCTAssertEqual(downloads, 1, "Le premier rendu télécharge une fois.")

        let second = try await coordinator.open(message)
        let downloadsAfter = await transport.downloads
        XCTAssertEqual(downloadsAfter, 1, "Le second rendu vient du cache scellé.")
        XCTAssertEqual(second.data, first.data)
        XCTAssertNotNil(second.thumbnail)
    }

    func testInvalidatePurgesTheRealCacheWithoutRemovingPendingIntent() async throws {
        let scope = scope
        let root = try makeRoot()
        let keys = SyntheticMediaKeyStore()
        let sealed = try AESCTRMediaCryptography().seal(tinyPNG)
        let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
            mime: .png, name: "photo.png", width: 1, height: 1, file: sealed.info)
        let content = try MessagingMediaContentV3(text: nil, media: attachment)
        let messageID = UUID()
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, media: reference)
        let encryption = JourneyEncryption()
        await encryption.setMatrixContent(
            try MessagingMediaContent.messageContent(content, mentions: nil), for: messageID)
        let transport = JourneyTransport()
        await transport.downloadData = sealed.ciphertext
        let cache = try makeCache(scope: scope, anchor: root, keys: keys)
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let coordinator = MessagingMediaCoordinator(scope: scope, preparer: MessagingMediaPreparer(),
            cryptography: AESCTRMediaCryptography(), outbox: outbox, cache: cache,
            encryption: encryption, sending: JourneySender(scope: scope),
            transportFactory: { transport }, currentScope: { scope })

        _ = try await coordinator.open(message)
        let stored = try await cache.data(mediaID: sealed.mediaID, scope: scope)
        XCTAssertNotNil(stored)

        let prepared = MessagingPreparedMedia(data: tinyPNG, mime: .png, name: "photo.png",
            width: 1, height: 1, thumbnail: Data([1]))
        let snapshot = try await coordinator.enqueue(prepared, clientMessageID: UUID(),
            conversationID: conversation, caption: nil, mentionPersonIDs: [], replyToMessageID: nil)
        await coordinator.invalidate()

        let purged = try await cache.data(mediaID: sealed.mediaID, scope: scope)
        XCTAssertNil(purged, "L'invalidation purge le cache du scope.")
        let pending = try await outbox.entries(scope: scope)
        XCTAssertEqual(pending.count, 1, "L'intention encore à vérifier reste dans la file.")
        XCTAssertEqual(pending.first?.mediaID, snapshot.mediaID)
        let delivery = await coordinator.send(clientMessageID: snapshot.clientMessageID)
        guard case .pending(let failure) = delivery else {
            XCTFail("Le runtime invalidé ne doit plus envoyer."); return
        }
        XCTAssertEqual(failure, .contextChanged)
    }

    // MARK: Workspace : provenance typée, repli legacy et cache non contournable

    func testWorkspaceReadsExplicitMatrixProvenanceAndTypedMedia() async throws {
        let scope = scope
        let messageID = UUID()
        let sealed = try AESCTRMediaCryptography().seal(tinyPNG)
        let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
            mime: .png, name: "photo.png", width: 1, height: 1, file: sealed.info)
        let content = try MessagingMediaContentV3(text: "Légende", media: attachment)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, media: reference)
        let crypto = WorkspaceProvenanceCrypto()
        crypto.decrypted[messageID] = .matrixContent(
            try MessagingMediaContent.messageContent(content, mentions: nil))
        let workspace = MessagingWorkspace(scope: scope, cryptography: crypto,
            currentScope: { scope })

        let value = await workspace.content(for: message)
        XCTAssertEqual(value?.text, "Légende")
        XCTAssertEqual(value?.media?.id, sealed.mediaID)
        XCTAssertEqual(value?.media?.mime, MessagingMediaAttachment.MIME.png)
        XCTAssertNil(workspace.decryptionCodes[messageID])
    }

    func testWorkspaceRefusesAnInvalidV3MatrixContent() async throws {
        let scope = scope
        let messageID = UUID()
        let sealed = try AESCTRMediaCryptography().seal(tinyPNG)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let message = makeWire(messageID, media: reference)
        let crypto = WorkspaceProvenanceCrypto()
        crypto.decrypted[messageID] = .matrixContent(Data(
            #"{"msgtype":"m.text","body":"Photo","ch.drivy.messaging":{"v":3}}"#.utf8))
        let workspace = MessagingWorkspace(scope: scope, cryptography: crypto,
            currentScope: { scope })

        let value = await workspace.content(for: message)
        XCTAssertNil(value, "Un v3 connu mais invalide échoue fermé, sans repli heuristique.")
    }

    func testWorkspaceKeepsTheLegacyFallbackForAnExistingDouble() async throws {
        let scope = scope
        let messageID = UUID()
        let message = MessagingWireMessage(id: messageID, conversationID: conversation,
            schoolID: school, senderID: UUID(), acceptedAt: Date(),
            ciphertext: MessagingCiphertext(scheme: "TEST", keyID: "k", payload: Data("x".utf8)))
        let crypto = WorkspaceLegacyCrypto()
        crypto.payloads[messageID] = Data("Texte existant".utf8)
        let workspace = MessagingWorkspace(scope: scope, cryptography: crypto,
            currentScope: { scope })

        let value = await workspace.content(for: message)
        XCTAssertEqual(value?.text, "Texte existant")
        XCTAssertNil(value?.media)
    }

    func testWorkspaceDoesNotServeCachedMediaAfterATombstone() async throws {
        let scope = scope
        let messageID = UUID()
        let sealed = try AESCTRMediaCryptography().seal(tinyPNG)
        let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
            mime: .png, name: "photo.png", width: 1, height: 1, file: sealed.info)
        let content = try MessagingMediaContentV3(text: "Légende", media: attachment)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let live = makeWire(messageID, media: reference)
        let crypto = WorkspaceProvenanceCrypto()
        crypto.decrypted[messageID] = .matrixContent(
            try MessagingMediaContent.messageContent(content, mentions: nil))
        let workspace = MessagingWorkspace(scope: scope, cryptography: crypto,
            currentScope: { scope })
        let first = await workspace.content(for: live)
        XCTAssertNotNil(first?.media)

        let tombstone = makeWire(messageID, media: reference, deletedForEveryone: true)
        let after = await workspace.content(for: tombstone)
        XCTAssertNil(after, "Un objet mis en cache ne contourne jamais le tombstone serveur.")
    }

    func testWorkspaceDoesNotServeCachedMediaWhenTheServerReferenceDisappears() async throws {
        let scope = scope
        let messageID = UUID()
        let sealed = try AESCTRMediaCryptography().seal(tinyPNG)
        let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
            mime: .png, name: "photo.png", width: 1, height: 1, file: sealed.info)
        let content = try MessagingMediaContentV3(text: nil, media: attachment)
        let reference = try MessagingMessageMediaReference(mediaID: sealed.mediaID,
            byteSize: sealed.byteSize, deleted: false)
        let live = makeWire(messageID, media: reference)
        let crypto = WorkspaceProvenanceCrypto()
        crypto.decrypted[messageID] = .matrixContent(
            try MessagingMediaContent.messageContent(content, mentions: nil))
        let workspace = MessagingWorkspace(scope: scope, cryptography: crypto,
            currentScope: { scope })
        let first = await workspace.content(for: live)
        XCTAssertNotNil(first?.media)

        var noReference = live
        noReference.meta.media = nil
        let after = await workspace.content(for: noReference)
        XCTAssertNil(after, "La disparition de la référence serveur ne laisse pas le média en cache.")
    }

    func testWorkspaceKeepsTheOptionalRuntimePointWithoutChangingTextComposition() async throws {
        let scope = scope
        let plain = MessagingWorkspace(scope: scope, currentScope: { scope })
        XCTAssertNil(plain.mediaRuntime)

        let runtime = StubMediaRuntime()
        let withMedia = MessagingWorkspace(scope: scope, mediaRuntime: runtime,
            currentScope: { scope })
        XCTAssertNotNil(withMedia.mediaRuntime)
        let text = MessagingWireMessage(id: UUID(), conversationID: conversation,
            schoolID: school, senderID: UUID(), acceptedAt: Date(),
            ciphertext: MessagingCiphertext(scheme: "TEST", keyID: "k", payload: Data("x".utf8)))
        let legacy = WorkspaceLegacyCrypto()
        let workspace = MessagingWorkspace(scope: scope, cryptography: legacy,
            mediaRuntime: runtime, currentScope: { scope })
        let value = await workspace.content(for: text)
        XCTAssertNil(value, "Un double sans contenu ne casse pas la messagerie texte.")
    }
}

// MARK: - Fixtures et doubles

/// Clé synthétique locale aux tests : jamais la Keychain de l'application.
private final class SyntheticMediaKeyStore: MessagingMediaOutboxKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Data?
    private(set) var creationCount = 0

    func key(create: Bool) throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        if let bytes { return SymmetricKey(data: bytes) }
        guard create else { throw MessagingFailure.protectionUnavailable }
        let created = Data(repeating: 0x42, count: 32)
        bytes = created
        creationCount += 1
        return SymmetricKey(data: created)
    }
}

private actor JourneyEncryption: MessagingMatrixContentEncryption, MessagingContentProvenanceDecryption {
    private var matrixContentByMessage: [UUID: Data] = [:]
    private(set) var encryptionCount = 0
    private var envelopeIndex = 0

    func setMatrixContent(_ data: Data, for messageID: UUID) {
        matrixContentByMessage[messageID] = data
    }

    func encryptMatrixContent(_ content: MessagingMediaContentV3, mentions: [UUID],
                              scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        encryptionCount += 1
        envelopeIndex += 1
        return MessagingCiphertext(scheme: "test.megolm", keyID: "cle-\(envelopeIndex)",
            payload: Data("ENVELOPPE-\(envelopeIndex)".utf8), expectedMembersEpoch: 1)
    }

    func decryptContent(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> MessagingDecryptedContent {
        guard let data = matrixContentByMessage[message.id] else {
            throw MessagingFailure.protectionUnavailable
        }
        return .matrixContent(data)
    }
}

private actor JourneySender: MessagingMediaMessageSending {
    let scope: MessagingScope
    private(set) var sends = 0

    init(scope: MessagingScope) { self.scope = scope }

    func sendMedia(scope: MessagingScope, pending: MessagingPending,
                   media: MessagingMediaMessageIntent) async throws -> MessagingAcknowledgement {
        sends += 1
        return MessagingAcknowledgement(clientMessageID: pending.clientMessageID,
            serverMessageID: UUID(), conversationID: pending.conversationID,
            schoolID: scope.schoolID, acceptedAt: Date(), senderID: scope.accountID)
    }
}

private actor JourneyTransport: MessagingMediaTransport {
    var downloadData: Data?
    private(set) var uploads: [MessagingSealedMedia] = []
    private(set) var downloads = 0

    func upload(_ sealed: MessagingSealedMedia, scope: MessagingScope,
                conversationID: UUID) async throws -> MessagingMediaReceipt {
        uploads.append(sealed)
        let digest = SHA256.hash(data: sealed.ciphertext)
            .map { String(format: "%02x", $0) }.joined()
        return MessagingMediaReceipt(mediaID: sealed.mediaID, byteSize: sealed.byteSize,
            sha256: digest, state: .uploaded)
    }

    func download(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        downloads += 1
        guard let downloadData else { throw MessagingMediaTransportFailure.unavailable }
        return downloadData
    }

    func cancel(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws {}
}

/// Double de la couche Megolm pour le workspace : provenance explicite.
private final class WorkspaceProvenanceCrypto: MessagingCryptography, MessagingContentProvenanceDecryption, @unchecked Sendable {
    var decrypted: [UUID: MessagingDecryptedContent] = [:]

    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope,
                 conversationID: UUID) async throws -> MessagingCiphertext { throw MessagingFailure.protectionUnavailable }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope,
                 conversationID: UUID) async throws -> Data { throw MessagingFailure.protectionUnavailable }
    func decrypt(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> Data {
        throw MessagingFailure.protectionUnavailable
    }
    func decryptContent(_ message: MessagingWireMessage,
                        scope: MessagingScope) async throws -> MessagingDecryptedContent {
        guard let value = decrypted[message.id] else { throw MessagingFailure.protectionUnavailable }
        return value
    }
}

/// Double historique sans provenance : le repli legacy doit rester intact.
private final class WorkspaceLegacyCrypto: MessagingCryptography, @unchecked Sendable {
    var payloads: [UUID: Data] = [:]

    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { true }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope,
                 conversationID: UUID) async throws -> MessagingCiphertext { throw MessagingFailure.protectionUnavailable }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope,
                 conversationID: UUID) async throws -> Data { ciphertext.payload }
    func decrypt(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> Data {
        guard let data = payloads[message.id] else { throw MessagingFailure.protectionUnavailable }
        return data
    }
}

private actor StubMediaRuntime: MessagingMediaRuntime {
    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        throw MessagingMediaRuntimeFailure.unavailable
    }
    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID,
                 conversationID: UUID, caption: String?, mentionPersonIDs: [UUID],
                 replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot {
        throw MessagingMediaRuntimeFailure.unavailable
    }
    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot] {
        throw MessagingMediaRuntimeFailure.unavailable
    }
    func send(clientMessageID: UUID) async -> MessagingMediaDelivery {
        .pending(.unavailable)
    }
    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery {
        .pending(.unavailable)
    }
    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        throw MessagingMediaRuntimeFailure.unavailable
    }
    func invalidate() async {}
}
