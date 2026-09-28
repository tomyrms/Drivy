import Foundation

enum SchoolProfileField: String, Codable, Sendable, CaseIterable, Identifiable {
    case firstName, lastName, birthDate, postalAddress, contactEmail, contactPhone, profilePhotoDocumentId
    var id: String { rawValue }
    var label: String {
        switch self {
        case .firstName: "Prénom"
        case .lastName: "Nom"
        case .birthDate: "Date de naissance"
        case .postalAddress: "Adresse postale"
        case .contactEmail: "E-mail"
        case .contactPhone: "Téléphone"
        case .profilePhotoDocumentId: "Photo de profil"
        }
    }
    var isName: Bool { self == .firstName || self == .lastName }
    var purposes: [SchoolProfilePurpose] {
        switch self {
        case .firstName, .lastName: [.identification]
        case .birthDate: [.courseEligibility, .certificate]
        case .postalAddress: [.postalContact, .certificate]
        case .contactEmail, .contactPhone: [.lessonContact]
        case .profilePhotoDocumentId: [.personalisation]
        }
    }
}

enum SchoolProfileRequirement: String, Codable, Sendable, CaseIterable {
    case required = "REQUIRED", conditional = "CONDITIONAL", optional = "OPTIONAL"
    var label: String {
        switch self { case .required: "Requis"; case .conditional: "Selon la situation"; case .optional: "Facultatif" }
    }
}
enum SchoolProfileStage: String, Codable, Sendable, CaseIterable {
    case join = "JOIN", beforeLesson = "BEFORE_LESSON", beforeCourse = "BEFORE_COURSE", optional = "OPTIONAL"
    var label: String {
        switch self {
        case .join: "À l’entrée"
        case .beforeLesson: "Avant une leçon"
        case .beforeCourse: "Avant un cours"
        case .optional: "Facultatif"
        }
    }
}
enum SchoolProfilePurpose: String, Codable, Sendable, CaseIterable {
    case identification = "IDENTIFICATION", lessonContact = "LESSON_CONTACT", courseEligibility = "COURSE_ELIGIBILITY"
    case certificate = "CERTIFICATE", postalContact = "POSTAL_CONTACT", personalisation = "PERSONALISATION"
    var label: String {
        switch self {
        case .identification: "Identifier la personne"
        case .lessonContact: "Contacter pour une leçon"
        case .courseEligibility: "Vérifier les prérequis d’un cours"
        case .certificate: "Établir une attestation"
        case .postalContact: "Contacter par courrier"
        case .personalisation: "Personnaliser le profil"
        }
    }
}
struct SchoolProfileRule: Codable, Sendable, Equatable, Identifiable {
    var field: SchoolProfileField
    var requirement: SchoolProfileRequirement
    var stage: SchoolProfileStage
    var purposeCode: SchoolProfilePurpose
    var explanation: String
    var id: SchoolProfileField { field }
    var isValid: Bool {
        guard !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              explanation.unicodeScalars.count <= 1000 else { return false }
        if field.isName { return requirement == .required && stage == .join && purposeCode == .identification }
        if field == .profilePhotoDocumentId { return requirement == .optional && stage == .optional && purposeCode == .personalisation }
        guard field.purposes.contains(purposeCode) else { return false }
        if requirement == .optional { return stage == .optional }
        if requirement == .conditional { return stage == .beforeCourse }
        return stage == .beforeLesson || stage == .beforeCourse
    }
}
struct SchoolProfilePolicy: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let status: String
    let effectiveFrom: String
    let fields: [SchoolProfileRule]
    let noticeVersionId: UUID
    let approvedByMembershipId: UUID?
}
struct SchoolPostalAddress: Codable, Sendable, Equatable {
    var line1: String
    var line2: String?
    var postalCode: String
    var locality: String
    var countryCode: String
    private enum CodingKeys: String, CodingKey { case line1, line2, postalCode, locality, countryCode }
    func encode(to encoder: any Encoder) throws {
        var value = encoder.container(keyedBy: CodingKeys.self)
        try value.encode(line1, forKey: .line1)
        if let line2 { try value.encode(line2, forKey: .line2) }
        else { try value.encodeNil(forKey: .line2) }
        try value.encode(postalCode, forKey: .postalCode)
        try value.encode(locality, forKey: .locality)
        try value.encode(countryCode, forKey: .countryCode)
    }
    var isValid: Bool {
        !line1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && line1.unicodeScalars.count <= 200
            && (line2?.unicodeScalars.count ?? 0) <= 200 && !postalCode.isEmpty && postalCode.unicodeScalars.count <= 20
            && !locality.isEmpty && locality.unicodeScalars.count <= 150
            && countryCode.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil
    }
}
struct SchoolAdministrativeProfile: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let learnerId: UUID
    let firstName: String?
    let lastName: String?
    let birthDate: String?
    let postalAddress: SchoolPostalAddress?
    let contactEmail: String?
    let contactPhone: String?
    let profilePhotoDocumentId: UUID?
    let updatedAt: String
    let enteredByMembershipId: UUID
    let entrySource: String
    let policyVersionId: UUID
}
enum SchoolOnboardingKind: String, Codable, Sendable, CaseIterable { case student = "STUDENT", staff = "STAFF" }
enum SchoolOnboardingStep: String, Codable, Sendable, CaseIterable {
    case identity = "IDENTITY", formations = "FORMATIONS", information = "INFORMATION", device = "DEVICE", review = "REVIEW"
    var label: String {
        switch self {
        case .identity: "Identité"
        case .formations: "Formations"
        case .information: "Informations"
        case .device: "Appareil"
        case .review: "Vérification"
        }
    }
}
struct SchoolOnboarding: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let personId: UUID
    let membershipId: UUID
    let kind: SchoolOnboardingKind
    let status: String
    let currentStep: SchoolOnboardingStep
    let skippedOptionalSteps: [String]
    let policyVersionId: UUID
    let lastSavedAt: String
    let pendingActions: [SchoolActionBlocker]
    let returnDestinationKey: String?
    let returnResourceId: UUID?
}
struct SchoolLearnerReadiness: Codable, Sendable, Equatable {
    let learnerId: UUID
    let action: String
    let resourceId: UUID?
    let ready: Bool
    let blockers: [SchoolActionBlocker]
    let policyVersionId: UUID
    let computedAt: String
}
struct SchoolProfilePolicyCommand: Encodable, Sendable {
    let operationId: UUID
    let effectiveFrom: String
    let fields: [SchoolProfileRule]
    let noticeVersionId: UUID
    let impactAcknowledged: Bool
}
struct SchoolEmptyProfileCommand: Codable, Sendable { let operationId: UUID }
enum SchoolProfileValue: Codable, Sendable, Equatable {
    case text(String), address(SchoolPostalAddress), null
    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let text = try? value.decode(String.self) { self = .text(text) }
        else { self = .address(try value.decode(SchoolPostalAddress.self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .text(let text): try value.encode(text)
        case .address(let address): try value.encode(address)
        }
    }
}
struct SchoolOnboardingCommand: Encodable, Sendable {
    let operationId: UUID
    let kind: SchoolOnboardingKind
    let currentStep: SchoolOnboardingStep
    let skippedOptionalSteps: [String]
    let policyVersionId: UUID
}
struct SchoolCompleteOnboardingCommand: Encodable, Sendable {
    let operationId: UUID
    let kind: SchoolOnboardingKind
    let policyVersionId: UUID
}
enum SchoolProfileResult: Sendable {
    case policy(SchoolProfilePolicy), profile(SchoolAdministrativeProfile), onboarding(SchoolOnboarding)
    var id: UUID {
        switch self { case .policy(let v): v.id; case .profile(let v): v.id; case .onboarding(let v): v.id }
    }
    var version: Int {
        switch self { case .policy(let v): v.version; case .profile(let v): v.version; case .onboarding(let v): v.version }
    }
    var schoolID: UUID {
        switch self { case .policy(let v): v.schoolId; case .profile(let v): v.schoolId; case .onboarding(let v): v.schoolId }
    }
}
@MainActor
protocol SchoolProfileAPI: AnyObject {
    func school(id: UUID) async throws -> SchoolDetails
    func policies(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolProfilePolicy>
    func notice(schoolID: UUID, id: UUID?) async throws -> SchoolDataPolicy
    func profile(schoolID: UUID, learnerID: UUID) async throws -> SchoolAdministrativeProfile
    func readiness(schoolID: UUID, learnerID: UUID, action: String) async throws -> SchoolLearnerReadiness
    func onboarding(schoolID: UUID, kind: SchoolOnboardingKind) async throws -> SchoolOnboarding
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt
    func send(_ command: PendingSchoolCommand) async throws -> SchoolProfileResult
}
enum SchoolProfileFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, notFound, unavailable, invalidResponse, notInitialized, operationUnknown, pendingCommand, conflict
    case rejected(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Reconnectez-vous pour continuer. La demande en attente reste conservée."
        case .forbidden: "Vos droits ne permettent plus cet accès."
        case .notFound: "Ce dossier n’est plus disponible dans votre périmètre d’accès."
        case .unavailable: "L’école est momentanément inaccessible. Une demande déjà envoyée reste conservée jusqu’à confirmation."
        case .invalidResponse: "La réponse de l’école ne peut pas être vérifiée."
        case .notInitialized: "L’école doit publier sa politique de champs avant de compléter les profils."
        case .operationUnknown: "Le résultat n’est pas confirmé. Conservez cette référence et vérifiez à nouveau."
        case .pendingCommand: "Une demande reste à vérifier avant une autre modification."
        case .conflict: "Ce dossier ou sa politique a changé. Rechargez les informations et relisez vos modifications."
        case .rejected(let message): message
        }
    }
    var permitsFreshCorrection: Bool {
        switch self { case .conflict, .rejected, .notInitialized: true; default: false }
    }
}
