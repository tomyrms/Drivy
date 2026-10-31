import Foundation

/// Préparation privée par leçon ; souhait personnel par formation. Aucun envoi automatique au retour.
struct SchoolLessonTextDraft: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case preparation, wish }
    struct Content: Codable, Equatable, Sendable {
        var goals: [SchoolLessonGoal] = []
        var text: String = ""
    }
    let kind: Kind
    let resourceID: UUID
    let baseVersion: Int
    let base: Content
    let edited: Content
    /// Contenu d’une demande en vol : un GET identique permet de reprendre la saisie suivante sans faux conflit.
    let sent: Content?
    let savedAt: Date

    func conflicts(with confirmed: Content) -> Bool {
        edited != confirmed && base != confirmed && sent != confirmed
    }
}

@MainActor protocol SchoolLessonTextDraftStore: AnyObject {
    func read(scope: SchoolCommandScope, kind: SchoolLessonTextDraft.Kind, resourceID: UUID) throws -> SchoolLessonTextDraft?
    func save(_ value: SchoolLessonTextDraft, scope: SchoolCommandScope) throws
    func remove(scope: SchoolCommandScope, kind: SchoolLessonTextDraft.Kind, resourceID: UUID, explicit: Bool) throws
}

@MainActor final class EncryptedSchoolLessonTextDraftStore: SchoolLessonTextDraftStore {
    private let directory: URL?
    private let keyData: Data?
    init(directory: URL? = nil, keyData: Data? = nil) { self.directory = directory; self.keyData = keyData }

    private func store(_ scope: SchoolCommandScope, _ kind: SchoolLessonTextDraft.Kind, _ id: UUID) -> EncryptedAccountIntentStore<SchoolLessonTextDraft> {
        EncryptedAccountIntentStore(purpose: "lesson-text-v1|\(scope.schoolID)|\(scope.membershipID)|\(scope.accessEpoch)|\(kind.rawValue)|\(id)",
            directory: directory, keyData: keyData)
    }
    private func account(_ scope: SchoolCommandScope) -> AccountIntentScope {
        AccountIntentScope(personID: scope.personID, apiBaseURL: scope.apiBaseURL)
    }
    func read(scope: SchoolCommandScope, kind: SchoolLessonTextDraft.Kind, resourceID: UUID) throws -> SchoolLessonTextDraft? {
        guard let value = try store(scope, kind, resourceID).read(for: account(scope)) else { return nil }
        guard value.kind == kind, value.resourceID == resourceID, value.baseVersion > 0 else { throw SchoolConfigurationFailure.storage }
        return value
    }
    func save(_ value: SchoolLessonTextDraft, scope: SchoolCommandScope) throws {
        try store(scope, value.kind, value.resourceID).save(value, for: account(scope))
    }
    func remove(scope: SchoolCommandScope, kind: SchoolLessonTextDraft.Kind, resourceID: UUID, explicit: Bool) throws {
        try store(scope, kind, resourceID).remove(for: account(scope), discardingUnreadable: explicit)
    }
}
