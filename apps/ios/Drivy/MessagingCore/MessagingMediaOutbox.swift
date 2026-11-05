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
    func isDirectory(at url: URL) -> Bool
    func isRegularFile(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int
    func read(_ url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func replaceItem(at target: URL, withItemAt source: URL) throws
    func moveItem(at source: URL, to target: URL) throws
    func remove(_ url: URL) throws
    func synchronizeFile(_ url: URL) throws
    func synchronizeDirectory(_ url: URL) throws
    /// Énumération bornée : au-delà de `limit`, lève sans matérialiser la suite.
    func contents(of directory: URL, limit: Int) throws -> [URL]
}

/// Keychain locale du scope : clé AES-256 dédiée, `WhenUnlockedThisDeviceOnly`,
/// explicitement non synchronisée. Le compte est l'empreinte opaque du scope.
///
/// Une clé préexistante dont la classe d'accessibilité ou la synchronisation ne
/// correspond pas à l'exigence échoue fermé : elle n'est ni utilisée, ni
/// remplacée, ni élargie.
struct KeychainMediaOutboxKeyStore: MessagingMediaOutboxKeyStore {
    static let service = "ch.drivy.messaging.media-outbox.v1"
    let account: String

    init(account: String) {
        self.account = account
    }

    /// Contrôle des attributs réellement rendus par la Keychain. Séparé pour
    /// être éprouvé avec des dictionnaires synthétiques, sans jamais lire une
    /// clé de l'hôte.
    static func validatedKey(from attributes: [String: Any]) -> SymmetricKey? {
        guard let accessible = attributes[kSecAttrAccessible as String] as? String,
              accessible == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String) else {
            return nil
        }
        // Absent = non synchronisé (la requête filtre déjà sur false) ; une
        // valeur vraie est refusée.
        if let raw = attributes[kSecAttrSynchronizable as String] {
            guard let synchronizable = raw as? Bool, synchronizable == false else { return nil }
        }
        guard let bytes = attributes[kSecValueData as String] as? Data, bytes.count == 32 else {
            return nil
        }
        return SymmetricKey(data: bytes)
    }

    func key(create: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let attributes = result as? [String: Any],
                  let key = Self.validatedKey(from: attributes) else {
                throw MessagingFailure.protectionUnavailable
            }
            return key
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

    /// `lstat` : un lien symbolique, même pendant, est vu comme tel.
    func isSymbolicLink(at url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            return true
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isDirectory(at url: URL) -> Bool {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
            return false
        }
        return directory.boolValue
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

    func contents(of directory: URL, limit: Int) throws -> [URL] {
        guard limit > 0 else { return [] }
        guard let enumerator = FileManager.default.enumerator(at: directory,
                                                             includingPropertiesForKeys: nil,
                                                             options: [.skipsSubdirectoryDescendants]) else {
            throw MessagingFailure.protectionUnavailable
        }
        var urls: [URL] = []
        urls.reserveCapacity(min(limit, 64))
        for case let url as URL in enumerator {
            urls.append(url)
            if urls.count > limit { throw MessagingFailure.protectionUnavailable }
        }
        return urls
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
    /// Nombre maximal de temporaires résiduels tolérés. Au-delà, l'admission
    /// est refusée : un crash répété ne contourne ni le quota ni le nombre.
    private static let maximumResidualTemporaries = 8
    private static let ownedRootName = "MessagingMediaOutbox"
    private static let recordSuffix = ".sealed"
    private static let temporaryPrefix = "media-outbox-tmp-"
    private static let temporarySuffix = ".tmp"

    private struct RecordFile {
        let url: URL
        let digest: String
        let size: Int
    }

    private struct Snapshot {
        let records: [RecordFile]
        let temporaryBytes: Int
        let temporaryCount: Int
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
    /// Racine fournie par l'appelant, normalisée mais non résolue : un lien
    /// symbolique à ce niveau est refusé, pas traversé.
    private let rootURL: URL
    /// `root/MessagingMediaOutbox`, composant possédé et contrôlé.
    private let ownedRoot: URL
    private let folder: URL
    /// Chemin canonique de la racine, capturé à l'ouverture : un ancêtre
    /// remplacé ensuite ne peut plus correspondre.
    private let canonicalRootPath: String
    private let keyStore: any MessagingMediaOutboxKeyStore
    private let fileSystem: any MessagingMediaOutboxFileSystem
    private let limits: MessagingMediaOutboxLimits

    /// Ouverture de production : racine Application Support et Keychain locale.
    init(scope: MessagingScope) throws {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else {
            throw MessagingFailure.contextChanged
        }
        let base: URL
        do {
            base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
        let systemFileSystem = SystemMediaOutboxFileSystem()
        let digest = Self.fingerprint(for: scope)
        let prepared = try Self.prepare(root: base, fingerprint: digest, fileSystem: systemFileSystem)
        expectedScope = scope
        fingerprint = digest
        rootURL = base.standardizedFileURL
        ownedRoot = prepared.ownedRoot
        folder = prepared.folder
        canonicalRootPath = prepared.canonicalRootPath
        keyStore = KeychainMediaOutboxKeyStore(account: digest)
        fileSystem = systemFileSystem
        limits = .standard
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
        guard (1...10_000).contains(limits.maximumIntents),
              (1...(1 << 30)).contains(limits.maximumScopeBytes),
              (1...(64 << 20)).contains(limits.maximumRecordBytes) else {
            throw MessagingFailure.invalidResponse
        }
        let digest = Self.fingerprint(for: scope)
        let prepared = try Self.prepare(root: root, fingerprint: digest, fileSystem: fileSystem)
        expectedScope = scope
        fingerprint = digest
        rootURL = root.standardizedFileURL
        ownedRoot = prepared.ownedRoot
        folder = prepared.folder
        canonicalRootPath = prepared.canonicalRootPath
        self.keyStore = keyStore
        self.fileSystem = fileSystem
        self.limits = limits
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
            try verifyOwnedLocation()
            try Self.validate(pending)
            let digest = Self.fileDigest(pending.mediaID, fingerprint: fingerprint)
            let snapshot = try scanFiles()
            if let existingFile = snapshot.records.first(where: { $0.digest == digest }) {
                let existing = try loadRecord(at: existingFile.url, digest: digest)
                guard existing.isSameIntent(as: pending) else {
                    throw MessagingFailure.stateConflict
                }
                // Un échec antérieur a pu laisser l'état neuf non synchronisé :
                // aucune réussite n'est rendue sans resceller les protections et
                // sans refaire les deux synchronisations. L'intention n'est pas
                // réécrite et son horodatage ne change pas.
                try reconfirm(existingFile.url)
                return
            }
            // Le plafond est vérifié avant toute lecture d'archive : aucune
            // intention existante n'est chargée quand l'admission est impossible.
            guard snapshot.records.count < limits.maximumIntents else {
                throw MessagingFailure.protectionUnavailable
            }
            for file in snapshot.records {
                let record = try loadRecord(at: file.url, digest: file.digest)
                guard record.clientMessageID != pending.clientMessageID else {
                    throw MessagingFailure.stateConflict
                }
            }
            let record = StoredRecord(pending, scopeFingerprint: fingerprint)
            // Aucune clé nouvelle dès qu'un octet scellé (archive ou temporaire)
            // subsiste : une clé perdue ne doit jamais être remplacée en silence.
            let mayCreateKey = snapshot.records.isEmpty && snapshot.temporaryCount == 0
            let bytes = try seal(record, digest: digest, mayCreateKey: mayCreateKey)
            let used = try Self.totalBytes(snapshot.records) + snapshot.temporaryBytes
            guard used <= limits.maximumScopeBytes,
                  bytes.count <= limits.maximumScopeBytes - used else {
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
            try verifyOwnedLocation()
            try Self.validateEnvelope(replacement)
            let digest = Self.fileDigest(mediaID, fingerprint: fingerprint)
            let target = folder.appendingPathComponent(digest + Self.recordSuffix)
            try confine(target)
            guard !fileSystem.isSymbolicLink(at: target), fileSystem.isRegularFile(at: target) else {
                throw MessagingFailure.stateConflict
            }
            let record = try loadRecord(at: target, digest: digest)
            // Comparaison stricte conservée : une reprise peut relire l'état,
            // jamais écraser une valeur concurrente.
            guard record.messageCiphertext == expected else {
                throw MessagingFailure.stateConflict
            }
            if record.messageCiphertext == replacement {
                try reconfirm(target)
                return
            }
            var updated = record
            updated.messageCiphertext = replacement
            let snapshot = try scanFiles()
            guard let existing = snapshot.records.first(where: { $0.digest == digest }) else {
                throw MessagingFailure.stateConflict
            }
            let bytes = try seal(updated, digest: digest, mayCreateKey: false)
            let others = try Self.totalBytes(snapshot.records) - existing.size + snapshot.temporaryBytes
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
            try verifyOwnedLocation()
            let snapshot = try scanFiles()
            guard snapshot.records.count <= limits.maximumIntents else {
                throw MessagingFailure.protectionUnavailable
            }
            var result: [MessagingPendingMedia] = []
            result.reserveCapacity(snapshot.records.count)
            for file in snapshot.records {
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
            try verifyOwnedLocation()
            let digest = Self.fileDigest(mediaID, fingerprint: fingerprint)
            let target = folder.appendingPathComponent(digest + Self.recordSuffix)
            try confine(target)
            guard !fileSystem.isSymbolicLink(at: target) else {
                throw MessagingFailure.protectionUnavailable
            }
            guard fileSystem.fileExists(at: target) else {
                // Une suppression antérieure a pu réussir sans que le dossier
                // soit synchronisé : ne jamais annoncer un succès durable avant
                // de refaire cette synchronisation.
                try fileSystem.synchronizeDirectory(folder)
                return
            }
            guard fileSystem.isRegularFile(at: target) else {
                throw MessagingFailure.protectionUnavailable
            }
            try verifyOwnedLocation()
            try fileSystem.remove(target)
            try fileSystem.synchronizeDirectory(folder)
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    /// Reconfirme les protections et les deux synchronisations d'un état déjà
    /// présent, sans réécrire l'archive ni toucher son contenu.
    private func reconfirm(_ url: URL) throws {
        do {
            try verifyOwnedLocation()
            guard !fileSystem.isSymbolicLink(at: url), fileSystem.isRegularFile(at: url) else {
                throw MessagingFailure.protectionUnavailable
            }
            try fileSystem.protect(url)
            try fileSystem.synchronizeFile(url)
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

    /// Énumération bornée avant toute lecture d'archive. Les temporaires
    /// résiduels sont vus, comptés et bornés : ni ignorés du quota, ni effacés
    /// (une autre instance pourrait encore les publier).
    private func scanFiles() throws -> Snapshot {
        do {
            let (recordLimit, overflow) = limits.maximumIntents
                .addingReportingOverflow(Self.maximumResidualTemporaries)
            guard !overflow else { throw MessagingFailure.protectionUnavailable }
            let (ceiling, ceilingOverflow) = recordLimit.addingReportingOverflow(1)
            guard !ceilingOverflow else { throw MessagingFailure.protectionUnavailable }
            let entries = try fileSystem.contents(of: folder, limit: ceiling)
            guard entries.count <= ceiling - 1 else {
                throw MessagingFailure.protectionUnavailable
            }
            var records: [RecordFile] = []
            records.reserveCapacity(min(entries.count, limits.maximumIntents))
            var temporaryBytes = 0
            var temporaryCount = 0
            for url in entries {
                let name = url.lastPathComponent
                guard !fileSystem.isSymbolicLink(at: url), fileSystem.isRegularFile(at: url) else {
                    throw MessagingFailure.protectionUnavailable
                }
                let size = try fileSystem.fileSize(at: url)
                guard size > 0, size <= limits.maximumRecordBytes else {
                    throw MessagingFailure.protectionUnavailable
                }
                if Self.isTemporaryName(name) {
                    temporaryCount += 1
                    temporaryBytes += size
                    continue
                }
                guard name.hasSuffix(Self.recordSuffix) else {
                    throw MessagingFailure.protectionUnavailable
                }
                let digest = String(name.dropLast(Self.recordSuffix.count))
                guard Self.isDigest(digest) else {
                    throw MessagingFailure.protectionUnavailable
                }
                records.append(RecordFile(url: url, digest: digest, size: size))
            }
            guard temporaryCount <= Self.maximumResidualTemporaries else {
                throw MessagingFailure.protectionUnavailable
            }
            return Snapshot(records: records, temporaryBytes: temporaryBytes,
                            temporaryCount: temporaryCount)
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
            try verifyOwnedLocation()
            try confine(temporary)
            try confine(target)
            try fileSystem.write(bytes, to: temporary)
            try fileSystem.protect(temporary)
            try fileSystem.synchronizeFile(temporary)
            // Contrôle juste avant le renommage : un dossier ou un ancêtre
            // remplacé depuis l'ouverture refuse l'opération avant tout effet.
            try verifyOwnedLocation()
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
    /// enveloppe Megolm et plafond du contenu Matrix complet mesuré dans la
    /// **forme canonique réellement émise** (`@uuid:drivy`), mentions comprises.
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
        // Forme exacte de `encryptMatrixContent` : sans cette conversion,
        // l'intention pourrait être admise puis refusée à l'émission.
        let mentions = pending.mentionPersonIDs.map { MatrixMessagingCryptography.userID($0) }
        let content: Data
        do {
            content = try MessagingMediaContent.messageContent(pending.content, mentions: mentions)
        } catch {
            throw MessagingFailure.invalidResponse
        }
        guard content.count <= MessagingPlainContent.maximumV3ByteCount else {
            throw MessagingFailure.invalidResponse
        }
    }

    /// Enveloppe opaque bornée : schéma et identifiant de clé non vides, charge
    /// base64 ≤ 12 000 caractères (≤ 9 000 octets décodés), époque de membres ≥ 0.
    /// `0` est l'époque légale d'une conversation neuve (migration `DEFAULT 0`,
    /// route `min(0)`) : la borne suit le contrat serveur, pas une supposition.
    private static func validateEnvelope(_ envelope: MessagingCiphertext) throws {
        guard !envelope.scheme.isEmpty, envelope.scheme.utf8.count <= 80,
              !envelope.keyID.isEmpty, envelope.keyID.utf8.count <= 128,
              !envelope.payload.isEmpty, envelope.payload.count <= 9_000,
              let epoch = envelope.expectedMembersEpoch, epoch >= 0 else {
            throw MessagingFailure.invalidResponse
        }
    }

    // MARK: Empreintes, chemins et racine

    private func verify(_ scope: MessagingScope) throws {
        guard scope == expectedScope else {
            throw MessagingFailure.contextChanged
        }
    }

    /// Contrôle de la racine de confiance et des composants possédés, à chaque
    /// opération et autour des renommages/suppressions. Les ancêtres système
    /// légitimes (par exemple `/var` → `/private/var`) sont résolus pour la
    /// comparaison, mais la racine elle-même et chaque composant possédé
    /// doivent être des dossiers réels, jamais des liens.
    private func verifyOwnedLocation() throws {
        guard !fileSystem.isSymbolicLink(at: rootURL), fileSystem.isDirectory(at: rootURL) else {
            throw MessagingFailure.protectionUnavailable
        }
        let canonicalRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalRoot.path == canonicalRootPath,
              !fileSystem.isSymbolicLink(at: ownedRoot),
              fileSystem.isDirectory(at: ownedRoot),
              ownedRoot.resolvingSymlinksInPath().standardizedFileURL.path
                == Self.componentPath(canonicalRoot, [Self.ownedRootName]),
              !fileSystem.isSymbolicLink(at: folder),
              fileSystem.isDirectory(at: folder),
              folder.resolvingSymlinksInPath().standardizedFileURL.path
                == Self.componentPath(canonicalRoot, [Self.ownedRootName, fingerprint]) else {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private static func prepare(root: URL, fingerprint: String,
                                fileSystem: any MessagingMediaOutboxFileSystem)
        throws -> (ownedRoot: URL, folder: URL, canonicalRootPath: String) {
        do {
            let standardizedRoot = root.standardizedFileURL
            guard !fileSystem.isSymbolicLink(at: standardizedRoot),
                  fileSystem.isDirectory(at: standardizedRoot) else {
                throw MessagingFailure.protectionUnavailable
            }
            let canonicalRoot = standardizedRoot.resolvingSymlinksInPath().standardizedFileURL
            let owned = standardizedRoot.appendingPathComponent(ownedRootName, isDirectory: true)
            let folder = owned.appendingPathComponent(fingerprint, isDirectory: true)
            try ensureDirectory(owned,
                                expectedPath: componentPath(canonicalRoot, [ownedRootName]),
                                fileSystem: fileSystem)
            try ensureDirectory(folder,
                                expectedPath: componentPath(canonicalRoot, [ownedRootName, fingerprint]),
                                fileSystem: fileSystem)
            // Aucune protection n'est appliquée avant les contrôles ci-dessus.
            try fileSystem.protect(owned)
            try fileSystem.protect(folder)
            return (owned, folder, canonicalRoot.path)
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private static func ensureDirectory(_ url: URL, expectedPath: String,
                                        fileSystem: any MessagingMediaOutboxFileSystem) throws {
        guard !fileSystem.isSymbolicLink(at: url) else {
            throw MessagingFailure.protectionUnavailable
        }
        if fileSystem.fileExists(at: url) {
            guard fileSystem.isDirectory(at: url) else {
                throw MessagingFailure.protectionUnavailable
            }
        } else {
            try fileSystem.createDirectory(at: url)
            guard !fileSystem.isSymbolicLink(at: url), fileSystem.isDirectory(at: url) else {
                throw MessagingFailure.protectionUnavailable
            }
        }
        guard url.resolvingSymlinksInPath().standardizedFileURL.path == expectedPath else {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private static func componentPath(_ root: URL, _ components: [String]) -> String {
        components.reduce(root) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }.path
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

    private static func isTemporaryName(_ name: String) -> Bool {
        guard name.hasPrefix(temporaryPrefix), name.hasSuffix(temporarySuffix) else {
            return false
        }
        let middle = name.dropFirst(temporaryPrefix.count).dropLast(temporarySuffix.count)
        guard (1...64).contains(middle.count) else { return false }
        return middle.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102) || byte == 45
        }
    }

    private static func totalBytes(_ records: [RecordFile]) throws -> Int {
        var total = 0
        for record in records {
            let (sum, overflow) = total.addingReportingOverflow(record.size)
            guard !overflow else { throw MessagingFailure.protectionUnavailable }
            total = sum
        }
        return total
    }
}
