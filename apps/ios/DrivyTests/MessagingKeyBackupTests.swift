import XCTest
import SwiftUI
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
        await keys.set(restore: .failure(.recoveryKeyRefused))
        let model = MessagingKeyBackupModel(scope: scope, keys: keys)
        await model.restore("   ")
        XCTAssertEqual(model.failure, .emptyKey)
        await model.restore("bad")
        XCTAssertEqual(model.failure, .wrongKey)
        XCTAssertFalse(model.restored)
    }

    /// #169 : une requête qui n'aboutit pas n'accuse jamais la clé, et ne simule aucune restauration.
    func testRequestFailuresNeverBlameKey() async {
        let expectations: [(MessagingFailure, MessagingKeyBackupModel.Failure, Bool)] = [
            (.unavailable, .unreachable, true),
            (.accessChanged, .sessionExpired, false),
            (.contextChanged, .contextChanged, false),
            (.invalidResponse, .restoreFailed, true),
            (.protectionUnavailable, .restoreFailed, true),
            (.recoveryKeyRefused, .wrongKey, false),
        ]
        for (thrown, expected, retryable) in expectations {
            let keys = FakeKeys()
            await keys.set(restore: .failure(thrown))
            let model = MessagingKeyBackupModel(scope: scope, keys: keys, diagnostics: MessagingDiagnostics())
            await model.restore("synthetic-key")
            XCTAssertEqual(model.failure, expected, "\(thrown)")
            XCTAssertEqual(model.failure?.retryable, retryable, "\(thrown)")
            XCTAssertFalse(model.restored)
            XCTAssertNil(model.notRestored)
            if expected != .wrongKey {
                XCTAssertFalse(model.failure!.message.localizedCaseInsensitiveContains("refusée"), "\(thrown)")
                XCTAssertEqual(model.failure?.tone, .warning)
            }
        }
        XCTAssertEqual(MessagingKeyBackupModel.classify(CancellationError()), .restoreFailed)
        XCTAssertEqual(MessagingKeyBackupModel.Failure.wrongKey.tone, .danger)
    }

    /// #170 : la clé reste jusqu'à une confirmation explicite ; un autre compte ne la voit jamais.
    func testKeyHeldUntilExplicitConfirmationAndHiddenAfterAccountChange() async {
        final class Box: @unchecked Sendable { var scope: MessagingScope?; init(_ s: MessagingScope?) { scope = s } }
        let current = Box(scope)
        let model = MessagingKeyBackupModel(scope: scope, keys: FakeKeys(), currentScope: { current.scope })
        await model.create()
        XCTAssertTrue(model.holdsUnconfirmedKey)
        model.purgeIfContextChanged()
        XCTAssertEqual(model.recoveryKey, "EsTc abcd", "Même contexte : rien n'est purgé en silence")
        current.scope = MessagingScope(accountID: UUID(), schoolID: scope.schoolID, accessEpoch: 1)
        XCTAssertNil(model.recoveryKey, "Le compte suivant ne lit jamais la clé précédente")
        XCTAssertFalse(model.holdsUnconfirmedKey)
        model.purgeIfContextChanged()
        current.scope = scope
        XCTAssertNil(model.recoveryKey, "Purgée, la clé ne revient pas au retour du compte")
    }

    /// #141 : encres d'alerte sur la rangée de formulaire, en clair, Soft Charcoal et contraste accru (AA texte, 4,5:1).
    func testAlertInksMeetContrastOnFormRows() {
        func luminance(_ color: Color, _ traits: UITraitCollection) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ c: CGFloat) -> Double { let c = Double(c); return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        let variants: [(String, UITraitCollection)] = [
            ("clair", UITraitCollection(userInterfaceStyle: .light)),
            ("sombre", UITraitCollection(userInterfaceStyle: .dark)),
            ("sombre contraste accru", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .dark), .init(accessibilityContrast: .high)])),
            ("clair contraste accru", UITraitCollection(traitsFrom: [.init(userInterfaceStyle: .light), .init(accessibilityContrast: .high)])),
        ]
        for (name, traits) in variants {
            for tone in [DrivyTone.warning, .danger, .success] {
                let fg = luminance(tone.foreground, traits), bg = luminance(DrivyTheme.surfaceRaised, traits)
                let ratio = (max(fg, bg) + 0.05) / (min(fg, bg) + 0.05)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tone) \(name) : \(ratio)")
            }
        }
    }

    func testKeyCreatedAfterContextChangeIsNeverShown() async {
        let other = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2)
        let model = MessagingKeyBackupModel(scope: scope, keys: FakeKeys(), currentScope: { other })
        await model.create()
        XCTAssertNil(model.recoveryKey)
        XCTAssertEqual(model.failure, .contextChanged)
    }
}
