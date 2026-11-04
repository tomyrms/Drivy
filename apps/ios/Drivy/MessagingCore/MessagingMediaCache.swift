import Foundation
import CryptoKit
import Security
import Darwin
import ImageIO
import UniformTypeIdentifiers

/// Cache local des médias de la messagerie (#97, contrat §3.10 et §4.5).
///
/// Ce que ce cache **reçoit** : des `Data` **déjà authentifiés et déchiffrés en mémoire** par
/// le consommateur (Megolm pour le fichier, contenu Matrix pour les métadonnées). Il ne
/// déchiffre rien de bout en bout, ne touche ni au réseau, ni à l'import de fichiers, et ne
/// génère aucune miniature : la miniature est fournie par l'appelant, il la valide et la scelle.
///
/// Ce que ce cache **fait** : rechiffrer au repos en AES-GCM, par fichier, avec une clé
/// Keychain dédiée (`WhenUnlockedThisDeviceOnly`, non synchronisée), dans un répertoire opaque
/// par scope (compte/école/époque/API). Le SHA-256 de transport porte sur le chiffré téléchargé
/// et n'est **jamais** comparé aux octets clairs de ce cache : l'intégrité locale vient du tag
/// AES-GCM et de l'AAD qui lie version, scope, identité média et genre.
///
/// Aucune politique de conservation, aucune TTL, aucune purge automatique : le plafond de
/// 50 Mio par scope est une **garde de ressources réversible**, pas une règle d'exploitation.
/// Aucun rendu, aucune UI, aucun branchement de déconnexion.
///
/// Cycle de la clé, exactement : créée au premier scellé d'un scope **seulement si aucun
/// fichier scellé n'existe** ; jamais recréée face à des fichiers existants (clé perdue →
/// erreur fermée) ; jamais supprimée par `purge` ni `purgeAll`, car elle est partagée par les
/// scopes du même appareil — sa destruction relève d'un retrait Keychain hors de ce composant.
/// `unlink` supprime le nom et les octets lisibles par le système : ce cache ne promet **ni**
/// effacement physique du support SSD, **ni** effacement garanti de la mémoire.
protocol MessagingMediaCache: Sendable {
    func store(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws
    func data(mediaID: UUID, scope: MessagingScope) async throws -> Data?
    func thumbnail(mediaID: UUID, scope: MessagingScope) async throws -> Data?
    /// Ajout explicite au §4.5 : sans lui, aucune miniature ne peut entrer dans le cache.
    func storeThumbnail(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws
    func purge(mediaIDs: [UUID], scope: MessagingScope) async throws
    /// Ajout explicite au §4.5 : primitive appelable à la sortie de contexte, à la fin de lien
    /// et à la suppression. Aucun branchement UI, aucun logout implicite dans ce fichier.
    func purgeAll(scope: MessagingScope) async throws
}

/// Cache média local protégé, un scope complet par instance.
///
/// Deux instances du même scope (deux feuilles ouvertes) partagent le même répertoire : la
/// section critique est sérialisée par un verrou **statique** et ne contient **aucun `await`**,
/// car l'acteur seul est réentrant aux points de suspension. Les fichiers d'un scope ne sont
/// jamais rendus à un appel d'un autre scope : le scope attendu est vérifié avant chaque accès.
actor MessagingProtectedMediaCache: MessagingMediaCache {
    /// Genre de contenu stocké. Il entre dans le nom opaque **et** dans l'AAD : un fichier
    /// déplacé d'un genre à l'autre est refusé.
    enum Genre: String, Codable, Sendable, CaseIterable {
        case original
        case thumbnail
    }

    /// Métadonnée scellée dans l'index : identité média, genre, taille claire et rang LRU.
    struct IndexEntry: Codable, Sendable, Equatable {
        let mediaID: UUID
        let genre: Genre
        let byteSize: Int
        var lastAccess: UInt64
    }

    /// Rang LRU d'un média, tous genres confondus (l'éviction part par média entier).
    struct AccessMark: Sendable, Equatable {
        let mediaID: UUID
        let lastAccess: UInt64
    }

    private struct Index: Codable {
        let version: Int
        let scopeFingerprint: String
        var counter: UInt64
        var entries: [IndexEntry]
    }

    private struct CacheFile {
        let url: URL
        let name: String
        let modified: Date
    }

    // MARK: Bornes

    /// Originaux : 1 octet à 4 Mio, même plafond que le produit et le transport.
    static let maximumOriginalByteSize = MessagingMediaAttachment.maximumByteSize
    /// Miniatures : JPEG ou PNG, 128 Kio au plus.
    static let maximumThumbnailByteSize = 131_072
    /// Miniatures : 512 px au plus par axe.
    static let maximumThumbnailPixels = 512
    /// Plafond technique local par scope : originaux + miniatures + index.
    static let maximumScopeByteSize = 52_428_800
    /// Plafond de l'index scellé lui-même.
    static let maximumIndexByteSize = 1_048_576
    /// Nombre d'entrées d'index au plus (borne de travail, jamais une règle produit).
    static let maximumEntryCount = 4_096
    /// Surcoût AES-GCM combiné : nonce 12 octets + tag 16 octets.
    private static let sealedOverhead = 28
    /// Marge réservée à la croissance de l'index lors d'une écriture.
    private static let indexGrowthReserve = 512

    // MARK: État

    private let expectedScope: MessagingScope
    private let fingerprint: String
    private let root: URL
    private let folder: URL
    private let maximumScopeBytes: Int
    private let keyProvider: @Sendable (Bool) throws -> SymmetricKey

    private static let keychainService = "ch.drivy.messaging.media.cache.v1"
    private static let keychainAccount = "media-cache-key-v1"
    private static let rootDirectoryName = "MessagingMediaCache"
    /// Sérialise toutes les instances, y compris celles du même scope. Aucun `await` dedans.
    private static let ioLock = NSLock()

    // MARK: Initialisation

    /// Initialiseur de production : racine Application Support dédiée, clé Keychain dédiée.
    init(scope: MessagingScope) throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        try self.init(scope: scope,
                      root: base.appendingPathComponent(Self.rootDirectoryName, isDirectory: true),
                      maximumScopeBytes: Self.maximumScopeByteSize,
                      keyProvider: { mayCreate in try Self.keychainKey(mayCreate: mayCreate) })
    }

    /// Injection **interne** de la racine, du plafond et de la clé : réservée aux preuves.
    /// La production n'utilise que `init(scope:)` ; aucun repli mémoire n'existe.
    init(scope: MessagingScope, root: URL, maximumScopeBytes: Int,
         keyProvider: @escaping @Sendable (Bool) throws -> SymmetricKey) throws {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else { throw MessagingFailure.contextChanged }
        guard maximumScopeBytes > Self.sealedOverhead + Self.indexGrowthReserve,
              maximumScopeBytes <= Self.maximumScopeByteSize else { throw MessagingFailure.invalidResponse }
        let fingerprint = Self.scopeFingerprint(scope)
        self.expectedScope = scope
        self.fingerprint = fingerprint
        self.root = root
        self.folder = root.appendingPathComponent(fingerprint, isDirectory: true)
        self.maximumScopeBytes = maximumScopeBytes
        self.keyProvider = keyProvider
        try Self.prepareDirectory(root)
        try Self.prepareDirectory(folder)
    }

    // MARK: Interface

    func store(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try verify(scope)
        try Task.checkCancellation()
        try closed { try storeLocked(data, mediaID: mediaID, genre: .original) }
    }

    func storeThumbnail(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try verify(scope)
        try Task.checkCancellation()
        try closed { try storeLocked(data, mediaID: mediaID, genre: .thumbnail) }
    }

    func data(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try verify(scope)
        try Task.checkCancellation()
        return try closed { try readLocked(mediaID: mediaID, genre: .original) }
    }

    func thumbnail(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try verify(scope)
        try Task.checkCancellation()
        return try closed { try readLocked(mediaID: mediaID, genre: .thumbnail) }
    }

    func purge(mediaIDs: [UUID], scope: MessagingScope) async throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try verify(scope)
        try Task.checkCancellation()
        try closed { try purgeLocked(mediaIDs) }
    }

    func purgeAll(scope: MessagingScope) async throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try verify(scope)
        try Task.checkCancellation()
        try closed { try purgeAllLocked() }
    }

    // MARK: Écriture

    private func storeLocked(_ clear: Data, mediaID: UUID, genre: Genre) throws {
        try Self.validate(clear, genre: genre)
        var index = try loadIndex()
        let target = fileURL(mediaID: mediaID, genre: genre)
        if let existing = try readSealed(target, mediaID: mediaID, genre: genre) {
            // Un identifiant média désigne un seul contenu : le remplacer par d'autres octets
            // serait une substitution, jamais une mise à jour.
            guard existing == clear else { throw MessagingFailure.invalidResponse }
            try touch(&index, mediaID: mediaID, genre: genre, byteSize: clear.count)
            try saveIndex(index)
            return
        }
        try evictIfNeeded(index: &index, incomingBytes: clear.count + Self.sealedOverhead, excluding: mediaID)
        try sealAndWrite(clear, to: target, authentication: Self.authentication(fingerprint, genre: genre, mediaID: mediaID))
        do {
            try touch(&index, mediaID: mediaID, genre: genre, byteSize: clear.count)
            try saveIndex(index)
        } catch {
            // Aucun succès avant la garantie durable : sans index scellé, le fichier ne reste pas.
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        try enforceQuotaAfterWrite(index: &index, keeping: mediaID)
    }

    private func touch(_ index: inout Index, mediaID: UUID, genre: Genre, byteSize: Int) throws {
        guard index.counter < UInt64.max else { throw MessagingFailure.protectionUnavailable }
        index.counter += 1
        index.entries.removeAll { $0.mediaID == mediaID && $0.genre == genre }
        index.entries.append(IndexEntry(mediaID: mediaID, genre: genre, byteSize: byteSize, lastAccess: index.counter))
        guard index.entries.count <= Self.maximumEntryCount else { throw MessagingFailure.protectionUnavailable }
    }

    private func sealAndWrite(_ clear: Data, to target: URL, authentication: Data) throws {
        guard clear.count + Self.sealedOverhead <= maximumScopeBytes else { throw MessagingFailure.protectionUnavailable }
        // Calculé avant toute création de fichier : une clé n'est créée que si le cache est vide.
        let mayCreate = mayCreateKey()
        let sealed = try AES.GCM.seal(clear, using: try key(mayCreate: mayCreate), authenticating: authentication)
        guard let bytes = sealed.combined else { throw MessagingFailure.protectionUnavailable }
        let temporary = folder.appendingPathComponent(UUID().uuidString.lowercased() + ".tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                             attributes: [.protectionKey: FileProtectionType.complete]) else {
            throw MessagingFailure.protectionUnavailable
        }
        do {
            try Self.protect(temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
            try handle.close()
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: target)
            }
            try Self.protect(target)
            try Self.synchronize(target, directory: false)
            try Self.synchronize(folder, directory: true)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw MessagingFailure.protectionUnavailable
        }
    }

    // MARK: Lecture

    private func readLocked(mediaID: UUID, genre: Genre) throws -> Data? {
        var index = try loadIndex()
        let url = fileURL(mediaID: mediaID, genre: genre)
        guard let clear = try readSealed(url, mediaID: mediaID, genre: genre) else {
            // Fichier réellement absent : une entrée d'index orpheline est retirée, jamais
            // utilisée pour fabriquer un faux cache ni pour ressusciter un fichier purgé.
            if index.entries.contains(where: { $0.mediaID == mediaID && $0.genre == genre }) {
                index.entries.removeAll { $0.mediaID == mediaID && $0.genre == genre }
                try saveIndex(index)
            }
            return nil
        }
        try touch(&index, mediaID: mediaID, genre: genre, byteSize: clear.count)
        try saveIndex(index)
        return clear
    }

    private func readSealed(_ url: URL, mediaID: UUID, genre: Genre) throws -> Data? {
        guard let bytes = try Self.readBounded(url, maximum: Self.maximumSealedSize(for: genre)) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: bytes)
            let clear = try AES.GCM.open(box, using: try key(mayCreate: false),
                                         authenticating: Self.authentication(fingerprint, genre: genre, mediaID: mediaID))
            try Self.validate(clear, genre: genre)
            return clear
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    // MARK: Index scellé

    private var indexURL: URL { folder.appendingPathComponent("index.sealed") }

    private var indexAuthentication: Data {
        Data("drivy.media.cache.v1|\(fingerprint)|index|aad".utf8)
    }

    private func loadIndex() throws -> Index {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return Index(version: 1, scopeFingerprint: fingerprint, counter: 0, entries: [])
        }
        do {
            guard let bytes = try Self.readBounded(indexURL, maximum: Self.maximumIndexByteSize) else {
                // L'index a disparu entre les deux contrôles : jamais un faux index vide.
                throw MessagingFailure.protectionUnavailable
            }
            let box = try AES.GCM.SealedBox(combined: bytes)
            let clear = try AES.GCM.open(box, using: try key(mayCreate: false), authenticating: indexAuthentication)
            let index = try JSONDecoder().decode(Index.self, from: clear)
            guard index.version == 1, index.scopeFingerprint == fingerprint,
                  index.entries.count <= Self.maximumEntryCount else {
                throw MessagingFailure.protectionUnavailable
            }
            let identities = Set(index.entries.map { "\($0.mediaID.uuidString)|\($0.genre.rawValue)" })
            guard identities.count == index.entries.count else { throw MessagingFailure.protectionUnavailable }
            for entry in index.entries {
                guard entry.lastAccess <= index.counter, Self.isPlausible(entry) else {
                    throw MessagingFailure.protectionUnavailable
                }
            }
            return index
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private func saveIndex(_ index: Index) throws {
        guard index.scopeFingerprint == fingerprint else { throw MessagingFailure.contextChanged }
        var canonical = index
        canonical.entries.sort {
            if $0.mediaID.uuidString.lowercased() != $1.mediaID.uuidString.lowercased() {
                return $0.mediaID.uuidString.lowercased() < $1.mediaID.uuidString.lowercased()
            }
            return $0.genre.rawValue < $1.genre.rawValue
        }
        let clear = try JSONEncoder().encode(canonical)
        guard clear.count + Self.sealedOverhead <= Self.maximumIndexByteSize else {
            throw MessagingFailure.protectionUnavailable
        }
        try sealAndWrite(clear, to: indexURL, authentication: indexAuthentication)
    }

    // MARK: Quota et éviction

    private func evictIfNeeded(index: inout Index, incomingBytes: Int, excluding: UUID) throws {
        guard incomingBytes + Self.indexGrowthReserve <= maximumScopeBytes else {
            throw MessagingFailure.protectionUnavailable
        }
        while try diskUsage() + incomingBytes + Self.indexGrowthReserve > maximumScopeBytes
                || index.entries.count + 1 > Self.maximumEntryCount {
            try evictOne(index: &index, excluding: excluding)
        }
    }

    private func enforceQuotaAfterWrite(index: inout Index, keeping mediaID: UUID) throws {
        guard try diskUsage() > maximumScopeBytes else { return }
        while try diskUsage() > maximumScopeBytes {
            try evictOne(index: &index, excluding: mediaID)
        }
        try saveIndex(index)
    }

    /// Évince une unité : d'abord un artefact orphelin (temporaire, fichier non indexé), puis le
    /// média le moins récemment utilisé — original et miniature ensemble.
    private func evictOne(index: inout Index, excluding: UUID) throws {
        let indexName = indexURL.lastPathComponent
        let referenced = Set(index.entries.map { fileURL(mediaID: $0.mediaID, genre: $0.genre).lastPathComponent })
        let orphans = try cacheFiles()
            .filter { $0.name != indexName && !referenced.contains($0.name) }
            .sorted { ($0.modified, $0.name) < ($1.modified, $1.name) }
        if let orphan = orphans.first {
            try Self.removeFile(orphan.url)
            return
        }
        let groups = Dictionary(grouping: index.entries.filter { $0.mediaID != excluding }, by: { $0.mediaID })
        let marks = groups.map { AccessMark(mediaID: $0.key, lastAccess: $0.value.map(\.lastAccess).max() ?? 0) }
        guard let victim = Self.evictionOrder(marks).first else { throw MessagingFailure.protectionUnavailable }
        for genre in Genre.allCases {
            try Self.removeFile(fileURL(mediaID: victim, genre: genre))
        }
        index.entries.removeAll { $0.mediaID == victim }
    }

    /// Ordre déterministe : rang LRU croissant, puis identité média croissante à égalité.
    static func evictionOrder(_ marks: [AccessMark]) -> [UUID] {
        marks.sorted {
            if $0.lastAccess != $1.lastAccess { return $0.lastAccess < $1.lastAccess }
            return $0.mediaID.uuidString.lowercased() < $1.mediaID.uuidString.lowercased()
        }.map(\.mediaID)
    }

    private func diskUsage() throws -> Int {
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [])
            var total = 0
            for item in items {
                let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true, let size = values.fileSize else { continue }
                total += size
            }
            return total
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private func cacheFiles() throws -> [CacheFile] {
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [])
            var files: [CacheFile] = []
            for item in items where item.pathExtension == "sealed" || item.pathExtension == "tmp" {
                let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey,
                                                               .contentModificationDateKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
                files.append(CacheFile(url: item, name: item.lastPathComponent,
                                       modified: values.contentModificationDate ?? .distantPast))
            }
            return files
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    // MARK: Purge

    private func purgeLocked(_ mediaIDs: [UUID]) throws {
        var unique: [UUID] = []
        for id in mediaIDs where !unique.contains(id) { unique.append(id) }
        guard !unique.isEmpty else { return }
        var index = try loadIndex()
        for id in unique {
            for genre in Genre.allCases { try Self.removeFile(fileURL(mediaID: id, genre: genre)) }
            index.entries.removeAll { $0.mediaID == id }
        }
        try saveIndex(index)
    }

    /// Ne supprime que les fichiers scellés de **ce** scope. Ni la racine, ni un autre scope,
    /// ni le Keychain ne sont touchés. Le répertoire opaque vide est conservé.
    private func purgeAllLocked() throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try Self.requireRealDirectory(folder)
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
                options: [])
            for item in items {
                let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                // Ni lien symbolique, ni sous-répertoire : ce cache n'en crée aucun.
                guard values.isSymbolicLink != true, values.isDirectory != true else {
                    throw MessagingFailure.protectionUnavailable
                }
                try Self.removeFile(item)
            }
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    // MARK: Chemins opaques

    /// Empreinte du scope : compte, école, époque et API. Jamais un identifiant en clair.
    static func scopeFingerprint(_ scope: MessagingScope) -> String {
        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        return SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Nom de fichier opaque : empreinte du scope, du genre et de l'identité média.
    static func opaqueName(scopeFingerprint: String, genre: Genre, mediaID: UUID) -> String {
        let descriptor = "drivy.media.cache.v1|\(scopeFingerprint)|\(genre.rawValue)|\(mediaID.uuidString.lowercased())"
        return SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(mediaID: UUID, genre: Genre) -> URL {
        folder.appendingPathComponent(Self.opaqueName(scopeFingerprint: fingerprint, genre: genre, mediaID: mediaID) + ".sealed")
    }

    /// AAD : version du format, scope, identité média et genre. Un fichier déplacé d'une
    /// identité, d'un scope ou d'un genre ne s'ouvre pas.
    private static func authentication(_ scopeFingerprint: String, genre: Genre, mediaID: UUID) -> Data {
        Data("drivy.media.cache.v1|\(scopeFingerprint)|\(genre.rawValue)|\(mediaID.uuidString.lowercased())|aad".utf8)
    }

    // MARK: Validation

    private static func validate(_ clear: Data, genre: Genre) throws {
        switch genre {
        case .original:
            guard (MessagingMediaAttachment.minimumByteSize...MessagingMediaAttachment.maximumByteSize)
                .contains(clear.count) else { throw MessagingFailure.invalidResponse }
        case .thumbnail:
            try validateThumbnail(clear)
        }
    }

    /// Format et dimensions lus par ImageIO sur les seules métadonnées : aucun décodage, aucune
    /// génération de contenu, aucune allocation proportionnelle aux pixels.
    private static func validateThumbnail(_ data: Data) throws {
        guard (1...maximumThumbnailByteSize).contains(data.count) else { throw MessagingFailure.invalidResponse }
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary),
              let rawType = CGImageSourceGetType(source) else { throw MessagingFailure.invalidResponse }
        let type = rawType as String
        guard type == UTType.jpeg.identifier || type == UTType.png.identifier else {
            throw MessagingFailure.invalidResponse
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              (1...maximumThumbnailPixels).contains(width),
              (1...maximumThumbnailPixels).contains(height) else { throw MessagingFailure.invalidResponse }
    }

    private static func isPlausible(_ entry: IndexEntry) -> Bool {
        switch entry.genre {
        case .original:
            return (MessagingMediaAttachment.minimumByteSize...MessagingMediaAttachment.maximumByteSize)
                .contains(entry.byteSize)
        case .thumbnail:
            return (1...maximumThumbnailByteSize).contains(entry.byteSize)
        }
    }

    private static func maximumSealedSize(for genre: Genre) -> Int {
        switch genre {
        case .original: return maximumOriginalByteSize + sealedOverhead
        case .thumbnail: return maximumThumbnailByteSize + sealedOverhead
        }
    }

    // MARK: Clé

    private func key(mayCreate: Bool) throws -> SymmetricKey {
        do { return try keyProvider(mayCreate) } catch { throw MessagingFailure.protectionUnavailable }
    }

    /// Vrai seulement si aucun artefact scellé n'existe dans la racine : une clé perdue face à
    /// des fichiers existants est une erreur fermée, jamais une nouvelle clé silencieuse.
    private func mayCreateKey() -> Bool {
        guard let scopes = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else {
            return false
        }
        for scopeDirectory in scopes {
            guard let values = try? scopeDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, values.isDirectory == true else { continue }
            guard let files = try? FileManager.default.contentsOfDirectory(at: scopeDirectory,
                                                                          includingPropertiesForKeys: nil, options: []) else {
                return false
            }
            if files.contains(where: { $0.pathExtension == "sealed" }) { return false }
        }
        return true
    }

    private static func keychainKey(mayCreate: Bool) throws -> SymmetricKey {
        if let existing = try keychainKeyIfPresent() { return existing }
        guard mayCreate else { throw MessagingFailure.protectionUnavailable }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard randomStatus == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: keychainService,
                                     kSecAttrAccount as String: keychainAccount,
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                     kSecAttrSynchronizable as String: false,
                                     kSecValueData as String: bytes]
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try keychainKeyIfPresent() { return existing }
        guard status == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        return SymmetricKey(data: bytes)
    }

    private static func keychainKeyIfPresent() throws -> SymmetricKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount,
                                    kSecAttrSynchronizable as String: false,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            throw MessagingFailure.protectionUnavailable
        }
        return SymmetricKey(data: data)
    }

    // MARK: Vérifications et erreurs fermées

    private func verify(_ scope: MessagingScope) throws {
        guard scope == expectedScope else { throw MessagingFailure.contextChanged }
    }

    /// Toute erreur non typée devient une erreur fermée : aucun `NSError`, domaine, chemin ni
    /// `userInfo` ne traverse la frontière du cache.
    private func closed<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let failure as MessagingFailure { throw failure }
        catch { throw MessagingFailure.protectionUnavailable }
    }

    // MARK: Fichiers protégés

    private static func prepareDirectory(_ url: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw MessagingFailure.protectionUnavailable }
            try requireRealDirectory(url)
        } else {
            do {
                try manager.createDirectory(at: url, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
            } catch {
                throw MessagingFailure.protectionUnavailable
            }
        }
        do { try protect(url) } catch { throw MessagingFailure.protectionUnavailable }
    }

    private static func requireRealDirectory(_ url: URL) throws {
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw MessagingFailure.protectionUnavailable
            }
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    /// Borne vérifiée **avant** toute lecture : taille d'abord, contenu ensuite.
    private static func readBounded(_ url: URL, maximum: Int) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= maximum else {
            throw MessagingFailure.protectionUnavailable
        }
        let bytes: Data
        do { bytes = try Data(contentsOf: url) } catch { throw MessagingFailure.protectionUnavailable }
        guard bytes.count == size, bytes.count <= maximum else { throw MessagingFailure.protectionUnavailable }
        return bytes
    }

    private static func removeFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isSymbolicLinkKey]) } catch {
            throw MessagingFailure.protectionUnavailable
        }
        guard values.isSymbolicLink != true else { throw MessagingFailure.protectionUnavailable }
        do { try FileManager.default.removeItem(at: url) } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                              ofItemAtPath: url.path)
        var item = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try item.setResourceValues(values)
    }

    private static func synchronize(_ url: URL, directory: Bool) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw MessagingFailure.protectionUnavailable }
            let descriptor = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (directory ? O_DIRECTORY : 0))
            guard descriptor >= 0 else { throw MessagingFailure.protectionUnavailable }
            defer { Darwin.close(descriptor) }
            let result = directory ? Darwin.fsync(descriptor) : Darwin.fcntl(descriptor, F_FULLFSYNC)
            guard result == 0 else { throw MessagingFailure.protectionUnavailable }
        }
    }
}
