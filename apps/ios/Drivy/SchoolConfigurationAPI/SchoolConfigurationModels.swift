import Foundation

struct SchoolActionBlocker: Codable, Sendable, Equatable {
    let code: String
    let message: String
    let field: String?
    let purpose: String?
    let resourceId: UUID?
    let destinationKey: String?
}

struct SchoolReadinessItem: Codable, Sendable, Equatable {
    let capability: String
    let ready: Bool
    let blockers: [SchoolActionBlocker]
}

struct SchoolReadiness: Codable, Sendable, Equatable {
    let schoolId: UUID
    let configurationVersion: Int
    let computedAt: String
    let capabilities: [SchoolReadinessItem]
    let activationReady: Bool
    let activationBlockers: [SchoolActionBlocker]
}

struct SchoolSetup: Codable, Sendable, Equatable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let status: String
    let currentStep: String
    let completedSteps: [String]
    let lastSavedAt: String
    let configuredByMembershipId: UUID
    let readiness: SchoolReadiness
}

struct SchoolDataPolicy: Codable, Sendable, Equatable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let status: String
    let noticeText: String
    let retentionText: String
    let contactEmail: String?
    let approvedAt: String?
    let approvedByMembershipId: UUID?
}

struct SchoolIdentityCommand: Codable, Sendable, Equatable {
    let operationId: UUID
    let name: String
    let timeZone: String
    let contactEmail: String
    let contactPhone: String?
    let impactConfirmed: Bool
}

struct SchoolSetupCommand: Codable, Sendable, Equatable {
    let operationId: UUID
    let currentStep: String
    let completedSteps: [String]
}

struct SchoolActivationCommand: Codable, Sendable, Equatable {
    let operationId: UUID
    let expectedConfigurationVersion: Int
    let reviewAcknowledged: Bool
}

struct SchoolDataPolicyCommand: Codable, Sendable, Equatable {
    let operationId: UUID
    let noticeText: String
    let retentionText: String
    let contactEmail: String
    let reviewAcknowledged: Bool
}

enum SchoolCommandResult: Sendable {
    case school(SchoolDetails)
    case setup(SchoolSetup)
    case dataPolicy(SchoolDataPolicy)
}

struct SchoolOperationReceipt: Codable, Sendable, Equatable {
    let operationId: UUID
    let commandType: String
    let resourceType: String
    let resourceId: UUID
    let committedAt: String
    let resourceVersion: Int
}

enum SchoolConfigurationFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, conflict, incomplete, rejected, unavailable, invalidResponse, storage, pendingCommand, operationUnknown

    // Usable only for the fresh operation's first emission in this process.
    // A resumed/uncertain command is never removed on an error response.
    var permitsCorrectionOfFreshRequest: Bool {
        switch self {
        case .conflict, .incomplete, .rejected: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Votre session a expiré. Connectez-vous à nouveau."
        case .forbidden: "Vous n’avez plus accès à la configuration de cette école."
        case .conflict: "La configuration a changé. Rechargez-la avant de confirmer à nouveau."
        case .incomplete: "L’école n’est pas encore prête. Vérifiez les éléments à compléter."
        case .rejected: "Cette modification a été refusée. Vérifiez les informations saisies."
        case .unavailable: "La réponse n’a pas été reçue. Vérifiez le résultat avec la même demande avant de continuer."
        case .invalidResponse: "La réponse n’a pas pu être vérifiée. La modification n’est pas confirmée."
        case .storage: "Le suivi protégé de la demande est inaccessible. Vérifiez son résultat avant une nouvelle modification."
        case .pendingCommand: "Une demande attend encore sa confirmation. Vérifiez son résultat avant une autre modification."
        case .operationUnknown: "Le résultat n’a pas encore pu être établi. La demande reste protégée sur cet appareil."
        }
    }
}

@MainActor
protocol SchoolConfigurationAPI: AnyObject {
    func school(id: UUID) async throws -> SchoolDetails
    func setup(schoolID: UUID) async throws -> SchoolSetup
    func readiness(schoolID: UUID) async throws -> SchoolReadiness
    func dataPolicy(schoolID: UUID) async throws -> SchoolDataPolicy
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt
    func send(_ command: PendingSchoolCommand) async throws -> SchoolCommandResult
}
