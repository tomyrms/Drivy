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
            photoVersion: base.photoVersion, version: base.version)
    }

    func baseStillMatches(_ profile: SchoolSelfProfile) -> Bool {
        switch kind {
        case .fields: SchoolSelfProfileEdit(base) == SchoolSelfProfileEdit(profile)
        case .photo: base.photoVersion == profile.photoVersion
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
