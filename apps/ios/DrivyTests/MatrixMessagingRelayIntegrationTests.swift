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
        let aRelay = RelayQualificationSyncObserver(upstream: MessagingCryptoHTTPRelay(
            baseURL: base, token: { aToken }, invalidate: { _ in false }, currentScope: { aScope }))
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

        // Physical regression: A has already shared a General session while B has no device keys.
        // Keep these same FFI instances alive. Do not discard the room key or reopen A to hide a stale cache.
        enter("GENERAL-BEFORE-B-REGISTRATION")
        let general = try await aHTTP.generalConversation(scope: aScope)
        let aReady = await a.isAvailable(scope: aScope, conversationID: general)
        guard aReady else { XCTFail("Publication clés A impossible : diagnostic=\(safeDiagnostic())."); return }
        let aDevice = try aVault.secrets().deviceID
        let learnerUser = MatrixMessagingCryptography.userID(learner)
        let queryBody = try JSONSerialization.data(withJSONObject: ["device_keys": [learnerUser: [String]()]])
        let beforeKeys = try await aRelay.call(scope: aScope, deviceID: aDevice, method: "POST",
                                               path: ["keys", "query"], query: [], body: queryBody)
        guard let beforeObject = try JSONSerialization.jsonObject(with: beforeKeys) as? [String: Any],
              let beforeDevices = beforeObject["device_keys"] as? [String: [String: Any]],
              (beforeDevices[learnerUser] ?? [:]).isEmpty else {
            XCTFail("Précondition invalide : B doit être sans clés publiées avant le premier envoi Général."); return
        }
        let earlyText = Data("SYNTHETIC_GENERAL_BEFORE_REGISTRATION".utf8)
        let earlyCiphertext = try await a.encrypt(earlyText, mentions: [], scope: aScope, conversationID: general)
        let earlyAck = try await aHTTP.send(scope: aScope, conversationID: general,
            body: MessagingSendDTO(clientMessageId: UUID(), ciphertext: earlyCiphertext, mentionPersonIds: []))
        // A has a durable message and an existing Megolm session before any B SDK open/upload.
        let earlyPage = try await MessagingAPIClient(transport: aHTTP).messages(scope: aScope, conversationID: general, before: nil)
        guard earlyPage.items.contains(where: { $0.id == earlyAck.serverMessageId }) else {
            XCTFail("Le premier message Général doit être relu du serveur avant inscription B."); return
        }
        await aRelay.clearObservedChanges()

        enter("B-KEYS-UPLOAD")
        let bGeneral = try await bHTTP.generalConversation(scope: bScope)
        guard bGeneral == general else { XCTFail("A et B doivent rejoindre le même Général."); return }
        let bReady = await b.isAvailable(scope: bScope, conversationID: conversation)
        guard bReady else { XCTFail("Publication clés B impossible : diagnostic=\(safeDiagnostic())."); return }

        enter("GENERAL-A-SEND-AFTER-B-REGISTRATION")
        let lateText = Data("SYNTHETIC_GENERAL_AFTER_REGISTRATION".utf8)
        let lateCiphertext = try await a.encrypt(lateText, mentions: [], scope: aScope, conversationID: general)
        let observedBChange = await aRelay.observedChange(for: learnerUser)
        XCTAssertTrue(observedBChange, "Le sync réel consommé par A doit annoncer B dans device_lists.changed après son inscription.")
        XCTAssertTrue(lateCiphertext.keyID == earlyCiphertext.keyID,
                      "Le nouvel appareil doit recevoir la session Général déjà ouverte, sans rotation forcée par le test.")
        let lateAck = try await aHTTP.send(scope: aScope, conversationID: general,
            body: MessagingSendDTO(clientMessageId: UUID(), ciphertext: lateCiphertext, mentionPersonIds: []))
        enter("GENERAL-B-LATE-DECRYPT")
        let latePage = try await MessagingAPIClient(transport: bHTTP).messages(scope: bScope, conversationID: general, before: nil)
        guard let lateMessage = latePage.items.first(where: { $0.id == lateAck.serverMessageId }) else {
            XCTFail("B doit relire le nouveau message Général via PostgreSQL."); return
        }
        let lateReceived = try await b.decrypt(lateMessage, scope: bScope)
        XCTAssertTrue(lateReceived == lateText, "B inscrit tardivement doit déchiffrer le nouveau message Général.")

        // Alternate accounts/FFI instances on the same General without clearing either protected store.
        enter("GENERAL-B-REPLY")
        let replyText = Data("SYNTHETIC_GENERAL_REPLY_FROM_B".utf8)
        let replyCiphertext = try await b.encrypt(replyText, mentions: [], scope: bScope, conversationID: general)
        let replyAck = try await bHTTP.send(scope: bScope, conversationID: general,
            body: MessagingSendDTO(clientMessageId: UUID(), ciphertext: replyCiphertext, mentionPersonIds: []))
        enter("GENERAL-A-REPLY-DECRYPT")
        let replyPage = try await MessagingAPIClient(transport: aHTTP).messages(scope: aScope, conversationID: general, before: nil)
        guard let replyMessage = replyPage.items.first(where: { $0.id == replyAck.serverMessageId }) else {
            XCTFail("A doit relire la réponse Général du compte B."); return
        }
        let replyReceived = try await a.decrypt(replyMessage, scope: aScope)
        XCTAssertTrue(replyReceived == replyText, "Le retour B vers A doit rester déchiffrable après alternance de comptes.")

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
            XCTAssertTrue(error as? MessagingFailure == .recoveryKeyRefused, "La mauvaise clé doit être refusée sans divulgation.")
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

/// Passive observation of actual HTTP sync responses. No fabricated response, extra sync or SDK injection.
/// In particular, observing changed must not consume a cursor before the production FFI receives it.
private actor RelayQualificationSyncObserver: MessagingCryptoRelay {
    let upstream: MessagingCryptoHTTPRelay
    private var changedUsers = Set<String>()

    init(upstream: MessagingCryptoHTTPRelay) { self.upstream = upstream }

    func call(scope: MessagingScope, deviceID: String, method: String, path: [String],
              query: [URLQueryItem], body: Data?) async throws -> Data {
        let raw = try await upstream.call(scope: scope, deviceID: deviceID, method: method,
                                          path: path, query: query, body: body)
        if method == "GET", path == ["sync"], let page = try? MatrixMessagingCryptography.syncPage(raw) {
            changedUsers.formUnion(page.changed)
        }
        return raw
    }

    func members(scope: MessagingScope, deviceID: String, conversationID: UUID) async throws -> MessagingConversationMembers {
        try await upstream.members(scope: scope, deviceID: deviceID, conversationID: conversationID)
    }

    func clearObservedChanges() { changedUsers.removeAll() }
    func observedChange(for user: String) -> Bool { changedUsers.contains(user) }
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
