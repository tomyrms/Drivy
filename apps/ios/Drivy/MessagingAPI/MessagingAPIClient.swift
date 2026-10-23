import Foundation

/// Formes d'échange proposées, non canoniques tant que #69/#70 et OpenAPI ne les fixent pas.
/// L'adaptateur HTTP est injecté afin de ne pas inventer des chemins ou activer un service réel.
struct MessagingConversationDTO: Sendable {
    let id: UUID
    let schoolId: UUID
    let kind: String
    let title: String
    let identityDetail: String?
    let unreadCount: Int?
    let lastSequence: Int
    let lastReadSequence: Int
    let mutedUntil: Date?
    let readStateVersion: Int
}

struct MessagingMessageDTO: Sendable {
    let id: UUID
    let conversationId: UUID
    let schoolId: UUID
    let senderId: UUID
    let acceptedAt: Date
    let ciphertext: MessagingCiphertext?
    var meta = MessagingMessageMeta()
}

struct MessagingPageDTO<Item: Sendable>: Sendable {
    let items: [Item]
    let nextCursor: String?
    var access: MessagingConversationAccess? = nil
    var readReceipts: [MessagingReadReceipt] = []
}

struct MessagingSendDTO: Codable, Sendable {
    let clientMessageId: UUID
    let ciphertext: MessagingCiphertext
    let mentionPersonIds: [UUID]
    var replyToMessageId: UUID? = nil
    var poll: MessagingPollDraftMeta? = nil
}

struct MessagingAcknowledgementDTO: Codable, Sendable {
    let clientMessageId: UUID
    let serverMessageId: UUID
    let conversationId: UUID
    let schoolId: UUID
    let acceptedAt: Date
    let senderId: UUID
}

protocol MessagingAPITransport: Sendable {
    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPageDTO<MessagingConversationDTO>
    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPageDTO<MessagingMessageDTO>
    func send(scope: MessagingScope, conversationID: UUID, body: MessagingSendDTO) async throws -> MessagingAcknowledgementDTO
}

/// Les routes, l'authentification, les limites et le format de date sont délégués à l'adaptateur
/// conforme au contrat canonique futur. Les IDs et curseurs sont contrôlés avant affichage.
struct MessagingAPIClient: MessagingService {
    let transport: any MessagingAPITransport

    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPage<MessagingConversation> {
        let page = try await transport.conversations(scope: scope, cursor: cursor)
        guard page.nextCursor != cursor || cursor == nil,
              page.items.allSatisfy({ $0.schoolId == scope.schoolID && ($0.unreadCount ?? 0) >= 0 && $0.lastSequence >= 0 && $0.lastReadSequence >= 0 && $0.lastReadSequence <= $0.lastSequence && $0.readStateVersion >= 0 && !$0.title.isEmpty }),
              Set(page.items.map(\.id)).count == page.items.count else { throw MessagingFailure.invalidResponse }
        return MessagingPage(items: try page.items.map { item in
            let kind: MessagingConversation.Kind
            switch item.kind {
            case "PRIVATE": kind = .privateExchange
            case "GENERAL": kind = .schoolGeneral
            default: throw MessagingFailure.invalidResponse
            }
            return MessagingConversation(id: item.id, schoolID: item.schoolId, kind: kind,
                title: item.title, identityDetail: item.identityDetail, unreadCount: item.unreadCount,
                lastSequence: item.lastSequence, lastReadSequence: item.lastReadSequence,
                mutedUntil: item.mutedUntil, readStateVersion: item.readStateVersion)
        }, nextCursor: page.nextCursor)
    }

    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPage<MessagingWireMessage> {
        let page = try await transport.messages(scope: scope, conversationID: conversationID, before: before)
        guard page.nextCursor != before || before == nil,
              page.items.allSatisfy({ $0.schoolId == scope.schoolID && $0.conversationId == conversationID
                  && ($0.ciphertext != nil || $0.meta.deletedForEveryone) }),
              Set(page.items.map(\.id)).count == page.items.count else { throw MessagingFailure.invalidResponse }
        // Lecture seule : rien au-delà de la limite n'est accepté, même si le serveur l'envoyait.
        let limit = page.access?.readableUntilSequence
        let items = page.items.filter { limit == nil || $0.meta.sequence <= limit! }
        return MessagingPage(items: items.map {
            MessagingWireMessage(id: $0.id, conversationID: $0.conversationId, schoolID: $0.schoolId,
                senderID: $0.senderId, acceptedAt: $0.acceptedAt, ciphertext: $0.ciphertext, meta: $0.meta)
        }, nextCursor: page.nextCursor, access: page.access, readReceipts: page.readReceipts)
    }

    func send(scope: MessagingScope, pending: MessagingPending) async throws -> MessagingAcknowledgement {
        let ack = try await transport.send(scope: scope, conversationID: pending.conversationID,
            body: MessagingSendDTO(clientMessageId: pending.clientMessageID,
                ciphertext: pending.ciphertext, mentionPersonIds: pending.mentionPersonIDs,
                replyToMessageId: pending.replyToMessageID, poll: pending.poll))
        guard ack.clientMessageId == pending.clientMessageID, ack.conversationId == pending.conversationID,
              ack.schoolId == scope.schoolID, ack.senderId == scope.accountID else { throw MessagingFailure.invalidResponse }
        return MessagingAcknowledgement(clientMessageID: ack.clientMessageId, serverMessageID: ack.serverMessageId,
            conversationID: ack.conversationId, schoolID: ack.schoolId, acceptedAt: ack.acceptedAt,
            senderID: ack.senderId)
    }
}
