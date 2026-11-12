import Foundation
import Observation

@MainActor
@Observable final class MessagingMediaComposerModel {
    /// Aperçu plein écran (#474/#476). L'identité reste celle de l'ouverture : chargement, prêt ou échec se succèdent
    /// dans la même présentation, sans la fermer ni la rouvrir.
    struct Preview: Identifiable {
        let id: UUID
        let messageID: UUID?
        let title: String
        var state: MessagingMediaViewerState

        init(media: MessagingPreparedMedia, messageID: UUID?) {
            self.init(messageID: messageID, title: media.name, state: .ready(media))
        }

        init(messageID: UUID?, title: String, state: MessagingMediaViewerState) {
            self.id = UUID(); self.messageID = messageID; self.title = title; self.state = state
        }

        var media: MessagingPreparedMedia? {
            if case .ready(let media) = state { return media }
            return nil
        }
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
    /// Ouverture d'une pièce reçue, suivie PAR message (#476) : aucun verrou global du fil.
    private(set) var openStates: [UUID: MessagingMediaOpenState] = [:]
    /// Intention en cours de reprise explicite ; `sending` reste le verrou des envois.
    private(set) var retryingID: UUID?
    /// Intentions confirmées dont le message réel n'est pas encore dans le fil (la bulle locale reste en place).
    private(set) var confirmedAwaiting: [UUID: MessagingMediaConfirmedIntention] = [:]
    /// Message serveur → intention locale, pour toute la session : l'identité d'affichage ne change pas à l'arrivée.
    private(set) var confirmedClientIDs: [UUID: UUID] = [:]
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
    private var openEpoch = UUID()
    private var openTickets: [UUID: UUID] = [:]
    private var openTasks: [UUID: Task<MessagingPreparedMedia, Error>] = [:]

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
        sending = true; error = nil; confirmation = nil; retryingID = id
        pendingRevision = UUID()
        let request = generation
        let result: MessagingMediaDelivery
        if failures[id] == .membersChanged {
            result = await runtime.recomposeAfterMembersChanged(clientMessageID: id)
        } else {
            result = await runtime.send(clientMessageID: id)
        }
        apply(result, id: id, request: request)
        if retryingID == id { retryingID = nil }
        if request == generation { sending = false }
    }

    private func apply(_ delivery: MessagingMediaDelivery, id: UUID, request: UUID) {
        guard active, request == generation else { return }
        switch delivery {
        case .confirmed(let receipt, let cleanup):
            guard receipt.clientMessageID == id, receipt.conversationID == conversationID else {
                failures[id] = .resultUnknown; return
            }
            if let snapshot = pendingItems.first(where: { $0.id == id }) {
                confirmedAwaiting[id] = MessagingMediaConfirmedIntention(snapshot: snapshot,
                    serverMessageID: receipt.serverMessageID, cleanupPending: cleanup)
            }
            confirmedClientIDs[receipt.serverMessageID] = id
            confirmation = receipt; cleanupPending = cleanup; confirmedIDs.insert(id)
            pendingItems.removeAll { $0.id == id }; failures[id] = nil
        case .pending(let failure):
            if failure == .contextChanged || failure == .accessChanged {
                suspend(); error = Self.label(failure)
            } else { failures[id] = failure }
        }
    }

    // MARK: Ouverture par pièce (#476)

    func openState(for messageID: UUID) -> MessagingMediaOpenState? { openStates[messageID] }
    func isOpening(_ messageID: UUID) -> Bool { openStates[messageID] == .opening }

    /// Ouvre la visionneuse tout de suite en chargement, puis la fait passer à prêt ou échec. Un second toucher sur la
    /// même pièce pendant l'ouverture est ignoré ; une autre pièce reste libre. Un résultat dont l'ouverture a été
    /// fermée, révoquée ou suspendue entre-temps est ignoré.
    func open(_ message: MessagingWireMessage, title: String = "Pièce jointe", stillVisible: () -> Bool) async {
        guard active, message.conversationID == conversationID,
              !message.meta.deletedForEveryone, message.meta.media?.deleted == false, stillVisible() else { return }
        let id = message.id
        guard openStates[id] != .opening else { return }
        let epoch = openEpoch, ticket = UUID()
        openStates[id] = .opening; openTickets[id] = ticket; error = nil
        if preview?.messageID == id { preview?.state = .loading }
        else { preview = Preview(messageID: id, title: title, state: .loading) }
        let runtime = runtime
        let task = Task { try await runtime.open(message) }
        openTasks[id] = task
        let outcome = await task.result
        guard active, epoch == openEpoch, openTickets[id] == ticket else { return }
        openTickets[id] = nil; openTasks[id] = nil
        guard stillVisible(), !Task.isCancelled else { abandonOpen(id); return }
        switch outcome {
        case .success(let media):
            openStates[id] = nil
            if preview?.messageID == id { preview?.state = .ready(media) }
        case .failure(let failure):
            if failure is CancellationError { abandonOpen(id); return }
            if let runtimeFailure = failure as? MessagingMediaRuntimeFailure,
               runtimeFailure == .contextChanged || runtimeFailure == .accessChanged {
                suspend(); error = Self.label(runtimeFailure); return
            }
            let reason = MessagingMediaOpenFailure(failure)
            openStates[id] = .failed(reason)
            if preview?.messageID == id { preview?.state = .failed(reason.message) }
        }
    }

    /// Fermeture de la visionneuse : une ouverture encore en vol est annulée (lecture seulement, jamais un envoi) et son
    /// résultat tardif ignoré. Un échec déjà constaté reste affiché sur la pièce.
    func closePreview() {
        if let id = preview?.messageID, openStates[id] == .opening { abandonOpen(id) }
        preview = nil
    }

    private func abandonOpen(_ id: UUID) {
        openTasks[id]?.cancel()
        openTasks[id] = nil; openTickets[id] = nil; openStates[id] = nil
        if preview?.messageID == id { preview = nil }
    }

    /// Révocation ou retrait : la visionneuse ouverte sur un message qui n'est plus lisible se ferme, et les états
    /// d'ouverture des pièces devenues illisibles sont oubliés.
    func dismissRemovedPreview(visibleIDs: Set<UUID>) {
        if let id = preview?.messageID, !visibleIDs.contains(id) { closePreview() }
        for id in Array(openStates.keys) where !visibleIDs.contains(id) { abandonOpen(id) }
    }

    // MARK: Intentions dans le fil (#476)

    /// Phase d'une intention encore connue du runtime. Une reprise en cours prime sur l'échec précédent ; un échec
    /// constaté prime sur le verrou d'envoi (qui retombe) ; sans l'un ni l'autre, l'issue est à vérifier.
    func phase(of id: UUID) -> MessagingMediaIntentionPhase {
        if !pendingItems.contains(where: { $0.id == id }), let confirmed = confirmedAwaiting[id] {
            return .confirmed(cleanupPending: confirmed.cleanupPending)
        }
        if retryingID == id { return .sending }
        if let failure = failures[id] { return .failed(failure) }
        if sending, lastEnqueuedID == id { return .sending }
        return .toVerify
    }

    /// Intentions à projeter dans le fil, de la plus ancienne à la plus récente : en attente, puis confirmées dont le
    /// message réel n'est pas encore arrivé.
    var timelineEntries: [MessagingMediaPendingEntry] {
        var entries = pendingItems.map { MessagingMediaPendingEntry(snapshot: $0, phase: phase(of: $0.id)) }
        for (id, confirmed) in confirmedAwaiting where !pendingItems.contains(where: { $0.id == id }) {
            entries.append(MessagingMediaPendingEntry(snapshot: confirmed.snapshot,
                                                      phase: .confirmed(cleanupPending: confirmed.cleanupPending)))
        }
        return entries.sorted {
            $0.snapshot.createdAt == $1.snapshot.createdAt
                ? $0.id.uuidString < $1.id.uuidString : $0.snapshot.createdAt < $1.snapshot.createdAt
        }
    }

    /// Le message réel est dans le fil : la bulle locale n'a plus de raison d'être (l'identité d'affichage reste la même).
    func reconcile(visibleMessageIDs: Set<UUID>) {
        confirmedAwaiting = confirmedAwaiting.filter { !visibleMessageIDs.contains($0.value.serverMessageID) }
    }

    /// Relit les intentions durables sans effacer l'erreur ni rouvrir un contexte suspendu.
    func refreshPending() async {
        guard active else { return }
        let request = generation, revision = pendingRevision
        guard let items = try? await runtime.pending(conversationID: conversationID),
              active, request == generation, revision == pendingRevision else { return }
        pendingItems = items.filter { !confirmedIDs.contains($0.id) }
    }

    func suspend() {
        // La légende liée au brouillon du composeur n'est pas touchée ici : le brouillon a ses propres règles.
        active = false; generation = UUID(); selection = nil; localCaption = ""; selectionError = nil; preview = nil
        preparing = false; sending = false; pendingItems = []; failures = [:]
        for task in openTasks.values { task.cancel() }
        openTasks = [:]; openTickets = [:]; openStates = [:]; openEpoch = UUID()
        retryingID = nil; confirmedAwaiting = [:]; confirmedClientIDs = [:]
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

    nonisolated static func label(_ error: Error) -> String {
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
