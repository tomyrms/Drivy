import Foundation

struct MessagingStoredMutation: Codable, Equatable, Sendable {
    let key: MessagingMutationKey
    let value: MessagingPendingMutation

    var isValid: Bool {
        guard value.startedAt.timeIntervalSince1970.isFinite,
              value.acknowledgedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { return false }
        func accepts(_ candidate: MessagingMutationValue) -> Bool {
            switch (key.kind, candidate) {
            case (.reaction(let emoji), .active): return !emoji.isEmpty && emoji.utf8.count <= 64
            case (.pin, .active), (.hideForMe, .active(true)), (.deleteForEveryone, .active(true)): return true
            case (.vote, .options(let ids)): return ids.count <= 20 && ids.allSatisfy { !$0.isEmpty && $0.utf8.count <= 128 }
            case (.mute, .mutedUntil(let date)): return date.map { $0.timeIntervalSince1970.isFinite } ?? true
            default: return false
            }
        }
        return accepts(value.desired) && (value.acknowledged.map(accepts) ?? true)
            && (value.transmitting.map(accepts) ?? true)
            && (key.kind != .mute || (value.readState.map { $0.version >= 0 && $0.lastReadSequence >= 0 } ?? false))
    }
}

protocol MessagingProtectedMutations: Sendable {
    func mutationEntries(scope: MessagingScope) async throws -> [MessagingStoredMutation]
    /// Compare la révision locale, pour qu'une ancienne instance n'écrase jamais un choix conservé plus récent.
    func putMutation(_ entry: MessagingStoredMutation, replacing clock: UUID?, scope: MessagingScope) async throws
    func removeMutation(_ key: MessagingMutationKey, id: UUID, clock: UUID, scope: MessagingScope) async throws
}

struct UnavailableMessagingMutations: MessagingProtectedMutations {
    func mutationEntries(scope: MessagingScope) async throws -> [MessagingStoredMutation] { [] }
    func putMutation(_ entry: MessagingStoredMutation, replacing clock: UUID?, scope: MessagingScope) async throws {
        throw MessagingFailure.protectionUnavailable
    }
    func removeMutation(_ key: MessagingMutationKey, id: UUID, clock: UUID, scope: MessagingScope) async throws {
        throw MessagingFailure.protectionUnavailable
    }
}
