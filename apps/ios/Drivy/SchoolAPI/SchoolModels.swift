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
    /// Projection indicative de l’école ; le démarrage recontrôle toujours l’affectation.
    var startNowBlockerCode: String? = nil
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
        startNowBlockerCode = try c.decodeIfPresent(String.self, forKey: .startNowBlockerCode)
    }
}

@MainActor
protocol AccessTokenSource: AnyObject {
    func accessToken() async throws -> String
    /// L’API a répondu 401 à ce jeton : le prochain `accessToken()` doit le renouveler auprès du fournisseur,
    /// même si l’appareil le croit encore valable. `true` seulement si un autre jeton peut être attendu ;
    /// une source qui ne renouvelle rien répond `false` et le 401 reste une session expirée.
    func invalidateAccessToken(_ token: String) async -> Bool
}

extension AccessTokenSource {
    func invalidateAccessToken(_ token: String) async -> Bool { false }
}

@MainActor
protocol SchoolAPI: AnyObject {
    func me() async throws -> SchoolPerson
    func school(id: UUID) async throws -> SchoolDetails
    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner>
    /// Une page des dossiers actifs auxquels manque une information requise (filtre serveur `requiresAction`),
    /// combinable avec la recherche ; le serveur relit la portée du compte comme pour la liste.
    func incompleteLearners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner>
    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining>
    func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining
    /// Le dossier de l’élève connecté, archivé compris : une formation terminée garde ses bilans et ses trajets.
    func ownLearners(schoolID: UUID) async throws -> SchoolPage<SchoolLearner>
    /// Les dossiers actifs de toute l’école auxquels manque une information requise (filtre `requiresAction`),
    /// toutes pages lues ; `nil` quand ce client ne sait pas les lire.
    func learnersToComplete(schoolID: UUID) async throws -> [SchoolLearner]?
    /// Profil personnel complet (`GET /v1/me/profile`).
    func selfProfile() async throws -> SchoolSelfProfile
    /// Enregistre le compte Drivy : nom affiché, prénom, nom, contact, naissance et adresse (`PATCH /v1/me/profile`).
    /// `version` : celle de la personne lue par `me()` ou par `selfProfile()`.
    func saveSelfProfile(_ edit: SchoolSelfProfileEdit, version: Int) async throws -> SchoolSelfProfile
    /// Remplace la photo (JPEG carré) ; `nil` la retire.
    func setSelfPhoto(_ jpeg: Data?, version: Int) async throws -> SchoolSelfProfile
    /// Photo d’une personne visible par le compte connecté ; `nil` si elle n’en a pas ou n’est pas visible.
    func personPhoto(personID: UUID) async throws -> Data?
}

struct SchoolProfilePhoto: Sendable, Equatable {
    let version: Int
    let data: Data
}

struct SchoolSelfProfileEdit: Encodable, Sendable, Equatable {
    var displayName: String
    var firstName: String
    var lastName: String
    var contactPhone: String
    var contactEmail: String = ""
    /// Date civile `yyyy-MM-dd`, ou vide.
    var birthDate: String = ""
    var postalAddress: SchoolPostalAddress? = nil

    private enum CodingKeys: String, CodingKey { case displayName, firstName, lastName, contactPhone, contactEmail, birthDate, postalAddress }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName, forKey: .lastName)
        try c.encode(contactPhone, forKey: .contactPhone)
        try c.encode(contactEmail, forKey: .contactEmail)
        // Vide : effacé (null), jamais une chaîne vide que le serveur refuserait comme date.
        if birthDate.isEmpty { try c.encodeNil(forKey: .birthDate) } else { try c.encode(birthDate, forKey: .birthDate) }
        if let postalAddress { try c.encode(postalAddress, forKey: .postalAddress) } else { try c.encodeNil(forKey: .postalAddress) }
    }

    init(displayName: String, firstName: String, lastName: String, contactPhone: String,
         contactEmail: String = "", birthDate: String = "", postalAddress: SchoolPostalAddress? = nil) {
        self.displayName = displayName; self.firstName = firstName; self.lastName = lastName; self.contactPhone = contactPhone
        self.contactEmail = contactEmail; self.birthDate = birthDate; self.postalAddress = postalAddress
    }

    init(_ profile: SchoolSelfProfile) {
        self.init(displayName: profile.displayName, firstName: profile.firstName ?? "", lastName: profile.lastName ?? "",
            contactPhone: profile.contactPhone ?? "", contactEmail: profile.contactEmail ?? "", birthDate: profile.birthDate ?? "",
            postalAddress: profile.postalAddress)
    }
}

/// Ce que l’école renvoie du profil : la version de la personne et, pour la photo, sa version (`nil` : initiales).
struct SchoolSelfProfile: Codable, Sendable, Equatable {
    let personId: UUID
    let displayName: String
    var firstName: String? = nil
    var lastName: String? = nil
    var contactPhone: String? = nil
    var contactEmail: String? = nil
    var birthDate: String? = nil
    var postalAddress: SchoolPostalAddress? = nil
    var photoVersion: Int? = nil
    let version: Int
}

enum SchoolSelfProfileFailure: Error, LocalizedError, Equatable {
    case changed, invalidName, invalidPhoto, unsupported
    var errorDescription: String? {
        switch self {
        case .changed: "Ton profil a changé sur un autre appareil. Il vient d’être relu : vérifie puis enregistre."
        case .invalidName: "Une information ne peut pas être enregistrée. Vérifie le nom et le numéro de téléphone."
        case .invalidPhoto: "Cette photo ne peut pas être utilisée. Choisis-en une autre."
        case .unsupported: "Ton école ne permet pas encore de modifier ton profil depuis l’app."
        }
    }
}

extension SchoolAPI {
    func ownLearners(schoolID: UUID) async throws -> SchoolPage<SchoolLearner> {
        try await learners(schoolID: schoolID, query: "", cursor: nil)
    }
    func learnersToComplete(schoolID: UUID) async throws -> [SchoolLearner]? { nil }
    /// Sans filtre serveur, la page lue est filtrée sur place : mêmes curseurs, mêmes lignes que la liste.
    func incompleteLearners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> {
        let page = try await learners(schoolID: schoolID, query: query, cursor: cursor)
        return SchoolPage(items: page.items.filter(SchoolRequiredActionRules.profileIsIncomplete), nextCursor: page.nextCursor)
    }
    func selfProfile() async throws -> SchoolSelfProfile { throw SchoolSelfProfileFailure.unsupported }
    func saveSelfProfile(_ edit: SchoolSelfProfileEdit, version: Int) async throws -> SchoolSelfProfile { throw SchoolSelfProfileFailure.unsupported }
    func setSelfPhoto(_ jpeg: Data?, version: Int) async throws -> SchoolSelfProfile { throw SchoolSelfProfileFailure.unsupported }
    func personPhoto(personID: UUID) async throws -> Data? { nil }
}

enum SchoolAPIError: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, identityNotLinked, notFound, invalidResponse
    case unavailable, invalidConfiguration, invalidCursor, tooLarge

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Ta session a expiré. Reconnecte-toi pour continuer."
        case .forbidden: "Tu n’as plus accès à cet espace. Actualise tes écoles."
        case .identityNotLinked: "Ce compte n’a pas encore accès à Drivy. Contacte ton école."
        case .notFound: "Ce dossier n’est plus disponible dans ton espace."
        case .invalidResponse: "Les données reçues ne peuvent pas être affichées. Réessaie."
        case .unavailable: "Connexion au serveur impossible. Vérifie ta connexion et réessaie."
        case .invalidConfiguration: "La connexion à ton école n’est pas encore configurée pour cette version."
        case .invalidCursor: "Cette liste a changé. Actualise-la pour continuer."
        case .tooLarge: "La réponse du serveur dépasse la taille prévue. Réessaie."
        }
    }
}
