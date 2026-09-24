import CryptoKit
import Foundation
import Testing
@testable import Drivy

@MainActor
struct SchoolCommandOutboxTests {
    private let key = Data(repeating: 0xA7, count: 32)
    private let person = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let school = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let membership = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!

    private func scope(personID: UUID? = nil, schoolID: UUID? = nil, epoch: Int = 1,
                       base: String = "https://api.example.invalid/refonte") -> SchoolCommandScope {
        SchoolCommandScope(personID: personID ?? person, schoolID: schoolID ?? school,
            membershipID: membership, accessEpoch: epoch, apiBaseURL: base)
    }

    private func command(scope: SchoolCommandScope? = nil, id: UUID = UUID(), text: String = "Nom privé de l’école") throws -> PendingSchoolCommand {
        let body = try JSONSerialization.data(withJSONObject: ["operationId": id.uuidString, "name": text], options: [.sortedKeys])
        return PendingSchoolCommand(id: id, scope: scope ?? self.scope(), kind: .updateSchool,
            resourceVersion: 1, createdAt: Date(timeIntervalSince1970: 1_790_000_000), body: body)
    }

    private func inDirectory(_ run: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DrivyOutbox-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try run(directory)
    }

    @Test func encryptedRequestSurvivesRecreationAndRetainsExactBytes() throws {
        try inDirectory { directory in
            let expected = try command()
            let first = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try first.save(expected)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            #expect(files.map(\.lastPathComponent) == ["pending-v1.bin"])
            let stored = try Data(contentsOf: directory.appendingPathComponent("pending-v1.bin"))
            #expect(stored.range(of: expected.body) == nil)
            #expect(stored.range(of: Data("Nom privé de l’école".utf8)) == nil)
            #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pending(for: scope()) == expected)
            try reopened.save(expected)
            #expect(try reopened.pending(for: scope())?.body == expected.body)
        }
    }

    @Test func scopeIsolatesAccountsSchoolsAndServersButPreservesChangedRights() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let expected = try command()
            try store.save(expected)
            #expect(try store.pending(for: scope(personID: UUID())) == nil)
            #expect(try store.pending(for: scope(schoolID: UUID())) == nil)
            #expect(try store.pending(for: scope(base: "https://another.example.invalid")) == nil)
            #expect(try store.pending(for: scope(epoch: 2)) == expected)
            let newerRights = try command(scope: scope(epoch: 2))
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(newerRights) }
            #expect(try store.pending(for: scope()) == expected)
        }
    }

    @Test func keychainKeySurvivesRecreationAndMissingKeyDoesNotReplaceTheArchive() throws {
        try inDirectory { directory in
            let vault = KeychainIdentityVault(service: "ch.drivy.tests.outbox.\(UUID().uuidString)")
            defer { try? vault.clear() }
            let expected = try command()
            try EncryptedSchoolCommandOutbox(directory: directory, vault: vault).save(expected)
            #expect(try vault.read()?.count == 32)
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, vault: vault)
            #expect(try reopened.pending(for: scope()) == expected)
            let file = directory.appendingPathComponent("pending-v1.bin")
            let before = try Data(contentsOf: file)
            try vault.clear()
            #expect(throws: SchoolConfigurationFailure.storage) { try reopened.pending(for: scope()) }
            #expect(throws: SchoolConfigurationFailure.storage) { try reopened.save(expected) }
            #expect(try vault.read() == nil)
            #expect(try Data(contentsOf: file) == before)
        }
    }

    @Test func pendingOperationCannotBeReplacedOrRemovedWithDifferentBytes() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let expected = try command()
            try store.save(expected)
            let modified = try command(id: expected.id, text: "Un autre contenu")
            #expect(throws: SchoolConfigurationFailure.pendingCommand) { try store.save(modified) }
            #expect(throws: SchoolConfigurationFailure.storage) { try store.remove(modified) }
            try store.remove(expected)
            let reopened = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            #expect(try reopened.pending(for: scope()) == nil)
            try reopened.remove(expected)
        }
    }

    @Test func wrongKeyOrModifiedCiphertextFailsClosedWithoutReplacement() throws {
        try inDirectory { directory in
            let expected = try command()
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            try store.save(expected)
            let file = directory.appendingPathComponent("pending-v1.bin")
            let before = try Data(contentsOf: file)
            let wrong = EncryptedSchoolCommandOutbox(directory: directory, keyData: Data(repeating: 0x44, count: 32))
            #expect(throws: SchoolConfigurationFailure.storage) { try wrong.pending(for: scope()) }
            #expect(throws: SchoolConfigurationFailure.storage) { try wrong.save(expected) }
            #expect(try Data(contentsOf: file) == before)
            var damaged = before
            damaged[damaged.count - 1] ^= 0x01
            try damaged.write(to: file)
            #expect(throws: SchoolConfigurationFailure.storage) { try store.pending(for: scope()) }
            #expect(throws: SchoolConfigurationFailure.storage) { try store.save(expected) }
            #expect(try Data(contentsOf: file) == damaged)
        }
    }

    @Test func malformedDecryptedRecordsAndMismatchedOperationIDsAreRejected() throws {
        try inDirectory { directory in
            let expected = try command()
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let mismatch = PendingSchoolCommand(id: UUID(), scope: expected.scope, kind: expected.kind,
                resourceVersion: 1, createdAt: expected.createdAt, body: expected.body)
            #expect(throws: SchoolConfigurationFailure.storage) { try store.save(mismatch) }
            try store.save(expected)
            // Authenticate a structurally invalid archive with the known test key:
            // validation must still reject duplicate workspace commands after open.
            struct Archive: Encodable { let version: Int; let commands: [PendingSchoolCommand] }
            let duplicate = try command()
            let clear = try JSONEncoder().encode(Archive(version: 1, commands: [expected, duplicate]))
            let encrypted = try AES.GCM.seal(clear, using: SymmetricKey(data: key),
                authenticating: Data("drivy-school-commands-v1".utf8)).combined!
            try encrypted.write(to: directory.appendingPathComponent("pending-v1.bin"))
            #expect(throws: SchoolConfigurationFailure.storage) { try store.pending(for: scope()) }
        }
    }

    @Test func unsafeScopeOversizedBodyAndUnwritableLocationDoNotAdmitACommand() throws {
        try inDirectory { directory in
            let store = EncryptedSchoolCommandOutbox(directory: directory, keyData: key)
            let insecure = try command(scope: scope(base: "http://api.example.invalid"))
            let tooLarge = try command(text: String(repeating: "x", count: 200_000))
            #expect(throws: SchoolConfigurationFailure.storage) { try store.save(insecure) }
            #expect(throws: SchoolConfigurationFailure.storage) { try store.save(tooLarge) }
            #expect(!FileManager.default.fileExists(atPath: directory.path))
            try Data("unrelated test file".utf8).write(to: directory)
            let valid = try command()
            #expect(throws: SchoolConfigurationFailure.storage) { try store.save(valid) }
            #expect(try String(contentsOf: directory, encoding: .utf8) == "unrelated test file")
        }
    }
}
