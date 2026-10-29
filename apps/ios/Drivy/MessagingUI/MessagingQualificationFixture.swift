#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// UI-only fixture. Never creates an identity, opens a socket or persists data.
/// Uses the real views and HTTP decoder, but does not qualify server rights or E2EE.
/// `-messaging-ui-rich` adds synthetic conversations and messages (in memory only).
@MainActor
struct MessagingQualificationFixture: View {
    @State private var workspace: MessagingWorkspace
    private let keys = MessagingQualificationKeys()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                   apiBaseURL: "https://messaging-ui.example.invalid/")
        let rich = arguments.contains("-messaging-ui-rich")
        let seed = rich ? MessagingQualificationHTTP.seed(me: scope.accountID) : []
        let transport = MessagingQualificationHTTP(scope: scope,
            readOnly: arguments.contains("-messaging-ui-readonly"), rich: rich, seed: seed)
        let http = MessagingHTTPTransport(baseURL: URL(string: scope.apiBaseURL)!, transport: transport,
            token: { "synthetic-ui-only" }, invalidate: { _ in false }, currentScope: { scope })
        let memory = MessagingQualificationMemory()
        // Decrypt-only: encrypt always throws, so the UI can never report a false successful send.
        _workspace = State(initialValue: MessagingWorkspace(scope: scope,
            service: MessagingAPIClient(transport: http), cryptography: MessagingQualificationCrypto(),
            outbox: memory, drafts: memory, directory: http, actions: http,
            history: MessagingQualificationHistory(seed: seed), mutations: memory, notifications: MessagingQualificationNotifications(),
            currentScope: { scope }))
    }

    var body: some View {
        SchoolMessagingEntryButton()
            .environment(\.schoolMessagingEntry, SchoolMessagingEntry(scopeID: "synthetic-ui-only", makeView: { _ in
                AnyView(MessagingInboxView(workspace: workspace, keys: keys, currentScope: { [scope = workspace.scope] in scope }))
            }))
            .environment(\.locale, Locale(identifier: "fr_CH"))
    }
}

/// Synthetic identifiers, stable so UI tests can address rows.
enum MessagingQualificationIDs {
    static let general = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    static let lea = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
    static let marc = UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!
    static let leaPerson = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    static let marcPerson = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!
    static let ciphertextScheme = "drivy.ui-fixture.decrypt-only"

    static func message(_ conversation: Int, _ sequence: Int) -> UUID {
        let tail = String(sequence, radix: 16, uppercase: true)
        return UUID(uuidString: "B000000\(conversation)-0000-4000-8000-" + String(repeating: "0", count: 12 - tail.count) + tail)!
    }
}

private struct FixtureMessage: Sendable {
    let id: UUID
    let sequence: Int
    let sender: UUID
    let date: Date
    var text: String? = nil
    var poll: MessagingPlainContent.Poll? = nil
    var pollVotes: [[UUID]] = []
    var replyTo: UUID? = nil
}

private struct FixtureConversation: Sendable {
    let id: UUID
    let kind: String
    let title: String
    let peer: UUID?
    let messages: [FixtureMessage]
    var lastRead: Int
    var version = 1
    var lastSequence: Int { messages.map(\.sequence).max() ?? 0 }
}

private actor MessagingQualificationHTTP: SchoolHTTPTransport {
    let scope: MessagingScope
    let readOnly: Bool
    let rich: Bool
    let conversation: UUID
    let member: UUID
    private var removed = false
    private var conversations: [FixtureConversation] = []
    private var reactions: [UUID: [String: [UUID]]] = [:]
    private var pinned: Set<UUID> = []
    private var mutationReceipts: [UUID: (request: URLRequest, response: SchoolHTTPResponse)] = [:]
    private let mutationDelay: Int
    private let refuseMutation: Bool
    private let denyMutationAccess: Bool
    /// General page 1 holds sequences 24...9, page 2 holds 8...1.
    private static let generalPageCursor = "fixture-page-2"
    private static let generalPageFloor = 9

    init(scope: MessagingScope, readOnly: Bool, rich: Bool, seed: [FixtureConversation]) {
        self.scope = scope; self.readOnly = readOnly; self.rich = rich
        let arguments = ProcessInfo.processInfo.arguments
        let delay = arguments.first { $0.hasPrefix("-messaging-ui-mutation-delay=") }
            .flatMap { Int($0.dropFirst("-messaging-ui-mutation-delay=".count)) } ?? 0
        mutationDelay = [1, 5, 15].contains(delay) ? delay : 0
        refuseMutation = arguments.contains("-messaging-ui-mutation-refused")
        denyMutationAccess = arguments.contains("-messaging-ui-mutation-access-denied")
        conversation = rich ? MessagingQualificationIDs.general : UUID()
        member = rich ? MessagingQualificationIDs.leaPerson : UUID()
        guard rich else { return }
        conversations = seed
        reactions[MessagingQualificationIDs.message(1, 21)] = ["👍": [MessagingQualificationIDs.leaPerson, scope.accountID],
                                                              "😂": [MessagingQualificationIDs.marcPerson]]
        pinned = [MessagingQualificationIDs.message(1, 20)]
        if arguments.contains("-messaging-ui-two-pins") { pinned.insert(MessagingQualificationIDs.message(1, 24)) }
    }

    /// Synthetic conversations shared by the HTTP fixture and the in-memory history (inbox previews).
    static func seed(me: UUID) -> [FixtureConversation] {
        let lea = MessagingQualificationIDs.leaPerson, marc = MessagingQualificationIDs.marcPerson
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func at(_ daysAgo: Int, _ minutes: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(TimeInterval(8 * 3600 + minutes * 60))
        }
        var general: [FixtureMessage] = []
        for seq in 1...24 {
            let sender = [lea, marc, me][seq % 3]
            let day = seq <= 8 ? 3 : (seq <= 16 ? 1 : 0)
            general.append(FixtureMessage(id: MessagingQualificationIDs.message(1, seq), sequence: seq,
                sender: sender, date: at(day, seq * 7), text: "Message \(seq) du général"))
        }
        func set(_ seq: Int, _ change: (inout FixtureMessage) -> Void) { change(&general[seq - 1]) }
        set(1) { $0.text = "Premier message du général" }
        set(9) { $0.text = "Bonjour à tous, nouvelle semaine" }
        set(20) { $0.text = "Pensez aux papiers du permis" }
        set(21) { $0.text = "Leçon de conduite confirmée" }
        set(22) {
            $0.text = nil
            $0.poll = .init(question: "Créneau du code ?", options: [.init(id: "o1", label: "Lundi"), .init(id: "o2", label: "Mardi")])
            $0.pollVotes = [[lea], [marc]]
        }
        set(23) { $0.text = "Merci, je les apporte"; $0.replyTo = MessagingQualificationIDs.message(1, 20) }
        set(24) { $0.text = "Rendez-vous à 14 h devant l'auto-école" }
        return [
            FixtureConversation(id: MessagingQualificationIDs.general, kind: "GENERAL", title: "Général", peer: nil,
                                messages: general, lastRead: 21),
            FixtureConversation(id: MessagingQualificationIDs.lea, kind: "PRIVATE", title: "Léa Fixture", peer: lea,
                messages: (1...6).map { seq in
                    FixtureMessage(id: MessagingQualificationIDs.message(2, seq), sequence: seq, sender: seq % 2 == 0 ? lea : me,
                                   date: at(seq <= 3 ? 1 : 0, 60 + seq * 5),
                                   text: seq == 6 ? "À demain pour la leçon" : "Échange privé \(seq)")
                }, lastRead: 4),
            FixtureConversation(id: MessagingQualificationIDs.marc, kind: "PRIVATE", title: "Marc Fixture", peer: marc,
                messages: (1...3).map { seq in
                    FixtureMessage(id: MessagingQualificationIDs.message(3, seq), sequence: seq, sender: seq == 3 ? marc : me,
                                   date: at(2, 30 + seq * 5),
                                   text: seq == 3 ? "Je décale mon examen" : "Question de Marc \(seq)")
                }, lastRead: 2),
        ]
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "messaging-ui.example.invalid" else {
            throw MessagingFailure.invalidResponse
        }
        let path = url.path.lowercased()
        let parts = url.pathComponents.map { $0.lowercased() }
        let method = request.httpMethod ?? "GET"
        let requestID = request.value(forHTTPHeaderField: "Idempotency-Key").flatMap(UUID.init(uuidString:))
        if parts.count >= 2, parts[parts.count - 2] == "reactions", method == "PUT" || method == "DELETE" {
            if mutationDelay > 0 { try await Task.sleep(for: .seconds(mutationDelay)) }
            if refuseMutation || denyMutationAccess {
                return SchoolHTTPResponse(data: Data("{\"code\":\"MESSAGING_MUTATION_CONFLICT\"}".utf8),
                    status: denyMutationAccess ? 403 : 409, url: url, contentType: "application/json")
            }
        }
        if let requestID, let previous = mutationReceipts[requestID] {
            guard previous.request.url == request.url, previous.request.httpMethod == request.httpMethod,
                  previous.request.httpBody == request.httpBody else { throw MessagingFailure.stateConflict }
            return previous.response
        }
        let other = #"{"personId":"\#(member)","displayName":"Léa Fixture","hasPhoto":false,"isGroupAdmin":false}"#
        let marc = #"{"personId":"\#(MessagingQualificationIDs.marcPerson)","displayName":"Marc Fixture","hasPhoto":false,"isGroupAdmin":false}"#
        let admin = #"{"personId":"\#(scope.accountID)","displayName":"Admin Fixture","hasPhoto":false,"isGroupAdmin":true}"#
        let data: String
        if path.hasSuffix("/contacts"), method == "GET" {
            data = rich
                ? #"{"contacts":[{"personId":"\#(member)","displayName":"Léa Fixture"},{"personId":"\#(MessagingQualificationIDs.marcPerson)","displayName":"Marc Fixture"}],"nextCursor":null}"#
                : #"{"contacts":[],"nextCursor":null}"#
        } else if path.hasSuffix("/general/members"), method == "GET" {
            data = #"{"members":[\#(admin)\#(removed ? "" : "," + other)\#(rich ? "," + marc : "")],"nextCursor":null}"#
        } else if path.hasSuffix("/general/removed-members"), method == "GET" {
            data = #"{"members":[\#(removed ? other : "")],"nextCursor":null}"#
        } else if path.hasSuffix("/general/members/" + member.uuidString.lowercased()), method == "DELETE" || method == "PUT" {
            removed = method == "DELETE"
            data = #"{"done":true}"#
        } else if path.hasSuffix("/general"), method == "PUT" {
            data = #"{"conversationId":"\#(conversation)"}"#
        } else if path.hasSuffix("/conversations"), method == "GET" {
            data = rich ? try conversationList() : #"{"items":[],"nextCursor":null}"#
        } else if path.hasSuffix("/messages"), method == "GET" {
            if rich, let id = uuid(after: "conversations", in: parts) {
                let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "cursor" }?.value
                data = try messagePage(id, cursor: cursor)
            } else {
                data = #"{"items":[],"nextCursor":null,"access":{"canWrite":\#(!readOnly),"readableUntilSequence":\#(readOnly ? "0" : "null"),"isGroupAdmin":true},"readStates":[]}"#
            }
        } else if rich, path.hasSuffix("/read-state"), method == "PUT", let id = uuid(after: "conversations", in: parts) {
            data = try readState(id, body: request.httpBody)
        } else if rich, parts.count >= 2, parts[parts.count - 2] == "reactions", method == "PUT" || method == "DELETE",
                  let messageID = uuid(after: "messages", in: parts) {
            let emoji = url.lastPathComponent
            var current = reactions[messageID] ?? [:]
            var people = current[emoji] ?? []
            people.removeAll { $0 == scope.accountID }
            if method == "PUT" { people.append(scope.accountID) }
            current[emoji] = people.isEmpty ? nil : people
            reactions[messageID] = current
            data = #"{"done":true}"#
        } else if rich, path.hasSuffix("/pin"), method == "PUT" || method == "DELETE",
                  let messageID = uuid(after: "messages", in: parts) {
            if method == "PUT" { pinned.insert(messageID) } else { pinned.remove(messageID) }
            data = #"{"done":true}"#
        } else {
            // Unspecified mutations (message send included) must fail rather than manufacture acceptance.
            throw MessagingFailure.unavailable
        }
        let receipt = requestID.map { #", "mutationReceipt":{"operationId":"\#($0)"}"# } ?? ""
        let body = #"{"data":\#(data),"context":{"schoolId":"\#(scope.schoolID)","actorPersonId":"\#(scope.accountID)","accessEpoch":1}\#(receipt)}"#
        let response = SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: url, contentType: "application/json")
        if let requestID { mutationReceipts[requestID] = (request, response) }
        return response
    }

    private func uuid(after marker: String, in parts: [String]) -> UUID? {
        guard let index = parts.firstIndex(of: marker), index + 1 < parts.count else { return nil }
        return UUID(uuidString: parts[index + 1])
    }

    private func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    private func conversationList() throws -> String {
        let items: [[String: Any]] = conversations.map { item in
            let unread = item.messages.filter { $0.sequence > item.lastRead && $0.sender != scope.accountID }.count
            var row: [String: Any] = ["id": item.id.uuidString.lowercased(), "schoolId": scope.schoolID.uuidString.lowercased(),
                "kind": item.kind, "title": item.title, "lastSequence": item.lastSequence,
                "lastReadSequence": item.lastRead, "readStateVersion": item.version,
                "mutedUntil": NSNull(), "unreadCount": unread]
            row["peerPersonId"] = item.peer.map { $0.uuidString.lowercased() as Any } ?? NSNull()
            return row
        }
        return try json(["items": items, "nextCursor": NSNull()])
    }

    private func messagePage(_ id: UUID, cursor: String?) throws -> String {
        guard let item = conversations.first(where: { $0.id == id }) else { throw MessagingFailure.conversationUnavailable }
        var selected = item.messages
        var next: Any = NSNull()
        if id == MessagingQualificationIDs.general {
            if cursor == Self.generalPageCursor {
                selected = selected.filter { $0.sequence < Self.generalPageFloor }
            } else {
                selected = selected.filter { $0.sequence >= Self.generalPageFloor }
                next = Self.generalPageCursor
            }
        }
        let formatter = ISO8601DateFormatter()
        let items: [[String: Any]] = selected.sorted { $0.sequence > $1.sequence }.map { message in
            let content = MessagingPlainContent(text: message.text, poll: message.poll)
            let payload = (try? content.encoded()) ?? Data()
            let ciphertext: [String: String] = ["scheme": MessagingQualificationIDs.ciphertextScheme, "keyId": "fixture",
                                                "payload": payload.base64EncodedString()]
            let reactionRows: [[String: Any]] = MessagingReactionPalette.all.compactMap { emoji in
                guard let people = reactions[message.id]?[emoji], !people.isEmpty else { return nil }
                return ["emoji": emoji, "personIds": people.map { $0.uuidString.lowercased() }]
            }
            var row: [String: Any] = [
                "id": message.id.uuidString.lowercased(), "schoolId": scope.schoolID.uuidString.lowercased(),
                "conversationId": id.uuidString.lowercased(), "sequence": message.sequence,
                "clientMessageId": message.id.uuidString.lowercased(), "senderId": message.sender.uuidString.lowercased(),
                "ciphertext": ciphertext,
                "mentionPersonIds": [String](), "acceptedAt": formatter.string(from: message.date),
                "pinned": pinned.contains(message.id), "reactions": reactionRows,
            ]
            row["replyToMessageId"] = message.replyTo.map { $0.uuidString.lowercased() as Any } ?? NSNull()
            if message.poll != nil {
                let votes: [[String: Any]] = message.pollVotes.enumerated().map { index, people in
                    ["optionIndex": index, "personIds": people.map { $0.uuidString.lowercased() }]
                }
                let poll: [String: Any] = ["optionCount": message.pollVotes.count, "multiple": false, "closed": false,
                                           "creatorId": scope.accountID.uuidString.lowercased(), "votes": votes]
                row["poll"] = poll
            }
            return row
        }
        let limit: Any = readOnly ? (id == MessagingQualificationIDs.general ? 20 : item.lastSequence) : NSNull()
        let reader = item.peer ?? MessagingQualificationIDs.leaPerson
        let receipts: [[String: Any]] = [["personId": reader.uuidString.lowercased(),
                                          "lastReadSequence": item.lastSequence - 1]]
        let access: [String: Any] = ["canWrite": !readOnly, "readableUntilSequence": limit, "isGroupAdmin": true]
        return try json(["items": items, "nextCursor": next, "access": access, "readStates": receipts])
    }

    private func readState(_ id: UUID, body: Data?) throws -> String {
        struct Body: Decodable { let lastReadSequence: Int }
        guard let index = conversations.firstIndex(where: { $0.id == id }),
              let body, let requested = try? JSONDecoder().decode(Body.self, from: body) else { throw MessagingFailure.invalidResponse }
        conversations[index].lastRead = min(max(conversations[index].lastRead, requested.lastReadSequence),
                                            conversations[index].lastSequence)
        conversations[index].version += 1
        return try json(["lastReadSequence": max(conversations[index].lastRead, requested.lastReadSequence),
                         "mutedUntil": NSNull(), "readStateVersion": conversations[index].version])
    }
}

/// Decrypt-only fixture: reads the synthetic plain envelope of the fixture scheme, refuses anything else.
/// `encrypt` throws and `isAvailable` is false: no send can ever be reported as successful.
private struct MessagingQualificationCrypto: MessagingCryptography {
    func isAvailable(scope: MessagingScope, conversationID: UUID) async -> Bool { false }
    func encrypt(_ plaintext: Data, mentions: [UUID], scope: MessagingScope, conversationID: UUID) async throws -> MessagingCiphertext {
        throw MessagingFailure.protectionUnavailable
    }
    func decrypt(_ ciphertext: MessagingCiphertext, scope: MessagingScope, conversationID: UUID) async throws -> Data {
        guard ciphertext.scheme == MessagingQualificationIDs.ciphertextScheme,
              MessagingPlainContent.decode(ciphertext.payload) != nil else { throw MessagingFailure.protectionUnavailable }
        return ciphertext.payload
    }
}

/// In-memory history for previews and on-device search. Lost when the app quits.
private actor MessagingQualificationHistory: MessagingHistoryStore {
    private var items: [UUID: [UUID: MessagingHistoryEntry]] = [:]

    /// Only the latest message of each conversation, as a device that already read it would hold.
    init(seed: [FixtureConversation]) {
        for conversation in seed {
            guard let last = conversation.messages.max(by: { $0.sequence < $1.sequence }) else { continue }
            items[conversation.id] = [last.id: MessagingHistoryEntry(messageID: last.id, conversationID: conversation.id,
                sequence: last.sequence, senderID: last.sender, acceptedAt: last.date,
                content: MessagingPlainContent(text: last.text, poll: last.poll))]
        }
    }
    func upsert(_ entries: [MessagingHistoryEntry], scope: MessagingScope) {
        for entry in entries { items[entry.conversationID, default: [:]][entry.messageID] = entry }
    }
    func entries(conversationID: UUID, scope: MessagingScope) -> [MessagingHistoryEntry] {
        Array((items[conversationID] ?? [:]).values)
    }
    func remove(messageIDs: [UUID], scope: MessagingScope) {
        for key in items.keys { for id in messageIDs { items[key]?[id] = nil } }
    }
    func truncate(conversationID: UUID, after sequence: Int, scope: MessagingScope) {
        items[conversationID] = items[conversationID]?.filter { $0.value.sequence <= sequence }
    }
}

/// Never touches system notifications or the app badge.
private struct MessagingQualificationNotifications: MessagingNotificationCleaning {
    func removeDelivered(schoolID: UUID, conversationID: UUID, upTo sequence: Int) async {}
    func setMessagingBadge(_ count: Int) async {}
}

/// Ephemeral UI input only. No disk storage and no successful message send.
private actor MessagingQualificationMemory: MessagingProtectedOutbox, MessagingProtectedDrafts, MessagingProtectedMutations {
    private var drafts: [UUID: String] = [:]
    private var mutations: [MessagingMutationKey: MessagingPendingMutation] = [:]
    func mutationEntries(scope: MessagingScope) -> [MessagingStoredMutation] { mutations.map { .init(key: $0.key, value: $0.value) } }
    func putMutation(_ entry: MessagingStoredMutation, replacing clock: UUID?, scope: MessagingScope) throws {
        guard mutations[entry.key]?.clock == clock else { throw MessagingFailure.stateConflict }
        mutations[entry.key] = entry.value
    }
    func removeMutation(_ key: MessagingMutationKey, id: UUID, clock: UUID, scope: MessagingScope) {
        if mutations[key]?.id == id && mutations[key]?.clock == clock { mutations[key] = nil }
    }
    func put(_ entry: MessagingPending, scope: MessagingScope) throws { throw MessagingFailure.protectionUnavailable }
    func entries(scope: MessagingScope) -> [MessagingPending] { [] }
    func remove(clientMessageID: UUID, scope: MessagingScope) throws { throw MessagingFailure.protectionUnavailable }
    func loadDraft(conversationID: UUID, scope: MessagingScope) -> String { drafts[conversationID] ?? "" }
    func saveDraft(_ text: String, conversationID: UUID, scope: MessagingScope) { drafts[conversationID] = text }
}

private actor MessagingQualificationKeys: MessagingKeyManagement {
    /// `-messaging-ui-backup` : clé et erreurs synthétiques pour qualifier l'écran (#169/#170/#141), jamais une vraie clé.
    private let backupScenarios = ProcessInfo.processInfo.arguments.contains("-messaging-ui-backup")
    func backupPending(scope: MessagingScope) -> Bool { backupScenarios }
    func enableBackup(scope: MessagingScope) throws -> String {
        guard backupScenarios else { throw MessagingFailure.protectionUnavailable }
        return "SYNT HETI QUEX CLEF TEST UNIQ UEME NTUI"
    }
    func restoreBackup(recoveryKey: String, scope: MessagingScope) throws -> (imported: Int, failed: Int) {
        guard backupScenarios else { throw MessagingFailure.protectionUnavailable }
        switch recoveryKey {
        case "reseau": throw MessagingFailure.unavailable
        case "session": throw MessagingFailure.accessChanged
        case "partielle": return (imported: 2, failed: 1)
        default: throw MessagingFailure.recoveryKeyRefused
        }
    }
    func ownDevices(scope: MessagingScope) -> [MessagingOwnDevice] { [] }
    func deviceVerificationSnapshot(scope: MessagingScope) -> MessagingDeviceVerificationSnapshot {
        MessagingDeviceVerificationSnapshot(
            localDevice: MessagingOwnDevice(id: "FIXTURELOCAL", fingerprint: "local-synthetic-public-fingerprint",
                isCurrent: true, isVerified: false),
            devices: [MessagingOwnDevice(id: "FIXTUREOTHER", fingerprint: "other-synthetic-public-fingerprint",
                isCurrent: false, isVerified: false)], capability: .available)
    }
    func confirmOwnDevice(deviceID: String, fingerprint: String, scope: MessagingScope) throws {
        throw MessagingFailure.protectionUnavailable
    }
}
#endif
