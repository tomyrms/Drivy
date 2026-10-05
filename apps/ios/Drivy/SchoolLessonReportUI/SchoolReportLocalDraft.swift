import CryptoKit
import Foundation

/// Saisie d’un bilan pas encore envoyée, gardée sur l’appareil entre deux ouvertures de l’app.
/// `base` est le contenu que l’école avait enregistré quand la saisie a été faite : la saisie n’est reprise
/// telle quelle que si l’école en est toujours là.
struct SchoolReportLocalDraft: Codable, Sendable, Equatable {
    struct Content: Codable, Sendable, Equatable {
        var workedOn: String
        var observationText: String
        var nextStep: String
        var observations: [SchoolReportObservation]

        var isEmpty: Bool {
            SchoolLessonHubRules.reportIsEmpty(workedOn: workedOn, observationText: observationText,
                nextStep: nextStep, observations: observations)
        }
    }
    let draftID: UUID
    let lessonID: UUID
    let base: Content
    let edited: Content
    let savedAt: Date
}

/// Jamais de repli en clair : un coffre illisible signifie qu’aucun brouillon local n’est écrit ni relu.
@MainActor
protocol SchoolReportLocalDraftStore: AnyObject {
    func read(scope: SchoolCommandScope, draftID: UUID) throws -> SchoolReportLocalDraft?
    func save(_ draft: SchoolReportLocalDraft, scope: SchoolCommandScope) throws
    func remove(scope: SchoolCommandScope, draftID: UUID) throws
}

/// Un fichier chiffré par bilan, avec la clé de la file des demandes (même coffre du trousseau).
/// Le compte, l’école et le serveur sont authentifiés avec le contenu : un autre compte ne déchiffre rien.
@MainActor
final class EncryptedSchoolReportDraftStore: SchoolReportLocalDraftStore {
    private let directory: URL
    private let suppliedKey: Data?
    private let vault: any IdentityVault
    private let maximumBytes = 400_000
    private let retention: TimeInterval = 30 * 86_400

    init(directory: URL? = nil, keyData: Data? = nil, vault: (any IdentityVault)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolReportDrafts", isDirectory: true)
        suppliedKey = keyData
        self.vault = vault ?? KeychainIdentityVault(service: "ch.drivy.school-commands.key-v1")
    }

    func read(scope: SchoolCommandScope, draftID: UUID) throws -> SchoolReportLocalDraft? {
        let file = file(for: draftID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let encrypted = try Data(contentsOf: file)
            guard encrypted.count <= maximumBytes else { throw SchoolConfigurationFailure.storage }
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let clear = try AES.GCM.open(box, using: key(create: false), authenticating: authenticatedData(scope: scope, draftID: draftID))
            let value = try JSONDecoder().decode(SchoolReportLocalDraft.self, from: clear)
            guard value.draftID == draftID else { throw SchoolConfigurationFailure.storage }
            return value
        } catch { throw SchoolConfigurationFailure.storage }
    }

    func save(_ draft: SchoolReportLocalDraft, scope: SchoolCommandScope) throws {
        do {
            let data = try JSONEncoder().encode(draft)
            guard data.count + 28 <= maximumBytes else { throw SchoolConfigurationFailure.storage }
            let box = try AES.GCM.seal(data, using: key(create: true), authenticating: authenticatedData(scope: scope, draftID: draft.draftID))
            guard let encrypted = box.combined else { throw SchoolConfigurationFailure.storage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            var protectedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(values)
            try encrypted.write(to: file(for: draft.draftID), options: [.atomic, .completeFileProtection])
            removeExpired(now: draft.savedAt)
        } catch { throw SchoolConfigurationFailure.storage }
    }

    func remove(scope: SchoolCommandScope, draftID: UUID) throws {
        let file = file(for: draftID)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { try FileManager.default.removeItem(at: file) }
        catch { throw SchoolConfigurationFailure.storage }
    }

    private func file(for draftID: UUID) -> URL {
        directory.appendingPathComponent("\(draftID.uuidString.lowercased()).bin")
    }

    private func authenticatedData(scope: SchoolCommandScope, draftID: UUID) -> Data {
        Data(["drivy-report-draft-v1", scope.personID.uuidString.lowercased(), scope.schoolID.uuidString.lowercased(),
              scope.apiBaseURL, draftID.uuidString.lowercased()].joined(separator: "|").utf8)
    }

    /// Un bilan jamais repris ne reste pas indéfiniment sur l’appareil.
    private func removeExpired(now: Date) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files where file.pathExtension == "bin" {
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) > retention else { continue }
            try? manager.removeItem(at: file)
        }
    }

    private func key(create: Bool) throws -> SymmetricKey {
        if let suppliedKey {
            guard suppliedKey.count == 32 else { throw SchoolConfigurationFailure.storage }
            return SymmetricKey(data: suppliedKey)
        }
        if let data = try vault.read() {
            guard data.count == 32 else { throw SchoolConfigurationFailure.storage }
            return SymmetricKey(data: data)
        }
        guard create else { throw SchoolConfigurationFailure.storage }
        let generated = SymmetricKey(size: .bits256)
        try vault.write(generated.withUnsafeBytes { Data($0) })
        return generated
    }
}
