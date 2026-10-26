import Foundation
import CryptoKit
import Security
import MatrixSDKCrypto

/// Gestion des clés visible par l'utilisateur : sauvegarde par clé de récupération et appareils du compte.
protocol MessagingKeyManagement: Sendable {
    /// Crée une sauvegarde serveur. Renvoie la clé de récupération à montrer UNE fois à l'utilisateur.
    func enableBackup(scope: MessagingScope) async throws -> String
    /// Restaure l'historique sur un nouvel appareil avec la clé de récupération saisie.
    func restoreBackup(recoveryKey: String, scope: MessagingScope) async throws -> (imported: Int, failed: Int)
    /// Vrai si des clés n'ont pas encore pu être envoyées à la sauvegarde (nouvel essai au prochain open/sync).
    func backupPending(scope: MessagingScope) async -> Bool
    func ownDevices(scope: MessagingScope) async throws -> [MessagingOwnDevice]
    func deviceVerificationSnapshot(scope: MessagingScope) async throws -> MessagingDeviceVerificationSnapshot
    /// À appeler seulement après comparaison visuelle de l'empreinte affichée sur les deux appareils.
    func confirmOwnDevice(deviceID: String, fingerprint: String, scope: MessagingScope) async throws
}

extension MessagingKeyManagement {
    func deviceVerificationSnapshot(scope: MessagingScope) async throws -> MessagingDeviceVerificationSnapshot {
        throw MessagingFailure.protectionUnavailable
    }
}

struct MessagingDeviceVerificationSnapshot: Sendable {
    enum Capability: Sendable, Equatable { case available, originalDeviceRequired, identityConflict }
    /// Empreinte issue de la machine locale, jamais de la réponse du serveur.
    let localDevice: MessagingOwnDevice
    let devices: [MessagingOwnDevice]
    let capability: Capability
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
    /// Un seul sync en vol, partagé par tous les appels concurrents.
    private var syncing: Task<Void, any Error>?
    /// Les écritures de sauvegarde partagent une seule boucle, comme le sync.
    private var backingUp: Task<Void, any Error>?
    /// Incrémenté à chaque sync terminé : un déchiffrement sans clé relit la file sauf si un sync a fini depuis son début.
    private var syncGeneration = 0

    /// Une seule confirmation en vol : aucun bootstrap concurrent dans cette instance.
    private var verifyingDevice = false
    private let diagnostics: MessagingDiagnostics

    init(scope: MessagingScope, relay: any MessagingCryptoRelay, vault: MessagingCryptoVault? = nil,
         diagnostics: MessagingDiagnostics = .shared) throws {
        self.scope = scope
        self.relay = relay
        self.diagnostics = diagnostics
        self.vault = try vault ?? MessagingCryptoVault(scope: scope, diagnostics: diagnostics)
    }

    /// Code court de la dernière panne, affiché sous l'erreur (jamais journalisé).
    nonisolated var lastDiagnostic: String? { diagnostics.last }

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

    func availabilityFailure(scope: MessagingScope, conversationID: UUID) async -> MessagingFailure? {
        guard scope == self.scope else { return .contextChanged }
        if machine == nil, opening == nil { diagnostics.clear() }
        do { _ = try await open(); return nil }
        catch MessagingCryptoRelayFailure.deviceLimitReached { return .deviceLimitReached }
        catch MessagingFailure.deviceLimitReached { return .deviceLimitReached }
        catch is MessagingFailure, is MessagingCryptoRelayFailure, is CancellationError { return .protectionUnavailable }
        catch {
            diagnostics.recordIfEmpty("SDK-\(MessagingDiagnostics.caseName(error))")
            return .protectionUnavailable
        }
    }

    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        try guardScope(scope)
        diagnostics.clear()
        guard let text = String(data: plaintext, encoding: .utf8), !text.isEmpty else { throw MessagingFailure.invalidResponse }
        return try await shielded {
            let machine = try await open()
            let room = Self.roomID(conversationID)
            let listed = try await relay.members(scope: scope, deviceID: deviceID, conversationID: conversationID)
            let members = listed.members
            guard members.contains(scope.accountID) else { throw MessagingFailure.accessChanged }
            let users = Set(members).map(Self.userID).sorted()
            // Départ (ou départ puis retour) d'un membre : la session de groupe sortante est jetée avant tout partage.
            if Self.mustRotate(previous: state.members[conversationID], current: members,
                               previousEpoch: state.membersEpoch[conversationID], currentEpoch: listed.membersEpoch) {
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
            if let epoch = listed.membersEpoch { state.membersEpoch[conversationID] = epoch }
            try vault.save(state)
            let content = try Self.messageContent(text: text, mentions: mentions)
            let encrypted = try machine.encrypt(roomId: room, eventType: "m.room.message", content: content)
            try await backupOrMarkPending(machine)
            let envelope = try Self.envelope(fromEncryptedContent: encrypted)
            return MessagingCiphertext(scheme: envelope.scheme, keyID: envelope.keyID, payload: envelope.payload,
                                       expectedMembersEpoch: listed.membersEpoch)
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
            let started = syncGeneration
            let decrypted: DecryptedEvent
            do {
                do { decrypted = try machine.decryptRoomEvent(event: event, roomId: room, handleVerificationEvents: false,
                                                              strictShields: false, decryptionSettings: settings) }
                catch DecryptionError.MissingRoomKey {
                    // Clé pas encore reçue : relire la file to-device, sauf si un sync s'est terminé depuis le début de cet appel.
                    if syncGeneration == started { try await sync(machine) }
                    decrypted = try machine.decryptRoomEvent(event: event, roomId: room, handleVerificationEvents: false,
                                                             strictShields: false, decryptionSettings: settings)
                }
            } catch let error as DecryptionError {
                // Raison du SDK seulement (catégorie fixe), jamais le message d'erreur libre.
                throw MessagingDecryptionFailure(code: Self.decryptionCode(error))
            }
            return try Self.plaintext(from: decrypted)
        }
    }

    // MARK: MessagingKeyManagement

    func enableBackup(scope: MessagingScope) async throws -> String {
        try guardScope(scope)
        diagnostics.clear()
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
            try await backupOrMarkPending(machine)
            return key.toBase58()
        }
    }

    func restoreBackup(recoveryKey: String, scope: MessagingScope) async throws -> (imported: Int, failed: Int) {
        try guardScope(scope)
        return try await shielded {
            let machine = try await open()
            // Seuls une clé illisible, une sauvegarde absente ou une clé publique différente sont un refus de clé.
            // Réseau, session, contexte et réponse invalide gardent leur propre cause (#169).
            guard let key = try? BackupRecoveryKey.fromBase58(key: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw MessagingFailure.recoveryKeyRefused
            }
            let info: Data
            do {
                info = try await relay.call(scope: scope, deviceID: deviceID, method: "GET",
                                            path: ["room_keys", "version"], query: [], body: nil)
            } catch MessagingCryptoRelayFailure.notFound { throw MessagingFailure.recoveryKeyRefused }
            guard let object = try? JSONSerialization.jsonObject(with: info) as? [String: Any],
                  let version = object["version"] as? String,
                  let auth = object["auth_data"] as? [String: Any],
                  let publicKey = auth["public_key"] as? String else { throw MessagingFailure.invalidResponse }
            guard publicKey == key.megolmV1PublicKey().publicKey else { throw MessagingFailure.recoveryKeyRefused }
            let raw = try await relay.call(scope: scope, deviceID: deviceID, method: "GET", path: ["room_keys", "keys"],
                                           query: [URLQueryItem(name: "version", value: version)], body: nil)
            let backup = try Self.decryptBackup(raw, key: key)
            let keys = String(decoding: try JSONSerialization.data(withJSONObject: backup.sessions), as: UTF8.self)
            let result = try machine.importRoomKeysFromBackup(keys: keys, backupVersion: version, progressListener: SilentProgress())
            try machine.saveRecoveryKey(key: key, version: version)
            try machine.enableBackupV1(key: key.megolmV1PublicKey(), version: version)
            let rejected = max(0, Int(result.total) - Int(result.imported))
            return (imported: Int(result.imported), failed: backup.failed + rejected)
        }
    }

    func backupPending(scope: MessagingScope) async -> Bool {
        guard scope == self.scope else { return false }
        // Ne pas afficher un faux état à jour avant l'ouverture de la machine.
        if machine == nil { return (try? vault.load().backupPending) ?? true }
        return state.backupPending
    }

    func ownDevices(scope: MessagingScope) async throws -> [MessagingOwnDevice] {
        try guardScope(scope)
        return try await shielded {
            let machine = try await open()
            _ = try await refreshOwnIdentity(machine)
            return try deviceProjection(machine)
        }
    }

    func deviceVerificationSnapshot(scope: MessagingScope) async throws -> MessagingDeviceVerificationSnapshot {
        try guardScope(scope)
        return try await shielded {
            let machine = try await open()
            let remote = try await refreshOwnIdentity(machine)
            guard let fingerprint = machine.identityKeys()["ed25519"], !fingerprint.isEmpty else {
                throw MessagingFailure.protectionUnavailable
            }
            let devices = try deviceProjection(machine)
            let status = machine.crossSigningStatus()
            let capability: MessagingDeviceVerificationSnapshot.Capability
            if let record = try vault.deviceSigningRecord(), !record.completed {
                let matches = try record.intent.identity() == remote.signing
                if remote.signing.master != nil && !matches { capability = .identityConflict }
                else { capability = status.hasSelfSigning ? .available : .originalDeviceRequired }
            } else if remote.signing.master != nil {
                let verified = try machine.isIdentityVerified(userId: Self.userID(scope.accountID))
                capability = status.hasSelfSigning && verified ? .available : .originalDeviceRequired
            } else {
                let existingRecord = try vault.deviceSigningRecord() != nil
                capability = existingRecord || status.hasMaster || status.hasSelfSigning || status.hasUserSigning
                    ? .identityConflict : .available
            }
            return MessagingDeviceVerificationSnapshot(
                localDevice: MessagingOwnDevice(id: deviceID, fingerprint: fingerprint, isCurrent: true,
                    isVerified: devices.first(where: { $0.id == deviceID })?.isVerified == true),
                devices: devices.filter { !$0.isCurrent }, capability: capability)
        }
    }

    func confirmOwnDevice(deviceID other: String, fingerprint: String, scope: MessagingScope) async throws {
        try guardScope(scope)
        guard !verifyingDevice else { throw MessagingFailure.unavailable }
        verifyingDevice = true
        defer { verifyingDevice = false }
        try await shielded {
            let machine = try await open()
            let me = Self.userID(scope.accountID)
            guard other != deviceID, !fingerprint.isEmpty else { throw MessagingFailure.protectionUnavailable }
            let remote = try await refreshOwnIdentity(machine)
            guard remote.devices[other] == fingerprint,
                  let device = try machine.getDevice(userId: me, deviceId: other, timeout: 0),
                  device.keys["ed25519:\(other)"] == fingerprint else { throw MessagingFailure.protectionUnavailable }
            try await ensureSigningIdentity(machine, remote: remote)
            // Une révocation pendant l'initialisation ne doit pas être signée depuis un cache ancien.
            let current = try await refreshOwnIdentity(machine)
            guard current.devices[other] == fingerprint else { throw MessagingFailure.protectionUnavailable }
            let signature = try machine.verifyDevice(userId: me, deviceId: other)
            try await uploadDeviceSignature(Data(signature.body.utf8))
            let accepted = try await refreshOwnIdentity(machine)
            guard accepted.devices[other] == fingerprint,
                  let verified = try machine.getDevice(userId: me, deviceId: other, timeout: 0),
                  verified.crossSigningTrusted else { throw MessagingFailure.protectionUnavailable }
        }
    }

    private func deviceProjection(_ machine: OlmMachine) throws -> [MessagingOwnDevice] {
        try machine.getUserDevices(userId: Self.userID(scope.accountID), timeout: 0).map {
            MessagingOwnDevice(id: $0.deviceId, fingerprint: $0.keys["ed25519:\($0.deviceId)"] ?? "",
                               isCurrent: $0.deviceId == deviceID, isVerified: $0.crossSigningTrusted)
        }.sorted { $0.id < $1.id }
    }

    private struct OwnIdentity: Sendable {
        let devices: [String: String]
        let signing: MessagingCryptoVault.SigningIdentity
    }

    /// Requête explicite : updateTrackedUsers seul ne rafraîchit pas un compte déjà suivi.
    private func refreshOwnIdentity(_ machine: OlmMachine) async throws -> OwnIdentity {
        let me = Self.userID(scope.accountID)
        try machine.updateTrackedUsers(users: [me])
        try await flush(machine)
        let id = UUID().uuidString
        let body = try JSONSerialization.data(withJSONObject: ["device_keys": [me: [String]()]])
        let response = try await relay.call(scope: scope, deviceID: deviceID, method: "POST",
                                            path: ["keys", "query"], query: [], body: body)
        guard let raw = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let failures = raw["failures"] as? [String: Any], failures.isEmpty,
              let allDevices = raw["device_keys"] as? [String: [String: Any]] else {
            throw MessagingFailure.invalidResponse
        }
        var devices: [String: String] = [:]
        for (device, value) in allDevices[me] ?? [:] {
            guard let value = value as? [String: Any], value["user_id"] as? String == me,
                  value["device_id"] as? String == device,
                  let keys = value["keys"] as? [String: String], let fingerprint = keys["ed25519:\(device)"],
                  !fingerprint.isEmpty else { throw MessagingFailure.invalidResponse }
            devices[device] = fingerprint
        }
        let signing = try MessagingCryptoVault.SigningIdentity(query: raw, user: me)
        try machine.markRequestAsSent(requestId: id, requestType: .keysQuery,
                                     responseBody: String(decoding: response, as: UTF8.self))
        return OwnIdentity(devices: devices, signing: signing)
    }

    /// Intention publique scellée avant tout upload. Aucune nouvelle identité à la reprise.
    private func ensureSigningIdentity(_ machine: OlmMachine, remote: OwnIdentity) async throws {
        let status = machine.crossSigningStatus()
        if try vault.deviceSigningRecord() == nil, remote.signing.master != nil {
            guard status.hasSelfSigning,
                  try machine.isIdentityVerified(userId: Self.userID(scope.accountID)) else {
                throw MessagingFailure.protectionUnavailable
            }
            return
        }
        // Lecture/création/écriture coordonnées entre instances, sans attente réseau sous verrou.
        let record = try vault.prepareDeviceSigning {
            // Secrets privés sans intention durable : état ambigu, ne jamais les remplacer.
            guard remote.signing.master == nil,
                  !status.hasMaster, !status.hasSelfSigning, !status.hasUserSigning else {
                throw MessagingFailure.stateConflict
            }
            let bootstrap = try machine.bootstrapCrossSigning()
            let signing = bootstrap.uploadSigningKeysRequest
            let body = Data("{\"master_key\":\(signing.masterKey),\"self_signing_key\":\(signing.selfSigningKey),\"user_signing_key\":\(signing.userSigningKey)}".utf8)
            var deviceKeys: String?
            if let upload = bootstrap.uploadKeysRequest {
                guard case .keysUpload(_, let value) = upload else { throw MessagingFailure.invalidResponse }
                deviceKeys = value
            }
            return MessagingCryptoVault.PendingDeviceSigning(
                signingBody: body, signatureBody: Data(bootstrap.uploadSignatureRequest.body.utf8), deviceKeysBody: deviceKeys)
        }
        guard machine.crossSigningStatus().hasSelfSigning else { throw MessagingFailure.protectionUnavailable }
        let pending = record.intent
        let expected = try pending.identity()
        if record.completed {
            guard remote.signing == expected else { throw MessagingFailure.stateConflict }
            return
        }
        if remote.signing.master == nil {
            if let body = pending.deviceKeysBody {
                try await dispatch(.keysUpload(requestId: UUID().uuidString, body: body), machine)
            }
            let response = try await relay.call(scope: scope, deviceID: deviceID, method: "POST",
                path: ["keys", "device_signing", "upload"], query: [], body: pending.signingBody)
            guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any], object.isEmpty else {
                throw MessagingFailure.invalidResponse
            }
        } else {
            guard remote.signing == expected else { throw MessagingFailure.stateConflict }
        }
        // Une réponse d'upload perdue est résolue par query, sans renvoyer un master existant.
        let published = try await refreshOwnIdentity(machine)
        guard published.signing == expected else { throw MessagingFailure.stateConflict }
        try await uploadDeviceSignature(pending.signatureBody)
        try vault.completeDeviceSigning(expected: pending)
    }

    private func uploadDeviceSignature(_ body: Data) async throws {
        let response = try await relay.call(scope: scope, deviceID: deviceID, method: "POST",
            path: ["keys", "signatures", "upload"], query: [], body: body)
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let failures = object["failures"] as? [String: Any] else { throw MessagingFailure.invalidResponse }
        guard failures.isEmpty else { throw MessagingFailure.protectionUnavailable }
    }

    // MARK: Machine

    private func guardScope(_ value: MessagingScope) throws {
        guard value == scope else { throw MessagingFailure.contextChanged }
    }

    /// Toute erreur de la bibliothèque est fermée : jamais de repli en clair.
    private func shielded<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() }
        catch let failure as MessagingFailure { throw failure }
        catch let failure as MessagingDecryptionFailure { diagnostics.recordIfEmpty(failure.code); throw failure }
        catch is CancellationError { throw CancellationError() }
        catch MessagingCryptoRelayFailure.backupVersionConflict { throw MessagingFailure.stateConflict }
        catch MessagingCryptoRelayFailure.deviceLimitReached { throw MessagingFailure.deviceLimitReached }
        // 404 ou 409 sans code : jamais présenté comme sauvegarde existante (déjà diagnostiqué par le relais).
        catch is MessagingCryptoRelayFailure { throw MessagingFailure.protectionUnavailable }
        catch {
            diagnostics.recordIfEmpty("SDK-\(MessagingDiagnostics.caseName(error))")
            throw MessagingFailure.protectionUnavailable
        }
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
        let created: OlmMachine
        do {
            created = try OlmMachine(userId: Self.userID(scope.accountID), deviceId: secrets.deviceID,
                                     path: vault.storePath, passphrase: secrets.passphrase)
        } catch {
            diagnostics.recordIfEmpty("SQL-\(MessagingDiagnostics.caseName(error))")
            throw MessagingFailure.protectionUnavailable
        }
        try vault.protectStore()
        deviceID = secrets.deviceID
        state = try vault.load()
        // Le SDK persiste la clé de récupération, pas l'activation en mémoire du backup.
        if !created.backupEnabled(), let saved = try created.getBackupKeys() {
            try created.enableBackupV1(key: saved.recoveryKey().megolmV1PublicKey(), version: saved.backupVersion())
        }
        try await flush(created)
        // Inspecter aussi les clés non sauvegardées du SDK après un arrêt avant l'écriture de notre état.
        try await backupOrMarkPending(created)
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
        if let syncing { return try await syncing.value }
        let task = Task { try await self.performSync(machine) }
        syncing = task
        defer { syncing = nil }
        try await task.value
    }

    private func performSync(_ machine: OlmMachine) async throws {
        for _ in 0..<10 {
            let query = state.syncToken.map { [URLQueryItem(name: "since", value: $0)] } ?? []
            let raw = try await relay.call(scope: scope, deviceID: deviceID, method: "GET", path: ["sync"], query: query, body: nil)
            let page = try Self.syncPage(raw)
            // Write-ahead : la réception SDK et son curseur ne précèdent jamais l'intention durable de backup.
            if machine.backupEnabled() {
                state.backupPending = true
                try vault.save(state)
            }
            _ = try machine.receiveSyncChanges(events: page.events, deviceChanges: DeviceLists(changed: page.changed, left: page.left),
                keyCounts: page.counts, unusedFallbackKeys: page.fallback, nextBatchToken: page.next,
                decryptionSettings: DecryptionSettings(senderDeviceTrustRequirement: .untrusted))
            let advanced = page.next != state.syncToken
            state.syncToken = page.next
            // Appareil ou membre parti : toute session sortante qu'il a pu recevoir est jetée.
            for conversation in Self.conversationsAffected(byLeft: page.left, members: state.members) {
                try machine.discardRoomKey(roomId: Self.roomID(conversation))
            }
            try vault.save(state)
            try await flush(machine)
            if !advanced || page.eventCount < 100 { break }
        }
        syncGeneration &+= 1
        try await backupOrMarkPending(machine)
    }

    /// La panne réseau ne bloque pas la lecture/envoi. L'intention scellée précède toute tentative.
    /// Une panne du coffre reste une erreur fermée : elle ne peut pas fabriquer un état durable.
    private func backupOrMarkPending(_ machine: OlmMachine) async throws {
        guard machine.backupEnabled() else { return }
        if let backingUp { return try await backingUp.value }
        let task = Task { try await self.performBackup(machine) }
        backingUp = task
        defer { backingUp = nil }
        try await task.value
    }

    private func performBackup(_ machine: OlmMachine) async throws {
        state.backupPending = true
        try vault.save(state)
        do { try await backup(machine) }
        catch { return } // pending reste vrai, y compris dans le coffre, pour la prochaine ouverture/sync.
        state.backupPending = false
        do { try vault.save(state) }
        catch { state.backupPending = true; throw error }
    }

    private func backup(_ machine: OlmMachine) async throws {
        guard machine.backupEnabled() else { throw MessagingFailure.protectionUnavailable }
        for _ in 0..<20 {
            guard let request = try machine.backupRoomKeys() else { return }
            try await dispatch(request, machine)
        }
        // Une boucle bornée n'est pas une preuve que toutes les clés ont été sauvegardées.
        if try machine.backupRoomKeys() != nil { throw MessagingFailure.unavailable }
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

    /// Rotation si cet appareil voit un départ, ou si l'époque de membres a changé (départ puis retour inclus).
    static func mustRotate(previous: [UUID]?, current: [UUID], previousEpoch: Int?, currentEpoch: Int?) -> Bool {
        if someoneLeft(previous: previous, current: current) { return true }
        guard let previousEpoch, let currentEpoch else { return false }
        return previousEpoch != currentEpoch
    }

    static func conversationsAffected(byLeft left: [String], members: [UUID: [UUID]]) -> [UUID] {
        let gone = Set(left.compactMap(person(fromUserID:)))
        guard !gone.isEmpty else { return [] }
        return members.filter { !gone.isDisjoint(with: $0.value) }.map(\.key).sorted { $0.uuidString < $1.uuidString }
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

    /// Code court et non sensible de la raison d'échec du SDK (#84).
    static func decryptionCode(_ error: DecryptionError) -> String {
        switch error {
        case .MissingRoomKey(_, let withheld):
            guard let withheld else { return "D-NOKEY" }
            let clean = String(withheld.uppercased().unicodeScalars
                .filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 48 && $0.value <= 57) }
                .prefix(16).map(Character.init))
            return clean.isEmpty ? "D-WITHHELD" : "D-WH-\(clean)"
        case .Megolm: return "D-MEGOLM"
        case .Identifier: return "D-ID"
        case .Serialization: return "D-FORMAT"
        case .Store: return "D-STORE"
        }
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

    static func decryptBackup(_ raw: Data, key: BackupRecoveryKey) throws -> (sessions: [[String: Any]], failed: Int) {
        guard let rooms = (try JSONSerialization.jsonObject(with: raw) as? [String: Any])?["rooms"] as? [String: Any] else {
            throw MessagingFailure.invalidResponse
        }
        var sessions: [[String: Any]] = []
        var failed = 0
        for (room, value) in rooms {
            guard let list = (value as? [String: Any])?["sessions"] as? [String: Any] else { failed += 1; continue }
            for (session, entry) in list {
                guard let data = (entry as? [String: Any])?["session_data"] as? [String: Any],
                      let ephemeral = data["ephemeral"] as? String, let mac = data["mac"] as? String,
                      let ciphertext = data["ciphertext"] as? String,
                      let clear = try? key.decryptV1(ephemeralKey: ephemeral, mac: mac, ciphertext: ciphertext),
                      var decoded = try? JSONSerialization.jsonObject(with: Data(clear.utf8)) as? [String: Any] else { failed += 1; continue }
                decoded["room_id"] = room
                decoded["session_id"] = session
                sessions.append(decoded)
            }
        }
        return (sessions, failed)
    }
}

/// Accès Keychain injectable pour tester l'échec d'écriture.
protocol MessagingCryptoKeychain: Sendable {
    func read(service: String, account: String) throws -> Data?
    func add(service: String, account: String, data: Data) throws
}

struct MessagingSystemKeychain: MessagingCryptoKeychain {
    func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MessagingKeychainError(operation: "R", status: status) }
        guard let data = result as? Data else { throw MessagingKeychainError(operation: "R", status: 0) }
        return data
    }

    func add(service: String, account: String, data: Data) throws {
        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw MessagingKeychainError(operation: "A", status: status) }
    }
}

/// Statut Keychain numérique seulement, converti en diagnostic par le coffre.
struct MessagingKeychainError: Error, Equatable, Sendable {
    let operation: String
    let status: OSStatus
}

private final class SilentProgress: ProgressListener, @unchecked Sendable {
    func onProgress(progress: Int32, total: Int32) {}
}

/// Store crypto dans un dossier protégé, passphrase et identifiant d'appareil dans le Keychain.
/// Si le store existe sans passphrase, il n'est ni recréé ni ouvert en clair : erreur fermée.
struct MessagingCryptoVault: Sendable {
    /// Comparaison des clés publiques seulement, les signatures peuvent être enrichies au serveur.
    struct PublicSigningKey: Codable, Equatable, Sendable {
        let user_id: String
        let usage: [String]
        let keys: [String: String]
    }
    struct SigningIdentity: Codable, Equatable, Sendable {
        let master: PublicSigningKey?
        let selfSigning: PublicSigningKey?
        let userSigning: PublicSigningKey?

        init(query: [String: Any], user: String) throws {
            func key(_ field: String, usage: String) throws -> PublicSigningKey? {
                guard let raw = query[field] else { return nil }
                guard let values = raw as? [String: Any] else { throw MessagingFailure.invalidResponse }
                guard let value = values[user] else { return nil }
                let key = try JSONDecoder().decode(PublicSigningKey.self, from: JSONSerialization.data(withJSONObject: value))
                guard key.user_id == user, key.usage == [usage], key.keys.count == 1 else {
                    throw MessagingFailure.invalidResponse
                }
                return key
            }
            master = try key("master_keys", usage: "master")
            selfSigning = try key("self_signing_keys", usage: "self_signing")
            userSigning = try key("user_signing_keys", usage: "user_signing")
        }
    }
    struct PendingDeviceSigning: Codable, Equatable, Sendable {
        let signingBody: Data
        let signatureBody: Data
        let deviceKeysBody: String?

        func identity() throws -> SigningIdentity {
            guard let raw = try JSONSerialization.jsonObject(with: signingBody) as? [String: Any],
                  let master = raw["master_key"] as? [String: Any], let user = master["user_id"] as? String,
                  let selfSigning = raw["self_signing_key"], let userSigning = raw["user_signing_key"] else {
                throw MessagingFailure.invalidResponse
            }
            return try SigningIdentity(query: ["master_keys": [user: master],
                "self_signing_keys": [user: selfSigning], "user_signing_keys": [user: userSigning]], user: user)
        }
    }
    struct DeviceSigningRecord: Codable, Equatable, Sendable {
        let intent: PendingDeviceSigning
        var completed: Bool
    }
    struct State: Codable, Equatable, Sendable {
        var syncToken: String?
        var members: [UUID: [UUID]] = [:]
        var membersEpoch: [UUID: Int] = [:]
        var backupPending = false

        init() {}
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            syncToken = try values.decodeIfPresent(String.self, forKey: .syncToken)
            members = try values.decodeIfPresent([UUID: [UUID]].self, forKey: .members) ?? [:]
            membersEpoch = try values.decodeIfPresent([UUID: Int].self, forKey: .membersEpoch) ?? [:]
            backupPending = try values.decodeIfPresent(Bool.self, forKey: .backupPending) ?? false
        }
    }
    struct Secrets: Sendable { let deviceID: String; let passphrase: String }

    static let service = "ch.drivy.messaging.crypto.v1"
    let folder: URL
    let fingerprint: String
    let keychain: any MessagingCryptoKeychain
    let diagnostics: MessagingDiagnostics
    var storePath: String { folder.appendingPathComponent("store", isDirectory: true).path }
    private var stateFile: URL { folder.appendingPathComponent("state.sealed") }
    private var signingFile: URL { folder.appendingPathComponent("device-signing.sealed") }
    /// Toutes les instances de l'app coordonnent la préparation et l'acquittement du journal dédié.
    private static let signingLock = NSLock()

    init(scope: MessagingScope, root: URL? = nil, keychain: any MessagingCryptoKeychain = MessagingSystemKeychain(),
         diagnostics: MessagingDiagnostics = .shared) throws {
        self.keychain = keychain
        self.diagnostics = diagnostics
        guard !scope.apiBaseURL.isEmpty else { throw MessagingFailure.contextChanged }
        // Une identité d'appareil par compte, école et serveur ; l'époque d'accès ne détruit pas les clés.
        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.apiBaseURL)"
        fingerprint = SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
        folder = base.appendingPathComponent("MessagingCrypto", isDirectory: true).appendingPathComponent(fingerprint, isDirectory: true)
    }

    func secrets() throws -> Secrets {
        let manager = FileManager.default
        if let existing = try read() { return existing }
        if manager.fileExists(atPath: storePath) {
            // Store sans secret : vide (essai précédent interrompu) il est recréé, sinon erreur fermée.
            // Typiquement : app re-signée (autre équipe) qui garde le conteneur mais perd l'accès au Keychain.
            guard (try? manager.contentsOfDirectory(atPath: storePath))?.isEmpty == true else {
                diagnostics.recordIfEmpty("S-ORPHAN")
                throw MessagingFailure.protectionUnavailable
            }
            do { try manager.removeItem(atPath: storePath) }
            catch { diagnostics.recordIfEmpty("S-RM"); throw MessagingFailure.protectionUnavailable }
        }
        // Le secret est durable avant toute création du store : un échec Keychain ne bloque pas l'essai suivant.
        let fresh = Secrets(deviceID: try Self.randomDeviceID(), passphrase: try Self.random(32).base64EncodedString())
        try write(fresh)
        do {
            try manager.createDirectory(at: URL(fileURLWithPath: storePath), withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        } catch { diagnostics.recordIfEmpty("S-DIR"); throw MessagingFailure.protectionUnavailable }
        try protectStore()
        return fresh
    }

    func protectStore() throws {
        do {
            let manager = FileManager.default
            for url in [folder.deletingLastPathComponent(), folder, URL(fileURLWithPath: storePath)] where manager.fileExists(atPath: url.path) {
                try Self.protect(url)
            }
            if let items = manager.enumerator(at: URL(fileURLWithPath: storePath), includingPropertiesForKeys: nil) {
                for case let item as URL in items { try Self.protect(item) }
            }
        } catch {
            diagnostics.recordIfEmpty("S-PROT-\((error as NSError).code)")
            throw MessagingFailure.protectionUnavailable
        }
    }

    func load() throws -> State {
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return State() }
        do {
            let box = try AES.GCM.SealedBox(combined: try Data(contentsOf: stateFile))
            return try JSONDecoder().decode(State.self, from: try AES.GCM.open(box, using: try stateKey(), authenticating: Data(fingerprint.utf8)))
        } catch { diagnostics.recordIfEmpty("S-STATE"); throw MessagingFailure.protectionUnavailable }
    }

    func save(_ state: State) throws {
        do {
            let sealed = try AES.GCM.seal(try JSONEncoder().encode(state), using: try stateKey(), authenticating: Data(fingerprint.utf8))
            guard let bytes = sealed.combined else { throw MessagingFailure.protectionUnavailable }
            try bytes.write(to: stateFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try Self.protect(stateFile)
        } catch { diagnostics.recordIfEmpty("S-SAVE"); throw MessagingFailure.protectionUnavailable }
    }

    /// Journal indépendant : aucun save(State) de sync/backup ne peut le remplacer.
    func deviceSigningRecord() throws -> DeviceSigningRecord? {
        try Self.signingLock.withLock { try readDeviceSigning() }
    }

    func prepareDeviceSigning(_ create: () throws -> PendingDeviceSigning) throws -> DeviceSigningRecord {
        try Self.signingLock.withLock {
            if let existing = try readDeviceSigning() { return existing }
            let record = DeviceSigningRecord(intent: try create(), completed: false)
            try writeDeviceSigning(record)
            return record
        }
    }

    func completeDeviceSigning(expected: PendingDeviceSigning) throws {
        try Self.signingLock.withLock {
            guard var record = try readDeviceSigning(), record.intent == expected else {
                throw MessagingFailure.stateConflict
            }
            if record.completed { return }
            record.completed = true
            try writeDeviceSigning(record)
        }
    }

    private func readDeviceSigning() throws -> DeviceSigningRecord? {
        guard FileManager.default.fileExists(atPath: signingFile.path) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: signingFile))
            let clear = try AES.GCM.open(box, using: stateKey(),
                                         authenticating: Data("device-signing|\(fingerprint)".utf8))
            return try JSONDecoder().decode(DeviceSigningRecord.self, from: clear)
        } catch { diagnostics.recordIfEmpty("S-SIGN-READ"); throw MessagingFailure.protectionUnavailable }
    }

    private func writeDeviceSigning(_ record: DeviceSigningRecord) throws {
        do {
            let sealed = try AES.GCM.seal(JSONEncoder().encode(record), using: stateKey(),
                                         authenticating: Data("device-signing|\(fingerprint)".utf8))
            guard let bytes = sealed.combined else { throw MessagingFailure.protectionUnavailable }
            try bytes.write(to: signingFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try Self.protect(signingFile)
        } catch { diagnostics.recordIfEmpty("S-SIGN-SAVE"); throw MessagingFailure.protectionUnavailable }
    }

    private func stateKey() throws -> SymmetricKey {
        guard let secrets = try read(), let raw = Data(base64Encoded: secrets.passphrase) else { throw MessagingFailure.protectionUnavailable }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: raw), info: Data("drivy.messaging.crypto.state".utf8), outputByteCount: 32)
    }

    private func read() throws -> Secrets? {
        let data: Data
        do {
            guard let found = try keychain.read(service: Self.service, account: fingerprint) else { return nil }
            data = found
        } catch { throw keychainFailure(error, operation: "R") }
        guard let pair = try? JSONDecoder().decode([String: String].self, from: data),
              let device = pair["deviceId"], let passphrase = pair["passphrase"],
              MessagingCryptoHTTPRelay.validDeviceID(device), Data(base64Encoded: passphrase)?.count == 32
        else { diagnostics.recordIfEmpty("K-R-FORMAT"); throw MessagingFailure.protectionUnavailable }
        return Secrets(deviceID: device, passphrase: passphrase)
    }

    private func write(_ secrets: Secrets) throws {
        let data = try JSONEncoder().encode(["deviceId": secrets.deviceID, "passphrase": secrets.passphrase])
        do { try keychain.add(service: Self.service, account: fingerprint, data: data) }
        catch { throw keychainFailure(error, operation: "A") }
    }

    private func keychainFailure(_ error: any Error, operation: String) -> MessagingFailure {
        if let keychain = error as? MessagingKeychainError {
            diagnostics.recordIfEmpty(MessagingDiagnostics.keychain(keychain.operation, keychain.status))
        } else {
            diagnostics.recordIfEmpty("K-\(operation)-X")
        }
        return .protectionUnavailable
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
