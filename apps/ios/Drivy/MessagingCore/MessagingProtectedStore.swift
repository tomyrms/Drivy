import Foundation
import CryptoKit
import Security
import Darwin

/// Protection locale au repos uniquement. Ne fournit PAS le chiffrement de bout en bout #67.
/// Un snapshot par compte/école/époque/URL API ; aucune donnée de personne dans le chemin ou les logs.
actor MessagingProtectedStore: MessagingProtectedOutbox, MessagingProtectedDrafts, MessagingProtectedReports, MessagingProtectedMutations {
    private struct Snapshot: Codable {
        let scopeFingerprint: String
        var pending: [MessagingPending]
        var drafts: [UUID: String]
        // Optional for snapshots written before report persistence. No cleartext fallback.
        var reports: [UUID: MessagingPendingReport]? = nil
    }

    private let expectedScope: MessagingScope
    private let folder: URL
    private let file: URL
    private var mutationFile: URL { folder.appendingPathComponent(fingerprint + "-mutations.sealed") }
    private var mutationAuthentication: Data { Data((fingerprint + "|mutations-v1").utf8) }
    private let fingerprint: String
    private static let service = "ch.drivy.messaging.local.v1"
    private static let keyAccount = "protected-snapshot-key"
    private static let maxBytes = 2 * 1_024 * 1_024
    /// Sérialise toutes les instances, y compris celles du même scope ouvertes par deux sheets.
    /// La section critique ne contient aucun await et englobe lecture-modification-remplacement.
    private static let ioLock = NSLock()

    init(scope: MessagingScope) throws {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else { throw MessagingFailure.contextChanged }
        expectedScope = scope
        let descriptor = "\(scope.accountID.uuidString.lowercased())|\(scope.schoolID.uuidString.lowercased())|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        fingerprint = SHA256.hash(data: Data(descriptor.utf8)).map { String(format: "%02x", $0) }.joined()
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        folder = base.appendingPathComponent("MessagingProtected", isDirectory: true)
        file = folder.appendingPathComponent(fingerprint + ".sealed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        try Self.protect(folder)
    }

    func put(_ entry: MessagingPending, scope: MessagingScope) throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        var snapshot = try load(scope)
        guard snapshot.pending.count < 500 || snapshot.pending.contains(where: { $0.clientMessageID == entry.clientMessageID }) else {
            throw MessagingFailure.protectionUnavailable
        }
        if let index = snapshot.pending.firstIndex(where: { $0.clientMessageID == entry.clientMessageID }) {
            guard snapshot.pending[index].conversationID == entry.conversationID,
                  snapshot.pending[index].ciphertext == entry.ciphertext,
                  snapshot.pending[index].mentionPersonIDs == entry.mentionPersonIDs,
                  snapshot.pending[index].replyToMessageID == entry.replyToMessageID,
                  snapshot.pending[index].poll == entry.poll,
                  snapshot.pending[index].recoveryContent == entry.recoveryContent else { throw MessagingFailure.invalidResponse }
        } else { snapshot.pending.append(entry) }
        try save(snapshot)
    }

    func entries(scope: MessagingScope) throws -> [MessagingPending] {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        return try load(scope).pending
    }

    func remove(clientMessageID: UUID, scope: MessagingScope) throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        var snapshot = try load(scope)
        snapshot.pending.removeAll { $0.clientMessageID == clientMessageID }
        try save(snapshot)
    }

    func loadDraft(conversationID: UUID, scope: MessagingScope) throws -> String {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        return try load(scope).drafts[conversationID] ?? ""
    }

    func saveDraft(_ text: String, conversationID: UUID, scope: MessagingScope) throws {
        guard text.utf8.count <= 16_384 else { throw MessagingFailure.invalidResponse }
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try Task.checkCancellation()
        var snapshot = try load(scope)
        if text.isEmpty { snapshot.drafts.removeValue(forKey: conversationID) }
        else { snapshot.drafts[conversationID] = text }
        try save(snapshot)
    }

    func pendingReport(conversationID: UUID, scope: MessagingScope) throws -> MessagingPendingReport? {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        return try load(scope).reports?[conversationID]
    }

    func prepareReport(_ candidate: MessagingPendingReport, scope: MessagingScope) throws -> MessagingPendingReport {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try Task.checkCancellation()
        try Self.validateReport(candidate)
        var snapshot = try load(scope)
        var reports = snapshot.reports ?? [:]
        if let existing = reports[candidate.conversationID] {
            if existing.messageIDs == candidate.messageIDs { return existing }
            guard existing.clientReportID != candidate.clientReportID else { throw MessagingFailure.invalidResponse }
        }
        guard reports.count < 100 || reports[candidate.conversationID] != nil else { throw MessagingFailure.protectionUnavailable }
        reports[candidate.conversationID] = candidate
        snapshot.reports = reports
        try save(snapshot)
        return candidate
    }

    func removeReport(conversationID: UUID, clientReportID: UUID, scope: MessagingScope) throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try Task.checkCancellation()
        var snapshot = try load(scope)
        guard snapshot.reports?[conversationID]?.clientReportID == clientReportID else { return }
        snapshot.reports?.removeValue(forKey: conversationID)
        try save(snapshot)
    }

    private static func validateReport(_ report: MessagingPendingReport) throws {
        guard (1...50).contains(report.items.count), report.messageIDs.count == report.items.count,
              report.items.allSatisfy({ !$0.ciphertext.payload.isEmpty }) else { throw MessagingFailure.invalidResponse }
    }

    private struct MutationSnapshot: Codable {
        let version: Int
        let scopeFingerprint: String
        var entries: [MessagingStoredMutation]
    }

    func mutationEntries(scope: MessagingScope) throws -> [MessagingStoredMutation] {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        return try loadMutations(scope).entries
    }

    func putMutation(_ entry: MessagingStoredMutation, replacing clock: UUID?, scope: MessagingScope) throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        guard entry.isValid else { throw MessagingFailure.invalidResponse }
        var snapshot = try loadMutations(scope)
        if let index = snapshot.entries.firstIndex(where: { $0.key == entry.key }) {
            let current = snapshot.entries[index]
            guard current.value.clock == clock || current == entry else { throw MessagingFailure.stateConflict }
            snapshot.entries[index] = entry
        } else {
            guard clock == nil else { throw MessagingFailure.stateConflict }
            guard snapshot.entries.count < 500 else { throw MessagingFailure.protectionUnavailable }
            snapshot.entries.append(entry)
        }
        try saveMutations(snapshot)
    }

    func removeMutation(_ key: MessagingMutationKey, id: UUID, clock: UUID, scope: MessagingScope) throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        var snapshot = try loadMutations(scope)
        snapshot.entries.removeAll { $0.key == key && $0.value.id == id && $0.value.clock == clock }
        try saveMutations(snapshot)
    }

    private func loadMutations(_ scope: MessagingScope) throws -> MutationSnapshot {
        try verify(scope)
        guard FileManager.default.fileExists(atPath: mutationFile.path) else {
            return MutationSnapshot(version: 1, scopeFingerprint: fingerprint, entries: [])
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: mutationFile.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue <= Self.maxBytes else { throw MessagingFailure.protectionUnavailable }
            let bytes = try Data(contentsOf: mutationFile)
            guard bytes.count <= Self.maxBytes else { throw MessagingFailure.protectionUnavailable }
            let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key(create: false), authenticating: mutationAuthentication)
            let snapshot = try JSONDecoder().decode(MutationSnapshot.self, from: clear)
            guard snapshot.version == 1, snapshot.scopeFingerprint == fingerprint, snapshot.entries.count <= 500,
                  Set(snapshot.entries.map(\.key)).count == snapshot.entries.count,
                  snapshot.entries.allSatisfy(\.isValid) else { throw MessagingFailure.protectionUnavailable }
            return snapshot
        } catch { throw MessagingFailure.protectionUnavailable }
    }

    private func saveMutations(_ snapshot: MutationSnapshot) throws {
        guard snapshot.scopeFingerprint == fingerprint else { throw MessagingFailure.contextChanged }
        try save(JSONEncoder().encode(snapshot), to: mutationFile, authentication: mutationAuthentication)
    }

    /// À invoquer explicitement lors d'une révocation connue ; une clé d'une autre époque ne récupère pas ce fichier.
    func purge(scope: MessagingScope) throws {
        Self.ioLock.lock(); defer { Self.ioLock.unlock() }
        try verify(scope)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        if FileManager.default.fileExists(atPath: mutationFile.path) { try FileManager.default.removeItem(at: mutationFile) }
    }

    private func verify(_ scope: MessagingScope) throws {
        guard scope == expectedScope else { throw MessagingFailure.contextChanged }
    }

    private func load(_ scope: MessagingScope) throws -> Snapshot {
        try verify(scope)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return Snapshot(scopeFingerprint: fingerprint, pending: [], drafts: [:])
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maxBytes else { throw MessagingFailure.protectionUnavailable }
            let bytes = try Data(contentsOf: file)
            let combined = try AES.GCM.SealedBox(combined: bytes)
            let clear = try AES.GCM.open(combined, using: key(create: false), authenticating: Data(fingerprint.utf8))
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: clear)
            guard snapshot.scopeFingerprint == fingerprint else { throw MessagingFailure.contextChanged }
            guard (snapshot.reports?.count ?? 0) <= 100 else { throw MessagingFailure.protectionUnavailable }
            for (conversation, report) in snapshot.reports ?? [:] {
                guard report.conversationID == conversation else { throw MessagingFailure.protectionUnavailable }
                try Self.validateReport(report)
            }
            return snapshot
        } catch { throw MessagingFailure.protectionUnavailable }
    }

    private func save(_ snapshot: Snapshot) throws {
        guard snapshot.scopeFingerprint == fingerprint else { throw MessagingFailure.contextChanged }
        let clear = try JSONEncoder().encode(snapshot)
        try save(clear, to: file, authentication: Data(fingerprint.utf8))
    }

    private func save(_ clear: Data, to target: URL, authentication: Data) throws {
        guard clear.count <= Self.maxBytes - 128 else { throw MessagingFailure.protectionUnavailable }
        let mayCreateKey = !FileManager.default.fileExists(atPath: file.path)
            && !FileManager.default.fileExists(atPath: mutationFile.path)
        let sealed = try AES.GCM.seal(clear, using: key(create: mayCreateKey), authenticating: authentication)
        guard let bytes = sealed.combined, bytes.count <= Self.maxBytes else { throw MessagingFailure.protectionUnavailable }
        let temporary = folder.appendingPathComponent(UUID().uuidString + ".tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]) else { throw MessagingFailure.protectionUnavailable }
        do {
            try Self.protect(temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
            try handle.close()
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at: temporary, to: target) }
            try Self.protect(target)
            try Self.synchronize(target, directory: false)
            try Self.synchronize(folder, directory: true)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw MessagingFailure.protectionUnavailable
        }
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

    private func key(create: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.keyAccount,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let bytes = result as? Data, bytes.count == 32 { return SymmetricKey(data: bytes) }
        guard status == errSecItemNotFound, create else { throw MessagingFailure.protectionUnavailable }
        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        let insert: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service, kSecAttrAccount as String: Self.keyAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: bytes]
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        return SymmetricKey(data: bytes)
    }

    private static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var item = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try item.setResourceValues(values)
    }
}
