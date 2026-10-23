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
        catch { XCTAssertEqual(error as? MessagingFailure, .protectionUnavailable) }
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
        await relay.setMembers(conversation, [alice])
        await relay.setMembers(conversation, [alice, bob])
        let after = try await a.encrypt(Data("Trois".utf8), mentions: [], scope: aScope, conversationID: conversation)
        XCTAssertNotEqual(steady.keyID, after.keyID)
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
    private var members: [UUID: [UUID]] = [:]

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
            try await relay.handle(user: MatrixMessagingCryptography.userID(person), device: deviceID, path: path, body: body)
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

    func handle(user: String, device: String, path: [String], body: Data?) throws -> Data {
        let input = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        var output: [String: Any] = [:]
        switch path.joined(separator: "/") {
        case "keys/upload":
            if let keys = input["device_keys"] as? [String: Any] { deviceKeys["\(user)|\(device)"] = keys }
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
                        oneTimeKeys[id]?.removeValue(forKey: keyID)
                        result[target, default: [:]][targetDevice] = [keyID: entry["k"]!]
                    }
                }
            }
            output = ["one_time_keys": result, "failures": [String: Any]()]
        case let route where route.hasPrefix("sendToDevice/"):
            let type = path[1]
            for (target, devices) in (input["messages"] as? [String: [String: Any]]) ?? [:] {
                for (targetDevice, content) in devices {
                    inbox["\(target)|\(targetDevice)", default: []].append(["type": type, "sender": user, "content": content])
                }
            }
        case "sync":
            let events = inbox.removeValue(forKey: "\(user)|\(device)") ?? []
            output = ["to_device": ["events": events], "device_lists": ["changed": [String](), "left": [String]()],
                      "device_one_time_keys_count": ["signed_curve25519": oneTimeKeys["\(user)|\(device)"]?.count ?? 0],
                      "next_batch": UUID().uuidString]
        default:
            output = [:]
        }
        return try JSONSerialization.data(withJSONObject: output)
    }
}
