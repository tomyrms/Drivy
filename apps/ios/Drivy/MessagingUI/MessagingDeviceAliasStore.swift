import CryptoKit
import Foundation
import Security

protocol MessagingDeviceAliases: Sendable {
    func load(scope: MessagingScope) async throws -> [String: String]
    func set(_ name: String, device: MessagingOwnDevice, scope: MessagingScope) async throws -> [String: String]
}

enum MessagingDeviceAliasRules {
    static let maximumLength = 64
    static func normalized(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func valid(_ name: String) -> Bool {
        name.count <= maximumLength && !name.unicodeScalars.contains {
            $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0)
                || (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
        }
    }
    /// The same device ID with a replaced key never inherits an old name.
    static func identity(_ device: MessagingOwnDevice) -> String {
        digest("\(device.id.utf8.count):\(device.id)\(device.fingerprint)")
    }
    static func account(_ scope: MessagingScope) throws -> String {
        guard scope.accessEpoch > 0, !scope.apiBaseURL.isEmpty else { throw MessagingFailure.contextChanged }
        let data = try JSONEncoder().encode([scope.accountID.uuidString.lowercased(), scope.schoolID.uuidString.lowercased(),
            String(scope.accessEpoch), scope.apiBaseURL])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The iOS Keychain encrypts this dedicated item at rest. No cleartext file, UserDefaults or iCloud synchronisation;
/// the ThisDeviceOnly class prevents migration to another device.
/// One item per complete authorized scope; aliases never enter the cryptographic trust/signing store.
final class MessagingKeychainDeviceAliases: MessagingDeviceAliases, @unchecked Sendable {
    private struct Snapshot: Codable {
        let version: Int
        let scope: String
        var names: [String: String]
    }
    private static let service = "ch.drivy.messaging.device-aliases.v1"
    private static let lock = NSLock()
    private static let maximumBytes = 65_536

    func load(scope: MessagingScope) async throws -> [String: String] {
        try readSynchronously(scope: scope)
    }
    func set(_ name: String, device: MessagingOwnDevice, scope: MessagingScope) async throws -> [String: String] {
        try writeSynchronously(name, device: device, scope: scope)
    }
    private func readSynchronously(scope: MessagingScope) throws -> [String: String] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try read(account: MessagingDeviceAliasRules.account(scope)).names
    }
    private func writeSynchronously(_ name: String, device: MessagingOwnDevice, scope: MessagingScope) throws -> [String: String] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try Task.checkCancellation()
        let name = MessagingDeviceAliasRules.normalized(name)
        guard MessagingDeviceAliasRules.valid(name), !device.id.isEmpty, !device.fingerprint.isEmpty else {
            throw MessagingFailure.invalidResponse
        }
        let account = try MessagingDeviceAliasRules.account(scope)
        var snapshot = try read(account: account)
        let identity = MessagingDeviceAliasRules.identity(device)
        if name.isEmpty { snapshot.names.removeValue(forKey: identity) }
        else { snapshot.names[identity] = name }
        guard snapshot.names.count <= 128 else { throw MessagingFailure.protectionUnavailable }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= Self.maximumBytes else { throw MessagingFailure.protectionUnavailable }
        let query = query(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insert = query.merging(attributes) { _, new in new }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw MessagingFailure.protectionUnavailable }
        } else if status != errSecSuccess { throw MessagingFailure.protectionUnavailable }
        // The UI only adopts names read back from the protected item.
        let confirmed = try read(account: account)
        guard confirmed.names == snapshot.names else { throw MessagingFailure.protectionUnavailable }
        return confirmed.names
    }
    private func read(account: String) throws -> Snapshot {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return Snapshot(version: 1, scope: account, names: [:]) }
        guard status == errSecSuccess, let data = result as? Data, data.count <= Self.maximumBytes else {
            throw MessagingFailure.protectionUnavailable
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard snapshot.version == 1, snapshot.scope == account, snapshot.names.count <= 128,
              snapshot.names.allSatisfy({ $0.key.count == 64 && MessagingDeviceAliasRules.valid($0.value)
                  && !$0.value.isEmpty && $0.value == MessagingDeviceAliasRules.normalized($0.value) }) else {
            throw MessagingFailure.protectionUnavailable
        }
        return snapshot
    }
    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
}
