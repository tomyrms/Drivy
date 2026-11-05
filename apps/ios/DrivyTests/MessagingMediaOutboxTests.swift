import XCTest
import CryptoKit
import Security

@testable import Drivy

/// File d'intentions média durable et chiffrée (#97, T2b3).
///
/// Ces tests ont été écrits avant l'implémentation, mais ils n'ont pas été
/// exécutés sur le poste d'implémentation (Windows, aucun Xcode ni `swift`).
/// Aucun RED/GREEN natif n'est revendiqué : la preuve vient d'un runner Apple,
/// au SHA du commit. Aucune clé réelle ni Keychain système n'est utilisée ici :
/// chaque test injecte une racine temporaire et un fournisseur de clés
/// synthétique. Les erreurs d'entrée/sortie sont injectées par un adaptateur
/// fautif qui délègue au système de fichiers réel et journalise ses appels.
///
/// Les appels asynchrones ne sont jamais placés dans une autoclosure
/// `XCTAssert*` : les signatures XCTest n'offrent pas d'autoclosure
/// asynchrone. Le résultat est lié à une variable, puis la même valeur est
/// assertée.
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

    func testFirstKeyIsCreatedOnceThenReusedOnReopening() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore(bytes: nil)
        let pending = try makePending(try sealMedia())
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        try await outbox.put(pending, scope: scope)
        XCTAssertEqual(keys.creationCount, 1, "La première écriture crée la clé du scope")
        let created = try XCTUnwrap(keys.storedBytes)

        let reopened = try makeOutbox(scope: scope, root: root, keys: keys)
        let entries = try await reopened.entries(scope: scope)
        XCTAssertEqual(entries, [pending])
        try await reopened.put(pending, scope: scope)
        XCTAssertEqual(keys.creationCount, 1, "Aucune nouvelle clé face à des archives existantes")
        XCTAssertEqual(keys.storedBytes, created)
    }

    func testInitialOwnedDirectoriesAreCreatedBeforeProtection() throws {
        let root = try makeRoot()
        let scope = makeScope()
        let fileSystem = FaultyFileSystem()
        _ = try makeOutbox(scope: scope, root: root, keys: SyntheticKeyStore(), fileSystem: fileSystem)

        let owned = fileSystem.calls.filter {
            $0.operation == .createDirectory || $0.operation == .protect
        }
        XCTAssertEqual(owned.map(\.operation),
                       [.createDirectory, .createDirectory, .protect, .protect],
                       "Créer puis protéger, jamais protéger une cible non contrôlée")
        XCTAssertEqual(owned[0].name, "MessagingMediaOutbox")
        XCTAssertEqual(owned[1].name, try scopeFingerprint(scope))
        XCTAssertEqual(owned[2].name, "MessagingMediaOutbox")
        XCTAssertEqual(owned[3].name, try scopeFingerprint(scope))
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
        let entries = try await outbox.entries(scope: scope)
        XCTAssertTrue(entries.isEmpty)
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
        let entries = try await reopened.entries(scope: scope)
        XCTAssertEqual(entries, [pending])
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

        let entries = try await outbox.entries(scope: scope)
        XCTAssertTrue(entries.isEmpty)
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
        let entries = try await outbox.entries(scope: scope)
        XCTAssertEqual(entries, [pending])
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

        let retained = try await outbox.entries(scope: scope)
        XCTAssertEqual(retained, [pending], "Rien n'a été écrasé")
    }

    func testIdempotentPutAtFullQuota() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys,
                                    limits: MessagingMediaOutboxLimits(maximumIntents: 1))
        let pending = try makePending(try sealMedia())
        try await outbox.put(pending, scope: scope)
        try await outbox.put(pending, scope: scope)
        let entries = try await outbox.entries(scope: scope)
        XCTAssertEqual(entries, [pending], "L'idempotence passe avant le plafond")
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
        let afterStale = try await outbox.entries(scope: scope)
        XCTAssertEqual(afterStale[0].messageCiphertext, first)

        try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: first,
                                         replacement: first, scope: scope)
        try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: first,
                                         replacement: stale, scope: scope)
        let afterSwap = try await outbox.entries(scope: scope)
        XCTAssertEqual(afterSwap[0].messageCiphertext, stale)

        await expectFailure(.stateConflict) {
            try await outbox.replaceEnvelope(mediaID: UUID(), expected: nil,
                                             replacement: first, scope: scope)
        }

        let invalid = envelope(payloadBytes: 0, epoch: 3)
        await expectFailure(.invalidResponse) {
            try await outbox.replaceEnvelope(mediaID: pending.mediaID, expected: stale,
                                             replacement: invalid, scope: scope)
        }
        let afterInvalid = try await outbox.entries(scope: scope)
        XCTAssertEqual(afterInvalid[0].messageCiphertext, stale)
    }

    func testEnvelopeNoOpResynchronizesBeforeSuccess() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let fileSystem = FaultyFileSystem()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: fileSystem)
        let pending = try makePending(try sealMedia(), envelope: envelope(payloadBytes: 32, epoch: 2))
        try await outbox.put(pending, scope: scope)
        let file = try scopeFolder(scope, root: root)
            .appendingPathComponent(try recordDigest(pending.mediaID, scope: scope) + ".sealed")
        let before = try Data(contentsOf: file)

        fileSystem.fail(.synchronizeDirectory)
        fileSystem.clearCalls()
        await expectFailure(.protectionUnavailable) {
            try await outbox.replaceEnvelope(mediaID: pending.mediaID,
                                             expected: pending.messageCiphertext,
                                             replacement: pending.messageCiphertext,
                                             scope: scope)
        }
        XCTAssertTrue(fileSystem.operations.contains(.protect))
        XCTAssertTrue(fileSystem.operations.contains(.synchronizeFile))
        XCTAssertTrue(fileSystem.operations.contains(.synchronizeDirectory))

        fileSystem.heal(.synchronizeDirectory)
        try await outbox.replaceEnvelope(mediaID: pending.mediaID,
                                         expected: pending.messageCiphertext,
                                         replacement: pending.messageCiphertext,
                                         scope: scope)
        XCTAssertEqual(try Data(contentsOf: file), before, "Un no-op ne réécrit jamais l'archive")
        let entries = try await outbox.entries(scope: scope)
        XCTAssertEqual(entries, [pending])
    }

    func testMegolmEnvelopeIsBoundedAndRequiresAValidEpoch() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)

        let accepted = try makePending(try sealMedia(), envelope: envelope(payloadBytes: 9_000, epoch: 9))
        try await outbox.put(accepted, scope: scope)
        let entries = try await outbox.entries(scope: scope)
        XCTAssertEqual(entries, [accepted])

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
        let entries = try await outbox.entries(scope: scope)
        XCTAssertEqual(entries, [accepted])

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

    func testMatrixContentCeilingUsesCanonicalUserIDs() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)

        let mentions = (0..<8).map { _ in UUID() }
        let canonical = mentions.map { MatrixMessagingCryptography.userID($0) }
        XCTAssertTrue(canonical.allSatisfy { $0.hasPrefix("@") && $0.hasSuffix(":drivy") },
                      "La mesure doit utiliser la forme réellement émise, pas l'UUID nu")

        let caption = "Légende"
        let sealed = try sealMedia(plaintext: Data("BOUNDARY".utf8), keyByte: 0x71)
        let boundary = try boundaryName(sealed: sealed, text: caption, mentions: canonical)
        XCTAssertEqual(boundary.measurement, MessagingPlainContent.maximumV3ByteCount,
                       "Le nom est mesuré avec 8 mentions canoniques, à la borne exacte")
        XCTAssertLessThan(boundary.name.count, MessagingMediaAttachment.maximumNameLength,
                          "Le nom garde la place du 'a' ASCII du cas +1, sans troncature par l'assainissement")

        let atLimit = try makePending(sealed, name: boundary.name, text: caption, mentions: mentions)
        let measured = try MessagingMediaContent.messageContent(atLimit.content, mentions: canonical).count
        XCTAssertEqual(measured, MessagingPlainContent.maximumV3ByteCount)
        try await outbox.put(atLimit, scope: scope)

        // Même sceau, mêmes mentions, même légende : seul le nom gagne un `a` ASCII.
        // La taille est validée avant le conflit d'identité, donc ce contenu trop long
        // est refusé sans créer un nouveau média.
        let over = try makePending(sealed, name: boundary.name + "a", text: caption, mentions: mentions)
        let overMeasured = try MessagingMediaContent.messageContent(over.content, mentions: canonical).count
        XCTAssertEqual(overMeasured, MessagingPlainContent.maximumV3ByteCount + 1,
                       "Un octet ASCII de plus sur le nom produit exactement un octet de contenu de plus")
        await expectFailure(.invalidResponse) { try await outbox.put(over, scope: scope) }
    }

    // MARK: - Ordre déterministe

    func testEntriesAreOrderedByCreationThenIdentifier() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let outbox = try makeOutbox(scope: scope, root: root, keys: keys)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            try makePending(try sealMedia(plaintext: Data("1".utf8), keyByte: 0x73),
                            createdAt: base.addingTimeInterval(2)),
            try makePending(try sealMedia(plaintext: Data("2".utf8), keyByte: 0x74),
                            createdAt: base),
            try makePending(try sealMedia(plaintext: Data("3".utf8), keyByte: 0x75),
                            createdAt: base.addingTimeInterval(1))
        ]
        for item in items.reversed() { try await outbox.put(item, scope: scope) }
        let ordered = try await outbox.entries(scope: scope)
        XCTAssertEqual(ordered.map(\.mediaID), [items[1].mediaID, items[2].mediaID, items[0].mediaID])
        let reopened = try makeOutbox(scope: scope, root: root, keys: keys)
        let reopenedOrder = try await reopened.entries(scope: scope).map(\.mediaID)
        XCTAssertEqual(reopenedOrder, ordered.map(\.mediaID))
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
        let empty = try await normal.entries(scope: scope)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0)
        try await normal.remove(mediaID: pending.mediaID, scope: scope)

        try await normal.put(pending, scope: scope)
        let faulty = FaultyFileSystem(failures: [.remove])
        let broken = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: faulty)
        await expectFailure(.protectionUnavailable) {
            try await broken.remove(mediaID: pending.mediaID, scope: scope)
        }
        let retained = try await normal.entries(scope: scope)
        XCTAssertEqual(retained, [pending],
                       "Un retrait non durable n'est jamais annoncé comme un succès")
    }

    func testRemoveAbsentAfterFailedDirectorySyncIsNotASuccess() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let normal = try makeOutbox(scope: scope, root: root, keys: keys)
        let pending = try makePending(try sealMedia())
        try await normal.put(pending, scope: scope)

        let faulty = FaultyFileSystem(failures: [.synchronizeDirectory])
        let store = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: faulty)
        await expectFailure(.protectionUnavailable) {
            try await store.remove(mediaID: pending.mediaID, scope: scope)
        }
        XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0,
                       "L'unlink a eu lieu, mais la synchro du dossier a échoué")
        // L'archive est absente : un retrait ne peut pas être un faux succès durable.
        await expectFailure(.protectionUnavailable) {
            try await store.remove(mediaID: pending.mediaID, scope: scope)
        }

        faulty.heal(.synchronizeDirectory)
        try await store.remove(mediaID: pending.mediaID, scope: scope)
        XCTAssertGreaterThanOrEqual(faulty.operations.filter { $0 == .synchronizeDirectory }.count, 3)
        let entries = try await normal.entries(scope: scope)
        XCTAssertTrue(entries.isEmpty)
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
        let fromSecond = try await second.entries(scope: scope)
        XCTAssertEqual(fromSecond.count, items.count)
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
        let entries = try await tight.entries(scope: scope)
        XCTAssertEqual(entries.map(\.mediaID), [first.mediaID])
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
        let entries = try await outbox.entries(scope: scope)
        XCTAssertTrue(entries.isEmpty)
    }

    func testSymlinkedOwnedRootIsRefusedWithoutExternalEffect() throws {
        let root = try makeRoot()
        let external = try makeExternalRoot()
        let sentinel = external.appendingPathComponent("sentinel.bin")
        let sentinelBytes = Data("EXTERNAL_SENTINEL".utf8)
        try sentinelBytes.write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("MessagingMediaOutbox", isDirectory: true),
            withDestinationURL: external)

        let fileSystem = FaultyFileSystem()
        do {
            _ = try makeOutbox(scope: makeScope(), root: root, keys: SyntheticKeyStore(),
                               fileSystem: fileSystem)
            XCTFail("Un composant possédé lié doit être refusé")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .protectionUnavailable, "Retour fermé, sans NSError ni chemin")
        } catch {
            XCTFail("Erreur non fermée à l'initialisation")
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: external,
                                                                  includingPropertiesForKeys: nil).count, 1)
        XCTAssertFalse(fileSystem.operations.contains(.createDirectory))
        XCTAssertFalse(fileSystem.operations.contains(.protect))
    }

    func testSymlinkedRootIsRefusedWithoutExternalEffect() throws {
        let container = try makeRoot()
        let external = try makeExternalRoot()
        let sentinel = external.appendingPathComponent("sentinel.bin")
        let sentinelBytes = Data("EXTERNAL_SENTINEL".utf8)
        try sentinelBytes.write(to: sentinel)
        let linkedRoot = container.appendingPathComponent("linked-root", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: external)

        let fileSystem = FaultyFileSystem()
        do {
            _ = try makeOutbox(scope: makeScope(), root: linkedRoot, keys: SyntheticKeyStore(),
                               fileSystem: fileSystem)
            XCTFail("Une racine liée doit être refusée")
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, .protectionUnavailable)
        } catch {
            XCTFail("Erreur non fermée à l'initialisation")
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: external,
                                                                  includingPropertiesForKeys: nil).count, 1)
        XCTAssertFalse(fileSystem.operations.contains(.createDirectory))
        XCTAssertFalse(fileSystem.operations.contains(.protect))
    }

    func testReplacedFolderIsRefusedBeforeRemovalAndWrite() async throws {
        let root = try makeRoot()
        let external = try makeExternalRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let store = try makeOutbox(scope: scope, root: root, keys: keys)
        let pending = try makePending(try sealMedia())
        try await store.put(pending, scope: scope)

        let folder = try scopeFolder(scope, root: root)
        let digestName = try recordDigest(pending.mediaID, scope: scope) + ".sealed"
        let sentinel = Data("OUTSIDE_RECORD".utf8)
        try sentinel.write(to: external.appendingPathComponent(digestName))
        let backup = root.appendingPathComponent("folder-backup", isDirectory: true)
        try FileManager.default.moveItem(at: folder, to: backup)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: external)

        await expectFailure(.protectionUnavailable) {
            try await store.remove(mediaID: pending.mediaID, scope: scope)
        }
        XCTAssertEqual(try Data(contentsOf: external.appendingPathComponent(digestName)), sentinel,
                       "Aucune suppression hors racine")

        let replacement = try makePending(try sealMedia(plaintext: Data("REPLACED".utf8), keyByte: 0x35))
        await expectFailure(.protectionUnavailable) {
            try await store.put(replacement, scope: scope)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: external,
                                                                  includingPropertiesForKeys: nil).count, 1,
                       "Aucun temporaire ni archive créés hors racine")
        await expectFailure(.protectionUnavailable) { _ = try await store.entries(scope: scope) }
    }

    func testReplacedAncestorIsRefusedBeforeWrite() async throws {
        let root = try makeRoot()
        let external = try makeExternalRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let store = try makeOutbox(scope: scope, root: root, keys: keys)
        let ownedRoot = root.appendingPathComponent("MessagingMediaOutbox", isDirectory: true)
        let backup = root.appendingPathComponent("owned-backup", isDirectory: true)
        try FileManager.default.moveItem(at: ownedRoot, to: backup)
        try FileManager.default.createSymbolicLink(at: ownedRoot, withDestinationURL: external)

        let pending = try makePending(try sealMedia())
        await expectFailure(.protectionUnavailable) { try await store.put(pending, scope: scope) }
        await expectFailure(.protectionUnavailable) { _ = try await store.entries(scope: scope) }
        await expectFailure(.protectionUnavailable) {
            try await store.remove(mediaID: pending.mediaID, scope: scope)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: external,
                                                                  includingPropertiesForKeys: nil).count, 0)
    }

    func testProtectAndFileSyncFailuresRefuseWithoutPartialRecord() async throws {
        for failure in [FaultyFileSystem.Operation.protect, .synchronizeFile] {
            let root = try makeRoot()
            let scope = makeScope()
            let keys = SyntheticKeyStore(bytes: nil)
            let fileSystem = FaultyFileSystem()
            let store = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: fileSystem)
            let pending = try makePending(try sealMedia())

            fileSystem.fail(failure)
            await expectFailure(.protectionUnavailable) { try await store.put(pending, scope: scope) }
            XCTAssertEqual(try folderContents(scope: scope, root: root).count, 0,
                           "Aucun temporaire ni archive partielle après \(failure.rawValue)")

            fileSystem.heal(failure)
            let recovered = try makeOutbox(scope: scope, root: root, keys: keys)
            try await recovered.put(pending, scope: scope)
            let entries = try await recovered.entries(scope: scope)
            XCTAssertEqual(entries, [pending])
        }
    }

    func testDirectorySyncFailureAfterRenameIsResynchronizedOnRetry() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let fileSystem = FaultyFileSystem(failures: [.synchronizeDirectory])
        let store = try makeOutbox(scope: scope, root: root, keys: keys, fileSystem: fileSystem)
        let pending = try makePending(try sealMedia())

        await expectFailure(.protectionUnavailable) { try await store.put(pending, scope: scope) }
        let files = try folderContents(scope: scope, root: root)
        XCTAssertEqual(files.count, 1, "Le renommage a eu lieu, la synchro du dossier a échoué")
        let file = try XCTUnwrap(files.first)
        let before = try Data(contentsOf: file)

        // Même appel : l'idempotence ne doit pas masquer l'absence de synchro.
        fileSystem.clearCalls()
        await expectFailure(.protectionUnavailable) { try await store.put(pending, scope: scope) }
        XCTAssertTrue(fileSystem.operations.contains(.protect))
        XCTAssertTrue(fileSystem.operations.contains(.synchronizeFile))
        XCTAssertTrue(fileSystem.operations.contains(.synchronizeDirectory))

        fileSystem.heal(.synchronizeDirectory)
        fileSystem.clearCalls()
        try await store.put(pending, scope: scope)
        XCTAssertTrue(fileSystem.operations.contains(.synchronizeDirectory))
        XCTAssertEqual(try Data(contentsOf: file), before, "La reprise ne réécrit pas l'intention")
        let entries = try await store.entries(scope: scope)
        XCTAssertEqual(entries, [pending])
    }

    func testResidualTemporaryIsCountedAndBounded() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let store = try makeOutbox(scope: scope, root: root, keys: keys)
        let first = try makePending(try sealMedia(plaintext: Data("FIRST".utf8), keyByte: 0x61))
        try await store.put(first, scope: scope)

        let folder = try scopeFolder(scope, root: root)
        let record = try XCTUnwrap(try folderContents(scope: scope, root: root).first {
            $0.lastPathComponent.hasSuffix(".sealed")
        })
        let attributes = try FileManager.default.attributesOfItem(atPath: record.path)
        let recordSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let temporary = folder.appendingPathComponent("media-outbox-tmp-\(UUID().uuidString.lowercased()).tmp")
        try Data(repeating: 0x6E, count: 512).write(to: temporary)

        let entries = try await store.entries(scope: scope)
        XCTAssertEqual(entries, [first], "Un temporaire résiduel est ignoré à la lecture")

        let tight = try makeOutbox(scope: scope, root: root, keys: keys,
                                   limits: MessagingMediaOutboxLimits(maximumScopeBytes: recordSize + 512 + 1))
        let second = try makePending(try sealMedia(plaintext: Data("SECOND".utf8), keyByte: 0x62))
        await expectFailure(.protectionUnavailable) { try await tight.put(second, scope: scope) }

        for _ in 0..<8 {
            let extra = folder.appendingPathComponent("media-outbox-tmp-\(UUID().uuidString.lowercased()).tmp")
            try Data(repeating: 0x6F, count: 128).write(to: extra)
        }
        let bounded = try makeOutbox(scope: scope, root: root, keys: keys)
        let third = try makePending(try sealMedia(plaintext: Data("THIRD".utf8), keyByte: 0x63))
        await expectFailure(.protectionUnavailable) { try await bounded.put(third, scope: scope) }
        let temporaries = try folderContents(scope: scope, root: root).filter {
            $0.lastPathComponent.hasPrefix("media-outbox-tmp-")
        }
        XCTAssertEqual(temporaries.count, 9, "Aucun temporaire n'est effacé silencieusement")
    }

    func testOversizedTemporaryIsRefusedWithoutDeletion() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let store = try makeOutbox(scope: scope, root: root, keys: keys,
                                   limits: MessagingMediaOutboxLimits(maximumRecordBytes: 4_096))
        let folder = try scopeFolder(scope, root: root)
        let temporary = folder.appendingPathComponent("media-outbox-tmp-\(UUID().uuidString.lowercased()).tmp")
        try Data(repeating: 0x01, count: 8_192).write(to: temporary)

        await expectFailure(.protectionUnavailable) { _ = try await store.entries(scope: scope) }
        let bytes = try Data(contentsOf: temporary)
        XCTAssertEqual(bytes.count, 8_192, "Le temporaire hors borne n'est jamais supprimé")
    }

    func testEntriesBeyondMaximumIntentsIsRefused() async throws {
        let root = try makeRoot()
        let scope = makeScope()
        let keys = SyntheticKeyStore()
        let generous = try makeOutbox(scope: scope, root: root, keys: keys)
        for index in 0..<3 {
            try await generous.put(try makePending(try sealMedia(plaintext: Data("N\(index)".utf8),
                                                                 keyByte: UInt8(0x90 + index))),
                                   scope: scope)
        }
        let strictFileSystem = FaultyFileSystem()
        let strict = try makeOutbox(scope: scope, root: root, keys: keys,
                                    fileSystem: strictFileSystem,
                                    limits: MessagingMediaOutboxLimits(maximumIntents: 2))
        await expectFailure(.protectionUnavailable) { _ = try await strict.entries(scope: scope) }
        XCTAssertEqual(strictFileSystem.readCount, 0,
                       "Le dépassement est refusé avant de charger une archive")
        let fourth = try makePending(try sealMedia(plaintext: Data("FOURTH".utf8), keyByte: 0x68))
        await expectFailure(.protectionUnavailable) { try await strict.put(fourth, scope: scope) }
        XCTAssertEqual(strictFileSystem.readCount, 0,
                       "L'admission au plafond est refusée sans charger les archives existantes")
    }

    // MARK: - Fichiers d'écriture et d'enveloppe

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
        let entries = try await normal.entries(scope: scope)
        XCTAssertEqual(entries, [pending])
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

    // MARK: - Attributs de clé (sans Keychain)

    func testKeychainKeyAttributesAreVerified() {
        let expected = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        func attributes(accessible: String, synchronizable: Bool?, bytes: Data) -> [String: Any] {
            var value: [String: Any] = [
                kSecAttrAccessible as String: accessible,
                kSecValueData as String: bytes
            ]
            if let synchronizable { value[kSecAttrSynchronizable as String] = synchronizable }
            return value
        }
        let keyBytes = Data(repeating: 0x22, count: 32)

        XCTAssertNotNil(KeychainMediaOutboxKeyStore.validatedKey(
            from: attributes(accessible: expected, synchronizable: nil, bytes: keyBytes)))
        XCTAssertNotNil(KeychainMediaOutboxKeyStore.validatedKey(
            from: attributes(accessible: expected, synchronizable: false, bytes: keyBytes)))
        XCTAssertNil(KeychainMediaOutboxKeyStore.validatedKey(
            from: attributes(accessible: kSecAttrAccessibleAfterFirstUnlock as String,
                             synchronizable: false, bytes: keyBytes)),
            "Une autre classe d'accessibilité est refusée")
        XCTAssertNil(KeychainMediaOutboxKeyStore.validatedKey(
            from: attributes(accessible: expected, synchronizable: true, bytes: keyBytes)),
            "Une clé synchronisée est refusée")
        XCTAssertNil(KeychainMediaOutboxKeyStore.validatedKey(
            from: attributes(accessible: expected, synchronizable: false,
                             bytes: Data(repeating: 0x22, count: 31))),
            "Une longueur incorrecte est refusée")
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

    private func makeExternalRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drivy-media-external-\(UUID().uuidString)", isDirectory: true)
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
                             name: String = "IMG_0421.jpg",
                             text: String? = "Légende",
                             mentions: [UUID] = [],
                             replyTo: UUID? = nil,
                             createdAt: Date = Date(),
                             envelope: MessagingCiphertext? = nil) throws -> MessagingPendingMedia {
        let attachment = try MessagingMediaAttachment(
            id: mediaIDOverride ?? sealed.mediaID,
            size: sizeOverride ?? sealed.byteSize,
            mime: .jpeg,
            name: name,
            width: 64,
            height: 64,
            file: fileOverride ?? sealed.info)
        let content = try MessagingMediaContentV3(text: text, media: attachment)
        return MessagingPendingMedia(clientMessageID: clientMessageID, conversationID: conversationID,
                                     sealed: sealed, content: content,
                                     mentionPersonIDs: mentions, replyToMessageID: replyTo,
                                     createdAt: createdAt, messageCiphertext: envelope)
    }

    /// Nom dont la mesure canonique atteint exactement la borne de 6 000 octets,
    /// avec les 8 mentions réelles et **le contenu exact** de l'intention mesurée
    /// (même sceau, même légende explicite). Les grafèmes apportent le volume,
    /// puis des `a` ASCII ajustent au byte près : l'ajout d'un seul `a` produit
    /// donc exactement un octet de contenu supplémentaire.
    private func boundaryName(sealed: MessagingSealedMedia, text: String?,
                              mentions: [String]) throws -> (name: String, measurement: Int) {
        func measurement(_ name: String) throws -> Int {
            let attachment = try MessagingMediaAttachment(id: sealed.mediaID, size: sealed.byteSize,
                                                          mime: .jpeg, name: name, width: 64, height: 64,
                                                          file: sealed.info)
            let content = try MessagingMediaContentV3(text: text, media: attachment)
            return try MessagingMediaContent.messageContent(content, mentions: mentions).count
        }
        let family = "👨‍👩‍👧‍👦"
        var name = "a"
        while name.count < MessagingMediaAttachment.maximumNameLength {
            let candidate = name + family
            guard candidate.count <= MessagingMediaAttachment.maximumNameLength,
                  try measurement(candidate) <= MessagingPlainContent.maximumV3ByteCount else { break }
            name = candidate
        }
        while name.count < MessagingMediaAttachment.maximumNameLength {
            let candidate = name + "a"
            guard try measurement(candidate) <= MessagingPlainContent.maximumV3ByteCount else { break }
            name = candidate
        }
        return (name, try measurement(name))
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

/// Adaptateur fautif : délègue au système de fichiers réel, journalise l'ordre
/// réel des appels et permet d'injecter une panne par frontière.
private final class FaultyFileSystem: MessagingMediaOutboxFileSystem, @unchecked Sendable {
    enum Operation: String, Hashable {
        case createDirectory, protect, isSymbolicLink, fileExists, isDirectory, isRegularFile,
             fileSize, read, write, replace, move, remove, synchronizeFile, synchronizeDirectory, contents
    }

    struct Call: Equatable {
        let operation: Operation
        let name: String
    }

    private let base = SystemMediaOutboxFileSystem()
    private let lock = NSLock()
    private var failures: Set<Operation>
    private var log: [Call] = []
    private var readCounter = 0
    private var writes: [Data] = []

    init(failures: Set<Operation> = []) {
        self.failures = failures
    }

    var operations: [Operation] { lock.withLock { log.map(\.operation) } }
    var calls: [Call] { lock.withLock { log } }
    var readCount: Int { lock.withLock { readCounter } }
    var capturedWrites: [Data] { lock.withLock { writes } }

    func fail(_ operation: Operation) { lock.withLock { _ = failures.insert(operation) } }
    func heal(_ operation: Operation) { lock.withLock { _ = failures.remove(operation) } }
    func clearCalls() { lock.withLock { log.removeAll() } }

    private func record(_ operation: Operation, _ url: URL) {
        lock.withLock { log.append(Call(operation: operation, name: url.lastPathComponent)) }
    }

    private func check(_ operation: Operation, _ url: URL) throws {
        record(operation, url)
        guard !lock.withLock({ failures.contains(operation) }) else {
            throw MessagingFailure.protectionUnavailable
        }
    }

    func createDirectory(at url: URL) throws {
        try check(.createDirectory, url)
        try base.createDirectory(at: url)
    }

    func protect(_ url: URL) throws {
        try check(.protect, url)
        try base.protect(url)
    }

    func isSymbolicLink(at url: URL) -> Bool {
        record(.isSymbolicLink, url)
        return base.isSymbolicLink(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        record(.fileExists, url)
        return base.fileExists(at: url)
    }

    func isDirectory(at url: URL) -> Bool {
        record(.isDirectory, url)
        return base.isDirectory(at: url)
    }

    func isRegularFile(at url: URL) -> Bool {
        record(.isRegularFile, url)
        return base.isRegularFile(at: url)
    }

    func fileSize(at url: URL) throws -> Int {
        try check(.fileSize, url)
        return try base.fileSize(at: url)
    }

    func read(_ url: URL) throws -> Data {
        lock.withLock { readCounter += 1 }
        try check(.read, url)
        return try base.read(url)
    }

    func write(_ data: Data, to url: URL) throws {
        lock.withLock { writes.append(data) }
        try check(.write, url)
        try base.write(data, to: url)
    }

    func replaceItem(at target: URL, withItemAt source: URL) throws {
        try check(.replace, target)
        try base.replaceItem(at: target, withItemAt: source)
    }

    func moveItem(at source: URL, to target: URL) throws {
        try check(.move, source)
        try base.moveItem(at: source, to: target)
    }

    func remove(_ url: URL) throws {
        try check(.remove, url)
        try base.remove(url)
    }

    func synchronizeFile(_ url: URL) throws {
        try check(.synchronizeFile, url)
        try base.synchronizeFile(url)
    }

    func synchronizeDirectory(_ url: URL) throws {
        try check(.synchronizeDirectory, url)
        try base.synchronizeDirectory(url)
    }

    func contents(of directory: URL, limit: Int) throws -> [URL] {
        try check(.contents, directory)
        return try base.contents(of: directory, limit: limit)
    }
}
