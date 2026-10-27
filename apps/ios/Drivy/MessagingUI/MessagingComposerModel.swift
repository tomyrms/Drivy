import Foundation
import Observation

/// Composeur d'une conversation, seul propriétaire du brouillon (#182) : un seul champ, une seule copie du texte.
/// Le texte n'est retiré qu'après la mise en file protégée ; en cas d'échec, texte, mentions et réponse restent.
@MainActor
@Observable final class MessagingComposerModel {
    let workspace: MessagingWorkspace
    let conversationID: UUID
    var draft = "" {
        // Une mention effacée du texte n'est plus envoyée (#101).
        didSet { selectedMentions.removeAll { !draft.contains("@\($0.displayName)") } }
    }
    private(set) var selectedMentions: [MessagingMentionSelection] = []
    var replyTo: MessagingWireMessage?
    private(set) var draftReady = false
    private(set) var draftFailure: String?
    /// Échec avant la mise en file (protection indisponible, contexte changé) : le brouillon reste.
    private(set) var deliveryLabel: String?
    private(set) var sending = false
    private(set) var queued: [MessagingPending] = []
    /// Première présentation de chaque envoi, pour une place stable dans le fil.
    private(set) var queuedDates: [UUID: Date] = [:]
    /// Incrémenté pour demander le focus du champ (réponse, mention).
    private(set) var focusRequest = 0
    /// Incrémenté pour fermer le clavier (ouverture du menu d'un message).
    private(set) var blurRequest = 0
    /// Miroir du focus du champ, tenu par la vue.
    var isFocused = false

    init(workspace: MessagingWorkspace, conversationID: UUID) {
        self.workspace = workspace
        self.conversationID = conversationID
    }

    private var access: MessagingConversationAccess { workspace.access(for: conversationID) }

    var canSend: Bool {
        !sending && draftReady && draftFailure == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Jeton `@xxx` en cours de frappe à la fin du brouillon (#101), nil sinon.
    var mentionQuery: String? { MessagingMentionToken.query(in: draft) }

    /// Envois encore affichés : l'accusé ET le message serveur chargé retirent la bulle locale.
    var visibleQueue: [MessagingPending] { queued.filter { !workspace.isDelivered($0) } }

    func load() async {
        do {
            draft = try await workspace.loadDraft(conversationID)
            try await reloadQueue()
            draftReady = true
        } catch { draftFailure = Self.describe(error) }
    }

    /// Reprise : la file protégée fait foi, les envois d'un autre contexte n'apparaissent jamais.
    func reloadQueue() async throws {
        let entries = try await workspace.outbox.pending(currentScope: workspace.scope)
            .filter { $0.conversationID == conversationID }
        let now = Date()
        for entry in entries where queuedDates[entry.clientMessageID] == nil { queuedDates[entry.clientMessageID] = now }
        queued = entries
    }

    func resume() async {
        guard workspace.error != .accessChanged && workspace.error != .contextChanged else { return }
        do { try await reloadQueue() } catch { deliveryLabel = Self.describe(error) }
    }

    /// Accès ou école changés : rien de l'ancien contexte ne reste dans le composeur.
    func reset() {
        draft = ""; queued = []; queuedDates = [:]; selectedMentions = []; draftReady = false; replyTo = nil
    }

    /// Conservation protégée du brouillon, appelée après une courte pause de frappe.
    func persistDraft() async {
        guard draftReady, access.canWrite else { return }
        do {
            try await workspace.saveDraft(draft, conversationID: conversationID)
            draftFailure = nil
        } catch is CancellationError {} catch { draftFailure = Self.describe(error) }
    }

    func reply(to message: MessagingWireMessage) {
        replyTo = message
        focusRequest += 1
    }

    func blur() { blurRequest += 1 }

    func insertMention(_ person: MessagingContact) {
        guard let replaced = MessagingMentionToken.replacing(in: draft, with: person.displayName) else { return }
        draft = replaced
        if !selectedMentions.contains(where: { $0.personID == person.id }) && selectedMentions.count < 8 {
            selectedMentions.append(MessagingMentionSelection(personID: person.id, displayName: person.displayName))
        }
        focusRequest += 1
    }

    func sendText() async -> Bool { await send(MessagingPlainContent(text: draft)) }

    /// La file chiffrée sur disque précède toute tentative réseau. `sending` ne couvre que la mise en file
    /// durable : l'envoi réseau part ensuite dans la file FIFO du workspace, sans bloquer le composeur.
    func send(_ content: MessagingPlainContent, pollAllowsMultiple: Bool = false) async -> Bool {
        guard !sending, draftReady, access.canWrite else { return false }
        sending = true
        let isText = content.poll == nil
        let submitted = draft
        let submittedMentions = isText ? selectedMentions.map(\.personID) : []
        do {
            let entry = try await workspace.enqueue(content: content, conversationID: conversationID,
                mentions: submittedMentions, replyTo: replyTo?.id, pollAllowsMultiple: pollAllowsMultiple)
            deliveryLabel = nil
            queuedDates[entry.clientMessageID] = Date()
            queued.append(entry)
            replyTo = nil
            if isText && selectedMentions.map(\.personID) == submittedMentions { selectedMentions = [] }
            // Seule la révision effectivement conservée est retirée : une frappe pendant la mise en file reste.
            if isText && draft == submitted { draft = "" }
            sending = false
            workspace.scheduleSend(entry)
            if isText {
                // Brouillon vidé après la mise en file durable ; la saisie suivante reste protégée.
                try? await workspace.saveDraft(draft, conversationID: conversationID)
            }
            return true
        } catch {
            sending = false
            deliveryLabel = MessagingDiagnostics.shared.describe(error as? MessagingFailure ?? .protectionUnavailable)
            return false
        }
    }

    func retry(_ entry: MessagingPending) { workspace.retrySend(entry) }

    private static func describe(_ error: Error) -> String {
        (error as? MessagingFailure ?? .protectionUnavailable).localizedDescription
    }
}
