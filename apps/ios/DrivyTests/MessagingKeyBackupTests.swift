import XCTest
@testable import Drivy

/// Sauvegarde des clés (#67). Écrit, non exécuté (#84).
@MainActor
final class MessagingKeyBackupTests: XCTestCase {
    private actor FakeKeys: MessagingKeyManagement {
        var pending = false
        var enableResult: Result<String, MessagingFailure> = .success("EsTc abcd")
        var restoreResult: Result<(imported: Int, failed: Int), MessagingFailure> = .success((3, 0))
        var lastRecovery: String?

        func set(pending: Bool) { self.pending = pending }
        func set(enable: Result<String, MessagingFailure>) { enableResult = enable }
        func set(restore: Result<(imported: Int, failed: Int), MessagingFailure>) { restoreResult = restore }

        func enableBackup(scope: MessagingScope) async throws -> String { try enableResult.get() }
        func restoreBackup(recoveryKey: String, scope: MessagingScope) async throws -> (imported: Int, failed: Int) {
            lastRecovery = recoveryKey
            return try restoreResult.get()
        }
        func backupPending(scope: MessagingScope) async -> Bool { pending }
        func ownDevices(scope: MessagingScope) async throws -> [MessagingOwnDevice] { [] }
        func confirmOwnDevice(deviceID: String, fingerprint: String, scope: MessagingScope) async throws {}
    }

    private let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1)

    func testPendingShownOnlyWhenLate() async {
        let keys = FakeKeys()
        let model = MessagingKeyBackupModel(scope: scope, keys: keys)
        await model.refresh()
        XCTAssertFalse(model.pending)
        await keys.set(pending: true)
        await model.refresh()
        XCTAssertTrue(model.pending)
    }

    func testRecoveryKeyShownOnceThenForgotten() async {
        let model = MessagingKeyBackupModel(scope: scope, keys: FakeKeys())
        await model.create()
        XCTAssertEqual(model.recoveryKey, "EsTc abcd")
        model.acknowledgeKey()
        XCTAssertNil(model.recoveryKey)
    }

    func testCreateConflictExplainsExistingBackup() async {
        let keys = FakeKeys()
        await keys.set(enable: .failure(.stateConflict))
        let model = MessagingKeyBackupModel(scope: scope, keys: keys)
        await model.create()
        XCTAssertNil(model.recoveryKey)
        XCTAssertEqual(model.failure, .existingBackup)
    }

    func testRestoreTrimsKeyAndHidesZeroNotRestored() async {
        let keys = FakeKeys()
        let model = MessagingKeyBackupModel(scope: scope, keys: keys)
        await model.restore("  key  \n")
        let sent = await keys.lastRecovery
        XCTAssertEqual(sent, "key")
        XCTAssertTrue(model.restored)
        XCTAssertNil(model.notRestored)
    }

    func testRestoreReportsNotRestoredWhenPositive() async {
        let keys = FakeKeys()
        await keys.set(restore: .success((1, 2)))
        let model = MessagingKeyBackupModel(scope: scope, keys: keys)
        await model.restore("key")
        XCTAssertEqual(model.notRestored, 2)
        XCTAssertEqual(MessagingKeyBackupModel.notRestoredText(2), "2 conversations non restaurées")
        XCTAssertEqual(MessagingKeyBackupModel.notRestoredText(1), "1 conversation non restaurée")
    }

    func testWrongKeyAndEmptyKeyAreExplicit() async {
        let keys = FakeKeys()
        await keys.set(restore: .failure(.protectionUnavailable))
        let model = MessagingKeyBackupModel(scope: scope, keys: keys)
        await model.restore("   ")
        XCTAssertEqual(model.failure, .emptyKey)
        await model.restore("bad")
        XCTAssertEqual(model.failure, .wrongKey)
        XCTAssertFalse(model.restored)
    }
}
