import Foundation

struct MessagingReadState: Sendable {
    let lastReadSequence: Int
    let mutedUntil: Date?
    let version: Int
}

protocol MessagingDirectoryService: Sendable {
    func contacts(scope: MessagingScope) async throws -> [MessagingContact]
    func generalMembers(scope: MessagingScope) async throws -> [MessagingContact]
    func privateConversation(scope: MessagingScope, peerID: UUID) async throws -> UUID
    func generalConversation(scope: MessagingScope) async throws -> UUID
    /// nil mutedUntil sans version = progression seule, silence conservé.
    /// Toute modification du silence exige expectedVersion du serveur.
    func readState(scope: MessagingScope, conversationID: UUID, sequence: Int,
                   mutedUntil: Date?, expectedVersion: Int?) async throws -> MessagingReadState
}

struct UnavailableMessagingDirectory: MessagingDirectoryService {
    func contacts(scope: MessagingScope) async throws -> [MessagingContact] { throw MessagingFailure.unavailable }
    func generalMembers(scope: MessagingScope) async throws -> [MessagingContact] { throw MessagingFailure.unavailable }
    func privateConversation(scope: MessagingScope, peerID: UUID) async throws -> UUID { throw MessagingFailure.unavailable }
    func generalConversation(scope: MessagingScope) async throws -> UUID { throw MessagingFailure.unavailable }
    func readState(scope: MessagingScope, conversationID: UUID, sequence: Int,
                   mutedUntil: Date?, expectedVersion: Int?) async throws -> MessagingReadState { throw MessagingFailure.unavailable }
}

extension MessagingHTTPTransport: MessagingDirectoryService {}
extension MessagingHTTPTransport: MessagingThreadActions {}

/// Réactions proposées. Le serveur n'accepte que cette liste fermée (métadonnée visible).
enum MessagingReactionPalette {
    static let all = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    static func label(_ emoji: String) -> String {
        switch emoji {
        case "👍": "Pouce levé"
        case "❤️": "Cœur"
        case "😂": "Rire"
        case "😮": "Surprise"
        case "😢": "Tristesse"
        case "🙏": "Merci"
        default: emoji
        }
    }
}
