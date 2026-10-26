import Foundation
import Observation

/// Aperçu de la dernière activité d'une conversation, issu de la mémoire ou de l'historique scellé local.
struct MessagingInboxPreview: Equatable, Sendable {
    let text: String?
    let date: Date?
    let fromMe: Bool
    let unavailable: Bool
}

/// État éphémère par contexte, sans cache transversal ni persistance de texte déchiffré.
@MainActor
@Observable final class MessagingWorkspace {
    let scope: MessagingScope
    private let service: any MessagingService
    private let crypto: any MessagingCryptography
    private let directory: any MessagingDirectoryService
    private let drafts: any MessagingProtectedDrafts
    private let currentScope: @MainActor @Sendable () -> MessagingScope?
    private let actions: any MessagingThreadActions
    private let history: any MessagingHistoryStore
    private let reportSealing: any MessagingReportSealing
    private let reports: any MessagingProtectedReports
    private let mutationStore: any MessagingProtectedMutations
    private let photoLoader: @Sendable (UUID) async -> Data?
    let outbox: MessagingOutboxCoordinator
    private(set) var members: [MessagingMember] = []
    /// Retirés pendant la session, en mémoire seulement.
    private(set) var removedMembers: [MessagingMember] = []
    private(set) var photos: [UUID: Data] = [:]
    private var photoRequested: Set<UUID> = []
    private(set) var accessByConversation: [UUID: MessagingConversationAccess] = [:]
    private(set) var receipts: [UUID: [MessagingReadReceipt]] = [:]
    /// Contenu déchiffré en mémoire, recopié dans l'historique scellé quand il est disponible.
    private(set) var contents: [UUID: MessagingPlainContent] = [:]
    /// Raison non sensible d'un déchiffrement impossible, affichée à la place du contenu.
    private(set) var decryptionCodes: [UUID: String] = [:]
    private(set) var hiddenForMe: Set<UUID> = []
    private(set) var actionError: MessagingFailure?
    private struct ReportOperationKey: Hashable {
        let scope: MessagingScope
        let conversationID: UUID
    }
    /// MainActor sérialise acquisition/libération, sans verrou bloquant pendant les awaits.
    /// Partagé par toutes les instances, du début du scellement à la fin du POST/ACK ou abandon.
    private static var activeReportOperations: Set<ReportOperationKey> = []
    private(set) var contacts: [MessagingContact] = []
    private(set) var generalMembers: [MessagingContact] = []
    private(set) var conversations: [MessagingConversation] = []
    private(set) var messages: [UUID: [MessagingWireMessage]] = [:]
    private(set) var readStates: [UUID: MessagingReadState] = [:]
    private(set) var conversationCursor: String?
    private(set) var messageCursors: [UUID: String] = [:]
    private(set) var error: MessagingFailure?
    /// Chargement de la liste seulement : un chargement de fil n'empêche jamais celui de la liste, et inversement.
    private(set) var loading = false
    private var loadingMessages: Set<UUID> = []
    private(set) var resumeGeneration = 0
    private var resuming = false
    private var loadedConversations = false
    private var loadedMessages: Set<UUID> = []
    private var visibleMessageConversationID: UUID?
    private var requestedRead: [UUID: Int] = [:]
    private var readInFlight: Set<UUID> = []
    private let notifications: any MessagingNotificationCleaning
    /// Projection des intentions scellées par cible. L'état serveur reste dans `messages`.
    private(set) var pendingMutations: [MessagingMutationKey: MessagingPendingMutation] = [:]
    private var mutationsRestored = false
    private var mutationRestoration: Task<Bool, Never>?
    private var persistedMutationClocks: [MessagingMutationKey: UUID] = [:]
    private var persistedMutations: [MessagingMutationKey: MessagingPendingMutation] = [:]
    private var mutationPersistence: [MessagingMutationKey: Task<Bool, Never>] = [:]
    private var restoredMutations: Set<MessagingMutationKey> = []
    /// Une seule requête en vol par cible ; à sa réponse, le dernier état souhaité est renvoyé si besoin.
    private var mutationsInFlight: Set<MessagingMutationKey> = []
    /// Refus explicite par message, affiché sur la bulle concernée.
    private(set) var rejections: [UUID: MessagingMutationRejection] = [:]
    /// Hors connexion connu (MessagingConnectivity) : aucune attente artificielle, renvoi à la reconnexion.
    private(set) var networkOffline = false
    /// Actions sensibles en cours : « En cours » visible, effet annoncé seulement après confirmation.
    private(set) var operationsInProgress: Set<String> = []
    private var reloadAgain: Set<UUID> = []
    let mutationLatency: MessagingMutationLatency
    /// Au-delà, une intention confirmée mais toujours absente des relectures cède à l'état serveur.
    static let confirmationGrace: TimeInterval = 30

    init(scope: MessagingScope, service: any MessagingService = UnavailableMessagingService(),
         cryptography: any MessagingCryptography = UnavailableMessagingCryptography(),
         outbox: any MessagingProtectedOutbox = UnavailableMessagingOutbox(),
         drafts: any MessagingProtectedDrafts = UnavailableMessagingDrafts(),
         directory: any MessagingDirectoryService = UnavailableMessagingDirectory(),
         actions: any MessagingThreadActions = UnavailableMessagingThreadActions(),
         history: any MessagingHistoryStore = UnavailableMessagingHistory(),
         reportSealing: any MessagingReportSealing = UnavailableMessagingReportSealing(),
         reports: any MessagingProtectedReports = UnavailableMessagingReports(),
         mutations: any MessagingProtectedMutations = UnavailableMessagingMutations(),
         photoLoader: @escaping @Sendable (UUID) async -> Data? = { _ in nil },
         notifications: any MessagingNotificationCleaning = SystemMessagingNotifications(),
         mutationLatency: MessagingMutationLatency = MessagingMutationLatency(),
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope? = { nil }) {
        self.actions = actions
        self.mutationLatency = mutationLatency
        self.notifications = notifications
        self.history = history
        self.reportSealing = reportSealing
        self.reports = reports
        self.mutationStore = mutations
        self.photoLoader = photoLoader
        self.scope = scope
        self.service = service
        self.crypto = cryptography
        self.drafts = drafts
        self.directory = directory
        self.currentScope = currentScope
        self.outbox = MessagingOutboxCoordinator(scope: scope, service: service,
            cryptography: cryptography, outbox: outbox, currentScope: currentScope)
    }

    var canLoadMoreConversations: Bool { conversationCursor != nil }
    func canLoadMoreMessages(_ conversationID: UUID) -> Bool { messageCursors[conversationID] != nil }

    func loadConversations(more: Bool = false) async {
        guard !loading, !more || conversationCursor != nil else { return }
        loading = true; defer { loading = false }
        _ = await restoreMutations()
        do {
            let cursor = more ? conversationCursor : nil
            let page = try await service.conversations(scope: scope, cursor: cursor)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            guard (cursor == nil || page.nextCursor != cursor), page.items.allSatisfy({ $0.schoolID == scope.schoolID && ($0.unreadCount ?? 0) >= 0 && $0.lastSequence >= 0 }),
                  Set(page.items.map(\.id)).count == page.items.count else { throw MessagingFailure.invalidResponse }
            conversations = more ? conversations + page.items.filter { item in !conversations.contains(where: { $0.id == item.id }) } : page.items
            for item in page.items {
                mergeReadState(MessagingReadState(lastReadSequence: item.lastReadSequence,
                    mutedUntil: item.mutedUntil, version: item.readStateVersion), conversationID: item.id)
            }
            conversationCursor = page.nextCursor
            loadedConversations = true
            error = nil
            for item in page.items { await reconcileMutations(item.id, readMute: true) }
            resumeMutations()
            // #103 : état serveur relu (autre appareil compris) → alertes déjà lues retirées, badge recalculé.
            // Première page seulement pour le badge : il reflète les compteurs connus, jamais un zéro aveugle.
            for item in page.items where item.lastReadSequence > 0 {
                await notifications.removeDelivered(schoolID: scope.schoolID, conversationID: item.id, upTo: item.lastReadSequence)
            }
            if !more { await notifications.setMessagingBadge(unreadTotal) }
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func refreshVisible(conversationID: UUID? = nil) async {
        guard !resuming, currentScope() == scope else { return }
        if let conversationID { visibleMessageConversationID = conversationID }
        resuming = true
        defer { resuming = false; resumeGeneration += 1 }
        resumeSends()
        let results = await outbox.flushPending(currentScope: scope)
        for result in results {
            if case .failed(let failure) = result,
               failure == .accessChanged || failure == .contextChanged || failure == .protectionUnavailable || failure == .deviceLimitReached {
                recordFailure(failure)
                return
            }
        }
        guard currentScope() == scope else { recordFailure(.contextChanged); return }
        await loadConversations()
        if let conversationID, visibleMessageConversationID == conversationID { await loadMessages(conversationID) }
    }

    func loadMessages(_ conversationID: UUID, more: Bool = false, marksVisible: Bool = true) async {
        if marksVisible {
            visibleMessageConversationID = conversationID
            if error == .membersChanged { error = nil }
        }
        guard !loadingMessages.contains(conversationID) else {
            // Relecture demandée pendant une autre : relancée après, pour ne pas garder une page antérieure à l'écriture.
            if !more { reloadAgain.insert(conversationID) }
            return
        }
        guard !more || messageCursors[conversationID] != nil else { return }
        loadingMessages.insert(conversationID); defer { loadingMessages.remove(conversationID) }
        _ = await restoreMutations()
        defer {
            if reloadAgain.remove(conversationID) != nil, currentScope() == scope {
                Task { await self.loadMessages(conversationID, marksVisible: false) }
            }
        }
        do {
            let cursor = more ? messageCursors[conversationID] : nil
            let page = try await service.messages(scope: scope, conversationID: conversationID, before: cursor)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            guard (cursor == nil || page.nextCursor != cursor),
                  page.items.allSatisfy({ $0.schoolID == scope.schoolID && $0.conversationID == conversationID }),
                  Set(page.items.map(\.id)).count == page.items.count else { throw MessagingFailure.invalidResponse }
            messages[conversationID] = Self.mergedMessages(messages[conversationID] ?? [], page.items)
            // Un rechargement initial ne doit pas faire oublier la suite des pages anciennes déjà parcourues.
            if more || !loadedMessages.contains(conversationID) {
                messageCursors[conversationID] = page.nextCursor
            }
            if let pageAccess = page.access {
                accessByConversation[conversationID] = pageAccess
                if let limit = pageAccess.readableUntilSequence {
                    try? await history.truncate(conversationID: conversationID, after: limit, scope: scope)
                }
            }
            await reconcileMutations(conversationID)
            resumeMutations()
            if !more { receipts[conversationID] = page.readReceipts }
            let deleted = page.items.filter(\.meta.deletedForEveryone).map(\.id)
            if !deleted.isEmpty {
                for id in deleted { contents.removeValue(forKey: id) }
                try? await history.remove(messageIDs: deleted, scope: scope)
            }
            loadedMessages.insert(conversationID)
            error = nil
            let membersChanged = await outbox.hasMembersConflict(conversationID: conversationID, currentScope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            if visibleMessageConversationID == conversationID, membersChanged { error = .membersChanged }
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func text(for message: MessagingWireMessage) async -> String? {
        await content(for: message)?.summary
    }

    /// Déchiffre via MessagingCryptography, puis recopie dans l'historique scellé pour la recherche.
    func content(for message: MessagingWireMessage) async -> MessagingPlainContent? {
        if let known = contents[message.id] { return known }
        guard message.schoolID == scope.schoolID else { error = .contextChanged; return nil }
        guard message.ciphertext != nil, !message.meta.deletedForEveryone else { return nil }
        do {
            let bytes = try await crypto.decrypt(message, scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            guard let value = MessagingPlainContent.decode(bytes) else { throw MessagingFailure.invalidResponse }
            contents[message.id] = value
            decryptionCodes[message.id] = nil
            try? await history.upsert([MessagingHistoryEntry(messageID: message.id, conversationID: message.conversationID,
                sequence: message.meta.sequence, senderID: message.senderID, acceptedAt: message.acceptedAt,
                content: value)], scope: scope)
            return value
        } catch let failure as MessagingDecryptionFailure {
            // Un message illisible n'est pas une panne de la conversation : code sur la bulle seulement.
            decryptionCodes[message.id] = MessagingDiagnostics.isSafe(failure.code) ? failure.code : "D-X"
            return nil
        }
        catch let failure as MessagingFailure { recordFailure(failure); return nil }
        catch { recordFailure(.protectionUnavailable); return nil }
    }

    func loadContacts() async {
        do {
            let result = try await directory.contacts(scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            contacts = result; error = nil
        }
        catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func loadGeneralMembers() async {
        do {
            let result = try await directory.generalMembers(scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            generalMembers = result; error = nil
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func privateConversation(peerID: UUID) async -> UUID? {
        do {
            // Ne pas déduire l'autorisation du carnet local : le serveur revalide au PUT.
            let id = try await directory.privateConversation(scope: scope, peerID: peerID)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            error = nil; return id
        } catch let failure as MessagingFailure { recordFailure(failure); return nil }
        catch { self.error = .unavailable; return nil }
    }

    func generalConversation() async -> UUID? {
        do {
            let id = try await directory.generalConversation(scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            error = nil; return id
        }
        catch let failure as MessagingFailure { recordFailure(failure); return nil }
        catch { self.error = .unavailable; return nil }
    }

    /// Accusé serveur, puis seulement en cas de succès : compteur local, badge, alertes de CETTE conversation.
    @discardableResult func markRead(conversationID: UUID, sequence: Int) async -> Bool {
        do {
            let state = try await directory.readState(scope: scope, conversationID: conversationID,
                sequence: sequence, mutedUntil: nil, expectedVersion: nil)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            mergeReadState(state, conversationID: conversationID)
            error = nil
            applyConfirmedRead(conversationID)
            if let confirmed = readStates[conversationID]?.lastReadSequence {
                await notifications.removeDelivered(schoolID: scope.schoolID, conversationID: conversationID, upTo: confirmed)
            }
            await notifications.setMessagingBadge(unreadTotal)
            return true
        }
        catch let failure as MessagingFailure { recordFailure(failure); return false }
        catch { self.error = .unavailable; return false }
    }

    /// Bas du fil réellement affiché (#103). Borne monotone, limitée au dernier message lisible chargé,
    /// requêtes coalescées : une seule en vol par conversation, la plus haute demande gagne.
    func conversationViewed(_ id: UUID, upTo sequence: Int) async {
        guard currentScope() == scope, access(for: id).readableUntilSequence.map({ $0 > 0 }) ?? true,
              let readable = lastReadableSequence(id) else { return }
        let target = min(sequence, readable)
        guard target > (readStates[id]?.lastReadSequence ?? 0) else { return }
        requestedRead[id] = max(requestedRead[id] ?? 0, target)
        guard !readInFlight.contains(id) else { return }
        readInFlight.insert(id); defer { readInFlight.remove(id) }
        while let wanted = requestedRead[id], wanted > (readStates[id]?.lastReadSequence ?? 0) {
            requestedRead[id] = nil
            // Tâche détachée de la vue : un défilement qui relance `.task` n'annule pas un accusé en vol.
            guard await Task(operation: { await self.markRead(conversationID: id, sequence: wanted) }).value else { return }
        }
        requestedRead[id] = nil
    }

    /// Somme des non-lus messagerie connus de ce contexte.
    var unreadTotal: Int { conversations.reduce(0) { $0 + max(0, $1.unreadCount ?? 0) } }

    /// Non-lus après une lecture confirmée : zéro si la borne couvre la conversation, sinon les seuls
    /// messages reçus (pas les miens) chargés au-delà de la borne, sans dépasser le compteur serveur.
    private func applyConfirmedRead(_ id: UUID) {
        guard let read = readStates[id]?.lastReadSequence, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let item = conversations[index]
        let remaining = Self.unreadAfterRead(lastSequence: item.lastSequence, readSequence: read, serverUnread: item.unreadCount,
            loaded: messages[id] ?? [], accountID: scope.accountID)
        conversations[index] = MessagingConversation(id: item.id, schoolID: item.schoolID, kind: item.kind, title: item.title,
            identityDetail: item.identityDetail, unreadCount: remaining, lastSequence: item.lastSequence,
            lastReadSequence: max(item.lastReadSequence, read), mutedUntil: readStates[id]?.mutedUntil ?? item.mutedUntil,
            readStateVersion: max(item.readStateVersion, readStates[id]?.version ?? 0), peerPersonID: item.peerPersonID)
    }

    nonisolated static func unreadAfterRead(lastSequence: Int, readSequence: Int, serverUnread: Int?,
                                            loaded: [MessagingWireMessage], accountID: UUID) -> Int {
        let newest = max(lastSequence, loaded.map(\.meta.sequence).max() ?? 0)
        guard readSequence < newest else { return 0 }
        let after = loaded.filter { $0.meta.sequence > readSequence && $0.senderID != accountID }.count
        return min(after, serverUnread ?? after)
    }

    /// Sourdine : contrôle local immédiat, synchronisation serveur distincte. Ne promet pas l'arrêt
    /// des notifications déjà en transit.
    func silence(conversationID: UUID, fallbackSequence: Int, until: Date, fallbackVersion: Int) async {
        submitMute(conversationID, until: until, sequence: fallbackSequence, version: fallbackVersion)
    }

    func unsilence(conversationID: UUID, fallbackSequence: Int, fallbackVersion: Int) async {
        submitMute(conversationID, until: nil, sequence: fallbackSequence, version: fallbackVersion)
    }

    private func submitMute(_ conversationID: UUID, until: Date?, sequence: Int, version: Int) {
        let key = MessagingMutationKey(conversationID: conversationID, messageID: conversationID, kind: .mute)
        // Le transport ISO8601 n'émet pas de fractions : journal et réconciliation utilisent la même valeur.
        let canonical = until.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
        submit(key, desired: .mutedUntil(canonical), readState: readStates[conversationID]
            ?? MessagingReadState(lastReadSequence: sequence, mutedUntil: nil, version: version))
    }

    func muteAttention(_ conversationID: UUID) -> MessagingMutationStatus? {
        pendingMutations[MessagingMutationKey(conversationID: conversationID, messageID: conversationID, kind: .mute)]?.status
    }

    func retryMute(_ conversationID: UUID) {
        let key = MessagingMutationKey(conversationID: conversationID, messageID: conversationID, kind: .mute)
        guard !mutationsInFlight.contains(key) else { return }
        restart(key)
    }

    /// Sourdine affichée : la demande locale en cours prime sur l'état serveur connu.
    func displayedMutedUntil(_ conversationID: UUID, fallback: Date?) -> Date? {
        let key = MessagingMutationKey(conversationID: conversationID, messageID: conversationID, kind: .mute)
        if case .mutedUntil(let until) = pendingMutations[key]?.desired { return until }
        return readStates[conversationID].map(\.mutedUntil) ?? fallback
    }

    func loadDraft(_ conversationID: UUID) async throws -> String {
        guard currentScope() == scope else { throw MessagingFailure.contextChanged }
        let text = try await drafts.loadDraft(conversationID: conversationID, scope: scope)
        guard currentScope() == scope else { throw MessagingFailure.contextChanged }
        return text
    }
    func saveDraft(_ text: String, conversationID: UUID) async throws {
        guard currentScope() == scope else { throw MessagingFailure.contextChanged }
        try await drafts.saveDraft(text, conversationID: conversationID, scope: scope)
        guard currentScope() == scope else { throw MessagingFailure.contextChanged }
    }

    private func recordFailure(_ failure: MessagingFailure) {
        if failure == .accessChanged || failure == .contextChanged {
            // Effacer uniquement la mémoire affichée. La file et les brouillons scellés restent intacts.
            contacts = []
            generalMembers = []
            members = []
            removedMembers = []
            photos = [:]
            photoRequested = []
            accessByConversation = [:]
            receipts = [:]
            contents = [:]
            decryptionCodes = [:]
            hiddenForMe = []
            // #104 : aucune intention n'est rejouée sous un autre compte, une autre école ou après retrait.
            pendingMutations = [:]
            rejections = [:]
            restoredMutations = []
            reloadAgain = []
            sendStates = [:]
            sendQueues = [:]
            sendClocks = [:]
            previews = [:]
            conversations = []
            messages = [:]
            readStates = [:]
            loadedMessages = []
            loadedConversations = false
            conversationCursor = nil
            messageCursors = [:]
        }
        error = failure
    }

    func hasLoadedMessages(_ id: UUID) -> Bool { loadedMessages.contains(id) }

    /// Fusion par identifiant (la version serveur la plus récente remplace), ordre ascendant de séquence.
    /// Le serveur renvoie chaque page en séquence décroissante ; l'heure locale n'est jamais utilisée.
    static func mergedMessages(_ existing: [MessagingWireMessage], _ incoming: [MessagingWireMessage]) -> [MessagingWireMessage] {
        var byID: [UUID: MessagingWireMessage] = [:]
        for item in existing { byID[item.id] = item }
        for item in incoming { byID[item.id] = item }
        return byID.values.sorted { lhs, rhs in
            lhs.meta.sequence != rhs.meta.sequence ? lhs.meta.sequence < rhs.meta.sequence : lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: Aperçus de la boîte de réception

    /// Aperçus issus de l'historique scellé local, en mémoire seulement.
    private(set) var previews: [UUID: MessagingInboxPreview] = [:]

    private func readable(_ sequence: Int, in conversationID: UUID) -> Bool {
        guard let limit = accessByConversation[conversationID]?.readableUntilSequence else { return true }
        return sequence <= limit
    }

    /// Dernier message visible (ni masqué pour moi, ni au-delà de la limite lisible).
    func lastReadableSequence(_ id: UUID) -> Int? {
        visibleMessages(id).last { readable($0.meta.sequence, in: id) }?.meta.sequence
    }

    /// Mémoire de session d'abord (dernier message chargé), puis historique scellé. Jamais de réseau.
    func preview(for conversationID: UUID) -> MessagingInboxPreview? {
        if let last = visibleMessages(conversationID).last(where: { readable($0.meta.sequence, in: conversationID) }) {
            let fromMe = last.senderID == scope.accountID
            if let content = contents[last.id] {
                return MessagingInboxPreview(text: content.summary, date: last.acceptedAt, fromMe: fromMe, unavailable: false)
            }
            if last.meta.deletedForEveryone || decryptionCodes[last.id] != nil {
                return MessagingInboxPreview(text: nil, date: last.acceptedAt, fromMe: fromMe, unavailable: true)
            }
        }
        return previews[conversationID]
    }

    /// Lit le dernier élément de l'historique scellé de chaque conversation listée, sans requête réseau.
    func loadPreviews() async {
        guard currentScope() == scope else { recordFailure(.contextChanged); return }
        for conversation in conversations {
            guard let entries = try? await history.entries(conversationID: conversation.id, scope: scope) else { continue }
            guard currentScope() == scope else { recordFailure(.contextChanged); return }
            let last = entries
                .filter { !hiddenForMe.contains($0.messageID) && readable($0.sequence, in: conversation.id) }
                .max { $0.sequence != $1.sequence ? $0.sequence < $1.sequence : $0.messageID.uuidString < $1.messageID.uuidString }
            if let last {
                previews[conversation.id] = MessagingInboxPreview(text: last.content.summary, date: last.acceptedAt,
                    fromMe: last.senderID == scope.accountID, unavailable: false)
            } else {
                previews.removeValue(forKey: conversation.id)
            }
        }
    }

    // MARK: v2

    func access(for conversationID: UUID) -> MessagingConversationAccess { accessByConversation[conversationID] ?? .full }

    /// Projection : état serveur + intentions locales. Une relecture ne les écrase pas.
    func visibleMessages(_ conversationID: UUID) -> [MessagingWireMessage] {
        let base = (messages[conversationID] ?? []).filter { !hiddenForMe.contains($0.id) && !isHiddenLocally($0.id, in: conversationID) }
        guard pendingMutations.keys.contains(where: { $0.conversationID == conversationID }) else { return base }
        return base.map(project)
    }

    private func isHiddenLocally(_ id: UUID, in conversationID: UUID) -> Bool {
        guard let pending = pendingMutations[MessagingMutationKey(conversationID: conversationID, messageID: id, kind: .hideForMe)] else { return false }
        return pending.status != .storageFailed
    }

    private func project(_ message: MessagingWireMessage) -> MessagingWireMessage {
        MessagingMutationProjection.apply(pendingMutations, to: message, account: scope.accountID)
    }

    func pinnedMessages(_ conversationID: UUID) -> [MessagingWireMessage] {
        visibleMessages(conversationID).filter { $0.meta.pinned && !$0.meta.deletedForEveryone }
    }

    func message(_ id: UUID, in conversationID: UUID) -> MessagingWireMessage? {
        messages[conversationID]?.first { $0.id == id }.map(project)
    }

    /// Noms affichables connus dans ce contexte, plus longs d'abord (« @Léa Martin » avant « @Léa »).
    var knownDisplayNames: [String] {
        Array(Set(members.map(\.displayName) + generalMembers.map(\.displayName) + contacts.map(\.displayName)))
            .filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }

    func displayName(_ personID: UUID) -> String {
        if personID == scope.accountID { return "Moi" }
        return members.first { $0.id == personID }?.displayName
            ?? contacts.first { $0.id == personID }?.displayName
            ?? generalMembers.first { $0.id == personID }?.displayName
            ?? "Membre"
    }

    /// Lu par : personnes autres que l'auteur dont la progression atteint ce message.
    func readers(of message: MessagingWireMessage) -> [UUID] {
        (receipts[message.conversationID] ?? [])
            .filter { $0.personID != message.senderID && $0.lastReadSequence >= message.meta.sequence }
            .map(\.personID)
    }

    func loadMembers() async {
        do {
            let result = try await actions.members(scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            members = result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            error = nil
            await loadRemovedMembers()
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    /// Liste serveur des retirés, seulement pour un administrateur du groupe ; sinon elle reste vide.
    func loadRemovedMembers() async {
        guard members.first(where: { $0.id == scope.accountID })?.isGroupAdmin == true else { removedMembers = []; return }
        do {
            let result = try await actions.removedMembers(scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            removedMembers = result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch let failure as MessagingFailure {
            removedMembers = []
            if failure == .accessChanged || failure == .contextChanged { recordFailure(failure) }
        } catch { removedMembers = [] }
    }

    /// Photo #64 lue une fois par session, en mémoire uniquement. Absente : les initiales restent.
    func loadPhoto(_ personID: UUID) async {
        guard !photoRequested.contains(personID) else { return }
        photoRequested.insert(personID)
        if let data = await photoLoader(personID), currentScope() == scope { photos[personID] = data }
    }

    /// Exécute une action serveur sans effet optimiste, puis relit la conversation en arrière-plan.
    private func perform(_ conversationID: UUID?, _ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            actionError = nil
            if let conversationID { Task { await self.loadMessages(conversationID, marksVisible: false) } }
            return true
        } catch let failure as MessagingFailure {
            if failure == .accessChanged || failure == .contextChanged { recordFailure(failure) }
            actionError = failure; return false
        } catch { actionError = .unavailable; return false }
    }

    func clearActionError() { actionError = nil }

    /// Pour moi : masquage local immédiat. Pour tous : « Suppression en cours » jusqu'à la réponse,
    /// l'effacement chez tous n'est annoncé qu'après relecture serveur.
    func delete(_ message: MessagingWireMessage, for deletion: MessagingDeletionScope) {
        submit(MessagingMutationKey(conversationID: message.conversationID, messageID: message.id,
                                    kind: deletion == .me ? .hideForMe : .deleteForEveryone), desired: .active(true))
    }

    /// L'état souhaité part de la projection (intentions en cours comprises), jamais d'une bascule aveugle.
    func toggleReaction(_ emoji: String, on message: MessagingWireMessage) {
        let current = self.message(message.id, in: message.conversationID) ?? message
        let mine = current.meta.reactions.first { $0.emoji == emoji }?.personIDs.contains(scope.accountID) ?? false
        submit(MessagingMutationKey(conversationID: message.conversationID, messageID: message.id, kind: .reaction(emoji)),
               desired: .active(!mine))
    }

    func setPinned(_ message: MessagingWireMessage, pinned: Bool) {
        submit(MessagingMutationKey(conversationID: message.conversationID, messageID: message.id, kind: .pin),
               desired: .active(pinned))
    }

    func vote(_ message: MessagingWireMessage, optionIDs: Set<String>) {
        submit(MessagingMutationKey(conversationID: message.conversationID, messageID: message.id, kind: .vote),
               desired: .options(optionIDs))
    }

    func isInProgress(_ operation: String) -> Bool { operationsInProgress.contains(operation) }
    static func pollCloseOperation(_ messageID: UUID) -> String { "poll.close.\(messageID.uuidString)" }
    static func memberOperation(_ personID: UUID) -> String { "member.\(personID.uuidString)" }

    /// Sensible : « En cours » visible, la clôture n'est affichée qu'après confirmation.
    func closePoll(_ message: MessagingWireMessage) async {
        let operation = Self.pollCloseOperation(message.id)
        guard operationsInProgress.insert(operation).inserted else { return }
        defer { operationsInProgress.remove(operation) }
        _ = await perform(message.conversationID) {
            try await actions.closePoll(scope: scope, conversationID: message.conversationID, messageID: message.id)
        }
    }

    func setGroupAdmin(_ personID: UUID, admin: Bool) async {
        await runMemberOperation(personID) { try await self.actions.setGroupAdmin(scope: self.scope, personID: personID, admin: admin) }
    }

    func removeMember(_ personID: UUID) async {
        await runMemberOperation(personID) { try await self.actions.removeGeneralMember(scope: self.scope, personID: personID) }
    }

    func reinstateMember(_ personID: UUID) async {
        await runMemberOperation(personID) { try await self.actions.reinstateGeneralMember(scope: self.scope, personID: personID) }
    }

    /// Révocation et rôles : aucun effet affiché avant la relecture des membres.
    private func runMemberOperation(_ personID: UUID, _ work: () async throws -> Void) async {
        let operation = Self.memberOperation(personID)
        guard operationsInProgress.insert(operation).inserted else { return }
        defer { operationsInProgress.remove(operation) }
        if await perform(nil, work) { await loadMembers() }
    }

    // MARK: Intentions locales (#104)

    func mutation(_ kind: MessagingMutationKind, on message: MessagingWireMessage) -> MessagingPendingMutation? {
        pendingMutations[MessagingMutationKey(conversationID: message.conversationID, messageID: message.id, kind: kind)]
    }

    /// État le plus préoccupant parmi les intentions du message, pour l'indication au niveau de la bulle.
    func mutationAttention(for message: MessagingWireMessage) -> MessagingMutationStatus? {
        let statuses = pendingMutations.filter { $0.key.messageID == message.id && $0.key.conversationID == message.conversationID }
            .map(\.value.status)
        for candidate in [MessagingMutationStatus.storageFailed, .uncertain, .unconfirmed, .offline, .slow] where statuses.contains(candidate) {
            return candidate
        }
        return nil
    }

    func rejection(for messageID: UUID) -> MessagingMutationRejection? { rejections[messageID] }
    func clearRejection(_ messageID: UUID) { rejections[messageID] = nil }

    /// Indique la connectivité connue. Hors connexion : les nouvelles intentions attendent sans minuterie.
    func setNetworkAvailable(_ available: Bool) {
        networkOffline = !available
        if available { resumeMutations(); resumeSends() } else {
            for (id, status) in sendStates where status == .queued { sendStates[id] = .offline }
        }
    }

    /// « Réessayer » : renvoie le MÊME état souhaité (idempotent). Requête encore en vol : simple vérification.
    func retryMutations(for message: MessagingWireMessage) {
        rejections[message.id] = nil
        let keys = pendingMutations.keys.filter { $0.messageID == message.id && $0.conversationID == message.conversationID }
        if keys.contains(where: mutationsInFlight.contains) {
            Task { await self.loadMessages(message.conversationID, marksVisible: false) }
        }
        for key in keys where !mutationsInFlight.contains(key) { restart(key) }
    }

    /// Reconnexion ou retour au premier plan : les intentions hors connexion repartent. Un masquage pour moi
    /// incertain (invisible, sans bouton) est aussi renvoyé : l'écriture serveur est idempotente.
    private func resumeMutations() {
        guard !networkOffline else { return }
        for (key, mutation) in pendingMutations where !mutationsInFlight.contains(key) {
            if mutation.status == .offline || restoredMutations.contains(key)
                || (key.kind == .hideForMe && mutation.status == .uncertain) {
                restoredMutations.remove(key)
                restart(key)
            }
        }
    }

    private func restart(_ key: MessagingMutationKey) {
        guard var mutation = pendingMutations[key], mutation.status != .confirmed || mutation.acknowledged != mutation.desired else { return }
        mutation.status = networkOffline ? .offline : .sending
        mutation.clock = UUID()
        pendingMutations[key] = mutation
        persistAndDispatch(key)
    }

    private func submit(_ key: MessagingMutationKey, desired: MessagingMutationValue, readState: MessagingReadState? = nil) {
        guard currentScope() == scope else { recordFailure(.contextChanged); return }
        rejections[key.messageID] = nil
        var mutation = pendingMutations[key]
            ?? MessagingPendingMutation(id: UUID(), desired: desired, startedAt: Date(), status: .sending)
        mutation.desired = desired
        mutation.status = networkOffline ? .offline : .sending
        mutation.clock = UUID()
        if mutation.readState == nil { mutation.readState = readState }
        pendingMutations[key] = mutation
        persistAndDispatch(key)
    }

    /// La projection est immédiate, mais même hors connexion son intention est scellée sans attendre le HTTP.
    /// Une modification pendant un HTTP lent est ainsi conservée avant la réponse de la précédente.
    private func persistAndDispatch(_ key: MessagingMutationKey) {
        Task {
            guard await restoreMutations(), await persistMutation(key), currentScope() == scope,
                  let current = pendingMutations[key] else { return }
            guard !networkOffline else { return }
            scheduleLatency(key, clock: current.clock)
            dispatch(key)
        }
    }

    @discardableResult private func restoreMutations() async -> Bool {
        guard currentScope() == scope else { return false }
        if mutationsRestored { return true }
        if let mutationRestoration { return await mutationRestoration.value }
        let task = Task { @MainActor in
            do {
                let stored = try await mutationStore.mutationEntries(scope: scope)
                guard currentScope() == scope else { return false }
                for entry in stored {
                    var value = entry.value
                    persistedMutationClocks[entry.key] = value.clock
                    persistedMutations[entry.key] = value
                    if let local = pendingMutations[entry.key] {
                        // Une saisie pendant l'ouverture du coffre garde le dernier choix et l'ancien envoi exact.
                        value.desired = local.desired; value.clock = local.clock; value.status = local.status
                    } else if value.status != .confirmed && value.status != .storageFailed {
                        value.status = .uncertain
                        restoredMutations.insert(entry.key)
                    }
                    pendingMutations[entry.key] = value
                }
                mutationsRestored = true
                return true
            } catch {
                guard currentScope() == scope else { return false }
                actionError = .protectionUnavailable
                for key in pendingMutations.keys { pendingMutations[key]?.status = .storageFailed }
                return false
            }
        }
        mutationRestoration = task
        let success = await task.value
        mutationRestoration = nil
        return success
    }

    /// Sérialise les écritures locales, sans bloquer les autres cibles ni attendre la requête réseau.
    @discardableResult private func persistMutation(_ key: MessagingMutationKey) async -> Bool {
        if let task = mutationPersistence[key] {
            guard await task.value else { return false }
            if pendingMutations[key] == persistedMutations[key] { return true }
            return await persistMutation(key)
        }
        let task = Task { @MainActor in
            defer { mutationPersistence[key] = nil }
            while let value = pendingMutations[key] {
                guard currentScope() == scope else { return false }
                do {
                    try await mutationStore.putMutation(.init(key: key, value: value),
                        replacing: persistedMutationClocks[key], scope: scope)
                    guard currentScope() == scope else { return false }
                    persistedMutationClocks[key] = value.clock
                    persistedMutations[key] = value
                    if pendingMutations[key] == value { return true }
                } catch {
                    guard currentScope() == scope else { return false }
                    pendingMutations[key]?.status = .storageFailed
                    actionError = error as? MessagingFailure ?? .protectionUnavailable
                    // La reprise explicite relira le journal partagé avant de remplacer un choix local devenu ancien.
                    if error as? MessagingFailure == .stateConflict { mutationsRestored = false }
                    return false
                }
            }
            return true
        }
        mutationPersistence[key] = task
        return await task.value
    }

    /// Indication de latence seulement : ni échec ni renvoi à l'échéance.
    private func scheduleLatency(_ key: MessagingMutationKey, clock: UUID) {
        let latency = mutationLatency
        Task { [weak self] in
            try? await Task.sleep(for: latency.slow)
            self?.advance(key, clock: clock, to: .slow)
            try? await Task.sleep(for: max(.zero, latency.unconfirmed - latency.slow))
            self?.advance(key, clock: clock, to: .unconfirmed)
        }
    }

    private func advance(_ key: MessagingMutationKey, clock: UUID, to status: MessagingMutationStatus) {
        guard var mutation = pendingMutations[key], mutation.clock == clock, mutationsInFlight.contains(key),
              mutation.status == .sending || mutation.status == .slow else { return }
        mutation.status = status
        pendingMutations[key] = mutation
    }

    private func dispatch(_ key: MessagingMutationKey) {
        guard mutationsInFlight.insert(key).inserted else { return }
        Task { await self.drive(key) }
    }

    /// Une requête à la fois par cible ; tant que l'état accusé diffère du dernier souhaité, on le renvoie.
    private func drive(_ key: MessagingMutationKey) async {
        defer { mutationsInFlight.remove(key) }
        var accepted = false
        var muteRebases = 0
        while let current = pendingMutations[key], (current.acknowledged != current.desired || current.transmitting != nil),
              current.status != .offline, current.status != .uncertain {
            guard currentScope() == scope else { recordFailure(.contextChanged); return }
            guard current.status != .storageFailed else { return }
            let sent = current.transmitting ?? current.desired
            let sentClock = current.clock
            pendingMutations[key]?.transmitting = sent
            guard await persistMutation(key), currentScope() == scope else { return }
            do {
                try await transmit(key, sent)
                guard currentScope() == scope else { recordFailure(.contextChanged); return }
                guard var mutation = pendingMutations[key] else { return }
                mutation.acknowledged = sent
                mutation.acknowledgedAt = Date()
                mutation.transmitting = nil
                if mutation.desired == sent { mutation.status = .confirmed }
                pendingMutations[key] = mutation
                guard await persistMutation(key) else { return }
                accepted = true
                if key.kind == .hideForMe || key.kind == .deleteForEveryone { await applyDeletion(key) }
            } catch {
                let failure = error as? MessagingFailure ?? .unavailable
                guard pendingMutations[key] != nil else { return }
                guard currentScope() == scope else { recordFailure(.contextChanged); return }
                if failure == .stateConflict, key.kind == .mute, muteRebases < 2 {
                    muteRebases += 1
                    let previous = pendingMutations[key]?.readState
                    await loadConversations()
                    guard currentScope() == scope else { recordFailure(.contextChanged); return }
                    if let fresh = readStates[key.conversationID], fresh.version > (previous?.version ?? -1),
                       case .mutedUntil(let until) = sent {
                        if fresh.mutedUntil == until || fresh.mutedUntil == previous?.mutedUntil {
                            pendingMutations[key]?.readState = fresh
                            if fresh.mutedUntil == until {
                                pendingMutations[key]?.acknowledged = sent
                                pendingMutations[key]?.acknowledgedAt = Date()
                                pendingMutations[key]?.transmitting = nil
                                if pendingMutations[key]?.desired == sent { pendingMutations[key]?.status = .confirmed }
                                accepted = true
                            }
                            guard await persistMutation(key) else { return }
                            continue
                        }
                    }
                }
                switch failure {
                case .accessChanged, .contextChanged:
                    recordFailure(failure)
                case .stateConflict, .conversationUnavailable, .membersChanged:
                    // Refus explicite : seule cette intention est retirée, l'état serveur courant reste.
                    // Une réponse à une ancienne volonté ne retire pas celle saisie pendant le HTTP.
                    if pendingMutations[key]?.clock == sentClock {
                        _ = await removeMutation(key, expectedClock: sentClock)
                    } else {
                        pendingMutations[key]?.transmitting = nil
                        pendingMutations[key]?.status = .uncertain
                        _ = await persistMutation(key)
                    }
                    rejections[key.messageID] = MessagingMutationRejection(kind: key.kind, failure: failure)
                    if key.kind == .mute { actionError = failure }
                default:
                    // Réponse perdue, délai dépassé, indisponibilité : peut-être enregistré, jamais un refus.
                    pendingMutations[key]?.status = networkOffline ? .offline : .uncertain
                    _ = await persistMutation(key)
                }
                return
            }
        }
        if let current = pendingMutations[key], current.acknowledged == current.desired,
           current.transmitting == nil, current.status != .confirmed {
            pendingMutations[key]?.status = .confirmed
            guard await persistMutation(key) else { return }
            accepted = true
        }
        if accepted {
            Task {
                if key.kind == .mute { await self.loadConversations() }
                else { await self.loadMessages(key.conversationID, marksVisible: false) }
            }
        }
    }

    private func transmit(_ key: MessagingMutationKey, _ value: MessagingMutationValue) async throws {
        let actions = self.actions, scope = self.scope
        switch (key.kind, value) {
        case (.reaction(let emoji), .active(let active)):
            try await actions.setReaction(scope: scope, conversationID: key.conversationID, messageID: key.messageID,
                                          emoji: emoji, active: active)
        case (.pin, .active(let pinned)):
            try await actions.setPinned(scope: scope, conversationID: key.conversationID, messageID: key.messageID, pinned: pinned)
        case (.vote, .options(let options)):
            try await actions.vote(scope: scope, conversationID: key.conversationID, messageID: key.messageID,
                                   optionIDs: options.sorted())
        case (.hideForMe, _):
            try await actions.delete(scope: scope, conversationID: key.conversationID, messageID: key.messageID, for: .me)
        case (.deleteForEveryone, _):
            try await actions.delete(scope: scope, conversationID: key.conversationID, messageID: key.messageID, for: .everyone)
        case (.mute, .mutedUntil(let until)):
            guard let base = pendingMutations[key]?.readState else { throw MessagingFailure.invalidResponse }
            let response = try await directory.readState(scope: scope, conversationID: key.conversationID,
                sequence: base.lastReadSequence, mutedUntil: until, expectedVersion: base.version)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            mergeReadState(response, conversationID: key.conversationID)
            pendingMutations[key]?.readState = response
        default:
            throw MessagingFailure.invalidResponse
        }
    }

    private func applyDeletion(_ key: MessagingMutationKey) async {
        if key.kind == .hideForMe {
            hiddenForMe.insert(key.messageID)
            if let clock = pendingMutations[key]?.clock { _ = await removeMutation(key, expectedClock: clock) }
        }
        contents.removeValue(forKey: key.messageID)
        try? await history.remove(messageIDs: [key.messageID], scope: scope)
    }

    /// Après relecture : une intention hors vol que le serveur reflète est retirée (pas de double compte).
    /// Confirmée mais toujours absente après le délai de grâce : l'état serveur fait foi.
    private func reconcileMutations(_ conversationID: UUID, readMute: Bool = false) async {
        let now = Date()
        for (key, mutation) in pendingMutations where key.conversationID == conversationID && !mutationsInFlight.contains(key) {
            let satisfied: Bool
            if key.kind == .mute {
                guard readMute, case .mutedUntil(let until) = mutation.desired, let base = readStates[conversationID] else { continue }
                satisfied = base.mutedUntil == until
            } else if key.kind == .hideForMe, mutation.status == .confirmed, !readMute {
                hiddenForMe.insert(key.messageID)
                satisfied = true
            } else {
                guard !readMute, let base = messages[conversationID]?.first(where: { $0.id == key.messageID }) else { continue }
                satisfied = MessagingMutationProjection.isSatisfied(key.kind, mutation.desired, by: base.meta, account: scope.accountID)
            }
            let settled = mutation.status == .confirmed || mutation.status == .uncertain
            let expired = mutation.status == .confirmed
                && (mutation.acknowledgedAt.map { now.timeIntervalSince($0) > Self.confirmationGrace } ?? false)
            // Un ancien envoi encore incertain peut porter une autre valeur que la projection actuelle.
            if (satisfied && settled && (mutation.transmitting == nil || mutation.transmitting == mutation.desired)) || expired {
                mutationsInFlight.insert(key)
                _ = await removeMutation(key, expectedClock: mutation.clock)
                mutationsInFlight.remove(key)
                if pendingMutations[key] != nil, pendingMutations[key]?.clock != mutation.clock { persistAndDispatch(key) }
            }
        }
    }

    /// Acquittement local comparé à la révision scellée. Un geste pendant l'effacement n'est pas perdu.
    @discardableResult private func removeMutation(_ key: MessagingMutationKey, expectedClock: UUID) async -> Bool {
        guard pendingMutations[key]?.clock == expectedClock, await persistMutation(key),
              let value = pendingMutations[key], value.clock == expectedClock else { return false }
        let task = Task { @MainActor in
            defer { mutationPersistence[key] = nil }
            do {
                try await mutationStore.removeMutation(key, id: value.id, clock: value.clock, scope: scope)
                guard currentScope() == scope else { return false }
                persistedMutationClocks[key] = nil; persistedMutations[key] = nil
                if pendingMutations[key]?.clock == value.clock { pendingMutations[key] = nil }
                return true
            } catch {
                guard currentScope() == scope else { return false }
                pendingMutations[key]?.status = .storageFailed
                actionError = .protectionUnavailable
                return false
            }
        }
        mutationPersistence[key] = task
        return await task.value
    }

    /// Seuls les messages choisis sont rechiffrés pour les administrateurs de l'école puis transmis.
    func report(_ selected: [MessagingWireMessage], conversationID: UUID) async -> Bool {
        let operation = ReportOperationKey(scope: scope, conversationID: conversationID)
        guard Self.activeReportOperations.insert(operation).inserted else { return false }
        defer { Self.activeReportOperations.remove(operation) }
        return await perform(nil) {
            try verifyReportContext()
            let ids = Set(selected.map(\.id))
            guard (1...50).contains(selected.count), ids.count == selected.count,
                  selected.allSatisfy({ $0.conversationID == conversationID && $0.schoolID == scope.schoolID })
            else { throw MessagingFailure.invalidResponse }
            let existing = try await reports.pendingReport(conversationID: conversationID, scope: scope)
            try verifyReportContext()
            let pending: MessagingPendingReport
            if let existing, existing.messageIDs == ids {
                pending = existing
            } else {
                var items: [MessagingReportItem] = []
                for message in selected.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                    guard let content = await content(for: message) else { throw MessagingFailure.protectionUnavailable }
                    try verifyReportContext()
                    let sealed = try await reportSealing.sealForSchoolAdmins(try content.encoded(), scope: scope,
                                                                             conversationID: conversationID)
                    try verifyReportContext()
                    items.append(MessagingReportItem(messageID: message.id, ciphertext: sealed))
                }
                pending = try await reports.prepareReport(MessagingPendingReport(clientReportID: UUID(),
                    conversationID: conversationID, items: items), scope: scope)
                try verifyReportContext()
            }
            // Aucun POST avant écriture durable. Le serveur revalide les droits à chaque tentative.
            try await actions.report(scope: scope, conversationID: conversationID,
                                     clientReportID: pending.clientReportID, items: pending.items)
            try verifyReportContext()
            try await reports.removeReport(conversationID: conversationID, clientReportID: pending.clientReportID, scope: scope)
            try verifyReportContext()
        }
    }

    private func verifyReportContext() throws {
        try Task.checkCancellation()
        guard currentScope() == scope else { throw MessagingFailure.contextChanged }
    }

    @discardableResult
    func abandonReport(conversationID: UUID) async -> Bool {
        let operation = ReportOperationKey(scope: scope, conversationID: conversationID)
        guard Self.activeReportOperations.insert(operation).inserted else { return false }
        defer { Self.activeReportOperations.remove(operation) }
        return await perform(nil) {
            try verifyReportContext()
            let existing = try await reports.pendingReport(conversationID: conversationID, scope: scope)
            try verifyReportContext()
            if let existing {
                try await reports.removeReport(conversationID: conversationID, clientReportID: existing.clientReportID, scope: scope)
                try verifyReportContext()
            }
        }
    }

    /// Recherche sur l'appareil : historique scellé, complété par la mémoire de la session.
    func search(_ query: String, conversationID: UUID) async -> [MessagingHistoryEntry] {
        var entries = (try? await history.entries(conversationID: conversationID, scope: scope)) ?? []
        let known = Set(entries.map(\.messageID))
        for message in messages[conversationID] ?? [] where !known.contains(message.id) {
            if let content = contents[message.id] {
                entries.append(MessagingHistoryEntry(messageID: message.id, conversationID: conversationID,
                    sequence: message.meta.sequence, senderID: message.senderID, acceptedAt: message.acceptedAt, content: content))
            }
        }
        let limit = accessByConversation[conversationID]?.readableUntilSequence
        entries = entries.filter { !hiddenForMe.contains($0.messageID) && !isHiddenLocally($0.messageID, in: conversationID)
            && (limit == nil || $0.sequence <= limit!) }
        guard currentScope() == scope else { return [] }
        return MessagingHistorySearch.matches(entries, query: query)
    }

    // MARK: Envoi de messages (#104)

    /// État honnête d'un envoi de la file protégée. « Envoyé » seulement après l'accusé serveur.
    enum SendStatus: Equatable, Sendable {
        case queued, sending, slow, unconfirmed, offline, uncertain
        case failed(MessagingFailure)
        case accepted(serverMessageID: UUID)
    }

    private(set) var sendStates: [UUID: SendStatus] = [:]
    /// File FIFO par conversation : un seul envoi en vol, l'ordre serveur suit l'ordre de mise en file.
    private var sendQueues: [UUID: [MessagingPending]] = [:]
    private var sendInFlight: Set<UUID> = []
    private var sendClocks: [UUID: UUID] = [:]

    func sendStatus(_ clientMessageID: UUID) -> SendStatus? { sendStates[clientMessageID] }

    /// Accusé reçu ET message serveur chargé : la bulle en attente peut céder sa place sans trou.
    func isDelivered(_ entry: MessagingPending) -> Bool {
        guard case .accepted(let serverID)? = sendStates[entry.clientMessageID] else { return false }
        return messages[entry.conversationID]?.contains { $0.id == serverID } ?? false
    }

    /// Ajoute à la file d'envoi (entrée déjà écrite dans la file protégée). Ne bloque pas l'appelant.
    func scheduleSend(_ entry: MessagingPending) {
        let id = entry.clientMessageID
        if case .accepted? = sendStates[id] { return }
        var queue = sendQueues[entry.conversationID] ?? []
        if !queue.contains(where: { $0.clientMessageID == id }) { queue.append(entry) }
        sendQueues[entry.conversationID] = queue
        sendStates[id] = networkOffline ? .offline : .queued
        drainSends(entry.conversationID)
    }

    /// « Réessayer » : la MÊME entrée (même clientMessageId), dédupliquée par le serveur.
    func retrySend(_ entry: MessagingPending) {
        let status = sendStates[entry.clientMessageID]
        guard status != .sending, status != .slow else { return }
        scheduleSend(entry)
    }

    private func resumeSends() {
        guard !networkOffline else { return }
        for (conversationID, queue) in sendQueues {
            for entry in queue where sendStates[entry.clientMessageID] == .offline { sendStates[entry.clientMessageID] = .queued }
            drainSends(conversationID)
        }
    }

    private func drainSends(_ conversationID: UUID) {
        guard !networkOffline, sendInFlight.insert(conversationID).inserted else { return }
        Task { await self.runSends(conversationID) }
    }

    private func runSends(_ conversationID: UUID) async {
        defer { sendInFlight.remove(conversationID) }
        var accepted = false
        while let entry = sendQueues[conversationID]?.first(where: { sendStates[$0.clientMessageID] == .queued }) {
            // Ordre conservé : un envoi précédent incertain ou hors connexion retient les suivants.
            if let head = sendQueues[conversationID]?.first, head.clientMessageID != entry.clientMessageID,
               [SendStatus.uncertain, .offline, .unconfirmed].contains(sendStates[head.clientMessageID] ?? .queued) { break }
            guard currentScope() == scope, !networkOffline else { break }
            let id = entry.clientMessageID
            sendStates[id] = .sending
            let clock = UUID(); sendClocks[id] = clock
            scheduleSendLatency(id, clock: clock)
            let result = await outbox.retry(entry, currentScope: scope)
            sendClocks[id] = nil
            guard currentScope() == scope else { recordFailure(.contextChanged); return }
            switch result {
            case .accepted(let ack):
                sendStates[id] = .accepted(serverMessageID: ack.serverMessageID)
                sendQueues[conversationID]?.removeAll { $0.clientMessageID == id }
                accepted = true
            case .waiting:
                // Déjà en vol ailleurs (reprise) : la relecture de la file tranchera.
                sendStates[id] = .uncertain
            case .failed(let failure):
                switch failure {
                case .unavailable, .invalidResponse:
                    // Réponse perdue ou délai dépassé : peut-être accepté, jamais présenté comme refus.
                    sendStates[id] = networkOffline ? .offline : .uncertain
                case .accessChanged, .contextChanged:
                    sendStates[id] = .failed(failure)
                    recordFailure(failure)
                    return
                default:
                    // Refus explicite : contenu conservé dans la file protégée, les suivants peuvent partir.
                    sendStates[id] = .failed(failure)
                    sendQueues[conversationID]?.removeAll { $0.clientMessageID == id }
                }
            }
            if case .accepted? = sendStates[id] { continue }
            if case .failed? = sendStates[id] { continue }
            break
        }
        if accepted { Task { await self.loadMessages(conversationID, marksVisible: false) } }
    }

    private func scheduleSendLatency(_ id: UUID, clock: UUID) {
        let latency = mutationLatency
        Task { [weak self] in
            try? await Task.sleep(for: latency.slow)
            self?.advanceSend(id, clock: clock, to: .slow)
            try? await Task.sleep(for: max(.zero, latency.unconfirmed - latency.slow))
            self?.advanceSend(id, clock: clock, to: .unconfirmed)
        }
    }

    private func advanceSend(_ id: UUID, clock: UUID, to status: SendStatus) {
        guard sendClocks[id] == clock, sendStates[id] == .sending || sendStates[id] == .slow else { return }
        sendStates[id] = status
    }

    func enqueue(content: MessagingPlainContent, conversationID: UUID, mentions: [UUID], replyTo: UUID?,
                 pollAllowsMultiple: Bool = false) async throws -> MessagingPending {
        guard access(for: conversationID).canWrite else { throw MessagingFailure.accessChanged }
        return try await outbox.enqueue(content: content, conversationID: conversationID, mentions: mentions,
            replyTo: replyTo, pollAllowsMultiple: pollAllowsMultiple, currentScope: scope)
    }
    var hasLoadedConversations: Bool { loadedConversations }

    private func mergeReadState(_ incoming: MessagingReadState, conversationID: UUID) {
        readStates[conversationID] = Self.mergedReadState(previous: readStates[conversationID], incoming: incoming)
    }

    static func mergedReadState(previous: MessagingReadState?, incoming: MessagingReadState) -> MessagingReadState {
        guard let previous else { return incoming }
        guard incoming.version >= previous.version else { return previous }
        return MessagingReadState(lastReadSequence: max(previous.lastReadSequence, incoming.lastReadSequence),
            mutedUntil: incoming.version > previous.version ? incoming.mutedUntil : previous.mutedUntil,
            version: incoming.version)
    }
}
