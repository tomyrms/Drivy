import Foundation

// Corrections et retraits d'observations après la leçon (#112). Chacun est écrit dans un coffre chiffré avant son envoi, puis part sans
// retenir l'écran ni les autres observations : deux corrections de deux observations se suivent sans s'attendre. Après un arrêt de
// l'app, une demande sans réponse revient « non confirmée » avec Réessayer (même opération : l'école ne l'enregistre pas deux fois) et
// Abandonner. Rien n'est jamais renvoyé sans le geste de la personne, et l'observation n'est présentée comme modifiée ou retirée
// qu'après la réponse de l'école.

@MainActor
protocol SchoolObservationCorrectionStoring: AnyObject {
    /// Demandes conservées pour cette leçon, le plus ancien d'abord.
    func commands(scope: SchoolCommandScope, lessonID: UUID) throws -> [PendingSchoolCommand]
    func save(_ command: PendingSchoolCommand) throws
    func remove(_ command: PendingSchoolCommand) throws
}

/// Un seul coffre par appareil ; les écrans de contrôle et les tests y mettent un coffre en mémoire.
@MainActor enum SchoolObservationCorrectionStores {
    static var shared: any SchoolObservationCorrectionStoring = EncryptedSchoolObservationCorrectionStore()
}

/// Coffre chiffré, distinct de celui des commandes de l'école : une correction n'attend ni ne bloque aucune autre écriture, et la file
/// des signalements en direct ne la voit pas.
@MainActor
final class EncryptedSchoolObservationCorrectionStore: SchoolObservationCorrectionStoring {
    private let outbox: EncryptedSchoolCommandOutbox

    init(directory: URL? = nil, keyData: Data? = nil, vault: (any IdentityVault)? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolObservationCorrections", isDirectory: true)
        outbox = EncryptedSchoolCommandOutbox(directory: base, keyData: keyData, vault: vault)
    }

    func commands(scope: SchoolCommandScope, lessonID: UUID) throws -> [PendingSchoolCommand] {
        var kept: [PendingSchoolCommand] = []
        for command in try outbox.pendingCommands(for: scope)
        where command.kind.isObservationCorrection && command.routeResourceID == lessonID && command.scope.sharesMembership(with: scope) {
            if command.scope == scope { kept.append(command); continue }
            // Même compte, même école, même adhésion : seule l'époque d'accès a avancé (une affectation de plus, par exemple).
            // L'école relit les droits au rejeu ; la demande suit la portée actuelle plutôt que de rester bloquée.
            let moved = PendingSchoolCommand(id: command.id, scope: scope, kind: command.kind, resourceVersion: command.resourceVersion,
                createdAt: command.createdAt, body: command.body, resourceID: command.resourceID, routeResourceID: command.routeResourceID)
            try outbox.remove(command)
            try outbox.save(moved)
            kept.append(moved)
        }
        return kept.sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ command: PendingSchoolCommand) throws { try outbox.save(command) }
    func remove(_ command: PendingSchoolCommand) throws { try outbox.remove(command) }
}

/// Coffre en mémoire : tests et écrans de contrôle, qui n'écrivent aucun fichier.
@MainActor
final class SchoolObservationCorrectionMemoryStore: SchoolObservationCorrectionStoring {
    private(set) var stored: [PendingSchoolCommand] = []
    /// Simule un appareil qui ne peut rien conserver.
    var refusesToStore = false

    func commands(scope: SchoolCommandScope, lessonID: UUID) throws -> [PendingSchoolCommand] {
        stored.filter { $0.kind.isObservationCorrection && $0.routeResourceID == lessonID && $0.scope.sharesMembership(with: scope) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ command: PendingSchoolCommand) throws {
        guard !refusesToStore else { throw SchoolConfigurationFailure.storage }
        // Même règle que le coffre chiffré : une seule demande à la fois pour une même observation.
        guard !stored.contains(where: { $0.id != command.id && $0.resourceID == command.resourceID && $0.routeResourceID == command.routeResourceID })
        else { throw SchoolConfigurationFailure.pendingCommand }
        stored.removeAll { $0.id == command.id }
        stored.append(command)
    }

    func remove(_ command: PendingSchoolCommand) throws { stored.removeAll { $0.id == command.id } }
}

/// Correction ou retrait d'une observation, du geste à la réponse de l'école. L'identifiant est l'`operationId` : une reprise
/// renvoie exactement la même demande.
struct SchoolObservationCorrection: Identifiable, Equatable {
    enum State: Equatable {
        case queued, sending
        /// Panne ou réponse perdue : peut-être enregistrée, jamais présentée comme un refus ni comme acquise.
        case uncertain(String)
    }

    let command: PendingSchoolCommand
    var state: State

    var id: UUID { command.id }
    var observationID: UUID? { command.resourceID }
    var isRemoval: Bool { command.kind == .removeObservation }

    /// L'observation telle que la demande la montrera. Elle n'est jamais présentée comme confirmée : la ligne dit qu'elle est en cours.
    func projecting(_ observation: SchoolObservation) -> SchoolObservation {
        guard command.kind == .updateObservation, command.resourceID == observation.id,
              let body = try? JSONDecoder().decode(SchoolObservationBody.self, from: command.body) else { return observation }
        return SchoolObservation(id: observation.id, schoolId: observation.schoolId, version: observation.version,
            lessonId: observation.lessonId, trainingId: observation.trainingId, draftId: observation.draftId,
            captureId: observation.captureId, segmentId: observation.segmentId, pointSequence: observation.pointSequence,
            competencyId: body.competencyId, text: body.text, origin: observation.origin, observedAt: observation.observedAt,
            eventKind: body.eventKind ?? observation.eventKind, eventStatus: body.eventStatus,
            authorMembershipId: observation.authorMembershipId, themeKey: body.themeKey)
    }
}

enum SchoolObservationCorrectionText {
    static let restored = "Demande conservée sur cet appareil, pas encore confirmée par l’école."
    static let unkept = "Cet appareil ne peut pas conserver cette demande : elle n’a pas été envoyée."
    static let alreadyPending = "Une demande est déjà en cours pour cette observation."
}
