import Foundation

/// Intention locale de compte ; `id` sert seulement à reconnaître une réponse locale.
/// Il n'est jamais envoyé comme clé d'idempotence à l'API du profil.
struct SchoolSelfProfileIntent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case fields, photo }
    let id: UUID
    let kind: Kind
    var base: SchoolSelfProfile
    let fields: SchoolSelfProfile?
    let jpeg: Data?

    var edit: SchoolSelfProfileEdit? { fields.map(SchoolSelfProfileEdit.init) }
    var photoChoice: SchoolSelfPhotoIntent? {
        guard kind == .photo else { return nil }
        return jpeg.map(SchoolSelfPhotoIntent.replace) ?? .remove
    }

    static func projecting(_ edit: SchoolSelfProfileEdit, on base: SchoolSelfProfile) -> SchoolSelfProfile {
        SchoolSelfProfile(personId: base.personId, displayName: edit.displayName,
            firstName: edit.firstName, lastName: edit.lastName, contactPhone: edit.contactPhone,
            contactEmail: edit.contactEmail, birthDate: edit.birthDate, postalAddress: edit.postalAddress,
            photoVersion: base.photoVersion, photoGeneration: base.photoGeneration, version: base.version)
    }

    func baseStillMatches(_ profile: SchoolSelfProfile) -> Bool {
        switch kind {
        case .fields: SchoolSelfProfileEdit(base) == SchoolSelfProfileEdit(profile)
        case .photo: base.hasSamePhotoState(as: profile)
        }
    }
}

struct SchoolSelfProfileIntents: Codable, Equatable, Sendable {
    var fields: SchoolSelfProfileIntent?
    var photo: SchoolSelfProfileIntent?
    /// La requête effectivement remise au transport reste distincte du dernier choix.
    var attempted: SchoolSelfProfileIntent?
    var isEmpty: Bool { fields == nil && photo == nil && attempted == nil }

    func validate(personID: UUID) throws {
        guard fields?.kind != .photo, photo?.kind != .fields else { throw SchoolConfigurationFailure.storage }
        for intent in [fields, photo, attempted].compactMap({ $0 }) {
            guard intent.base.personId == personID, intent.base.version > 0,
                  intent.jpeg.map({ $0.count <= 262_144 }) ?? true else { throw SchoolConfigurationFailure.storage }
            switch intent.kind {
            case .fields:
                guard intent.fields?.personId == personID, intent.jpeg == nil else { throw SchoolConfigurationFailure.storage }
            case .photo:
                guard intent.fields == nil else { throw SchoolConfigurationFailure.storage }
            }
        }
    }
}

@MainActor protocol SchoolSelfProfileIntentStore: AnyObject {
    func read(scope: AccountIntentScope) throws -> SchoolSelfProfileIntents?
    func save(_ value: SchoolSelfProfileIntents, scope: AccountIntentScope) throws
}

@MainActor final class EncryptedSchoolSelfProfileIntentStore: SchoolSelfProfileIntentStore {
    private let store: EncryptedAccountIntentStore<SchoolSelfProfileIntents>
    init(directory: URL? = nil, keyData: Data? = nil) {
        store = EncryptedAccountIntentStore(purpose: "self-profile-v1", directory: directory, keyData: keyData)
    }
    func read(scope: AccountIntentScope) throws -> SchoolSelfProfileIntents? {
        let value = try store.read(for: scope)
        try value?.validate(personID: scope.personID)
        return value
    }
    func save(_ value: SchoolSelfProfileIntents, scope: AccountIntentScope) throws {
        try value.validate(personID: scope.personID)
        if value.isEmpty { try store.remove(for: scope) }
        else { try store.save(value, for: scope) }
    }
}

/// Champs de l'accueil guidé, tels que la personne les a saisis. Aucune condition, aucun consentement,
/// aucune autorisation n'y figure : une saisie reprise ne peut donc jamais valoir acceptation.
struct SchoolOnboardingDraftFields: Codable, Equatable, Sendable {
    var firstName = ""
    var lastName = ""
    var birthDate = ""
    var contactEmail = ""
    var contactPhone = ""
    var hasAddress = false
    var address = SchoolPostalAddress(line1: "", line2: nil, postalCode: "", locality: "", countryCode: "")

    init() {}
    init(_ draft: SchoolProfileDraft) {
        firstName = draft.firstName; lastName = draft.lastName; birthDate = draft.birthDate
        contactEmail = draft.contactEmail; contactPhone = draft.contactPhone
        hasAddress = draft.hasAddress; address = draft.address
    }

    /// Seuls les champs que la personne a réellement changés depuis la base sont réappliqués : une valeur
    /// non touchée vient toujours de la dernière lecture du serveur, jamais d'un ancien brouillon.
    func applying(to value: SchoolProfileDraft, base: SchoolOnboardingDraftFields,
                  allowed: Set<SchoolProfileField>) -> SchoolProfileDraft {
        var draft = value
        if allowed.contains(.firstName), firstName != base.firstName { draft.firstName = firstName }
        if allowed.contains(.lastName), lastName != base.lastName { draft.lastName = lastName }
        if allowed.contains(.birthDate), birthDate != base.birthDate { draft.birthDate = birthDate }
        if allowed.contains(.contactEmail), contactEmail != base.contactEmail { draft.contactEmail = contactEmail }
        if allowed.contains(.contactPhone), contactPhone != base.contactPhone { draft.contactPhone = contactPhone }
        if allowed.contains(.postalAddress), hasAddress != base.hasAddress || address != base.address {
            draft.hasAddress = hasAddress; draft.address = address
        }
        return draft
    }
}

/// Brouillon de l'accueil guidé conservé dans le coffre chiffré du compte et de l'école.
/// L'étape est celle atteinte localement : elle se lit toujours à part de l'étape confirmée par l'école.
struct SchoolOnboardingDraft: Codable, Equatable, Sendable {
    let onboardingID: UUID
    /// Version de l'accueil lue quand le brouillon a été écrit. Une autre version signifie que l'école a
    /// avancé depuis : le brouillon ne se réapplique pas et rien n'est inventé.
    let version: Int
    let base: SchoolOnboardingDraftFields
    let edited: SchoolOnboardingDraftFields
    let step: SchoolOnboardingStep
    let savedAt: Date

    func validate() throws {
        guard version > 0 else { throw SchoolConfigurationFailure.storage }
    }
}

@MainActor protocol SchoolOnboardingDraftStore: AnyObject {
    func read(scope: SchoolCommandScope, kind: SchoolOnboardingKind) throws -> SchoolOnboardingDraft?
    func save(_ value: SchoolOnboardingDraft, scope: SchoolCommandScope, kind: SchoolOnboardingKind) throws
    func remove(scope: SchoolCommandScope, kind: SchoolOnboardingKind, discardingUnreadable: Bool) throws
}

/// Un seul brouillon par compte, école, adhésion, époque et nature d'accueil : le coffre générique
/// `EncryptedAccountIntentStore` porte déjà le chiffrement, la portée du compte et l'interdiction du clair.
@MainActor final class EncryptedSchoolOnboardingDraftStore: SchoolOnboardingDraftStore {
    private let directory: URL?
    private let keyData: Data?
    init(directory: URL? = nil, keyData: Data? = nil) { self.directory = directory; self.keyData = keyData }

    private func store(_ scope: SchoolCommandScope, _ kind: SchoolOnboardingKind) -> EncryptedAccountIntentStore<SchoolOnboardingDraft> {
        EncryptedAccountIntentStore(purpose: "onboarding-draft-v1|\(scope.schoolID)|\(scope.membershipID)|\(scope.accessEpoch)|\(kind.rawValue)",
            directory: directory, keyData: keyData)
    }
    private func account(_ scope: SchoolCommandScope) -> AccountIntentScope {
        AccountIntentScope(personID: scope.personID, apiBaseURL: scope.apiBaseURL)
    }
    func read(scope: SchoolCommandScope, kind: SchoolOnboardingKind) throws -> SchoolOnboardingDraft? {
        guard let value = try store(scope, kind).read(for: account(scope)) else { return nil }
        try value.validate()
        return value
    }
    func save(_ value: SchoolOnboardingDraft, scope: SchoolCommandScope, kind: SchoolOnboardingKind) throws {
        try value.validate()
        try store(scope, kind).save(value, for: account(scope))
    }
    func remove(scope: SchoolCommandScope, kind: SchoolOnboardingKind, discardingUnreadable: Bool) throws {
        try store(scope, kind).remove(for: account(scope), discardingUnreadable: discardingUnreadable)
    }
}
