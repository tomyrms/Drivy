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
        schoolStatus == "ACTIVE" && (roles.contains("INSTRUCTOR") || roles.contains("LEARNER"))
    }
}
