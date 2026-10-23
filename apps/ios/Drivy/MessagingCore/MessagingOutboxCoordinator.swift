import Foundation

struct UnavailableMessagingOutbox: MessagingProtectedOutbox {
    func put(_ entry: MessagingPending, scope: MessagingScope) async throws { throw MessagingFailure.protectionUnavailable }
    func entries(scope: MessagingScope) async throws -> [MessagingPending] { throw MessagingFailure.protectionUnavailable }
    func remove(clientMessageID: UUID, scope: MessagingScope) async throws { throw MessagingFailure.protectionUnavailable }
}

/// File autonome : aucun verrou ni dépendance envers les commandes GPS ou la leçon.
/// Un succès signifie réponse serveur validée, jamais livraison à un autre appareil ni lecture.
actor MessagingOutboxCoordinator {
    enum Delivery: Sendable { case waiting, accepted(MessagingAcknowledgement), failed(MessagingFailure) }
    private let scope: MessagingScope
    private let service: any MessagingService
    private let cryptography: any MessagingCryptography
    private let outbox: any MessagingProtectedOutbox
    private let currentScope: @MainActor @Sendable () -> MessagingScope?
    private var active: Set<UUID> = []
    /// Échecs observés dans cette instance de scope, indexés par intention puis conversation.
    private var membersConflicts: [UUID: UUID] = [:]

    init(scope: MessagingScope, service: any MessagingService,
         cryptography: any MessagingCryptography = UnavailableMessagingCryptography(),
         outbox: any MessagingProtectedOutbox = UnavailableMessagingOutbox(),
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope? = { nil }) {
        self.scope = scope
        self.service = service
        self.cryptography = cryptography
        self.outbox = outbox
        self.currentScope = currentScope
    }

    /// En l'absence de file protégée, la saisie ne quitte jamais la mémoire ni le réseau.
    func enqueue(text: String, conversationID: UUID, mentions: [UUID] = [], currentScope: MessagingScope) async throws -> MessagingPending {
        guard currentScope == scope else { throw MessagingFailure.contextChanged }
        guard await self.currentScope() == scope else { throw MessagingFailure.contextChanged }
        if let failure = await cryptography.availabilityFailure(scope: scope, conversationID: conversationID) { throw failure }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 16_384, mentions.count <= 8,
              Set(mentions).count == mentions.count else { throw MessagingFailure.invalidResponse }
        let ciphertext = try await cryptography.encrypt(Data(text.utf8), mentions: mentions,
            scope: scope, conversationID: conversationID)
        guard await self.currentScope() == scope else { throw MessagingFailure.contextChanged }
        guard Self.validEnvelope(ciphertext) else { throw MessagingFailure.invalidResponse }
        guard Self.hasEncryptionEpoch(ciphertext) else { throw MessagingFailure.protectionUnavailable }
        let entry = MessagingPending(clientMessageID: UUID(), conversationID: conversationID,
            ciphertext: ciphertext, mentionPersonIDs: mentions, recoveryContent: Data(text.utf8))
        try await outbox.put(entry, scope: scope)
        return entry
    }

    /// v2 : texte ou sondage, réponse citée. Le contenu est encodé puis chiffré, jamais stocké en clair.
    func enqueue(content: MessagingPlainContent, conversationID: UUID, mentions: [UUID] = [],
                 replyTo: UUID? = nil, pollAllowsMultiple: Bool = false, currentScope: MessagingScope) async throws -> MessagingPending {
        guard currentScope == scope, await self.currentScope() == scope else { throw MessagingFailure.contextChanged }
        if let failure = await cryptography.availabilityFailure(scope: scope, conversationID: conversationID) { throw failure }
        let hasText = !(content.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText != (content.poll != nil), mentions.count <= 8, Set(mentions).count == mentions.count else {
            throw MessagingFailure.invalidResponse
        }
        if let poll = content.poll {
            guard MessagingPollRules.validated(question: poll.question, options: poll.options.map(\.label)) != nil else {
                throw MessagingFailure.invalidResponse
            }
        }
        let recoveryContent = try content.encoded()
        let ciphertext = try await cryptography.encrypt(recoveryContent, mentions: mentions,
            scope: scope, conversationID: conversationID)
        guard await self.currentScope() == scope else { throw MessagingFailure.contextChanged }
        guard Self.validEnvelope(ciphertext) else { throw MessagingFailure.invalidResponse }
        guard Self.hasEncryptionEpoch(ciphertext) else { throw MessagingFailure.protectionUnavailable }
        let entry = MessagingPending(clientMessageID: UUID(), conversationID: conversationID,
            ciphertext: ciphertext, mentionPersonIDs: mentions, replyToMessageID: replyTo,
            poll: content.poll.map { MessagingPollDraftMeta(allowsMultiple: pollAllowsMultiple, optionIDs: $0.options.map(\.id)) },
            recoveryContent: recoveryContent)
        try await outbox.put(entry, scope: scope)
        return entry
    }

    func pending(currentScope: MessagingScope) async throws -> [MessagingPending] {
        guard currentScope == scope, await self.currentScope() == scope else { throw MessagingFailure.contextChanged }
        return try await outbox.entries(scope: scope)
    }

    func retry(_ entry: MessagingPending, currentScope: MessagingScope) async -> Delivery {
        guard currentScope == scope else { return .failed(.contextChanged) }
        guard await self.currentScope() == scope else { return .failed(.contextChanged) }
        guard Self.validEnvelope(entry.ciphertext) else { return .failed(.invalidResponse) }
        if let failure = await cryptography.availabilityFailure(scope: scope, conversationID: entry.conversationID) { return .failed(failure) }
        guard !active.contains(entry.clientMessageID) else { return .waiting }
        active.insert(entry.clientMessageID)
        defer { active.remove(entry.clientMessageID) }
        do {
            // Même identifiant, octets et époque, y compris pour une archive ancienne sans époque.
            // Seul le serveur peut distinguer réponse perdue déjà acceptée et intention nouvelle périmée.
            // Un refus conserve aussi le contenu de récupération dans le snapshot protégé.
            let acknowledgement = try await service.send(scope: scope, pending: entry)
            guard await self.currentScope() == scope else { return .failed(.contextChanged) }
            guard acknowledgement.clientMessageID == entry.clientMessageID,
                  acknowledgement.conversationID == entry.conversationID,
                  acknowledgement.schoolID == scope.schoolID,
                  acknowledgement.senderID == scope.accountID else { return .failed(.invalidResponse) }
            try await outbox.remove(clientMessageID: entry.clientMessageID, scope: scope)
            membersConflicts.removeValue(forKey: entry.clientMessageID)
            return .accepted(acknowledgement)
        } catch let failure as MessagingFailure {
            guard await self.currentScope() == scope else { return .failed(.contextChanged) }
            if failure == .membersChanged { membersConflicts[entry.clientMessageID] = entry.conversationID }
            return .failed(failure)
        }
        catch { return .failed(.unavailable) }
    }

    func hasMembersConflict(conversationID: UUID, currentScope: MessagingScope) async -> Bool {
        guard currentScope == scope, await self.currentScope() == scope else { return false }
        return membersConflicts.values.contains(conversationID)
    }

    /// Une reprise par événement, au plus vingt requêtes, sans boucle réseau ni nouveau chiffrement.
    func flushPending(currentScope: MessagingScope) async -> [Delivery] {
        guard currentScope == scope, await self.currentScope() == scope else { return [.failed(.contextChanged)] }
        let entries: [MessagingPending]
        do { entries = try await outbox.entries(scope: scope) }
        catch { return [.failed(.protectionUnavailable)] }
        var results: [Delivery] = []
        for entry in entries.prefix(20) {
            guard await self.currentScope() == scope else { results.append(.failed(.contextChanged)); break }
            let result = await retry(entry, currentScope: currentScope)
            results.append(result)
            if case .failed(let failure) = result,
               failure == .accessChanged || failure == .contextChanged || failure == .protectionUnavailable || failure == .deviceLimitReached { break }
        }
        return results
    }

    private static func validEnvelope(_ value: MessagingCiphertext) -> Bool {
        let scheme = value.scheme.utf8, key = value.keyID.utf8
        guard (1...80).contains(scheme.count), (1...128).contains(key.count),
              !value.payload.isEmpty, value.payload.base64EncodedString().utf8.count <= 12_000 else { return false }
        return scheme.allSatisfy { ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 46 || $0 == 95 || $0 == 45 }
            && key.allSatisfy { ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 46 || $0 == 95 || $0 == 45 || $0 == 58 }
    }

    private static func hasEncryptionEpoch(_ value: MessagingCiphertext) -> Bool {
        guard let epoch = value.expectedMembersEpoch else { return false }
        return epoch >= 0 && epoch <= 9_007_199_254_740_991
    }
}
