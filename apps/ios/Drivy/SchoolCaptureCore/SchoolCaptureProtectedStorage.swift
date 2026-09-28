import Foundation
import Security

enum SchoolCaptureProtectedStorage {
    static func directory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("SchoolCapture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try ProtectedStorage.protect(directory)
        return directory
    }

    static func loadOrCreateKey(databaseExists: Bool) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ch.drivy.school-capture.database.v1",
            kSecAttrAccount as String: "device-key-v1",
            kSecAttrSynchronizable as String: false
        ]
        func read() -> (OSStatus, Data?) {
            var lookup = query
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &item)
            return (status, item as? Data)
        }
        let (status, existing) = read()
        if status == errSecSuccess, let existing, existing.count == 32 { return existing }
        guard status == errSecItemNotFound, !databaseExists else { throw SchoolCaptureStorageFailure.keyUnavailable }
        var key = Data(count: 32)
        guard key.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }) == errSecSuccess else {
            throw SchoolCaptureStorageFailure.keyUnavailable
        }
        var addition = query
        addition[kSecValueData as String] = key
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let inserted = SecItemAdd(addition as CFDictionary, nil)
        if inserted == errSecSuccess { return key }
        if inserted == errSecDuplicateItem {
            let (retried, other) = read()
            if retried == errSecSuccess, let other, other.count == 32 { return other }
        }
        throw SchoolCaptureStorageFailure.keyUnavailable
    }
}
