import XCTest
import CryptoKit

@testable import Drivy

/// File d'intentions média durable et chiffrée (#97, T2b3).
///
/// Ces tests ont été écrits **avant** l'implémentation, mais ils n'ont pas été
/// exécutés sur le poste d'implémentation (Windows, aucun Xcode ni `swift`).
/// Aucun RED/GREEN natif n'est revendiqué : la preuve vient d'un runner Apple,
/// au SHA du commit. Aucune clé réelle ni Keychain système n'est utilisée ici :
/// chaque test injecte une racine temporaire et un fournisseur de clés
/// synthétique. Les erreurs d'entrée/sortie sont injectées par un adaptateur
/// fautif qui délègue au système de fichiers réel.
final class MessagingMediaOutboxTests: XCTestCase {

    // MARK: - Aller-retour et absence de clair sur disque

    func testPutRoundTripsThroughReopeningWithNoCleartextOnDisk() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let sealed = try sealMedia(plaintext: Data("SYNTHETIC_MEDIA_PLAINTEXT".utf8))
        let pending = try makePending(sealed)

        let first = try makeOutbox(scope: scope, root: root, keys: keys)
        try await first.put(pending, scope: scope)

        let reopened = try makeOutbox(scope: scope, root: root, keys: keys)
        let restored = try await reopened.entries(scope: scope)
        XCTAssertEqual(restored, [pending], "L'intention doit survivre intacte à la réouverture.")

        let folder = try scopeFolder(scope, root: root)
        XCTAssertEqual(folder.lastPathComponent, try scopeFingerprint(scope),
                       "Le dossier ne porte que l'empreinte opaque du scope.")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.lastPathComponent, try recordDigest(pending.mediaID, scope: scope) + ".sealed")
        XCTAssertNil(file.lastPathComponent.range(of: pending.mediaID.uuidString), "Aucun identifiant dans le nom")
        XCTAssertFalse(file.lastPathComponent.hasSuffix(".tmp"), "Aucun temporaire ne survit à un succès")

        let bytes = try Data(contentsOf: file)
        let sentinels: [(String, Data)] = [
            ("clientMessageID", Data(pending.clientMessageID.uuidString.utf8)),
            ("conversationID", Data(pending.conversationID.uuidString.utf8)),
            ("mediaID", Data(pending.mediaID.uuidString.utf8)),
            ("file name", Data(pending.content.media.name.utf8)),
            ("caption", Data("Légende".utf8)),
            ("plaintext", Data("SYNTHETIC_MEDIA_PLAINTEXT".utf8)),
            ("key", Data(sealed.info.key.k.utf8)),
            ("iv", Data(sealed.info.iv.utf8)),
            ("sha256", Data(sealed.info.hashes.sha256.utf8)),
            ("sealed media ciphertext", sealed.ciphertext)
        ]
        for (label, sentinel) in sentinels {
            XCTAssertNil(bytes.range(of: sentinel), "\(label) ne doit jamais apparaître en clair sur disque")
        }
    }

    func testFoldersAndRecordsAreExcludedFromBackup() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let sealed = try sealMedia()
        let pending = try makePending(sealed)
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        try await outbox.put(pending, scope: scope)

        let folder = try scopeFolder(scope, root: root)
        let folderValues = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(folderValues.isExcludedFromBackup, true, "Le dossier scellé ne part pas en sauvegarde")
        let file = folder.appendingPathComponent(try recordDigest(pending.mediaID, scope: scope) + ".sealed")
        let fileValues = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(fileValues.isExcludedFromBackup, true, "Chaque archive scellée ne part pas en sauvegarde")
        // La protection `complete` est appliquée par la même API que le store texte existant.
        // Sa relecture n'est pas garantie sur simulateur : elle n'est donc pas revendiquée ici.
    }

    // MARK: - Bornes de taille du média

    func testZeroByteMediaIsRefused() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let reference = try sealMedia()
        let empty = MessagingSealedMedia(mediaID: UUID(), ciphertext: Data(), info: reference.info)
        let pending = try makePending(empty, sizeOverride: 1)
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        await expectFailure(.invalidResponse) { try await outbox.put(pending, scope: scope) }
        let entries = try await outbox.entries(scope: scope)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0)
    }

    func testOversizeMediaIsRefused() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let reference = try sealMedia()
        let oversize = Data(repeating: 0xA5, count: AESCTRMediaCryptography.maximumByteSize + 1)
        let info = MessagingMediaEncryptionInfo(
            key: Data(repeating: 0x21, count: 32),
            iv: Data(repeating: 0, count: 16),
            sha256: Data(SHA256.hash(data: oversize)))
        let sealed = MessagingSealedMedia(mediaID: UUID(), ciphertext: oversize, info: info)
        XCTAssertNotEqual(sealed.info, reference.info)
        let pending = try makePending(sealed, sizeOverride: AESCTRMediaCryptography.maximumByteSize)
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        await expectFailure(.invalidResponse) { try await outbox.put(pending, scope: scope) }
        XCTAssertTrue(try await outbox.entries(scope: scope).isEmpty)
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0)
    }

    func testFourMebibyteMediaIsSealedDurably() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let plaintext = Data(repeating: 0x5A, count: AESCTRMediaCryptography.maximumByteSize)
        let sealed = try sealMedia(plaintext: plaintext, keyByte: 0x31)
        let pending = try makePending(sealed)
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        try await outbox.put(pending, scope: scope)
        let reopened = try makeOutbox(scope: scope, root: root, keys: keys)
        XCTAssertEqual(try await reopened.entries(scope: scope), [pending])
    }

    // MARK: - Cohérence contenu / sceau

    func testContentAndSealMustAgree() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let sealed = try sealMedia()
        let otherSeal = try sealMedia(plaintext: Data("OTHER".utf8), keyByte: 0x77)

        let identityMismatch = try makePending(sealed, mediaIDOverride: UUID())
        await expectFailure(.invalidResponse) { try await outbox.put(identityMismatch, scope: scope) }

        let sizeMismatch = try makePending(sealed, sizeOverride: sealed.byteSize - 1)
        await expectFailure(.invalidResponse) { try await outbox.put(sizeMismatch, scope: scope) }

        let fileMismatch = try makePending(sealed, fileOverride: otherSeal.info)
        await expectFailure(.invalidResponse) { try await outbox.put(fileMismatch, scope: scope) }

        XCTAssertTrue(try await outbox.entries(scope: scope).isEmpty)
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0)
    }

    // MARK: - Contexte complet exigé

    func testEveryScopeFieldIsRequiredAndExact() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let pending = try makePending(try sealMedia())
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        try await outbox.put(pending, scope: scope)

        let foreign = [
            MessagingScope(accountID: UUID(), schoolID: scope.schoolID,
                           accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: UUID(),
                           accessEpoch: scope.accessEpoch, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
                           accessEpoch: scope.accessEpoch + 1, apiBaseURL: scope.apiBaseURL),
            MessagingScope(accountID: scope.accountID, schoolID: scope.schoolID,
                           accessEpoch: scope.accessEpoch, apiBaseURL: "https://other.example.invalid/")
        ]
        for other in foreign {
            await expectFailure(.contextChanged) { try await outbox.put(pending, scope: other) }
            await expectFailure(.contextChanged) { _ = try await outbox.entries(scope: other) }
            await expectFailure(.contextChanged) { try await outbox.remove(mediaID: pending.mediaID, scope: other) }
            await expectFailure(.contextChanged) {
                try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: nil,
                                                 replacement: envelope(), scope: other)
            }
        }

        XCTAssertThrowsError(try makeOutbox(
            scope: MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 0,
                                  apiBaseURL: "https://example.invalid/"),
            root: root, keys: SyntheticKeyStore()))
        XCTAssertThrowsError(try makeOutbox(
            scope: MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: ""),
            root: root, keys: SyntheticKeyStore()))
        XCTAssertEqual(try await outbox.entries(scope: scope), [pending])
    }

    // MARK: - Clé absente, clé fausse, fichier corrompu

    func testMissingKeyWithExistingDataFailsClosedAndNeverCreatesReplacement() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let pending = try makePending(try sealMedia())
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        try await outbox.put(pending, scope: scope)

        let withoutKey = SyntheticKeyStore(bytes: nil)
        let blind = try makeOutbox(scope: scope, root: root, keys: withoutKey)
        await expectFailure(.protectionUnavailable) { _ = try await blind.entries(scope: scope) }
        await expectFailure(.protectionUnavailable) { try await blind.put(pending, scope: scope) }
        XCTAssertEqual(withoutKey.creationCount, 0, "Aucune clé n'est créée face à des données existantes")
        XCTAssertNil(withoutKey.storedBytes)
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 1)

        let wrongKey = SyntheticKeyStore(bytes: Data(repeating: 0xEE, count: 32))
        let foreign = try makeOutbox(scope: scope, root: root, keys: wrongKey)
        await expectFailure(.protectionUnavailable) { _ = try await foreign.entries(scope: scope) }
    }

    func testEmptyOutboxReturnsEmptyWithoutCreatingAKey() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore(bytes: nil)
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let entries = try await outbox.entries(scope: scope)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(keys.creationCount, 0, "Lire une file vide n'exige ni ne crée de clé")
    }

    func testCorruptedRecordFailsClosedWithoutBeingReplaced() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let pending = try makePending(try sealMedia())
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        try await outbox.put(pending, scope: scope)

        let folder = try scopeFolder(scope, root: root)
        let file = folder.appendingPathComponent(try recordDigest(pending.mediaID, scope: scope) + ".sealed")
        var damaged = try Data(contentsOf: file)
        damaged[damaged.count - 1] ^= 0x01
        try damaged.write(to: file)

        let reopened = try makeOutbox(scope: scope, root: root, keys: keys)
        await expectFailure(.protectionUnavailable) { _ = try await reopened.entries(scope: scope) }
        await expectFailure(.protectionUnavailable) { try await reopened.put(pending, scope: scope) }
        await expectFailure(.protectionUnavailable) {
            try await reopened.replaceEnvelope(mediaID: pending.mediaID, expected: nil,
                                                replacement: envelope(), scope: scope)
        }
        XCTAssertEqual(try Data(contentsOf: file), damaged, "Une archive illisible n'est jamais remplacée")
        XCTAssertEqual(keys.creationCount, 0)
    }

    // MARK: - Idempotence et conflits

    func testPutIsIdempotentAndConflictsStayClosed() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let sealed = try sealMedia()
        let pending = try makePending(sealed)

        try await outbox.put(pending, scope: scope)
        try await outbox.put(pending, scope: scope)
        let once = try await outbox.entries(scope: scope)
        XCTAssertEqual(once.count, 1, "Deux fois la même intention reste une seule archive")

        let sameIDOtherBytes = try makePending(try sealMedia(plaintext: Data("OTHER_BYTES".utf8), keyByte: 0x44),
                                               mediaIDOverride: pending.mediaID)
        await expectFailure(.stateConflict) { try await outbox.put(sameIDOtherBytes, scope: scope) }

        let sameIDOtherClient = try makePending(sealed, clientMessageID: UUID())
        await expectFailure(.stateConflict) { try await outbox.put(sameIDOtherClient, scope: scope) }

        let sameIDOtherConversation = try makePending(sealed, conversationID: UUID())
        await expectFailure(.stateConflict) { try await outbox.put(sameIDOtherConversation, scope: scope) }

        let sameIDOtherMentions = try makePending(sealed, mentions: [UUID()])
        await expectFailure(.stateConflict) { try await outbox.put(sameIDOtherMentions, scope: scope) }

        let sameIDOtherReply = try makePending(sealed, replyTo: UUID())
        await expectFailure(.stateConflict) { try await outbox.put(sameIDOtherReply, scope: scope) }

        let sameClientOtherMedia = try makePending(try sealMedia(plaintext: Data("OTHER_MEDIA".utf8), keyByte: 0x55),
                                                   clientMessageID: pending.clientMessageID)
        await expectFailure(.stateConflict) { try await outbox.put(sameClientOtherMedia, scope: scope) }

        XCTAssertEqual(try await outbox.entries(scope: scope), [pending], "Rien n'a été écrasé")
    }

    // MARK: - Comparaison d'enveloppe

    func testEnvelopeReplacementIsCompareAndSwapOnly() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let pending = try makePending(try sealMedia(), envelope: nil)
        try await outbox.put(pending, scope: scope)

        let first = envelope(payloadBytes: 32, epoch: 4)
        try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: nil, replacement: first, scope: scope)
        let replaced = try await outbox.entries(scope: scope)
        XCTAssertEqual(replaced.count, 1)
        XCTAssertEqual(replaced[0].messageCiphertext, first)
        XCTAssertEqual(replaced[0].clientMessageID, pending.clientMessageID)
        XCTAssertEqual(replaced[0].conversationID, pending.conversationID)
        XCTAssertEqual(replaced[0].sealed, pending.sealed)
        XCTAssertEqual(replaced[0].content, pending.content)
        XCTAssertEqual(replaced[0].mentionPersonIDs, pending.mentionPersonIDs)
        XCTAssertEqual(replaced[0].replyToMessageID, pending.replyToMessageID)
        XCTAssertEqual(replaced[0].createdAt, pending.createdAt, "Seule l'enveloppe change")

        let stale = envelope(payloadBytes: 48, epoch: 5)
        await expectFailure(.stateConflict) {
            try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: nil,
                                             replacement: stale, scope: scope)
        }
        XCTAssertEqual(try await outbox.entries(scope: scope)[0].messageCiphertext, first)

        try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: first,
                                         replacement: first, scope: scope)
        try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: first,
                                         replacement: stale, scope: scope)
        XCTAssertEqual(try await outbox.entries(scope: scope)[0].messageCiphertext, stale)

        await expectFailure(.stateConflict) {
            try await outbox.replaceEnvelope(mediaID: UUID(), expected: nil,
                                             replacement: first, scope: scope)
        }

        let invalid = envelope(payloadBytes: 0, epoch: 3)
        await expectFailure(.invalidResponse) {
            try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: stale,
                                             replacement: invalid, scope: scope)
        }
        XCTAssertEqual(try await outbox.entries(scope: scope)[0].messageCiphertext, stale)
    }

    func testMegolmEnvelopeIsBoundedAndRequiresAValidEpoch() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)

        let accepted = try makePending(try sealMedia(), envelope: envelope(payloadBytes: 9_000, epoch: 9))
        try await outbox.put(accepted, scope: scope)
        XCTAssertEqual(try await outbox.entries(scope: scope), [accepted])

        let tooLong = try makePending(try sealMedia(plaintext: Data("B".utf8), keyByte: 0x61),
                                      envelope: envelope(payloadBytes: 9_001, epoch: 9))
        await expectFailure(.invalidResponse) { try await outbox.put(tooLong, scope: scope) }

        let noEpoch = try makePending(try sealMedia(plaintext: Data("C".utf8), keyByte: 0x62),
                                      envelope: envelope(payloadBytes: 32, epoch: nil))
        await expectFailure(.invalidResponse) { try await outbox.put(noEpoch, scope: scope) }

        let zeroEpoch = try makePending(try sealMedia(plaintext: Data("D".utf8), keyByte: 0x63),
                                        envelope: envelope(payloadBytes: 32, epoch: 0))
        await expectFailure(.invalidResponse) { try await outbox.put(zeroEpoch, scope: scope) }
    }

    // MARK: - Mentions et plafond du contenu Matrix

    func testMentionsAreBoundedAndUnique() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)

        let eight = (0..<8).map { _ in UUID() }
        let accepted = try makePending(try sealMedia(), mentions: eight)
        try await outbox.put(accepted, scope: scope)
        XCTAssertEqual(try await outbox.entries(scope: scope), [accepted])

        let nine = (0..<9).map { _ in UUID() }
        await expectFailure(.invalidResponse) {
            try await outbox.put(try makePending(try sealMedia(plaintext: Data("E".utf8), keyByte: 0x64),
                                                 mentions: nine), scope: scope)
        }
        let duplicate = [UUID(), UUID()]
        await expectFailure(.invalidResponse) {
            try await outbox.put(try makePending(try sealMedia(plaintext: Data("F".utf8), keyByte: 0x65),
                                                 mentions: duplicate + [duplicate[0]]), scope: scope)
        }
    }

    func testMatrixContentCeilingIncludesMentions() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)

        // 1 000 grafèmes multi-scalaires : sous la borne de caractères du contenu,
        // mais très au-delà du plafond d'octets du contenu Matrix complet.
        let heavy = String(repeating: "👨‍👩‍👧‍👦", count: MessagingMediaContent.maximumTextLength)
        let pending = try makePending(try sealMedia(), text: heavy, mentions: (0..<8).map { _ in UUID() })
        await expectFailure(.invalidResponse) { try await outbox.put(pending, scope: scope) }
        XCTAssertTrue(try await outbox.entries(scope: scope).isEmpty)
    }

    // MARK: - Ordre déterministe

    func testEntriesAreOrderedByCreationThenIdentifier() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            try makePending(try sealMedia(plaintext: Data("1".utf8), keyByte: 0x71),
                            createdAt: base.addingTimeInterval(2)),
            try makePending(try sealMedia(plaintext: Data("2".utf8), keyByte: 0x72),
                            createdAt: base),
            try makePending(try sealMedia(plaintext: Data("3".utf8), keyByte: 0x73),
                            createdAt: base.addingTimeInterval(1))
        ]
        for item in items.reversed() { try await outbox.put(item, scope: scope) }
        let ordered = try await outbox.entries(scope: scope)
        XCTAssertEqual(ordered.map(\.mediaID), [items[1].mediaID, items[2].mediaID, items[0].mediaID])
        let reopened = try makeOutbox(scope: scope, root: root, keys: keys)
        XCTAssertEqual(try await reopened.entries(scope: scope).map(\.mediaID), ordered.map(\.mediaID))
    }

    // MARK: - Retrait

    func testRemoveIsIdempotentDurableAndSurfacesIOFailure() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let normal = try makeOutbox(scope: scope, root: root, keys: keys)
        try await normal.remove(mediaID: UUID(), scope: scope)

        let pending = try makePending(try sealMedia())
        try await normal.put(pending, scope: scope)
        try await normal.remove(mediaID: pending.mediaID, scope: scope)
        XCTAssertTrue(try await normal.entries(scope: scope).isEmpty)
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0)
        try await normal.remove(mediaID: pending.mediaID, scope: scope)

        try await normal.put(pending, scope: scope)
        let faulty = FaultyFileSystem(failures: [.remove])
        let broken = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: faulty)
        await expectFailure(.protectionUnavailable) {
            try await broken.remove(mediaID: pending.mediaID, scope: scope)
        }
        XCTAssertEqual(try await normal.entries(scope: scope), [pending],
                       "Un retrait non durable n'est jamais annoncé comme un succès")
    }

    // MARK: - Deux instances, aucun await sous verrou

    func testTwoInstancesConcurrentPutsLoseNothing() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let first = try makeOutbox(scope: scope, root: root, keys: keys)
        let second = try makeOutbox(scope: scope, root: root, keys: keys)
        var items: [MessagingPendingMedia] = []
        for index in 0..<8 {
            items.append(try makePending(try sealMedia(plaintext: Data("concurrent-\(index)".utf8),
                                                       keyByte: UInt8(0x80 + index))))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    try await (index.isMultiple(of: 2) ? first : second).put(item, scope: scope)
                }
            }
            try await group.waitForAll()
        }
        let persisted = try await first.entries(scope: scope)
        XCTAssertEqual(Set(persisted.map(\.mediaID)), Set(items.map(\.mediaID)))
        XCTAssertEqual(persisted.count, items.count)
        XCTAssertEqual(try await second.entries(scope: scope).count, items.count)
    }

    // MARK: - Bornes locales

    func testCapacityRefusesWithoutEvicting() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let strict = try makeOutbox(scope: scope, root: root, keys: keys,
                                    limits: MessagingMediaOutboxLimits(maximumIntents: 2))
        let first = try makePending(try sealMedia(plaintext: Data("A".utf8), keyByte: 0x41))
        let second = try makePending(try sealMedia(plaintext: Data("B".utf8), keyByte: 0x42))
        let third = try makePending(try sealMedia(plaintext: Data("C".utf8), keyByte: 0x43))
        try await strict.put(first, scope: scope)
        try await strict.put(second, scope: scope)
        await expectFailure(.protectionUnavailable) { try await strict.put(third, scope: scope) }
        let retained = try await strict.entries(scope: scope)
        XCTAssertEqual(Set(retained.map(\.mediaID)), [first.mediaID, second.mediaID],
                       "Aucune éviction automatique d'une intention existante")
    }

    func testScopeByteCapRefusesTheNextIntention() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let spacious = try makeOutbox(scope: scope, root: root, keys: keys)
        let first = try makePending(try sealMedia(plaintext: Data("FIRST".utf8), keyByte: 0x51))
        try await spacious.put(first, scope: scope)
        let files = try folderContents(scope: scope, root: root)
        let used = try files.reduce(0) { sum, url in
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            return sum + size
        }
        let tight = try makeOutbox(scope: scope, root: root, keys: keys,
                                   limits: MessagingMediaOutboxLimits(maximumScopeBytes: used + 8))
        let second = try makePending(try sealMedia(plaintext: Data("SECOND".utf8), keyByte: 0x52))
        await expectFailure(.protectionUnavailable) { try await tight.put(second, scope: scope) }
        XCTAssertEqual(try await tight.entries(scope: scope).map(\.mediaID), [first.mediaID])
    }

    // MARK: - Bornage avant lecture et confinement

    func testOversizeRecordIsRefusedBeforeAnyRead() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let faulty = FaultyFileSystem()
        let watched = try makeOutbox(scope: scope, root: root, keys: keys,
                                      fileSystem: faulty,
                                      limits: MessagingMediaOutboxLimits(maximumRecordBytes: 4_096))
        let folder = try scopeFolder(scope, root: root)
        let name = try recordDigest(UUID(), scope: scope) + ".sealed"
        try Data(repeating: 0x7F, count: 8_192).write(to: folder.appendingPathComponent(name))
        await expectFailure(.protectionUnavailable) { _ = try await watched.entries(scope: scope) }
        XCTAssertEqual(faulty.readCount, 0, "La taille est contrôlée avant toute lecture ou allocation")
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 1,
                       "Le fichier hors borne n'est ni supprimé ni remplacé en silence")
    }

    func testUnexpectedFilesAndSymlinksAreRefused() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let folder = try scopeFolder(scope, root: root)

        let stranger = folder.appendingPathComponent("not-a-record.bin")
        try Data([0x01]).write(to: stranger)
        await expectFailure(.protectionUnavailable) { _ = try await outbox.entries(scope: scope) }
        try FileManager.default.removeItem(at: stranger)

        let outside = root.appendingPathComponent("outside.sealed")
        try Data(repeating: 0x02, count: 32).write(to: outside)
        let link = folder.appendingPathComponent(try recordDigest(UUID(), scope: scope) + ".sealed")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await expectFailure(.protectionUnavailable) { _ = try await outbox.entries(scope: scope) }
        try FileManager.default.removeItem(at: link)
        XCTAssertTrue(try await outbox.entries(scope: scope).isEmpty)
    }

    func testFailedWriteLeavesNoTemporaryAndNoCleartextBytes() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let sealed = try sealMedia(plaintext: Data("SYNTHETIC_MEDIA_PLAINTEXT".utf8))
        let pending = try makePending(sealed)

        let noMove = FaultyFileSystem(failures: [.move])
        let refused = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: noMove)
        await expectFailure(.protectionUnavailable) { try await refused.put(pending, scope: scope) }
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0,
                       "Un échec ne laisse ni archive partielle ni temporaire clair")

        let noWrite = FaultyFileSystem(failures: [.write])
        let stopped = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: noWrite)
        await expectFailure(.protectionUnavailable) { try await stopped.put(pending, scope: scope) }
        let captured = try XCTUnwrap(noWrite.capturedWrites.first)
        XCTAssertNil(captured.range(of: Data("SYNTHETIC_MEDIA_PLAINTEXT".utf8)))
        XCTAssertNil(captured.range(of: Data(pending.content.media.name.utf8)))
        XCTAssertNil(captured.range(of: Data(pending.clientMessageID.uuidString.utf8)))
        XCTAssertFalse(String(decoding: captured.prefix(1), as: UTF8.self) == "{",
                       "Le temporaire ne contient jamais le JSON en clair")
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0)
    }

    func testFailedEnvelopeReplacementLeavesTheOriginalEnvelope() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let pending = try makePending(try sealMedia(), envelope: envelope(payloadBytes: 32, epoch: 2))
        let normal = try makeOutbox(scope: scope, root: root, keys: keys)
        try await normal.put(pending, scope: scope)

        let faulty = FaultyFileSystem(failures: [.replace])
        let broken = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: faulty)
        await expectFailure(.protectionUnavailable) {
            try await broken.replaceEnvelope(mediaID: pending.mediaID,
                                             expected: pending.messageCiphertext,
                                             replacement: envelope(payloadBytes: 48, epoch: 3),
                                             scope: scope)
        }
        XCTAssertEqual(try await normal.entries(scope: scope), [pending])
    }

    // MARK: - Déplacement entre scopes ou intentions

    func testFileCopiedBetweenScopesOrIntentionsIsRefused() async throws {
        let root = try makeRoot()
        let scopeA = makeScope()
        let scopeB = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 3,
                                    apiBaseURL: "https://other.example.invalid/")
        let keys = SyntheticKeyStore()
        let pending = try makePending(try sealMedia())
        let a = try makeOutbox(scope: scopeA, root: root, keys: keys)
        try await a.put(pending, scope: scopeA)

        let folderA = try scopeFolder(scopeA, root: root)
        let folderB = try scopeFolder(scopeB, root: root)
        let b = try makeOutbox(scope: scopeB, root: root, keys: keys)
        let source = folderA.appendingPathComponent(try recordDigest(pending.mediaID, scope: scopeA) + ".sealed")
        let copied = folderB.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copied)
        await expectFailure(.protectionUnavailable) { _ = try await b.entries(scope: scopeB) }

        try FileManager.default.removeItem(at: copied)
        let otherMedia = UUID()
        let renamed = folderA.appendingPathComponent(try recordDigest(otherMedia, scope: scopeA) + ".sealed")
        try FileManager.default.moveItem(at: source, to: renamed)
        await expectFailure(.protectionUnavailable) { _ = try await a.entries(scope: scopeA) }
    }

    // MARK: - Structures de test

    private func makeScope() -> MessagingScope {
        MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 5,
                       apiBaseURL: "https://example.invalid/")
    }

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drivy-media-outbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeOutbox(scope: MessagingScope, root: URL, keys: SyntheticKeyStore,
                            fileSystem: any MessagingMediaOutboxFileSystem = SystemMediaOutboxFileSystem(),
                            limits: MessagingMediaOutboxLimits = .standard) throws -> MessagingProtectedMediaOutbox {
        try MessagingProtectedMediaOutbox(scope: scope, root: root, keyStore: keys,
                                          fileSystem: fileSystem, limits: limits)
    }

    private func scopeFingerprint(_ scope: MessagingScope) throws -> String {
        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        return SHA256.hash(data: Data(descriptor.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func scopeFolder(_ scope: MessagingScope, root: URL) throws -> URL {
        root.appendingPathComponent("MessagingMediaOutbox", isDirectory: true)
            .appendingPathComponent(try scopeFingerprint(scope), isDirectory: true)
    }

    private func recordDigest(_ mediaID: UUID, scope: MessagingScope) throws -> String {
        let fingerprint = try scopeFingerprint(scope)
        let descriptor = "media-outbox-file-v1|\(fingerprint)|\(mediaID.uuidString.lowercased())"
        return SHA256.hash(data: Data(descriptor.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private func folderContents(_ scope: MessagingScope, root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: try scopeFolder(scope, root: root),
                                                    includingPropertiesForKeys: nil)
    }

    /// Sceau média synthétique : clé et IV réservés, aucun aléa, aucune clé réelle.
    private func sealMedia(plaintext: Data = Data("SYNTHETIC_MEDIA_PLAINTEXT".utf8),
                           keyByte: UInt8 = 0x33) throws -> MessagingSealedMedia {
        let cryptography = try AESCTRMediaCryptography(reservedKey: Data(repeating: keyByte, count: 32),
                                                       reservedIV: Data(repeating: 0, count: 16))
        return try cryptography.seal(plaintext)
    }

    private func makePending(_ sealed: MessagingSealedMedia,
                             clientMessageID: UUID = UUID(),
                             conversationID: UUID = UUID(),
                             mediaIDOverride: UUID? = nil,
                             sizeOverride: Int? = nil,
                             fileOverride: MessagingMediaEncryptionInfo? = nil,
                             text: String? = "Légende",
                             mentions: [UUID] = [],
                             replyTo: UUID? = nil,
                             createdAt: Date = Date(),
                             envelope: MessagingCiphertext? = nil) throws -> MessagingPendingMedia {
        let attachment = try MessagingMediaAttachment(
            id: mediaIDOverride ?? sealed.mediaID,
            size: sizeOverride ?? sealed.byteSize,
            mime: .jpeg,
            name: "IMG_0421.jpg",
            width: 64,
            height: 64,
            file: fileOverride ?? sealed.info)
        let content = try MessagingMediaContentV3(text: text, media: attachment)
        return MessagingPendingMedia(clientMessageID: clientMessageID, conversationID: conversationID,
                                     sealed: sealed, content: content,
                                     mentionPersonIDs: mentions, replyToMessageID: replyTo,
                                     createdAt: createdAt, messageCiphertext: envelope)
    }

    private func envelope(payloadBytes: Int = 64, epoch: Int? = 7) -> MessagingCiphertext {
        MessagingCiphertext(scheme: "megolm.v1", keyID: "synthetic-key",
                            payload: Data(repeating: 0x42, count: payloadBytes),
                            expectedMembersEpoch: epoch)
    }

    private func expectFailure(_ expected: MessagingFailure,
                               file: StaticString = #filePath, line: UInt = #line,
                               _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("Un échec fermé \(expected) était attendu", file: file, line: line)
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, expected, file: file, line: line)
        } catch {
            XCTFail("Erreur inattendue : \(error)", file: file, line: line)
        }
    }
}

/// Fournisseur de clés synthétique : jamais la Keychain système, jamais de clé réelle.
private final class SyntheticKeyStore: MessagingMediaOutboxKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    private var creations = 0

    init(bytes: Data? = Data(repeating: 0x11, count: 32)) {
        stored = bytes
    }

    var storedBytes: Data? { lock.withLock { stored } }
    var creationCount: Int { lock.withLock { creations } }

    func key(create: Bool) throws -> SymmetricKey {
        try lock.withLock {
            if let stored {
                guard stored.count == 32 else { throw MessagingFailure.protectionUnavailable }
                return SymmetricKey(data: stored)
            }
            guard create else { throw MessagingFailure.protectionUnavailable }
            creations += 1
            let generated = Data((0..<32).map { UInt8($0 &+ 1) })
            stored = generated
            return SymmetricKey(data: generated)
        }
    }
}

/// Adaptateur fautif : délègue au système de fichiers réel et permet d'injecter
/// une panne à chaque frontière, sans toucher aux fichiers d'un autre worker.
private final class FaultyFileSystem: MessagingMediaOutboxFileSystem, @unchecked Sendable {
    enum Operation: Hashable {
        case read, write, replace, move, remove, synchronizeFile, synchronizeDirectory, contents
    }

    private let base = SystemMediaOutboxFileSystem()
    private let lock = NSLock()
    private var failures: Set<Operation>
    private var readCounter = 0
    private var writes: [Data] = []

    init(failures: Set<Operation> = []) {
        self.failures = failures
    }

    var readCount: Int { lock.withLock { readCounter } }
    var capturedWrites: [Data] { lock.withLock { writes } }

    private func check(_ operation: Operation) throws {
        guard !lock.withLock({ failures.contains(operation) }) else {
            throw MessagingFailure.protectionUnavailable
        }
    }

    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func protect(_ url: URL) throws { try base.protect(url) }
    func isSymbolicLink(at url: URL) -> Bool { base.isSymbolicLink(at: url) }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func isRegularFile(at url: URL) -> Bool { base.isRegularFile(at: url) }
    func fileSize(at url: URL) throws -> Int { try base.fileSize(at: url) }

    func read(_ url: URL) throws -> Data {
        lock.withLock { readCounter += 1 }
        try check(.read)
        return try base.read(url)
    }

    func write(_ data: Data, to url: URL) throws {
        lock.withLock { writes.append(data) }
        try check(.write)
        try base.write(data, to: url)
    }

    func replaceItem(at target: URL, withItemAt source: URL) throws {
        try check(.replace)
        try base.replaceItem(at: target, withItemAt: source)
    }

    func moveItem(at source: URL, to target: URL) throws {
        try check(.move)
        try base.moveItem(at: source, to: target)
    }

    func remove(_ url: URL) throws {
        try check(.remove)
        try base.remove(url)
    }

    func synchronizeFile(_ url: URL) throws {
        try check(.synchronizeFile)
        try base.synchronizeFile(url)
    }

    func synchronizeDirectory(_ url: URL) throws {
        try check(.synchronizeDirectory)
        try base.synchronizeDirectory(url)
    }

    func contents(of directory: URL) throws -> [URL] {
        try check(.contents)
        return try base.contents(of: directory)
    }
}
