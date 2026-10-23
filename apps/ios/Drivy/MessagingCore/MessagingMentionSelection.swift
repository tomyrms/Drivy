import Foundation

/// Sélection de participant du général par identité stable, jamais par texte du nom.
struct MessagingMentionSelection: Hashable, Sendable {
    let personID: UUID
    let displayName: String
}
