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
/// Règle de cohérence de cette première livraison : **un fichier qu'aucun index valide ne
/// référence n'est jamais servi**. Deux situations distinctes :
///
/// - index valide présent : un fichier sans entrée est un orphelin, nettoyé de façon contrôlée
///   (échec propagé) — la clé a déjà été validée par la lecture de l'index ;
/// - index **absent** alors que des fichiers scellés existent : état incohérent, **erreur
///   fermée**. Aucun fichier n'est servi, adopté ni nettoyé, et aucune clé n'est recréée. La
///   seule sortie est `purgeAll`, explicite ; il n'y a aucun rétablissement implicite du cache.
///
/// L'index n'est pas une source de vérité et ne reconstruit aucun contenu : un fichier purgé
/// n'est jamais ressuscité.
///
/// Confinement : l'**ancre de confiance** (Application Support, ou répertoire fourni par la
/// factory de test) peut voir ses préfixes système légitimes canonisés une fois (`/var` →
/// `/private/var`). Les composants **possédés** sous cette ancre — la racine du cache puis le
/// répertoire du scope — ne sont jamais canonisés : s'ils existent comme lien ou comme fichier,
/// la construction échoue avant toute création, protection ou écriture.
///
/// Aucune politique de conservation, aucune TTL, aucune purge automatique : le plafond de
/// 50 Mio par scope est une **garde de ressources réversible**, pas une règle d'exploitation.
/// Aucun rendu, aucune UI, aucun branchement de déconnexion.
///
/// Cycle de la clé, exactement : créée au premier scellé **seulement si aucun fichier scellé
/// n'existe** ; jamais recréée face à des fichiers existants (clé perdue → erreur fermée) ;
/// jamais supprimée par `purge` ni `purgeAll`, car elle est partagée par les scopes du même
/// appareil — sa destruction relève d'un retrait Keychain hors de ce composant. `unlink`
/// supprime le nom et les octets lisibles par le système : ce cache ne promet **ni** effacement
/// physique du support SSD, **ni** effacement garanti de la mémoire.
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

/// Espace Keychain nommé. La production utilise `production` ; les tests n'injectent qu'un
/// espace temporaire qui leur est propre, pour ne jamais lire ni supprimer la clé de l'app.
struct MessagingMediaCacheKeychain: Sendable, Equatable {
    let service: String
    let account: String

    static let production = MessagingMediaCacheKeychain(service: "ch.drivy.messaging.media.cache.v1",
                                                        account: "media-cache-key-v1")
}

/// Cache média local protégé, un scope complet par instance.
///
/// Deux instances du même scope (deux feuilles ouvertes) partagent le même répertoire : la
/// section critique est sérialisée par un verrou **statique** et ne contient **aucun `await`**.
/// `NSLock.lock`/`unlock` portent `noasync` : elles ne sont donc jamais appelées depuis un
/// contexte async, mais depuis la section synchrone `withIOLock` (`NSLock.withLock`).
/// Les fichiers d'un scope ne sont jamais rendus à un appel d'un autre scope : le scope attendu
/// est vérifié avant chaque accès, et les répertoires possédés sont revérifiés avant tout effet.
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

    /// Points de panne internes, **bornés**, réservés aux preuves : ils simulent un échec
    /// précis (rename, synchronisation, nettoyage) sans jamais représenter une coupure
    /// d'alimentation physique. Aucun n'est armé en production.
    enum FaultPoint: Sendable, Equatable {
        case payloadAfterRename
        case indexBeforeCommit
        case fileSync
        case directorySync
        case orphanCleanup
    }

    private enum WriteRole: Equatable {
        case payload
        case index

        var faultAfterRename: FaultPoint {
            switch self {
            case .payload: return .payloadAfterRename
            case .index: return .indexBeforeCommit
            }
        }
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
    /// Ancre **de confiance** fournie par l'OS ou la factory (Application Support, répertoire
    /// temporaire de test) : ses préfixes système légitimes (`/var` → `/private/var`) peuvent être
    /// canonisés **une fois**. L'ancre n'appartient pas au cache et n'est jamais créée ici.
    private let anchor: URL
    /// Composant **possédé** (racine du cache) sous l'ancre. Jamais canonisé : s'il existe comme
    /// lien ou comme fichier, la construction échoue **avant** tout effet.
    private let root: URL
    /// Deuxième composant possédé (répertoire du scope), même règle.
    private let folder: URL
    private let maximumScopeBytes: Int
    private let keyProvider: @Sendable (Bool) throws -> SymmetricKey
    private var faults: (@Sendable (FaultPoint) -> Bool)?

    /// Nom du composant possédé sous l'ancre de production (aussi valeur par défaut de l'injection).
    static let rootDirectoryName = "MessagingMediaCache"
    /// Sérialise toutes les instances, y compris celles du même scope. Aucun `await` dedans.
    private static let ioLock = NSLock()

    // MARK: Initialisation

    /// Initialiseur de production : ancre Application Support fournie par l'OS, composant possédé
    /// `MessagingMediaCache`, clé Keychain dédiée.
    init(scope: MessagingScope) throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        try self.init(scope: scope, anchor: base, rootName: Self.rootDirectoryName,
                      maximumScopeBytes: Self.maximumScopeByteSize,
                      keyProvider: { mayCreate in
                          try Self.keychainKey(mayCreate: mayCreate, namespace: .production)
                      })
    }

    /// Injection **interne** : l'appelant désigne l'**ancre de confiance** et le **nom du composant
    /// possédé** sous cette ancre. La production n'utilise que `init(scope:)` ; aucun repli mémoire
    /// n'existe. Un composant possédé qui est déjà un lien est refusé à la construction.
    init(scope: MessagingScope, anchor: URL, rootName: String = MessagingProtectedMediaCache.rootDirectoryName,
         maximumScopeBytes: Int,
         keyProvider: @escaping @Sendable (Bool) throws -> SymmetricKey) throws {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else { throw MessagingFailure.contextChanged }
        guard maximumScopeBytes > Self.sealedOverhead + Self.indexGrowthReserve,
              maximumScopeBytes <= Self.maximumScopeByteSize else { throw MessagingFailure.invalidResponse }
        try Self.validateComponentName(rootName)
        // Seule l'ancre est canonisée (préfixes système légitimes). Les composants possédés sont
        // construits **sous** elle et ne sont jamais résolus vers une cible arbitraire.
        let canonicalAnchor = anchor.standardizedFileURL.resolvingSymlinksInPath()
        let ownedRoot = canonicalAnchor.appendingPathComponent(rootName, isDirectory: true)
        let folder = ownedRoot.appendingPathComponent(Self.scopeFingerprint(scope), isDirectory: true)
        self.expectedScope = scope
        self.fingerprint = Self.scopeFingerprint(scope)
        self.anchor = canonicalAnchor
        self.root = ownedRoot
        self.folder = folder
        self.maximumScopeBytes = maximumScopeBytes
        self.keyProvider = keyProvider
        // L'ancre est fournie : elle doit exister comme répertoire réel, jamais être créée ici.
        try Self.requireRealDirectory(canonicalAnchor)
        try Self.prepareOwnedDirectory(ownedRoot, inside: canonicalAnchor)
        try Self.prepareOwnedDirectory(folder, inside: ownedRoot)
        try Self.verifyConfinement(anchor: canonicalAnchor, root: ownedRoot, folder: folder)
    }

    /// Forme historique conservée pour les appels qui désignent la racine possédée : l'ancre est
    /// alors son parent, et le nom possédé son dernier composant. Aucune autre sémantique.
    init(scope: MessagingScope, root: URL, maximumScopeBytes: Int,
         keyProvider: @escaping @Sendable (Bool) throws -> SymmetricKey) throws {
        try self.init(scope: scope, anchor: root.deletingLastPathComponent(), rootName: root.lastPathComponent,
                      maximumScopeBytes: maximumScopeBytes, keyProvider: keyProvider)
    }

    /// Arme des points de panne pour une preuve. `nil` rétablit le comportement de production.
    func injectFaults(_ faults: (@Sendable (FaultPoint) -> Bool)?) {
        self.faults = faults
    }

    // MARK: Interface

    func store(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        try verify(scope)
        try Task.checkCancellation()
        try withIOLock {
            try verifyConfinement()
            try storeLocked(data, mediaID: mediaID, genre: .original)
        }
    }

    func storeThumbnail(_ data: Data, mediaID: UUID, scope: MessagingScope) async throws {
        try verify(scope)
        try Task.checkCancellation()
        try withIOLock {
            try verifyConfinement()
            try storeLocked(data, mediaID: mediaID, genre: .thumbnail)
        }
    }

    func data(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        try verify(scope)
        try Task.checkCancellation()
        return try withIOLock {
            try verifyConfinement()
            return try readLocked(mediaID: mediaID, genre: .original)
        }
    }

    func thumbnail(mediaID: UUID, scope: MessagingScope) async throws -> Data? {
        try verify(scope)
        try Task.checkCancellation()
        return try withIOLock {
            try verifyConfinement()
            return try readLocked(mediaID: mediaID, genre: .thumbnail)
        }
    }

    func purge(mediaIDs: [UUID], scope: MessagingScope) async throws {
        try verify(scope)
        try Task.checkCancellation()
        try withIOLock {
            try verifyConfinement()
            try purgeLocked(mediaIDs)
        }
    }

    func purgeAll(scope: MessagingScope) async throws {
        try verify(scope)
        try Task.checkCancellation()
        try withIOLock {
            // Rien à purger si le répertoire du scope n'existe plus : idempotent, sans effet.
            guard FileManager.default.fileExists(atPath: folder.path) else { return }
            try verifyConfinement()
            try purgeAllLocked()
        }
    }

    // MARK: Écriture

    private func storeLocked(_ clear: Data, mediaID: UUID, genre: Genre) throws {
        try Self.validate(clear, genre: genre)
        var index = try loadIndex()
        // Tout fichier qu'aucun index valide ne référence est écarté avant d'écrire : il ne
        // peut donc jamais devenir lisible par une écriture ultérieure.
        try removeUnreferencedFiles(index)
        let target = fileURL(mediaID: mediaID, genre: genre)
        let referenced = index.entries.contains { $0.mediaID == mediaID && $0.genre == genre }
        if referenced {
            if let existing = try readSealed(target, mediaID: mediaID, genre: genre) {
                // Un identifiant média désigne un seul contenu : le remplacer par d'autres
                // octets serait une substitution, jamais une mise à jour.
                guard existing == clear else { throw MessagingFailure.invalidResponse }
                try touch(&index, mediaID: mediaID, genre: genre, byteSize: clear.count)
                try commit(&index, keeping: mediaID)
                return
            }
            // Entrée sans fichier : l'entrée est retirée, l'écriture repart proprement.
            index.entries.removeAll { $0.mediaID == mediaID && $0.genre == genre }
        }
        try evictIfNeeded(index: &index, incomingBytes: clear.count + Self.sealedOverhead, excluding: mediaID)
        do {
            try sealAndWrite(clear, to: target, role: .payload,
                             authentication: Self.authentication(fingerprint, genre: genre, mediaID: mediaID))
        } catch {
            // Aucun fichier non commité ne reste derrière un échec d'écriture.
            try? Self.removeFile(target)
            try? Self.synchronize(folder, directory: true)
            throw error
        }
        do {
            try touch(&index, mediaID: mediaID, genre: genre, byteSize: clear.count)
            try saveIndex(index)
        } catch {
            // Aucun succès avant la garantie durable : sans index scellé, le fichier ne reste pas.
            try? Self.removeFile(target)
            try? Self.synchronize(folder, directory: true)
            throw error
        }
        try enforceQuota(&index, keeping: mediaID)
    }

    private func touch(_ index: inout Index, mediaID: UUID, genre: Genre, byteSize: Int) throws {
        guard index.counter < UInt64.max else { throw MessagingFailure.protectionUnavailable }
        index.counter += 1
        index.entries.removeAll { $0.mediaID == mediaID && $0.genre == genre }
        index.entries.append(IndexEntry(mediaID: mediaID, genre: genre, byteSize: byteSize, lastAccess: index.counter))
        guard index.entries.count <= Self.maximumEntryCount else { throw MessagingFailure.protectionUnavailable }
    }

    private func sealAndWrite(_ clear: Data, to target: URL, role: WriteRole, authentication: Data) throws {
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
            do {
                try handle.write(contentsOf: bytes)
                try handle.synchronize()
                try handle.close()
            } catch {
                // Le descripteur est fermé sur **tous** les chemins, y compris l'échec.
                try? handle.close()
                throw MessagingFailure.protectionUnavailable
            }
            if role == .index, faulted(.indexBeforeCommit) {
                throw MessagingFailure.protectionUnavailable
            }
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: target)
            }
            if faulted(role.faultAfterRename) { throw MessagingFailure.protectionUnavailable }
            if faulted(.fileSync) { throw MessagingFailure.protectionUnavailable }
            try Self.protect(target)
            try Self.synchronize(target, directory: false)
            if faulted(.directorySync) { throw MessagingFailure.protectionUnavailable }
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
        guard index.entries.contains(where: { $0.mediaID == mediaID && $0.genre == genre }) else {
            // Aucun index valide ne référence ce chemin : le fichier n'est pas servi, il est
            // nettoyé (l'échec du nettoyage est propagé, jamais un faux cache vide).
            try discardUnreferenced(url)
            return nil
        }
        guard let clear = try readSealed(url, mediaID: mediaID, genre: genre) else {
            // Fichier réellement absent : l'entrée orpheline est retirée, rien n'est reconstruit.
            index.entries.removeAll { $0.mediaID == mediaID && $0.genre == genre }
            try saveIndex(index)
            return nil
        }
        try touch(&index, mediaID: mediaID, genre: genre, byteSize: clear.count)
        // Toute croissance de l'index (compteur LRU compris) repasse par la borne réelle.
        try commit(&index, keeping: mediaID)
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

    /// Nettoie le fichier d'un chemin qu'aucun index valide ne référence.
    private func discardUnreferenced(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if faulted(.orphanCleanup) { throw MessagingFailure.protectionUnavailable }
        try Self.removeFile(url)
        try Self.synchronize(folder, directory: true)
    }

    /// Nettoie tous les artefacts non référencés (temporaires d'un crash, fichiers sans entrée).
    private func removeUnreferencedFiles(_ index: Index) throws {
        let indexName = indexURL.lastPathComponent
        let referenced = Set(index.entries.map { fileURL(mediaID: $0.mediaID, genre: $0.genre).lastPathComponent })
        var removed = false
        for file in try cacheFiles() where file.name != indexName && !referenced.contains(file.name) {
            if faulted(.orphanCleanup) { throw MessagingFailure.protectionUnavailable }
            try Self.removeFile(file.url)
            removed = true
        }
        if removed { try Self.synchronize(folder, directory: true) }
    }

    // MARK: Index scellé

    private var indexURL: URL { folder.appendingPathComponent("index.sealed") }

    private var indexAuthentication: Data {
        Data("drivy.media.cache.v1|\(fingerprint)|index|aad".utf8)
    }

    private func loadIndex() throws -> Index {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            // Index absent : cache vide **seulement** si aucun artefact scellé n'existe. Des
            // fichiers scellés sans index sont un état incohérent : erreur fermée, aucune
            // adoption, aucun nettoyage silencieux, et donc aucune recréation de clé possible.
            // La sortie explicite est `purgeAll`.
            guard try !hasSealedArtifacts() else { throw MessagingFailure.protectionUnavailable }
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
        try sealAndWrite(clear, to: indexURL, role: .index, authentication: indexAuthentication)
    }

    // MARK: Quota et éviction

    /// Borne réelle après une écriture ou une lecture qui a fait croître l'index.
    private func commit(_ index: inout Index, keeping mediaID: UUID) throws {
        try saveIndex(index)
        try enforceQuota(&index, keeping: mediaID)
    }

    private func enforceQuota(_ index: inout Index, keeping mediaID: UUID) throws {
        guard try diskUsage() > maximumScopeBytes else { return }
        while try diskUsage() > maximumScopeBytes {
            // Si le média conservé et son index ne tiennent plus, l'issue est fermée.
            try evictOne(index: &index, excluding: mediaID)
        }
        try saveIndex(index)
    }

    private func evictIfNeeded(index: inout Index, incomingBytes: Int, excluding: UUID) throws {
        guard incomingBytes + Self.indexGrowthReserve <= maximumScopeBytes else {
            throw MessagingFailure.protectionUnavailable
        }
        while try diskUsage() + incomingBytes + Self.indexGrowthReserve > maximumScopeBytes
                || index.entries.count + 1 > Self.maximumEntryCount {
            try evictOne(index: &index, excluding: excluding)
        }
    }

    /// Évince une unité : d'abord un artefact orphelin (temporaire, fichier non indexé), puis le
    /// média le moins récemment utilisé — original et miniature ensemble. La suppression est
    /// synchronisée avant de rendre la main.
    private func evictOne(index: inout Index, excluding: UUID) throws {
        let indexName = indexURL.lastPathComponent
        let referenced = Set(index.entries.map { fileURL(mediaID: $0.mediaID, genre: $0.genre).lastPathComponent })
        let orphans = try cacheFiles()
            .filter { $0.name != indexName && !referenced.contains($0.name) }
            .sorted { ($0.modified, $0.name) < ($1.modified, $1.name) }
        if let orphan = orphans.first {
            try Self.removeFile(orphan.url)
            if faulted(.directorySync) { throw MessagingFailure.protectionUnavailable }
            try Self.synchronize(folder, directory: true)
            return
        }
        let groups = Dictionary(grouping: index.entries.filter { $0.mediaID != excluding }, by: { $0.mediaID })
        let marks = groups.map { AccessMark(mediaID: $0.key, lastAccess: $0.value.map(\.lastAccess).max() ?? 0) }
        guard let victim = Self.evictionOrder(marks).first else { throw MessagingFailure.protectionUnavailable }
        for genre in Genre.allCases {
            try Self.removeFile(fileURL(mediaID: victim, genre: genre))
        }
        if faulted(.directorySync) { throw MessagingFailure.protectionUnavailable }
        try Self.synchronize(folder, directory: true)
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

    /// Vrai si le répertoire du scope contient au moins un artefact scellé. Sert uniquement à
    /// distinguer un cache réellement vide d'un état incohérent (index absent + données).
    private func hasSealedArtifacts() throws -> Bool {
        do {
            let items = try FileManager.default.contentsOfDirectory(at: folder,
                                                                    includingPropertiesForKeys: nil, options: [])
            return items.contains { $0.pathExtension == "sealed" }
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
        // L'index ne fait que rétrécir ici ; `saveIndex` synchronise aussi le répertoire.
        try saveIndex(index)
    }

    /// Ne supprime que les fichiers scellés de **ce** scope, puis synchronise le répertoire avant
    /// de rendre la main. Ni la racine, ni un autre scope, ni le Keychain ne sont touchés.
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
        if faulted(.directorySync) { throw MessagingFailure.protectionUnavailable }
        try Self.synchronize(folder, directory: true)
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

    /// Clé Keychain d'un espace nommé. La production utilise `.production` ; un espace
    /// temporaire ne sert qu'aux preuves d'isolation.
    static func keychainKey(mayCreate: Bool, namespace: MessagingMediaCacheKeychain) throws -> SymmetricKey {
        guard !namespace.service.isEmpty, !namespace.account.isEmpty else {
            throw MessagingFailure.protectionUnavailable
        }
        if let existing = try keychainKeyIfPresent(namespace) { return existing }
        guard mayCreate else { throw MessagingFailure.protectionUnavailable }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard randomStatus == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: namespace.service,
                                     kSecAttrAccount as String: namespace.account,
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                     kSecAttrSynchronizable as String: false,
                                     kSecValueData as String: bytes]
        let status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try keychainKeyIfPresent(namespace) { return existing }
        guard status == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        return SymmetricKey(data: bytes)
    }

    private static func keychainKeyIfPresent(_ namespace: MessagingMediaCacheKeychain) throws -> SymmetricKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: namespace.service,
                                    kSecAttrAccount as String: namespace.account,
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

    // MARK: Vérifications, confinement et erreurs fermées

    private func verify(_ scope: MessagingScope) throws {
        guard scope == expectedScope else { throw MessagingFailure.contextChanged }
    }

    private func faulted(_ point: FaultPoint) -> Bool {
        faults?(point) == true
    }

    /// Sérialise toutes les instances. `NSLock.lock`/`unlock` sont `noasync` : elles ne sont donc
    /// appelées que depuis cette fonction **synchrone** (`NSLock.withLock`), jamais depuis un
    /// contexte async, et aucun `await` ne peut s'y glisser. Toute erreur non typée devient une
    /// erreur fermée : aucun `NSError`, domaine, chemin ni `userInfo` ne traverse la frontière.
    private func withIOLock<T>(_ body: () throws -> T) throws -> T {
        do {
            return try Self.ioLock.withLock { try body() }
        } catch let failure as MessagingFailure {
            throw failure
        } catch {
            throw MessagingFailure.protectionUnavailable
        }
    }

    /// Revérifie l'ancre de confiance et les composants **possédés** avant tout effet.
    private func verifyConfinement() throws {
        try Self.verifyConfinement(anchor: anchor, root: root, folder: folder)
    }

    /// L'ancre est celle enregistrée à la construction (déjà canonisée, préfixes système
    /// légitimes compris). Les composants possédés doivent être des répertoires réels, non
    /// résolus, et rester les bons enfants : un remplacement par un lien après l'initialisation
    /// change la forme canonique ou le type et échoue ici. Ce n'est pas une protection contre une
    /// course inter-processus : elle couvre un remplacement entre deux opérations, pas un
    /// attaquant actif pendant l'opération.
    private static func verifyConfinement(anchor: URL, root: URL, folder: URL) throws {
        try requireRealDirectory(anchor)
        try requireRealDirectory(root)
        try requireRealDirectory(folder)
        guard samePath(anchor.resolvingSymlinksInPath(), anchor),
              samePath(root.deletingLastPathComponent(), anchor),
              samePath(folder.deletingLastPathComponent(), root),
              samePath(root.resolvingSymlinksInPath(), root),
              samePath(folder.resolvingSymlinksInPath(), folder) else {
            throw MessagingFailure.protectionUnavailable
        }
    }

    private static func samePath(_ left: URL, _ right: URL) -> Bool {
        func normalized(_ url: URL) -> String {
            var path = url.standardizedFileURL.path
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            return path
        }
        return normalized(left) == normalized(right)
    }

    // MARK: Fichiers protégés

    /// Nom de composant possédé : un seul segment, jamais un chemin fourni tel quel.
    private static func validateComponentName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw MessagingFailure.protectionUnavailable
        }
    }

    /// Prépare un composant **possédé** sous son parent déjà vérifié. Un lien, un fichier ou un
    /// parent inattendu est refusé **avant** toute création, protection ou écriture.
    private static func prepareOwnedDirectory(_ url: URL, inside parent: URL) throws {
        guard samePath(url.deletingLastPathComponent(), parent) else {
            throw MessagingFailure.protectionUnavailable
        }
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw MessagingFailure.protectionUnavailable }
            try requireRealDirectory(url)
        } else {
            do {
                // Aucun composant intermédiaire n'est créé : un parent inattendu échouerait ici.
                try manager.createDirectory(at: url, withIntermediateDirectories: false,
                                            attributes: [.protectionKey: FileProtectionType.complete])
            } catch {
                throw MessagingFailure.protectionUnavailable
            }
            try requireRealDirectory(url)
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
