import Foundation
import Observation

/// Une tuile du trajet en cours : un geste, l’heure du geste, la compétence précisée après la leçon.
enum SchoolLiveTile: CaseIterable, Identifiable, Sendable {
    case toWorkOn, attention, positive, marker
    var id: Self { self }
    var title: String {
        switch self {
        case .toWorkOn: "À retravailler"
        case .attention: "Attention"
        case .positive: "Positif"
        case .marker: "Repère"
        }
    }
    var symbol: String {
        switch self {
        case .toWorkOn: "xmark"
        case .attention: "exclamationmark"
        case .positive: "checkmark"
        case .marker: "bookmark.fill"
        }
    }
    /// Le serveur n’admet un constat qu’avec une compétence : la tuile pose un repère dont le texte garde
    /// le constat (relu par `SchoolObservationStatus(markerText:)` jusqu’à la relecture).
    var text: String {
        switch self {
        case .toWorkOn: SchoolObservationStatus.toWorkOn.label
        case .attention: SchoolObservationStatus.attention.label
        case .positive: SchoolObservationStatus.positive.label
        case .marker: "Moment à revoir"
        }
    }

    func body(operationID: UUID, observedAt: String) -> SchoolObservationBody {
        SchoolObservationBody(operationId: operationID, draftId: nil, captureId: nil, segmentId: nil, pointSequence: nil,
            competencyId: nil, text: text, origin: "LIVE", observedAt: observedAt, eventKind: "MARKER", eventStatus: nil)
    }
}

/// Une demande à la fois, écrite dans la file chiffrée dès le geste. Aucun geste n'attend uniquement en mémoire.
/// Le renvoi utilise la même opération et le même instant ; l'accès est relu par le client avant chaque envoi.
@MainActor @Observable final class SchoolLiveObservationRecorder {
    let scope: SchoolCommandScope
    let lessonID: UUID
    private(set) var confirmed = 0
    private(set) var errorMessage: String?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isSending = false
    var canRecord: Bool { !stopped && !isSending && pending == nil }
    @ObservationIgnored private let client: SchoolObservationClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var stopped = false

    init(scope: SchoolCommandScope, lessonID: UUID, client: SchoolObservationClient,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.lessonID = lessonID; self.client = client; self.outbox = outbox
        do { pending = try outbox.pending(for: scope) }
        catch { stopped = true; errorMessage = "Le stockage protégé est indisponible. Aucun repère n’a été ajouté." }
    }

    /// L’heure est prise au geste, avant tout réseau.
    @discardableResult func record(_ tile: SchoolLiveTile, at instant: Date = Date()) -> Bool {
        guard canRecord else { return false }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let operation = UUID()
        let value = tile.body(operationID: operation, observedAt: formatter.string(from: instant))
        do {
            let command = PendingSchoolCommand(id: operation, scope: scope, kind: .createObservation, resourceVersion: 0,
                createdAt: instant, body: try JSONEncoder().encode(value), routeResourceID: lessonID)
            try outbox.save(command)
            pending = command; errorMessage = nil
            Task { await retry() }
            return true
        } catch {
            errorMessage = "Le repère n’a pas été enregistré. Vérifiez les demandes en attente de la leçon."
            return false
        }
    }

    /// Accès changé ou trajet remplacé : plus aucun envoi depuis cette instance. Une demande déjà durable reste
    /// dans la file chiffrée et se vérifie depuis les observations de la leçon.
    func stop() { stopped = true }

    var canRetry: Bool {
        !stopped && !isSending && pending?.kind == .createObservation && pending?.routeResourceID == lessonID
    }
    func retry() async {
        guard canRetry, let command = pending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try outbox.save(command)
            _ = try await client.send(command)
            try outbox.remove(command)
            guard !stopped else { return }
            pending = nil; confirmed += 1; errorMessage = nil
        } catch {
            guard !stopped else { return }
            // Même un refus conserve le geste pour une relecture explicite depuis la leçon.
            errorMessage = "Repère conservé sur cet appareil. Son envoi reste à confirmer."
            if error as? SchoolObservationFailure == .unauthorized || error as? SchoolObservationFailure == .forbidden {
                stop(); errorMessage = "Votre accès a changé. Le repère reste conservé dans le compte d’origine."
            }
        }
    }
}
