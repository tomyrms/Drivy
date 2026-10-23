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
    private let revocationStore: MessagingProtectedStore?
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
    private var loadedConversations = false
    private var loadedMessages: Set<UUID> = []

    init(scope: MessagingScope, service: any MessagingService = UnavailableMessagingService(),
         cryptography: any MessagingCryptography = UnavailableMessagingCryptography(),
         outbox: any MessagingProtectedOutbox = UnavailableMessagingOutbox(),
         drafts: any MessagingProtectedDrafts = UnavailableMessagingDrafts(),
         directory: any MessagingDirectoryService = UnavailableMessagingDirectory(),
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope? = { nil },
         revocationStore: MessagingProtectedStore? = nil) {
        self.scope = scope
        self.service = service
        self.crypto = cryptography
        self.drafts = drafts
        self.directory = directory
        self.currentScope = currentScope
        self.revocationStore = revocationStore
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
                let known = readStates[item.id]
                if item.readStateVersion >= (known?.version ?? 0) {
                    readStates[item.id] = MessagingReadState(lastReadSequence: item.lastReadSequence,
                        mutedUntil: item.mutedUntil, version: item.readStateVersion)
                }
            }
            conversationCursor = page.nextCursor
            loadedConversations = true
            error = nil
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { error = .unavailable }
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
        catch { error = .unavailable }
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
        catch { error = .unavailable }
    }

    func loadGeneralMembers() async {
        do {
            let result = try await directory.generalMembers(scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            generalMembers = result; error = nil
        } catch let failure as MessagingFailure { recordFailure(failure) }
        catch { error = .unavailable }
    }

    func privateConversation(peerID: UUID) async -> UUID? {
        do {
            // Ne pas déduire l'autorisation du carnet local : le serveur revalide au PUT.
            let id = try await directory.privateConversation(scope: scope, peerID: peerID)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            error = nil; return id
        } catch let failure as MessagingFailure { recordFailure(failure); return nil }
        catch { error = .unavailable; return nil }
    }

    func generalConversation() async -> UUID? {
        do {
            let id = try await directory.generalConversation(scope: scope)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            error = nil; return id
        }
        catch let failure as MessagingFailure { recordFailure(failure); return nil }
        catch { error = .unavailable; return nil }
    }

    func markRead(conversationID: UUID, sequence: Int) async {
        do {
            let state = try await directory.readState(scope: scope, conversationID: conversationID,
                sequence: sequence, mutedUntil: nil, expectedVersion: nil)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            readStates[conversationID] = state
            error = nil
        }
        catch let failure as MessagingFailure { recordFailure(failure) }
        catch { error = .unavailable }
    }

    func silence(conversationID: UUID, fallbackSequence: Int, until: Date, fallbackVersion: Int) async {
        do {
            let state = readStates[conversationID]
            let response = try await directory.readState(scope: scope, conversationID: conversationID,
                sequence: state?.lastReadSequence ?? fallbackSequence,
                mutedUntil: until, expectedVersion: state?.version ?? fallbackVersion)
            guard currentScope() == scope else { throw MessagingFailure.contextChanged }
            readStates[conversationID] = response
            error = nil
            await loadConversations()
        }
        catch let failure as MessagingFailure { recordFailure(failure) }
        catch { error = .unavailable }
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
            if failure == .accessChanged, let revocationStore {
                Task {
                    do { try await revocationStore.purge(scope: scope) }
                    catch { error = .protectionUnavailable }
                }
            }
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
}
