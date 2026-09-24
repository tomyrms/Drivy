import Foundation
import Security

struct SchoolJoinRecord: Codable, Equatable, Sendable {
    let version: Int
    let principal: SchoolJoinPrincipal
    let operationID: UUID
    let preview: SchoolJoinPreview
    let createdAt: Date
    let body: Data?
    let receipt: SchoolOperationReceipt?

    func matches(_ receipt: SchoolOperationReceipt) -> Bool {
        receipt.operationId == operationID && receipt.commandType == "ACCEPT_INVITATION"
            && receipt.resourceType == "Membership" && receipt.resourceVersion > 0 && SchoolLesson.date(receipt.committedAt) != nil
            && (self.receipt.map { $0 == receipt } ?? true)
    }
    func confirmed(by receipt: SchoolOperationReceipt) -> SchoolJoinRecord {
        SchoolJoinRecord(version: version, principal: principal, operationID: operationID, preview: preview,
            createdAt: createdAt, body: nil, receipt: receipt)
    }
    var isValid: Bool {
        guard version == 1, createdAt.timeIntervalSince1970.isFinite,
              let apiURL = URL(string: principal.apiBaseURL), AppConfiguration.isSecureEndpoint(apiURL),
              !principal.subject.isEmpty, principal.subject.utf8.count <= 512,
              preview.notice.version > 0, !preview.roles.isEmpty, SchoolLesson.date(preview.expiresAt) != nil else { return false }
        if let receipt { return body == nil && matches(receipt) }
        guard let body, body.count <= 2_048, let command = try? JSONDecoder().decode(SchoolJoinBody.self, from: body) else { return false }
        return command.operationId == operationID && SchoolJoinClient.validToken(command.token)
    }
}

/// The token and intention are stored only inside the system-encrypted, device-only Keychain.
/// A committed record keeps its receipt but erases the invitation token and command body.
@MainActor final class SchoolJoinJournal {
    private let service = "ch.drivy.invitation-acceptance.v1"
    private let maximumBytes = 512 * 1_024
    private func query(_ principal: SchoolJoinPrincipal) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: principal.storageKey, kSecAttrSynchronizable as String: false]
    }
    func load(for principal: SchoolJoinPrincipal) throws -> SchoolJoinRecord? {
        var query = query(principal); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, data.count <= maximumBytes,
              let record = try? JSONDecoder().decode(SchoolJoinRecord.self, from: data),
              record.principal == principal, record.isValid else { throw SchoolJoinFailure.storage }
        return record
    }
    func save(_ record: SchoolJoinRecord) throws {
        guard record.isValid, record.receipt == nil else { throw SchoolJoinFailure.storage }
        if let existing = try load(for: record.principal) {
            if existing.operationID == record.operationID {
                guard existing == record else { throw SchoolJoinFailure.pending }
            } else { guard existing.receipt != nil else { throw SchoolJoinFailure.pending } }
        }
        try write(record)
    }
    func confirm(_ record: SchoolJoinRecord, receipt: SchoolOperationReceipt) throws -> SchoolJoinRecord {
        guard record.matches(receipt), let current = try load(for: record.principal), current == record else { throw SchoolJoinFailure.storage }
        let confirmed = record.confirmed(by: receipt)
        try write(confirmed); return confirmed
    }
    /// Called only for a new UUID whose first emission received an explicit rejection.
    func removeFreshRejection(_ record: SchoolJoinRecord) throws {
        guard record.receipt == nil, try load(for: record.principal) == record else { throw SchoolJoinFailure.storage }
        let status = SecItemDelete(query(record.principal) as CFDictionary)
        guard status == errSecSuccess else { throw SchoolJoinFailure.storage }
    }
    private func write(_ record: SchoolJoinRecord) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record), data.count <= maximumBytes else { throw SchoolJoinFailure.storage }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(record.principal) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query(record.principal).merging(attributes) { _, value in value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SchoolJoinFailure.storage }
        } else if status != errSecSuccess { throw SchoolJoinFailure.storage }
        guard try load(for: record.principal) == record else { throw SchoolJoinFailure.storage }
    }
}
