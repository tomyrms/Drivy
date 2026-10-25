import Foundation

/// Échec de déchiffrement d'un message, avec la raison du SDK en code fixe (D-NOKEY, D-MEGOLM…).
/// Reste une erreur fermée : aucun contenu n'est produit.
struct MessagingDecryptionFailure: Error, Equatable, Sendable {
    let code: String
}

/// Code court affiché sous une erreur de chiffrement pour la qualification sur appareil (#84).
/// Ne contient jamais d'identifiant, de chemin, de jeton, de contenu ni de message d'erreur libre :
/// uniquement des catégories fixes, des statuts HTTP et des OSStatus numériques.
final class MessagingDiagnostics: @unchecked Sendable {
    static let shared = MessagingDiagnostics()
    private let lock = NSLock()
    private var value: String?

    var last: String? { lock.withLock { value } }
    func record(_ code: String) {
        guard Self.isSafe(code) else { return }
        lock.withLock { value = code }
    }
    /// Ne garde que le premier code d'une tentative : la cause, pas ses conséquences.
    func recordIfEmpty(_ code: String) {
        guard Self.isSafe(code) else { return }
        lock.withLock { if value == nil { value = code } }
    }
    func clear() { lock.withLock { value = nil } }

    /// Texte affiché : message inchangé, puis le code seulement pour une panne de protection ou de service.
    func describe(_ failure: MessagingFailure) -> String {
        guard failure == .protectionUnavailable || failure == .unavailable || failure == .invalidResponse,
              let code = last else { return failure.localizedDescription }
        return "\(failure.localizedDescription)\nCode : \(code)"
    }

    static func isSafe(_ code: String) -> Bool {
        (1...40).contains(code.utf8.count) && code.utf8.allSatisfy {
            ($0 >= 65 && $0 <= 90) || ($0 >= 48 && $0 <= 57) || $0 == 45
        }
    }

    /// Catégorie fixe d'une route du relais : jamais l'identifiant de conversation ou de transaction.
    static func route(_ path: [String]) -> String {
        let joined = path.prefix(3).joined(separator: "/")
        if path.first == "conversations" {
            switch path.count > 2 ? path[2] : "" {
            case "members": return "MEMBERS"
            case "messages": return path.count == 3 ? "SEND" : "MSG"
            default: return "CONV"
            }
        }
        if path.first == "sendToDevice" { return "TODEVICE" }
        switch joined {
        case "crypto/keys/upload": return "UPLOAD"
        case "crypto/keys/query": return "QUERY"
        case "crypto/keys/claim": return "CLAIM"
        case "crypto/keys/device_signing", "crypto/keys/signatures": return "SIGN"
        case "crypto/sync": return "SYNC"
        case "crypto/room_keys/version": return "BKVER"
        case "crypto/room_keys/keys": return "BKKEYS"
        default: return path.count > 1 && path[1] == "sendToDevice" ? "TODEVICE" : "OTHER"
        }
    }

    static func http(_ path: [String], _ status: Int) -> String { "H-\(route(path))-\(status)" }
    static func network(_ path: [String]) -> String { "H-\(route(path))-NET" }
    static func keychain(_ operation: String, _ status: OSStatus) -> String {
        "K-\(operation)-\(status < 0 ? "N\(-Int(status))" : String(status))"
    }

    /// Nom de cas d'une erreur de la bibliothèque native, sans sa charge (qui peut contenir un chemin).
    static func caseName(_ error: any Error) -> String {
        // Seulement l'étiquette du cas (jamais String(describing:), qui peut contenir un chemin).
        guard let label = Mirror(reflecting: error).children.first?.label else { return "X" }
        let clean = String(label.uppercased().unicodeScalars.filter {
            ($0.value >= 65 && $0.value <= 90) || ($0.value >= 48 && $0.value <= 57)
        }.prefix(20).map(Character.init))
        return clean.isEmpty ? "X" : clean
    }
}
