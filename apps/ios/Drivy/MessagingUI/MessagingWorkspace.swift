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
    let outbox: MessagingOutboxCoordinator
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

    init(scope: MessagingScope, service: any MessagingService = UnavailableMessagingService(),
         cryptography: any MessagingCryptography = UnavailableMessagingCryptography(),
         outbox: any MessagingProtectedOutbox = UnavailableMessagingOutbox(),
         drafts: any MessagingProtectedDrafts = UnavailableMessagingDrafts(),
         directory: any MessagingDirectoryService = UnavailableMessagingDirectory(),
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope? = { nil }) {
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
        resuming = true
        defer { resuming = false; resumeGeneration += 1 }
        let results = await outbox.flushPending(currentScope: scope)
        for result in results {
            if case .failed(let failure) = result,
               failure == .accessChanged || failure == .contextChanged || failure == .protectionUnavailable {
                recordFailure(failure)
                return
            }
        }
        guard currentScope() == scope else { recordFailure(.contextChanged); return }
        await loadConversations()
        if let conversationID { await loadMessages(conversationID) }
    }

    func loadMessages(_ conversationID: UUID, more: Bool = false) async {
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
            loadedMessages.insert(conversationID)
            error = nil
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { self.error = .unavailable }
    }

    func text(for message: MessagingWireMessage) async -> String? {
        guard message.schoolID == scope.schoolID else { error = .contextChanged; return nil }
        do {
            let bytes = try await crypto.decrypt(message.ciphertext, scope: scope, conversationID: message.conversationID)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            guard let value = String(data: bytes, encoding: .utf8) else { throw MessagingFailure.invalidResponse }
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
