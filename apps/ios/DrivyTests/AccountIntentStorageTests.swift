import Foundation
import Testing
@testable import Drivy

@MainActor struct AccountIntentStorageTests {
    private let scope = AccountIntentScope(personID: UUID(uuidString: "10000000-0000-4000-8000-000000000119")!,
                                           apiBaseURL: "https://api.example.invalid")
    private let key = Data(repeating: 0x61, count: 32)

    @Test func pendingChoiceAndExactRequestSurviveEncryptedReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccountIntents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID(), base = SchoolNotificationPreferences(version: 7, courseOffers: true, courseReminders: true,
                                                               courseChanges: true, courseStaffAlerts: false)
        let body = SchoolNotificationPreferencesBody(courseOffers: false, courseReminders: true, courseChanges: true, courseStaffAlerts: false)
        let journal = SchoolNotificationIntentJournal(intents: [.courseOffers: .init(id: id, value: false)],
            attempt: .init(base: base, body: body, intentIDs: [.courseOffers: id]))
        let store = EncryptedAccountIntentStore<SchoolNotificationIntentJournal>(purpose: "notification-preferences", directory: directory, keyData: key)
        try store.save(journal, for: scope)
        let reopened = EncryptedAccountIntentStore<SchoolNotificationIntentJournal>(purpose: "notification-preferences", directory: directory, keyData: key)
        #expect(try reopened.read(for: scope) == journal)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let bytes = try Data(contentsOf: #require(files.first))
        #expect(bytes.range(of: Data("courseOffers".utf8)) == nil)
        #expect(bytes.range(of: Data(scope.personID.uuidString.utf8)) == nil)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try reopened.read(for: .init(personID: UUID(), apiBaseURL: scope.apiBaseURL)) == nil)
        #expect(try reopened.read(for: .init(personID: scope.personID, apiBaseURL: "https://other.example.invalid")) == nil)
    }

    @Test func wrongKeyCannotReplaceAJournalWithAnEmptySnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccountIntents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = SchoolNotificationIntentJournal(intents: [.courseOffers: .init(id: UUID(), value: false)])
        try EncryptedAccountIntentStore<SchoolNotificationIntentJournal>(purpose: "notification-preferences", directory: directory, keyData: key)
            .save(journal, for: scope)
        let file = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let before = try Data(contentsOf: file)
        let wrong = EncryptedAccountIntentStore<SchoolNotificationIntentJournal>(purpose: "notification-preferences", directory: directory,
                                                                               keyData: Data(repeating: 0x62, count: 32))
        #expect(throws: SchoolConfigurationFailure.storage) { try wrong.read(for: scope) }
        #expect(throws: SchoolConfigurationFailure.storage) { try wrong.save(.init(), for: scope) }
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func unsafeScopeAndNonDirectoryNeverCreateAnUnprotectedFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccountIntents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EncryptedAccountIntentStore<SchoolNotificationIntentJournal>(purpose: "notification-preferences", directory: directory, keyData: key)
        #expect(throws: SchoolConfigurationFailure.storage) {
            try store.save(.init(), for: .init(personID: scope.personID, apiBaseURL: "http://api.example.invalid"))
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try Data("unrelated".utf8).write(to: directory)
        #expect(throws: SchoolConfigurationFailure.storage) { try store.save(.init(), for: scope) }
        #expect(try Data(contentsOf: directory) == Data("unrelated".utf8))
    }
}
