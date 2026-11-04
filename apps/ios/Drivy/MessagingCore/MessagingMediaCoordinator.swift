import Foundation
import CryptoKit

/// Fabrique du transport binaire média (#97).
///
/// L'identité d'appareil n'est pas connue à la construction synchrone de la feuille :
/// la fabrique est asynchrone et lit l'appareil déjà enregistré dans la machine Matrix.
/// Elle est isolée au MainActor pour capturer sans conflit la source de jeton de l'app,
/// mais ne fait qu'y attendre : aucun décodage ni I/O bloquant ne tient le fil d'interface.
typealias MessagingMediaTransportFactory = @MainActor @Sendable () async throws -> any MessagingMediaTransport

/// Coordinateur du parcours média (#97) : préparation, intention durable, dépôt, POST,
/// reprise, recomposition explicite et lecture authentifiée.
///
/// Ce type est le seul point qui assemble les primitives livrées :
/// `MessagingMediaPreparer`, `MessagingMediaCryptography`, `MessagingProtectedMediaOutbox`,
/// `MessagingProtectedMediaCache`, `MessagingMatrixContentEncryption`,
/// `MessagingMediaTransport` et `MessagingMediaMessageSending`.
///
/// Il ne crée aucun texte d'interface, ne journalise aucun identifiant, nom, clé, hash
/// ou contenu, et ne promet ni livraison au destinataire ni effacement physique.
actor MessagingMediaCoordinator: MessagingMediaRuntime {
    private static let maximumMentions = 8

    private let scope: MessagingScope
    private let preparer: any MessagingMediaPreparing
    private let cryptography: any MessagingMediaCryptography
    private let outbox: any MessagingMediaOutbox & MessagingMediaOutboxEnvelope
    private let cache: any MessagingMediaCache
    private let encryption: any MessagingMatrixContentEncryption & MessagingContentProvenanceDecryption
    private let sending: any MessagingMediaMessageSending
    private let transportFactory: MessagingMediaTransportFactory
    private let currentScope: @MainActor @Sendable () -> MessagingScope?

    /// Un seul transport binaire par instance, créé à la première utilisation.
    private var transport: (any MessagingMediaTransport)?
    /// Gestes en vol, pour ne pas doubler un dépôt ou un POST dans le même processus.
    private var active: Set<UUID> = []
    /// Refus `MEMBERS_CHANGED` réellement observés dans cette instance : seule une
    /// recomposition explicite consécutive à ce refus est admise, jamais après une
    /// réponse perdue.
    private var membersChanged: Set<UUID> = []
    private var invalidated = false

    init(scope: MessagingScope,
         preparer: any MessagingMediaPreparing = MessagingMediaPreparer(),
         cryptography: any MessagingMediaCryptography = AESCTRMediaCryptography(),
         outbox: any MessagingMediaOutbox & MessagingMediaOutboxEnvelope,
         cache: any MessagingMediaCache,
         encryption: any MessagingMatrixContentEncryption & MessagingContentProvenanceDecryption,
         sending: any MessagingMediaMessageSending,
         transportFactory: @escaping MessagingMediaTransportFactory,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        self.scope = scope
        self.preparer = preparer
        self.cryptography = cryptography
        self.outbox = outbox
        self.cache = cache
        self.encryption = encryption
        self.sending = sending
        self.transportFactory = transportFactory
        self.currentScope = currentScope
    }

    // MARK: Préparation

    func prepare(_ data: Data, suggestedName: String) async throws -> MessagingPreparedMedia {
        try await ensureActive()
        do {
            // ImageIO/PDFKit sont bloquants : le décodage ne doit jamais tenir le MainActor.
            let prepared = try await Task.detached(priority: .userInitiated) { [preparer] in
                try preparer.prepare(data, suggestedName: suggestedName)
            }.value
            try await ensureActive()
            return prepared
        } catch let failure as MessagingMediaRuntimeFailure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as MessagingMediaPreparationFailure {
            throw Self.map(failure)
        } catch {
            throw MessagingMediaRuntimeFailure.unreadable
        }
    }

    // MARK: Mise en file

    func enqueue(_ prepared: MessagingPreparedMedia, clientMessageID: UUID,
                 conversationID: UUID, caption: String?, mentionPersonIDs: [UUID],
                 replyToMessageID: UUID?) async throws -> MessagingMediaPendingSnapshot {
        try await ensureActive()

        guard let name = MessagingMediaName.sanitized(prepared.name), name == prepared.name else {
            throw MessagingMediaRuntimeFailure.invalidContent
        }
        guard (MessagingMediaAttachment.minimumByteSize...MessagingMediaAttachment.maximumByteSize)
            .contains(prepared.data.count) else {
            throw MessagingMediaRuntimeFailure.invalidSize
        }
        let normalizedCaption = Self.normalizedCaption(caption)
        guard (normalizedCaption?.count ?? 0) <= MessagingMediaContent.maximumTextLength else {
            throw MessagingMediaRuntimeFailure.invalidContent
        }
        guard mentionPersonIDs.count <= Self.maximumMentions,
              Set(mentionPersonIDs).count == mentionPersonIDs.count else {
            throw MessagingMediaRuntimeFailure.invalidContent
        }

        // Le sceau porte l'identifiant média et les octets : une seule fois, jamais recréé.
        let sealed: MessagingSealedMedia
        do {
            sealed = try cryptography.seal(prepared.data)
        } catch let failure as MessagingMediaCryptographyFailure {
            throw Self.map(failure)
        } catch {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }

        let content: MessagingMediaContentV3
        do {
            let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
                mime: prepared.mime, name: name, width: prepared.width, height: prepared.height,
                file: sealed.info)
            content = try MessagingMediaContentV3(text: normalizedCaption, media: attachment)
        } catch {
            throw MessagingMediaRuntimeFailure.invalidContent
        }

        let intent = MessagingPendingMedia(clientMessageID: clientMessageID,
            conversationID: conversationID, sealed: sealed, content: content,
            mentionPersonIDs: mentionPersonIDs, replyToMessageID: replyToMessageID, createdAt: Date())

        try await ensureActive()
        do {
            // Le sceau et le contenu sont durables avant tout dépôt, et avant le chiffrement.
            try await outbox.put(intent, scope: scope)
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }

        let envelope: MessagingCiphertext
        do {
            envelope = try await encryption.encryptMatrixContent(content, mentions: mentionPersonIDs,
                scope: scope, conversationID: conversationID)
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }

        do {
            // CAS explicite : l'enveloppe Megolm est durable avant toute émission.
            try await outbox.replaceEnvelope(mediaID: sealed.mediaID, expected: nil,
                replacement: envelope, scope: scope)
        } catch let failure as MessagingFailure where failure == .stateConflict {
            // Une autre instance a déjà persisté une enveloppe : on adopte la sienne,
            // jamais un second chiffrement ni un écrasement concurrent.
            let stored = try await reload(mediaID: sealed.mediaID)
            guard stored?.messageCiphertext != nil else {
                throw MessagingMediaRuntimeFailure.resultUnknown
            }
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }

        try await ensureActive()
        return Self.snapshot(intent)
    }

    func pending(conversationID: UUID) async throws -> [MessagingMediaPendingSnapshot] {
        try await ensureActive()
        let entries: [MessagingPendingMedia]
        do {
            entries = try await outbox.entries(scope: scope)
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch {
            // Une panne de coffre n'est jamais une liste vide : elle est rendue au consommateur.
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }
        try await ensureActive()
        return entries.filter { $0.conversationID == conversationID }.map(Self.snapshot)
    }

    // MARK: Envoi

    func send(clientMessageID: UUID) async -> MessagingMediaDelivery {
        guard await isActive() else { return .pending(.contextChanged) }
        guard !active.contains(clientMessageID) else { return .pending(.alreadyInFlight) }
        active.insert(clientMessageID)
        defer { active.remove(clientMessageID) }
        do {
            guard let entry = try await storedEntry(clientMessageID: clientMessageID) else {
                return .pending(.removed)
            }
            let delivery = try await deliver(entry, upload: true)
            if case .confirmed = delivery { membersChanged.remove(clientMessageID) }
            return delivery
        } catch let failure as MessagingMediaRuntimeFailure {
            if failure == .membersChanged { membersChanged.insert(clientMessageID) }
            return .pending(failure)
        } catch {
            return .pending(.resultUnknown)
        }
    }

    func recomposeAfterMembersChanged(clientMessageID: UUID) async -> MessagingMediaDelivery {
        guard await isActive() else { return .pending(.contextChanged) }
        guard !active.contains(clientMessageID) else { return .pending(.alreadyInFlight) }
        // Une recomposition n'a de sens qu'après un refus MEMBERS_CHANGED réellement
        // observé. Une réponse perdue n'ouvre pas ce chemin.
        guard membersChanged.contains(clientMessageID) else {
            return .pending(.membersChanged)
        }
        active.insert(clientMessageID)
        defer { active.remove(clientMessageID) }
        do {
            guard let entry = try await storedEntry(clientMessageID: clientMessageID) else {
                return .pending(.removed)
            }
            guard let previous = entry.messageCiphertext else { return .pending(.membersChanged) }
            let replacement = try await encryptEnvelope(for: entry)
            do {
                try await outbox.replaceEnvelope(mediaID: entry.mediaID, expected: previous,
                    replacement: replacement, scope: scope)
            } catch let failure as MessagingFailure where failure == .stateConflict {
                return .pending(.resultUnknown)
            } catch let failure as MessagingFailure {
                throw Self.map(failure)
            } catch {
                throw MessagingMediaRuntimeFailure.protectionUnavailable
            }
            let updated = try await reload(mediaID: entry.mediaID) ?? entry
            let delivery = try await deliver(updated, upload: false)
            if case .confirmed = delivery { membersChanged.remove(clientMessageID) }
            return delivery
        } catch let failure as MessagingMediaRuntimeFailure {
            return .pending(failure)
        } catch {
            return .pending(.resultUnknown)
        }
    }

    /// Dépôt idempotent puis POST. `upload` est faux seulement pour la recomposition
    /// d'enveloppe après un `MESSAGING_MEMBERS_CHANGED` déjà constaté : les octets média
    /// ne sont jamais re-déposés dans ce cas.
    private func deliver(_ entry: MessagingPendingMedia, upload: Bool) async throws -> MessagingMediaDelivery {
        try await ensureActive()
        var current = entry

        if current.messageCiphertext == nil {
            let envelope = try await encryptEnvelope(for: current)
            do {
                try await outbox.replaceEnvelope(mediaID: current.mediaID, expected: nil,
                    replacement: envelope, scope: scope)
            } catch let failure as MessagingFailure {
                throw Self.map(failure)
            } catch {
                throw MessagingMediaRuntimeFailure.protectionUnavailable
            }
            current = try await reload(mediaID: current.mediaID) ?? current
        }

        try await ensureActive()
        if upload {
            let transport = try await currentTransport()
            let receipt: MessagingMediaReceipt
            do {
                receipt = try await transport.upload(current.sealed, scope: scope,
                    conversationID: current.conversationID)
            } catch let failure as MessagingMediaTransportFailure {
                throw Self.map(failure, lostResult: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MessagingMediaRuntimeFailure.resultUnknown
            }
            guard receipt.mediaID == current.mediaID,
                  receipt.byteSize == current.sealed.byteSize,
                  receipt.sha256 == Self.hex(SHA256.hash(data: current.sealed.ciphertext)) else {
                throw MessagingMediaRuntimeFailure.integrity
            }
        }

        try await ensureActive()
        guard let envelope = current.messageCiphertext else {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }
        let message = MessagingPending(clientMessageID: current.clientMessageID,
            conversationID: current.conversationID, ciphertext: envelope,
            mentionPersonIDs: current.mentionPersonIDs, replyToMessageID: current.replyToMessageID,
            poll: nil, recoveryContent: nil)
        let media: MessagingMediaMessageIntent
        do {
            media = try MessagingMediaMessageIntent(mediaID: current.mediaID,
                byteSize: current.sealed.byteSize)
        } catch {
            throw MessagingMediaRuntimeFailure.invalidSize
        }

        let acknowledgement: MessagingAcknowledgement
        do {
            acknowledgement = try await sending.sendMedia(scope: scope, pending: message, media: media)
        } catch let failure as MessagingMediaRuntimeFailure {
            throw failure
        } catch let failure as MessagingMediaTransportFailure {
            throw Self.map(failure, lostResult: true)
        } catch let failure as MessagingFailure {
            // Un POST peut avoir été accepté avant une réponse perdue : ce n'est pas un refus.
            throw Self.mapSend(failure)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MessagingMediaRuntimeFailure.resultUnknown
        }

        guard acknowledgement.clientMessageID == current.clientMessageID,
              acknowledgement.conversationID == current.conversationID,
              acknowledgement.schoolID == scope.schoolID,
              acknowledgement.senderID == scope.accountID else {
            throw MessagingMediaRuntimeFailure.resultUnknown
        }

        // Le reçu serveur est validé : un changement de contexte ou un défaut de nettoyage
        // local ne transforme pas ce succès en échec d'envoi.
        do {
            try await outbox.remove(mediaID: current.mediaID, scope: scope)
        } catch {
            // Le reçu serveur est valide : un échec d'effacement local ne le transforme
            // jamais en faux échec d'envoi.
            return .confirmed(acknowledgement, cleanupPending: true)
        }
        return .confirmed(acknowledgement, cleanupPending: false)
    }

    // MARK: Lecture

    func open(_ message: MessagingWireMessage) async throws -> MessagingPreparedMedia {
        try await ensureActive()
        guard message.schoolID == scope.schoolID else {
            throw MessagingMediaRuntimeFailure.contextChanged
        }
        guard !message.meta.deletedForEveryone else {
            throw MessagingMediaRuntimeFailure.removed
        }

        let decrypted: MessagingDecryptedContent
        do {
            decrypted = try await encryption.decryptContent(message, scope: scope)
        } catch is MessagingDecryptionFailure {
            throw MessagingMediaRuntimeFailure.unreadable
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MessagingMediaRuntimeFailure.unreadable
        }
        try await ensureActive()

        guard decrypted.provenance == .matrixContent,
              let content = MessagingPlainContent.decodeMatrixContent(decrypted.bytes),
              let media = content.media else {
            throw MessagingMediaRuntimeFailure.invalidContent
        }
        // Les métadonnées serveur authentifient la référence avant tout octet média.
        guard let reference = message.meta.media, !reference.deleted else {
            throw MessagingMediaRuntimeFailure.removed
        }
        guard reference.mediaID == media.id, reference.byteSize == media.size else {
            throw MessagingMediaRuntimeFailure.integrity
        }

        var cached: Data?
        do {
            cached = try await cache.data(mediaID: media.id, scope: scope)
        } catch {
            // Un cache fermé n'autorise aucun repli clair : on retente le téléchargement
            // authentifié. Aucune donnée non validée n'est rendue depuis ce cache.
            cached = nil
        }

        let plaintext: Data
        if let cached {
            plaintext = cached
        } else {
            let transport = try await currentTransport()
            let ciphertext: Data
            do {
                ciphertext = try await transport.download(mediaID: media.id, scope: scope,
                    conversationID: message.conversationID)
            } catch let failure as MessagingMediaTransportFailure {
                throw Self.map(failure, lostResult: false)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MessagingMediaRuntimeFailure.unavailable
            }
            do {
                plaintext = try cryptography.open(ciphertext, info: media.file)
            } catch let failure as MessagingMediaCryptographyFailure {
                throw Self.map(failure)
            } catch {
                throw MessagingMediaRuntimeFailure.integrity
            }
        }
        guard plaintext.count == media.size else {
            throw MessagingMediaRuntimeFailure.integrity
        }

        // Format et dimensions sont vérifiés avant tout rendu ; l'original n'est jamais
        // ré-encodé ni écrit en clair. Seule la miniature reconstruite est conservée.
        let prepared: MessagingPreparedMedia
        do {
            prepared = try await prepare(plaintext, suggestedName: media.name)
        } catch let failure as MessagingMediaRuntimeFailure {
            try? await cache.purge(mediaIDs: [media.id], scope: scope)
            throw failure
        }
        guard prepared.mime == media.mime else {
            try? await cache.purge(mediaIDs: [media.id], scope: scope)
            throw MessagingMediaRuntimeFailure.invalidFormat
        }
        if let width = media.width, let height = media.height {
            guard prepared.width == width, prepared.height == height else {
                try? await cache.purge(mediaIDs: [media.id], scope: scope)
                throw MessagingMediaRuntimeFailure.integrity
            }
        } else {
            guard prepared.width == nil, prepared.height == nil else {
                try? await cache.purge(mediaIDs: [media.id], scope: scope)
                throw MessagingMediaRuntimeFailure.integrity
            }
        }

        if cached == nil {
            try? await cache.store(plaintext, mediaID: media.id, scope: scope)
        }
        if let thumbnail = prepared.thumbnail {
            try? await cache.storeThumbnail(thumbnail, mediaID: media.id, scope: scope)
        }
        try await ensureActive()
        return prepared
    }

    func invalidate() async {
        invalidated = true
        transport = nil
        // Les intentions encore à vérifier restent dans la file : seule la lecture
        // déchiffrée du scope est fermée et purgée. Aucun effacement physique n'est promis.
        do { try await cache.purgeAll(scope: scope) } catch {}
    }

    // MARK: Interne

    private func isActive() async -> Bool {
        guard !invalidated else { return false }
        return await currentScope() == scope
    }

    private func ensureActive() async throws {
        guard !invalidated else { throw MessagingMediaRuntimeFailure.contextChanged }
        guard await currentScope() == scope else {
            throw MessagingMediaRuntimeFailure.contextChanged
        }
    }

    private func storedEntry(clientMessageID: UUID) async throws -> MessagingPendingMedia? {
        let entries: [MessagingPendingMedia]
        do {
            entries = try await outbox.entries(scope: scope)
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }
        return entries.first { $0.clientMessageID == clientMessageID }
    }

    private func reload(mediaID: UUID) async throws -> MessagingPendingMedia? {
        let entries: [MessagingPendingMedia]
        do {
            entries = try await outbox.entries(scope: scope)
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }
        return entries.first { $0.mediaID == mediaID }
    }

    private func encryptEnvelope(for entry: MessagingPendingMedia) async throws -> MessagingCiphertext {
        do {
            return try await encryption.encryptMatrixContent(entry.content,
                mentions: entry.mentionPersonIDs, scope: scope, conversationID: entry.conversationID)
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MessagingMediaRuntimeFailure.protectionUnavailable
        }
    }

    private func currentTransport() async throws -> any MessagingMediaTransport {
        if let transport { return transport }
        let created: any MessagingMediaTransport
        do {
            created = try await transportFactory()
        } catch let failure as MessagingFailure {
            throw Self.map(failure)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MessagingMediaRuntimeFailure.unavailable
        }
        guard await isActive() else {
            throw MessagingMediaRuntimeFailure.contextChanged
        }
        transport = created
        return created
    }

    private static func normalizedCaption(_ caption: String?) -> String? {
        guard let caption else { return nil }
        return caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caption
    }

    private static func snapshot(_ entry: MessagingPendingMedia) -> MessagingMediaPendingSnapshot {
        MessagingMediaPendingSnapshot(clientMessageID: entry.clientMessageID,
            mediaID: entry.mediaID, conversationID: entry.conversationID,
            caption: entry.content.text, name: entry.content.media.name,
            mime: entry.content.media.mime, byteSize: entry.sealed.byteSize,
            createdAt: entry.createdAt)
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Traduction fermée des erreurs

    private static func map(_ failure: MessagingMediaPreparationFailure) -> MessagingMediaRuntimeFailure {
        switch failure {
        case .invalidSize: return .invalidSize
        case .invalidName: return .invalidContent
        case .invalidFormat: return .invalidFormat
        case .invalidDimensions: return .invalidFormat
        case .unreadable: return .unreadable
        case .lockedPDF: return .lockedPDF
        case .thumbnailUnavailable: return .unreadable
        }
    }

    private static func map(_ failure: MessagingMediaCryptographyFailure) -> MessagingMediaRuntimeFailure {
        switch failure {
        case .invalidSize: return .invalidSize
        case .invalidEncryptionInfo: return .integrity
        case .integrityMismatch: return .integrity
        case .randomnessUnavailable, .cipherUnavailable: return .protectionUnavailable
        }
    }

    /// Traduction du POST : une panne ou une réponse illisible laisse le résultat inconnu,
    /// jamais un refus définitif ni un succès. Seuls les refus explicites gardent leur sens.
    private static func mapSend(_ failure: MessagingFailure) -> MessagingMediaRuntimeFailure {
        switch failure {
        case .membersChanged: return .membersChanged
        case .contextChanged: return .contextChanged
        case .accessChanged: return .accessChanged
        case .protectionUnavailable: return .protectionUnavailable
        case .conversationUnavailable: return .removed
        case .unavailable, .invalidResponse, .stateConflict: return .resultUnknown
        default: return .unavailable
        }
    }

    private static func map(_ failure: MessagingFailure) -> MessagingMediaRuntimeFailure {
        switch failure {
        case .contextChanged: return .contextChanged
        case .accessChanged: return .accessChanged
        case .protectionUnavailable: return .protectionUnavailable
        case .membersChanged: return .membersChanged
        case .invalidResponse: return .invalidContent
        case .stateConflict: return .resultUnknown
        case .unavailable: return .unavailable
        case .conversationUnavailable: return .removed
        case .deviceLimitReached: return .protectionUnavailable
        default: return .unavailable
        }
    }

    private static func map(_ failure: MessagingMediaTransportFailure,
                            lostResult: Bool) -> MessagingMediaRuntimeFailure {
        switch failure {
        case .invalidIntent: return .invalidContent
        case .tooLarge, .sizeConflict: return .invalidSize
        case .contextChanged: return .contextChanged
        case .accessChanged, .deviceRequired: return .accessChanged
        case .notFound, .purged: return .removed
        case .intentConflict, .integrityMismatch: return .integrity
        case .alreadyAttached: return .resultUnknown
        case .stateConflict, .invalidResponse: return .resultUnknown
        case .unavailable: return lostResult ? .resultUnknown : .unavailable
        }
    }
}
