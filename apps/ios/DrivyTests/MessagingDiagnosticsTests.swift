import XCTest
import MatrixSDKCrypto
@testable import Drivy

/// QA84 : diagnostic court non sensible sous les erreurs de protection, sans repli en clair.
@MainActor
final class MessagingDiagnosticsTests: XCTestCase {
    private let person = UUID(), school = UUID()
    private let baseURL = URL(string: "https://api.example.invalid/")!
    private var scope: MessagingScope {
        MessagingScope(accountID: person, schoolID: school, accessEpoch: 1, apiBaseURL: baseURL.absoluteString)
    }

    private func relay(_ diagnostics: MessagingDiagnostics, status: Int, body: String = "{}") -> MessagingCryptoHTTPRelay {
        let scope = self.scope
        let wire = DiagnosticHTTP { request in
            SchoolHTTPResponse(data: Data(body.utf8), status: status, url: request.url!, contentType: "application/json")
        }
        return MessagingCryptoHTTPRelay(baseURL: baseURL, transport: wire, diagnostics: diagnostics,
            token: { "synthetic-token" }, invalidate: { _ in false }, currentScope: { scope })
    }

    func testRelayKeepsHTTPStatusOfDeviceUploadWithoutIdentifiers() async throws {
        for (status, expected) in [(404, "H-UPLOAD-404"), (422, "H-UPLOAD-422"), (400, "H-UPLOAD-400"), (503, "H-UPLOAD-503")] {
            let diagnostics = MessagingDiagnostics()
            do {
                _ = try await relay(diagnostics, status: status).call(scope: scope, deviceID: "ABCDEFGHIJ0123",
                    method: "POST", path: ["keys", "upload"], query: [], body: Data("{}".utf8))
                XCTFail("Un refus serveur ne doit jamais réussir")
            } catch {}
            XCTAssertEqual(diagnostics.last, expected)
        }
    }

    func testMembersRouteIsCategorisedAndNeverCarriesConversationID() async throws {
        let diagnostics = MessagingDiagnostics()
        let conversation = UUID()
        do { _ = try await relay(diagnostics, status: 500).members(scope: scope, deviceID: "ABCDEFGHIJ0123", conversationID: conversation); XCTFail() }
        catch {}
        XCTAssertEqual(diagnostics.last, "H-MEMBERS-500")
        XCTAssertFalse(diagnostics.last!.lowercased().contains(conversation.uuidString.lowercased().prefix(8)))
        XCTAssertEqual(MessagingDiagnostics.route(["crypto", "sendToDevice", "m.room.encrypted", "txn"]), "TODEVICE")
    }

    func testUnknownConflictIsNotAnExistingBackup() async throws {
        let diagnostics = MessagingDiagnostics()
        do {
            _ = try await relay(diagnostics, status: 409, body: "{\"code\":\"SOMETHING_ELSE\"}").call(scope: scope,
                deviceID: "ABCDEFGHIJ0123", method: "POST", path: ["room_keys", "version"], query: [], body: Data("{}".utf8))
            XCTFail()
        } catch { XCTAssertEqual(error as? MessagingCryptoRelayFailure, .conflict) }
        XCTAssertEqual(diagnostics.last, "H-BKVER-409")
        do {
            _ = try await relay(MessagingDiagnostics(), status: 409, body: "{\"code\":\"BACKUP_VERSION_CONFLICT\"}").call(scope: scope,
                deviceID: "ABCDEFGHIJ0123", method: "POST", path: ["room_keys", "version"], query: [], body: Data("{}".utf8))
            XCTFail()
        } catch { XCTAssertEqual(error as? MessagingCryptoRelayFailure, .backupVersionConflict) }
    }

    func testEnableBackupWithUnknownConflictFailsWithoutClaimingExistingBackup() async throws {
        let diagnostics = MessagingDiagnostics()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let crypto = try MatrixMessagingCryptography(scope: scope, relay: ConflictRelay(),
            vault: MessagingCryptoVault(scope: scope, root: root, keychain: MemoryKeychain(), diagnostics: diagnostics),
            diagnostics: diagnostics)
        do { _ = try await crypto.enableBackup(scope: scope); XCTFail() }
        catch { XCTAssertNotEqual(error as? MessagingFailure, .stateConflict) }
    }

    func testKeychainStatusIsKeptAndNoStoreIsCreated() async throws {
        let diagnostics = MessagingDiagnostics()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try MessagingCryptoVault(scope: scope, root: root,
            keychain: MemoryKeychain(addStatus: errSecMissingEntitlement), diagnostics: diagnostics)
        let crypto = try MatrixMessagingCryptography(scope: scope, relay: ConflictRelay(), vault: vault, diagnostics: diagnostics)
        let failure = await crypto.availabilityFailure(scope: scope, conversationID: UUID())
        XCTAssertEqual(failure, .protectionUnavailable)
        XCTAssertEqual(crypto.lastDiagnostic, "K-A-N34018")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.storePath))
    }

    func testOrphanStoreIsReportedAndLeftIntact() throws {
        let diagnostics = MessagingDiagnostics()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try MessagingCryptoVault(scope: scope, root: root, keychain: MemoryKeychain(), diagnostics: diagnostics)
        try FileManager.default.createDirectory(atPath: vault.storePath, withIntermediateDirectories: true)
        let db = URL(fileURLWithPath: vault.storePath).appendingPathComponent("matrix-sdk-crypto.sqlite3")
        try Data("chiffré".utf8).write(to: db)
        XCTAssertThrowsError(try vault.secrets())
        XCTAssertEqual(diagnostics.last, "S-ORPHAN")
        XCTAssertTrue(FileManager.default.fileExists(atPath: db.path))
    }

    func testFirstCauseWinsAndDisplayAddsOnlySafeCode() {
        let diagnostics = MessagingDiagnostics()
        diagnostics.recordIfEmpty("H-UPLOAD-404")
        diagnostics.recordIfEmpty("SDK-X")
        XCTAssertEqual(diagnostics.last, "H-UPLOAD-404")
        XCTAssertEqual(diagnostics.describe(.protectionUnavailable),
                       "\(MessagingFailure.protectionUnavailable.localizedDescription)\nCode : H-UPLOAD-404")
        XCTAssertEqual(diagnostics.describe(.accessChanged), MessagingFailure.accessChanged.localizedDescription)
        let clean = MessagingDiagnostics()
        clean.record("/var/mobile/Containers/x")
        clean.record("Bearer abc")
        XCTAssertNil(clean.last)
        XCTAssertEqual(MessagingDiagnostics.keychain("R", -25300), "K-R-N25300")
    }

    func testBackupCreateFailureShowsCodeButExistingBackupDoesNot() async {
        let diagnostics = MessagingDiagnostics()
        diagnostics.record("H-BKVER-404")
        let failing = FailingKeys(failure: .protectionUnavailable)
        let model = MessagingKeyBackupModel(scope: scope, keys: failing, diagnostics: diagnostics)
        await model.create()
        XCTAssertEqual(model.failure, .createFailed)
        XCTAssertEqual(model.diagnosticCode, "H-BKVER-404")
        let conflict = MessagingKeyBackupModel(scope: scope, keys: FailingKeys(failure: .stateConflict), diagnostics: diagnostics)
        await conflict.create()
        XCTAssertEqual(conflict.failure, .existingBackup)
        XCTAssertNil(conflict.diagnosticCode)
    }
}

private actor DiagnosticHTTP: SchoolHTTPTransport {
    private let responder: @Sendable (URLRequest) -> SchoolHTTPResponse
    init(_ responder: @escaping @Sendable (URLRequest) -> SchoolHTTPResponse) { self.responder = responder }
    func send(_ request: URLRequest) -> SchoolHTTPResponse { responder(request) }
}

private struct ConflictRelay: MessagingCryptoRelay {
    func call(scope: MessagingScope, deviceID: String, method: String, path: [String], query: [URLQueryItem], body: Data?) async throws -> Data {
        throw MessagingCryptoRelayFailure.conflict
    }
    func members(scope: MessagingScope, deviceID: String, conversationID: UUID) async throws -> MessagingConversationMembers {
        throw MessagingCryptoRelayFailure.conflict
    }
}

private final class MemoryKeychain: MessagingCryptoKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private let addStatus: OSStatus
    init(addStatus: OSStatus = errSecSuccess) { self.addStatus = addStatus }
    func read(service: String, account: String) throws -> Data? { lock.withLock { items["\(service)|\(account)"] } }
    func add(service: String, account: String, data: Data) throws {
        guard addStatus == errSecSuccess else { throw MessagingKeychainError(operation: "A", status: addStatus) }
        lock.withLock { items["\(service)|\(account)"] = data }
    }
}

private struct FailingKeys: MessagingKeyManagement {
    let failure: MessagingFailure
    func enableBackup(scope: MessagingScope) async throws -> String { throw failure }
    func restoreBackup(recoveryKey: String, scope: MessagingScope) async throws -> (imported: Int, failed: Int) { throw failure }
    func backupPending(scope: MessagingScope) async -> Bool { false }
    func ownDevices(scope: MessagingScope) async throws -> [MessagingOwnDevice] { [] }
    func confirmOwnDevice(deviceID: String, fingerprint: String, scope: MessagingScope) async throws {}
}
