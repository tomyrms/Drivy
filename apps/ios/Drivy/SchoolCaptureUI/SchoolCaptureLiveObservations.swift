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

/// Une tuile de « Signaler ». Les thèmes du catalogue précisent une compétence existante, sans créer de
/// référentiel parallèle ; `key` vaut `nil` pour la tuile générique d’une compétence qu’aucun thème ne désigne.
struct SchoolLiveObservationTheme: Identifiable, Equatable {
    let competency: SchoolCatalogCompetency
    let title: String
    var key: String? = nil
    var id: String { "\(competency.id.uuidString):\(title)" }

    /// Tuiles d’une formation : les thèmes affichés, dans l’ordre de l’école, dont la compétence existe dans le
    /// référentiel (première clé de `competencyKeys` trouvée) ; puis une tuile générique pour chaque compétence
    /// qu’aucun thème du catalogue, affiché ou masqué, n’a prise. `includingHidden` sert au contrôle d’un
    /// signalement : masquer un thème ne le rend jamais inacceptable.
    static func tiles(for themes: [SchoolObservationTheme], competencies: [SchoolCatalogCompetency],
                      includingHidden: Bool = false) -> [Self] {
        var result: [Self] = []
        var claimed = Set<UUID>()
        for theme in themes {
            guard let key = theme.competencyKeys.first(where: { key in competencies.contains { $0.key == key } }),
                  let competency = competencies.first(where: { $0.key == key }) else { continue }
            claimed.insert(competency.id)
            if theme.visible || includingHidden { result.append(.init(competency: competency, title: theme.title, key: theme.key)) }
        }
        for competency in competencies where !claimed.contains(competency.id) {
            result.append(.init(competency: competency, title: competency.displayLabel))
        }
        return result
    }
}

/// Une demande à la fois, écrite dans la file chiffrée dès le geste. Aucun geste n'attend uniquement en mémoire.
/// Le renvoi utilise la même opération et le même instant ; l'accès est relu par le client avant chaque envoi.
@MainActor @Observable final class SchoolLiveObservationRecorder {
    let scope: SchoolCommandScope
    let lessonID: UUID
    private(set) var competencies: [SchoolCatalogCompetency] = []
    private(set) var isLoadingCompetencies = false
    private(set) var competenciesMessage: String?
    private(set) var confirmed = 0
    private(set) var errorMessage: String?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isSending = false
    /// Envoi qui suit le geste lui-même (signalement ou son annulation), jamais un nouvel essai. Bref et déjà
    /// confirmé par le bandeau, il ne ferme pas « Signaler » : seule l’écriture suivante l’attend.
    private(set) var isSettlingGesture = false
    private(set) var mapObservations: [SchoolLiveMapObservation] = []
    private(set) var lastAdded: SchoolLiveObservationReceipt?
    private(set) var undoState: SchoolLiveObservationUndoState = .none
    private(set) var undoErrorMessage: String?
    /// Instantané de la configuration, pris à l’ouverture de « Signaler » : une modification faite ailleurs
    /// pendant que la palette est ouverte ne déplace aucune tuile ; elle s’applique à l’ouverture suivante.
    private(set) var themeConfiguration: SchoolObservationThemeConfiguration
    var themes: [SchoolLiveObservationTheme] {
        SchoolLiveObservationTheme.tiles(for: themeConfiguration.themes, competencies: competencies)
    }
    /// Nombre de tuiles attendu avant la lecture du référentiel, pour donner d’emblée sa hauteur à la palette.
    var expectedTileCount: Int {
        competencies.isEmpty && competenciesMessage == nil ? themeConfiguration.visibleCount : themes.count
    }
    var canRecord: Bool { !stopped && !isSending && pending == nil }
    /// Rien de durable n’empêche d’ouvrir un signalement : ni arrêt, ni demande à vérifier ou à renvoyer.
    /// L’écriture elle-même reste gardée par `canRecord`, une demande à la fois.
    var acceptsSignal: Bool { !stopped && (pending == nil || isSettlingGesture) }
    /// La file chiffrée n’accepte qu’une demande par école : une autre demande en attente (départ de
    /// leçon, fin de leçon, note…) bloque « Signaler » sans être une observation de cette leçon.
    var pendingIsForeign: Bool {
        guard let pending else { return false }
        return !(pending.kind == .createObservation && pending.routeResourceID == lessonID)
    }
    @ObservationIgnored private let client: SchoolObservationClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private let onSettlement: (@MainActor () async -> Void)?
    @ObservationIgnored private let permitsAnchor: (@MainActor (SchoolLiveObservationAnchor) -> Bool)?
    @ObservationIgnored private let prepareAnchor: (@MainActor (SchoolLiveObservationAnchor) async throws -> Void)?
    @ObservationIgnored private let themeStore: SchoolObservationThemeStore?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var lastAddedCommand: PendingSchoolCommand?
    @ObservationIgnored private var lastAddedWasConfirmed = false

    /// Sans `themeStore`, la palette garde le catalogue embarqué et n’envoie aucune clé de thème.
    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolObservationClient,
         themeStore: SchoolObservationThemeStore? = nil,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox(),
         permitsAnchor: (@MainActor (SchoolLiveObservationAnchor) -> Bool)? = nil,
         prepareAnchor: (@MainActor (SchoolLiveObservationAnchor) async throws -> Void)? = nil,
         onSettlement: (@MainActor () async -> Void)? = nil) {
        self.scope = scope; self.lessonID = lessonID; self.client = client; self.outbox = outbox
        self.themeStore = themeStore
        themeConfiguration = themeStore?.configuration ?? .embedded
        self.onSettlement = onSettlement
        self.permitsAnchor = permitsAnchor; self.prepareAnchor = prepareAnchor
        do { pending = try outbox.pending(for: scope) }
        catch { stopped = true; errorMessage = "Le stockage protégé est indisponible. Aucune observation n’a été ajoutée." }
        if let pending, pending.scope == scope, pending.kind == .createObservation, pending.routeResourceID == lessonID,
           let body = try? JSONDecoder().decode(SchoolObservationBody.self, from: pending.body) {
            mapObservations = [.init(id: pending.id, body: body, isPending: true)]
            if body.origin == "LIVE" {
                lastAddedCommand = pending.withoutObservationUndo
                lastAdded = .init(id: pending.id, displayTitle: body.eventKind == "MARKER" ? "Moment ajouté" : "Observation ajoutée")
                if pending.observationUndoOperationID != nil { undoState = .pending }
            }
        }
    }

    func loadCompetencies() async {
        guard !stopped, !isLoadingCompetencies, competencies.isEmpty else { return }
        isLoadingCompetencies = true
        defer { isLoadingCompetencies = false }
        do {
            let lesson = try await client.agenda.lesson(schoolID: scope.schoolID, id: lessonID)
            let values = try await client.competencies(scope: scope, trainingID: lesson.trainingId)
            guard !stopped else { return }
            competencies = values
            competenciesMessage = values.isEmpty ? "Aucune compétence n’est disponible pour cette formation." : nil
        } catch {
            // Feuille fermée pendant la lecture : la requête annulée n’est pas un échec à afficher à la
            // réouverture, qui relance elle-même la lecture.
            guard !stopped, !Task.isCancelled, (error as? URLError)?.code != .cancelled,
                  !(error is CancellationError) else { return }
            competenciesMessage = "Les thèmes n’ont pas pu être chargés. Réessaie pour choisir une observation précise."
        }
    }

    /// Ouverture de « Signaler » : la palette prend la dernière configuration confirmée, puis demande une
    /// relecture dont le résultat ne servira qu’à l’ouverture suivante.
    func openPalette() {
        guard let themeStore else { return }
        if themeConfiguration != themeStore.configuration { themeConfiguration = themeStore.configuration }
        Task { await themeStore.refresh() }
    }

    /// Le thème vient du référentiel reçu, le statut est un choix explicite. Un thème masqué depuis l’ouverture
    /// reste recevable : masquer n’est qu’un réglage d’affichage.
    @discardableResult func record(theme: SchoolLiveObservationTheme, status: SchoolObservationStatus,
                                   at instant: Date, anchor: SchoolLiveObservationAnchor? = nil) -> Bool {
        guard SchoolLiveObservationTheme.tiles(for: themeConfiguration.themes, competencies: competencies,
                                               includingHidden: true).contains(theme) else { return false }
        return save(theme: theme, status: status, at: instant, anchor: anchor)
    }

    @discardableResult func markMoment(at instant: Date = Date(), anchor: SchoolLiveObservationAnchor? = nil) -> Bool {
        save(theme: nil, status: nil, at: instant, anchor: anchor)
    }

    private func save(theme: SchoolLiveObservationTheme?, status: SchoolObservationStatus?, at instant: Date,
                      anchor: SchoolLiveObservationAnchor?) -> Bool {
        guard canRecord else { return false }
        if let anchor, permitsAnchor?(anchor) != true {
            errorMessage = "Le GPS a changé. Ferme puis rouvre Signaler pour enregistrer au bon endroit ou sans position."
            return false
        }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let operation = UUID()
        let value = SchoolObservationBody(operationId: operation, draftId: nil, captureId: anchor?.captureID,
            segmentId: anchor?.segmentID, pointSequence: anchor?.pointSequence, competencyId: theme?.competency.id,
            text: theme?.title ?? "Moment à revoir", origin: "LIVE", observedAt: formatter.string(from: instant),
            eventKind: theme == nil ? "MARKER" : "QUALIFIED", eventStatus: status?.rawValue,
            // Une école qui n’a jamais répondu ne connaît peut-être pas ce champ, et une école plus ancienne ne
            // connaît pas tous les thèmes : la clé ne part qu’avec sa configuration, pour un thème qu’elle liste.
            themeKey: themeConfiguration.sendsThemeKey(theme?.key) ? theme?.key : nil)
        do {
            let command = PendingSchoolCommand(id: operation, scope: scope, kind: .createObservation, resourceVersion: 0,
                createdAt: instant, body: try JSONEncoder().encode(value), routeResourceID: lessonID)
            try outbox.save(command)
            pending = command; errorMessage = nil
            mapObservations.append(.init(id: operation, body: value, isPending: true))
            lastAddedCommand = command; lastAddedWasConfirmed = false
            lastAdded = .init(id: operation, displayTitle: theme == nil ? "Moment ajouté" : "Observation ajoutée")
            undoState = .none; undoErrorMessage = nil
            sendAfterGesture(command)
            return true
        } catch {
            errorMessage = "L’observation n’a pas été enregistrée. Vérifie les demandes en attente de la leçon."
            return false
        }
    }

    /// Accès changé ou trajet remplacé : plus aucun envoi depuis cette instance. Une demande déjà durable reste
    /// dans la file chiffrée et se vérifie depuis les observations de la leçon.
    func stop() {
        stopped = true
        lastAdded = nil; lastAddedCommand = nil; undoState = .none; undoErrorMessage = nil
    }

    /// Sending the CREATE does not remove the right to request its durable withdrawal.
    func canUndo(_ id: UUID) -> Bool {
        !stopped && lastAdded?.id == id && lastAddedCommand?.id == id && undoState == .none
            && (pending == nil || (pending?.id == id && pending?.scope == scope))
    }

    /// True means the withdrawal intent is durable, not that the service has removed the observation.
    @discardableResult func undoLastAdded(id: UUID) async -> Bool {
        guard canUndo(id), let original = lastAddedCommand else { return false }
        let withdrawal = original.requestingObservationUndo(operationID: UUID())
        do {
            try outbox.save(withdrawal)
            pending = withdrawal; undoState = .pending; undoErrorMessage = nil; errorMessage = nil
            // A send already in flight will reread the upgraded command before acknowledging it.
            if !isSending { sendAfterGesture(withdrawal) }
            return true
        } catch {
            // An atomic write can have happened before a storage barrier failed. Keep that exact ID.
            if let stored = try? outbox.pending(for: scope), stored.id == original.id,
               stored.observationUndoOperationID != nil {
                pending = stored; undoState = .pending
            }
            undoErrorMessage = "L’annulation n’a pas pu être confirmée sur cet appareil. Réessaie."
            return false
        }
    }

    func refreshPending() {
        guard !stopped, !isSending else { return }
        do { pending = try outbox.pending(for: scope); if pending == nil { errorMessage = nil } }
        catch { errorMessage = "Le stockage protégé n’a pas pu être relu." }
    }

    var canRetry: Bool {
        !stopped && !isSending && pending?.scope == scope
            && pending?.kind == .createObservation && pending?.routeResourceID == lessonID
    }
    func retry() async {
        guard canRetry, let initial = pending else { return }
        // Une demande retirée ou remplacée depuis un autre écran (abandon, vérification réussie) n’est pas
        // réécrite dans la file : l’état relu fait foi.
        guard let stored = try? outbox.pending(for: scope),
              stored.withoutObservationUndo == initial.withoutObservationUndo else { refreshPending(); return }
        isSending = true
        await transmit(stored)
    }

    /// L’envoi est réclamé dans le tour même de l’écriture durable : aucune image ne montre « attend son
    /// envoi » pour une demande qui part aussitôt.
    private func sendAfterGesture(_ command: PendingSchoolCommand) {
        isSending = true; isSettlingGesture = true
        Task { await transmit(command) }
    }

    /// `isSending` est déjà vrai. La demande relue dans la file chiffrée fait foi à chaque tour.
    private func transmit(_ initial: PendingSchoolCommand) async {
        // Arrêt survenu entre le geste et le départ : la demande reste dans la file, sans réécriture.
        guard !stopped else { isSending = false; isSettlingGesture = false; return }
        // Premier envoi, dans le tour du geste : aucune réponse antérieure de l’école ne peut exister.
        let followsGesture = isSettlingGesture
        var command = initial
        while true {
            do {
                // Another observation screen may have upgraded this same command while we were idle.
                if let current = try outbox.pending(for: scope), current.withoutObservationUndo == command.withoutObservationUndo {
                    command = current; pending = current
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
                if let current = try outbox.pending(for: scope), current != command {
                    guard current.withoutObservationUndo == command, current.observationUndoOperationID != nil else {
                        throw SchoolConfigurationFailure.storage
                    }
                    // The CREATE succeeded, but its withdrawal now owns the durable slot.
                    if stopped { break }
                    command = current; pending = current; undoState = .pending
                    continue
                }
                try outbox.remove(command)
                if !stopped {
                    pending = nil; errorMessage = nil
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
                }
                break
            } catch {
                // A concurrent undo must survive both a late response and an uncertain CREATE failure.
                if !stopped, command.observationUndoOperationID == nil,
                   let current = try? outbox.pending(for: scope), current.withoutObservationUndo == command,
                   current.observationUndoOperationID != nil {
                    command = current; pending = current; undoState = .pending
                    continue
                }
                // Refus définitif de l’école au premier envoi (leçon close, limite atteinte, position qui n’est
                // plus admissible) : rien n’a été enregistré et le même envoi serait refusé à nouveau. La demande
                // quitte la file, qu’elle bloquerait pour toute autre écriture, et le bandeau cesse d’annoncer un ajout.
                if !stopped, followsGesture, command.observationUndoOperationID == nil,
                   let refusal = error as? SchoolObservationFailure, refusal.permitsFreshCorrection,
                   (try? outbox.remove(command)) != nil {
                    pending = nil
                    mapObservations.removeAll { $0.id == command.id }
                    errorMessage = "Observation non enregistrée. \(refusal.errorDescription ?? "L’école l’a refusée.")"
                    if lastAdded?.id == command.id {
                        lastAddedCommand = nil; undoState = .refused; undoErrorMessage = errorMessage
                    }
                    break
                }
                if !stopped {
                    errorMessage = command.observationUndoOperationID == nil
                        ? "Observation conservée sur cet appareil. Son envoi reste à confirmer."
                        : "Annulation conservée sur cet appareil. Son retrait reste à confirmer."
                    if command.observationUndoOperationID != nil {
                        undoErrorMessage = (error as? SchoolObservationFailure)?.errorDescription ?? errorMessage
                    }
                    if error as? SchoolObservationFailure == .unauthorized || error as? SchoolObservationFailure == .forbidden {
                        stop(); errorMessage = "Ton accès a changé. La demande reste conservée dans le compte d’origine."
                    }
                }
                break
            }
        }
        isSending = false; isSettlingGesture = false
        // La feuille peut déjà être fermée : avertir son propriétaire après le résultat réseau,
        // sans confondre la sauvegarde du geste et la confirmation de l’école.
        await onSettlement?()
    }
}
