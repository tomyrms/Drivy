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
    /// Fourni avec les messages : lecture seule après la fin du lien, rôle d'administrateur du groupe.
    var access: MessagingConversationAccess? = nil
    var readReceipts: [MessagingReadReceipt] = []
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
    /// Pair d'un échange privé (photo de la cellule), nil pour le général.
    var peerPersonID: UUID? = nil
}

struct MessagingCiphertext: Codable, Sendable, Equatable {
    let scheme: String
    let keyID: String
    let payload: Data
    /// Époque lue pour CE chiffrement. Métadonnée locale durable, jamais remplacée au retry.
    /// nil conserve la lecture des anciennes files et permet de résoudre un envoi déjà accepté.
    let expectedMembersEpoch: Int?
    init(scheme: String, keyID: String, payload: Data, expectedMembersEpoch: Int? = nil) {
        self.scheme = scheme; self.keyID = keyID; self.payload = payload
        self.expectedMembersEpoch = expectedMembersEpoch
    }
    enum CodingKeys: String, CodingKey {
        case scheme, payload, expectedMembersEpoch
        case keyID = "keyId"
    }
}

struct MessagingWireMessage: Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let schoolID: UUID
    let senderID: UUID
    let acceptedAt: Date
    /// nil uniquement pour un message supprimé pour tout le monde.
    let ciphertext: MessagingCiphertext?
    var meta = MessagingMessageMeta()
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
    case protectionUnavailable, accessChanged, conversationUnavailable, unavailable, invalidResponse, contextChanged, stateConflict, deviceLimitReached, membersChanged
    /// Clé de récupération mal formée, étrangère à la sauvegarde ou sauvegarde absente : volontairement indistincts.
    case recoveryKeyRefused
    case mutationReceiptUnavailable
    /// Signalement : aucun administrateur de l'école n'a d'appareil joignable, ou la cadence autorisée est atteinte (#77).
    case noReportRecipient, reportRateLimited
    var errorDescription: String? {
        switch self {
        case .protectionUnavailable: "La protection des messages est indisponible. Aucun envoi en clair n'a été effectué."
        case .accessChanged: "L'accès à cette conversation a changé."
        case .conversationUnavailable: "Cette conversation n'est plus accessible. Les autres messages en attente sont conservés."
        case .unavailable: "Messages est momentanément indisponible. Réessaie plus tard."
        case .invalidResponse: "La réponse de Messages est invalide."
        case .contextChanged: "Le compte ou l'école a changé. Recharge Messages."
        case .stateConflict: "Cette conversation a changé sur un autre appareil. Actualise avant de réessayer."
        case .deviceLimitReached: "Trop d'appareils utilisent Messages sur ce compte. Retire un appareil puis réessaie. Rien n'a été envoyé."
        case .membersChanged: "Les participants ont changé. Ce message n'a pas été envoyé et reste conservé sur cet appareil."
        case .recoveryKeyRefused: "Clé de récupération refusée. Rien n'a été modifié."
        case .mutationReceiptUnavailable: "Le service doit être mis à jour pour confirmer ces modifications. Tes choix restent conservés."
        case .noReportRecipient: "Aucun administrateur de l'école n'est joignable pour recevoir ce signalement. Rien n'a été envoyé."
        case .reportRateLimited: "Trop de signalements envoyés récemment. Réessaie plus tard : le tien reste conservé sur cet appareil."
        }
    }
}

/// Fourni par #67 : ne jamais substituer une implémentation qui renvoie les octets en clair.
protocol MessagingCryptography: Sendable {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data
    /// Megolm authentifie l'expéditeur : préférer cette forme qui transmet l'enveloppe complète.
    func decrypt(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> Data
    /// Raison précise de l'indisponibilité, `nil` si la protection est prête.
    func availabilityFailure(scope: MessagingScope, conversationID: UUID) async -> MessagingFailure?
}

extension MessagingCryptography {
    func decrypt(_ message: MessagingWireMessage, scope: MessagingScope) async throws -> Data {
        guard let ciphertext = message.ciphertext else { throw MessagingFailure.protectionUnavailable }
        return try await decrypt(ciphertext, scope: scope, conversationID: message.conversationID)
    }

    func availabilityFailure(scope: MessagingScope, conversationID: UUID) async -> MessagingFailure? {
        await isAvailable(scope: scope, conversationID: conversationID) ? nil : .protectionUnavailable
    }
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
    let replyToMessageID: UUID?
    let poll: MessagingPollDraftMeta?
    /// Contenu original pour une recomposition volontaire. Uniquement dans le snapshot scellé,
    /// jamais transmis au serveur ni utilisé pour rechiffrer automatiquement une intention.
    let recoveryContent: Data?
    init(clientMessageID: UUID, conversationID: UUID, ciphertext: MessagingCiphertext, mentionPersonIDs: [UUID] = [],
         replyToMessageID: UUID? = nil, poll: MessagingPollDraftMeta? = nil, recoveryContent: Data? = nil) {
        self.clientMessageID = clientMessageID; self.conversationID = conversationID
        self.ciphertext = ciphertext; self.mentionPersonIDs = mentionPersonIDs
        self.replyToMessageID = replyToMessageID; self.poll = poll
        self.recoveryContent = recoveryContent
    }
    // Les entrées v1 scellées n'ont pas ces clés : decodeIfPresent les garde lisibles.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientMessageID = try c.decode(UUID.self, forKey: .clientMessageID)
        conversationID = try c.decode(UUID.self, forKey: .conversationID)
        ciphertext = try c.decode(MessagingCiphertext.self, forKey: .ciphertext)
        mentionPersonIDs = try c.decodeIfPresent([UUID].self, forKey: .mentionPersonIDs) ?? []
        replyToMessageID = try c.decodeIfPresent(UUID.self, forKey: .replyToMessageID)
        poll = try c.decodeIfPresent(MessagingPollDraftMeta.self, forKey: .poll)
        recoveryContent = try c.decodeIfPresent(Data.self, forKey: .recoveryContent)
    }
}

/// Partie visible du serveur d'un sondage à créer : identifiants d'options et mode de choix.
struct MessagingPollDraftMeta: Codable, Sendable, Equatable {
    let allowsMultiple: Bool
    let optionIDs: [String]
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
