import Foundation

struct UnavailableMessagingDrafts: MessagingProtectedDrafts {
    func loadDraft(conversationID: UUID, scope: MessagingScope) async throws -> String { throw MessagingFailure.protectionUnavailable }
    func saveDraft(_ text: String, conversationID: UUID, scope: MessagingScope) async throws { throw MessagingFailure.protectionUnavailable }
}
