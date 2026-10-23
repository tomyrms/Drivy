import SwiftUI

/// Composition explicite et réversible du simulateur. Aucun onglet ajouté ni service activé implicitement.
@MainActor
enum MessagingDevelopmentEntry {
    static func make(scope: MessagingScope, baseURL: URL, tokenSource: any AccessTokenSource,
                     transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
                     currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) -> SchoolMessagingEntry? {
        #if DEBUG && targetEnvironment(simulator)
        let allowed = ProcessInfo.processInfo.arguments.contains("-messaging-development")
        #else
        let allowed = false
        #endif
        guard allowed, scope.apiBaseURL == baseURL.absoluteString, DrivyAPIClient.permits(baseURL),
              currentScope() == scope else { return nil }
        let http = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: tokenSource,
                                                transport: transport, currentScope: currentScope)
        let scopeID = "\(scope.accountID.uuidString)|\(scope.schoolID.uuidString)|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        return SchoolMessagingEntry(scopeID: scopeID, makeView: { peerID in
            AnyView(MessagingDevelopmentContainer(scope: scope, http: http,
                currentScope: currentScope, initialPeerID: peerID))
        })
    }
}

private struct MessagingDevelopmentContainer: View {
    let scope: MessagingScope
    let http: MessagingHTTPTransport
    let currentScope: @MainActor @Sendable () -> MessagingScope?
    let initialPeerID: UUID?
    @State private var workspace: MessagingWorkspace?
    @State private var failure: MessagingFailure?

    var body: some View {
        Group {
            if let workspace {
                MessagingInboxView(workspace: workspace, initialPeerID: initialPeerID)
            } else if let failure {
                ContentUnavailableView("Messages indisponibles", systemImage: "lock.shield",
                    description: Text(failure.localizedDescription))
            } else {
                ProgressView("Ouverture de Messages")
            }
        }
        .task {
            guard workspace == nil, failure == nil else { return }
            guard currentScope() == scope else { failure = .contextChanged; return }
            do {
                // Ouverture du Keychain et des fichiers uniquement après ouverture de la sheet.
                let store = try MessagingProtectedStore(scope: scope)
                workspace = MessagingWorkspace(scope: scope, service: MessagingAPIClient(transport: http),
                    cryptography: UnavailableMessagingCryptography(), outbox: store, drafts: store,
                    directory: http, currentScope: currentScope)
            } catch { failure = .protectionUnavailable }
        }
    }
}
