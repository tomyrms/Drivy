import Foundation
import Security
@preconcurrency import AppAuth

enum IdentityFailure: Error, LocalizedError {
    case notConfigured, unavailable, invalidProvider, reauthentication, storage, invalidArchive

    var errorDescription: String? {
        switch self {
        case .notConfigured: "La connexion à l’école n’est pas configurée dans cette version."
        case .unavailable: "La connexion n’a pas abouti. Vérifiez le réseau puis réessayez."
        case .invalidProvider: "La configuration du fournisseur d’identité ne correspond pas à cette application."
        case .reauthentication: "Votre session a expiré. Connectez-vous à nouveau."
        case .storage: "Le Trousseau de cet appareil est inaccessible. Déverrouillez l’appareil puis réessayez."
        case .invalidArchive: "La session enregistrée est illisible. Connectez-vous à nouveau."
        }
    }
}

@MainActor
protocol IdentityVault: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func clear() throws
}

@MainActor
final class KeychainIdentityVault: IdentityVault {
    // Service distinct de la clé SQLCipher locale ; aucune synchronisation iCloud.
    private let service: String
    init(service: String = "ch.drivy.identity.oidc") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "session-v1",
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> Data? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw IdentityFailure.storage }
        return data
    }

    func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw IdentityFailure.storage }
        let item = query.merging(attributes) { _, new in new }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw IdentityFailure.storage }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IdentityFailure.storage }
    }
}

struct StoredIdentity: Codable {
    let version: Int
    let configuration: AppConfiguration
    let state: Data

    @MainActor
    static func encode(_ state: OIDAuthState, configuration: AppConfiguration) throws -> Data {
        let archive = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
        return try JSONEncoder().encode(StoredIdentity(version: 1, configuration: configuration, state: archive))
    }

    @MainActor
    static func decode(_ data: Data, configuration: AppConfiguration) throws -> OIDAuthState {
        let stored: StoredIdentity
        do { stored = try JSONDecoder().decode(StoredIdentity.self, from: data) }
        catch { throw IdentityFailure.invalidArchive }
        guard stored.version == 1, stored.configuration == configuration else { throw IdentityFailure.invalidProvider }
        let state: OIDAuthState?
        do { state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: stored.state) }
        catch { throw IdentityFailure.invalidArchive }
        guard let state, OIDCPolicy.accepts(state, configuration: configuration) else { throw IdentityFailure.invalidProvider }
        return state
    }
}
