import Foundation
import CryptoKit
import Security
import Darwin

/// Intention média locale (#97, contrat §3.9/§3.10/§4.5).
///
/// Elle existe **avant** tout dépôt réseau et survit à une relance : le même
/// `mediaID`, les mêmes octets scellés et la même enveloppe Megolm. Ce type ne
/// contient aucun texte d'affichage libre, aucune URL et aucun chemin : le nom
/// du fichier reste une donnée du contenu chiffré, jamais un chemin.
///
/// Invariant : `mediaID` est dérivé du sceau (`sealed.mediaID`) ; le contenu
/// doit désigner exactement ce sceau (`id`, `size`, `file`). L'enveloppe
/// `messageCiphertext` est nulle tant que le contenu n'a pas été chiffré par
/// Megolm ; elle est ensuite immuable sauf comparaison explicite.
struct MessagingPendingMedia: Sendable, Equatable {
    let clientMessageID: UUID
    let conversationID: UUID
    let sealed: MessagingSealedMedia
    let content: MessagingMediaContentV3
    let mentionPersonIDs: [UUID]
    let replyToMessageID: UUID?
    let createdAt: Date
    /// `nil` avant chiffrement Megolm. Renseignée par le futur coordinateur,
    /// jamais par cette file : aucun rechiffrement n'est déclenché ici.
    let messageCiphertext: MessagingCiphertext?

    var mediaID: UUID { sealed.mediaID }

    init(clientMessageID: UUID, conversationID: UUID, sealed: MessagingSealedMedia,
         content: MessagingMediaContentV3, mentionPersonIDs: [UUID] = [],
         replyToMessageID: UUID? = nil, createdAt: Date = Date(),
         messageCiphertext: MessagingCiphertext? = nil) {
        self.clientMessageID = clientMessageID
        self.conversationID = conversationID
        self.sealed = sealed
        self.content = content
        self.mentionPersonIDs = mentionPersonIDs
        self.replyToMessageID = replyToMessageID
        self.createdAt = createdAt
        self.messageCiphertext = messageCiphertext
    }
}

/// File d'intentions média scellées (contrat §4.5). Les trois opérations sont
/// volontairement minimales : aucune ne parle au réseau, aucune n'ouvre le clair
/// d'un média reçu.
protocol MessagingMediaOutbox: Sendable {
    func put(_ pending: MessagingPendingMedia, scope: MessagingScope) async throws
    func entries(scope: MessagingScope) async throws -> [MessagingPendingMedia]
    func remove(mediaID: UUID, scope: MessagingScope) async throws
}

/// Capacité additive de la file média : remplacer **seulement** l'enveloppe
/// Megolm d'une intention, par comparaison avec la valeur courante.
///
/// Ce n'est pas un rechiffrement : l'appelant fournit l'enveloppe déjà calculée
/// par le chiffrement de messages, et cette opération ne modifie aucun autre
/// champ. Un futur coordinateur s'en servira après une décision explicite sur
/// `MEMBERS_CHANGED` ; aucun renvoi ni rechiffrement automatique n'est autorisé.
protocol MessagingMediaOutboxEnvelope: Sendable {
    func replaceEnvelope(mediaID: UUID, expected: MessagingCiphertext?,
                         replacement: MessagingCiphertext, scope: MessagingScope) async throws
}

/// Bornes techniques locales et réversibles. Ce ne sont **pas** une politique
/// d'exploitation ou de conservation : aucune éviction automatique n'existe.
struct MessagingMediaOutboxLimits: Sendable, Equatable {
    /// Nombre maximal d'intentions conservées pour un scope.
    var maximumIntents: Int
    /// Somme maximale des archives scellées sur disque, pour un scope.
    var maximumScopeBytes: Int
    /// Plafond d'une archive scellée (contrôle avant lecture puis après encodage).
    var maximumRecordBytes: Int

    init(maximumIntents: Int = 20,
         maximumScopeBytes: Int = 64 * 1_024 * 1_024,
         maximumRecordBytes: Int = 6 * 1_024 * 1_024) {
        self.maximumIntents = maximumIntents
        self.maximumScopeBytes = maximumScopeBytes
        self.maximumRecordBytes = maximumRecordBytes
    }

    static let standard = MessagingMediaOutboxLimits()
}

/// Fournisseur de la clé dédiée au scope. `create` n'est vrai que lorsqu'aucune
/// archive n'existe : une clé manquante face à des données ne doit **jamais**
/// produire une nouvelle clé ni un repli en clair.
protocol MessagingMediaOutboxKeyStore: Sendable {
    func key(create: Bool) throws -> SymmetricKey
}

/// Frontières d'entrée/sortie de la file, injectables pour éprouver les pannes.
/// Toutes les erreurs sont ramenées par l'acteur à des refus fermés.
protocol MessagingMediaOutboxFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func protect(_ url: URL) throws
    func isSymbolicLink(at url: URL) -> Bool
    func fileExists(at url: URL) -> Bool
    func isRegularFile(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func replaceItem(at target: URL, withItemAt source: URL) throws
    func moveItem(at source: URL, to target: URL) throws
    func remove(_ url: URL) throws
    func synchronizeFile(_ url: URL) throws
    func synchronizeDirectory(_ url: URL) throws
    func contents(of directory: URL) throws -> [URL]
}

/// Keychain locale du scope : clé AES-256 dédiée, `WhenUnlockedThisDeviceOnly`,
/// explicitement non synchronisée. Le compte est l'empreinte opaque du scope.
struct KeychainMediaOutboxKeyStore: MessagingMediaOutboxKeyStore {
    static let service = "ch.drivy.messaging.media-outbox.v1"
    let account: String

    init(account: String) {
        self.account = account
    }

    func key(create: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let bytes = result as? Data, bytes.count == 32 {
            return SymmetricKey(data: bytes)
        }
        guard status == errSecItemNotFound, create else {
            throw MessagingFailure.protectionUnavailable
        }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard randomStatus == errSecSuccess else {
            throw MessagingFailure.protectionUnavailable
        }
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecValueData as String: bytes
        ]
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw MessagingFailure.protectionUnavailable
        }
        return SymmetricKey(data: bytes)
    }
}

/// Système de fichiers réel : `completeFileProtection`, hors sauvegarde,
/// écriture atomique et synchronisation disque, comme le store texte existant
/// (qui n'est pas modifié pour autant).
struct SystemMediaOutboxFileSystem: MessagingMediaOutboxFileSystem {
    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
    }

    func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                             ofItemAtPath: url.path)
        var item = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try item.setResourceValues(values)
    }

    func isSymbolicLink(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isRegularFile(at url: URL) -> Bool {
        guard !isSymbolicLink(at: url) else { return false }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
            return false
        }
        return !directory.boolValue
    }

    func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            throw MessagingFailure.protectionUnavailable
        }
        return size.intValue
    }

    func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw MessagingFailure.protectionUnavailable
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    func replaceItem(at target: URL, withItemAt source: URL) throws {
        _ = try FileManager.default.replaceItemAt(target, withItemAt: source)
    }

    func moveItem(at source: URL, to target: URL) throws {
        try FileManager.default.moveItem(at: source, to: target)
    }

    func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func synchronizeFile(_ url: URL) throws {
        try Self.synchronize(url, directory: false)
    }

    func synchronizeDirectory(_ url: URL) throws {
        try Self.synchronize(url, directory: true)
    }

    func contents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                    options: [])
    }

    private static func synchronize(_ url: URL, directory: Bool) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw MessagingFailure.protectionUnavailable }
            let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW |
                                         (directory ? O_DIRECTORY : 0))
            guard descriptor >= 0 else { throw MessagingFailure.protectionUnavailable }
            defer { Darwin.close(descriptor) }
            let result = directory ? Darwin.fsync(descriptor) : Darwin.fcntl(descriptor, F_FULLFSYNC)
            guard result == 0 else { throw MessagingFailure.protectionUnavailable }
        }
    }
}

/// File média durable, chiffrée **une archive AES-GCM par intention**.
///
/// Le scope complet (compte, école, époque, URL API) est fixé à l'ouverture ;
/// l'empreinte opaque du scope nomme le dossier et les fichiers. Le scope, la
/// version et l'identité du fichier sont authentifiés comme données associées
/// (AAD) et contrôlés dans l'archive : déplacer un fichier vers un autre scope
/// ou vers une autre intention échoue fermé.
///
/// Aucune écriture en clair n'existe : les octets scellés du média ne sont
/// stockés qu'à l'intérieur de l'archive AES-GCM, y compris dans le temporaire.
/// Aucun accès réseau, aucune crypto média, aucune UI.
actor MessagingProtectedMediaOutbox: MessagingMediaOutbox, MessagingMediaOutboxEnvelope {
    /// Sérialise toutes les instances du même processus, y compris deux
    /// instances du même scope : lecture, contrôle de quota et écriture dans la
    /// même section critique. La section ne contient aucun `await`.
    private static let ioLock = NSLock()
    private static let maximumMentions = 8
    private static let recordSuffix = ".sealed"
    private static let temporaryPrefix = "media-outbox-tmp-"
    private static let temporarySuffix = ".tmp"

    private struct RecordFile {
        let url: URL
        let digest: String
        let size: Int
    }

    /// DTO privé : les types existants (`MessagingSealedMedia`) ne deviennent
    /// pas `Codable` pour les besoins de cette file.
    private struct StoredRecord: Codable {
        static let currentVersion = 1

        let version: Int
        let scopeFingerprint: String
        let mediaID: UUID
        let clientMessageID: UUID
        let conversationID: UUID
        let ciphertext: Data
        let encryptionInfo: MessagingMediaEncryptionInfo
        let content: MessagingMediaContentV3
        let mentionPersonIDs: [UUID]
        let replyToMessageID: UUID?
        let createdAt: Date
        var messageCiphertext: MessagingCiphertext?

        init(_ pending: MessagingPendingMedia, scopeFingerprint: String) {
            version = Self.currentVersion
            self.scopeFingerprint = scopeFingerprint
            mediaID = pending.sealed.mediaID
            clientMessageID = pending.clientMessageID
            conversationID = pending.conversationID
            ciphertext = pending.sealed.ciphertext
            encryptionInfo = pending.sealed.info
            content = pending.content
            mentionPersonIDs = pending.mentionPersonIDs
            replyToMessageID = pending.replyToMessageID
            createdAt = pending.createdAt
            messageCiphertext = pending.messageCiphertext
        }

        var pending: MessagingPendingMedia {
            MessagingPendingMedia(clientMessageID: clientMessageID, conversationID: conversationID,
                                  sealed: MessagingSealedMedia(mediaID: mediaID, ciphertext: ciphertext,
                                                               info: encryptionInfo),
                                  content: content, mentionPersonIDs: mentionPersonIDs,
                                  replyToMessageID: replyToMessageID, createdAt: createdAt,
                                  messageCiphertext: messageCiphertext)
        }

        /// Une répétition de la même intention est idempotente ; `createdAt` du
        /// premier enregistrement fait foi et n'est jamais réécrit.
        func isSameIntent(as pending: MessagingPendingMedia) -> Bool {
            clientMessageID == pending.clientMessageID
                && conversationID == pending.conversationID
                && mediaID == pending.sealed.mediaID
                && ciphertext == pending.sealed.ciphertext
                && encryptionInfo == pending.sealed.info
                && content == pending.content
                && mentionPersonIDs == pending.mentionPersonIDs
                && replyToMessageID == pending.replyToMessageID
                && messageCiphertext == pending.messageCiphertext
        }
    }

    private let expectedScope: MessagingScope
    private let fingerprint: String
    private let folder: URL
    private let keyStore: any MessagingMediaOutboxKeyStore
    private let fileSystem: any MessagingMediaOutboxFileSystem
    private let limits: MessagingMediaOutboxLimits

    /// Ouverture de production : racine Application Support et Keychain locale.
    init(scope: MessagingScope) throws {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else {
            throw MessagingFailure.contextChanged
        }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let digest = Self.fingerprint(for: scope)
        let directory = base.appendingPathComponent("MessagingMediaOutbox", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
        let systemFileSystem = SystemMediaOutboxFileSystem()
        expectedScope = scope
        fingerprint = digest
        folder = directory
        keyStore = KeychainMediaOutboxKeyStore(account: digest)
        fileSystem = systemFileSystem
        limits = .standard
        try systemFileSystem.createDirectory(at: directory)
        try systemFileSystem.protect(directory)
    }

    /// Ouverture injectable (tests, artefacts dédiés) : racine, clés, E/S et
    /// bornes fournis par l'appelant. Aucune clé de l'hôte n'est lue ici.
    init(scope: MessagingScope, root: URL,
         keyStore: any MessagingMediaOutboxKeyStore,
         fileSystem: any MessagingMediaOutboxFileSystem,
         limits: MessagingMediaOutboxLimits) throws {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else {
            throw MessagingFailure.contextChanged
        }
        guard limits.maximumIntents > 0, limits.maximumScopeBytes > 0,
              limits.maximumRecordBytes > 0 else {
            throw MessagingFailure.invalidResponse
        }
        let digest = Self.fingerprint(for: scope)
        let directory = root.appendingPathComponent("MessagingMediaOutbox", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
        expectedScope = scope
        fingerprint = digest
        folder = directory
        self.keyStore = keyStore
        self.fileSystem = fileSystem
        self.limits = limits
        try fileSystem.createDirectory(at: directory)
        try fileSystem.protect(directory)
    }

    // MARK: MessagingMediaOutbox

    func put(_ pending: MessagingPendingMedia, scope: MessagingScope) throws {
        try verify(scope)
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        try performPut(pending)
    }

    func entries(scope: MessagingScope) throws -> [MessagingPendingMedia] {
        try verify(scope)
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        return try performEntries()
    }

    func remove(mediaID: UUID, scope: MessagingScope) throws {
        try verify(scope)
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        try performRemove(mediaID)
    }

    // MARK: MessagingMediaOutboxEnvelope

    func replaceEnvelope(mediaID: UUID, expected: MessagingCiphertext?,
                         replacement: MessagingCiphertext, scope: MessagingScope) throws {
        try verify(scope)
        Self.ioLock.lock()
        defer { Self.ioLock.unlock() }
        try performReplaceEnvelope(mediaID: mediaID, expected: expected, replacement: replacement)
    }

    // MARK: Écriture

    private func performPut(_ pending: MessagingPendingMedia) throws {
        do {
            try Self.validate(pending)
            let digest = Self.fileDigest(pending.mediaID, fingerprint: fingerprint)
            let files = try recordFiles()
            if let existingFile = files.first(where: { $0.digest == digest }) {
                let existing = try loadRecord(at: existingFile.url, digest: digest)
                guard existing.isSameIntent(as: pending) else {
                    throw MessagingFailure.stateConflict
                }
                return
            }
            for file in files {
                let record = try loadRecord(at: file.url, digest: file.digest)
                guard record.clientMessageID != pending.clientMessageID else {
                    throw MessagingFailure.stateConflict
                }
            }
            guard files.count < limits.maximumIntents else {
                throw MessagingFailure.protectionUnavailable
            }
            let record = StoredRecord(pending, scopeFingerprint: fingerprint)
            let bytes = try seal(record, digest: digest, mayCreateKey: files.isEmpty)
            let total = files.reduce(0) { $0 + $1.size }
            guard total <= limits.maximumScopeBytes,
                  bytes.count <= limits.maximumScopeBytes - total else {
                throw MessagingFailure.protectionUnavailable
            }
            try write(bytes, digest: digest)
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private func performReplaceEnvelope(mediaID: UUID, expected: MessagingCiphertext?,
                                       replacement: MessagingCiphertext) throws {
        do {
            try Self.validateEnvelope(replacement)
            let digest = Self.fileDigest(mediaID, fingerprint: fingerprint)
            let target = folder.appendingPathComponent(digest + Self.recordSuffix)
            try confine(target)
            guard !fileSystem.isSymbolicLink(at: target), fileSystem.isRegularFile(at: target) else {
                throw MessagingFailure.stateConflict
            }
            let record = try loadRecord(at: target, digest: digest)
            guard record.messageCiphertext == expected else {
                throw MessagingFailure.stateConflict
            }
            guard record.messageCiphertext != replacement else { return }
            var updated = record
            updated.messageCiphertext = replacement
            let files = try recordFiles()
            guard let existing = files.first(where: { $0.digest == digest }) else {
                throw MessagingFailure.stateConflict
            }
            let bytes = try seal(updated, digest: digest, mayCreateKey: false)
            let others = files.reduce(0) { $0 + $1.size } - existing.size
            guard others <= limits.maximumScopeBytes,
                  bytes.count <= limits.maximumScopeBytes - others else {
                throw MessagingFailure.protectionUnavailable
            }
            try write(bytes, digest: digest)
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private func performEntries() throws -> [MessagingPendingMedia] {
        do {
            let files = try recordFiles()
            guard files.count <= limits.maximumIntents else {
                throw MessagingFailure.protectionUnavailable
            }
            var result: [MessagingPendingMedia] = []
            result.reserveCapacity(files.count)
            for file in files {
                let record = try loadRecord(at: file.url, digest: file.digest)
                result.append(record.pending)
            }
            result.sort { left, right in
                if left.createdAt != right.createdAt {
                    return left.createdAt < right.createdAt
                }
                return left.mediaID.uuidString < right.mediaID.uuidString
            }
            return result
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private func performRemove(_ mediaID: UUID) throws {
        do {
            let digest = Self.fileDigest(mediaID, fingerprint: fingerprint)
            let target = folder.appendingPathComponent(digest + Self.recordSuffix)
            try confine(target)
            guard !fileSystem.isSymbolicLink(at: target) else {
                throw MessagingFailure.protectionUnavailable
            }
            guard fileSystem.fileExists(at: target) else { return }
            guard fileSystem.isRegularFile(at: target) else {
                throw MessagingFailure.protectionUnavailable
            }
            try fileSystem.remove(target)
            try fileSystem.synchronizeDirectory(folder)
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    // MARK: Archives

    private func seal(_ record: StoredRecord, digest: String, mayCreateKey: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let clear: Data
        do {
            clear = try encoder.encode(record)
        } catch {
            throw MessagingFailure.invalidResponse
        }
        guard clear.count <= limits.maximumRecordBytes else {
            throw MessagingFailure.invalidResponse
        }
        let key: SymmetricKey
        do {
            key = try keyStore.key(create: mayCreateKey)
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.seal(clear, using: key, authenticating: authentication(for: digest))
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
        guard let combined = box.combined, combined.count <= limits.maximumRecordBytes else {
            throw MessagingFailure.protectionUnavailable
        }
        return combined
    }

    private func loadRecord(at url: URL, digest: String) throws -> StoredRecord {
        guard !fileSystem.isSymbolicLink(at: url), fileSystem.isRegularFile(at: url) else {
            throw MessagingFailure.protectionUnavailable
        }
        let size = try fileSystem.fileSize(at: url)
        guard size > 0, size <= limits.maximumRecordBytes else {
            throw MessagingFailure.protectionUnavailable
        }
        let bytes = try fileSystem.read(url)
        guard !bytes.isEmpty, bytes.count <= limits.maximumRecordBytes else {
            throw MessagingFailure.protectionUnavailable
        }
        let clear: Data
        do {
            clear = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes),
                                     using: try keyStore.key(create: false),
                                     authenticating: authentication(for: digest))
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
        let decoder = JSONDecoder()
        let record: StoredRecord
        do {
            record = try decoder.decode(StoredRecord.self, from: clear)
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
        guard record.version == StoredRecord.currentVersion,
              record.scopeFingerprint == fingerprint,
              Self.fileDigest(record.mediaID, fingerprint: fingerprint) == digest else {
            throw MessagingFailure.protectionUnavailable
        }
        do {
            try Self.validate(record.pending)
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
        return record
    }

    private func recordFiles() throws -> [RecordFile] {
        do {
            guard !fileSystem.isSymbolicLink(at: folder) else {
                throw MessagingFailure.protectionUnavailable
            }
            let entries = try fileSystem.contents(of: folder)
            var files: [RecordFile] = []
            files.reserveCapacity(entries.count)
            for url in entries {
                let name = url.lastPathComponent
                if name.hasPrefix(Self.temporaryPrefix), name.hasSuffix(Self.temporarySuffix) {
                    continue
                }
                guard !fileSystem.isSymbolicLink(at: url), fileSystem.isRegularFile(at: url),
                      name.hasSuffix(Self.recordSuffix) else {
                    throw MessagingFailure.protectionUnavailable
                }
                let digest = String(name.dropLast(Self.recordSuffix.count))
                guard Self.isDigest(digest) else {
                    throw MessagingFailure.protectionUnavailable
                }
                let size = try fileSystem.fileSize(at: url)
                guard size > 0, size <= limits.maximumRecordBytes else {
                    throw MessagingFailure.protectionUnavailable
                }
                files.append(RecordFile(url: url, digest: digest, size: size))
            }
            return files
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private func write(_ bytes: Data, digest: String) throws {
        let temporary = folder.appendingPathComponent(Self.temporaryPrefix +
                                                      UUID().uuidString.lowercased() +
                                                      Self.temporarySuffix)
        let target = folder.appendingPathComponent(digest + Self.recordSuffix)
        do {
            try confine(temporary)
            try confine(target)
            try fileSystem.write(bytes, to: temporary)
            try fileSystem.protect(temporary)
            try fileSystem.synchronizeFile(temporary)
            if fileSystem.fileExists(at: target) {
                try fileSystem.replaceItem(at: target, withItemAt: temporary)
            } else {
                try fileSystem.moveItem(at: temporary, to: target)
            }
            try fileSystem.protect(target)
            try fileSystem.synchronizeFile(target)
            try fileSystem.synchronizeDirectory(folder)
        } catch {
            try? fileSystem.remove(temporary)
            throw MessagingFailure.protectionUnavailable
        }
    }

    // MARK: Validation

    /// Valide l'intention **avant** toute conservation : taille du chiffré,
    /// cohérence contenu/sceau, intégrité par la primitive existante, mentions,
    /// enveloppe Megolm et plafond du contenu Matrix complet.
    private static func validate(_ pending: MessagingPendingMedia) throws {
        guard (1...AESCTRMediaCryptography.maximumByteSize).contains(pending.sealed.ciphertext.count) else {
            throw MessagingFailure.invalidResponse
        }
        guard pending.sealed.mediaID == pending.content.media.id,
              pending.sealed.byteSize == pending.content.media.size,
              pending.sealed.info == pending.content.media.file else {
            throw MessagingFailure.invalidResponse
        }
        guard AESCTRMediaCryptography().verify(pending.sealed.ciphertext, info: pending.sealed.info) else {
            throw MessagingFailure.invalidResponse
        }
        guard pending.mentionPersonIDs.count <= maximumMentions,
              Set(pending.mentionPersonIDs).count == pending.mentionPersonIDs.count else {
            throw MessagingFailure.invalidResponse
        }
        guard pending.createdAt.timeIntervalSince1970.isFinite else {
            throw MessagingFailure.invalidResponse
        }
        if let envelope = pending.messageCiphertext {
            try validateEnvelope(envelope)
        }
        let mentions = pending.mentionPersonIDs.map { $0.uuidString.lowercased() }
        let content: Data
        do {
            content = try MessagingMediaContent.messageContent(pending.content, mentions: mentions)
        } catch {
            throw MessagingFailure.invalidResponse
        }
        guard content.count <= MessagingMediaContent.maximumByteCount else {
            throw MessagingFailure.invalidResponse
        }
    }

    /// Enveloppe opaque bornée : schéma et identifiant de clé non vides, charge
    /// base64 ≤ 12 000 caractères (≤ 9 000 octets décodés), époque positive.
    private static func validateEnvelope(_ envelope: MessagingCiphertext) throws {
        guard !envelope.scheme.isEmpty, envelope.scheme.utf8.count <= 80,
              !envelope.keyID.isEmpty, envelope.keyID.utf8.count <= 128,
              !envelope.payload.isEmpty, envelope.payload.count <= 9_000,
              let epoch = envelope.expectedMembersEpoch, epoch > 0 else {
            throw MessagingFailure.invalidResponse
        }
    }

    // MARK: Empreintes et chemins

    private func verify(_ scope: MessagingScope) throws {
        guard scope == expectedScope else {
            throw MessagingFailure.contextChanged
        }
    }

    private static func fingerprint(for scope: MessagingScope) -> String {
        let descriptor = "\(scope.accountID.uuidString.lowercased())|"
            + "\(scope.schoolID.uuidString.lowercased())|"
            + "\(scope.accessEpoch)|\(scope.apiBaseURL)"
        return SHA256.hash(data: Data(descriptor.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Nom de fichier opaque : jamais l'identifiant média, jamais un nom de
    /// pièce. Le digest dépend du scope et de l'intention.
    private static func fileDigest(_ mediaID: UUID, fingerprint: String) -> String {
        let descriptor = "media-outbox-file-v1|\(fingerprint)|"
            + mediaID.uuidString.lowercased()
        return SHA256.hash(data: Data(descriptor.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// AAD : scope, version et identité du fichier. Un déplacement entre scopes
    /// ou entre intentions ne peut donc pas être authentifié.
    private func authentication(for digest: String) -> Data {
        Data("media-outbox-v1|\(fingerprint)|\(digest)".utf8)
    }

    private func confine(_ url: URL) throws {
        guard url.deletingLastPathComponent().standardizedFileURL.path
            == folder.standardizedFileURL.path else {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
    }
}
