import Foundation

/// Accès à l'historique tel que décidé par le serveur (décision 2 du 23 octobre).
/// Après la fin du lien, lecture seule jusqu'à `readableUntilSequence` inclus.
struct MessagingConversationAccess: Sendable, Equatable {
    let canWrite: Bool
    let readableUntilSequence: Int?
    let isGroupAdmin: Bool
    static let full = MessagingConversationAccess(canWrite: true, readableUntilSequence: nil, isGroupAdmin: false)
    var isReadOnly: Bool { !canWrite }
}

struct MessagingReaction: Sendable, Equatable, Hashable {
    let emoji: String
    let personIDs: [UUID]
}

struct MessagingReadReceipt: Sendable, Equatable {
    let personID: UUID
    let lastReadSequence: Int
}

/// Votes nominatifs et état du sondage, visibles du serveur. Question et libellés restent chiffrés.
struct MessagingPollState: Sendable, Equatable {
    struct Option: Sendable, Equatable { let optionID: String; let voterIDs: [UUID] }
    let allowsMultiple: Bool
    let closed: Bool
    let creatorID: UUID
    let options: [Option]
}

/// Métadonnées visibles du serveur, acceptées par la décision 1.
struct MessagingMessageMeta: Sendable, Equatable {
    var sequence: Int = 0
    var replyToMessageID: UUID? = nil
    var deletedForEveryone = false
    var pinned = false
    var reactions: [MessagingReaction] = []
    var poll: MessagingPollState? = nil
}

/// Contenu clair, encodé AVANT chiffrement par MessagingCryptography. Jamais transmis tel quel.
struct MessagingPlainContent: Codable, Sendable, Equatable {
    struct Poll: Codable, Sendable, Equatable {
        struct Option: Codable, Sendable, Equatable { let id: String; let label: String }
        let question: String
        let options: [Option]
    }
    var text: String?
    var poll: Poll?

    static let version = 2

    func encoded() throws -> Data {
        let data = try JSONEncoder().encode(Envelope(v: Self.version, text: text, poll: poll))
        guard data.count <= 16_384 else { throw MessagingFailure.invalidResponse }
        return data
    }

    /// Les messages v1 sont du texte UTF-8 brut ; ils restent lisibles.
    static func decode(_ bytes: Data) -> MessagingPlainContent? {
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: bytes), envelope.v == version {
            return MessagingPlainContent(text: envelope.text, poll: envelope.poll)
        }
        return String(data: bytes, encoding: .utf8).map { MessagingPlainContent(text: $0) }
    }

    var summary: String {
        if let poll { return "Sondage : \(poll.question)" }
        return text ?? ""
    }

    private struct Envelope: Codable { let v: Int; let text: String?; let poll: Poll? }
}

enum MessagingPollRules {
    static let maxOptions = 12
    static let maxLength = 200

    /// Options vides retirées, doublons refusés, au moins deux options.
    static func validated(question: String, options: [String]) -> MessagingPlainContent.Poll? {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !q.isEmpty, q.count <= maxLength, (2...maxOptions).contains(labels.count),
              labels.allSatisfy({ $0.count <= maxLength }),
              Set(labels.map { $0.lowercased() }).count == labels.count else { return nil }
        return .init(question: q, options: labels.enumerated().map { .init(id: "o\($0.offset + 1)", label: $0.element) })
    }

    /// Choix unique : un nouveau choix remplace l'ancien. Un appui sur le choix courant le retire.
    static func toggled(_ current: Set<String>, option: String, allowsMultiple: Bool) -> Set<String> {
        if current.contains(option) { return current.subtracting([option]) }
        return allowsMultiple ? current.union([option]) : [option]
    }
}

/// Le serveur ne connaît que des indices d'option. Identifiant local : "o1" pour l'indice 0.
enum MessagingPollIndex {
    static func id(_ index: Int) -> String { "o\(index + 1)" }
    static func index(_ id: String) -> Int? {
        guard id.hasPrefix("o"), let n = Int(id.dropFirst()), (1...MessagingPollRules.maxOptions).contains(n) else { return nil }
        return n - 1
    }
}

enum MessagingDeletionScope: String, Sendable { case me, everyone }

/// Droits d'action dérivés des données serveur. L'interface ne fait que masquer : le serveur revalide.
enum MessagingPermissions {
    static func canDeleteForEveryone(senderID: UUID, account: UUID, access: MessagingConversationAccess) -> Bool {
        access.canWrite && (senderID == account || access.isGroupAdmin)
    }
    static func canClosePoll(_ poll: MessagingPollState, account: UUID, access: MessagingConversationAccess) -> Bool {
        access.canWrite && !poll.closed && poll.creatorID == account
    }
    static func canVote(_ poll: MessagingPollState, access: MessagingConversationAccess) -> Bool {
        access.canWrite && !poll.closed
    }
}

/// Membre du général : nom et photo uniquement (décision 2).
struct MessagingMember: Identifiable, Sendable, Hashable {
    let id: UUID
    let displayName: String
    let hasPhoto: Bool
    let isGroupAdmin: Bool
}

/// Élément transmis aux administrateurs de l'école, rechiffré pour eux.
struct MessagingReportItem: Sendable, Equatable {
    let messageID: UUID
    let ciphertext: MessagingCiphertext
}

/// Fourni par l'agent crypto (Olm vers les appareils des administrateurs de l'école).
protocol MessagingReportSealing: Sendable {
    func sealForSchoolAdmins(_ plaintext: Data, scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext
}

struct UnavailableMessagingReportSealing: MessagingReportSealing {
    func sealForSchoolAdmins(_ plaintext: Data, scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        throw MessagingFailure.protectionUnavailable
    }
}

/// Actions de conversation v2. Chaque appel est réautorisé par le serveur.
protocol MessagingThreadActions: Sendable {
    func delete(scope: MessagingScope, conversationID: UUID, messageID: UUID, for deletion: MessagingDeletionScope) async throws
    func setReaction(scope: MessagingScope, conversationID: UUID, messageID: UUID, emoji: String, active: Bool) async throws
    func setPinned(scope: MessagingScope, conversationID: UUID, messageID: UUID, pinned: Bool) async throws
    func vote(scope: MessagingScope, conversationID: UUID, messageID: UUID, optionIDs: [String]) async throws
    func closePoll(scope: MessagingScope, conversationID: UUID, messageID: UUID) async throws
    func setGroupAdmin(scope: MessagingScope, personID: UUID, admin: Bool) async throws
    func removeGeneralMember(scope: MessagingScope, personID: UUID) async throws
    func members(scope: MessagingScope) async throws -> [MessagingMember]
    func report(scope: MessagingScope, conversationID: UUID, clientReportID: UUID, items: [MessagingReportItem]) async throws
}

struct UnavailableMessagingThreadActions: MessagingThreadActions {
    func delete(scope: MessagingScope, conversationID: UUID, messageID: UUID, for deletion: MessagingDeletionScope) async throws { throw MessagingFailure.unavailable }
    func setReaction(scope: MessagingScope, conversationID: UUID, messageID: UUID, emoji: String, active: Bool) async throws { throw MessagingFailure.unavailable }
    func setPinned(scope: MessagingScope, conversationID: UUID, messageID: UUID, pinned: Bool) async throws { throw MessagingFailure.unavailable }
    func vote(scope: MessagingScope, conversationID: UUID, messageID: UUID, optionIDs: [String]) async throws { throw MessagingFailure.unavailable }
    func closePoll(scope: MessagingScope, conversationID: UUID, messageID: UUID) async throws { throw MessagingFailure.unavailable }
    func setGroupAdmin(scope: MessagingScope, personID: UUID, admin: Bool) async throws { throw MessagingFailure.unavailable }
    func removeGeneralMember(scope: MessagingScope, personID: UUID) async throws { throw MessagingFailure.unavailable }
    func members(scope: MessagingScope) async throws -> [MessagingMember] { throw MessagingFailure.unavailable }
    func report(scope: MessagingScope, conversationID: UUID, clientReportID: UUID, items: [MessagingReportItem]) async throws { throw MessagingFailure.unavailable }
}
