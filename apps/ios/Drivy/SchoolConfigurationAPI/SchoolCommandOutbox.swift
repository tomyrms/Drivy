import CryptoKit
import Darwin
import Foundation

struct SchoolCommandScope: Codable, Sendable, Equatable {
    let personID: UUID
    let schoolID: UUID
    let membershipID: UUID
    let accessEpoch: Int
    let apiBaseURL: String

    func belongsToWorkspace(_ other: SchoolCommandScope) -> Bool {
        personID == other.personID && schoolID == other.schoolID && apiBaseURL == other.apiBaseURL
    }
}

enum SchoolCommandKind: String, Codable, Sendable {
    case updateSchool, saveSetup, activate, saveDataPolicy
}

struct PendingSchoolCommand: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let scope: SchoolCommandScope
    let kind: SchoolCommandKind
    let resourceVersion: Int
    let createdAt: Date
    let body: Data
}

@MainActor
protocol SchoolCommandOutbox: AnyObject {
    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand?
    func save(_ command: PendingSchoolCommand) throws
    func remove(_ command: PendingSchoolCommand) throws
}

/// Persist before emission. Only encrypted bytes reach disk; an uncertain
/// command keeps the exact request and operation identifier across launches.
@MainActor
final class EncryptedSchoolCommandOutbox: SchoolCommandOutbox {
    private let directory: URL
    private let suppliedKey: Data?
    private let vault: any IdentityVault
    private let authenticatedData = Data("drivy-school-commands-v1".utf8)
    // JSON encodes request Data as base64, larger than the original request.
    private let maximumArchiveBytes = 14_000_000
    private var file: URL { directory.appendingPathComponent("pending-v1.bin") }

    init(directory: URL? = nil, keyData: Data? = nil, vault: (any IdentityVault)? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SchoolCommands", isDirectory: true)
        suppliedKey = keyData
        self.vault = vault ?? KeychainIdentityVault(service: "ch.drivy.school-commands.key-v1")
    }

    func pending(for scope: SchoolCommandScope) throws -> PendingSchoolCommand? {
        // Preserve uncertainty after rights change. The caller must compare the
        // full scope before retrying; another account never sees this command.
        try read().first { $0.scope.belongsToWorkspace(scope) }
    }

    func save(_ command: PendingSchoolCommand) throws {
        try validate(command)
        var commands = try read()
        if let existing = commands.first(where: { $0.scope.belongsToWorkspace(command.scope) || $0.id == command.id }) {
            guard existing == command else { throw SchoolConfigurationFailure.pendingCommand }
            try synchronize()
            return
        }
        guard commands.count < 50 else { throw SchoolConfigurationFailure.storage }
        commands.append(command)
        try write(commands)
    }

    func remove(_ command: PendingSchoolCommand) throws {
        var commands = try read()
        guard let index = commands.firstIndex(where: { $0.id == command.id }) else { return }
        guard commands[index] == command else { throw SchoolConfigurationFailure.storage }
        commands.remove(at: index)
        try write(commands)
    }

    private func read() throws -> [PendingSchoolCommand] {
        do {
            let manager = FileManager.default
            guard manager.fileExists(atPath: directory.path) else { return [] }
            guard try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
                throw SchoolConfigurationFailure.storage
            }
            guard manager.fileExists(atPath: file.path) else { return [] }
            let attributes = try manager.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let bytes = attributes[.size] as? NSNumber, bytes.intValue <= maximumArchiveBytes else {
                throw SchoolConfigurationFailure.storage
            }
            let encrypted = try Data(contentsOf: file)
            guard encrypted.count <= maximumArchiveBytes else { throw SchoolConfigurationFailure.storage }
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let clear = try AES.GCM.open(box, using: key(create: false), authenticating: authenticatedData)
            let archive = try JSONDecoder().decode(Archive.self, from: clear)
            guard archive.version == 1, archive.commands.count <= 50,
                  Set(archive.commands.map(\.id)).count == archive.commands.count else { throw SchoolConfigurationFailure.storage }
            for (index, command) in archive.commands.enumerated() {
                try validate(command)
                guard !archive.commands.prefix(index).contains(where: { $0.scope.belongsToWorkspace(command.scope) }) else {
                    throw SchoolConfigurationFailure.storage
                }
            }
            return archive.commands
        } catch { throw SchoolConfigurationFailure.storage }
    }

    private func write(_ commands: [PendingSchoolCommand]) throws {
        do {
            let data = try JSONEncoder().encode(Archive(version: 1, commands: commands))
            guard data.count + 28 <= maximumArchiveBytes else { throw SchoolConfigurationFailure.storage }
            let box = try AES.GCM.seal(data, using: key(create: true), authenticating: authenticatedData)
            guard let encrypted = box.combined else { throw SchoolConfigurationFailure.storage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            var protectedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedDirectory.setResourceValues(values)
            try encrypted.write(to: file, options: [.atomic, .completeFileProtection])
            try synchronize()
        } catch { throw SchoolConfigurationFailure.storage }
    }

    private func validate(_ command: PendingSchoolCommand) throws {
        let scope = command.scope
        guard command.resourceVersion > 0, scope.accessEpoch > 0,
              command.createdAt.timeIntervalSince1970.isFinite,
              !command.body.isEmpty, command.body.count <= 200_000,
              scope.apiBaseURL.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let endpoint = URLComponents(string: scope.apiBaseURL), endpoint.scheme == "https",
              let host = endpoint.host, !host.isEmpty, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              let payload = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              let operation = payload["operationId"] as? String, UUID(uuidString: operation) == command.id else {
            throw SchoolConfigurationFailure.storage
        }
    }

    private func synchronize() throws {
        // Atomic replacement plus a storage barrier precede every emission,
        // including a retry after a previous barrier error. No plaintext temp.
        try file.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw SchoolConfigurationFailure.storage }
            let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else { throw SchoolConfigurationFailure.storage }
            defer { Darwin.close(descriptor) }
            guard Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 else { throw SchoolConfigurationFailure.storage }
        }
        try directory.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw SchoolConfigurationFailure.storage }
            let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY)
            guard descriptor >= 0 else { throw SchoolConfigurationFailure.storage }
            defer { Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else { throw SchoolConfigurationFailure.storage }
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

    private struct Archive: Codable {
        let version: Int
        let commands: [PendingSchoolCommand]
    }
}
