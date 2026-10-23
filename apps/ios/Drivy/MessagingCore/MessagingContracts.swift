import Foundation

/// Le contexte est fixé à l'ouverture. Un changement de compte ou d'école exige une nouvelle instance.
struct MessagingScope: Hashable, Sendable {
    let accountID: UUID
    let schoolID: UUID
    let accessEpoch: Int
    let apiBaseURL: String
    init(accountID: UUID, schoolID: UUID, accessEpoch: Int, apiBaseURL: String = "") {
        self.accountID = accountID; self.schoolID = schoolID; self.accessEpoch = accessEpoch; self.apiBaseURL = apiBaseURL
    }
}

struct MessagingPage<Element: Sendable>: Sendable {
    let items: [Element]
    let nextCursor: String?
}

struct MessagingConversation: Identifiable, Sendable {
    enum Kind: Sendable { case privateExchange, schoolGeneral }
    let id: UUID
    let schoolID: UUID
    let kind: Kind
    let title: String
    let identityDetail: String?
    let unreadCount: Int?
    let lastSequence: Int
    let lastReadSequence: Int
    let mutedUntil: Date?
    let readStateVersion: Int
}

struct MessagingCiphertext: Codable, Sendable, Equatable {
    let scheme: String
    let keyID: String
    let payload: Data
    enum CodingKeys: String, CodingKey {
        case scheme, payload
        case keyID = "keyId"
    }
}

struct MessagingWireMessage: Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let schoolID: UUID
    let senderID: UUID
    let acceptedAt: Date
    let ciphertext: MessagingCiphertext
}

struct MessagingAcknowledgement: Sendable {
    let clientMessageID: UUID
    let serverMessageID: UUID
    let conversationID: UUID
    let schoolID: UUID
    let acceptedAt: Date
    let senderID: UUID
}

enum MessagingFailure: Error, LocalizedError, Sendable, Equatable {
    case protectionUnavailable, accessChanged, unavailable, invalidResponse, contextChanged, stateConflict
    var errorDescription: String? {
        switch self {
        case .protectionUnavailable: "La protection des messages est indisponible. Aucun envoi en clair n'a été effectué."
        case .accessChanged: "L'accès à cette conversation a changé."
        case .unavailable: "Messages est momentanément indisponible. Réessaie plus tard."
        case .invalidResponse: "La réponse de Messages est invalide."
        case .contextChanged: "Le compte ou l'école a changé. Recharge Messages."
        case .stateConflict: "Cette conversation a changé sur un autre appareil. Actualise avant de réessayer."
        }
    }
}

/// Fourni par #67 : ne jamais substituer une implémentation qui renvoie les octets en clair.
protocol MessagingCryptography: Sendable {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data
}

/// Implémentation par défaut volontairement inutilisable avant validation de #67.
struct UnavailableMessagingCryptography: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { false }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext { throw MessagingFailure.protectionUnavailable }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data { throw MessagingFailure.protectionUnavailable }
}

/// Une implémentation persistante doit chiffrer brouillons ET file et lier ses clés à scope.
/// Aucune persistance en clair n'est fournie dans ce module.
protocol MessagingProtectedOutbox: Sendable {
    func put(_ entry: MessagingPending, scope: MessagingScope) async throws
    func entries(scope: MessagingScope) async throws -> [MessagingPending]
    func remove(clientMessageID: UUID, scope: MessagingScope) async throws
}

struct MessagingPending: Codable, Sendable {
    let clientMessageID: UUID
    let conversationID: UUID
    let ciphertext: MessagingCiphertext
    let mentionPersonIDs: [UUID]
    init(clientMessageID: UUID, conversationID: UUID, ciphertext: MessagingCiphertext, mentionPersonIDs: [UUID] = []) {
        self.clientMessageID = clientMessageID; self.conversationID = conversationID
        self.ciphertext = ciphertext; self.mentionPersonIDs = mentionPersonIDs
    }
}

protocol MessagingProtectedDrafts: Sendable {
    func loadDraft(conversationID: UUID, scope: MessagingScope) async throws -> String
    func saveDraft(_ text: String, conversationID: UUID, scope: MessagingScope) async throws
}

protocol MessagingService: Sendable {
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation>
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage>
    /// Le serveur doit réautoriser puis dédupliquer clientMessageID lors de chaque tentative.
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement
}

/// Sans contrat #69/#70, aucun appel réseau ni fausse conversation n'est autorisé.
struct UnavailableMessagingService: MessagingService {
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> { throw MessagingFailure.unavailable }
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> { throw MessagingFailure.unavailable }
    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement { throw MessagingFailure.unavailable }
}
