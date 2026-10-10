import Foundation
import Security

/// Intention to join a school with a code, kept before it is sent. The answer of an uncertain
/// request is found again by sending the same bytes under the same operation (idempotent).
struct SchoolCodeJoinRecord: Codable, Equatable, Sendable {
    let version: Int
    let principal: SchoolJoinPrincipal
    let operationID: UUID
    let preview: SchoolCodePreview
    let createdAt: Date
    /// `{operationId, code}`; erased once the school confirmed the membership.
    let body: Data?
    /// Legacy journal field kept to read an already stored pending intention.
    let knownSchoolIDs: [UUID]
    let membership: SchoolMembership?

    static func make(principal: SchoolJoinPrincipal, preview: SchoolCodePreview, code: String,
                     knownSchoolIDs: [UUID], operationID: UUID = UUID(), createdAt: Date = Date()) throws -> SchoolCodeJoinRecord {
        guard let normalized = SchoolInvitationCode.normalized(code) else { throw SchoolJoinFailure.invalidCode }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(SchoolJoinCodeBody(operationId: operationID, code: normalized))
        return SchoolCodeJoinRecord(version: 1, principal: principal, operationID: operationID, preview: preview,
            createdAt: createdAt, body: body, knownSchoolIDs: knownSchoolIDs, membership: nil)
    }

    func confirmed(by membership: SchoolMembership) -> SchoolCodeJoinRecord {
        SchoolCodeJoinRecord(version: version, principal: principal, operationID: operationID, preview: preview,
            createdAt: createdAt, body: nil, knownSchoolIDs: knownSchoolIDs, membership: membership)
    }

    var isValid: Bool {
        guard version == 1, createdAt.timeIntervalSince1970.isFinite, preview.isValid, knownSchoolIDs.count <= 500,
              let apiURL = URL(string: principal.apiBaseURL), AppConfiguration.isSecureEndpoint(apiURL),
              !principal.subject.isEmpty, principal.subject.utf8.count <= 512 else { return false }
        if let membership { return body == nil && membership.accessEpoch > 0 }
        guard let body, body.count <= 1_024, let command = try? JSONDecoder().decode(SchoolJoinCodeBody.self, from: body) else { return false }
        return command.operationId == operationID && SchoolInvitationCode.normalized(command.code) == command.code
    }
}

@MainActor protocol SchoolCodeJoinStore: AnyObject {
    func load(for principal: SchoolJoinPrincipal) throws -> SchoolCodeJoinRecord?
    func save(_ record: SchoolCodeJoinRecord) throws
    func remove(_ record: SchoolCodeJoinRecord) throws
}

/// Stored only in the device-only Keychain, one record per signed-in identity.
@MainActor final class SchoolCodeJoinJournal: SchoolCodeJoinStore {
    private let service = "ch.drivy.invitation-code-acceptance.v1"
    private let maximumBytes = 64 * 1_024

    private func query(_ principal: SchoolJoinPrincipal) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: principal.storageKey, kSecAttrSynchronizable as String: false]
    }

    func load(for principal: SchoolJoinPrincipal) throws -> SchoolCodeJoinRecord? {
        var query = query(principal); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, data.count <= maximumBytes,
              let record = try? JSONDecoder().decode(SchoolCodeJoinRecord.self, from: data),
              record.principal == principal, record.isValid else { throw SchoolJoinFailure.storage }
        return record
    }

    /// A pending intention is never replaced by another one; a confirmed one may be.
    func save(_ record: SchoolCodeJoinRecord) throws {
        guard record.isValid else { throw SchoolJoinFailure.storage }
        if let existing = try load(for: record.principal), existing.operationID != record.operationID, existing.membership == nil {
            throw SchoolJoinFailure.pending
        }
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

    func remove(_ record: SchoolCodeJoinRecord) throws {
        guard let current = try load(for: record.principal) else { return }
        guard current.operationID == record.operationID else { throw SchoolJoinFailure.storage }
        let status = SecItemDelete(query(record.principal) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SchoolJoinFailure.storage }
    }
}
