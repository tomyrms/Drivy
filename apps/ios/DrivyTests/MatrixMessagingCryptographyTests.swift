import XCTest
import MatrixSDKCrypto
@testable import Drivy

/// Écrits, non exécutés (#84) : à lancer sur runner Apple avec la bibliothèque native.
final class MatrixMessagingCryptographyTests: XCTestCase {
    private let person = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let school = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let conversation = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    private var scope: MessagingScope { MessagingScope(accountID: person, schoolID: school, accessEpoch: 1, apiBaseURL: "https://api.example.test") }

    func testIdentifiersRoundTrip() {
        let user = MatrixMessagingCryptography.userID(person)
        XCTAssertEqual(user, "@11111111-1111-4111-8111-111111111111:drivy")
        XCTAssertEqual(MatrixMessagingCryptography.person(fromUserID: user), person)
        XCTAssertNil(MatrixMessagingCryptography.person(fromUserID: "@x:matrix.org"))
        XCTAssertEqual(MatrixMessagingCryptography.roomID(conversation), "!33333333-3333-4333-8333-333333333333:drivy")
    }

    func testRotationOnlyWhenSomeoneLeaves() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertFalse(MatrixMessagingCryptography.someoneLeft(previous: nil, current: [a]))
        XCTAssertFalse(MatrixMessagingCryptography.someoneLeft(previous: [a, b], current: [a, b, c]))
        XCTAssertTrue(MatrixMessagingCryptography.someoneLeft(previous: [a, b], current: [a]))
    }

    func testRotationWhenMembersEpochChanges() {
        let a = UUID(), b = UUID()
        XCTAssertTrue(MatrixMessagingCryptography.mustRotate(previous: [a, b], current: [a, b], previousEpoch: 1, currentEpoch: 2))
        XCTAssertFalse(MatrixMessagingCryptography.mustRotate(previous: [a, b], current: [a, b], previousEpoch: 2, currentEpoch: 2))
        XCTAssertFalse(MatrixMessagingCryptography.mustRotate(previous: [a, b], current: [a, b], previousEpoch: nil, currentEpoch: 3))
        XCTAssertTrue(MatrixMessagingCryptography.mustRotate(previous: [a, b], current: [a], previousEpoch: nil, currentEpoch: nil))
    }

    func testLeftDevicesSelectAffectedConversations() {
        let a = UUID(), b = UUID(), c1 = UUID(), c2 = UUID()
        let members = [c1: [a, b], c2: [a]]
        XCTAssertEqual(MatrixMessagingCryptography.conversationsAffected(byLeft: [MatrixMessagingCryptography.userID(b)], members: members), [c1])
        XCTAssertEqual(MatrixMessagingCryptography.conversationsAffected(byLeft: [], members: members), [])
        XCTAssertEqual(MatrixMessagingCryptography.conversationsAffected(byLeft: ["@x:matrix.org"], members: members), [])
    }

    func testStateDecodesWithoutNewFields() throws {
        let state = try JSONDecoder().decode(MessagingCryptoVault.State.self, from: Data("{\"syncToken\":\"s\"}".utf8))
        XCTAssertEqual(state.syncToken, "s"); XCTAssertFalse(state.backupPending); XCTAssertTrue(state.membersEpoch.isEmpty)
    }

    func testKeychainFailureDoesNotBlockNextAttempt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = FlakyKeychain()
        let vault = try MessagingCryptoVault(scope: scope, root: root, keychain: keychain)
        keychain.failNextAdd()
        XCTAssertThrowsError(try vault.secrets())
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.storePath))
        let first = try vault.secrets()
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.storePath))
        XCTAssertEqual(try vault.secrets().deviceID, first.deviceID)
    }

    func testEmptyStoreWithoutSecretIsRecreatedButFilledStoreIsRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain())
        try FileManager.default.createDirectory(atPath: vault.storePath, withIntermediateDirectories: true)
        XCTAssertNoThrow(try vault.secrets())
        let other = try MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain())
        try Data("x".utf8).write(to: URL(fileURLWithPath: other.storePath).appendingPathComponent("db"))
        XCTAssertThrowsError(try other.secrets())
    }

    func testRoutesMatchRelayContract() throws {
        let upload = try MatrixMessagingCryptography.route(.keysUpload(requestId: "r1", body: "{}"))
        XCTAssertEqual(upload.0, "POST"); XCTAssertEqual(upload.1, ["keys", "upload"])
        let toDevice = try MatrixMessagingCryptography.route(.toDevice(requestId: "t1", eventType: "m.room.encrypted", body: "{\"@a:drivy\":{}}"))
        XCTAssertEqual(toDevice.0, "PUT"); XCTAssertEqual(toDevice.1, ["sendToDevice", "m.room.encrypted", "t1"])
        XCTAssertEqual(String(decoding: toDevice.3, as: UTF8.self), "{\"messages\":{\"@a:drivy\":{}}}")
        let backup = try MatrixMessagingCryptography.route(.keysBackup(requestId: "b", version: "3", rooms: "{}"))
        XCTAssertEqual(backup.1, ["room_keys", "keys"]); XCTAssertEqual(backup.2.first?.value, "3")
        XCTAssertThrowsError(try MatrixMessagingCryptography.route(.roomMessage(requestId: "x", roomId: "!r:drivy", eventType: "m.room.message", content: "{}")))
    }

    func testEnvelopeRejectsNonMegolmAndKeepsSessionID() throws {
        let content = "{\"algorithm\":\"m.megolm.v1.aes-sha2\",\"ciphertext\":\"AwgA\",\"session_id\":\"ab+c/d\",\"sender_key\":\"k\",\"device_id\":\"D\"}"
        let envelope = try MatrixMessagingCryptography.envelope(fromEncryptedContent: content)
        XCTAssertEqual(envelope.scheme, "megolm.v1"); XCTAssertEqual(envelope.keyID, "ab-c_d")
        XCTAssertThrowsError(try MatrixMessagingCryptography.envelope(fromEncryptedContent: "{\"algorithm\":\"none\",\"body\":\"clair\"}"))
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: person,
                                           acceptedAt: Date(timeIntervalSince1970: 1), ciphertext: envelope)
        let event = try MatrixMessagingCryptography.encryptedEvent(message: message, ciphertext: envelope)
        XCTAssertTrue(event.contains("\"sender\":\"@11111111-1111-4111-8111-111111111111:drivy\""))
        let forged = MessagingCiphertext(scheme: "megolm.v1", keyID: "autre", payload: envelope.payload)
        XCTAssertThrowsError(try MatrixMessagingCryptography.encryptedEvent(message: message, ciphertext: forged))
    }

    func testSyncPageParsing() throws {
        let raw = Data("{\"to_device\":{\"events\":[{\"type\":\"m.room.encrypted\"}]},\"device_lists\":{\"changed\":[\"@a:drivy\"],\"left\":[]},\"device_one_time_keys_count\":{\"signed_curve25519\":12},\"next_batch\":\"n2\"}".utf8)
        let page = try MatrixMessagingCryptography.syncPage(raw)
        XCTAssertEqual(page.next, "n2"); XCTAssertEqual(page.eventCount, 1)
        XCTAssertEqual(page.counts["signed_curve25519"], 12); XCTAssertEqual(page.changed, ["@a:drivy"])
        XCTAssertThrowsError(try MatrixMessagingCryptography.syncPage(Data("{}".utf8)))
    }

    func testRelayUnwrapChecksContext() throws {
        let ok = Data("{\"data\":{\"one_time_key_counts\":{}},\"context\":{\"schoolId\":\"\(school)\",\"actorPersonId\":\"\(person)\",\"accessEpoch\":1}}".utf8)
        XCTAssertNoThrow(try MessagingCryptoHTTPRelay.unwrap(ok, scope: scope))
        let other = Data("{\"data\":{},\"context\":{\"schoolId\":\"\(UUID())\",\"actorPersonId\":\"\(person)\",\"accessEpoch\":1}}".utf8)
        XCTAssertThrowsError(try MessagingCryptoHTTPRelay.unwrap(other, scope: scope))
        XCTAssertTrue(MessagingCryptoHTTPRelay.validDeviceID("ABCDEFGHIJ0123"))
        XCTAssertFalse(MessagingCryptoHTTPRelay.validDeviceID("abc"))
    }

    func testBackupRoundTripWithRecoveryKey() throws {
        let key = BackupRecoveryKey()
        let restored = try BackupRecoveryKey.fromBase58(key: key.toBase58())
        XCTAssertEqual(restored.megolmV1PublicKey().publicKey, key.megolmV1PublicKey().publicKey)
        XCTAssertThrowsError(try BackupRecoveryKey.fromBase58(key: "pas une clé"))
    }

    /// Deux appareils, relais en mémoire : chiffrement Megolm, déchiffrement, puis rotation au départ d'un membre.
    func testTwoDevicesExchangeAndRotateOnLeave() async throws {
        let relay = InMemoryRelay()
        let alice = UUID(), bob = UUID()
        await relay.setMembers(conversation, [alice, bob])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let aScope = MessagingScope(accountID: alice, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let bScope = MessagingScope(accountID: bob, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let a = try MatrixMessagingCryptography(scope: aScope, relay: relay.view(alice), vault: MessagingCryptoVault(scope: aScope, root: root))
        let b = try MatrixMessagingCryptography(scope: bScope, relay: relay.view(bob), vault: MessagingCryptoVault(scope: bScope, root: root))
        let availableB = await b.isAvailable(scope: bScope, conversationID: conversation)
        XCTAssertTrue(availableB)
        let first = try await a.encrypt(Data("Bonjour".utf8), mentions: [], scope: aScope, conversationID: conversation)
        XCTAssertFalse(String(decoding: first.payload, as: UTF8.self).contains("Bonjour"))
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: alice,
                                           acceptedAt: Date(), ciphertext: first)
        let clear = try await b.decrypt(message, scope: bScope)
        XCTAssertEqual(String(decoding: clear, as: UTF8.self), "Bonjour")
        await relay.setMembers(conversation, [alice])
        let second = try await a.encrypt(Data("Après".utf8), mentions: [], scope: aScope, conversationID: conversation)
        XCTAssertNotEqual(first.keyID, second.keyID)
        let late = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: alice,
                                        acceptedAt: Date(), ciphertext: second)
        do { _ = try await b.decrypt(late, scope: bScope); XCTFail("Un membre parti ne doit pas lire") }
        catch let failure as MessagingDecryptionFailure { XCTAssertTrue(failure.code.hasPrefix("D-"), failure.code) }
        catch { XCTFail("Refus attendu avec un code de déchiffrement, reçu \(error)") }
    }

    /// Départ puis retour entre deux envois : la liste est identique, l'époque change, la clé doit changer.
    func testLeaveAndReturnBetweenSendsRotates() async throws {
        let relay = InMemoryRelay()
        let alice = UUID(), bob = UUID()
        await relay.setMembers(conversation, [alice, bob])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let aScope = MessagingScope(accountID: alice, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let a = try MatrixMessagingCryptography(scope: aScope, relay: relay.view(alice), vault: MessagingCryptoVault(scope: aScope, root: root))
        let first = try await a.encrypt(Data("Un".utf8), mentions: [], scope: aScope, conversationID: conversation)
        let steady = try await a.encrypt(Data("Deux".utf8), mentions: [], scope: aScope, conversationID: conversation)
        XCTAssertEqual(first.keyID, steady.keyID)
        XCTAssertEqual(first.expectedMembersEpoch, 0)
        XCTAssertEqual(steady.expectedMembersEpoch, 0)
        await relay.setMembers(conversation, [alice])
        await relay.setMembers(conversation, [alice, bob])
        let after = try await a.encrypt(Data("Trois".utf8), mentions: [], scope: aScope, conversationID: conversation)
        XCTAssertNotEqual(steady.keyID, after.keyID)
        XCTAssertEqual(after.expectedMembersEpoch, 2)
    }

    /// B ne chiffre jamais de message : sa sauvegarde doit inclure la clé reçue d'A.
    func testReadOnlyRecipientBacksUpReceivedKeyAndNewDeviceRestores() async throws {
        let relay = InMemoryRelay()
        let alice = UUID(), bob = UUID()
        await relay.setMembers(conversation, [alice, bob])
        let aScope = MessagingScope(accountID: alice, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let bScope = MessagingScope(accountID: bob, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let a = try makeDevice(aScope, relay: relay)
        let b = try makeDevice(bScope, relay: relay)
        let recovery = try await b.enableBackup(scope: bScope)
        let encrypted = try await a.encrypt(Data("Lecture seule".utf8), mentions: [], scope: aScope, conversationID: conversation)
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: alice,
                                           acceptedAt: Date(), ciphertext: encrypted)
        let clear = try await b.decrypt(message, scope: bScope)
        XCTAssertEqual(clear, Data("Lecture seule".utf8))
        let pending = await b.backupPending(scope: bScope)
        XCTAssertFalse(pending)
        let b2 = try makeDevice(bScope, relay: relay)
        do {
            _ = try await b2.restoreBackup(recoveryKey: BackupRecoveryKey().toBase58(), scope: bScope)
            XCTFail("Une autre clé ne doit pas restaurer la sauvegarde")
        } catch { XCTAssertEqual(error as? MessagingFailure, .protectionUnavailable) }
        let restored = try await b2.restoreBackup(recoveryKey: recovery, scope: bScope)
        XCTAssertEqual(restored.imported, 1)
        XCTAssertEqual(restored.failed, 0)
        let restoredClear = try await b2.decrypt(message, scope: bScope)
        XCTAssertEqual(restoredClear, clear)
    }

    func testReceivedKeyBackupFailureRemainsSealedAndResumesWhenDeviceReopens() async throws {
        let relay = InMemoryRelay()
        let alice = UUID(), bob = UUID()
        await relay.setMembers(conversation, [alice, bob])
        let aScope = MessagingScope(accountID: alice, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let bScope = MessagingScope(accountID: bob, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try MessagingCryptoVault(scope: bScope, root: root, keychain: FlakyKeychain())
        let a = try makeDevice(aScope, relay: relay)
        var b: MatrixMessagingCryptography? = try MatrixMessagingCryptography(scope: bScope, relay: relay.view(bob), vault: vault)
        let recovery = try await b!.enableBackup(scope: bScope)
        await relay.setBackupUnavailable(true)
        let encrypted = try await a.encrypt(Data("À sauvegarder".utf8), mentions: [], scope: aScope, conversationID: conversation)
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: alice,
                                           acceptedAt: Date(), ciphertext: encrypted)
        let clear = try await b!.decrypt(message, scope: bScope)
        XCTAssertEqual(clear, Data("À sauvegarder".utf8), "La panne de sauvegarde ne bloque pas la lecture locale")
        let pending = await b!.backupPending(scope: bScope)
        XCTAssertTrue(pending)
        XCTAssertTrue(try vault.load().backupPending, "L'intention de sauvegarde survit dans state.sealed")
        b = nil
        await relay.setBackupUnavailable(false)
        let reopened = try MatrixMessagingCryptography(scope: bScope, relay: relay.view(bob), vault: vault)
        let pendingBeforeOpen = await reopened.backupPending(scope: bScope)
        XCTAssertTrue(pendingBeforeOpen, "Un nouveau modèle lit l'état scellé avant toute ouverture réseau")
        let available = await reopened.isAvailable(scope: bScope, conversationID: conversation)
        XCTAssertTrue(available)
        let resumedPending = await reopened.backupPending(scope: bScope)
        XCTAssertFalse(resumedPending)
        XCTAssertFalse(try vault.load().backupPending)
        let b2 = try makeDevice(bScope, relay: relay)
        do {
            _ = try await b2.restoreBackup(recoveryKey: BackupRecoveryKey().toBase58(), scope: bScope)
            XCTFail("Une autre clé ne doit pas restaurer la sauvegarde")
        } catch { XCTAssertEqual(error as? MessagingFailure, .protectionUnavailable) }
        let restored = try await b2.restoreBackup(recoveryKey: recovery, scope: bScope)
        XCTAssertEqual(restored.imported, 1)
        XCTAssertEqual(restored.failed, 0)
        let restoredClear = try await b2.decrypt(message, scope: bScope)
        XCTAssertEqual(restoredClear, clear)
    }

    /// Constat qa84 : B s'enregistre APRÈS un premier envoi de A (A suit déjà B sans appareil).
    /// A doit apprendre l'appareil de B par device_lists.changed, réclamer une OTK, partager la clé en to-device ;
    /// B doit déchiffrer le message suivant. Le message antérieur reste illisible avec un code non sensible.
    func testRecipientRegisteredAfterFirstSendDecryptsNextMessage() async throws {
        let relay = InMemoryRelay()
        let alice = UUID(), bob = UUID()
        await relay.setMembers(conversation, [alice, bob])
        let aScope = MessagingScope(accountID: alice, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let bScope = MessagingScope(accountID: bob, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let a = try makeDevice(aScope, relay: relay)
        let early = try await a.encrypt(Data("Avant".utf8), mentions: [], scope: aScope, conversationID: conversation)
        let toDeviceBefore = await relay.toDeviceCount()
        let diagnostics = MessagingDiagnostics()
        let b = try MatrixMessagingCryptography(scope: bScope, relay: relay.view(bob),
            vault: MessagingCryptoVault(scope: bScope, root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                                        keychain: FlakyKeychain(), diagnostics: diagnostics), diagnostics: diagnostics)
        let ready = await b.isAvailable(scope: bScope, conversationID: conversation)
        XCTAssertTrue(ready)
        let later = try await a.encrypt(Data("Après".utf8), mentions: [], scope: aScope, conversationID: conversation)
        let claims = await relay.claimCount()
        let toDeviceAfter = await relay.toDeviceCount()
        XCTAssertGreaterThan(claims, 0, "A doit réclamer une clé à usage unique de B")
        XCTAssertGreaterThan(toDeviceAfter, toDeviceBefore, "A doit envoyer la clé de salon en to-device")
        let message = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: alice,
                                           acceptedAt: Date(), ciphertext: later)
        let clear = try await b.decrypt(message, scope: bScope)
        XCTAssertEqual(clear, Data("Après".utf8))
        let old = MessagingWireMessage(id: UUID(), conversationID: conversation, schoolID: school, senderID: alice,
                                       acceptedAt: Date(), ciphertext: early)
        do { _ = try await b.decrypt(old, scope: bScope); XCTFail("Aucune clé antérieure à l'appareil") }
        catch let failure as MessagingDecryptionFailure {
            XCTAssertTrue(failure.code.hasPrefix("D-"))
            XCTAssertTrue(MessagingDiagnostics.isSafe(failure.code))
        }
    }

    /// Deux comptes sur le même téléphone (même Keychain, même dossier) : appareils distincts et persistants.
    func testTwoAccountsOnSamePhoneKeepSeparatePersistentDevices() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = FlakyKeychain()
        let aScope = MessagingScope(accountID: UUID(), schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let bScope = MessagingScope(accountID: UUID(), schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
        let a = try MessagingCryptoVault(scope: aScope, root: root, keychain: keychain).secrets()
        let b = try MessagingCryptoVault(scope: bScope, root: root, keychain: keychain).secrets()
        XCTAssertNotEqual(a.deviceID, b.deviceID)
        XCTAssertNotEqual(a.passphrase, b.passphrase)
        XCTAssertNotEqual(try MessagingCryptoVault(scope: aScope, root: root, keychain: keychain).storePath,
                          try MessagingCryptoVault(scope: bScope, root: root, keychain: keychain).storePath)
        // Reconnexion de A après B : même appareil, aucune recréation.
        XCTAssertEqual(try MessagingCryptoVault(scope: aScope, root: root, keychain: keychain).secrets().deviceID, a.deviceID)
        // Une nouvelle époque d'accès ne change pas l'identité d'appareil.
        let renewed = MessagingScope(accountID: aScope.accountID, schoolID: school, accessEpoch: 2, apiBaseURL: "https://a.test")
        XCTAssertEqual(try MessagingCryptoVault(scope: renewed, root: root, keychain: keychain).secrets().deviceID, a.deviceID)
    }

    func testDecryptionCodesAreFixedAndSafe() {
        XCTAssertEqual(MatrixMessagingCryptography.decryptionCode(.MissingRoomKey(error: "/var/x", withheldCode: nil)), "D-NOKEY")
        XCTAssertEqual(MatrixMessagingCryptography.decryptionCode(.MissingRoomKey(error: "x", withheldCode: "m.unverified")), "D-WH-MUNVERIFIED")
        XCTAssertEqual(MatrixMessagingCryptography.decryptionCode(.Megolm(error: "secret path")), "D-MEGOLM")
        XCTAssertEqual(MatrixMessagingCryptography.decryptionCode(.Store(error: "x")), "D-STORE")
        for code in ["D-NOKEY", "D-WH-MUNVERIFIED", "D-MEGOLM", "D-ID", "D-FORMAT", "D-STORE"] {
            XCTAssertTrue(MessagingDiagnostics.isSafe(code))
        }
    }

    private func makeDevice(_ scope: MessagingScope, relay: InMemoryRelay) throws -> MatrixMessagingCryptography {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try MatrixMessagingCryptography(scope: scope, relay: relay.view(scope.accountID),
            vault: MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain()))
    }

    func testCiphertextOnlyDecryptIsRefused() async throws {
        let relay = InMemoryRelay()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let crypto = try MatrixMessagingCryptography(scope: scope, relay: relay.view(person), vault: MessagingCryptoVault(scope: scope, root: root))
        let envelope = MessagingCiphertext(scheme: "megolm.v1", keyID: "k", payload: Data("x".utf8))
        do { _ = try await crypto.decrypt(envelope, scope: scope, conversationID: conversation); XCTFail() }
        catch { XCTAssertEqual(error as? MessagingFailure, .protectionUnavailable) }
    }
}

private final class FlakyKeychain: MessagingCryptoKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    private var failing = false
    func failNextAdd() { lock.withLock { failing = true } }
    func read(service: String, account: String) throws -> Data? { lock.withLock { items["\(service)|\(account)"] } }
    func add(service: String, account: String, data: Data) throws {
        try lock.withLock {
            if failing { failing = false; throw MessagingFailure.protectionUnavailable }
            items["\(service)|\(account)"] = data
        }
    }
}

/// Relais minimal reproduisant la sémantique Matrix pour deux appareils (tests uniquement).
private actor InMemoryRelay {
    private var deviceKeys: [String: [String: Any]] = [:]
    private var oneTimeKeys: [String: [String: [String: Any]]] = [:]
    private var inbox: [String: [[String: Any]]] = [:]
    private var deliveredTransactions: Set<String> = []
    private var members: [UUID: [UUID]] = [:]
    private struct Backup {
        let version: String
        let algorithm: String
        let authData: [String: Any]
        var rooms: [String: [String: [String: Any]]] = [:]
        var etag = 0
        var count: Int { rooms.values.reduce(0) { $0 + $1.count } }
    }
    private var backups: [String: Backup] = [:]
    private var backupUnavailable = false
    /// Comme le serveur : chaque publication de clés d'appareil apparaît dans device_lists.changed des autres.
    private var deviceListChanges: [String] = []
    private var claims = 0
    private var toDeviceMessages = 0
    func claimCount() -> Int { claims }
    func toDeviceCount() -> Int { toDeviceMessages }
    func setBackupUnavailable(_ value: Bool) { backupUnavailable = value }

    nonisolated func view(_ person: UUID) -> View { View(relay: self, person: person) }
    func setMembers(_ id: UUID, _ value: [UUID]) {
        let old = Set(members[id] ?? []), new = Set(value)
        let left = !old.subtracting(new).isEmpty
        let returned = !new.subtracting(old).intersection(everMember[id] ?? []).isEmpty
        if left || returned { epochs[id, default: 0] += 1 }
        everMember[id, default: []].formUnion(new)
        members[id] = value
    }

    struct View: MessagingCryptoRelay {
        let relay: InMemoryRelay
        let person: UUID
        func call(scope: MessagingScope, deviceID: String, method: String, path: [String], query: [URLQueryItem], body: Data?) async throws -> Data {
            guard scope.accountID == person else { throw MessagingFailure.contextChanged }
            return try await relay.handle(user: MatrixMessagingCryptography.userID(person), school: scope.schoolID,
                device: deviceID, method: method, path: path, query: query, body: body)
        }
        func members(scope: MessagingScope, deviceID: String, conversationID: UUID) async throws -> MessagingConversationMembers {
            await relay.memberList(conversationID)
        }
    }

    /// Comme le serveur : l'époque augmente à chaque départ et à chaque retour, pas à la première arrivée.
    private var epochs: [UUID: Int] = [:]
    private var everMember: [UUID: Set<UUID>] = [:]
    func memberList(_ id: UUID) -> MessagingConversationMembers {
        MessagingConversationMembers(members: members[id] ?? [], membersEpoch: epochs[id] ?? 0)
    }

    func handle(user: String, school: UUID, device: String, method: String, path: [String], query: [URLQueryItem], body: Data?) throws -> Data {
        let input = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        var output: [String: Any] = [:]
        let backupOwner = "\(school)|\(user)"
        switch path.joined(separator: "/") {
        case "room_keys/version":
            if method == "POST" {
                guard backups[backupOwner] == nil else { throw MessagingCryptoRelayFailure.backupVersionConflict }
                guard let algorithm = input["algorithm"] as? String,
                      let auth = input["auth_data"] as? [String: Any], auth["public_key"] is String else {
                    throw MessagingFailure.invalidResponse
                }
                backups[backupOwner] = Backup(version: "1", algorithm: algorithm, authData: auth)
                output = ["version": "1"]
            } else if method == "GET" {
                guard let backup = backups[backupOwner] else { throw MessagingCryptoRelayFailure.notFound }
                output = ["version": backup.version, "algorithm": backup.algorithm, "auth_data": backup.authData,
                          "count": backup.count, "etag": String(backup.etag)]
            } else { throw MessagingFailure.invalidResponse }
        case "room_keys/keys":
            guard var backup = backups[backupOwner], query.first(where: { $0.name == "version" })?.value == backup.version else {
                throw MessagingCryptoRelayFailure.backupVersionConflict
            }
            if method == "GET" {
                output = ["rooms": backup.rooms.mapValues { ["sessions": $0] }]
            } else if method == "PUT" {
                if backupUnavailable { throw MessagingFailure.unavailable }
                guard let rooms = input["rooms"] as? [String: [String: Any]] else { throw MessagingFailure.invalidResponse }
                var changed = false
                for (room, value) in rooms {
                    guard let sessions = value["sessions"] as? [String: [String: Any]] else { throw MessagingFailure.invalidResponse }
                    for (id, data) in sessions {
                        guard let sealed = data["session_data"] as? [String: Any], sealed["ephemeral"] is String,
                              sealed["mac"] is String, sealed["ciphertext"] is String else { throw MessagingFailure.invalidResponse }
                        if let existing = backup.rooms[room]?[id], !Self.betterBackup(data, than: existing) { continue }
                        backup.rooms[room, default: [:]][id] = data
                        changed = true
                    }
                }
                if changed { backup.etag += 1 }
                backups[backupOwner] = backup
                output = ["etag": String(backup.etag), "count": backup.count]
            } else { throw MessagingFailure.invalidResponse }
        case "keys/upload":
            if let keys = input["device_keys"] as? [String: Any] { deviceKeys["\(user)|\(device)"] = keys; deviceListChanges.append(user) }
            var mine = oneTimeKeys["\(user)|\(device)"] ?? [:]
            for (id, key) in (input["one_time_keys"] as? [String: Any]) ?? [:] { mine[id] = ["k": key] }
            oneTimeKeys["\(user)|\(device)"] = mine
            output = ["one_time_key_counts": ["signed_curve25519": mine.count]]
        case "keys/query":
            var result: [String: [String: Any]] = [:]
            for requested in ((input["device_keys"] as? [String: Any]) ?? [:]).keys {
                for (id, keys) in deviceKeys where id.hasPrefix(requested + "|") {
                    result[requested, default: [:]][String(id.split(separator: "|")[1])] = keys
                }
            }
            output = ["device_keys": result, "failures": [String: Any]()]
        case "keys/claim":
            var result: [String: [String: [String: Any]]] = [:]
            for (target, devices) in (input["one_time_keys"] as? [String: [String: String]]) ?? [:] {
                for targetDevice in devices.keys {
                    let id = "\(target)|\(targetDevice)"
                    if let (keyID, entry) = oneTimeKeys[id]?.first {
                        claims += 1
                        oneTimeKeys[id]?.removeValue(forKey: keyID)
                        result[target, default: [:]][targetDevice] = [keyID: entry["k"]!]
                    }
                }
            }
            output = ["one_time_keys": result, "failures": [String: Any]()]
        case let route where route.hasPrefix("sendToDevice/"):
            guard method == "PUT", path.count == 3 else { throw MessagingFailure.invalidResponse }
            let transaction = "\(school)|\(user)|\(device)|\(path[2])"
            if deliveredTransactions.contains(transaction) { break }
            deliveredTransactions.insert(transaction)
            let type = path[1]
            // Mêmes refus que messaging-keys.ts : un corps doublement enveloppé ou mal formé échoue en 400, pas en silence.
            guard input.count == 1, let messages = input["messages"] as? [String: [String: Any]] else { throw MessagingFailure.unavailable }
            for (target, devices) in messages {
                guard MatrixMessagingCryptography.person(fromUserID: target) != nil else { throw MessagingFailure.unavailable }
                for (targetDevice, content) in devices {
                    guard targetDevice == "*" || MessagingCryptoHTTPRelay.validDeviceID(targetDevice), content is [String: Any] else {
                        throw MessagingFailure.unavailable
                    }
                    inbox["\(target)|\(targetDevice)", default: []].append(["type": type, "sender": user, "content": content])
                    toDeviceMessages += 1
                }
            }
        case "sync":
            guard method == "GET" else { throw MessagingFailure.invalidResponse }
            let queued = inbox["\(user)|\(device)"] ?? []
            let since = query.first(where: { $0.name == "since" })?.value ?? "0_0"
            let parts = since.split(separator: "_").compactMap { Int($0) }
            guard parts.count == 2, (0...queued.count).contains(parts[0]), (0...deviceListChanges.count).contains(parts[1]) else {
                throw MessagingFailure.invalidResponse
            }
            let offset = parts[0]
            // Une réponse perdue peut être rejouée : seule la progression de since change la page.
            let events = Array(queued.dropFirst(offset).prefix(100))
            let changed = query.isEmpty ? [] : Array(Set(deviceListChanges.dropFirst(parts[1]).filter { $0 != user })).sorted()
            output = ["to_device": ["events": events], "device_lists": ["changed": changed, "left": [String]()],
                      "device_one_time_keys_count": ["signed_curve25519": oneTimeKeys["\(user)|\(device)"]?.count ?? 0],
                      "next_batch": "\(offset + events.count)_\(deviceListChanges.count)"]
        default:
            throw MessagingFailure.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: output)
    }

    /// Même priorité que putBackupKeys : vérifiée, premier index, nombre de transferts.
    private static func betterBackup(_ next: [String: Any], than previous: [String: Any]) -> Bool {
        let verified = next["is_verified"] as? Bool ?? false
        let oldVerified = previous["is_verified"] as? Bool ?? false
        if verified != oldVerified { return verified }
        let index = next["first_message_index"] as? Int ?? Int.max
        let oldIndex = previous["first_message_index"] as? Int ?? Int.max
        if index != oldIndex { return index < oldIndex }
        return (next["forwarded_count"] as? Int ?? Int.max) < (previous["forwarded_count"] as? Int ?? Int.max)
    }
}
