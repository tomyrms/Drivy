import Foundation

/// L'ouverture d'une école précède les onglets terrain. Les rôles ne remplacent jamais son état serveur.
enum SchoolEntryDestination: Equatable {
    case chooseSchool, loading, prepareSchool, waitingForActivation, management, instructor, learner, archived, unavailable

    static func resolve(schoolStatus: String?, roles: [String]?) -> Self {
        guard let roles else { return .chooseSchool }
        guard let schoolStatus else { return .loading }
        switch schoolStatus {
        case "DRAFT": return roles.contains("ADMIN") ? .prepareSchool : .waitingForActivation
        case "ARCHIVED": return .archived
        case "ACTIVE":
            if roles.contains("INSTRUCTOR") { return .instructor }
            if roles.contains("LEARNER") { return .learner }
            return roles.contains("ADMIN") ? .management : .unavailable
        default: return .unavailable
        }
    }

    static func allowsPersonalOnboarding(schoolStatus: String?, roles: [String]) -> Bool {
        personalOnboardingKind(schoolStatus: schoolStatus, roles: roles) != nil
    }

    /// L’accueil suit l’usage ouvert par les onglets, y compris avec plusieurs rôles.
    /// Le moniteur n’a pas besoin de retrouver son propre dossier dans l’annuaire des élèves.
    static func personalOnboardingKind(schoolStatus: String?, roles: [String]) -> SchoolOnboardingKind? {
        switch resolve(schoolStatus: schoolStatus, roles: roles) {
        case .instructor: .staff
        case .learner: .student
        default: nil
        }
    }
}
