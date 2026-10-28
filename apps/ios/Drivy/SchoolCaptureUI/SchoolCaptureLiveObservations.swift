import Foundation
import Observation

struct SchoolLiveObservationAnchor: Equatable {
    let captureID: UUID
    let segmentID: UUID
    let pointSequence: Int
}

/// A map marker exists only after its command was written to the encrypted outbox.
/// Coordinates remain in the encrypted capture store, addressed by the measured point.
struct SchoolLiveMapObservation: Identifiable {
    let id: UUID
    let body: SchoolObservationBody
    var isPending: Bool
}

struct SchoolLiveObservationReceipt: Identifiable, Equatable {
    let id: UUID
    let displayTitle: String
}

/// `refused` : l’école a refusé définitivement le signalement dès son premier envoi ; rien n’a été enregistré.
enum SchoolLiveObservationUndoState: Equatable { case none, pending, confirmed, refused }

/// Une tuile de « Signaler » : un thème du catalogue, tel que l’école l’affiche. Il ne dépend d’aucune compétence de la
/// formation (#56) : le référentiel sert à l’évaluation, jamais à décider quels signalements existent. L’identité est la clé.
struct SchoolLiveObservationTheme: Identifiable, Equatable {
    let key: String
    let title: String
    var id: String { key }

    /// Tuiles d’une leçon : les thèmes affichés, dans l’ordre donné. Un thème que l’école ne liste pas n’a pas de tuile : elle le
    /// refuserait. `includingHidden` sert au contrôle d’un signalement : masquer un thème ne le rend jamais inacceptable.
    static func tiles(for themes: [SchoolObservationTheme], unlisted: Set<String> = [],
                      includingHidden: Bool = false) -> [Self] {
        themes.filter { theme in (theme.visible || includingHidden) && !unlisted.contains(theme.key) }
            .map { theme in Self(key: theme.key, title: theme.title) }
    }
}

/// Chaque geste est écrit dans la file chiffrée avant de rendre la main ; aucun signalement n’attend en mémoire.
/// Les signalements de la leçon forment une file (#112) : un geste n’attend jamais l’envoi du précédent, même sans
/// réseau. Ils partent dans l’ordre des gestes, un à la fois, avec la même opération et le même instant à chaque
/// renvoi ; l’accès est relu par le client avant chaque envoi.
@MainActor @Observable final class SchoolLiveObservationRecorder {
    /// Au-delà, la leçon a besoin d’un retour du réseau : la file chiffrée de l’école reste bornée.
    static let maximumQueued = 30
    let scope: SchoolCommandScope
    let lessonID: UUID
    private(set) var confirmed = 0
    private(set) var errorMessage: String?
    /// Signalements de cette leçon conservés sur l’appareil, dans l’ordre des gestes.
    private(set) var queue: [PendingSchoolCommand] = []
    /// Autre demande de l’école, hors de cette file, qui empêche d’écrire (même domaine ou autre époque d’accès).
    private(set) var foreign: PendingSchoolCommand?
    /// Demande en tête : celle qui bloque, sinon le plus ancien signalement de la leçon encore à envoyer.
    var pending: PendingSchoolCommand? { foreign ?? queue.first }
    private(set) var isSending = false
    /// Envoi qui suit le geste lui-même (signalement ou son annulation), jamais un nouvel essai. Bref et déjà
    /// confirmé par le bandeau, il ne ferme pas « Signaler » et ne fait attendre aucune écriture.
    private(set) var isSettlingGesture = false
    private(set) var mapObservations: [SchoolLiveMapObservation] = []
    private(set) var lastAdded: SchoolLiveObservationReceipt?
    private(set) var undoState: SchoolLiveObservationUndoState = .none
    private(set) var undoErrorMessage: String?
    /// Instantané de la configuration, pris à l’ouverture de « Signaler » : une modification faite ailleurs
    /// pendant que la palette est ouverte ne déplace aucune tuile ; elle s’applique à l’ouverture suivante.
    private(set) var themeConfiguration: SchoolObservationThemeConfiguration
    /// Ordre automatique appliqué aux tuiles : celui que la leçon a pris à sa première ouverture de « Signaler »,
    /// figé jusqu’à sa fin. `nil` en mode manuel : l’ordre de l’école, tel que la configuration le donne.
    private(set) var signalOrder: [String]?
    /// Les thèmes affichés dans l’ordre figé, puis ceux que l’école a affichés depuis. Aucune lecture du référentiel :
    /// la palette est prête dès l’ouverture, avec ou sans réseau.
    var themes: [SchoolLiveObservationTheme] {
        SchoolLiveObservationTheme.tiles(
            for: SchoolObservationRankingOrder.arranged(themeConfiguration.themes, order: signalOrder),
            unlisted: themeConfiguration.unlisted)
    }
    /// Hauteur de la palette dès l’ouverture : les tuiles ne dépendent d’aucune lecture.
    var expectedTileCount: Int { themes.count }
    /// Signalements de la leçon pas encore confirmés par l’école.
    var queuedCount: Int { queue.count }
    var canRecord: Bool { !stopped && foreign == nil && queue.count < Self.maximumQueued }
    /// Seule une autre demande de l’école ou un arrêt ferment « Signaler » ; les signalements en file, non.
    var acceptsSignal: Bool { !stopped && foreign == nil }
    /// Une autre demande en attente (départ de leçon, fin de leçon, note…) bloque « Signaler » sans être une
    /// observation de cette leçon.
    var pendingIsForeign: Bool { foreign != nil }
    @ObservationIgnored private let client: SchoolObservationClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private let onSettlement: (@MainActor () async -> Void)?
    @ObservationIgnored private let permitsAnchor: (@MainActor (SchoolLiveObservationAnchor) -> Bool)?
    @ObservationIgnored private let prepareAnchor: (@MainActor (SchoolLiveObservationAnchor) async throws -> Void)?
    @ObservationIgnored private let themeStore: SchoolObservationThemeStore?
    @ObservationIgnored private let rankingStore: SchoolObservationRankingStore?
    @ObservationIgnored private let signalOrders: (any SchoolLessonSignalOrderStore)?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var lastAddedCommand: PendingSchoolCommand?
    @ObservationIgnored private var lastAddedWasConfirmed = false
    /// Gestes de cette instance : seuls eux peuvent être refusés « au premier envoi » sans vérification.
    @ObservationIgnored private var createdHere: Set<UUID> = []
    /// Demandes déjà parties au moins une fois depuis cette instance.
    @ObservationIgnored private var attempted: Set<UUID> = []
    /// Demande que l’envoi en cours porte, ou qu’il va porter dans ce tour.
    @ObservationIgnored private var inFlightID: UUID?
    /// L’instant appartient au geste d’ouverture : un second appui du même geste porte le même et n’écrit rien.
    @ObservationIgnored private var lastGestureInstant: Date?
    /// Renvoi automatique d’une file restée sur l’appareil faute de réseau : essais espacés, puis le dernier délai.
    @ObservationIgnored private let retryDelays: [Duration]
    @ObservationIgnored private var automaticRetry: Task<Void, Never>?
    @ObservationIgnored private var automaticRetryCount = 0
    /// Le dernier envoi a échoué faute d’école joignable : le retour du réseau le relance.
    @ObservationIgnored private var waitsForNetwork = false

    /// Sans `themeStore`, la palette garde le catalogue embarqué et n’envoie aucune clé de thème.
    /// Sans `rankingStore`, l’ordre est toujours celui de l’école. `signalOrders` garde l’ordre figé de la leçon
    /// d’un enregistreur au suivant ; à défaut, il ne tient que pour cette instance.
    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolObservationClient,
         themeStore: SchoolObservationThemeStore? = nil,
         rankingStore: SchoolObservationRankingStore? = nil,
         signalOrders: (any SchoolLessonSignalOrderStore)? = nil,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox(),
         permitsAnchor: (@MainActor (SchoolLiveObservationAnchor) -> Bool)? = nil,
         prepareAnchor: (@MainActor (SchoolLiveObservationAnchor) async throws -> Void)? = nil,
         onSettlement: (@MainActor () async -> Void)? = nil,
         retryDelays: [Duration] = [.seconds(5), .seconds(15), .seconds(60)]) {
        self.scope = scope; self.lessonID = lessonID; self.client = client; self.outbox = outbox
        self.themeStore = themeStore
        themeConfiguration = themeStore?.configuration ?? .embedded
        self.rankingStore = rankingStore
        let orders: (any SchoolLessonSignalOrderStore)?
        if rankingStore == nil { orders = nil }
        else if let signalOrders { orders = signalOrders }
        else { orders = SchoolLessonSignalOrderMemoryStore() }
        self.signalOrders = orders
        self.onSettlement = onSettlement
        self.retryDelays = retryDelays
        self.permitsAnchor = permitsAnchor; self.prepareAnchor = prepareAnchor
        // Avant la première ouverture : l’ordre déjà figé pour cette leçon (reprise), sans rien figer encore.
        signalOrder = Self.resolvedSignalOrder(ranking: rankingStore, orders: orders, lessonID: lessonID, freezing: false)
        do { try reload() }
        catch { stopped = true; errorMessage = "Le stockage protégé est indisponible. Aucune observation n’a été ajoutée." }
        for command in queue {
            guard let body = try? JSONDecoder().decode(SchoolObservationBody.self, from: command.body) else { continue }
            mapObservations.append(.init(id: command.id, body: body, isPending: true))
        }
        if let last = queue.last, let body = mapObservations.last(where: { $0.id == last.id })?.body, body.origin == "LIVE" {
            lastAddedCommand = last.withoutObservationUndo
            lastAdded = .init(id: last.id, displayTitle: body.eventKind == "MARKER" ? "Moment ajouté" : "Observation ajoutée")
            if last.observationUndoOperationID != nil { undoState = .pending }
        }
    }

    /// Ouverture de « Signaler » : la palette prend la dernière configuration confirmée, puis demande une
    /// relecture dont le résultat ne servira qu’à l’ouverture suivante. L’ordre automatique, lui, n’est pris
    /// qu’une fois par leçon ; la relecture du classement ne sert qu’à une leçon suivante.
    func openPalette() {
        if let themeStore {
            if themeConfiguration != themeStore.configuration { themeConfiguration = themeStore.configuration }
            Task { await themeStore.refresh() }
        }
        guard let rankingStore else { return }
        let order = Self.resolvedSignalOrder(ranking: rankingStore, orders: signalOrders, lessonID: lessonID, freezing: true)
        if signalOrder != order { signalOrder = order }
        Task { await rankingStore.refresh() }
    }

    /// Mode manuel : aucun ordre automatique, et rien n’est figé (un ordre figé plus tôt est ignoré, sans être
    /// effacé). Mode automatique : l’ordre figé pour la leçon s’il existe ; sinon l’ordre confirmé du classement,
    /// figé pour elle si `freezing`.
    private static func resolvedSignalOrder(ranking: SchoolObservationRankingStore?, orders: (any SchoolLessonSignalOrderStore)?,
                                            lessonID: UUID, freezing: Bool) -> [String]? {
        guard let ranking, ranking.mode == .smart else { return nil }
        if let frozen = orders?.order(for: lessonID), !frozen.isEmpty { return frozen }
        guard let order = ranking.effectiveOrder else { return nil }
        if freezing { orders?.freeze(order, lessonID: lessonID) }
        return order
    }

    /// Le thème vient du catalogue de l’école, le statut est un choix explicite. Un thème masqué depuis l’ouverture
    /// reste recevable : masquer n’est qu’un réglage d’affichage.
    @discardableResult func record(theme: SchoolLiveObservationTheme, status: SchoolObservationStatus,
                                   at instant: Date, anchor: SchoolLiveObservationAnchor? = nil) -> Bool {
        guard SchoolLiveObservationTheme.tiles(for: themeConfiguration.themes, unlisted: themeConfiguration.unlisted,
                                               includingHidden: true).contains(theme) else { return false }
        return save(theme: theme, status: status, at: instant, anchor: anchor)
    }

    @discardableResult func markMoment(at instant: Date = Date(), anchor: SchoolLiveObservationAnchor? = nil) -> Bool {
        save(theme: nil, status: nil, at: instant, anchor: anchor)
    }

    /// Le signalement fait partie de la file de cette leçon (en attente ou en cours d’envoi).
    func owns(_ command: PendingSchoolCommand?) -> Bool {
        guard let command, !stopped else { return false }
        return queue.contains { $0.id == command.id }
    }

    private func save(theme: SchoolLiveObservationTheme?, status: SchoolObservationStatus?, at instant: Date,
                      anchor: SchoolLiveObservationAnchor?) -> Bool {
        guard canRecord, lastGestureInstant != instant else { return false }
        if let anchor, permitsAnchor?(anchor) != true {
            errorMessage = "Le GPS a changé. Ferme puis rouvre Signaler pour enregistrer au bon endroit ou sans position."
            return false
        }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let operation = UUID()
        let value = SchoolObservationBody(operationId: operation, draftId: nil, captureId: anchor?.captureID,
            segmentId: anchor?.segmentID, pointSequence: anchor?.pointSequence, competencyId: nil,
            text: theme?.title ?? "Moment à revoir", origin: "LIVE", observedAt: formatter.string(from: instant),
            eventKind: theme == nil ? "MARKER" : "QUALIFIED", eventStatus: status?.rawValue,
            // Le thème qualifie seul le signalement (#56) : aucune compétence n’est jointe ni déduite. Le service doit
            // porter la migration 036 avant cette version de l’app (docs/implementation/signalements-autonomes-20261021.md).
            themeKey: theme?.key)
        let command: PendingSchoolCommand
        do {
            command = PendingSchoolCommand(id: operation, scope: scope, kind: .createObservation, resourceVersion: 0,
                createdAt: instant, body: try JSONEncoder().encode(value), routeResourceID: lessonID)
            try outbox.save(command)
        } catch {
            // Une autre demande a pu prendre la place entre-temps : la relecture la nomme.
            try? reload()
            errorMessage = "L’observation n’a pas été enregistrée. Vérifie les demandes en attente de la leçon."
            return false
        }
        queue.append(command); createdHere.insert(operation); lastGestureInstant = instant
        errorMessage = nil
        mapObservations.append(.init(id: operation, body: value, isPending: true))
        lastAddedCommand = command; lastAddedWasConfirmed = false
        lastAdded = .init(id: operation, displayTitle: theme == nil ? "Moment ajouté" : "Observation ajoutée")
        undoState = .none; undoErrorMessage = nil
        startSending(afterGesture: true)
        return true
    }

    /// Accès changé ou trajet remplacé : plus aucun envoi depuis cette instance. Les demandes déjà durables restent
    /// dans la file chiffrée et se vérifient depuis les observations de la leçon.
    func stop() {
        stopped = true
        automaticRetry?.cancel(); automaticRetry = nil; waitsForNetwork = false
        lastAdded = nil; lastAddedCommand = nil; undoState = .none; undoErrorMessage = nil
    }

    /// Sending the CREATE does not remove the right to request its durable withdrawal.
    func canUndo(_ id: UUID) -> Bool {
        guard !stopped, foreign == nil, lastAdded?.id == id, lastAddedCommand?.id == id, undoState == .none else { return false }
        return queue.contains { $0.id == id } || queue.count < Self.maximumQueued
    }

    /// Vrai : le retrait est durable, ou le geste n’avait jamais quitté l’appareil. Pas une confirmation de l’école.
    @discardableResult func undoLastAdded(id: UUID) async -> Bool {
        guard canUndo(id), let original = lastAddedCommand else { return false }
        // Encore en file derrière un autre signalement, jamais parti : rien n’a atteint l’école, le geste s’efface.
        if let queued = queue.first(where: { $0.id == id }), queued.observationUndoOperationID == nil,
           createdHere.contains(id), !attempted.contains(id), inFlightID != id {
            do { try outbox.remove(queued) }
            catch {
                undoErrorMessage = "L’annulation n’a pas pu être confirmée sur cet appareil. Réessaie."
                return false
            }
            queue.removeAll { $0.id == id }
            mapObservations.removeAll { $0.id == id }
            lastAddedCommand = nil; undoState = .confirmed; undoErrorMessage = nil
            if queue.isEmpty { errorMessage = nil }
            return true
        }
        let withdrawal = original.requestingObservationUndo(operationID: UUID())
        do {
            try outbox.save(withdrawal)
            replaceOrAppend(withdrawal)
            undoState = .pending; undoErrorMessage = nil; errorMessage = nil
            // A send already in flight will reread the upgraded command before acknowledging it.
            startSending(afterGesture: true)
            return true
        } catch {
            // An atomic write can have happened before a storage barrier failed. Keep that exact ID.
            if let stored = try? storedCommand(original.id), stored.observationUndoOperationID != nil {
                replaceOrAppend(stored); undoState = .pending
            }
            undoErrorMessage = "L’annulation n’a pas pu être confirmée sur cet appareil. Réessaie."
            return false
        }
    }

    func refreshPending() {
        guard !stopped, !isSending else { return }
        do { try reload(); if pending == nil { errorMessage = nil } }
        catch { errorMessage = "Le stockage protégé n’a pas pu être relu." }
    }

    var canRetry: Bool { !stopped && !isSending && foreign == nil && !queue.isEmpty }

    /// Retour du réseau : la file de cette leçon, restée sur l’appareil faute d’école joignable, repart aussitôt.
    func retryAfterReconnection() async {
        guard waitsForNetwork else { return }
        automaticRetry?.cancel(); automaticRetry = nil
        automaticRetryCount = 0
        await retry()
    }

    /// Nouvel essai demandé : toute la file, dans l’ordre. Attend le résultat de chaque envoi.
    func retry() async {
        guard canRetry else { return }
        automaticRetry?.cancel(); automaticRetry = nil
        isSending = true; isSettlingGesture = false
        await drain()
    }

    private func reload() throws {
        let commands = try outbox.pendingCommands(for: scope)
        queue = commands.filter(isQueued)
        foreign = commands.first { command in
            !isQueued(command) && (command.scope != scope || command.kind.schedulingDomain.conflicts(with: .teaching))
        }
    }

    private func isQueued(_ command: PendingSchoolCommand) -> Bool {
        command.scope == scope && command.kind == .createObservation && command.routeResourceID == lessonID
    }

    private func storedCommand(_ id: UUID) throws -> PendingSchoolCommand? {
        try outbox.pendingCommands(for: scope).first { $0.id == id }
    }

    private func replaceOrAppend(_ command: PendingSchoolCommand) {
        if let index = queue.firstIndex(where: { $0.id == command.id }) { queue[index] = command }
        else { queue.append(command) }
    }

    /// Nouvel essai espacé (5 s, 15 s, puis toutes les 60 s) tant que la file de cette leçon attend et que l’école
    /// reste injoignable. Mêmes opérations, mêmes corps.
    private func scheduleAutomaticRetry() {
        guard !stopped, !retryDelays.isEmpty, !queue.isEmpty, foreign == nil else { return }
        let delay = retryDelays[min(automaticRetryCount, retryDelays.count - 1)]
        automaticRetryCount += 1
        automaticRetry?.cancel()
        automaticRetry = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !self.stopped else { return }
            self.automaticRetry = nil
            await self.retry()
        }
    }

    /// L’envoi est réclamé dans le tour même de l’écriture durable : aucune image ne montre « attend son envoi »
    /// pour une demande qui part aussitôt. Une file déjà en cours d’envoi prend le nouveau geste à sa suite.
    private func startSending(afterGesture: Bool) {
        guard !isSending, !stopped, let head = queue.first else { return }
        automaticRetry?.cancel(); automaticRetry = nil
        isSending = true; isSettlingGesture = afterGesture
        // La tête part dans ce tour : une annulation immédiate passe par sa demande de retrait durable.
        inFlightID = head.id
        Task { await drain() }
    }

    private enum Outcome { case settled, waiting(unreachable: Bool), stopped }

    /// `isSending` est déjà vrai. Une demande à la fois, la plus ancienne d’abord ; un échec garde la suite en file.
    private func drain() async {
        var unreachable = false
        while !stopped, foreign == nil, let head = queue.first {
            let outcome = await transmit(head)
            if case .settled = outcome { continue }
            if case .waiting(let offline) = outcome { unreachable = offline }
            break
        }
        inFlightID = nil
        isSending = false; isSettlingGesture = false
        waitsForNetwork = unreachable && !stopped
        if waitsForNetwork { scheduleAutomaticRetry() } else { automaticRetryCount = 0 }
        // La feuille peut déjà être fermée : avertir son propriétaire après le résultat réseau,
        // sans confondre la sauvegarde du geste et la confirmation de l’école.
        await onSettlement?()
    }

    /// La demande relue dans la file chiffrée fait foi à chaque tour.
    private func transmit(_ initial: PendingSchoolCommand) async -> Outcome {
        // Arrêt survenu entre le geste et le départ : la demande reste dans la file, sans réécriture.
        guard !stopped else { return .stopped }
        // Premier envoi d’un geste de cette instance : aucune réponse antérieure de l’école ne peut exister.
        let firstSend = createdHere.contains(initial.id) && !attempted.contains(initial.id)
        attempted.insert(initial.id); inFlightID = initial.id
        var command = initial
        while true {
            do {
                // Abandonnée ou vérifiée depuis un autre écran : l’état relu fait foi, rien n’est réécrit.
                guard let current = try storedCommand(command.id) else {
                    queue.removeAll { $0.id == command.id }
                    return .settled
                }
                // Another observation screen may have upgraded this same command while we were idle.
                if current != command, current.withoutObservationUndo == command.withoutObservationUndo {
                    command = current; replaceOrAppend(current)
                }
                try outbox.save(command)
                let body = try JSONDecoder().decode(SchoolObservationBody.self, from: command.body)
                guard !stopped else { throw CancellationError() }
                let result = try await client.send(command, beforeCreation: { [self] in
                    guard !stopped else { throw CancellationError() }
                    if let captureID = body.captureId, let segmentID = body.segmentId, let sequence = body.pointSequence {
                        try await prepareAnchor?(.init(captureID: captureID, segmentID: segmentID, pointSequence: sequence))
                    }
                }, validateContinuation: { [self] in
                    guard !stopped else { throw CancellationError() }
                })
                if let current = try storedCommand(command.id), current != command {
                    guard current.withoutObservationUndo == command, current.observationUndoOperationID != nil else {
                        throw SchoolConfigurationFailure.storage
                    }
                    // The CREATE succeeded, but its withdrawal now owns the durable slot.
                    if stopped { return .stopped }
                    command = current; replaceOrAppend(current)
                    if lastAdded?.id == command.id { undoState = .pending }
                    continue
                }
                try outbox.remove(command)
                queue.removeAll { $0.id == command.id }
                guard !stopped else { return .stopped }
                if queue.isEmpty { errorMessage = nil }
                switch result {
                case .observation:
                    confirmed += 1
                    if lastAdded?.id == command.id { lastAddedWasConfirmed = true }
                    if let index = mapObservations.firstIndex(where: { $0.id == command.id }) { mapObservations[index].isPending = false }
                case .removed:
                    mapObservations.removeAll { $0.id == command.id }
                    if lastAdded?.id == command.id {
                        if lastAddedWasConfirmed { confirmed = max(0, confirmed - 1) }
                        undoState = .confirmed; undoErrorMessage = nil
                    }
                }
                return .settled
            } catch {
                // A concurrent undo must survive both a late response and an uncertain CREATE failure.
                if !stopped, command.observationUndoOperationID == nil,
                   let current = try? storedCommand(command.id), current.withoutObservationUndo == command,
                   current.observationUndoOperationID != nil {
                    command = current; replaceOrAppend(current)
                    if lastAdded?.id == command.id { undoState = .pending }
                    continue
                }
                // Refus définitif de l’école au premier envoi (leçon close, limite atteinte, position qui n’est
                // plus admissible) : rien n’a été enregistré et le même envoi serait refusé à nouveau. La demande
                // quitte la file, le bandeau cesse d’annoncer un ajout et les signalements suivants partent.
                if !stopped, firstSend, command.observationUndoOperationID == nil,
                   let refusal = error as? SchoolObservationFailure, refusal.permitsFreshCorrection,
                   (try? outbox.remove(command)) != nil {
                    queue.removeAll { $0.id == command.id }
                    mapObservations.removeAll { $0.id == command.id }
                    errorMessage = "Observation non enregistrée. \(refusal.errorDescription ?? "L’école l’a refusée.")"
                    if lastAdded?.id == command.id {
                        lastAddedCommand = nil; undoState = .refused; undoErrorMessage = errorMessage
                    }
                    return .settled
                }
                guard !stopped else { return .stopped }
                if command.observationUndoOperationID != nil {
                    errorMessage = "Annulation conservée sur cet appareil. Son retrait reste à confirmer."
                    undoErrorMessage = (error as? SchoolObservationFailure)?.errorDescription ?? errorMessage
                } else if queue.count > 1 {
                    errorMessage = "\(queue.count) signalements conservés sur cet appareil. Leur envoi reste à confirmer."
                } else {
                    errorMessage = "Observation conservée sur cet appareil. Son envoi reste à confirmer."
                }
                if error as? SchoolObservationFailure == .unauthorized || error as? SchoolObservationFailure == .forbidden {
                    stop(); errorMessage = "Ton accès a changé. Les demandes restent conservées dans le compte d’origine."
                    return .stopped
                }
                return .waiting(unreachable: error as? SchoolObservationFailure == .unavailable)
            }
        }
    }
}
