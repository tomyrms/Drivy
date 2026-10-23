import Foundation
import CryptoKit
import Security
import MatrixSDKCrypto

/// Gestion des clés visible par l'utilisateur : sauvegarde par clé de récupération et appareils du compte.
protocol MessagingKeyManagement: Sendable {
    /// Crée une sauvegarde serveur. Renvoie la clé de récupération à montrer UNE fois à l'utilisateur.
    func enableBackup(scope: MessagingScope) async throws -> String
    /// Restaure l'historique sur un nouvel appareil avec la clé de récupération saisie.
    func restoreBackup(recoveryKey: String, scope: MessagingScope) async throws -> Int
    func ownDevices(scope: MessagingScope) async throws -> [MessagingOwnDevice]
    /// À appeler seulement après comparaison visuelle de l'empreinte affichée sur les deux appareils.
    func confirmOwnDevice(deviceID: String, fingerprint: String, scope: MessagingScope) async throws
}

struct MessagingOwnDevice: Sendable, Hashable, Identifiable {
    let id: String
    let fingerprint: String
    let isCurrent: Bool
    let isVerified: Bool
}

/// Chiffrement de bout en bout #67 : Olm/Megolm de matrix-sdk-crypto (vodozemac), transport API Drivy.
/// Aucun chemin ne renvoie ou n'envoie de clair : toute erreur devient `protectionUnavailable`.
actor MatrixMessagingCryptography: MessagingCryptography, MessagingKeyManagement {
    static let scheme = "megolm.v1"
    static let serverName = "drivy"
    /// Rotation périodique en plus de la rotation à chaque départ.
    static let rotationSeconds: UInt64 = 7 * 24 * 3_600
    static let rotationMessages: UInt64 = 100

    private let scope: MessagingScope
    private let relay: any MessagingCryptoRelay
    private let vault: MessagingCryptoVault
    private var machine: OlmMachine?
    /// Une seule ouverture du store même si plusieurs appels arrivent pendant la réentrance de l'acteur.
    private var opening: Task<OlmMachine, any Error>?
    private var deviceID = ""
    private var state = MessagingCryptoVault.State()

    init(scope: MessagingScope, relay: any MessagingCryptoRelay, vault: MessagingCryptoVault? = nil) throws {
        self.scope = scope
        self.relay = relay
        self.vault = try vault ?? MessagingCryptoVault(scope: scope)
    }

    static func userID(_ person: UUID) -> String { "@\(person.uuidString.lowercased()):\(serverName)" }
    static func roomID(_ conversation: UUID) -> String { "!\(conversation.uuidString.lowercased()):\(serverName)" }
    static func person(fromUserID value: String) -> UUID? {
        guard value.hasPrefix("@"), value.hasSuffix(":\(serverName)") else { return nil }
        return UUID(uuidString: String(value.dropFirst().dropLast(serverName.count + 1)))
    }

    // MARK: MessagingCryptography

    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool {
        guard scope == self.scope else { return false }
        do { _ = try await open(); return true } catch { return false }
    }

    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        try guardScope(scope)
        guard let text = String(data: plaintext, encoding: .utf8), !text.isEmpty else { throw MessagingFailure.invalidResponse }
        return try await shielded {
            let machine = try await open()
            let room = Self.roomID(conversationID)
            let members = try await relay.members(scope: scope, deviceID: deviceID, conversationID: conversationID)
            guard members.contains(scope.accountID) else { throw MessagingFailure.accessChanged }
            let users = Set(members).map(Self.userID).sorted()
            // Départ d'un membre : la session de groupe sortante est jetée avant tout partage.
            if Self.someoneLeft(previous: state.members[conversationID], current: members) {
                try machine.discardRoomKey(roomId: room)
            }
            try machine.updateTrackedUsers(users: users)
            try await sync(machine)
            try await flush(machine)
            if let claim = try machine.getMissingSessions(users: users) { try await dispatch(claim, machine) }
            let settings = EncryptionSettings(algorithm: .megolmV1AesSha2, rotationPeriod: Self.rotationSeconds,
                rotationPeriodMsgs: Self.rotationMessages, historyVisibility: .shared,
                onlyAllowTrustedDevices: false, errorOnVerifiedUserProblem: true)
            for request in try machine.shareRoomKey(roomId: room, users: users, settings: settings) {
                try await dispatch(request, machine)
            }
            state.members[conversationID] = members.sorted { $0.uuidString < $1.uuidString }
            try vault.save(state)
            let content = try Self.messageContent(text: text, mentions: mentions)
            let encrypted = try machine.encrypt(roomId: room, eventType: "m.room.message", content: content)
            try? await backup(machine)
            return try Self.envelope(fromEncryptedContent: encrypted)
        }
    }

    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        // L'expéditeur fait partie de l'authentification Megolm : la forme sans message est refusée.
        throw MessagingFailure.protectionUnavailable
    }

    func decrypt(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> Data {
        try guardScope(scope)
        guard let ciphertext = message.ciphertext, ciphertext.scheme == Self.scheme,
              message.schoolID == scope.schoolID else { throw MessagingFailure.protectionUnavailable }
        return try await shielded {
            let machine = try await open()
            let event = try Self.encryptedEvent(message: message, ciphertext: ciphertext)
            let room = Self.roomID(message.conversationID)
            let settings = DecryptionSettings(senderDeviceTrustRequirement: .untrusted)
            let decrypted: DecryptedEvent
            do { decrypted = try machine.decryptRoomEvent(event: event, roomId: room, handleVerificationEvents: false,
                                                          strictShields: false, decryptionSettings: settings) }
            catch {
                // Clé de session pas encore reçue : relever le relais une fois puis réessayer.
                try await sync(machine)
                decrypted = try machine.decryptRoomEvent(event: event, roomId: room, handleVerificationEvents: false,
                                                         strictShields: false, decryptionSettings: settings)
            }
            return try Self.plaintext(from: decrypted)
        }
    }

    // MARK: MessagingKeyManagement

    func enableBackup(scope: MessagingScope) async throws -> String {
        try guardScope(scope)
        return try await shielded {
            let machine = try await open()
            let key = BackupRecoveryKey()
            let publicKey = key.megolmV1PublicKey()
            let authData: [String: Any] = ["public_key": publicKey.publicKey]
            let body = try JSONSerialization.data(withJSONObject: ["algorithm": publicKey.backupAlgorithm, "auth_data": authData])
            let created = try await relay.call(scope: scope, deviceID: deviceID, method: "POST",
                                               path: ["room_keys", "version"], query: [], body: body)
            guard let version = (try JSONSerialization.jsonObject(with: created) as? [String: Any])?["version"] as? String,
                  !version.isEmpty else { throw MessagingFailure.invalidResponse }
            try machine.enableBackupV1(key: publicKey, version: version)
            try machine.saveRecoveryKey(key: key, version: version)
            try await backup(machine)
            return key.toBase58()
        }
    }

    func restoreBackup(recoveryKey: String, scope: MessagingScope) async throws -> Int {
        try guardScope(scope)
        return try await shielded {
            let machine = try await open()
            let key = try BackupRecoveryKey.fromBase58(key: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines))
            let info = try await relay.call(scope: scope, deviceID: deviceID, method: "GET",
                                            path: ["room_keys", "version"], query: [], body: nil)
            guard let object = try JSONSerialization.jsonObject(with: info) as? [String: Any],
                  let version = object["version"] as? String,
                  let auth = object["auth_data"] as? [String: Any],
                  auth["public_key"] as? String == key.megolmV1PublicKey().publicKey else { throw MessagingFailure.protectionUnavailable }
            let raw = try await relay.call(scope: scope, deviceID: deviceID, method: "GET", path: ["room_keys", "keys"],
                                           query: [URLQueryItem(name: "version", value: version)], body: nil)
            let sessions = try Self.decryptBackup(raw, key: key)
            let keys = String(decoding: try JSONSerialization.data(withJSONObject: sessions), as: UTF8.self)
            let result = try machine.importRoomKeysFromBackup(keys: keys, backupVersion: version, progressListener: SilentProgress())
            try machine.saveRecoveryKey(key: key, version: version)
            try machine.enableBackupV1(key: key.megolmV1PublicKey(), version: version)
            return Int(result.imported)
        }
    }

    func ownDevices(scope: MessagingScope) async throws -> [MessagingOwnDevice] {
        try guardScope(scope)
        return try await shielded {
            let machine = try await open()
            let me = Self.userID(scope.accountID)
            try machine.updateTrackedUsers(users: [me])
            try await flush(machine)
            return try machine.getUserDevices(userId: me, timeout: 0).map {
                MessagingOwnDevice(id: $0.deviceId, fingerprint: $0.keys["ed25519:\($0.deviceId)"] ?? "",
                                   isCurrent: $0.deviceId == deviceID, isVerified: $0.crossSigningTrusted || $0.locallyTrusted)
            }.sorted { $0.id < $1.id }
        }
    }

    func confirmOwnDevice(deviceID other: String, fingerprint: String, scope: MessagingScope) async throws {
        try guardScope(scope)
        try await shielded {
            let machine = try await open()
            let me = Self.userID(scope.accountID)
            guard let device = try machine.getDevice(userId: me, deviceId: other, timeout: 0),
                  device.keys["ed25519:\(other)"] == fingerprint else { throw MessagingFailure.protectionUnavailable }
            if !machine.crossSigningStatus().hasMaster {
                let bootstrap = try machine.bootstrapCrossSigning()
                if let upload = bootstrap.uploadKeysRequest { try await dispatch(upload, machine) }
                let signing = bootstrap.uploadSigningKeysRequest
                let body = "{\"master_key\":\(signing.masterKey),\"self_signing_key\":\(signing.selfSigningKey),\"user_signing_key\":\(signing.userSigningKey)}"
                _ = try await relay.call(scope: scope, deviceID: deviceID, method: "POST", path: ["keys", "device_signing", "upload"],
                                         query: [], body: Data(body.utf8))
                _ = try await relay.call(scope: scope, deviceID: deviceID, method: "POST", path: ["keys", "signatures", "upload"],
                                         query: [], body: Data(bootstrap.uploadSignatureRequest.body.utf8))
            }
            let signature = try machine.verifyDevice(userId: me, deviceId: other)
            _ = try await relay.call(scope: scope, deviceID: deviceID, method: "POST", path: ["keys", "signatures", "upload"],
                                     query: [], body: Data(signature.body.utf8))
        }
    }

    // MARK: Machine

    private func guardScope(_ value: MessagingScope) throws {
        guard value == scope else { throw MessagingFailure.contextChanged }
    }

    /// Toute erreur de la bibliothèque est fermée : jamais de repli en clair.
    private func shielded<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() }
        catch let failure as MessagingFailure { throw failure }
        catch is CancellationError { throw CancellationError() }
        catch MessagingCryptoRelayFailure.backupVersionConflict { throw MessagingFailure.stateConflict }
        catch { throw MessagingFailure.protectionUnavailable }
    }

    private func open() async throws -> OlmMachine {
        if let machine { return machine }
        if let opening { return try await opening.value }
        let task = Task { try await self.create() }
        opening = task
        do { let value = try await task.value; machine = value; return value }
        catch { opening = nil; throw error }
    }

    private func create() async throws -> OlmMachine {
        let secrets = try vault.secrets()
        let created = try OlmMachine(userId: Self.userID(scope.accountID), deviceId: secrets.deviceID,
                                     path: vault.storePath, passphrase: secrets.passphrase)
        try vault.protectStore()
        deviceID = secrets.deviceID
        state = try vault.load()
        try await flush(created)
        return created
    }

    private func flush(_ machine: OlmMachine) async throws {
        for _ in 0..<8 {
            let requests = try machine.outgoingRequests()
            if requests.isEmpty { return }
            for request in requests { try await dispatch(request, machine) }
        }
    }

    private func sync(_ machine: OlmMachine) async throws {
        for _ in 0..<10 {
            let query = state.syncToken.map { [URLQueryItem(name: "since", value: $0)] } ?? []
            let raw = try await relay.call(scope: scope, deviceID: deviceID, method: "GET", path: ["sync"], query: query, body: nil)
            let page = try Self.syncPage(raw)
            _ = try machine.receiveSyncChanges(events: page.events, deviceChanges: DeviceLists(changed: page.changed, left: page.left),
                keyCounts: page.counts, unusedFallbackKeys: page.fallback, nextBatchToken: page.next,
                decryptionSettings: DecryptionSettings(senderDeviceTrustRequirement: .untrusted))
            let advanced = page.next != state.syncToken
            state.syncToken = page.next
            try vault.save(state)
            try await flush(machine)
            if !advanced || page.eventCount < 100 { return }
        }
    }

    private func backup(_ machine: OlmMachine) async throws {
        guard machine.backupEnabled() else { return }
        for _ in 0..<20 { guard let request = try machine.backupRoomKeys() else { return }; try await dispatch(request, machine) }
    }

    private func dispatch(_ request: Request, _ machine: OlmMachine) async throws {
        let (method, path, query, body, id, type) = try Self.route(request)
        let response = try await relay.call(scope: scope, deviceID: deviceID, method: method, path: path, query: query, body: body)
        try machine.markRequestAsSent(requestId: id, requestType: type, responseBody: String(decoding: response, as: UTF8.self))
    }

    // MARK: Pure helpers (testés sans bibliothèque native)

    static func route(_ request: Request) throws -> (String, [String], [URLQueryItem], Data, String, RequestType) {
        switch request {
        case .keysUpload(let id, let body):
            return ("POST", ["keys", "upload"], [], Data(body.utf8), id, .keysUpload)
        case .keysQuery(let id, let users):
            let body = try JSONSerialization.data(withJSONObject: ["device_keys": Dictionary(uniqueKeysWithValues: users.map { ($0, [String]()) })])
            return ("POST", ["keys", "query"], [], body, id, .keysQuery)
        case .keysClaim(let id, let keys):
            return ("POST", ["keys", "claim"], [], try JSONSerialization.data(withJSONObject: ["one_time_keys": keys]), id, .keysClaim)
        case .toDevice(let id, let type, let body):
            return ("PUT", ["sendToDevice", type, id], [], Data("{\"messages\":\(body)}".utf8), id, .toDevice)
        case .signatureUpload(let id, let body):
            return ("POST", ["keys", "signatures", "upload"], [], Data(body.utf8), id, .signatureUpload)
        case .keysBackup(let id, let version, let rooms):
            return ("PUT", ["room_keys", "keys"], [URLQueryItem(name: "version", value: version)],
                    Data("{\"rooms\":\(rooms)}".utf8), id, .keysBackup)
        case .roomMessage:
            // Le transport des messages passe par MessagingService, jamais par ce relais.
            throw MessagingFailure.protectionUnavailable
        }
    }

    static func someoneLeft(previous: [UUID]?, current: [UUID]) -> Bool {
        guard let previous else { return false }
        return !Set(previous).isSubset(of: Set(current))
    }

    static func messageContent(text: String, mentions: [UUID]) throws -> String {
        var content: [String: Any] = ["msgtype": "m.text", "body": text]
        content["m.mentions"] = ["user_ids": mentions.map(userID)]
        return String(decoding: try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys]), as: UTF8.self)
    }

    /// keyId = session_id Megolm en base64url (jeu de caractères accepté par l'enveloppe).
    static func envelope(fromEncryptedContent content: String) throws -> MessagingCiphertext {
        let data = Data(content.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["algorithm"] as? String == "m.megolm.v1.aes-sha2",
              let session = object["session_id"] as? String, !session.isEmpty,
              object["ciphertext"] is String else { throw MessagingFailure.protectionUnavailable }
        let keyID = session.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return MessagingCiphertext(scheme: scheme, keyID: keyID, payload: data)
    }

    static func encryptedEvent(message: MessagingWireMessage, ciphertext: MessagingCiphertext) throws -> String {
        guard let content = try JSONSerialization.jsonObject(with: ciphertext.payload) as? [String: Any],
              content["algorithm"] as? String == "m.megolm.v1.aes-sha2",
              let session = content["session_id"] as? String,
              session.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") == ciphertext.keyID
        else { throw MessagingFailure.protectionUnavailable }
        let event: [String: Any] = [
            "type": "m.room.encrypted", "content": content,
            "sender": userID(message.senderID),
            "event_id": "$\(message.id.uuidString.lowercased())",
            "origin_server_ts": Int64(message.acceptedAt.timeIntervalSince1970 * 1_000),
            "room_id": roomID(message.conversationID),
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
    }

    static func plaintext(from decrypted: DecryptedEvent) throws -> Data {
        if decrypted.shieldState.code == .mismatchedSender { throw MessagingFailure.protectionUnavailable }
        guard let event = try JSONSerialization.jsonObject(with: Data(decrypted.clearEvent.utf8)) as? [String: Any],
              event["type"] as? String == "m.room.message",
              let content = event["content"] as? [String: Any],
              let body = content["body"] as? String else { throw MessagingFailure.protectionUnavailable }
        return Data(body.utf8)
    }

    struct SyncPage: Equatable {
        var events: String; var changed: [String]; var left: [String]
        var counts: [String: Int32]; var fallback: [String]?; var next: String; var eventCount: Int
    }

    static func syncPage(_ raw: Data) throws -> SyncPage {
        guard let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let next = object["next_batch"] as? String, !next.isEmpty else { throw MessagingFailure.invalidResponse }
        let events = ((object["to_device"] as? [String: Any])?["events"] as? [Any]) ?? []
        let lists = object["device_lists"] as? [String: Any]
        let counts = ((object["device_one_time_keys_count"] as? [String: Any]) ?? [:]).compactMapValues { ($0 as? NSNumber)?.int32Value }
        let wrapped = String(decoding: try JSONSerialization.data(withJSONObject: ["events": events]), as: UTF8.self)
        return SyncPage(events: wrapped, changed: lists?["changed"] as? [String] ?? [], left: lists?["left"] as? [String] ?? [],
                        counts: counts, fallback: object["device_unused_fallback_key_types"] as? [String],
                        next: next, eventCount: events.count)
    }

    static func decryptBackup(_ raw: Data, key: BackupRecoveryKey) throws -> [[String: Any]] {
        guard let rooms = (try JSONSerialization.jsonObject(with: raw) as? [String: Any])?["rooms"] as? [String: Any] else {
            throw MessagingFailure.invalidResponse
        }
        var sessions: [[String: Any]] = []
        for (room, value) in rooms {
            guard let list = (value as? [String: Any])?["sessions"] as? [String: Any] else { continue }
            for (session, entry) in list {
                guard let data = (entry as? [String: Any])?["session_data"] as? [String: Any],
                      let ephemeral = data["ephemeral"] as? String, let mac = data["mac"] as? String,
                      let ciphertext = data["ciphertext"] as? String,
                      let clear = try? key.decryptV1(ephemeralKey: ephemeral, mac: mac, ciphertext: ciphertext),
                      var decoded = try? JSONSerialization.jsonObject(with: Data(clear.utf8)) as? [String: Any] else { continue }
                decoded["room_id"] = room
                decoded["session_id"] = session
                sessions.append(decoded)
            }
        }
        return sessions
    }
}

private final class SilentProgress: ProgressListener, @unchecked Sendable {
    func onProgress(progress: Int32, total: Int32) {}
}

/// Store crypto dans un dossier protégé, passphrase et identifiant d'appareil dans le Keychain.
/// Si le store existe sans passphrase, il n'est ni recréé ni ouvert en clair : erreur fermée.
struct MessagingCryptoVault: Sendable {
    struct State: Codable, Equatable, Sendable {
        var syncToken: String?
        var members: [UUID: [UUID]] = [:]
    }
    struct Secrets: Sendable { let deviceID: String; let passphrase: String }

    static let service = "ch.drivy.messaging.crypto.v1"
    let folder: URL
    let fingerprint: String
    var storePath: String { folder.appendingPathComponent("store", isDirectory: true).path }
    private var stateFile: URL { folder.appendingPathComponent("state.sealed") }

    init(scope: MessagingScope, root: URL? = nil) throws {
        guard !scope.apiBaseURL.isEmpty else { throw MessagingFailure.contextChanged }
        // Une identité d'appareil par compte, école et serveur ; l'époque d'accès ne détruit pas les clés.
        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.apiBaseURL)"
        fingerprint = SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
        folder = base.appendingPathComponent("MessagingCrypto", isDirectory: true).appendingPathComponent(fingerprint, isDirectory: true)
    }

    func secrets() throws -> Secrets {
        let storeExists = FileManager.default.fileExists(atPath: storePath)
        if let existing = try read() { return existing }
        guard !storeExists else { throw MessagingFailure.protectionUnavailable }
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: storePath), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try protectStore()
        let fresh = Secrets(deviceID: try Self.randomDeviceID(), passphrase: try Self.random(32).base64EncodedString())
        try write(fresh)
        return fresh
    }

    func protectStore() throws {
        let manager = FileManager.default
        for url in [folder.deletingLastPathComponent(), folder, URL(fileURLWithPath: storePath)] where manager.fileExists(atPath: url.path) {
            try Self.protect(url)
        }
        if let items = manager.enumerator(at: URL(fileURLWithPath: storePath), includingPropertiesForKeys: nil) {
            for case let item as URL in items { try Self.protect(item) }
        }
    }

    func load() throws -> State {
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return State() }
        do {
            let box = try AES.GCM.SealedBox(combined: try Data(contentsOf: stateFile))
            return try JSONDecoder().decode(State.self, from: try AES.GCM.open(box, using: try stateKey(), authenticating: Data(fingerprint.utf8)))
        } catch { throw MessagingFailure.protectionUnavailable }
    }

    func save(_ state: State) throws {
        do {
            let sealed = try AES.GCM.seal(try JSONEncoder().encode(state), using: try stateKey(), authenticating: Data(fingerprint.utf8))
            guard let bytes = sealed.combined else { throw MessagingFailure.protectionUnavailable }
            try bytes.write(to: stateFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try Self.protect(stateFile)
        } catch { throw MessagingFailure.protectionUnavailable }
    }

    private func stateKey() throws -> SymmetricKey {
        guard let secrets = try read(), let raw = Data(base64Encoded: secrets.passphrase) else { throw MessagingFailure.protectionUnavailable }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: raw), info: Data("drivy.messaging.crypto.state".utf8), outputByteCount: 32)
    }

    private func read() throws -> Secrets? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
            kSecAttrAccount as String: fingerprint, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let pair = try? JSONDecoder().decode([String: String].self, from: data),
              let device = pair["deviceId"], let passphrase = pair["passphrase"],
              MessagingCryptoHTTPRelay.validDeviceID(device), Data(base64Encoded: passphrase)?.count == 32
        else { throw MessagingFailure.protectionUnavailable }
        return Secrets(deviceID: device, passphrase: passphrase)
    }

    private func write(_ secrets: Secrets) throws {
        let data = try JSONEncoder().encode(["deviceId": secrets.deviceID, "passphrase": secrets.passphrase])
        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
            kSecAttrAccount as String: fingerprint, kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
    }

    static func random(_ count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        return bytes
    }

    static func randomDeviceID() throws -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String(try random(16).map { alphabet[Int($0) % alphabet.count] })
    }

    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        var item = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try item.setResourceValues(values)
    }
}
