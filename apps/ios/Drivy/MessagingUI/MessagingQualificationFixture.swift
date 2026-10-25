#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// UI-only fixture. Never creates an identity, opens a socket or persists data.
/// Uses the real views and HTTP decoder, but does not qualify server rights or E2EE.
@MainActor
struct MessagingQualificationFixture: View {
    @State private var workspace: MessagingWorkspace
    private let keys = MessagingQualificationKeys()

    init() {
        let scope = MessagingScope(accountID: UUID(), schoolID: UUID(), accessEpoch: 1,
                                   apiBaseURL: "https://messaging-ui.example.invalid/")
        let transport = MessagingQualificationHTTP(scope: scope,
            readOnly: ProcessInfo.processInfo.arguments.contains("-messaging-ui-readonly"))
        let http = MessagingHTTPTransport(baseURL: URL(string: scope.apiBaseURL)!, transport: transport,
            token: { "synthetic-ui-only" }, invalidate: { _ in false }, currentScope: { scope })
        let memory = MessagingQualificationMemory()
        _workspace = State(initialValue: MessagingWorkspace(scope: scope,
            service: MessagingAPIClient(transport: http), outbox: memory, drafts: memory,
            directory: http, actions: http, currentScope: { scope }))
        // Cryptography intentionally remains unavailable: UI cannot report a false successful send.
    }

    var body: some View {
        SchoolMessagingEntryButton()
            .environment(\.schoolMessagingEntry, SchoolMessagingEntry(scopeID: "synthetic-ui-only", makeView: { _ in
                AnyView(MessagingInboxView(workspace: workspace, keys: keys, currentScope: { [scope = workspace.scope] in scope }))
            }))
            .environment(\.locale, Locale(identifier: "fr_CH"))
    }
}

private actor MessagingQualificationHTTP: SchoolHTTPTransport {
    let scope: MessagingScope
    let readOnly: Bool
    let conversation = UUID()
    let member = UUID()
    private var removed = false

    init(scope: MessagingScope, readOnly: Bool) { self.scope = scope; self.readOnly = readOnly }

    func send(_ request: URLRequest) throws -> SchoolHTTPResponse {
        guard let url = request.url, url.host == "messaging-ui.example.invalid" else {
            throw MessagingFailure.invalidResponse
        }
        let path = url.path.lowercased()
        let method = request.httpMethod ?? "GET"
        let other = #"{"personId":"\#(member)","displayName":"Léa Fixture","hasPhoto":false,"isGroupAdmin":false}"#
        let admin = #"{"personId":"\#(scope.accountID)","displayName":"Admin Fixture","hasPhoto":false,"isGroupAdmin":true}"#
        let data: String
        if path.hasSuffix("/contacts"), method == "GET" {
            data = #"{"contacts":[],"nextCursor":null}"#
        } else if path.hasSuffix("/general/members"), method == "GET" {
            data = #"{"members":[\#(admin)\#(removed ? "" : "," + other)],"nextCursor":null}"#
        } else if path.hasSuffix("/general/removed-members"), method == "GET" {
            data = #"{"members":[\#(removed ? other : "")],"nextCursor":null}"#
        } else if path.hasSuffix("/general/members/" + member.uuidString.lowercased()), method == "DELETE" || method == "PUT" {
            removed = method == "DELETE"
            data = #"{"done":true}"#
        } else if path.hasSuffix("/general"), method == "PUT" {
            data = #"{"conversationId":"\#(conversation)"}"#
        } else if path.hasSuffix("/conversations"), method == "GET" {
            data = #"{"items":[],"nextCursor":null}"#
        } else if path.hasSuffix("/messages"), method == "GET" {
            data = #"{"items":[],"nextCursor":null,"access":{"canWrite":\#(!readOnly),"readableUntilSequence":\#(readOnly ? "0" : "null"),"isGroupAdmin":true},"readStates":[]}"#
        } else {
            // Unspecified mutations must fail rather than manufacture acceptance.
            throw MessagingFailure.unavailable
        }
        let body = #"{"data":\#(data),"context":{"schoolId":"\#(scope.schoolID)","actorPersonId":"\#(scope.accountID)","accessEpoch":1}}"#
        return SchoolHTTPResponse(data: Data(body.utf8), status: 200, url: url, contentType: "application/json")
    }
}

/// Ephemeral UI input only. No disk storage and no successful message send.
private actor MessagingQualificationMemory: MessagingProtectedOutbox, MessagingProtectedDrafts {
    private var drafts: [UUID: String] = [:]
    func put(_ entry: MessagingPending, scope: MessagingScope) throws { throw MessagingFailure.protectionUnavailable }
    func entries(scope: MessagingScope) -> [MessagingPending] { [] }
    func remove(clientMessageID: UUID, scope: MessagingScope) throws { throw MessagingFailure.protectionUnavailable }
    func loadDraft(conversationID: UUID, scope: MessagingScope) -> String { drafts[conversationID] ?? "" }
    func saveDraft(_ text: String, conversationID: UUID, scope: MessagingScope) { drafts[conversationID] = text }
}

private actor MessagingQualificationKeys: MessagingKeyManagement {
    func backupPending(scope: MessagingScope) -> Bool { false }
    func enableBackup(scope: MessagingScope) throws -> String { throw MessagingFailure.protectionUnavailable }
    func restoreBackup(recoveryKey: String, scope: MessagingScope) throws -> (imported: Int, failed: Int) {
        throw MessagingFailure.protectionUnavailable
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
