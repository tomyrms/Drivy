import Foundation

/// Repère d’une fin de leçon ou d’une absence encore conservée dans le coffre chiffré (#114).
/// Rien n’y est confirmé : le repère dit ce que l’app a demandé, jamais ce que l’école a enregistré.
struct SchoolPendingClosureMarker: Identifiable, Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        case completion, absence

        /// Ce que la demande fait, avec les mots de la fiche de leçon.
        var inProgressTitle: String {
            switch self {
            case .completion: "Fin en cours"
            case .absence: "Absence en cours"
            }
        }

        /// Refus définitif de l’école : la demande ne sera pas envoyée de nouveau.
        var refusedTitle: String {
            switch self {
            case .completion: "Fin refusée"
            case .absence: "Absence refusée"
            }
        }
    }

    /// « en cours » : la demande vient d’être écrite et son envoi peut encore aboutir.
    /// « à vérifier » : l’app ne peut plus l’affirmer, la réponse de l’école manque.
    enum State: Equatable, Sendable {
        case inProgress, toVerify
    }

    /// Identifiant de l’opération conservée : la fiche de la leçon la retrouve à sa réouverture.
    let id: UUID
    /// Portée exacte de la demande : école, personne, rattachement et époque d’accès.
    let scope: SchoolCommandScope
    let kind: Kind
    /// Leçon visée : une fin ou une absence vise toujours une leçon.
    let lessonID: UUID
    let createdAt: Date
    let state: State

    /// Ce qu’affiche le repère. Jamais « Terminée » ni « Absence » : la preuve de l’école manque.
    var title: String {
        state == .inProgress ? kind.inProgressTitle : "À vérifier"
    }
}

/// Projection pure et en lecture seule du coffre : les fins de leçon et absences d’une portée, et rien d’autre.
/// Aucun envoi, aucune suppression : une demande se vérifie depuis la fiche de la leçon, jamais d’ici.
enum SchoolPendingClosureProjection {
    /// Demandes de la portée exacte, dans l’ordre où elles ont été écrites. Celles d’une autre école, d’une autre
    /// personne, d’un autre rattachement ou d’une autre époque d’accès n’existent pas ici. Les bilans, objectifs,
    /// signalements, permis et demandes de planification ne sont pas des fins de leçon et restent dehors.
    static func markers(from commands: [PendingSchoolCommand], scope: SchoolCommandScope, now: Date = Date())
        -> [SchoolPendingClosureMarker] {
        commands.compactMap { command -> SchoolPendingClosureMarker? in
            guard command.scope == scope, let kind = closureKind(of: command.kind),
                  let lessonID = command.resourceID else { return nil }
            // Hors de la fiche, l’app ne garde aucun état d’envoi : seul l’horodatage d’écriture distingue une demande
            // qui part d’une demande sans réponse. Une fin n’a pas d’horaire propre, elle n’expire donc jamais.
            let unanswered = now.timeIntervalSince(command.createdAt) > SchoolPendingPlanningProjection.inFlightWindow
            return SchoolPendingClosureMarker(id: command.id, scope: command.scope, kind: kind, lessonID: lessonID,
                createdAt: command.createdAt, state: unanswered ? .toVerify : .inProgress)
        }.sorted { left, right in
            left.createdAt == right.createdAt
                ? left.id.uuidString < right.id.uuidString
                : left.createdAt < right.createdAt
        }
    }

    /// Les deux seules demandes qui terminent une leçon ou notent une absence. Tout le reste du domaine
    /// pédagogique (planification, bilan, signalement, examen, cours) garde sa propre présentation.
    private static func closureKind(of kind: SchoolCommandKind) -> SchoolPendingClosureMarker.Kind? {
        switch kind {
        case .completeLesson: .completion
        case .markNoShow: .absence
        default: nil
        }
    }
}

/// Refus définitif d’une fin de leçon ou d’une absence reçu après la fermeture de la fiche (#114).
/// Mémoire seulement, jamais sur le disque : la demande a quitté le coffre, le titre dit ce qui s’est passé et la
/// raison se lit dans la fiche. Une autre école, une autre personne ou une autre époque d’accès n’en hérite pas.
struct SchoolRefusedClosureMarker: Identifiable, Equatable, Sendable {
    let lessonID: UUID
    let scope: SchoolCommandScope
    let kind: SchoolPendingClosureMarker.Kind

    var id: UUID { lessonID }
    var title: String { kind.refusedTitle }
}

/// Mémoire de session des refus : effacée à la réouverture de la fiche, au changement de portée et dès qu’une
/// relecture montre la leçon terminée. Rien n’est écrit sur l’appareil.
@MainActor enum SchoolRefusedClosureMemory {
    private static var stored: [SchoolRefusedClosureMarker] = []

    static func remember(lessonID: UUID, scope: SchoolCommandScope, kind: SchoolPendingClosureMarker.Kind) {
        stored.removeAll { $0.lessonID == lessonID && $0.scope == scope }
        stored.append(SchoolRefusedClosureMarker(lessonID: lessonID, scope: scope, kind: kind))
    }

    static func marker(forLesson lessonID: UUID, scope: SchoolCommandScope) -> SchoolRefusedClosureMarker? {
        stored.first { $0.lessonID == lessonID && $0.scope == scope }
    }

    static func markers(for scope: SchoolCommandScope) -> [SchoolRefusedClosureMarker] {
        stored.filter { $0.scope == scope }
    }

    /// La fiche se rouvre, ou la leçon est relue avec sa preuve : le repère a rempli son rôle.
    static func forget(lessonID: UUID, scope: SchoolCommandScope) {
        stored.removeAll { $0.lessonID == lessonID && $0.scope == scope }
    }

    /// Changement de portée (compte, école, rattachement, époque) : aucun repère d’un autre contexte ne survit.
    static func forgetAll() { stored.removeAll() }
}
