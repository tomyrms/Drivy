import Foundation
import Security
import XCTest
import MatrixSDKCrypto
@testable import Drivy

/// Vocabulaire fermé : seules une catégorie et des codes URLError connus sont exposés.
private enum RelayTransportCategory: String {
    case tls = "TLS"
    case ats = "ATS"
    case connect = "CONNECT"
    case timeout = "TIMEOUT"
    case cancelled = "CANCELLED"
    case other = "OTHER"
}

private struct RelayTransportDiagnostic {
    let category: RelayTransportCategory
    let code: Int?

    var text: String {
        guard let code else { return category.rawValue }
        return "\(category.rawValue) code=\(code)"
    }
}

/// Classifie sans lire localizedDescription, userInfo, URL, corps, en-tête ni certificat.
private func relayTransportDiagnostic(for error: any Error) -> RelayTransportDiagnostic {
    if error is CancellationError {
        return RelayTransportDiagnostic(category: .cancelled, code: nil)
    }
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else {
        return RelayTransportDiagnostic(category: .other, code: nil)
    }
    switch nsError.code {
    case (-1206)...(-1200):
        return RelayTransportDiagnostic(category: .tls, code: nsError.code)
    case -1022:
        return RelayTransportDiagnostic(category: .ats, code: nsError.code)
    case -1004, -1005:
        return RelayTransportDiagnostic(category: .connect, code: nsError.code)
    case -1001:
        return RelayTransportDiagnostic(category: .timeout, code: nsError.code)
    case -999:
        return RelayTransportDiagnostic(category: .cancelled, code: nsError.code)
    default:
        return RelayTransportDiagnostic(category: .other, code: nil)
    }
}

/// Diagnostic de readiness borné : statut HTTP et nom fermé du champ divergent, jamais sa valeur.
private struct RelayReadinessMismatch {
    enum Field: String {
        case type
        case fixture
        case schoolId
        case instructorId
        case learnerId
    }

    let status: Int
    let field: Field?

    var text: String {
        guard let field else { return "statut=\(status)" }
        return "statut=\(status) champ=\(field.rawValue)"
    }
}

private func relayReadinessMismatch(status: Int, data: Data, schoolID: UUID,
                                    instructorID: UUID, learnerID: UUID) -> RelayReadinessMismatch? {
    let boundedStatus = (100...599).contains(status) ? status : 0
    guard let raw = try? JSONSerialization.jsonObject(with: data),
          let object = raw as? [String: Any] else {
        return RelayReadinessMismatch(status: boundedStatus, field: .type)
    }
    let expected: [(RelayReadinessMismatch.Field, String, String)] = [
        (.fixture, "fixture", "drivy-messaging-relay-v1"),
        (.schoolId, "schoolId", schoolID.uuidString.lowercased()),
        (.instructorId, "instructorId", instructorID.uuidString.lowercased()),
        (.learnerId, "learnerId", learnerID.uuidString.lowercased())
    ]
    for (field, key, value) in expected where (object[key] as? String) != value {
        return RelayReadinessMismatch(status: boundedStatus, field: field)
    }
    return boundedStatus == 200 ? nil : RelayReadinessMismatch(status: boundedStatus, field: nil)
}

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

    /// Sonde de readiness : transport réel inchangé, seul l'observateur de phases est activé.
    /// Même MainActor que son appelant : aucune valeur non Sendable ne traverse de frontière.
    @MainActor
    private func sendReadiness(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        #if DEBUG && targetEnvironment(simulator)
        let probe = RelayReadinessPhaseProbe { markers in
            // Sink fermé : uniquement des marqueurs, jamais une requête, une erreur ou un objet du test.
            print("L2 readiness phases (callback) : " + markers.joined(separator: " "))
        }
        do {
            let response = try await SchoolURLSessionTransport(readinessPhaseProbe: probe).send(request)
            printReadinessPhaseObservation(probe)
            return response
        } catch {
            printReadinessPhaseObservation(probe)
            throw error
        }
        #else
        return try await SchoolURLSessionTransport().send(request)
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Lecture immédiate après le send, sans attente : `pending` reste temporel, jamais « jamais reçu ».
    @MainActor
    private func printReadinessPhaseObservation(_ probe: RelayReadinessPhaseProbe) {
        switch probe.immediate {
        case .pending:
            print("L2 readiness phases : R-METRICS-PENDING")
        case .received(let markers):
            print("L2 readiness phases : " + markers.joined(separator: " "))
        }
    }
    #endif

    @MainActor
    func testRealRelayExchangeIdempotenceRecoveryAndContextRefusal() async {
        enter("CONFIGURATION")
        do { try await exerciseRealRelay() }
        catch {
            let transport = relayTransportDiagnostic(for: error).text
            XCTFail("Relais interrompu : étape=\(stage), diagnostic=\(safeDiagnostic()), transport=\(transport).")
        }
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
        let readinessRequest = URLRequest(url: base.appendingPathComponent("qualification/ready"))
        let readiness: SchoolHTTPResponse
        do { readiness = try await sendReadiness(readinessRequest) }
        catch where RelayReadinessWait.isTransient(error) {
            // Premier essai (avec phases observées) perdu sur un runner chargé : attente bornée, voir RelayReadinessWait.
            readiness = try await RelayReadinessWait.retry(readinessRequest)
        }
        if let mismatch = relayReadinessMismatch(status: readiness.status, data: readiness.data,
                                                schoolID: school, instructorID: instructor, learnerID: learner) {
            XCTFail("Le relais ne correspond pas aux fixtures canoniques de qualification : \(mismatch.text).")
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

/// Tests locaux du vocabulaire de diagnostic. Aucune requête, aucun relais, aucun secret.
final class RelayReadinessDiagnosticTests: XCTestCase {
    private let school = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let instructor = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    private let learner = UUID(uuidString: "20000000-0000-4000-8000-000000000003")!

    private func readinessData(overrides: [String: Any] = [:]) throws -> Data {
        var fixture: [String: Any] = [
            "fixture": "drivy-messaging-relay-v1",
            "schoolId": school.uuidString.lowercased(),
            "instructorId": instructor.uuidString.lowercased(),
            "learnerId": learner.uuidString.lowercased()
        ]
        for (key, value) in overrides { fixture[key] = value }
        return try JSONSerialization.data(withJSONObject: fixture)
    }

    private func mismatch(status: Int = 200, data: Data) -> RelayReadinessMismatch? {
        relayReadinessMismatch(status: status, data: data, schoolID: school,
                               instructorID: instructor, learnerID: learner)
    }

    func testKnownURLErrorCodesUseClosedTransportCategories() {
        let cases: [(Int, String)] = [
            (-1200, "TLS code=-1200"),
            (-1202, "TLS code=-1202"),
            (-1206, "TLS code=-1206"),
            (-1022, "ATS code=-1022"),
            (-1004, "CONNECT code=-1004"),
            (-1005, "CONNECT code=-1005"),
            (-1001, "TIMEOUT code=-1001"),
            (-999, "CANCELLED code=-999")
        ]
        for (code, expected) in cases {
            let error = NSError(domain: NSURLErrorDomain, code: code)
            XCTAssertEqual(relayTransportDiagnostic(for: error).text, expected)
        }
    }

    func testCancellationAndUnknownErrorsStayInTheClosedVocabulary() {
        XCTAssertEqual(relayTransportDiagnostic(for: CancellationError()).text, "CANCELLED")
        XCTAssertEqual(relayTransportDiagnostic(for: NSError(domain: NSURLErrorDomain, code: -1003)).text, "OTHER")
        XCTAssertEqual(relayTransportDiagnostic(for: NSError(domain: "SyntheticDomain", code: -1202)).text, "OTHER")
    }

    func testTransportDiagnosticNeverLeaksURLTokenNameOrCertificate() throws {
        let url = try XCTUnwrap(URL(string: "https://127.0.0.1:18443/qualification/ready?token=SENTINEL_TOKEN"))
        let error = NSError(domain: NSURLErrorDomain, code: -1202, userInfo: [
            NSURLErrorFailingURLErrorKey: url,
            NSLocalizedDescriptionKey: "SENTINEL_NAME",
            "certificate": "SENTINEL_CERTIFICATE"
        ])
        let text = relayTransportDiagnostic(for: error).text
        XCTAssertEqual(text, "TLS code=-1202")
        for sentinel in ["SENTINEL_TOKEN", "SENTINEL_NAME", "SENTINEL_CERTIFICATE", "127.0.0.1"] {
            XCTAssertFalse(text.contains(sentinel))
        }
    }

    func testReadinessAcceptsOnlyTheExactCanonicalFixture() throws {
        XCTAssertNil(mismatch(data: try readinessData()))
    }

    func testMalformedReadinessReportsOnlyStatusAndType() {
        let malformed = Data("{not-json".utf8)
        XCTAssertEqual(mismatch(data: malformed)?.text, "statut=200 champ=type")
    }

    func testEachDivergentFieldIsNamedWithoutItsValue() throws {
        let cases: [(String, Any, String)] = [
            ("fixture", "SENTINEL_FIXTURE", "statut=200 champ=fixture"),
            ("schoolId", "SENTINEL_SCHOOL", "statut=200 champ=schoolId"),
            ("instructorId", "SENTINEL_INSTRUCTOR", "statut=200 champ=instructorId"),
            ("learnerId", "SENTINEL_LEARNER", "statut=200 champ=learnerId"),
            ("fixture", 7_654_321, "statut=200 champ=fixture")
        ]
        for (key, value, expected) in cases {
            let text = mismatch(data: try readinessData(overrides: [key: value]))?.text ?? ""
            XCTAssertEqual(text, expected)
            XCTAssertFalse(text.contains("SENTINEL"))
            XCTAssertFalse(text.contains("7654321"))
        }
    }

    func testNonSuccessStatusIsBoundedAndDoesNotInventAField() throws {
        XCTAssertEqual(mismatch(status: 503, data: try readinessData())?.text, "statut=503")
        XCTAssertEqual(mismatch(status: 0, data: try readinessData())?.text, "statut=0")
        XCTAssertEqual(mismatch(status: 999, data: try readinessData())?.text, "statut=0")
    }

    func testReadinessDiagnosticNeverLeaksFixtureValues() throws {
        let data = try readinessData(overrides: ["learnerId": "SENTINEL_LEARNER_VALUE"])
        let text = mismatch(data: data)?.text ?? ""
        XCTAssertEqual(text, "statut=200 champ=learnerId")
        XCTAssertFalse(text.contains("SENTINEL_LEARNER_VALUE"))
        XCTAssertFalse(text.contains(school.uuidString.lowercased()))
    }

    #if DEBUG && targetEnvironment(simulator)
    // MARK: Phases de readiness (instrumentation opt-in, sans réseau)

    /// Sink synthétique : ne garde que des marqueurs fermés, jamais une requête, une erreur ou un objet du test.
    private final class ReadinessMarkerSink: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [[String]] = []
        var captured: [[String]] { lock.withLock { lines } }
        func receive(_ markers: [String]) { lock.withLock { lines.append(markers) } }
    }

    func testReadinessPhaseMarkersStayClosedAndBounded() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let times = RelayReadinessPhaseTimes(
            fetchStart: start,
            connectStart: start.addingTimeInterval(0.010),
            connectEnd: start.addingTimeInterval(0.020),
            secureConnectionStart: start.addingTimeInterval(0.022),
            secureConnectionEnd: start.addingTimeInterval(0.030),
            requestStart: start.addingTimeInterval(0.031),
            requestEnd: start.addingTimeInterval(0.032),
            responseStart: start.addingTimeInterval(0.033),
            responseEnd: start.addingTimeInterval(0.040))

        let markers = RelayReadinessPhaseMarkers.make(times)

        XCTAssertEqual(markers, ["R-CONNECT-MS-10", "R-TLS-MS-8", "R-REQUEST-MS-1",
                                 "R-RESPONSE-MS-7", "R-TOTAL-MS-40", "R-TXN-1"])
        // Le vocabulaire fermé interdit dates absolues, URL, hôte et ponctuation.
        for marker in markers {
            XCTAssertTrue(MessagingDiagnostics.isSafe(marker), "Marqueur hors vocabulaire : \(marker)")
        }

        // Borne réellement exercée : saturation, négatif et non fini.
        XCTAssertEqual(RelayReadinessPhaseMarkers.milliseconds(700), 600_000)
        XCTAssertEqual(RelayReadinessPhaseMarkers.milliseconds(-1), 0)
        XCTAssertEqual(RelayReadinessPhaseMarkers.milliseconds(.infinity), 600_000)

        // Nombre de transactions borné : 9 signifie « 9 ou plus », jamais une valeur brute.
        let many = RelayReadinessPhaseTimes(fetchStart: start, transactionCount: 42)
        XCTAssertEqual(RelayReadinessPhaseMarkers.make(many).last, "R-TXN-9")
    }

    func testReadinessPhaseMarkersCoverMissingPartialAndInvalidTimestamps() {
        // Métriques reçues sans transaction : distinct de « pas encore de callback ».
        XCTAssertEqual(RelayReadinessPhaseMarkers.make(nil), ["R-TRANSACTION-NONE"])
        XCTAssertEqual(RelayReadinessPhaseMarkers.make(RelayReadinessPhaseTimes()),
                       ["R-CONNECT-ABSENT", "R-TLS-ABSENT", "R-REQUEST-ABSENT",
                        "R-RESPONSE-ABSENT", "R-TOTAL-ABSENT", "R-TXN-1"])

        let start = Date(timeIntervalSinceReferenceDate: 2_000)

        // Fin publiée sans début : incohérence annoncée, jamais une absence.
        let orphanConnect = RelayReadinessPhaseMarkers.make(
            RelayReadinessPhaseTimes(fetchStart: start, connectEnd: start.addingTimeInterval(0.005)))
        XCTAssertTrue(orphanConnect.contains("R-CONNECT-INVALID"))
        XCTAssertTrue(orphanConnect.contains("R-TOTAL-INCOMPLETE"))

        let orphanTotal = RelayReadinessPhaseMarkers.make(
            RelayReadinessPhaseTimes(responseEnd: start.addingTimeInterval(0.005)))
        XCTAssertTrue(orphanTotal.contains("R-TOTAL-INVALID"))

        let inverted = RelayReadinessPhaseTimes(
            fetchStart: start,
            connectStart: start.addingTimeInterval(0.050),
            connectEnd: start.addingTimeInterval(0.040),
            requestStart: start.addingTimeInterval(0.051),
            requestEnd: start.addingTimeInterval(0.052))
        let invertedMarkers = RelayReadinessPhaseMarkers.make(inverted)
        XCTAssertTrue(invertedMarkers.contains("R-CONNECT-INVALID"))
        XCTAssertTrue(invertedMarkers.contains("R-RESPONSE-ABSENT"))
        XCTAssertTrue(invertedMarkers.contains("R-TOTAL-INCOMPLETE"))
        for marker in invertedMarkers {
            XCTAssertTrue(MessagingDiagnostics.isSafe(marker), "Marqueur hors vocabulaire : \(marker)")
        }

        // Un début seul et fini reste incomplet ; une date non finie est invalide.
        let startedOnly = RelayReadinessPhaseMarkers.make(
            RelayReadinessPhaseTimes(fetchStart: start, requestStart: start))
        XCTAssertTrue(startedOnly.contains("R-REQUEST-INCOMPLETE"))

        let infiniteStart = RelayReadinessPhaseMarkers.make(
            RelayReadinessPhaseTimes(fetchStart: start,
                                     connectStart: start.addingTimeInterval(.infinity),
                                     connectEnd: start.addingTimeInterval(0.001)))
        XCTAssertTrue(infiniteStart.contains("R-CONNECT-INVALID"))

        let infiniteEnd = RelayReadinessPhaseMarkers.make(
            RelayReadinessPhaseTimes(fetchStart: start,
                                     connectStart: start,
                                     connectEnd: start.addingTimeInterval(.infinity)))
        XCTAssertTrue(infiniteEnd.contains("R-CONNECT-INVALID"))

        let reused = RelayReadinessPhaseTimes(
            fetchStart: start,
            requestStart: start,
            requestEnd: start.addingTimeInterval(0.002),
            responseStart: start.addingTimeInterval(0.002),
            responseEnd: start.addingTimeInterval(0.004),
            reusedConnection: true)
        let reusedMarkers = RelayReadinessPhaseMarkers.make(reused)
        XCTAssertEqual(reusedMarkers.first, "R-CONN-REUSED")
        XCTAssertFalse(reusedMarkers.contains { $0.hasPrefix("R-TLS") || $0.hasPrefix("R-CONNECT-MS") })
    }

    func testReadinessPhaseFilterAcceptsOnlyTheQualificationProbe() throws {
        func request(_ raw: String, method: String? = nil, authorization: String? = nil) throws -> URLRequest {
            var request = URLRequest(url: try XCTUnwrap(URL(string: raw)))
            if let method { request.httpMethod = method }
            if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
            return request
        }

        XCTAssertTrue(RelayReadinessPhaseGuard.accepts(try request("https://127.0.0.1:18443/qualification/ready")))
        XCTAssertTrue(RelayReadinessPhaseGuard.accepts(
            try request("https://localhost:18443/qualification/ready", method: "GET")))

        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(nil))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("http://127.0.0.1:18443/qualification/ready")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("https://example.invalid/qualification/ready")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("https://127.0.0.1:18443/qualification/other")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("https://127.0.0.1:18443/qualification/ready/extra")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("https://127.0.0.1:18443/qualification/ready?tenant=1")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("https://127.0.0.1:18443/qualification/ready#fragment")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(
            try request("https://user:secret@127.0.0.1:18443/qualification/ready")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("https://127.0.0.1:18443/qualification/ready", method: "POST")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(
            try request("https://127.0.0.1:18443/qualification/ready", authorization: "Bearer SENTINEL_TOKEN")))
        XCTAssertFalse(RelayReadinessPhaseGuard.accepts(try request("https://127.0.0.1:80/qualification/ready")))
    }

    func testReadinessPhaseProbeStaysPendingUntilCallbackAndKeepsLateObservation() throws {
        let sink = ReadinessMarkerSink()
        let probe = RelayReadinessPhaseProbe { sink.receive($0) }
        let accepted = URLRequest(url: try XCTUnwrap(URL(string: "https://127.0.0.1:18443/qualification/ready")))
        let start = Date(timeIntervalSinceReferenceDate: 4_000)
        let first = RelayReadinessPhaseTimes(
            fetchStart: start,
            requestStart: start,
            requestEnd: start.addingTimeInterval(0.004),
            responseStart: start.addingTimeInterval(0.004),
            responseEnd: start.addingTimeInterval(0.009),
            reusedConnection: true)
        let second = RelayReadinessPhaseTimes(
            fetchStart: start,
            requestStart: start,
            requestEnd: start.addingTimeInterval(0.100),
            responseStart: start.addingTimeInterval(0.100),
            responseEnd: start.addingTimeInterval(0.200),
            reusedConnection: true)

        // Aucun callback à cet instant : temporel, jamais une absence définitive.
        XCTAssertEqual(probe.immediate, .pending)
        XCTAssertTrue(sink.captured.isEmpty)

        // Callback tardif : la mesure est conservée et émise une seule fois.
        probe.record(first, request: accepted)
        XCTAssertEqual(probe.immediate, .received(RelayReadinessPhaseMarkers.make(first)))
        XCTAssertEqual(sink.captured, [RelayReadinessPhaseMarkers.make(first)])

        // Callback répété : ni réémission, ni écrasement de la première observation.
        probe.record(second, request: accepted)
        XCTAssertEqual(sink.captured.count, 1)
        XCTAssertEqual(probe.immediate, .received(RelayReadinessPhaseMarkers.make(first)))
    }

    func testReadinessPhaseProbesKeepSeparateObservations() throws {
        let sinkA = ReadinessMarkerSink()
        let sinkB = ReadinessMarkerSink()
        let probeA = RelayReadinessPhaseProbe { sinkA.receive($0) }
        let probeB = RelayReadinessPhaseProbe { sinkB.receive($0) }
        let accepted = URLRequest(url: try XCTUnwrap(URL(string: "https://127.0.0.1:18443/qualification/ready")))
        let other = URLRequest(url: try XCTUnwrap(URL(string: "https://127.0.0.1:18443/other")))
        let start = Date(timeIntervalSinceReferenceDate: 5_000)
        let times = RelayReadinessPhaseTimes(
            fetchStart: start,
            requestStart: start,
            requestEnd: start.addingTimeInterval(0.003),
            responseStart: start.addingTimeInterval(0.003),
            responseEnd: start.addingTimeInterval(0.006),
            reusedConnection: true)

        probeA.record(times, request: accepted)
        probeB.record(times, request: other) // requête hors périmètre : ni observation, ni émission

        XCTAssertEqual(sinkA.captured.count, 1)
        XCTAssertTrue(sinkB.captured.isEmpty)
        XCTAssertEqual(probeB.immediate, .pending)
        XCTAssertNotEqual(probeA.immediate, probeB.immediate)
    }
    #endif
}
