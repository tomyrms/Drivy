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

/// How the invitation reaches the person: an e-mail link, or a single-use code handed over in person.
enum SchoolInvitationDelivery: String, Codable, Sendable { case email = "EMAIL", code = "CODE" }

struct SchoolInvitation: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    /// Null for a code invitation.
    let maskedEmail: String?
    let roles: [SchoolInvitationRole]
    let status: SchoolInvitationStatus
    let expiresAt: String
    var delivery: SchoolInvitationDelivery = .email
    /// Present only in the creation and resend answers of a code invitation. Never kept in a list.
    var code: String? = nil
    /// Training carried by a learner invitation, when the server projects it.
    var training: SchoolInvitationTraining? = nil
    var trainings: [SchoolInvitationTraining]? = nil
    var trainingCategoryCode: String? = nil

    var roleLabel: String { roles.map(\.label).joined(separator: ", ") }
    var isCode: Bool { delivery == .code }
    /// The same projection without its one-time code.
    var withoutCode: SchoolInvitation { var copy = self; copy.code = nil; return copy }

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

extension SchoolInvitation {
    // Keys are the ones synthesized for Encodable, as for SchoolDetails.
    // A server that predates codes sends neither `delivery` nor `code`: an e-mail invitation.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        schoolId = try values.decode(UUID.self, forKey: .schoolId)
        version = try values.decode(Int.self, forKey: .version)
        maskedEmail = try values.decodeIfPresent(String.self, forKey: .maskedEmail)
        roles = try values.decode([SchoolInvitationRole].self, forKey: .roles)
        status = try values.decode(SchoolInvitationStatus.self, forKey: .status)
        expiresAt = try values.decode(String.self, forKey: .expiresAt)
        delivery = try values.decodeIfPresent(SchoolInvitationDelivery.self, forKey: .delivery) ?? .email
        code = try values.decodeIfPresent(String.self, forKey: .code)
        training = try values.decodeIfPresent(SchoolInvitationTraining.self, forKey: .training)
        trainings = try values.decodeIfPresent([SchoolInvitationTraining].self, forKey: .trainings)
        trainingCategoryCode = try values.decodeIfPresent(String.self, forKey: .trainingCategoryCode)
    }
}

/// Single-use invitation code: 8 characters without look-alikes (no I, O, 0, 1), shown `XXXX-XXXX`.
enum SchoolInvitationCode {
    static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 8

    /// Uppercased, spaces and dashes removed; nil unless exactly eight characters of the alphabet.
    static func normalized(_ input: String) -> String? {
        let value = String(input.uppercased().filter { !$0.isWhitespace && !Self.dashes.contains($0) })
        guard value.count == length, value.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return value
    }

    /// Formatting while typing: uppercase letters and digits only, eight at most, a dash after the
    /// fourth once a fifth follows, so deleting back over the dash never gets stuck.
    static func formatted(_ input: String) -> String {
        let characters = Array(input.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length))
        guard characters.count > 4 else { return String(characters) }
        return String(characters.prefix(4)) + "-" + String(characters.dropFirst(4))
    }

    /// `K7Q4MX2P` or `k7q4-mx2p` → `K7Q4-MX2P`; nil for anything that is not a code.
    static func display(_ input: String) -> String? {
        normalized(input).map { String($0.prefix(4)) + "-" + String($0.dropFirst(4)) }
    }

    /// Eight typed characters that can never form a code: a look-alike (I, O, 0, 1) was typed.
    static func isMistyped(_ input: String) -> Bool {
        let typed = formatted(input).filter { $0 != "-" }
        return typed.count == length && normalized(typed) == nil
    }

    private static let dashes: Set<Character> = ["-", "‐", "‑", "–", "—"]
}

/// Une invitation d'élève peut porter sa formation : elle s'ouvre, avec son moniteur, à l'acceptation.
struct SchoolInvitationTraining: Codable, Sendable, Equatable {
    let offeringId: UUID
    let instructorMembershipId: UUID
}

/// Creation body. An e-mail invitation carries `email`; a code invitation carries `delivery: CODE`
/// and no address. Absent keys are omitted, so an e-mail command keeps its historical bytes.
struct SchoolInviteCommand: Codable, Sendable, Equatable {
    let operationId: UUID
    var email: String? = nil
    var delivery: SchoolInvitationDelivery? = nil
    let roles: [SchoolInvitationRole]
    var training: SchoolInvitationTraining? = nil
    var trainings: [SchoolInvitationTraining]? = nil
}

struct SchoolInvitationInstructor: Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
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
    case trainingInvalid

    // Only a brand-new UUID's first response may release a rejected command.
    var permitsCorrectionOfFreshRequest: Bool {
        switch self {
        case .schoolInactive, .policyRequired, .alreadyMember, .alreadyInvited, .invitationUsed, .invitationRevoked, .conflict, .rejected,
             .trainingInvalid, .deliveryUnavailable: true
        default: false
        }
    }
    /// A refusal that proves the command never took effect, even for a resent operation: the
    /// school answers a replay of a committed operation with its stored result, before this check.
    /// `rejected` (400 INVALID_REQUEST, 428) est rendu avant toute écriture, à l’entrée de la requête : la même
    /// demande échouerait à chaque renvoi, elle ne doit donc pas rester en file.
    var provesNotCommitted: Bool { self == .deliveryUnavailable || self == .rejected }
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Ta session a expiré. Connecte-toi à nouveau."
        case .forbidden: "Tu n’as plus accès aux invitations de cette école."
        case .schoolInactive: "L’école doit être active pour gérer ses invitations."
        case .policyRequired: "La notice de l’école doit être adoptée avant d’inviter une personne."
        case .alreadyMember: "Cette personne appartient déjà à l’école. Aucun second dossier n’a été créé."
        case .alreadyInvited: "Une invitation existe déjà pour cette adresse. Actualise la liste avant de la renvoyer."
        case .invitationUsed: "Cette invitation a déjà été acceptée. Actualise la liste."
        case .invitationRevoked: "Cette invitation a été révoquée. Actualise la liste."
        case .conflict: "L’invitation a changé. Actualise-la avant de confirmer à nouveau."
        case .rejected: "La demande a été refusée. Vérifie l’adresse, les rôles ou le motif."
        case .invalidCursor: "La liste a changé. Actualise-la pour continuer."
        case .unavailable: "Connexion indisponible ou réponse non reçue. Aucune confirmation ne peut être donnée."
        case .deliveryUnavailable: "L’invitation par e-mail n’est pas disponible. Invite l’élève avec un code."
        case .invalidResponse: "La réponse n’a pas pu être vérifiée. Le résultat n’est pas confirmé."
        case .pendingCommand: "Une demande attend sa confirmation. Vérifie son résultat avant une autre action."
        case .operationUnknown: "Le résultat n’a pas encore pu être établi. La demande reste conservée sur cet appareil."
        case .trainingInvalid: "Cette formation n’est plus ouverte. Choisis-en une autre."
        }
    }
}

@MainActor
protocol SchoolInvitationAPI: AnyObject {
    func school(id: UUID) async throws -> SchoolDetails
    func invitations(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolInvitation>
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt
    func send(_ command: PendingSchoolCommand) async throws -> SchoolInvitation
    /// Offres ouvertes : dernière version active, référentiel et procédure adoptés.
    func trainingOfferings(schoolID: UUID) async throws -> [SchoolOffering]
    func instructors(schoolID: UUID) async throws -> [SchoolInvitationInstructor]
}
