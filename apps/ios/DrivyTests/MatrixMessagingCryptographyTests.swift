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
        } catch { XCTAssertEqual(error as? MessagingFailure, .recoveryKeyRefused) }
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
        } catch { XCTAssertEqual(error as? MessagingFailure, .recoveryKeyRefused) }
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

    // MARK: Vérification de ses appareils : régressions avant raccord UI

    /// Régression : updateTrackedUsers seul ne rafraîchit pas un compte déjà suivi.
    func testOwnDevicesRefreshFindsDeviceRegisteredAfterFirstListing() async throws {
        let relay = InMemoryRelay()
        let a = try makeDevice(scope, relay: relay)
        let first = try await a.ownDevices(scope: scope)
        XCTAssertEqual(first.filter { !$0.isCurrent }.count, 0)
        let b = try makeDevice(scope, relay: relay)
        let bDevices = try await b.ownDevices(scope: scope)
        let target = try XCTUnwrap(bDevices.first(where: \.isCurrent))

        let refreshed = try await a.ownDevices(scope: scope)
        XCTAssertTrue(refreshed.contains { $0.id == target.id && $0.fingerprint == target.fingerprint },
                      "Actualiser doit découvrir le nouvel appareil du même compte")
    }

    /// Le SDK réel produit les signatures, le relais stocke les documents publics sans fabriquer la confiance.
    func testConfirmOwnDevicePublishesSignatureAndReloadsSDKTrust() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        XCTAssertFalse(pair.target.isVerified)

        try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)

        let devices = try await pair.a.ownDevices(scope: scope)
        let verified = try XCTUnwrap(devices.first { $0.id == pair.target.id })
        XCTAssertTrue(verified.isVerified, "Le résultat doit être relu depuis la confiance du SDK")
    }

    func testConfirmOwnDeviceRejectsDifferentFingerprintBeforePublishingIdentity() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        do {
            try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: "different-public-fingerprint", scope: scope)
            XCTFail("Une comparaison différente ne peut pas vérifier l'appareil")
        } catch { XCTAssertEqual(error as? MessagingFailure, .protectionUnavailable) }
        let writes = await relay.verificationWriteCount()
        XCTAssertEqual(writes, 0, "Aucune identité ni signature publiée avant comparaison correcte")
    }

    func testConfirmOwnDeviceRejectsOtherScopeBeforePublishingIdentity() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        let other = MessagingScope(accountID: UUID(), schoolID: school, accessEpoch: 1, apiBaseURL: scope.apiBaseURL)
        do {
            try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: other)
            XCTFail("Un autre compte ne peut confirmer cet appareil")
        } catch { XCTAssertEqual(error as? MessagingFailure, .contextChanged) }
        let writes = await relay.verificationWriteCount()
        XCTAssertEqual(writes, 0)
    }

    /// HTTP 200 ne vaut pas acceptation : l'API renvoie les refus dans failures.
    func testConfirmOwnDeviceRejectsPartialSignatureFailure() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        await relay.setSignatureFault(.refused, target: pair.target.id)
        do {
            try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
            XCTFail("Un refus de signature HTTP 200 ne doit pas retourner un succès")
        } catch {
            XCTAssertNotNil(error as? MessagingFailure)
        }
        let refusals = await relay.signatureFaultCount()
        XCTAssertEqual(refusals, 1, "Atteindre le refus de la signature de B, pas échouer avant")
        let devices = try await pair.a.ownDevices(scope: scope)
        XCTAssertFalse(try XCTUnwrap(devices.first { $0.id == pair.target.id }).isVerified,
                       "Une signature refusée ne doit pas apparaître vérifiée après relecture")
    }

    func testConfirmOwnDeviceRejectsMalformedSignatureAcknowledgement() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        await relay.setSignatureFault(.malformed, target: pair.target.id)
        do {
            try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
            XCTFail("Une réponse sans failures typé ne confirme aucune signature")
        } catch {
            XCTAssertNotNil(error as? MessagingFailure)
        }
        let faults = await relay.signatureFaultCount()
        XCTAssertEqual(faults, 1)
    }

    func testConfirmOwnDeviceRejectsDeviceRevokedAfterComparison() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        await relay.removeDevice(person, device: pair.target.id)
        do {
            try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
            XCTFail("Une empreinte comparée avant révocation ne permet pas de confirmer l'appareil retiré")
        } catch { XCTAssertNotNil(error as? MessagingFailure) }
    }

    /// L'identité privée créée avant un échec réseau ne prouve pas sa publication.
    func testConfirmOwnDeviceRetriesBootstrapNotAcceptedByRelay() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        await relay.failNextSigningUpload(afterCommit: false)
        do {
            try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
            XCTFail("La publication initiale est indisponible")
        } catch { XCTAssertNotNil(error as? MessagingFailure) }

        try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
        let devices = try await pair.a.ownDevices(scope: scope)
        XCTAssertTrue(try XCTUnwrap(devices.first { $0.id == pair.target.id }).isVerified)
        let published = await relay.hasPublishedIdentity(person)
        XCTAssertTrue(published, "La reprise doit publier l'identité, pas seulement signer B localement")
    }

    /// Une réponse perdue ne doit ni remplacer ni régénérer la master key déjà acceptée.
    func testConfirmOwnDeviceReconcilesLostBootstrapResponseWithoutReplacingIdentity() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        await relay.failNextSigningUpload(afterCommit: true)
        do {
            try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
            XCTFail("La réponse de publication est perdue")
        } catch { XCTAssertNotNil(error as? MessagingFailure) }
        let acceptedMaster = await relay.publishedMasterKey(person)
        let firstMaster = try XCTUnwrap(acceptedMaster)

        try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
        let finalMaster = await relay.publishedMasterKey(person)
        XCTAssertEqual(finalMaster, firstMaster)
        let devices = try await pair.a.ownDevices(scope: scope)
        XCTAssertTrue(try XCTUnwrap(devices.first { $0.id == pair.target.id }).isVerified)
    }

    /// B possède ses clés d'appareil, pas les secrets cross-signing de A.
    func testDeviceWithoutPrivateSigningKeyDoesNotAttemptToReplaceExistingIdentity() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
        let before = await relay.signingUploadCount()
        do {
            try await pair.b.confirmOwnDevice(deviceID: pair.current.id, fingerprint: pair.current.fingerprint, scope: scope)
            XCTFail("B doit demander l'appareil d'origine, pas réinitialiser l'identité")
        } catch { XCTAssertNotNil(error as? MessagingFailure) }
        let after = await relay.signingUploadCount()
        XCTAssertEqual(after, before, "L'absence de clé privée n'autorise aucune tentative de remplacement")
    }

    func testDeviceVerificationSnapshotExposesLocalFingerprintAndPrivateCapability() async throws {
        let relay = InMemoryRelay()
        let pair = try await verificationPair(relay)
        let before = try await pair.a.deviceVerificationSnapshot(scope: scope)
        XCTAssertEqual(before.localDevice.id, pair.current.id)
        XCTAssertEqual(before.localDevice.fingerprint, pair.current.fingerprint)
        XCTAssertEqual(before.capability, .available)
        XCTAssertFalse(before.devices.contains(where: \.isCurrent))
        try await pair.a.confirmOwnDevice(deviceID: pair.target.id, fingerprint: pair.target.fingerprint, scope: scope)
        let onB = try await pair.b.deviceVerificationSnapshot(scope: scope)
        XCTAssertEqual(onB.localDevice.fingerprint, pair.target.fingerprint)
        XCTAssertEqual(onB.capability, .originalDeviceRequired)
        let onA = try await pair.a.deviceVerificationSnapshot(scope: scope)
        XCTAssertEqual(onA.capability, .available)
    }

    func testLocalFingerprintDoesNotDependOnServerDeviceProjection() async throws {
        let relay = InMemoryRelay()
        let device = try makeDevice(scope, relay: relay)
        let initial = try await device.deviceVerificationSnapshot(scope: scope)
        await relay.removeDevice(person, device: initial.localDevice.id)
        let withoutServerDevice = try await device.deviceVerificationSnapshot(scope: scope)
        XCTAssertFalse(initial.localDevice.fingerprint.isEmpty)
        XCTAssertEqual(withoutServerDevice.localDevice.fingerprint, initial.localDevice.fingerprint)
        XCTAssertEqual(withoutServerDevice.localDevice.id, initial.localDevice.id)
    }

    func testSigningBootstrapIntentSurvivesDeviceReopen() async throws {
        let relay = InMemoryRelay()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain())
        var a: MatrixMessagingCryptography? = try MatrixMessagingCryptography(scope: scope, relay: relay.view(person), vault: vault)
        let b = try makeDevice(scope, relay: relay)
        let bDevices = try await b.ownDevices(scope: scope)
        let target = try XCTUnwrap(bDevices.first(where: \.isCurrent))
        await relay.failNextSigningUpload(afterCommit: false)
        do {
            try await a!.confirmOwnDevice(deviceID: target.id, fingerprint: target.fingerprint, scope: scope)
            XCTFail("La publication initiale doit échouer")
        } catch { XCTAssertNotNil(error as? MessagingFailure) }
        let pending = try XCTUnwrap(vault.deviceSigningRecord()).intent
        let expected = try pending.identity()
        a = nil
        let reopened = try MatrixMessagingCryptography(scope: scope, relay: relay.view(person), vault: vault)
        try await reopened.confirmOwnDevice(deviceID: target.id, fingerprint: target.fingerprint, scope: scope)
        XCTAssertTrue(try XCTUnwrap(vault.deviceSigningRecord()).completed)
        let published = await relay.publishedMasterKey(person)
        XCTAssertEqual(published, expected.master?.keys.values.first)
        let devices = try await reopened.ownDevices(scope: scope)
        XCTAssertTrue(try XCTUnwrap(devices.first { $0.id == target.id }).isVerified)
    }

    func testConcurrentBackupCannotEraseSigningIntentAndReopenResumesSameIdentity() async throws {
        let relay = InMemoryRelay()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain())
        var signer: MatrixMessagingCryptography? = try MatrixMessagingCryptography(scope: scope, relay: relay.view(person), vault: vault)
        var staleWriter: MatrixMessagingCryptography? = try MatrixMessagingCryptography(scope: scope, relay: relay.view(person), vault: vault)
        let ready = await staleWriter!.isAvailable(scope: scope, conversationID: conversation)
        XCTAssertTrue(ready, "Le second écrivain charge son ancien snapshot avant le bootstrap")
        let other = try makeDevice(scope, relay: relay)
        let devices = try await other.ownDevices(scope: scope)
        let target = try XCTUnwrap(devices.first(where: \.isCurrent))
        await relay.holdNextSigningUpload()
        await relay.failNextSigningUpload(afterCommit: false)
        let task = Task { [signer = signer!, scope = scope] in
            do {
                try await signer.confirmOwnDevice(deviceID: target.id, fingerprint: target.fingerprint, scope: scope)
                XCTFail("La publication suspendue doit ensuite être refusée")
            } catch { XCTAssertNotNil(error as? MessagingFailure) }
            await relay.finishSigningAttempt()
        }
        guard await relay.waitForHeldSigningUpload() else {
            await task.value
            XCTFail("La tentative doit atteindre l'upload suspendu, pas échouer en préparation")
            return
        }
        let initial: MessagingCryptoVault.DeviceSigningRecord
        do {
            initial = try XCTUnwrap(vault.deviceSigningRecord())
            XCTAssertFalse(initial.completed)
            _ = try await staleWriter!.enableBackup(scope: scope)
            XCTAssertEqual(try vault.deviceSigningRecord(), initial,
                           "Le backup en vol sur le même coffre ne doit pas effacer l'intention")
        } catch {
            await relay.releaseSigningUpload()
            await task.value
            throw error
        }
        await relay.releaseSigningUpload()
        await task.value
        signer = nil
        staleWriter = nil
        let reopened = try MatrixMessagingCryptography(scope: scope, relay: relay.view(person), vault: vault)
        try await reopened.confirmOwnDevice(deviceID: target.id, fingerprint: target.fingerprint, scope: scope)
        let completed = try XCTUnwrap(vault.deviceSigningRecord())
        XCTAssertTrue(completed.completed)
        XCTAssertEqual(completed.intent, initial.intent, "Aucun reset ni remplacement à la reprise")
        let published = await relay.publishedMasterKey(person)
        XCTAssertEqual(published, try initial.intent.identity().master?.keys.values.first)
        let reloaded = try await reopened.ownDevices(scope: scope)
        XCTAssertTrue(try XCTUnwrap(reloaded.first { $0.id == target.id }).isVerified)
    }

    private func verificationPair(_ relay: InMemoryRelay) async throws ->
        (a: MatrixMessagingCryptography, b: MatrixMessagingCryptography, current: MessagingOwnDevice, target: MessagingOwnDevice) {
        let a = try makeDevice(scope, relay: relay)
        let b = try makeDevice(scope, relay: relay)
        let aReady = await a.isAvailable(scope: scope, conversationID: conversation)
        let bReady = await b.isAvailable(scope: scope, conversationID: conversation)
        XCTAssertTrue(aReady)
        XCTAssertTrue(bReady)
        let aDevices = try await a.ownDevices(scope: scope)
        let bDevices = try await b.ownDevices(scope: scope)
        let current = try XCTUnwrap(aDevices.first(where: \.isCurrent))
        let bCurrent = try XCTUnwrap(bDevices.first(where: \.isCurrent))
        let target = try XCTUnwrap(aDevices.first { $0.id == bCurrent.id })
        XCTAssertFalse(target.fingerprint.isEmpty)
        XCTAssertEqual(target.fingerprint, bCurrent.fingerprint)
        return (a, b, current, target)
    }

    private func makeDevice(_ scope: MessagingScope, relay: InMemoryRelay) throws -> MatrixMessagingCryptography {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try MatrixMessagingCryptography(scope: scope, relay: relay.view(scope.accountID),
            vault: MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain()))
    }

    /// #169 : seule la vérification refuse la clé ; réseau, session et absence de réponse gardent leur cause.
    func testRestoreFailureClassesNeverBlameKeyWhenRequestFailed() async throws {
        let cases: [(any Error, MessagingFailure)] = [
            (MessagingFailure.unavailable, .unavailable),
            (MessagingFailure.accessChanged, .accessChanged),
            (MessagingFailure.contextChanged, .contextChanged),
            (MessagingFailure.invalidResponse, .invalidResponse),
            (MessagingCryptoRelayFailure.notFound, .recoveryKeyRefused),
        ]
        let syntheticKey = BackupRecoveryKey().toBase58()
        for (thrown, expected) in cases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let crypto = try MatrixMessagingCryptography(scope: scope, relay: ThrowingRelay(error: thrown, base: InMemoryRelay().view(person)),
                vault: MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain()))
            do { _ = try await crypto.restoreBackup(recoveryKey: syntheticKey, scope: scope); XCTFail("\(expected)") }
            catch { XCTAssertEqual(error as? MessagingFailure, expected) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let crypto = try MatrixMessagingCryptography(scope: scope, relay: ThrowingRelay(error: MessagingFailure.unavailable, base: InMemoryRelay().view(person)),
            vault: MessagingCryptoVault(scope: scope, root: root, keychain: FlakyKeychain()))
        do { _ = try await crypto.restoreBackup(recoveryKey: "pas une clé", scope: scope); XCTFail() }
        catch { XCTAssertEqual(error as? MessagingFailure, .recoveryKeyRefused) }
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

/// Relais synthétique : la lecture de la version de sauvegarde échoue avec l'erreur donnée (#169).
private struct ThrowingRelay: MessagingCryptoRelay {
    let error: any Error & Sendable
    let base: InMemoryRelay.View
    func call(scope: MessagingScope, deviceID: String, method: String, path: [String], query: [URLQueryItem], body: Data?) async throws -> Data {
        if path.first == "room_keys" && method == "GET" { throw error }
        return try await base.call(scope: scope, deviceID: deviceID, method: method, path: path, query: query, body: body)
    }
    func members(scope: MessagingScope, deviceID: String, conversationID: UUID) async throws -> MessagingConversationMembers {
        try await base.members(scope: scope, deviceID: deviceID, conversationID: conversationID)
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
    // Cross-signing : documents publics réels du SDK, jamais de confiance attribuée par fixture.
    private var signingKeys: [String: [String: [String: Any]]] = [:]
    enum SignatureFault: Sendable { case refused, malformed }
    private var signatureFault: (mode: SignatureFault, target: String)?
    private var signatureFaults = 0
    private var signingUploads = 0
    private var signatureUploads = 0
    private var signingUploadFailureAfterCommit: Bool?
    private var holdSigningUpload = false
    private var heldSigningUpload: CheckedContinuation<Void, Never>?
    private var signingUploadStarted: CheckedContinuation<Bool, Never>?
    private var signingAttemptFinished = false
    func holdNextSigningUpload() { holdSigningUpload = true; signingAttemptFinished = false }
    func finishSigningAttempt() {
        signingAttemptFinished = true
        signingUploadStarted?.resume(returning: false)
        signingUploadStarted = nil
    }
    func pauseSigningUploadIfNeeded() async {
        guard holdSigningUpload else { return }
        holdSigningUpload = false
        await withCheckedContinuation { continuation in
            heldSigningUpload = continuation
            signingUploadStarted?.resume(returning: true)
            signingUploadStarted = nil
        }
    }
    func waitForHeldSigningUpload() async -> Bool {
        if heldSigningUpload != nil { return true }
        if signingAttemptFinished { return false }
        return await withCheckedContinuation { signingUploadStarted = $0 }
    }
    func releaseSigningUpload() { heldSigningUpload?.resume(); heldSigningUpload = nil }
    func setSignatureFault(_ mode: SignatureFault, target: String) { signatureFault = (mode, target) }
    func signatureFaultCount() -> Int { signatureFaults }
    func signingUploadCount() -> Int { signingUploads }
    func removeDevice(_ person: UUID, device: String) {
        let user = MatrixMessagingCryptography.userID(person)
        deviceKeys.removeValue(forKey: "\(user)|\(device)")
        oneTimeKeys.removeValue(forKey: "\(user)|\(device)")
        deviceListChanges.append(user)
    }
    func verificationWriteCount() -> Int { signingUploads + signatureUploads }
    func failNextSigningUpload(afterCommit: Bool) { signingUploadFailureAfterCommit = afterCommit }
    func hasPublishedIdentity(_ person: UUID) -> Bool {
        signingKeys[MatrixMessagingCryptography.userID(person)]?["master_key"] != nil
    }
    func publishedMasterKey(_ person: UUID) -> String? {
        let master = signingKeys[MatrixMessagingCryptography.userID(person)]?["master_key"]
        return (master?["keys"] as? [String: String])?.values.first
    }
    /// Comme le serveur : chaque publication de clés d'appareil apparaît dans device_lists.changed des autres.
    private var deviceListChanges: [String] = []
    private var claims = 0
    private var toDeviceMessages = 0
    func claimCount() -> Int { claims }
    func toDeviceCount() -> Int { toDeviceMessages }
    /// Administrateurs actifs de l'école, comme `GET crypto/report-recipients` : identifiants seulement.
    private var reportRecipients: [UUID: [UUID]] = [:]
    func setReportRecipients(_ school: UUID, _ people: [UUID]) { reportRecipients[school] = people }
    /// Messages to-device en attente pour une personne, tous appareils confondus.
    func queuedCount(for person: UUID) -> Int {
        let prefix = MatrixMessagingCryptography.userID(person) + "|"
        return inbox.filter { $0.key.hasPrefix(prefix) }.values.reduce(0) { $0 + $1.count }
    }
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
            if path == ["keys", "device_signing", "upload"] { await relay.pauseSigningUploadIfNeeded() }
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
        case "report-recipients":
            guard method == "GET" else { throw MessagingFailure.invalidResponse }
            output = ["recipients": (reportRecipients[school] ?? []).map { ["personId": $0.uuidString.lowercased()] }]
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
            var masters: [String: Any] = [:]
            var selfSigning: [String: Any] = [:]
            var userSigning: [String: Any] = [:]
            for requested in ((input["device_keys"] as? [String: Any]) ?? [:]).keys {
                masters[requested] = signingKeys[requested]?["master_key"]
                selfSigning[requested] = signingKeys[requested]?["self_signing_key"]
                if requested == user { userSigning[requested] = signingKeys[requested]?["user_signing_key"] }
            }
            output = ["device_keys": result, "failures": [String: Any](),
                      "master_keys": masters, "self_signing_keys": selfSigning, "user_signing_keys": userSigning]
        case "keys/device_signing/upload":
            guard method == "POST" else { throw MessagingFailure.invalidResponse }
            signingUploads += 1
            let failure = signingUploadFailureAfterCommit
            signingUploadFailureAfterCommit = nil
            if failure == false { throw MessagingFailure.unavailable }
            // Contrat actuel : même un master identique déjà présent est refusé, aucun remplacement.
            if signingKeys[user]?["master_key"] != nil, input["master_key"] != nil {
                throw MessagingFailure.stateConflict
            }
            let usages = ["master_key": "master", "self_signing_key": "self_signing", "user_signing_key": "user_signing"]
            for (field, usage) in usages {
                guard let raw = input[field] else { continue }
                guard let key = raw as? [String: Any], key["user_id"] as? String == user,
                      (key["usage"] as? [String])?.contains(usage) == true,
                      key["keys"] is [String: String] else { throw MessagingFailure.invalidResponse }
                signingKeys[user, default: [:]][field] = key
            }
            deviceListChanges.append(user)
            if failure == true { throw MessagingFailure.unavailable }
        case "keys/signatures/upload":
            guard method == "POST" else { throw MessagingFailure.invalidResponse }
            signatureUploads += 1
            if let fault = signatureFault, (input[user] as? [String: Any])?[fault.target] != nil {
                signatureFaults += 1
                switch fault.mode {
                case .refused:
                    output = ["failures": [user: [fault.target: ["errcode": "M_FORBIDDEN", "error": "Signature refusée."]]]]
                case .malformed:
                    output = ["failures": "not-an-object"]
                }
                break
            }
            var failures: [String: [String: Any]] = [:]
            for (owner, raw) in input {
                guard let signedKeys = raw as? [String: Any] else { throw MessagingFailure.invalidResponse }
                for (keyID, signed) in signedKeys {
                    guard owner == user, let signed = signed as? [String: Any] else {
                        failures[owner, default: [:]][keyID] = ["errcode": "M_FORBIDDEN", "error": "Signature refusée."]
                        continue
                    }
                    if let existing = deviceKeys["\(owner)|\(keyID)"] {
                        deviceKeys["\(owner)|\(keyID)"] = Self.mergeSignatures(existing, signed)
                    } else if let field = signingKeys[owner]?.first(where: {
                        ($0.value["keys"] as? [String: String])?.values.contains(keyID) == true
                    })?.key, let existing = signingKeys[owner]?[field] {
                        signingKeys[owner]?[field] = Self.mergeSignatures(existing, signed)
                    } else {
                        failures[owner, default: [:]][keyID] = ["errcode": "M_FORBIDDEN", "error": "Signature refusée."]
                    }
                }
            }
            deviceListChanges.append(user)
            output = ["failures": failures]
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
            let changed = query.isEmpty ? [] : Array(Set(deviceListChanges.dropFirst(parts[1]))).sorted()
            output = ["to_device": ["events": events], "device_lists": ["changed": changed, "left": [String]()],
                      "device_one_time_keys_count": ["signed_curve25519": oneTimeKeys["\(user)|\(device)"]?.count ?? 0],
                      "next_batch": "\(offset + events.count)_\(deviceListChanges.count)"]
        default:
            throw MessagingFailure.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: output)
    }

    /// Même fusion de signatures publiques que l'API. La validation cryptographique reste au SDK.
    private static func mergeSignatures(_ existing: [String: Any], _ incoming: [String: Any]) -> [String: Any] {
        var result = existing
        var signatures = existing["signatures"] as? [String: [String: String]] ?? [:]
        for (owner, values) in incoming["signatures"] as? [String: [String: String]] ?? [:] {
            signatures[owner, default: [:]].merge(values) { _, new in new }
        }
        result["signatures"] = signatures
        return result
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

/// Signalements (#77) : la clé de session d'un signalement est partagée aux appareils des administrateurs, et à eux seuls.
/// Deux, trois ou quatre appareils réels du SDK Matrix, relais en mémoire : le texte ne transite jamais en clair.
final class MatrixMessagingReportSealingTests: XCTestCase {
    private let school = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let conversation = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let alice = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let admin = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private let otherAdmin = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
    private let outsider = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!

    private func scope(_ person: UUID) -> MessagingScope {
        MessagingScope(accountID: person, schoolID: school, accessEpoch: 1, apiBaseURL: "https://a.test")
    }

    private func device(_ person: UUID, relay: InMemoryRelay) throws -> MatrixMessagingCryptography {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return try MatrixMessagingCryptography(scope: scope(person), relay: relay.view(person),
            vault: MessagingCryptoVault(scope: scope(person), root: root, keychain: FlakyKeychain()))
    }

    /// Ce que le serveur renvoie au lecteur : l'enveloppe, l'auteur du signalement, dans le salon de l'école.
    private func wire(_ sealed: MessagingCiphertext) -> MessagingWireMessage {
        MessagingWireMessage(id: UUID(), conversationID: school, schoolID: school, senderID: alice,
                             acceptedAt: Date(), ciphertext: sealed)
    }

    private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    func testSealedReportIsReadableByTheAdministratorDeviceAndNeverByAnOutsider() async throws {
        let relay = InMemoryRelay()
        await relay.setReportRecipients(school, [admin])
        let reporter = try device(alice, relay: relay)
        let administrator = try device(admin, relay: relay)
        let stranger = try device(outsider, relay: relay)
        let adminReady = await administrator.isAvailable(scope: scope(admin), conversationID: conversation)
        let strangerReady = await stranger.isAvailable(scope: scope(outsider), conversationID: conversation)
        XCTAssertTrue(adminReady)
        XCTAssertTrue(strangerReady)

        let sealed = try await reporter.sealForSchoolAdmins([Data("Premier message".utf8), Data("Second message".utf8)],
                                                            scope: scope(alice), conversationID: conversation)
        XCTAssertEqual(sealed.count, 2)
        XCTAssertEqual(sealed[0].scheme, "megolm.v1")
        // Une seule session pour tout le signalement, et jamais le texte dans l'enveloppe.
        XCTAssertEqual(sealed[0].keyID, sealed[1].keyID)
        XCTAssertFalse(text(sealed[0].payload).contains("Premier message"))
        XCTAssertFalse(text(sealed[1].payload).contains("Second message"))

        let first = try await administrator.decrypt(wire(sealed[0]), scope: scope(admin))
        let second = try await administrator.decrypt(wire(sealed[1]), scope: scope(admin))
        XCTAssertEqual(text(first), "Premier message")
        XCTAssertEqual(text(second), "Second message")

        // Le tiers n'a reçu aucune clé : le serveur n'a rien mis dans sa file, et il ne déchiffre pas.
        let queuedForStranger = await relay.queuedCount(for: outsider)
        XCTAssertEqual(queuedForStranger, 0)
        do {
            _ = try await stranger.decrypt(wire(sealed[0]), scope: scope(outsider))
            XCTFail("Un non-administrateur ne doit pas lire un signalement")
        } catch let failure as MessagingDecryptionFailure {
            XCTAssertEqual(failure.code, "D-NOKEY")
        } catch { XCTFail("Refus attendu avec un code de déchiffrement, reçu \(error)") }
    }

    func testAdministratorWithoutADeviceMeansNothingIsSealedOrSent() async throws {
        let relay = InMemoryRelay()
        await relay.setReportRecipients(school, [admin])
        let reporter = try device(alice, relay: relay)
        // L'administrateur est destinataire mais n'a jamais ouvert Messages : aucune clé d'appareil à utiliser.
        do {
            _ = try await reporter.sealForSchoolAdmins([Data("Sans appareil".utf8)], scope: scope(alice), conversationID: conversation)
            XCTFail("Aucun signalement ne part sans appareil d'administrateur")
        } catch { XCTAssertEqual(error as? MessagingFailure, .noReportRecipient) }
        let sent = await relay.toDeviceCount()
        XCTAssertEqual(sent, 0, "Aucune clé de session ne doit avoir été envoyée")

        // Sans aucun administrateur actif, même refus, sans même chercher de clés.
        await relay.setReportRecipients(school, [])
        let claimsBefore = await relay.claimCount()
        do {
            _ = try await reporter.sealForSchoolAdmins([Data("Personne".utf8)], scope: scope(alice), conversationID: conversation)
            XCTFail("Aucun signalement ne part sans administrateur")
        } catch { XCTAssertEqual(error as? MessagingFailure, .noReportRecipient) }
        let claimsAfter = await relay.claimCount()
        XCTAssertEqual(claimsAfter, claimsBefore)

        // Dès que l'administrateur ouvre Messages sur un appareil, le même signalant peut signaler et il lit.
        await relay.setReportRecipients(school, [admin])
        let administrator = try device(admin, relay: relay)
        let ready = await administrator.isAvailable(scope: scope(admin), conversationID: conversation)
        XCTAssertTrue(ready)
        let sealed = try await reporter.sealForSchoolAdmins(Data("Maintenant".utf8), scope: scope(alice), conversationID: conversation)
        let clear = try await administrator.decrypt(wire(sealed), scope: scope(admin))
        XCTAssertEqual(text(clear), "Maintenant")
    }

    func testEachReportHasItsOwnSessionSoALaterRevocationClosesTheNextOnes() async throws {
        let relay = InMemoryRelay()
        await relay.setReportRecipients(school, [admin, otherAdmin])
        let reporter = try device(alice, relay: relay)
        let first = try device(admin, relay: relay)
        let second = try device(otherAdmin, relay: relay)
        let firstReady = await first.isAvailable(scope: scope(admin), conversationID: conversation)
        let secondReady = await second.isAvailable(scope: scope(otherAdmin), conversationID: conversation)
        XCTAssertTrue(firstReady)
        XCTAssertTrue(secondReady)

        let before = try await reporter.sealForSchoolAdmins(Data("Avant la révocation".utf8), scope: scope(alice), conversationID: conversation)
        // Le second administrateur perd son rôle : il n'est plus destinataire du signalement suivant.
        await relay.setReportRecipients(school, [admin])
        let after = try await reporter.sealForSchoolAdmins(Data("Après la révocation".utf8), scope: scope(alice), conversationID: conversation)
        XCTAssertNotEqual(before.keyID, after.keyID, "Chaque signalement a sa propre session")

        let beforeByFirst = try await first.decrypt(wire(before), scope: scope(admin))
        let afterByFirst = try await first.decrypt(wire(after), scope: scope(admin))
        XCTAssertEqual(text(beforeByFirst), "Avant la révocation")
        XCTAssertEqual(text(afterByFirst), "Après la révocation")
        // Il garde ce qu'il avait déjà reçu, et ne lit rien de postérieur.
        let beforeBySecond = try await second.decrypt(wire(before), scope: scope(otherAdmin))
        XCTAssertEqual(text(beforeBySecond), "Avant la révocation")
        do {
            _ = try await second.decrypt(wire(after), scope: scope(otherAdmin))
            XCTFail("Un administrateur révoqué ne lit pas les signalements suivants")
        } catch let failure as MessagingDecryptionFailure { XCTAssertEqual(failure.code, "D-NOKEY") }
        catch { XCTFail("Refus attendu avec un code de déchiffrement, reçu \(error)") }
    }

    func testAnAdministratorDeviceRegisteredAfterTheReportDoesNotReadIt() async throws {
        let relay = InMemoryRelay()
        await relay.setReportRecipients(school, [admin])
        let reporter = try device(alice, relay: relay)
        let early = try device(admin, relay: relay)
        let earlyReady = await early.isAvailable(scope: scope(admin), conversationID: conversation)
        XCTAssertTrue(earlyReady)
        let sealed = try await reporter.sealForSchoolAdmins(Data("Déjà envoyé".utf8), scope: scope(alice), conversationID: conversation)

        // Limite documentée (messaging-reports-77.md, section 6) : seuls les appareils connus au moment du signalement reçoivent la clé.
        let late = try device(admin, relay: relay)
        let lateReady = await late.isAvailable(scope: scope(admin), conversationID: conversation)
        XCTAssertTrue(lateReady)
        let readByEarly = try await early.decrypt(wire(sealed), scope: scope(admin))
        XCTAssertEqual(text(readByEarly), "Déjà envoyé")
        do {
            _ = try await late.decrypt(wire(sealed), scope: scope(admin))
            XCTFail("Un appareil enregistré après le signalement ne reçoit pas la clé")
        } catch let failure as MessagingDecryptionFailure { XCTAssertEqual(failure.code, "D-NOKEY") }
        catch { XCTFail("Refus attendu avec un code de déchiffrement, reçu \(error)") }
    }

    @MainActor
    func testTheAdministratorScreenModelReadsASealedReportAndAnOutsiderGetsAnHonestMessage() async throws {
        let relay = InMemoryRelay()
        await relay.setReportRecipients(school, [admin])
        let reporter = try device(alice, relay: relay)
        let administrator = try device(admin, relay: relay)
        let stranger = try device(outsider, relay: relay)
        let adminReady = await administrator.isAvailable(scope: scope(admin), conversationID: conversation)
        let strangerReady = await stranger.isAvailable(scope: scope(outsider), conversationID: conversation)
        XCTAssertTrue(adminReady)
        XCTAssertTrue(strangerReady)

        // Le même contenu que le fil : une enveloppe JSON versionnée, scellée par le signalant.
        let content = try MessagingPlainContent(text: "Texte signalé").encoded()
        let sealed = try await reporter.sealForSchoolAdmins([content], scope: scope(alice), conversationID: conversation)
        let message = UUID()
        let record = MessagingReportRecord(id: UUID(), conversationID: conversation, conversationKind: "PRIVATE",
            reporterID: alice, reporterName: "Alice Fixture", createdAt: Date(), status: .open, statusUpdatedAt: nil,
            items: [MessagingReportEnvelope(messageID: message, senderID: UUID(), senderName: "Moniteur Fixture",
                                            sequence: 1, acceptedAt: Date(), ciphertext: sealed[0])],
            history: [])

        let adminScope = scope(admin)
        let adminModel = MessagingReportInboxModel(scope: adminScope, moderation: UnavailableMessagingThreadActions(),
                                                   cryptography: administrator, currentScope: { adminScope })
        await adminModel.open(record)
        let line = try XCTUnwrap(adminModel.lines[record.id]?.first)
        XCTAssertEqual(line.text, "Texte signalé")
        XCTAssertNil(line.unreadable)
        XCTAssertEqual(line.senderName, "Moniteur Fixture")

        let strangerScope = scope(outsider)
        let strangerModel = MessagingReportInboxModel(scope: strangerScope, moderation: UnavailableMessagingThreadActions(),
                                                      cryptography: stranger, currentScope: { strangerScope })
        await strangerModel.open(record)
        let blocked = try XCTUnwrap(strangerModel.lines[record.id]?.first)
        XCTAssertNil(blocked.text, "Aucun contenu inventé pour un message illisible")
        XCTAssertEqual(blocked.unreadable, MessagingDecryptionFailure.explanation(for: "D-NOKEY"))
    }
}
