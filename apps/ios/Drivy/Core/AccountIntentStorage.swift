import CryptoKit
import Darwin
import Foundation

/// Les préférences personnelles ne suivent pas l'école sélectionnée. L'API et la personne forment leur portée.
struct AccountIntentScope: Codable, Sendable, Equatable, Hashable {
    let personID: UUID
    let apiBaseURL: String

    var isValid: Bool {
        guard let url = URLComponents(string: apiBaseURL) else { return false }
        return url.scheme == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil && apiBaseURL.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

/// Snapshot atomique pour une intention de compte. Il ne remplace ni la file scolaire ni celle des messages.
/// La lecture n'est jamais assimilée à une autorisation : le consommateur revalide son contexte avant l'envoi.
@MainActor final class EncryptedAccountIntentStore<Value: Codable> {
    private let directory: URL
    private let purpose: String
    private let suppliedKey: Data?
    private let vault: any IdentityVault
    private let maximumBytes = 1_000_000

    init(purpose: String, directory: URL? = nil, keyData: Data? = nil, vault: (any IdentityVault)? = nil) {
        self.purpose = purpose
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AccountIntents", isDirectory: true)
        suppliedKey = keyData
        self.vault = vault ?? KeychainIdentityVault(service: "ch.drivy.account-intents.key-v1")
    }

    func read(for scope: AccountIntentScope) throws -> Value? {
        do {
            guard scope.isValid else { throw SchoolConfigurationFailure.storage }
            let file = url(scope)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else {
                throw SchoolConfigurationFailure.storage
            }
            let encrypted = try Data(contentsOf: file)
            guard encrypted.count <= maximumBytes else { throw SchoolConfigurationFailure.storage }
            let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key(create: false),
                                         authenticating: authentication(scope))
            let archive = try JSONDecoder().decode(Archive.self, from: clear)
            guard archive.version == 1, archive.scope == scope else { throw SchoolConfigurationFailure.storage }
            return archive.value
        } catch { throw SchoolConfigurationFailure.storage }
    }

    func save(_ value: Value, for scope: AccountIntentScope) throws {
        do {
            guard scope.isValid else { throw SchoolConfigurationFailure.storage }
            // Ne pas créer une nouvelle clé au-dessus d'un journal devenu illisible.
            if FileManager.default.fileExists(atPath: url(scope).path) { _ = try read(for: scope) }
            let clear = try JSONEncoder().encode(Archive(version: 1, scope: scope, value: value))
            guard clear.count + 28 <= maximumBytes else { throw SchoolConfigurationFailure.storage }
            let sealed = try AES.GCM.seal(clear, using: key(create: true), authenticating: authentication(scope))
            guard let encrypted = sealed.combined else { throw SchoolConfigurationFailure.storage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            guard try FileManager.default.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw SchoolConfigurationFailure.storage
            }
            var protectedDirectory = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(values)
            try encrypted.write(to: url(scope), options: [.atomic, .completeFileProtection])
            try sync(url(scope), directory: false)
            try sync(directory, directory: true)
        } catch { throw SchoolConfigurationFailure.storage }
    }

    private func authentication(_ scope: AccountIntentScope) -> Data {
        Data("drivy-account-intents-v1|\(purpose)|\(scope.apiBaseURL)|\(scope.personID.uuidString)".utf8)
    }
    private func url(_ scope: AccountIntentScope) -> URL {
        let digest = SHA256.hash(data: authentication(scope)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).sealed")
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
        let value = SymmetricKey(size: .bits256)
        try vault.write(value.withUnsafeBytes { Data($0) })
        return value
    }
    private func sync(_ url: URL, directory: Bool) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw SchoolConfigurationFailure.storage }
            let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (directory ? O_DIRECTORY : 0)
            let descriptor = Darwin.open(path, flags)
            guard descriptor >= 0 else { throw SchoolConfigurationFailure.storage }
            defer { Darwin.close(descriptor) }
            let result = directory ? Darwin.fsync(descriptor) : Darwin.fcntl(descriptor, F_FULLFSYNC)
            guard result == 0 else { throw SchoolConfigurationFailure.storage }
        }
    }
    private struct Archive: Codable {
        let version: Int
        let scope: AccountIntentScope
        let value: Value
    }
}
