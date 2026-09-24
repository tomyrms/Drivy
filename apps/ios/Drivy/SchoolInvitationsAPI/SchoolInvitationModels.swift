import Foundation

enum SchoolInvitationStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case pending = "PENDING", accepted = "ACCEPTED", revoked = "REVOKED", expired = "EXPIRED"

    var label: String {
        switch self {
        case .pending: "En attente"
        case .accepted: "Acceptée"
        case .revoked: "Révoquée"
        case .expired: "Expirée"
        }
    }
    var canBeManaged: Bool { self == .pending || self == .expired }
}

enum SchoolInvitationRole: String, Codable, CaseIterable, Hashable, Sendable {
    case learner = "LEARNER", instructor = "INSTRUCTOR", admin = "ADMIN"
    var label: String {
        switch self {
        case .learner: "Élève"
        case .instructor: "Moniteur"
        case .admin: "Administrateur"
        }
    }
}

struct SchoolInvitation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let maskedEmail: String
    let roles: [SchoolInvitationRole]
    let status: SchoolInvitationStatus
    let expiresAt: String

    var roleLabel: String { roles.map(\.label).joined(separator: ", ") }

    func expirationLabel(timeZone: String) -> String {
        guard let date = Self.date(expiresAt) else { return "Date indisponible" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct SchoolInviteCommand: Codable, Sendable, Equatable {
    let operationId: UUID
    let email: String
    let roles: [SchoolInvitationRole]
}

struct SchoolResendInvitationCommand: Codable, Sendable, Equatable {
    let operationId: UUID
}

struct SchoolRevokeInvitationCommand: Codable, Sendable, Equatable {
    let operationId: UUID
    let reason: String
}

enum SchoolInvitationFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, schoolInactive, policyRequired, alreadyMember, alreadyInvited, invitationUsed, invitationRevoked
    case conflict, rejected, invalidCursor, unavailable, deliveryUnavailable, invalidResponse, pendingCommand, operationUnknown

    // Only a brand-new UUID's first response may release a rejected command.
    var permitsCorrectionOfFreshRequest: Bool {
        switch self {
        case .schoolInactive, .policyRequired, .alreadyMember, .alreadyInvited, .invitationUsed, .invitationRevoked, .conflict, .rejected: true
        default: false
        }
    }
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Votre session a expiré. Connectez-vous à nouveau."
        case .forbidden: "Vous n’avez plus accès aux invitations de cette école."
        case .schoolInactive: "L’école doit être active pour gérer ses invitations."
        case .policyRequired: "La notice de l’école doit être adoptée avant d’inviter une personne."
        case .alreadyMember: "Cette personne appartient déjà à l’école. Aucun second dossier n’a été créé."
        case .alreadyInvited: "Une invitation existe déjà pour cette adresse. Actualisez la liste avant de la renvoyer."
        case .invitationUsed: "Cette invitation a déjà été acceptée. Actualisez la liste."
        case .invitationRevoked: "Cette invitation a été révoquée. Actualisez la liste."
        case .conflict: "L’invitation a changé. Actualisez-la avant de confirmer à nouveau."
        case .rejected: "La demande a été refusée. Vérifiez l’adresse, les rôles ou le motif."
        case .invalidCursor: "La liste a changé. Actualisez-la pour continuer."
        case .unavailable: "Connexion indisponible ou réponse non reçue. Aucune confirmation ne peut être donnée."
        case .deliveryUnavailable: "L’envoi des invitations n’est pas encore configuré. Votre demande reste conservée jusqu’à vérification de son résultat."
        case .invalidResponse: "La réponse n’a pas pu être vérifiée. Le résultat n’est pas confirmé."
        case .pendingCommand: "Une demande attend sa confirmation. Vérifiez son résultat avant une autre action."
        case .operationUnknown: "Le résultat n’a pas encore pu être établi. La demande reste conservée sur cet appareil."
        }
    }
}

@MainActor
protocol SchoolInvitationAPI: AnyObject {
    func school(id: UUID) async throws -> SchoolDetails
    func invitations(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolInvitation>
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt
    func send(_ command: PendingSchoolCommand) async throws -> SchoolInvitation
}
