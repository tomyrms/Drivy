import Foundation

// Adaptateurs limités aux six lectures G1A du contrat canonique OpenAPI 3.11.0.
// Les codes inconnus restent des codes inconnus ; ils n'accordent aucun droit local.
struct SchoolPerson: Codable, Sendable, Equatable, Identifiable {
    let personId: UUID
    let version: Int
    let displayName: String
    let locale: String
    let memberships: [SchoolMembership]
    var id: UUID { personId }
}

struct SchoolMembership: Codable, Sendable, Equatable, Identifiable {
    let membershipId: UUID
    let schoolId: UUID
    let schoolName: String
    let roles: [String]
    let grants: [String]
    let accessEpoch: Int
    var id: UUID { membershipId }
}

struct SchoolModules: Codable, Sendable, Equatable {
    let gpsEnabled: Bool
    let packsEnabled: Bool
    let collectiveCoursesEnabled: Bool
    let courseOffersVisibleByDefault: Bool
}

struct SchoolDetails: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let name: String
    let timeZone: String
    let status: String
    let contactEmail: String
    let contactPhone: String?
    let logoAssetId: UUID?
    let modules: SchoolModules
    let configurationVersion: Int
}

struct SchoolLearner: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let personId: UUID
    let version: Int
    let displayName: String
    let contactEmail: String?
    let contactPhone: String?
    let archivedAt: String?
    let profileReadiness: String?
    let profilePhotoDocumentId: UUID?
}

struct SchoolTraining: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let learnerId: UUID
    let offeringId: UUID
    let version: Int
    let categoryCode: String
    let status: String
    // Dates civiles, jamais interprétées comme des instants UTC.
    let startedOn: String?
    let closedOn: String?
}

struct SchoolPage<Item: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    let items: [Item]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey { case items, nextCursor }
    init(items: [Item], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decode([Item].self, forKey: .items)
        nextCursor = try values.decode(String?.self, forKey: .nextCursor)
        guard items.count <= 100, nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 6_000 }) ?? true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Page G1A invalide."))
        }
    }
}

extension SchoolDetails {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schoolId = try c.decode(UUID.self, forKey: .schoolId)
        version = try c.decode(Int.self, forKey: .version)
        name = try c.decode(String.self, forKey: .name)
        timeZone = try c.decode(String.self, forKey: .timeZone)
        status = try c.decode(String.self, forKey: .status)
        contactEmail = try c.decode(String.self, forKey: .contactEmail)
        contactPhone = try c.decode(String?.self, forKey: .contactPhone)
        logoAssetId = try c.decode(UUID?.self, forKey: .logoAssetId)
        modules = try c.decode(SchoolModules.self, forKey: .modules)
        configurationVersion = try c.decode(Int.self, forKey: .configurationVersion)
    }
}

extension SchoolLearner {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schoolId = try c.decode(UUID.self, forKey: .schoolId)
        personId = try c.decode(UUID.self, forKey: .personId)
        version = try c.decode(Int.self, forKey: .version)
        displayName = try c.decode(String.self, forKey: .displayName)
        contactEmail = try c.decode(String?.self, forKey: .contactEmail)
        contactPhone = try c.decode(String?.self, forKey: .contactPhone)
        archivedAt = try c.decode(String?.self, forKey: .archivedAt)
        profileReadiness = try c.decodeIfPresent(String.self, forKey: .profileReadiness)
        profilePhotoDocumentId = try c.decodeIfPresent(UUID.self, forKey: .profilePhotoDocumentId)
    }
}

extension SchoolTraining {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schoolId = try c.decode(UUID.self, forKey: .schoolId)
        learnerId = try c.decode(UUID.self, forKey: .learnerId)
        offeringId = try c.decode(UUID.self, forKey: .offeringId)
        version = try c.decode(Int.self, forKey: .version)
        categoryCode = try c.decode(String.self, forKey: .categoryCode)
        status = try c.decode(String.self, forKey: .status)
        startedOn = try c.decode(String?.self, forKey: .startedOn)
        closedOn = try c.decode(String?.self, forKey: .closedOn)
    }
}

@MainActor
protocol AccessTokenSource: AnyObject {
    func accessToken() async throws -> String
}

@MainActor
protocol SchoolAPI: AnyObject {
    func me() async throws -> SchoolPerson
    func school(id: UUID) async throws -> SchoolDetails
    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner>
    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining>
    func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining
}

enum SchoolAPIError: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, identityNotLinked, notFound, invalidResponse
    case unavailable, invalidConfiguration, invalidCursor, tooLarge

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Votre session a expiré. Reconnectez-vous pour continuer."
        case .forbidden: "Vous n’avez plus accès à cet espace. Actualisez vos écoles."
        case .identityNotLinked: "Ce compte n’a pas encore accès à Drivy. Contactez votre école."
        case .notFound: "Ce dossier n’est plus disponible dans votre espace."
        case .invalidResponse: "Les données reçues ne peuvent pas être affichées. Réessayez."
        case .unavailable: "Connexion au serveur impossible. Vérifiez votre connexion et réessayez."
        case .invalidConfiguration: "La connexion à votre école n’est pas encore configurée pour cette version."
        case .invalidCursor: "Cette liste a changé. Actualisez-la pour continuer."
        case .tooLarge: "La réponse du serveur dépasse la taille prévue. Réessayez."
        }
    }
}
