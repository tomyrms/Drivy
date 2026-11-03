import Foundation

/// Repère d’une demande de planification conservée dans le coffre chiffré (#108, #109).
/// Rien n’y est confirmé : le repère dit ce que l’app a demandé, jamais ce que l’école a enregistré.
struct SchoolPendingPlanningMarker: Identifiable, Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        case creation, move, cancellation

        /// Ce que la demande fait, dans les mots déjà employés par la feuille de planification.
        var inProgressTitle: String {
            switch self {
            case .creation: "Planification en cours"
            case .move: "Déplacement en cours"
            case .cancellation: "Annulation en cours"
            }
        }
    }

    /// « en cours » : la demande vient d’être écrite et son envoi peut encore aboutir.
    /// « à vérifier » : l’app ne peut plus l’affirmer, la réponse de l’école manque.
    enum State: Equatable, Sendable {
        case inProgress, toVerify
    }

    /// Identifiant de l’opération conservée : c’est lui qui rouvre la feuille sur cette demande.
    let id: UUID
    /// Portée exacte de la demande : école, personne, rattachement et époque d’accès.
    let scope: SchoolCommandScope
    let kind: Kind
    /// Leçon visée par un déplacement ou une annulation ; jamais renseignée par une création.
    let lessonID: UUID?
    /// Début voulu par une création ou un déplacement ; nil pour une annulation, qui garde l’horaire de la leçon.
    let requestedStart: Date?
    let createdAt: Date
    let state: State

    /// Ce qu’affiche le repère. Jamais « Réservé », « Déplacé » ni « Annulé » : la preuve de l’école manque.
    var title: String {
        state == .inProgress ? kind.inProgressTitle : "À vérifier"
    }

    /// Un repère posé sur une leçon confirmée la laisse à sa place ; une création n’en a aucune.
    func concerns(_ lessonID: UUID) -> Bool { self.lessonID == lessonID }
}

/// Projection pure et en lecture seule du coffre : les demandes de planification d’une portée, et rien d’autre.
/// Aucun envoi, aucune suppression : un repère se vérifie depuis la feuille de planification, jamais d’ici.
enum SchoolPendingPlanningProjection {
    /// Une demande plus vieille que ce délai n’a plus d’envoi en cours : hors de la feuille, l’app ne garde aucun
    /// état d’envoi, seul l’horodatage d’écriture distingue une demande qui part d’une demande sans réponse.
    static let inFlightWindow: TimeInterval = 60

    /// Demandes de la portée exacte, dans l’ordre où elles comptent : celles d’une autre école, d’une autre personne,
    /// d’un autre rattachement ou d’une autre époque d’accès n’existent pas ici. Les bilans, fins de leçon,
    /// signalements et préférences de planification ne sont pas des demandes de planification et restent dehors.
    static func markers(from commands: [PendingSchoolCommand], scope: SchoolCommandScope, now: Date = Date())
        -> [SchoolPendingPlanningMarker] {
        commands.compactMap { command -> SchoolPendingPlanningMarker? in
            guard command.scope == scope, command.kind.schedulingDomain == .teaching,
                  let kind = planningKind(of: command.kind) else { return nil }
            let stale = command.isStaleLessonRequest(at: now)
            let unanswered = now.timeIntervalSince(command.createdAt) > inFlightWindow
            let state: SchoolPendingPlanningMarker.State = stale || unanswered ? .toVerify : .inProgress
            return SchoolPendingPlanningMarker(id: command.id, scope: command.scope, kind: kind,
                lessonID: kind == .creation ? nil : command.resourceID,
                requestedStart: command.requestedLessonStart, createdAt: command.createdAt, state: state)
        }.sorted { left, right in
            let leftDate = left.requestedStart ?? left.createdAt, rightDate = right.requestedStart ?? right.createdAt
            return leftDate == rightDate ? left.id.uuidString < right.id.uuidString : leftDate < rightDate
        }
    }

    /// Les trois seules actions qui créent, déplacent ou annulent une leçon. Tout le reste du domaine pédagogique
    /// (bilan, fin de leçon, signalement, examen, cours) garde sa propre présentation.
    private static func planningKind(of kind: SchoolCommandKind) -> SchoolPendingPlanningMarker.Kind? {
        switch kind {
        case .createLesson: .creation
        case .moveLesson: .move
        case .cancelLesson: .cancellation
        default: nil
        }
    }
}
