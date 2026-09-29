import Foundation
import Observation

/// Les sous-thèmes précisent une compétence existante, sans créer de référentiel parallèle.
struct SchoolLiveObservationTheme: Identifiable, Equatable {
    let competency: SchoolCatalogCompetency
    let title: String
    var id: String { "\(competency.id.uuidString):\(title)" }
    var symbol: String {
        switch title {
        case "Priorité à droite": "arrow.turn.up.right"
        case "Signalisation": "signpost.right"
        case "Céder le passage": "triangle"
        case "Vitesse", "Adaptation de la vitesse": "speedometer"
        case "Stationnement": "parkingsign"
        case "Observation", "Observation et contrôles": "eye"
        case "Anticipation": "arrow.up.forward"
        case "Giratoire", "Giratoires": "arrow.triangle.2.circlepath"
        default: "steeringwheel"
        }
    }

    static func choices(for competency: SchoolCatalogCompetency) -> [Self] {
        let description = competency.description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
        if competency.key == "priorites", description.contains("priorite de droite"),
           description.contains("signalisation"), description.contains("ceder le passage") {
            return ["Priorité à droite", "Signalisation", "Céder le passage"].map { .init(competency: competency, title: $0) }
        }
        let label = competency.key == "vitesse" && competency.label == "Adaptation de la vitesse" ? "Vitesse" : competency.displayLabel
        return [.init(competency: competency, title: label)]
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
    var themes: [SchoolLiveObservationTheme] { competencies.flatMap(SchoolLiveObservationTheme.choices) }
    var canRecord: Bool { !stopped && !isSending && pending == nil }
    @ObservationIgnored private let client: SchoolObservationClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private let onSettlement: (@MainActor () async -> Void)?
    @ObservationIgnored private var stopped = false

    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolObservationClient,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox(),
         onSettlement: (@MainActor () async -> Void)? = nil) {
        self.scope = scope; self.lessonID = lessonID; self.client = client; self.outbox = outbox
        self.onSettlement = onSettlement
        do { pending = try outbox.pending(for: scope) }
        catch { stopped = true; errorMessage = "Le stockage protégé est indisponible. Aucune observation n’a été ajoutée." }
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
            guard !stopped else { return }
            competenciesMessage = "Les thèmes n’ont pas pu être chargés. Réessayez pour choisir une observation précise."
        }
    }

    /// Le thème vient du référentiel reçu, le statut est un choix explicite.
    @discardableResult func record(theme: SchoolLiveObservationTheme, status: SchoolObservationStatus,
                                   at instant: Date) -> Bool {
        guard themes.contains(theme) else { return false }
        return save(theme: theme, status: status, at: instant)
    }

    @discardableResult func markMoment(at instant: Date = Date()) -> Bool {
        save(theme: nil, status: nil, at: instant)
    }

    private func save(theme: SchoolLiveObservationTheme?, status: SchoolObservationStatus?, at instant: Date) -> Bool {
        guard canRecord else { return false }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let operation = UUID()
        let value = SchoolObservationBody(operationId: operation, draftId: nil, captureId: nil,
            segmentId: nil, pointSequence: nil, competencyId: theme?.competency.id,
            text: theme?.title ?? "Moment à revoir", origin: "LIVE", observedAt: formatter.string(from: instant),
            eventKind: theme == nil ? "MARKER" : "QUALIFIED", eventStatus: status?.rawValue)
        do {
            let command = PendingSchoolCommand(id: operation, scope: scope, kind: .createObservation, resourceVersion: 0,
                createdAt: instant, body: try JSONEncoder().encode(value), routeResourceID: lessonID)
            try outbox.save(command)
            pending = command; errorMessage = nil
            Task { await retry() }
            return true
        } catch {
            errorMessage = "L’observation n’a pas été enregistrée. Vérifiez les demandes en attente de la leçon."
            return false
        }
    }

    /// Accès changé ou trajet remplacé : plus aucun envoi depuis cette instance. Une demande déjà durable reste
    /// dans la file chiffrée et se vérifie depuis les observations de la leçon.
    func stop() { stopped = true }

    func refreshPending() {
        guard !stopped, !isSending else { return }
        do { pending = try outbox.pending(for: scope); if pending == nil { errorMessage = nil } }
        catch { errorMessage = "Le stockage protégé n’a pas pu être relu." }
    }

    var canRetry: Bool {
        !stopped && !isSending && pending?.kind == .createObservation && pending?.routeResourceID == lessonID
    }
    func retry() async {
        guard canRetry, let command = pending else { return }
        isSending = true
        do {
            try outbox.save(command)
            _ = try await client.send(command)
            try outbox.remove(command)
            if !stopped { pending = nil; confirmed += 1; errorMessage = nil }
        } catch {
            if !stopped {
                // Même un refus conserve le geste pour une relecture explicite depuis la leçon.
                errorMessage = "Observation conservée sur cet appareil. Son envoi reste à confirmer."
                if error as? SchoolObservationFailure == .unauthorized || error as? SchoolObservationFailure == .forbidden {
                    stop(); errorMessage = "Votre accès a changé. L’observation reste conservée dans le compte d’origine."
                }
            }
        }
        isSending = false
        // La feuille peut déjà être fermée : avertir son propriétaire après le résultat réseau,
        // sans confondre la sauvegarde du geste et la confirmation de l’école.
        await onSettlement?()
    }
}
