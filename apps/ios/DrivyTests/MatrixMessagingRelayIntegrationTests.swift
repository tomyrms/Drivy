import Foundation
import Security
import XCTest
import MatrixSDKCrypto
@testable import Drivy

/// Requires the disposable HTTPS Fastify/PostgreSQL relay. Missing setup is a failure, never a skip.
/// Run explicitly on an Apple simulator. No production URL, credential or mock HTTP transport.
final class MatrixMessagingRelayIntegrationTests: XCTestCase {
    @MainActor private var stage = "CONFIGURATION"

    /// Closed vocabulary only, never arbitrary SDK descriptions or identifiers.
    @MainActor
    private func safeDiagnostic() -> String {
        guard let code = MessagingDiagnostics.shared.last else { return "NONE" }
        if ["D-NOKEY", "D-MEGOLM", "D-UNKNOWN", "D-MISMATCH", "D-UNTRUSTED"].contains(code) { return code }
        let parts = code.split(separator: "-").map(String.init)
        let routes = ["MEMBERS", "UPLOAD", "QUERY", "CLAIM", "SEND", "MSG", "CONV", "SIGN", "SYNC", "BKVER", "BKKEYS", "TODEVICE", "OTHER"]
        if parts.count == 3, parts[0] == "H", routes.contains(parts[1]),
           ["NET", "TYPE", "CTX", "BODY"].contains(parts[2]) || (400...599).contains(Int(parts[2]) ?? 0) {
            return code
        }
        if code.hasPrefix("SDK-") { return "SDK" }
        if code.hasPrefix("K-") { return "KEYCHAIN" }
        if code.hasPrefix("S-") || code.hasPrefix("SQL-") { return "STORE" }
        return "OTHER"
    }

    @MainActor
    private func enter(_ next: String) {
        stage = next
        MessagingDiagnostics.shared.clear()
    }

    @MainActor
    func testRealRelayExchangeIdempotenceRecoveryAndContextRefusal() async {
        enter("CONFIGURATION")
        do { try await exerciseRealRelay() }
        catch { XCTFail("Relais interrompu : étape=\(stage), diagnostic=\(safeDiagnostic()).") }
    }

    @MainActor
    private func exerciseRealRelay() async throws {
        let configured = ProcessInfo.processInfo.environment["DRIVY_RELAY_QUALIFICATION_URL"]
        guard let configured, let base = URL(string: configured),
              base.scheme == "https", ["localhost", "127.0.0.1"].contains(base.host ?? ""),
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.path.isEmpty, let port = base.port, (1024...65535).contains(port) else {
            XCTFail("Relais HTTPS loopback isolé obligatoire, configuration de qualification absente ou invalide.")
            return
        }
        let school = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let otherSchool = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let instructor = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        let learner = UUID(uuidString: "20000000-0000-4000-8000-000000000003")!
        let aScope = MessagingScope(accountID: instructor, schoolID: school, accessEpoch: 1, apiBaseURL: base.absoluteString)
        let bScope = MessagingScope(accountID: learner, schoolID: school, accessEpoch: 1, apiBaseURL: base.absoluteString)
        let aToken = "demo-instructor", bToken = "demo-alice"
        let aHTTP = MessagingHTTPTransport(baseURL: base, token: { aToken }, invalidate: { _ in false }, currentScope: { aScope })
        let bHTTP = MessagingHTTPTransport(baseURL: base, token: { bToken }, invalidate: { _ in false }, currentScope: { bScope })
        let aRelay = MessagingCryptoHTTPRelay(baseURL: base, token: { aToken }, invalidate: { _ in false }, currentScope: { aScope })
        let bRelay = MessagingCryptoHTTPRelay(baseURL: base, token: { bToken }, invalidate: { _ in false }, currentScope: { bScope })

        // Readiness proves that this is our disposable fixture server, not merely an open port.
        enter("READINESS")
        let readiness = try await SchoolURLSessionTransport().send(URLRequest(url: base.appendingPathComponent("qualification/ready")))
        guard readiness.status == 200,
              let ready = try JSONSerialization.jsonObject(with: readiness.data) as? [String: Any],
              ready["fixture"] as? String == "drivy-messaging-relay-v1",
              ready["schoolId"] as? String == school.uuidString.lowercased(),
              ready["instructorId"] as? String == instructor.uuidString.lowercased(),
              ready["learnerId"] as? String == learner.uuidString.lowercased() else {
            XCTFail("Le relais ne correspond pas aux fixtures canoniques de qualification.")
            return
        }
        enter("CONVERSATION")
        let conversation = try await aHTTP.privateConversation(scope: aScope, peerID: learner)
        let run = UUID().uuidString
        let aKeychain = RelayQualificationKeychain(namespace: "\(run).A")
        let bKeychain = RelayQualificationKeychain(namespace: "\(run).B")
        let cKeychain = RelayQualificationKeychain(namespace: "\(run).C")
        defer { aKeychain.removeFixture(); bKeychain.removeFixture(); cKeychain.removeFixture() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("relay-qualification-\(run)", isDirectory: true)
        // Separate real Keychain namespaces are necessary: root alone does not change vault identity.
        enter("VAULTS")
        let aVault = try MessagingCryptoVault(scope: aScope, root: root.appendingPathComponent("A"), keychain: aKeychain)
        let bVault = try MessagingCryptoVault(scope: bScope, root: root.appendingPathComponent("B"), keychain: bKeychain)
        let cVault = try MessagingCryptoVault(scope: bScope, root: root.appendingPathComponent("C"), keychain: cKeychain)
        let a = try MatrixMessagingCryptography(scope: aScope, relay: aRelay, vault: aVault)
        let b = try MatrixMessagingCryptography(scope: bScope, relay: bRelay, vault: bVault)
        enter("B-KEYS-UPLOAD")
        let bReady = await b.isAvailable(scope: bScope, conversationID: conversation)
        guard bReady else { XCTFail("Publication clés B impossible : diagnostic=\(safeDiagnostic())."); return }

        let plaintext = Data("SYNTHETIC_RELAY_MESSAGE_\(run)".utf8)
        enter("A-ENCRYPT-MEMBERS-QUERY-CLAIM")
        let encrypted = try await a.encrypt(plaintext, mentions: [], scope: aScope, conversationID: conversation)
        XCTAssertFalse(encrypted.payload.range(of: plaintext) != nil, "Le transport ne doit pas contenir le texte synthétique.")
        let body = MessagingSendDTO(clientMessageId: UUID(), ciphertext: encrypted, mentionPersonIds: [])
        enter("SEND")
        let ack = try await aHTTP.send(scope: aScope, conversationID: conversation, body: body)
        enter("SEND-IDEMPOTENCE")
        let repeated = try await aHTTP.send(scope: aScope, conversationID: conversation, body: body)
        XCTAssertTrue(ack.serverMessageId == repeated.serverMessageId, "La répétition doit retourner le même reçu durable.")
        enter("B-FETCH")
        let page = try await MessagingAPIClient(transport: bHTTP).messages(scope: bScope, conversationID: conversation, before: nil)
        let matching = page.items.filter { $0.id == ack.serverMessageId }
        guard matching.count == 1, let message = matching.first else {
            XCTFail("Le destinataire doit relire exactement une enveloppe acceptée via les routes réelles."); return
        }
        enter("B-DECRYPT")
        let received = try await b.decrypt(message, scope: bScope)
        XCTAssertTrue(received == plaintext, "Le destinataire doit déchiffrer l'enveloppe relue du serveur.")

        // Backup after reception tests real upload/download/import, not only recovery-key encoding.
        enter("B-BACKUP")
        let recoveryKey = try await b.enableBackup(scope: bScope)
        enter("C-NEW-DEVICE")
        let c = try MatrixMessagingCryptography(scope: bScope, relay: bRelay, vault: cVault)
        let bSecrets = try bVault.secrets(), cSecrets = try cVault.secrets()
        XCTAssertTrue(bSecrets.deviceID != cSecrets.deviceID, "C doit être un appareil distinct sans anciennes clés.")
        do {
            _ = try await c.decrypt(message, scope: bScope)
            XCTFail("Un appareil vierge ne doit pas lire l'historique sans récupération.")
        } catch {
            XCTAssertTrue(error as? MessagingDecryptionFailure == MessagingDecryptionFailure(code: "D-NOKEY"), "L'appareil vierge doit échouer exactement avec D-NOKEY.")
        }
        enter("C-WRONG-RECOVERY-KEY")
        let wrongKey = BackupRecoveryKey().toBase58()
        do {
            _ = try await c.restoreBackup(recoveryKey: wrongKey, scope: bScope)
            XCTFail("Une clé valide mais étrangère doit être refusée.")
        } catch {
            XCTAssertTrue(error as? MessagingFailure == .protectionUnavailable, "La mauvaise clé doit être refusée sans divulgation.")
        }
        enter("C-RESTORE")
        let restored = try await c.restoreBackup(recoveryKey: recoveryKey, scope: bScope)
        XCTAssertTrue(restored.imported > 0 && restored.failed == 0, "La sauvegarde réelle doit importer des sessions.")
        enter("C-DECRYPT-RESTORED")
        let recovered = try await c.decrypt(message, scope: bScope)
        XCTAssertTrue(recovered == plaintext, "C doit retrouver le message via les clés restaurées du serveur.")

        // Internally consistent client scope, but credential belongs to B: refusal must come from the server.
        enter("REFUSE-ACTOR")
        let wrongActorRelay = MessagingCryptoHTTPRelay(baseURL: base, token: { bToken }, invalidate: { _ in false }, currentScope: { aScope })
        do {
            _ = try await wrongActorRelay.call(scope: aScope, deviceID: cSecrets.deviceID, method: "GET", path: ["sync"], query: [], body: nil)
            XCTFail("Le serveur doit refuser une personne attendue différente du jeton.")
        } catch {
            XCTAssertTrue(error as? MessagingFailure == .accessChanged, "Le refus de contexte doit provenir des droits serveur.")
        }
        enter("REFUSE-SCHOOL")
        let foreignScope = MessagingScope(accountID: learner, schoolID: otherSchool, accessEpoch: 1, apiBaseURL: base.absoluteString)
        let foreignRelay = MessagingCryptoHTTPRelay(baseURL: base, token: { bToken }, invalidate: { _ in false }, currentScope: { foreignScope })
        do {
            _ = try await foreignRelay.call(scope: foreignScope, deviceID: cSecrets.deviceID, method: "GET", path: ["sync"], query: [], body: nil)
            XCTFail("Le serveur doit refuser l'école sans appartenance.")
        } catch {
            XCTAssertTrue(error as? MessagingFailure == .accessChanged, "L'école étrangère doit être refusée par le serveur.")
        }
        // No values, keys, tokens, event JSON or SDK errors are printed by this test.
        // The simulator is disposable. Protected stores stay outside uploaded artifacts.
    }
}

/// Isolates three devices while exercising the real system Keychain, not an in-memory substitute.
private struct RelayQualificationKeychain: MessagingCryptoKeychain {
    let namespace: String
    private var fixtureService: String { "ch.drivy.qualification.relay.\(namespace)" }
    func read(service: String, account: String) throws -> Data? {
        try MessagingSystemKeychain().read(service: fixtureService, account: account)
    }
    func add(service: String, account: String, data: Data) throws {
        try MessagingSystemKeychain().add(service: fixtureService, account: account, data: data)
    }
    func removeFixture() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: fixtureService] as CFDictionary)
    }
}
