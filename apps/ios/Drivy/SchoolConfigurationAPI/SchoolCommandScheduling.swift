import Foundation

/// Domaines vérifiés sur les contrats actuels. Les actions sensibles restent une barrière scolaire.
/// Le domaine pédagogique reste volontairement commun : créneau, formation, bilan et observations se croisent.
enum SchoolCommandDomain: Equatable, Sendable {
    case school, invitations, teaching, planningPreferences

    func conflicts(with other: Self) -> Bool { self == .school || other == .school || self == other }
}

extension SchoolCommandKind {
    var schedulingDomain: SchoolCommandDomain {
        if self == .savePlanningDefaults { return .planningPreferences }
        if isInvitation { return .invitations }
        if isPlanning || isReport || isObservation { return .teaching }
        // Configuration, contrats, catalogue, profils et droits peuvent partager la version de l'école
        // ou modifier les prérequis des autres commandes. Aucun parallélisme supposé entre ces écritures.
        return .school
    }
}

extension PendingSchoolCommand {
    func conflicts(with other: Self) -> Bool {
        if id == other.id { return true }
        guard scope.belongsToWorkspace(other.scope) else { return false }
        // Une commande d'une ancienne époque reste à résoudre avant toute autre émission dans cette école.
        guard scope == other.scope else { return true }
        return kind.schedulingDomain.conflicts(with: other.kind.schedulingDomain)
    }
}

extension SchoolCommandOutbox {
    /// Les doubles anciens conservent leur contrat à une intention ; le coffre réel expose toute sa file.
    func pendingCommands(for scope: SchoolCommandScope) throws -> [PendingSchoolCommand] {
        try pending(for: scope).map { [$0] } ?? []
    }

    func pending(for scope: SchoolCommandScope, domain: SchoolCommandDomain) throws -> PendingSchoolCommand? {
        try pendingCommands(for: scope).first {
            $0.scope != scope || $0.kind.schedulingDomain.conflicts(with: domain)
        }
    }
}
