import Foundation
import Observation

@MainActor
@Observable final class MessagingMediaComposerModel {
    struct Preview: Identifiable {
        let id = UUID()
        let media: MessagingPreparedMedia
        let messageID: UUID?
    }
    let runtime: any MessagingMediaRuntime
    let conversationID: UUID
    private(set) var selection: MessagingPreparedMedia?
    /// Raccord au brouillon texte du composeur (#475). Règle : le champ principal reste visible et sert de
    /// légende tant qu'une pièce est choisie ; texte et légende sont UNE seule valeur, donc ni perte au
    /// choix/retrait/remplacement, ni duplication, ni texte masqué. Sans raccord (tests, compositions
    /// minimales) la légende est locale.
    @ObservationIgnored var draftChannel: MessagingCaptionChannel?
    private var localCaption = ""
    var caption: String {
        get { draftChannel?.read() ?? localCaption }
        set { if let draftChannel { draftChannel.write(newValue) } else { localCaption = newValue } }
    }
    /// Erreur propre au choix de la pièce (format, taille, import interrompu), affichée à côté de la pièce.
    private(set) var selectionError: String?
    private(set) var preparing = false
    private(set) var sending = false
    private(set) var opening = false
    private(set) var error: String?
    private(set) var pendingItems: [MessagingMediaPendingSnapshot] = []
    private(set) var failures: [UUID: MessagingMediaRuntimeFailure] = [:]
    private(set) var confirmation: MessagingAcknowledgement?
    private(set) var cleanupPending = false
    private(set) var lastEnqueuedID: UUID?
    private(set) var enqueuedReplyTo: UUID?
    var preview: Preview?
    private var generation = UUID()
    private var gestureID = UUID()
    private var active = true
    private var confirmedIDs: Set<UUID> = []
    private var pendingRevision = UUID()

    init(runtime: any MessagingMediaRuntime, conversationID: UUID) {
        self.runtime = runtime; self.conversationID = conversationID
    }

    var canSend: Bool { active && selection != nil && !preparing && !sending }
    var contextGeneration: UUID { generation }
    /// Change à chaque pièce choisie ; sert de clé aux vues (miniature) sans exposer de contenu.
    var selectionRevision: UUID { gestureID }

    func select(expectedGeneration: UUID? = nil, _ source: () async throws -> MessagingImportedMedia) async {
        guard active, !sending, !preparing else { return }
        guard expectedGeneration == nil || expectedGeneration == generation else { return }
        let request = generation
        preparing = true; error = nil; selectionError = nil; confirmation = nil
        defer { if request == generation { preparing = false } }
        do {
            let imported = try await source()
            guard active, request == generation else { return }
            let prepared = try await runtime.prepare(imported.data, suggestedName: imported.suggestedName)
            guard active, request == generation, !Task.isCancelled else { return }
            selection = prepared; gestureID = UUID()
        } catch is CancellationError {
            // Cancellation is a normal picker outcome; the preceding selection remains.
        } catch {
            if active, request == generation {
                let text = Self.selectionLabel(error)
                record(error, message: text)
                if self.error == text { selectionError = text }
            }
        }
        if request == generation { preparing = false }
    }

    func removeSelection() {
        guard !sending else { return }
        // Retrait avant envoi : la légende (le brouillon) reste dans le champ, rien n'est effacé ni envoyé.
        generation = UUID(); selection = nil; preparing = false; preview = nil; error = nil; selectionError = nil
        // This generation also invalidates any pending open; its stale defer must not
        // clear a newer operation, so release the presentation lock here instead.
        opening = false
        // Durable intentions belong to runtime; removing a local selection never deletes one.
    }

    func showSelection() {
        guard active, let selection else { return }
        preview = Preview(media: selection, messageID: nil)
    }

    func load() async {
        active = true
        error = nil
        let request = generation
        let revision = pendingRevision
        do {
            let items = try await runtime.pending(conversationID: conversationID)
            guard active, request == generation, revision == pendingRevision else { return }
            pendingItems = items.filter { !confirmedIDs.contains($0.id) }
        } catch {
            if active, request == generation, revision == pendingRevision { record(error) }
        }
    }

    func sendSelected(replyTo: UUID?) async {
        guard canSend, let selection else { return }
        sending = true; error = nil; confirmation = nil
        pendingRevision = UUID()
        let request = generation, id = gestureID
        let submitted = caption
        let trimmed = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let item = try await runtime.enqueue(selection, clientMessageID: id, conversationID: conversationID,
                caption: trimmed.isEmpty ? nil : trimmed, mentionPersonIDs: [], replyToMessageID: replyTo)
            guard active, request == generation else { return }
            pendingItems.removeAll { $0.id == item.id }; pendingItems.append(item)
            enqueuedReplyTo = replyTo; lastEnqueuedID = item.id
            // Seule la légende effectivement envoyée est retirée : une frappe pendant la mise en file reste.
            self.selection = nil; preview = nil
            if caption == submitted { caption = "" }
            apply(await runtime.send(clientMessageID: id), id: id, request: request)
        } catch {
            if active, request == generation {
                record(error, prefix: "Conservation non confirmée. ")
            }
        }
        if request == generation { sending = false }
    }

    func retry(_ id: UUID) async {
        guard active, !sending, pendingItems.contains(where: { $0.id == id }) else { return }
        sending = true; error = nil; confirmation = nil
        pendingRevision = UUID()
        let request = generation
        let result: MessagingMediaDelivery
        if failures[id] == .membersChanged {
            result = await runtime.recomposeAfterMembersChanged(clientMessageID: id)
        } else {
            result = await runtime.send(clientMessageID: id)
        }
        apply(result, id: id, request: request)
        if request == generation { sending = false }
    }

    private func apply(_ delivery: MessagingMediaDelivery, id: UUID, request: UUID) {
        guard active, request == generation else { return }
        switch delivery {
        case .confirmed(let receipt, let cleanup):
            guard receipt.clientMessageID == id, receipt.conversationID == conversationID else {
                failures[id] = .resultUnknown; return
            }
            confirmation = receipt; cleanupPending = cleanup; confirmedIDs.insert(id)
            pendingItems.removeAll { $0.id == id }; failures[id] = nil
        case .pending(let failure):
            if failure == .contextChanged || failure == .accessChanged {
                suspend(); error = Self.label(failure)
            } else { failures[id] = failure }
        }
    }

    func open(_ message: MessagingWireMessage, stillVisible: () -> Bool) async {
        guard active, !opening, message.conversationID == conversationID,
              !message.meta.deletedForEveryone, message.meta.media?.deleted == false, stillVisible() else { return }
        opening = true; error = nil
        let request = generation
        defer { if request == generation { opening = false } }
        do {
            let media = try await runtime.open(message)
            guard active, request == generation, stillVisible(), !Task.isCancelled else { return }
            preview = Preview(media: media, messageID: message.id)
        } catch {
            if active, request == generation { record(error) }
        }
        if request == generation { opening = false }
    }

    func dismissRemovedPreview(visibleIDs: Set<UUID>) {
        if let id = preview?.messageID, !visibleIDs.contains(id) { preview = nil }
    }

    func suspend() {
        // La légende liée au brouillon du composeur n'est pas touchée ici : le brouillon a ses propres règles.
        active = false; generation = UUID(); selection = nil; localCaption = ""; selectionError = nil; preview = nil
        preparing = false; sending = false; opening = false; pendingItems = []; failures = [:]
        error = nil; confirmation = nil; cleanupPending = false
        lastEnqueuedID = nil; enqueuedReplyTo = nil
        // No promise to cancel a request already in flight or erase durable intentions.
    }

    private func record(_ failure: Error, prefix: String = "", message: String? = nil) {
        if let failure = failure as? MessagingMediaRuntimeFailure,
           failure == .contextChanged || failure == .accessChanged { suspend() }
        error = prefix + (message ?? Self.label(failure))
    }

    /// Texte d'erreur du choix de pièce : format/taille refusés et lecture interrompue (iCloud, fournisseur
    /// de fichiers indisponible) restent distincts. L'annulation du sélecteur n'arrive jamais ici.
    static func selectionLabel(_ error: Error) -> String {
        if error is MessagingMediaRuntimeFailure || error is MessagingMediaImportFailure { return label(error) }
        return "Fichier indisponible. Vérifier la connexion, puis le choisir à nouveau."
    }

    static func label(_ error: Error) -> String {
        if let failure = error as? MessagingMediaImportFailure {
            return failure == .invalidSize ? "Choisir un fichier de 4 Mo maximum, non vide." : "Lecture impossible. Choisir à nouveau le fichier."
        }
        switch error as? MessagingMediaRuntimeFailure {
        case .invalidSize: return "Choisir un fichier de 4 Mo maximum, non vide."
        case .invalidFormat: return "Choisir une photo JPEG, PNG ou un PDF."
        case .lockedPDF: return "Ce PDF est protégé. Choisir un autre document."
        case .invalidContent, .unreadable, .integrity: return "Pièce illisible. Choisir un autre fichier."
        case .removed: return "Cette pièce n’est plus disponible."
        case .contextChanged, .accessChanged: return "L’accès a changé. Rouvrir la conversation."
        case .protectionUnavailable: return "Conservation indisponible. Réessayer."
        case .membersChanged: return "Les participants ont changé. Vérifier avant de renvoyer."
        case .alreadyInFlight: return "Envoi déjà en cours. Vérifier avant de renvoyer."
        case .resultUnknown: return "Envoi non confirmé. Vérifier et renvoyer."
        default: return "Pièce indisponible. Réessayer."
        }
    }
}
