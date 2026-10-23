import Foundation
import Observation

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
    private(set) var hiddenForMe: Set<UUID> = []
    private(set) var actionError: MessagingFailure?
    /// Signalement validé mais pas encore accepté : même identifiant à chaque tentative.
    private var pendingReports: [UUID: (messageIDs: Set<UUID>, clientReportID: UUID)] = [:]
    private(set) var contacts: [MessagingContact] = []
    private(set) var generalMembers: [MessagingContact] = []
    private(set) var conversations: [MessagingConversation] = []
    private(set) var messages: [UUID: [MessagingWireMessage]] = [:]
    private(set) var readStates: [UUID: MessagingReadState] = [:]
    private(set) var conversationCursor: String?
    private(set) var messageCursors: [UUID: String] = [:]
    private(set) var error: MessagingFailure?
    private(set) var loading = false
    private(set) var resumeGeneration = 0
    private var resuming = false
    private var loadedConversations = false
    private var loadedMessages: Set<UUID> = []
    private var visibleMessageConversationID: UUID?

    init(scope: MessagingScope, service: any MessagingService = UnavailableMessagingService(),
         cryptography: any MessagingCryptography = UnavailableMessagingCryptography(),
         outbox: any MessagingProtectedOutbox = UnavailableMessagingOutbox(),
         drafts: any MessagingProtectedDrafts = UnavailableMessagingDrafts(),
         directory: any MessagingDirectoryService = UnavailableMessagingDirectory(),
         actions: any MessagingThreadActions = UnavailableMessagingThreadActions(),
         history: any MessagingHistoryStore = UnavailableMessagingHistory(),
         reportSealing: any MessagingReportSealing = UnavailableMessagingReportSealing(),
         photoLoader: @escaping @Sendable (UUID) async -> Data? = { _ in nil },
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope? = { nil }) {
        self.actions = actions
        self.history = history
        self.reportSealing = reportSealing
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
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func refreshVisible(conversationID: UUID? = nil) async {
        guard !resuming, currentScope() == scope else { return }
        if let conversationID { visibleMessageConversationID = conversationID }
        resuming = true
        defer { resuming = false; resumeGeneration += 1 }
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

    func loadMessages(_ conversationID: UUID, more: Bool = false) async {
        visibleMessageConversationID = conversationID
        if error == .membersChanged { error = nil }
        guard !loading, !more || messageCursors[conversationID] != nil else { return }
        loading = true; defer { loading = false }
        do {
            let cursor = more ? messageCursors[conversationID] : nil
            let page = try await service.messages(scope: scope, conversationID: conversationID, before: cursor)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            guard (cursor == nil || page.nextCursor != cursor),
                  page.items.allSatisfy({ $0.schoolID == scope.schoolID && $0.conversationID == conversationID }),
                  Set(page.items.map(\.id)).count == page.items.count else { throw MessagingFailure.invalidResponse }
            let existing = more ? (messages[conversationID] ?? []) : []
            messages[conversationID] = existing + page.items.filter { item in !existing.contains(where: { $0.id == item.id }) }
            messageCursors[conversationID] = page.nextCursor
            if let pageAccess = page.access {
                accessByConversation[conversationID] = pageAccess
                if let limit = pageAccess.readableUntilSequence {
                    try? await history.truncate(conversationID: conversationID, after: limit, scope: scope)
                }
            }
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
            try? await history.upsert([MessagingHistoryEntry(messageID: message.id, conversationID: message.conversationID,
                sequence: message.meta.sequence, senderID: message.senderID, acceptedAt: message.acceptedAt,
                content: value)], scope: scope)
            return value
        } catch let failure as MessagingFailure { recordFailure(failure); return nil }
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

    func markRead(conversationID: UUID, sequence: Int) async {
        do {
            let state = try await directory.readState(scope: scope, conversationID: conversationID,
                sequence: sequence, mutedUntil: nil, expectedVersion: nil)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            mergeReadState(state, conversationID: conversationID)
            error = nil
        }
        catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func silence(conversationID: UUID, fallbackSequence: Int, until: Date, fallbackVersion: Int) async {
        do {
            let state = readStates[conversationID]
            let response = try await directory.readState(scope: scope, conversationID: conversationID,
                sequence: state?.lastReadSequence ?? fallbackSequence,
                mutedUntil: until, expectedVersion: state?.version ?? fallbackVersion)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            mergeReadState(response, conversationID: conversationID)
            error = nil
            await loadConversations()
        }
        catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func unsilence(conversationID: UUID, fallbackSequence: Int, fallbackVersion: Int) async {
        do {
            let state = readStates[conversationID]
            let response = try await directory.readState(scope: scope, conversationID: conversationID,
                sequence: state?.lastReadSequence ?? fallbackSequence,
                mutedUntil: nil, expectedVersion: state?.version ?? fallbackVersion)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            mergeReadState(response, conversationID: conversationID)
            error = nil
            await loadConversations()
        }
        catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
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
            hiddenForMe = []
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

    // MARK: v2

    func access(for conversationID: UUID) -> MessagingConversationAccess { accessByConversation[conversationID] ?? .full }

    func visibleMessages(_ conversationID: UUID) -> [MessagingWireMessage] {
        (messages[conversationID] ?? []).filter { !hiddenForMe.contains($0.id) }
    }

    func pinnedMessages(_ conversationID: UUID) -> [MessagingWireMessage] {
        visibleMessages(conversationID).filter { $0.meta.pinned && !$0.meta.deletedForEveryone }
    }

    func message(_ id: UUID, in conversationID: UUID) -> MessagingWireMessage? {
        messages[conversationID]?.first { $0.id == id }
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

    /// Exécute une action serveur puis relit la conversation : aucun état optimiste affiché comme acquis.
    private func perform(_ conversationID: UUID?, _ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            actionError = nil
            if let conversationID { await loadMessages(conversationID) }
            return true
        } catch let failure as MessagingFailure {
            if failure == .accessChanged || failure == .contextChanged { recordFailure(failure) }
            actionError = failure; return false
        } catch { actionError = .unavailable; return false }
    }

    func clearActionError() { actionError = nil }

    @discardableResult
    func delete(_ message: MessagingWireMessage, for deletion: MessagingDeletionScope) async -> Bool {
        let ok = await perform(message.conversationID) {
            try await actions.delete(scope: scope, conversationID: message.conversationID, messageID: message.id, for: deletion)
        }
        if ok {
            if deletion == .me { hiddenForMe.insert(message.id) }
            contents.removeValue(forKey: message.id)
            try? await history.remove(messageIDs: [message.id], scope: scope)
        }
        return ok
    }

    func toggleReaction(_ emoji: String, on message: MessagingWireMessage) async {
        let mine = message.meta.reactions.first { $0.emoji == emoji }?.personIDs.contains(scope.accountID) ?? false
        _ = await perform(message.conversationID) {
            try await actions.setReaction(scope: scope, conversationID: message.conversationID,
                                          messageID: message.id, emoji: emoji, active: !mine)
        }
    }

    func setPinned(_ message: MessagingWireMessage, pinned: Bool) async {
        _ = await perform(message.conversationID) {
            try await actions.setPinned(scope: scope, conversationID: message.conversationID, messageID: message.id, pinned: pinned)
        }
    }

    func vote(_ message: MessagingWireMessage, optionIDs: Set<String>) async {
        _ = await perform(message.conversationID) {
            try await actions.vote(scope: scope, conversationID: message.conversationID,
                                   messageID: message.id, optionIDs: optionIDs.sorted())
        }
    }

    func closePoll(_ message: MessagingWireMessage) async {
        _ = await perform(message.conversationID) {
            try await actions.closePoll(scope: scope, conversationID: message.conversationID, messageID: message.id)
        }
    }

    func setGroupAdmin(_ personID: UUID, admin: Bool) async {
        if await perform(nil, { try await actions.setGroupAdmin(scope: scope, personID: personID, admin: admin) }) {
            await loadMembers()
        }
    }

    func removeMember(_ personID: UUID) async {
        if await perform(nil, { try await actions.removeGeneralMember(scope: scope, personID: personID) }) {
            await loadMembers()
        }
    }

    func reinstateMember(_ personID: UUID) async {
        if await perform(nil, { try await actions.reinstateGeneralMember(scope: scope, personID: personID) }) {
            await loadMembers()
        }
    }

    /// Seuls les messages choisis sont rechiffrés pour les administrateurs de l'école puis transmis.
    func report(_ selected: [MessagingWireMessage], conversationID: UUID) async -> Bool {
        let clientReportID = reportIdentifier(for: selected, conversationID: conversationID)
        let sent = await perform(nil) {
            var items: [MessagingReportItem] = []
            for message in selected where message.conversationID == conversationID {
                guard let content = await content(for: message) else { throw MessagingFailure.protectionUnavailable }
                let sealed = try await reportSealing.sealForSchoolAdmins(try content.encoded(), scope: scope,
                                                                         conversationID: conversationID)
                items.append(MessagingReportItem(messageID: message.id, ciphertext: sealed))
            }
            guard !items.isEmpty else { throw MessagingFailure.invalidResponse }
            try await actions.report(scope: scope, conversationID: conversationID, clientReportID: clientReportID, items: items)
        }
        if sent { pendingReports[conversationID] = nil }
        return sent
    }

    /// L'identifiant naît à la première validation et survit aux échecs pour la même sélection.
    func reportIdentifier(for selected: [MessagingWireMessage], conversationID: UUID) -> UUID {
        let ids = Set(selected.filter { $0.conversationID == conversationID }.map(\.id))
        if let pending = pendingReports[conversationID], pending.messageIDs == ids { return pending.clientReportID }
        let id = UUID()
        pendingReports[conversationID] = (ids, id)
        return id
    }

    func abandonReport(conversationID: UUID) { pendingReports[conversationID] = nil }

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
        entries = entries.filter { !hiddenForMe.contains($0.messageID) && (limit == nil || $0.sequence <= limit!) }
        guard currentScope() == scope else { return [] }
        return MessagingHistorySearch.matches(entries, query: query)
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
