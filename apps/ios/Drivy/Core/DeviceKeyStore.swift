import Foundation
import Security

enum DeviceKeyStore {
    // Une clé absente ne doit jamais remplacer celle d’une base existante.
    static func loadOrCreate(databaseExists: Bool) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ch.drivy.g0.local-database",
            kSecAttrAccount as String: "device-key-v1",
            kSecAttrSynchronizable as String: false
        ]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let key = result as? Data, key.count == 32 {
            return key
        }
        guard status == errSecItemNotFound, !databaseExists else { throw SessionError.keyUnavailable }
        var key = Data(count: 32)
        let randomStatus = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw SessionError.keyUnavailable }
        var addition = query
        addition[kSecValueData as String] = key
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else {
            throw SessionError.keyUnavailable
        }
        return key
    }
}

enum ProtectedStorage {
    static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        var directory = base.appendingPathComponent("DrivyG0", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try protect(directory)
        return directory
    }

    static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path)
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }

    static func protectDatabaseFiles(at databaseURL: URL) throws {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) { try protect(url) }
        }
    }
}
