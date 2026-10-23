import Foundation

/// Transport réel du contrat #70. Le serveur reste désactivé en dehors du mode synthétique.
/// Aucune transformation des octets chiffrés en texte lisible n'est faite ici.
actor MessagingHTTPTransport: MessagingAPITransport {
    private let baseURL: URL
    private let sendHTTP: any SchoolHTTPTransport
    private let token: @MainActor @Sendable () async throws -> String
    private let invalidate: @MainActor @Sendable (String) async -> Bool
    private let currentScope: @MainActor @Sendable () -> MessagingScope?

    init(baseURL: URL, transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
         token: @escaping @MainActor @Sendable () async throws -> String,
         invalidate: @escaping @MainActor @Sendable (String) async -> Bool,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        self.baseURL = baseURL
        self.sendHTTP = transport
        self.token = token
        self.invalidate = invalidate
        self.currentScope = currentScope
    }

    @MainActor static func using(baseURL: URL, tokenSource: any AccessTokenSource,
                                 transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
                                 currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) -> MessagingHTTPTransport {
        MessagingHTTPTransport(baseURL: baseURL, transport: transport,
            token: { try await tokenSource.accessToken() },
            invalidate: { await tokenSource.invalidateAccessToken($0) }, currentScope: currentScope)
    }

    private struct Wrapper<T: Decodable>: Decodable {
        struct Context: Decodable { let schoolId: UUID; let actorPersonId: UUID; let accessEpoch: Int }
        let data: T
        let context: Context
    }
    private struct Conversations: Decodable {
        struct Item: Decodable {
            let id: UUID; let schoolId: UUID; let kind: String; let title: String
            let lastSequence: Int; let lastReadSequence: Int; let readStateVersion: Int; let mutedUntil: String?
            let peerPersonId: UUID?; let unreadCount: Int
        }
        let items: [Item]
        let nextCursor: UUID?
    }
    private struct Messages: Decodable {
        struct Reaction: Decodable { let emoji: String; let personIds: [UUID] }
        /// Contrat v2 : indices d'option en clair, libellés chiffrés. Index n <-> identifiant local "o(n+1)".
        struct Poll: Decodable {
            struct Vote: Decodable { let optionIndex: Int; let personIds: [UUID] }
            let optionCount: Int; let multiple: Bool; let closed: Bool; let creatorId: UUID; let votes: [Vote]
        }
        struct Item: Decodable {
            let id: UUID; let schoolId: UUID; let conversationId: UUID; let sequence: Int
            let clientMessageId: UUID; let senderId: UUID; let ciphertext: MessagingCiphertext?
            let mentionPersonIds: [UUID]; let acceptedAt: String
            let replyToMessageId: UUID?; let deletedForEveryone: Bool?; let pinned: Bool?
            let reactions: [Reaction]?; let poll: Poll?
        }
        struct Access: Decodable { let canWrite: Bool; let readableUntilSequence: Int?; let isGroupAdmin: Bool? }
        struct Receipt: Decodable { let personId: UUID; let lastReadSequence: Int }
        let items: [Item]
        let nextCursor: String?
        let access: Access?
        let readStates: [Receipt]?
    }
    private typealias MessageReceipt = Messages.Item
    private struct ContactList: Decodable { let contacts: [Contact]; let nextCursor: UUID? }
    private struct Contact: Decodable {
        let personId: UUID; let displayName: String; let hasPhoto: Bool?; let photoVersion: Int?; let isGroupAdmin: Bool?
    }
    private struct MemberList: Decodable { let members: [Contact]; let nextCursor: UUID? }
    private struct ConversationID: Decodable { let conversationId: UUID }
    private struct ReadState: Decodable { let lastReadSequence: Int; let mutedUntil: String?; let readStateVersion: Int }

    func conversations(scope: MessagingScope, cursor: String?) async throws -> MessagingPageDTO<MessagingConversationDTO> {
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let cursor { query.append(URLQueryItem(name: "before", value: cursor)) }
        let data: Conversations = try await request(scope: scope, method: "GET", path: ["conversations"], query: query)
        guard data.items.allSatisfy({ $0.schoolId == scope.schoolID }) else { throw MessagingFailure.invalidResponse }
        return MessagingPageDTO(items: try data.items.map { item in
            MessagingConversationDTO(id: item.id, schoolId: item.schoolId, kind: item.kind,
                title: item.title, identityDetail: nil,
                unreadCount: item.unreadCount, lastSequence: item.lastSequence,
                lastReadSequence: item.lastReadSequence, mutedUntil: try item.mutedUntil.map(date),
                readStateVersion: item.readStateVersion)
        }, nextCursor: data.nextCursor?.uuidString.lowercased())
    }

    func messages(scope: MessagingScope, conversationID: UUID, before: String?) async throws -> MessagingPageDTO<MessagingMessageDTO> {
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let before { query.append(URLQueryItem(name: "cursor", value: before)) }
        let data: Messages = try await request(scope: scope, method: "GET",
            path: ["conversations", conversationID.uuidString, "messages"], query: query)
        guard data.items.allSatisfy({ $0.schoolId == scope.schoolID && $0.conversationId == conversationID }) else {
            throw MessagingFailure.invalidResponse
        }
        return MessagingPageDTO(items: try data.items.map { item in
            let meta = MessagingMessageMeta(sequence: item.sequence, replyToMessageID: item.replyToMessageId,
                deletedForEveryone: item.deletedForEveryone ?? false, pinned: item.pinned ?? false,
                reactions: (item.reactions ?? []).map { MessagingReaction(emoji: $0.emoji, personIDs: $0.personIds) },
                poll: try item.poll.map { poll in
                    guard (2...12).contains(poll.optionCount),
                          poll.votes.allSatisfy({ (0..<poll.optionCount).contains($0.optionIndex) }) else { throw MessagingFailure.invalidResponse }
                    return MessagingPollState(allowsMultiple: poll.multiple, closed: poll.closed, creatorID: poll.creatorId,
                        options: (0..<poll.optionCount).map { index in
                            .init(optionID: MessagingPollIndex.id(index),
                                  voterIDs: poll.votes.filter { $0.optionIndex == index }.flatMap(\.personIds))
                        })
                })
            // Un message supprimé pour tout le monde ne garde aucune enveloppe côté client.
            return MessagingMessageDTO(id: item.id, conversationId: item.conversationId, schoolId: item.schoolId,
                senderId: item.senderId, acceptedAt: try date(item.acceptedAt),
                ciphertext: meta.deletedForEveryone ? nil : item.ciphertext, meta: meta)
        }, nextCursor: data.nextCursor,
           access: data.access.map { MessagingConversationAccess(canWrite: $0.canWrite,
               readableUntilSequence: $0.readableUntilSequence, isGroupAdmin: $0.isGroupAdmin ?? false) },
           readReceipts: (data.readStates ?? []).map { MessagingReadReceipt(personID: $0.personId, lastReadSequence: $0.lastReadSequence) })
    }

    func send(scope: MessagingScope, conversationID: UUID, body: MessagingSendDTO) async throws -> MessagingAcknowledgementDTO {
        let payload = try JSONEncoder().encode(SendBody(clientMessageId: body.clientMessageId,
            ciphertext: body.ciphertext, mentionPersonIds: body.mentionPersonIds,
            replyToMessageId: body.replyToMessageId,
            poll: body.poll.map { SendBody.Poll(optionCount: $0.optionIDs.count, multiple: $0.allowsMultiple) }))
        let receipt: MessageReceipt = try await request(scope: scope, method: "POST",
            path: ["conversations", conversationID.uuidString, "messages"], body: payload)
        guard receipt.clientMessageId == body.clientMessageId, receipt.conversationId == conversationID,
              receipt.schoolId == scope.schoolID, receipt.senderId == scope.accountID,
              receipt.ciphertext == body.ciphertext,
              receipt.mentionPersonIds == body.mentionPersonIds else {
            throw MessagingFailure.invalidResponse
        }
        return MessagingAcknowledgementDTO(clientMessageId: receipt.clientMessageId, serverMessageId: receipt.id,
            conversationId: receipt.conversationId, schoolId: receipt.schoolId, acceptedAt: try date(receipt.acceptedAt),
            senderId: receipt.senderId)
    }
    private struct SendBody: Encodable {
        struct Poll: Encodable { let optionCount: Int; let multiple: Bool }
        let clientMessageId: UUID
        let ciphertext: MessagingCiphertext
        let mentionPersonIds: [UUID]
        let replyToMessageId: UUID?
        let poll: Poll?
    }

    func contacts(scope: MessagingScope) async throws -> [MessagingContact] {
        var cursor: UUID?
        var contacts: [MessagingContact] = []
        repeat {
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor.uuidString)) }
            let result: ContactList = try await request(scope: scope, method: "GET", path: ["contacts"], query: query)
            guard (cursor == nil || result.nextCursor != cursor), contacts.count + result.contacts.count <= 2_000 else { throw MessagingFailure.invalidResponse }
            contacts += result.contacts.map { MessagingContact(id: $0.personId, displayName: $0.displayName) }
            cursor = result.nextCursor
        } while cursor != nil
        guard Set(contacts.map(\.id)).count == contacts.count else { throw MessagingFailure.invalidResponse }
        return contacts
    }

    func generalMembers(scope: MessagingScope) async throws -> [MessagingContact] {
        var cursor: UUID?
        var members: [MessagingContact] = []
        repeat {
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor.uuidString)) }
            let result: MemberList = try await request(scope: scope, method: "GET", path: ["general", "members"], query: query)
            guard (cursor == nil || result.nextCursor != cursor), members.count + result.members.count <= 2_000 else { throw MessagingFailure.invalidResponse }
            members += result.members.map { MessagingContact(id: $0.personId, displayName: $0.displayName) }
            cursor = result.nextCursor
        } while cursor != nil
        guard Set(members.map(\.id)).count == members.count else { throw MessagingFailure.invalidResponse }
        return members
    }

    func privateConversation(scope: MessagingScope, peerID: UUID) async throws -> UUID {
        let result: ConversationID = try await request(scope: scope, method: "PUT", path: ["private", peerID.uuidString])
        return result.conversationId
    }

    func generalConversation(scope: MessagingScope) async throws -> UUID {
        let result: ConversationID = try await request(scope: scope, method: "PUT", path: ["general"])
        return result.conversationId
    }

    func readState(scope: MessagingScope, conversationID: UUID, sequence: Int,
                   mutedUntil: Date?, expectedVersion: Int?) async throws -> MessagingReadState {
        guard sequence >= 0, (expectedVersion ?? 0) >= 0,
              mutedUntil == nil || expectedVersion != nil else {
            throw MessagingFailure.invalidResponse
        }
        let body = try JSONEncoder().encode(ReadBody(lastReadSequence: sequence,
            mutedUntil: mutedUntil.map { ISO8601DateFormatter().string(from: $0) }, expectedVersion: expectedVersion))
        let result: ReadState = try await request(scope: scope, method: "PUT",
            path: ["conversations", conversationID.uuidString, "read-state"], body: body)
        guard result.lastReadSequence >= sequence, result.readStateVersion >= 1 else { throw MessagingFailure.invalidResponse }
        return MessagingReadState(lastReadSequence: result.lastReadSequence,
            mutedUntil: try result.mutedUntil.map(date), version: result.readStateVersion)
    }
    private struct ReadBody: Encodable {
        let lastReadSequence: Int
        let mutedUntil: String?
        let expectedVersion: Int?

        private enum CodingKeys: String, CodingKey { case lastReadSequence, mutedUntil, expectedVersion }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(lastReadSequence, forKey: .lastReadSequence)
            if let expectedVersion {
                try container.encode(expectedVersion, forKey: .expectedVersion)
                // Présent avec null = lever la sourdine. Absent = préserver la sourdine en marquant lu.
                try container.encode(mutedUntil, forKey: .mutedUntil)
            }
        }
    }

    private func date(_ text: String) throws -> Date {
        let withFraction = ISO8601DateFormatter(); withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        guard let value = withFraction.date(from: text) ?? withoutFraction.date(from: text) else { throw MessagingFailure.invalidResponse }
        return value
    }

    private func request<T: Decodable>(scope: MessagingScope, method: String, path: [String],
                                        query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        guard scope.apiBaseURL == baseURL.absoluteString, await DrivyAPIClient.permits(baseURL),
              let origin = baseURL.host else { throw MessagingFailure.contextChanged }
        try await verifyCurrent(scope)
        var url = baseURL
        for part in ["v1", "schools", scope.schoolID.uuidString, "messaging"] + path { url.appendPathComponent(part) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw MessagingFailure.invalidResponse }
        components.queryItems = query.isEmpty ? nil : query
        guard let target = components.url, target.host == origin else { throw MessagingFailure.invalidResponse }
        var bearer = try await token()
        try await verifyCurrent(scope)
        for attempt in 0...1 {
            guard !bearer.isEmpty, bearer.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw MessagingFailure.accessChanged }
            try await verifyCurrent(scope)
            var request = URLRequest(url: target)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue(scope.accountID.uuidString.lowercased(), forHTTPHeaderField: "X-Drivy-Expected-Person-Id")
            request.setValue(String(scope.accessEpoch), forHTTPHeaderField: "X-Drivy-Expected-Access-Epoch")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let response: SchoolHTTPResponse
            do { response = try await sendHTTP.send(request) }
            catch { throw error.unlessCancelled(MessagingFailure.unavailable) }
            try Task.checkCancellation()
            try await verifyCurrent(scope)
            guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw MessagingFailure.invalidResponse }
            if response.status == 401 && attempt == 0 {
                if await invalidate(bearer) { bearer = try await token(); continue }
            }
            if response.status == 409 { throw MessagingFailure.stateConflict }
            if response.status == 404 { throw MessagingFailure.conversationUnavailable }
            if response.status == 401 || response.status == 403 { throw MessagingFailure.accessChanged }
            guard (200...299).contains(response.status) else { throw MessagingFailure.unavailable }
            guard response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else { throw MessagingFailure.invalidResponse }
            do {
                let wrapped = try JSONDecoder().decode(Wrapper<T>.self, from: response.data)
                guard wrapped.context.schoolId == scope.schoolID,
                      wrapped.context.actorPersonId == scope.accountID,
                      wrapped.context.accessEpoch == scope.accessEpoch else { throw MessagingFailure.contextChanged }
                return wrapped.data
            } catch let failure as MessagingFailure { throw failure }
            catch { throw MessagingFailure.invalidResponse }
        }
        throw MessagingFailure.accessChanged
    }

    // MARK: Actions v2 (docs/implementation/messaging-api-v2.md)

    /// Toute réponse `data` objet est acceptée : seul le statut et le contexte comptent.
    private struct Done: Decodable {}

    private func message(_ conversationID: UUID, _ messageID: UUID, _ tail: String...) -> [String] {
        ["conversations", conversationID.uuidString, "messages", messageID.uuidString] + tail
    }

    func delete(scope: MessagingScope, conversationID: UUID, messageID: UUID, for deletion: MessagingDeletionScope) async throws {
        let _: Done = try await request(scope: scope, method: "DELETE", path: message(conversationID, messageID),
                                        query: [URLQueryItem(name: "scope", value: deletion.rawValue)])
    }

    func setReaction(scope: MessagingScope, conversationID: UUID, messageID: UUID, emoji: String, active: Bool) async throws {
        guard MessagingReactionPalette.all.contains(emoji) else { throw MessagingFailure.invalidResponse }
        let _: Done = try await request(scope: scope, method: active ? "PUT" : "DELETE",
                                        path: message(conversationID, messageID, "reactions", emoji))
    }

    func setPinned(scope: MessagingScope, conversationID: UUID, messageID: UUID, pinned: Bool) async throws {
        let _: Done = try await request(scope: scope, method: pinned ? "PUT" : "DELETE", path: message(conversationID, messageID, "pin"))
    }

    func vote(scope: MessagingScope, conversationID: UUID, messageID: UUID, optionIDs: [String]) async throws {
        struct Body: Encodable { let optionIndexes: [Int] }
        let indexes = try optionIDs.map { id -> Int in
            guard let index = MessagingPollIndex.index(id) else { throw MessagingFailure.invalidResponse }
            return index
        }
        let _: Done = try await request(scope: scope, method: "PUT", path: message(conversationID, messageID, "poll", "votes"),
                                        body: try JSONEncoder().encode(Body(optionIndexes: indexes.sorted())))
    }

    func closePoll(scope: MessagingScope, conversationID: UUID, messageID: UUID) async throws {
        let _: Done = try await request(scope: scope, method: "POST", path: message(conversationID, messageID, "poll", "close"))
    }

    func setGroupAdmin(scope: MessagingScope, personID: UUID, admin: Bool) async throws {
        let _: Done = try await request(scope: scope, method: admin ? "PUT" : "DELETE", path: ["general", "admins", personID.uuidString])
    }

    func removeGeneralMember(scope: MessagingScope, personID: UUID) async throws {
        let _: Done = try await request(scope: scope, method: "DELETE", path: ["general", "members", personID.uuidString])
    }

    func members(scope: MessagingScope) async throws -> [MessagingMember] {
        var cursor: UUID?
        var members: [MessagingMember] = []
        repeat {
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor.uuidString)) }
            let result: MemberList = try await request(scope: scope, method: "GET", path: ["general", "members"], query: query)
            guard (cursor == nil || result.nextCursor != cursor), members.count + result.members.count <= 2_000 else { throw MessagingFailure.invalidResponse }
            members += result.members.map { MessagingMember(id: $0.personId, displayName: $0.displayName,
                hasPhoto: ($0.hasPhoto ?? false) || $0.photoVersion != nil, isGroupAdmin: $0.isGroupAdmin ?? false) }
            cursor = result.nextCursor
        } while cursor != nil
        guard Set(members.map(\.id)).count == members.count else { throw MessagingFailure.invalidResponse }
        return members
    }

    func report(scope: MessagingScope, conversationID: UUID, clientReportID: UUID, items: [MessagingReportItem]) async throws {
        struct Item: Encodable { let messageId: UUID; let ciphertext: MessagingCiphertext }
        struct Body: Encodable { let clientReportId: UUID; let conversationId: UUID; let items: [Item] }
        guard (1...50).contains(items.count) else { throw MessagingFailure.invalidResponse }
        let body = try JSONEncoder().encode(Body(clientReportId: clientReportID, conversationId: conversationID,
            items: items.map { Item(messageId: $0.messageID, ciphertext: $0.ciphertext) }))
        let _: Done = try await request(scope: scope, method: "POST", path: ["reports"], body: body)
    }

    private func verifyCurrent(_ scope: MessagingScope) async throws {
        guard await currentScope() == scope else { throw MessagingFailure.contextChanged }
    }
}

struct MessagingContact: Identifiable, Sendable, Hashable {
    let id: UUID
    let displayName: String
}
