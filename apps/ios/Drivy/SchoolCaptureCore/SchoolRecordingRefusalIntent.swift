import Foundation

/// Une restriction locale n'est pas un reçu de l'école. L'opération n'est formée
/// qu'après résolution de l'accord précédent et relecture de sa version réelle.
struct SchoolRecordingRefusalIntent: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let scope: SchoolCommandScope
    let learnerID: UUID
    let lessonID: UUID?
    let noticeVersionID: UUID
}

@MainActor final class SchoolRecordingRefusalStore {
    static let shared = SchoolRecordingRefusalStore()
    private let encrypted: EncryptedAccountIntentStore<[SchoolRecordingRefusalIntent]>
    /// Même une panne du disque ne réautorise pas la collecte dans ce processus.
    private var unsaved: [UUID: SchoolRecordingRefusalIntent] = [:]

    init(directory: URL? = nil, keyData: Data? = nil) {
        encrypted = EncryptedAccountIntentStore(purpose: "recording-refusal-v1", directory: directory, keyData: keyData)
    }
    private func account(_ scope: SchoolCommandScope) -> AccountIntentScope {
        AccountIntentScope(personID: scope.personID, apiBaseURL: scope.apiBaseURL)
    }
    func pending(scope: SchoolCommandScope, learnerID: UUID, lessonID: UUID?) throws -> SchoolRecordingRefusalIntent? {
        let values = (try encrypted.read(for: account(scope)) ?? []) + Array(unsaved.values)
        return values.first { $0.scope.belongsToWorkspace(scope) && $0.learnerID == learnerID
            && ($0.lessonID == nil || $0.lessonID == lessonID) }
    }
    func blocks(scope: SchoolCommandScope, learnerID: UUID, lessonID: UUID?) throws -> Bool {
        try pending(scope: scope, learnerID: learnerID, lessonID: lessonID) != nil
    }
    func save(_ intent: SchoolRecordingRefusalIntent) throws {
        unsaved[intent.id] = intent
        var values = try encrypted.read(for: account(intent.scope)) ?? []
        values.removeAll { $0.id == intent.id }
        guard values.count < 200 else { throw SchoolConfigurationFailure.storage }
        values.append(intent)
        try encrypted.save(values, for: account(intent.scope))
        unsaved.removeValue(forKey: intent.id)
    }
    func isDurable(_ intent: SchoolRecordingRefusalIntent) -> Bool {
        (try? encrypted.read(for: account(intent.scope)))?.contains(intent) == true
    }
    func remove(_ intent: SchoolRecordingRefusalIntent) throws {
        var values = try encrypted.read(for: account(intent.scope)) ?? []
        values.removeAll { $0.id == intent.id && $0.scope == intent.scope }
        try encrypted.save(values, for: account(intent.scope))
        unsaved.removeValue(forKey: intent.id)
    }
}
