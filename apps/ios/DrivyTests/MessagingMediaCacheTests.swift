import XCTest
import CryptoKit
import Security
import UIKit
@testable import Drivy

/// Cache local des médias (#97, contrat §3.10/§4.5).
///
/// Toutes les images de ce fichier sont **synthétiques** (aplat uni ou bruit déterministe) :
/// aucune photo, aucun nom, aucune donnée de personne. La clé est une fixture en mémoire pour
/// la majorité des cas ; deux tests traversent Security dans un **espace Keychain temporaire**
/// qui leur est propre, jamais le service de production.
///
/// Le nom opaque d'un fichier est recalculé par les tests (`opaqueName`) uniquement pour injecter
/// des pannes réelles : fichier remplacé, supprimé, lié symboliquement, énorme, orphelin.
///
/// Aucune assertion n'utilise `await` dans une autoclosure XCTest (interdit en Swift 6) : les
/// lectures passent par `expectData`/`expectMissing` et leurs équivalents miniature.
final class MessagingMediaCacheTests: XCTestCase {
    private let sentinel = Data("SYNTHETIC_MEDIA_CACHE_SENTINEL".utf8)

    // MARK: - Aller-retour, chiffrement réel, absence de sentinelle

    func testStoreAndReopenReturnExactBytes() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 7, count: 4_096)
        let thumb = try fixture.png(width: 64, height: 64)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        try await fixture.cache.storeThumbnail(thumb, mediaID: fixture.mediaID, scope: fixture.scope)

        let reopened = try fixture.makeCache()
        await expectData(reopened, fixture.mediaID, fixture.scope, equals: payload)
        await expectThumbnail(reopened, fixture.mediaID, fixture.scope, equals: thumb)
    }

    func testSealedFilesAndIndexRevealNoPlaintextOrIdentifier() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 3, count: 2_048)
        let thumb = try fixture.png(width: 32, height: 32)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        try await fixture.cache.storeThumbnail(thumb, mediaID: fixture.mediaID, scope: fixture.scope)

        let files = try fixture.allFiles()
        XCTAssertFalse(files.isEmpty)
        let forbidden = [sentinel, Data(fixture.mediaID.uuidString.utf8),
                         Data(fixture.mediaID.uuidString.lowercased().utf8),
                         Data("original".utf8), Data("thumbnail".utf8),
                         Data("image/jpeg".utf8), Data("image/png".utf8),
                         Data("SYNTHETIC".utf8)]
        for file in files {
            XCTAssertEqual(file.pathExtension, "sealed", "Seul un artefact scellé est admis : \(file.lastPathComponent)")
            let name = file.deletingPathExtension().lastPathComponent
            XCTAssertEqual(name.count, 64, "Nom opaque attendu (empreinte), pas un identifiant")
            XCTAssertTrue(name.allSatisfy { $0.isHexDigit })
            let bytes = try Data(contentsOf: file)
            for marker in forbidden {
                XCTAssertNil(bytes.range(of: marker), "Aucune sentinelle ni identifiant en clair dans \(file.lastPathComponent)")
            }
        }
    }

    // MARK: - Bornes et format

    func testOriginalBoundsRejectEmptyAndOversizedBeforeWrite() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.store(Data(), mediaID: fixture.mediaID, scope: fixture.scope)
        }
        let emptyPath = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original).path
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyPath))

        try await fixture.cache.store(Data([1]), mediaID: fixture.mediaID, scope: fixture.scope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: Data([1]))

        let maximum = MessagingProtectedMediaCache.maximumOriginalByteSize
        XCTAssertEqual(maximum, 4_194_304)
        XCTAssertEqual(maximum, MessagingMediaAttachment.maximumByteSize)
        let tooLarge = Data(repeating: 5, count: maximum + 1)
        let other = UUID()
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.store(tooLarge, mediaID: other, scope: fixture.scope)
        }
        await expectMissing(fixture.cache, other, fixture.scope)
    }

    func testOriginalAtExactMaximumIsAccepted() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = Data(repeating: 9, count: MessagingProtectedMediaCache.maximumOriginalByteSize)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)
    }

    func testThumbnailAcceptsJPEGAndPNGAtBounds() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let png = try fixture.png(width: 512, height: 512)
        XCTAssertLessThanOrEqual(png.count, MessagingProtectedMediaCache.maximumThumbnailByteSize)
        try await fixture.cache.storeThumbnail(png, mediaID: fixture.mediaID, scope: fixture.scope)
        await expectThumbnail(fixture.cache, fixture.mediaID, fixture.scope, equals: png)

        let jpeg = try fixture.jpeg(width: 512, height: 512)
        let other = UUID()
        try await fixture.cache.storeThumbnail(jpeg, mediaID: other, scope: fixture.scope)
        await expectThumbnail(fixture.cache, other, fixture.scope, equals: jpeg)
    }

    func testThumbnailRejectsPDFAndArbitraryBytes() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let pdf = Data("%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF".utf8)
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.storeThumbnail(pdf, mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.storeThumbnail(Data(repeating: 0x42, count: 512),
                                                   mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await expectMissingThumbnail(fixture.cache, fixture.mediaID, fixture.scope)
    }

    func testThumbnailRejectsDimensionsAbove512Pixels() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let wide = try fixture.png(width: 513, height: 8)
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.storeThumbnail(wide, mediaID: fixture.mediaID, scope: fixture.scope)
        }
        let tall = try fixture.png(width: 8, height: 513)
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.storeThumbnail(tall, mediaID: UUID(), scope: fixture.scope)
        }
    }

    func testThumbnailRejectsBytesAbove128KiB() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let noisy = try fixture.png(width: 512, height: 512, noisy: true)
        XCTAssertGreaterThan(noisy.count, MessagingProtectedMediaCache.maximumThumbnailByteSize,
                             "La fixture doit réellement dépasser la borne pour prouver le refus")
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.storeThumbnail(noisy, mediaID: fixture.mediaID, scope: fixture.scope)
        }
    }

    // MARK: - AAD : identité, genre, scope

    func testStoringDifferentBytesForSameMediaIsRefused() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let first = sentinel + Data([1, 2, 3])
        try await fixture.cache.store(first, mediaID: fixture.mediaID, scope: fixture.scope)
        await fixture.expectFailure(.invalidResponse) {
            try await fixture.cache.store(sentinel + Data([4, 5, 6]), mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: first)
    }

    func testSwappedFileBetweenMediaIsRefused() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let first = sentinel + Data(repeating: 1, count: 256)
        let second = sentinel + Data(repeating: 2, count: 256)
        try await fixture.cache.store(first, mediaID: fixture.mediaID, scope: fixture.scope)
        let other = UUID()
        try await fixture.cache.store(second, mediaID: other, scope: fixture.scope)
        let source = try fixture.fileURL(mediaID: other, genre: .original)
        let target = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)
        try Data(contentsOf: source).write(to: target, options: [.atomic])
        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await expectData(fixture.cache, other, fixture.scope, equals: second)
    }

    func testThumbnailBytesAtOriginalPathAreRefused() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 4, count: 128),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        try await fixture.cache.storeThumbnail(try fixture.png(width: 16, height: 16),
                                               mediaID: fixture.mediaID, scope: fixture.scope)
        let thumbnail = try fixture.fileURL(mediaID: fixture.mediaID, genre: .thumbnail)
        let original = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)
        try Data(contentsOf: thumbnail).write(to: original, options: [.atomic])
        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
    }

    func testFileCopiedFromAnotherScopeIsRefused() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let scopePayload = sentinel + Data(repeating: 6, count: 128)
        let otherPayload = sentinel + Data(repeating: 7, count: 128)
        try await fixture.cache.store(scopePayload, mediaID: fixture.mediaID, scope: fixture.scope)

        let otherScope = MessagingScope(accountID: UUID(), schoolID: fixture.scope.schoolID,
                                        accessEpoch: fixture.scope.accessEpoch, apiBaseURL: fixture.scope.apiBaseURL)
        let otherCache = try MessagingProtectedMediaCache(scope: otherScope, root: fixture.root,
                                                          maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                                                          keyProvider: fixture.key.provider)
        // L'autre scope possède une entrée valide pour le même média : seul l'échange d'octets
        // entre scopes est alors en cause, et l'AAD doit le refuser.
        try await otherCache.store(otherPayload, mediaID: fixture.mediaID, scope: otherScope)
        let source = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)
        let destination = try fixture.fileURL(scope: otherScope, mediaID: fixture.mediaID, genre: .original)
        try Data(contentsOf: source).write(to: destination, options: [.atomic])
        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await otherCache.data(mediaID: fixture.mediaID, scope: otherScope)
        }
    }

    // MARK: - Clé absente, clé fausse, index corrompu

    func testMissingKeyWithExistingFilesIsNeverRecreated() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 8, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)

        let missing = KeyFixture(failure: MessagingFailure.protectionUnavailable)
        let reopened = try MessagingProtectedMediaCache(scope: fixture.scope, root: fixture.root,
                                                        maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                                                        keyProvider: missing.provider)
        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await reopened.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
        XCTAssertEqual(missing.requests, [false], "Aucune clé n'est recréée face à des fichiers existants")
    }

    func testWrongKeyFailsClosedInsteadOfReturningEmptyCache() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 9, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)

        let foreign = KeyFixture()
        let reopened = try MessagingProtectedMediaCache(scope: fixture.scope, root: fixture.root,
                                                        maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                                                        keyProvider: foreign.provider)
        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await reopened.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.expectFailure(.protectionUnavailable) {
            try await reopened.store(Data([1, 2]), mediaID: UUID(), scope: fixture.scope)
        }
    }

    func testCorruptIndexFailsClosedAndIsNotReplaced() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 2, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        let index = try fixture.indexURL()
        let corrupt = Data([0, 1, 2, 3, 4])
        try corrupt.write(to: index, options: [.atomic])

        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.store(Data([1]), mediaID: UUID(), scope: fixture.scope)
        }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.purge(mediaIDs: [fixture.mediaID], scope: fixture.scope)
        }
        XCTAssertEqual(try Data(contentsOf: index), corrupt, "Un index illisible n'est jamais remplacé en silence")
    }

    // MARK: - Cohérence : fichier absent, purge, pas de résurrection

    func testDeletedFileReturnsNilWithoutMemoryFallback() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 3, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)

        try FileManager.default.removeItem(at: fixture.fileURL(mediaID: fixture.mediaID, genre: .original))
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        await expectMissingThumbnail(fixture.cache, fixture.mediaID, fixture.scope)
    }

    func testPurgedMediaIsNotResurrectedAfterReopen() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 5, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        try await fixture.cache.purge(mediaIDs: [fixture.mediaID], scope: fixture.scope)

        let reopened = try fixture.makeCache()
        await expectMissing(reopened, fixture.mediaID, fixture.scope)
        try await reopened.store(sentinel + Data(repeating: 6, count: 256), mediaID: UUID(), scope: fixture.scope)
        await expectMissing(reopened, fixture.mediaID, fixture.scope)
    }

    // MARK: - Orphelins : jamais servis, nettoyés de façon contrôlée

    func testFileWithoutIndexEntryIsNeverServedAndIsCleaned() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x31, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)

        // Fichier scellé présent à un chemin qu'aucune entrée ne référence (simule un fichier
        // écrit sans commit d'index, puis une reprise) : il ne doit jamais être servi.
        let orphanID = UUID()
        let orphan = try fixture.fileURL(mediaID: orphanID, genre: .original)
        let source = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)
        try Data(contentsOf: source).write(to: orphan)
        await expectMissing(fixture.cache, orphanID, fixture.scope)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path), "L'orphelin est nettoyé")
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)
        let reopened = try fixture.makeCache()
        await expectMissing(reopened, orphanID, fixture.scope)
    }

    func testMissingIndexWithSealedFilesIsNotAnEmptyCache() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x32, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        try FileManager.default.removeItem(at: fixture.indexURL())

        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        let mediaPath = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaPath.path),
                       "Sans index valide, le fichier scellé n'est pas adopté : il est écarté")

        let reopened = try fixture.makeCache()
        await expectMissing(reopened, fixture.mediaID, fixture.scope)
        let fresh = UUID()
        try await reopened.store(payload, mediaID: fresh, scope: fixture.scope)
        await expectData(reopened, fresh, fixture.scope, equals: payload)
    }

    func testOrphanCleanupFailureFailsClosed() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 0x33, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        try FileManager.default.removeItem(at: fixture.indexURL())
        let mediaPath = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)

        let scopeDirectory = try fixture.scopeDirectory()
        let permissions = try fixture.permissions(of: scopeDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: scopeDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: scopeDirectory.path) }

        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaPath.path),
                      "Rien n'est servi et rien n'est supprimé en silence quand le nettoyage échoue")

        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: scopeDirectory.path)
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaPath.path))
    }

    func testOrphanCleanupFaultIsClosedAndNotServed() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 0x34, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        let orphanID = UUID()
        let orphan = try fixture.fileURL(mediaID: orphanID, genre: .original)
        try Data(contentsOf: fixture.fileURL(mediaID: fixture.mediaID, genre: .original)).write(to: orphan)
        await fixture.cache.injectFaults { $0 == .orphanCleanup }

        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: orphanID, scope: fixture.scope)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))

        await fixture.cache.injectFaults(nil)
        await expectMissing(fixture.cache, orphanID, fixture.scope)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    // MARK: - Pannes contrôlées après rename et à la synchronisation

    func testIndexCommitFailureIsNotReportedAsSuccess() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x35, count: 512)
        await fixture.cache.injectFaults { $0 == .indexBeforeCommit }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.cache.injectFaults(nil)

        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        let mediaPath = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaPath.path),
                       "Un fichier sans index commité ne reste pas derrière un échec")
        let reopened = try fixture.makeCache()
        await expectMissing(reopened, fixture.mediaID, fixture.scope)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)
    }

    func testPayloadRenameFailureLeavesNoServableData() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        await fixture.cache.injectFaults { $0 == .payloadAfterRename }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.store(sentinel + Data(repeating: 0x36, count: 512),
                                          mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.cache.injectFaults(nil)
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        let reopened = try fixture.makeCache()
        await expectMissing(reopened, fixture.mediaID, fixture.scope)
    }

    func testFileSyncFailureIsNotReportedAsSuccess() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        await fixture.cache.injectFaults { $0 == .fileSync }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.store(sentinel + Data(repeating: 0x37, count: 512),
                                          mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.cache.injectFaults(nil)
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        let files = try fixture.allFiles()
        XCTAssertTrue(files.isEmpty, "Aucun artefact n'est laissé après un échec de synchronisation")
    }

    func testPurgeAllSyncFailureIsPropagated() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 0x38, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        await fixture.cache.injectFaults { $0 == .directorySync }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.purgeAll(scope: fixture.scope)
        }
        await fixture.cache.injectFaults(nil)
        // La purge n'a jamais annoncé de succès ; rien n'est servi depuis un index incohérent.
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
    }

    // MARK: - Quota et LRU

    func testQuotaEvictsLeastRecentlyUsedGroup() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = Data(repeating: 0xAB, count: 4_096)
        let first = UUID(), second = UUID(), third = UUID()
        try await fixture.cache.store(payload, mediaID: first, scope: fixture.scope)
        try await fixture.cache.store(payload, mediaID: second, scope: fixture.scope)
        let usage = try fixture.directoryUsage()
        let tight = try fixture.makeCache(quota: usage + 2_000)

        try await tight.store(payload, mediaID: third, scope: fixture.scope)
        await expectMissing(tight, first, fixture.scope, "L'entrée la moins récemment utilisée est évincée")
        await expectData(tight, second, fixture.scope, equals: payload)
        await expectData(tight, third, fixture.scope, equals: payload)
        XCTAssertLessThanOrEqual(try fixture.directoryUsage(), usage + 2_000)
    }

    func testReadRefreshesLRUAndChangesNextEviction() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = Data(repeating: 0xCD, count: 4_096)
        let first = UUID(), second = UUID(), third = UUID(), fourth = UUID()
        try await fixture.cache.store(payload, mediaID: first, scope: fixture.scope)
        try await fixture.cache.store(payload, mediaID: second, scope: fixture.scope)
        let usage = try fixture.directoryUsage()
        let tight = try fixture.makeCache(quota: usage + 2_000)
        try await tight.store(payload, mediaID: third, scope: fixture.scope)
        await expectMissing(tight, first, fixture.scope)

        await expectData(tight, second, fixture.scope, equals: payload)
        try await tight.store(payload, mediaID: fourth, scope: fixture.scope)
        await expectMissing(tight, third, fixture.scope, "La lecture de B a rajeuni B : C devient la victime")
        await expectData(tight, second, fixture.scope, equals: payload)
        await expectData(tight, fourth, fixture.scope, equals: payload)
    }

    func testEvictionRemovesOriginalAndThumbnailTogether() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = Data(repeating: 0x11, count: 4_096)
        let thumb = try fixture.png(width: 32, height: 32)
        let first = UUID(), second = UUID(), third = UUID()
        try await fixture.cache.store(payload, mediaID: first, scope: fixture.scope)
        try await fixture.cache.storeThumbnail(thumb, mediaID: first, scope: fixture.scope)
        try await fixture.cache.store(payload, mediaID: second, scope: fixture.scope)
        try await fixture.cache.storeThumbnail(thumb, mediaID: second, scope: fixture.scope)
        let usage = try fixture.directoryUsage()
        let tight = try fixture.makeCache(quota: usage + 4_200)

        try await tight.store(payload, mediaID: third, scope: fixture.scope)
        await expectMissing(tight, first, fixture.scope)
        await expectMissingThumbnail(tight, first, fixture.scope, "L'original et sa miniature partent ensemble")
        await expectData(tight, second, fixture.scope, equals: payload)
        await expectThumbnail(tight, second, fixture.scope, equals: thumb)
        await expectData(tight, third, fixture.scope, equals: payload)
    }

    func testLRUOrderSurvivesReopening() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = Data(repeating: 0x22, count: 4_096)
        let first = UUID(), second = UUID(), third = UUID(), fourth = UUID()
        try await fixture.cache.store(payload, mediaID: first, scope: fixture.scope)
        try await fixture.cache.store(payload, mediaID: second, scope: fixture.scope)
        let usage = try fixture.directoryUsage()
        let tight = try fixture.makeCache(quota: usage + 2_000)
        try await tight.store(payload, mediaID: third, scope: fixture.scope)

        let reopened = try fixture.makeCache(quota: usage + 2_000)
        try await reopened.store(payload, mediaID: fourth, scope: fixture.scope)
        await expectMissing(reopened, second, fixture.scope, "L'ordre LRU persiste après réouverture")
        await expectData(reopened, third, fixture.scope, equals: payload)
        await expectData(reopened, fourth, fixture.scope, equals: payload)
    }

    func testQuotaHoldsAfterReadsAndCounterGrowth() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = Data(repeating: 0x5A, count: 1_000)
        let first = UUID(), second = UUID()
        try await fixture.cache.store(payload, mediaID: first, scope: fixture.scope)
        try await fixture.cache.store(payload, mediaID: second, scope: fixture.scope)
        // Aucune marge : la croissance de l'index (compteur LRU) doit suffire à déclencher
        // l'éviction, et la borne doit tenir après chaque lecture.
        let quota = try fixture.directoryUsage()
        let tight = try fixture.makeCache(quota: quota)

        for _ in 0..<12 {
            let read = try await tight.data(mediaID: second, scope: fixture.scope)
            XCTAssertEqual(read, payload, "Le média lu reste servi")
            XCTAssertLessThanOrEqual(try fixture.directoryUsage(), quota,
                                     "La borne réelle tient après une lecture qui fait croître l'index")
        }
        await expectData(tight, second, fixture.scope, equals: payload)
        await expectMissing(tight, first, fixture.scope, "La croissance de l'index a évincé l'autre média")
    }

    func testTwoInstancesKeepQuotaAfterReads() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = Data(repeating: 0x5B, count: 1_000)
        let first = UUID(), second = UUID()
        try await fixture.cache.store(payload, mediaID: first, scope: fixture.scope)
        try await fixture.cache.store(payload, mediaID: second, scope: fixture.scope)
        let quota = try fixture.directoryUsage()
        let one = try fixture.makeCache(quota: quota)
        let two = try fixture.makeCache(quota: quota)

        for index in 0..<10 {
            let cache = index.isMultiple(of: 2) ? one : two
            _ = try await cache.data(mediaID: second, scope: fixture.scope)
            XCTAssertLessThanOrEqual(try fixture.directoryUsage(), quota)
        }
        await expectData(one, second, fixture.scope, equals: payload)
        await expectData(two, second, fixture.scope, equals: payload)
    }

    func testEvictionOrderIsDeterministicOnTies() {
        let low = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let high = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        let marks = [MessagingProtectedMediaCache.AccessMark(mediaID: high, lastAccess: 7),
                     MessagingProtectedMediaCache.AccessMark(mediaID: low, lastAccess: 7)]
        XCTAssertEqual(MessagingProtectedMediaCache.evictionOrder(marks), [low, high])
        let ordered = [MessagingProtectedMediaCache.AccessMark(mediaID: high, lastAccess: 2),
                       MessagingProtectedMediaCache.AccessMark(mediaID: low, lastAccess: 9)]
        XCTAssertEqual(MessagingProtectedMediaCache.evictionOrder(ordered), [high, low])
    }

    // MARK: - Purge et isolation des scopes

    func testPurgeRemovesBothGenresAndIsIdempotent() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x33, count: 512)
        let thumb = try fixture.png(width: 24, height: 24)
        let kept = UUID()
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        try await fixture.cache.storeThumbnail(thumb, mediaID: fixture.mediaID, scope: fixture.scope)
        try await fixture.cache.store(payload, mediaID: kept, scope: fixture.scope)

        try await fixture.cache.purge(mediaIDs: [fixture.mediaID, fixture.mediaID], scope: fixture.scope)
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        await expectMissingThumbnail(fixture.cache, fixture.mediaID, fixture.scope)
        await expectData(fixture.cache, kept, fixture.scope, equals: payload)
        try await fixture.cache.purge(mediaIDs: [fixture.mediaID], scope: fixture.scope)
        try await fixture.cache.purge(mediaIDs: [], scope: fixture.scope)
        await expectData(fixture.cache, kept, fixture.scope, equals: payload)
    }

    func testPurgeAndPurgeAllNeverTouchAnotherScope() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x44, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)

        let otherScope = MessagingScope(accountID: UUID(), schoolID: fixture.scope.schoolID,
                                        accessEpoch: fixture.scope.accessEpoch, apiBaseURL: fixture.scope.apiBaseURL)
        let other = try MessagingProtectedMediaCache(scope: otherScope, root: fixture.root,
                                                     maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                                                     keyProvider: fixture.key.provider)
        let otherMedia = UUID()
        try await other.store(payload, mediaID: otherMedia, scope: otherScope)
        try await other.purge(mediaIDs: [fixture.mediaID], scope: otherScope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)

        try await other.purgeAll(scope: otherScope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)
        await expectMissing(other, otherMedia, otherScope)

        try await fixture.cache.purge(mediaIDs: [otherMedia], scope: fixture.scope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)
    }

    func testPurgeAllRemovesEveryArtifactAndStaysUsable() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 0x55, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        try await fixture.cache.storeThumbnail(try fixture.png(width: 16, height: 16),
                                               mediaID: fixture.mediaID, scope: fixture.scope)

        try await fixture.cache.purgeAll(scope: fixture.scope)
        XCTAssertTrue(try fixture.allFiles().isEmpty)
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)
        try await fixture.cache.purgeAll(scope: fixture.scope)

        let payload = Data([1, 2, 3])
        try await fixture.cache.store(payload, mediaID: UUID(), scope: fixture.scope)
        XCTAssertEqual(try fixture.allFiles().count, 2, "Un index et un média, rien d'autre")
    }

    func testPurgeAllAndEvictionLeaveOutsideSentinelsIntact() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 0x56, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        let rootSentinel = fixture.root.appendingPathComponent("sentinel.bin")
        try Data([1, 2, 3]).write(to: rootSentinel)
        let foreignScope = fixture.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: foreignScope, withIntermediateDirectories: true)
        let foreignFile = foreignScope.appendingPathComponent("keep.sealed")
        try Data([4, 5, 6]).write(to: foreignFile)

        try await fixture.cache.purgeAll(scope: fixture.scope)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootSentinel.path),
                      "La purge ne touche pas la racine")
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignFile.path),
                      "La purge ne touche pas un autre répertoire")
        await expectMissing(fixture.cache, fixture.mediaID, fixture.scope)

        let tight = try fixture.makeCache(quota: 2_000)
        let payload = Data(repeating: 0x57, count: 1_000)
        try await tight.store(payload, mediaID: UUID(), scope: fixture.scope)
        try await tight.store(payload, mediaID: UUID(), scope: fixture.scope)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootSentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreignFile.path))
        XCTAssertLessThanOrEqual(try fixture.scopeUsage(), 2_000)
    }

    // MARK: - Pannes réelles, sans faux succès

    func testWriteFailureIsPropagatedWithoutFalseSuccess() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x66, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        let scopeDirectory = try fixture.scopeDirectory()
        let permissions = try fixture.permissions(of: scopeDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: scopeDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: scopeDirectory.path) }

        let blocked = UUID()
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.store(Data([7, 7, 7]), mediaID: blocked, scope: fixture.scope)
        }
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: scopeDirectory.path)
        await expectMissing(fixture.cache, blocked, fixture.scope)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload,
                         "L'écriture refusée ne corrompt pas l'index existant")
    }

    func testPurgeFailureIsPropagatedWithoutClaimingSuccess() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x77, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        let scopeDirectory = try fixture.scopeDirectory()
        let permissions = try fixture.permissions(of: scopeDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: scopeDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: scopeDirectory.path) }

        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.purge(mediaIDs: [fixture.mediaID], scope: fixture.scope)
        }
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: scopeDirectory.path)
        await expectData(fixture.cache, fixture.mediaID, fixture.scope, equals: payload)
    }

    func testOversizedFileOnDiskIsRefusedBeforeReading() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 0x98, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        // L'entrée existe : c'est bien la borne de lecture qui refuse, pas la règle d'orphelin.
        let oversized = Data(repeating: 0x99, count: 8 * 1_024 * 1_024)
        try oversized.write(to: fixture.fileURL(mediaID: fixture.mediaID, genre: .original), options: [.atomic])
        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
    }

    func testSymlinkedMediaFileIsRefused() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x88, count: 256)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        let sealed = try Data(contentsOf: fixture.fileURL(mediaID: fixture.mediaID, genre: .original))
        let outside = fixture.root.appendingPathComponent("outside.bin")
        try sealed.write(to: outside)
        let target = try fixture.fileURL(mediaID: fixture.mediaID, genre: .original)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)

        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
    }

    func testSymlinkedScopeDirectoryIsRefusedAtInit() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let target = fixture.root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let scopeDirectory = try fixture.scopeDirectory()
        try FileManager.default.removeItem(at: scopeDirectory)
        try FileManager.default.createSymbolicLink(at: scopeDirectory, withDestinationURL: target)

        XCTAssertThrowsError(try MessagingProtectedMediaCache(
            scope: fixture.scope, root: fixture.root,
            maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
            keyProvider: fixture.key.provider)) { error in
            XCTAssertEqual(error as? MessagingFailure, .protectionUnavailable)
        }
    }

    // MARK: - Confinement des répertoires possédés

    func testRootReplacedBySymlinkAfterInitIsRefused() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x91, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)

        let moved = fixture.root.deletingLastPathComponent()
            .appendingPathComponent("drivy-media-cache-moved-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: moved) }
        try FileManager.default.moveItem(at: fixture.root, to: moved)
        try FileManager.default.createSymbolicLink(at: fixture.root, withDestinationURL: moved)

        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.store(Data([1]), mediaID: UUID(), scope: fixture.scope)
        }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.purgeAll(scope: fixture.scope)
        }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.purge(mediaIDs: [fixture.mediaID], scope: fixture.scope)
        }
    }

    func testScopeDirectoryReplacedBySymlinkAfterInitIsRefused() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        try await fixture.cache.store(sentinel + Data(repeating: 0x92, count: 512),
                                      mediaID: fixture.mediaID, scope: fixture.scope)
        let scopeDirectory = try fixture.scopeDirectory()
        let moved = fixture.root.appendingPathComponent("moved-scope-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.moveItem(at: scopeDirectory, to: moved)
        try FileManager.default.createSymbolicLink(at: scopeDirectory, withDestinationURL: moved)

        await fixture.expectFailure(.protectionUnavailable) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: fixture.scope)
        }
        await fixture.expectFailure(.protectionUnavailable) {
            try await fixture.cache.purgeAll(scope: fixture.scope)
        }
    }

    func testIntermediateSymlinkBeforeInitIsResolvedOnceThenVerified() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("drivy-media-cache-links-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real", isDirectory: true)
        let other = base.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2,
                                   apiBaseURL: "https://example.invalid/")
        let key = KeyFixture()
        let cache = try MessagingProtectedMediaCache(scope: scope, root: link.appendingPathComponent("cache"),
                                                     maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                                                     keyProvider: key.provider)
        let payload = sentinel + Data(repeating: 0x93, count: 512)
        let mediaID = UUID()
        try await cache.store(payload, mediaID: mediaID, scope: scope)

        let canonicalScope = real.appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent(MessagingProtectedMediaCache.scopeFingerprint(scope), isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalScope.path),
                      "Le chemin canonique enregistré reçoit les fichiers")
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent("cache").path),
                       "Rien n'est écrit à travers le lien vers une autre cible")

        // Le lien change de cible : l'instance enregistrée continue d'opérer sur sa racine
        // canonique, et ne se laisse pas rediriger.
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        await expectData(cache, mediaID, scope, equals: payload)
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonicalScope.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.appendingPathComponent("cache").path))
    }

    // MARK: - Scope, concurrence, surface

    func testOtherScopeCallsNeverReturnData() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0xAA, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)

        let otherScope = MessagingScope(accountID: fixture.scope.accountID, schoolID: UUID(),
                                        accessEpoch: fixture.scope.accessEpoch, apiBaseURL: fixture.scope.apiBaseURL)
        await fixture.expectFailure(.contextChanged) {
            _ = try await fixture.cache.data(mediaID: fixture.mediaID, scope: otherScope)
        }
        await fixture.expectFailure(.contextChanged) {
            try await fixture.cache.purge(mediaIDs: [fixture.mediaID], scope: otherScope)
        }
        let other = try MessagingProtectedMediaCache(scope: otherScope, root: fixture.root,
                                                     maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                                                     keyProvider: fixture.key.provider)
        await expectMissing(other, fixture.mediaID, otherScope)
    }

    func testInitRejectsScopeWithoutEpochOrAPI() throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        for scope in [MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 0,
                                     apiBaseURL: "https://example.invalid/"),
                      MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1, apiBaseURL: "")] {
            XCTAssertThrowsError(try MessagingProtectedMediaCache(
                scope: scope, root: fixture.root,
                maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                keyProvider: fixture.key.provider)) { error in
                XCTAssertEqual(error as? MessagingFailure, .contextChanged)
            }
        }
    }

    func testTwoInstancesSerializeStoresWithoutLoss() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let first = fixture.cache
        let second = try fixture.makeCache()
        let scope = fixture.scope
        let ids = (0..<20).map { _ in UUID() }
        let payload = sentinel + Data(repeating: 0xBB, count: 512)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    try await (index.isMultiple(of: 2) ? first : second)
                        .store(payload, mediaID: id, scope: scope)
                }
            }
            try await group.waitForAll()
        }
        let reopened = try fixture.makeCache()
        for id in ids {
            await expectData(reopened, id, fixture.scope, equals: payload)
        }
    }

    func testConcurrentStoresRespectQuota() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let quota = 12_000
        let first = try fixture.makeCache(quota: quota)
        let second = try fixture.makeCache(quota: quota)
        let scope = fixture.scope
        let payload = Data(repeating: 0xCC, count: 1_024)
        let ids = (0..<12).map { _ in UUID() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask {
                    try await (index.isMultiple(of: 2) ? first : second)
                        .store(payload, mediaID: id, scope: scope)
                }
            }
            try await group.waitForAll()
        }
        XCTAssertLessThanOrEqual(try fixture.scopeUsage(), quota)
        var survivors = 0
        for id in ids {
            if let data = try await first.data(mediaID: id, scope: fixture.scope) {
                XCTAssertEqual(data, payload)
                survivors += 1
            }
        }
        XCTAssertGreaterThan(survivors, 0)
    }

    func testProtocolSurfaceAndPublishedBounds() async throws {
        let fixture = try Fixture()
        addTeardownBlock { fixture.remove() }
        let surface: any MessagingMediaCache = fixture.cache
        let mediaID = UUID()
        let payload = sentinel + Data(repeating: 0xEE, count: 64)
        try await surface.store(payload, mediaID: mediaID, scope: fixture.scope)
        let stored = try await surface.data(mediaID: mediaID, scope: fixture.scope)
        XCTAssertEqual(stored, payload)
        try await surface.storeThumbnail(try fixture.png(width: 8, height: 8), mediaID: mediaID, scope: fixture.scope)
        let thumb = try await surface.thumbnail(mediaID: mediaID, scope: fixture.scope)
        XCTAssertNotNil(thumb)
        try await surface.purge(mediaIDs: [mediaID], scope: fixture.scope)
        let purged = try await surface.data(mediaID: mediaID, scope: fixture.scope)
        XCTAssertNil(purged)
        try await surface.purgeAll(scope: fixture.scope)

        XCTAssertEqual(MessagingProtectedMediaCache.maximumOriginalByteSize, MessagingMediaAttachment.maximumByteSize)
        XCTAssertEqual(MessagingProtectedMediaCache.maximumOriginalByteSize, 4_194_304)
        XCTAssertEqual(MessagingProtectedMediaCache.maximumThumbnailByteSize, 131_072)
        XCTAssertEqual(MessagingProtectedMediaCache.maximumThumbnailPixels, 512)
        XCTAssertEqual(MessagingProtectedMediaCache.maximumScopeByteSize, 52_428_800)
    }

    // MARK: - Security réel, dans un espace de test isolé

    /// Espace Keychain propre au test : jamais le service de production, jamais une clé existante
    /// d'application. Sous Windows, ce test n'est ni compilé ni exécuté.
    func testKeychainRoundTripInIsolatedTestSpace() throws {
        let space = KeychainTestSpace()
        addTeardownBlock { space.remove() }   // ne supprime que cet espace

        let created = try MessagingProtectedMediaCache.keychainKey(mayCreate: true, namespace: space.namespace)
        let reloaded = try MessagingProtectedMediaCache.keychainKey(mayCreate: false, namespace: space.namespace)
        XCTAssertEqual(created.bitCount, 256)
        XCTAssertEqual(created.withUnsafeBytes { Data($0) }, reloaded.withUnsafeBytes { Data($0) },
                       "La clé relue est identique à celle créée")

        let attributes = try space.attributes()
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool, false,
                       "La clé n'est pas synchronisée")

        let empty = KeychainTestSpace()
        addTeardownBlock { empty.remove() }
        XCTAssertThrowsError(try MessagingProtectedMediaCache.keychainKey(mayCreate: false,
                                                                          namespace: empty.namespace)) { error in
            XCTAssertEqual(error as? MessagingFailure, .protectionUnavailable)
        }
    }

    /// Le cache complet sur une clé réellement stockée par Security, dans l'espace du test.
    func testCacheKeyedByIsolatedKeychainSpaceRoundTrip() async throws {
        let space = KeychainTestSpace()
        addTeardownBlock { space.remove() }
        let namespace = space.namespace
        let fixture = try Fixture(keyProvider: { mayCreate in
            try MessagingProtectedMediaCache.keychainKey(mayCreate: mayCreate, namespace: namespace)
        })
        addTeardownBlock { fixture.remove() }
        let payload = sentinel + Data(repeating: 0x9A, count: 512)
        try await fixture.cache.store(payload, mediaID: fixture.mediaID, scope: fixture.scope)
        let reopened = try fixture.makeCache()
        await expectData(reopened, fixture.mediaID, fixture.scope, equals: payload)
    }

    // MARK: - Assertions asynchrones (aucun `await` dans une autoclosure)

    private func expectData(_ cache: any MessagingMediaCache, _ mediaID: UUID, _ scope: MessagingScope,
                            equals expected: Data, _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let actual = try await cache.data(mediaID: mediaID, scope: scope)
            XCTAssertEqual(actual, expected, message, file: file, line: line)
        } catch {
            XCTFail("Lecture média en échec : \(error)", file: file, line: line)
        }
    }

    private func expectMissing(_ cache: any MessagingMediaCache, _ mediaID: UUID, _ scope: MessagingScope,
                               _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let actual = try await cache.data(mediaID: mediaID, scope: scope)
            XCTAssertNil(actual, message, file: file, line: line)
        } catch {
            XCTFail("Lecture média en échec : \(error)", file: file, line: line)
        }
    }

    private func expectThumbnail(_ cache: any MessagingMediaCache, _ mediaID: UUID, _ scope: MessagingScope,
                                 equals expected: Data, _ message: String = "",
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let actual = try await cache.thumbnail(mediaID: mediaID, scope: scope)
            XCTAssertEqual(actual, expected, message, file: file, line: line)
        } catch {
            XCTFail("Lecture miniature en échec : \(error)", file: file, line: line)
        }
    }

    private func expectMissingThumbnail(_ cache: any MessagingMediaCache, _ mediaID: UUID, _ scope: MessagingScope,
                                        _ message: String = "", file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let actual = try await cache.thumbnail(mediaID: mediaID, scope: scope)
            XCTAssertNil(actual, message, file: file, line: line)
        } catch {
            XCTFail("Lecture miniature en échec : \(error)", file: file, line: line)
        }
    }
}

// MARK: - Fixtures

/// Clé de test en mémoire. Enregistre les demandes de création pour prouver qu'aucune clé n'est
/// recréée face à des fichiers existants.
private final class KeyFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Bool] = []
    private let key: SymmetricKey
    private let failure: Error?

    init(failure: Error? = nil) {
        self.key = SymmetricKey(size: .bits256)
        self.failure = failure
    }

    var requests: [Bool] { lock.withLock { recorded } }

    var provider: @Sendable (Bool) throws -> SymmetricKey {
        { mayCreate in
            self.lock.withLock { self.recorded.append(mayCreate) }
            if let failure = self.failure { throw failure }
            return self.key
        }
    }
}

/// Espace Keychain temporaire, propre au test. `remove` ne supprime que ce service et ce compte.
private struct KeychainTestSpace {
    let namespace = MessagingMediaCacheKeychain(
        service: "ch.drivy.test.media.cache." + UUID().uuidString.lowercased(),
        account: "test-media-cache-key")

    func remove() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: namespace.service,
                                    kSecAttrAccount as String: namespace.account]
        _ = SecItemDelete(query as CFDictionary)
    }

    func attributes() throws -> [String: Any] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: namespace.service,
                                    kSecAttrAccount as String: namespace.account,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any] else {
            throw MessagingFailure.protectionUnavailable
        }
        return attributes
    }
}

private struct Fixture {
    let root: URL
    let scope: MessagingScope
    let mediaID = UUID()
    let key = KeyFixture()
    let cache: MessagingProtectedMediaCache
    private let provider: @Sendable (Bool) throws -> SymmetricKey

    init(keyProvider: (@Sendable (Bool) throws -> SymmetricKey)? = nil) throws {
        let key = KeyFixture()
        self.key = key
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("drivy-media-cache-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 2,
                                   apiBaseURL: "https://example.invalid/")
        self.scope = scope
        let provider = keyProvider ?? key.provider
        self.provider = provider
        cache = try MessagingProtectedMediaCache(scope: scope, root: root,
                                                 maximumScopeBytes: MessagingProtectedMediaCache.maximumScopeByteSize,
                                                 keyProvider: provider)
    }

    func makeCache(quota: Int = MessagingProtectedMediaCache.maximumScopeByteSize) throws -> MessagingProtectedMediaCache {
        try MessagingProtectedMediaCache(scope: scope, root: root, maximumScopeBytes: quota,
                                         keyProvider: provider)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func scopeDirectory() throws -> URL {
        scopeDirectoryFor(scope)
    }

    func scopeDirectoryFor(_ scope: MessagingScope) -> URL {
        root.appendingPathComponent(MessagingProtectedMediaCache.scopeFingerprint(scope), isDirectory: true)
    }

    func indexURL() throws -> URL {
        try scopeDirectory().appendingPathComponent("index.sealed")
    }

    func fileURL(scope: MessagingScope? = nil, mediaID: UUID,
                 genre: MessagingProtectedMediaCache.Genre) throws -> URL {
        let resolved = scope ?? self.scope
        let name = MessagingProtectedMediaCache.opaqueName(
            scopeFingerprint: MessagingProtectedMediaCache.scopeFingerprint(resolved),
            genre: genre, mediaID: mediaID)
        return scopeDirectoryFor(resolved).appendingPathComponent(name + ".sealed")
    }

    func scopeUsage() throws -> Int {
        try usage(of: scopeDirectory())
    }

    func directoryUsage() throws -> Int {
        try usage(of: scopeDirectory())
    }

    private func usage(of directory: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            .reduce(0) { total, url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, let size = values?.fileSize else { return total }
                return total + size
            }
    }

    func allFiles() throws -> [URL] {
        let directory = try scopeDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o700
    }

    func expectFailure<T>(_ expected: MessagingFailure, _ body: () async throws -> T,
                          file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await body()
            XCTFail("Échec fermé attendu : \(expected)", file: file, line: line)
        } catch let failure as MessagingFailure {
            XCTAssertEqual(failure, expected, file: file, line: line)
        } catch {
            XCTFail("Erreur non typée : \(type(of: error))", file: file, line: line)
        }
    }

    // Images synthétiques : aucun contenu réel, aucun fichier importé.

    func png(width: Int, height: Int, noisy: Bool = false) throws -> Data {
        try XCTUnwrap(image(width: width, height: height, noisy: noisy).pngData())
    }

    func jpeg(width: Int, height: Int) throws -> Data {
        try XCTUnwrap(image(width: width, height: height, noisy: false).jpegData(compressionQuality: 0.9))
    }

    private func image(width: Int, height: Int, noisy: Bool) -> UIImage {
        let count = width * height * 4
        var bytes = [UInt8](repeating: 0, count: count)
        if noisy {
            var state: UInt64 = 0x243F_6A88_85A3_08D3
            for index in 0..<count {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
            }
        } else {
            for index in stride(from: 0, to: count, by: 4) {
                bytes[index] = 40
                bytes[index + 1] = 120
                bytes[index + 2] = 200
                bytes[index + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return UIImage(cgImage: cgImage)
    }
}
