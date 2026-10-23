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
        guard await cryptography.isAvailable(scope: scope, conversationID: conversationID) else { throw MessagingFailure.protectionUnavailable }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 16_384, mentions.count <= 8,
              Set(mentions).count == mentions.count else { throw MessagingFailure.invalidResponse }
        let ciphertext = try await cryptography.encrypt(Data(text.utf8), mentions: mentions,
            scope: scope, conversationID: conversationID)
        guard await self.currentScope() == scope else { throw MessagingFailure.contextChanged }
        guard !ciphertext.scheme.isEmpty, !ciphertext.keyID.isEmpty, !ciphertext.payload.isEmpty else {
            throw MessagingFailure.protectionUnavailable
        }
        let entry = MessagingPending(clientMessageID: UUID(), conversationID: conversationID,
            ciphertext: ciphertext, mentionPersonIDs: mentions)
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
        guard await cryptography.isAvailable(scope: scope, conversationID: entry.conversationID) else { return .failed(.protectionUnavailable) }
        guard !active.contains(entry.clientMessageID) else { return .waiting }
        active.insert(entry.clientMessageID)
        defer { active.remove(entry.clientMessageID) }
        do {
            // Un appel réseau unique. Une réponse perdue garde le même identifiant lors du prochain essai.
            let acknowledgement = try await service.send(scope: scope, pending: entry)
            guard await self.currentScope() == scope else { return .failed(.contextChanged) }
            guard acknowledgement.clientMessageID == entry.clientMessageID,
                  acknowledgement.conversationID == entry.conversationID,
                  acknowledgement.schoolID == scope.schoolID,
                  acknowledgement.senderID == scope.accountID else { return .failed(.invalidResponse) }
            try await outbox.remove(clientMessageID: entry.clientMessageID, scope: scope)
            return .accepted(acknowledgement)
        } catch let failure as MessagingFailure { return .failed(failure) }
        catch { return .failed(.unavailable) }
    }
}
