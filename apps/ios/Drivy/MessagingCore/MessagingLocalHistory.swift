import Foundation
import CryptoKit
import Security

/// Historique déchiffré, conservé sur l'appareil pour la recherche locale (décision 7).
/// Scellé AES-GCM, clé Keychain propre à l'appareil, exclu de la sauvegarde. Jamais de repli en clair.
struct MessagingHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    var id: UUID { messageID }
    let messageID: UUID
    let conversationID: UUID
    let sequence: Int
    let senderID: UUID
    let acceptedAt: Date
    let content: MessagingPlainContent
}

protocol MessagingHistoryStore: Sendable {
    func upsert(_ entries: [MessagingHistoryEntry], scope: MessagingScope) async throws
    func entries(conversationID: UUID, scope: MessagingScope) async throws -> [MessagingHistoryEntry]
    func remove(messageIDs: [UUID], scope: MessagingScope) async throws
    /// Après la fin du lien : rien au-delà du dernier message lisible ne reste sur l'appareil.
    func truncate(conversationID: UUID, after sequence: Int, scope: MessagingScope) async throws
}

/// Sans stockage protégé, aucune copie locale n'est faite : la recherche porte sur la mémoire.
struct UnavailableMessagingHistory: MessagingHistoryStore {
    func upsert(_ entries: [MessagingHistoryEntry], scope: MessagingScope) async throws { throw MessagingFailure.protectionUnavailable }
    func entries(conversationID: UUID, scope: MessagingScope) async throws -> [MessagingHistoryEntry] { [] }
    func remove(messageIDs: [UUID], scope: MessagingScope) async throws {}
    func truncate(conversationID: UUID, after sequence: Int, scope: MessagingScope) async throws {}
}

enum MessagingHistorySearch {
    /// Recherche insensible à la casse et aux accents, du plus récent au plus ancien.
    static func matches(_ entries: [MessagingHistoryEntry], query: String) -> [MessagingHistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return entries.filter { entry in
            var haystack = [entry.content.text ?? ""]
            if let poll = entry.content.poll { haystack.append(poll.question); haystack += poll.options.map(\.label) }
            return haystack.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.sorted { $0.sequence > $1.sequence }
    }
}

actor MessagingSealedHistory: MessagingHistoryStore {
    private struct Snapshot: Codable {
        let scopeFingerprint: String
        var items: [UUID: [MessagingHistoryEntry]]
    }
    private let expectedScope: MessagingScope
    private let folder: URL
    private let file: URL
    private let fingerprint: String
    private static let service = "ch.drivy.messaging.history.v1"
    private static let keyAccount = "history-key"
    private static let maxBytes = 8 * 1_024 * 1_024
    private static let perConversation = 3_000

    init(scope: MessagingScope) throws {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else { throw MessagingFailure.contextChanged }
        expectedScope = scope
        let descriptor = "history|\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.apiBaseURL)"
        fingerprint = SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        folder = base.appendingPathComponent("MessagingHistory", isDirectory: true)
        file = folder.appendingPathComponent(fingerprint + ".sealed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        try Self.protect(folder)
    }

    func upsert(_ entries: [MessagingHistoryEntry], scope: MessagingScope) throws {
        guard !entries.isEmpty else { return }
        var snapshot = try load(scope)
        for entry in entries {
            var list = snapshot.items[entry.conversationID] ?? []
            list.removeAll { $0.messageID == entry.messageID }
            list.append(entry)
            list.sort { $0.sequence < $1.sequence }
            snapshot.items[entry.conversationID] = Array(list.suffix(Self.perConversation))
        }
        try save(snapshot)
    }

    func entries(conversationID: UUID, scope: MessagingScope) throws -> [MessagingHistoryEntry] {
        try load(scope).items[conversationID] ?? []
    }

    func remove(messageIDs: [UUID], scope: MessagingScope) throws {
        let ids = Set(messageIDs)
        var snapshot = try load(scope)
        for key in snapshot.items.keys { snapshot.items[key]?.removeAll { ids.contains($0.messageID) } }
        try save(snapshot)
    }

    func truncate(conversationID: UUID, after sequence: Int, scope: MessagingScope) throws {
        var snapshot = try load(scope)
        snapshot.items[conversationID]?.removeAll { $0.sequence > sequence }
        try save(snapshot)
    }

    private func load(_ scope: MessagingScope) throws -> Snapshot {
        guard scope == expectedScope else { throw MessagingFailure.contextChanged }
        guard FileManager.default.fileExists(atPath: file.path) else { return Snapshot(scopeFingerprint: fingerprint, items: [:]) }
        do {
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= Self.maxBytes else { throw MessagingFailure.protectionUnavailable }
            let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key(create: false),
                                         authenticating: Data(fingerprint.utf8))
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: clear)
            guard snapshot.scopeFingerprint == fingerprint else { throw MessagingFailure.contextChanged }
            return snapshot
        } catch { throw MessagingFailure.protectionUnavailable }
    }

    private func save(_ snapshot: Snapshot) throws {
        let clear = try JSONEncoder().encode(snapshot)
        let sealed = try AES.GCM.seal(clear, using: key(create: true), authenticating: Data(fingerprint.utf8))
        guard let bytes = sealed.combined, bytes.count <= Self.maxBytes else { throw MessagingFailure.protectionUnavailable }
        do {
            try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            try Self.protect(file)
        } catch { throw MessagingFailure.protectionUnavailable }
    }

    private func key(create: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.keyAccount,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let bytes = result as? Data, bytes.count == 32 { return SymmetricKey(data: bytes) }
        guard status == errSecItemNotFound, create else { throw MessagingFailure.protectionUnavailable }
        let key = SymmetricKey(size: .bits256)
        let bytes = key.withUnsafeBytes { Data($0) }
        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.keyAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: bytes]
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        return key
    }

    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var item = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try item.setResourceValues(values)
    }
}
