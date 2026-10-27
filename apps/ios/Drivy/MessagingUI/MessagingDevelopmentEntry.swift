import SwiftUI

/// Composition réelle pour le simulateur de développement ou l'IPA explicite de qualification.
/// Aucune fixture, aucun service serveur activé implicitement.
@MainActor
enum MessagingDevelopmentEntry {
    static func make(scope: MessagingScope, baseURL: URL, tokenSource: any AccessTokenSource,
                     transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
                     photoLoader: @escaping @Sendable (UUID) async -> Data? = { _ in nil },
                     schoolName: String? = nil,
                     arguments: [String] = ProcessInfo.processInfo.arguments,
                     currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) -> SchoolMessagingEntry? {
        let allowed = SchoolMessagingDevelopment.permitted(arguments: arguments, schoolIsActive: true)
        guard allowed, scope.apiBaseURL == baseURL.absoluteString, DrivyAPIClient.permits(baseURL),
              currentScope() == scope else { return nil }
        let http = MessagingHTTPTransport.using(baseURL: baseURL, tokenSource: tokenSource,
                                                transport: transport, currentScope: currentScope)
        let relay = MessagingCryptoHTTPRelay.using(baseURL: baseURL, tokenSource: tokenSource,
                                                   transport: transport, currentScope: currentScope)
        let scopeID = "\(scope.accountID.uuidString)|\(scope.schoolID.uuidString)|\(scope.accessEpoch)|\(scope.apiBaseURL)"
        return SchoolMessagingEntry(scopeID: scopeID,
            isQualification: SchoolMessagingDevelopment.isQualificationBuild, makeView: { peerID in
            AnyView(MessagingDevelopmentContainer(scope: scope, http: http, relay: relay,
                currentScope: currentScope, photoLoader: photoLoader, initialPeerID: peerID, schoolName: schoolName))
        })
    }
}

private struct MessagingDevelopmentContainer: View {
    let scope: MessagingScope
    let http: MessagingHTTPTransport
    let relay: MessagingCryptoHTTPRelay
    let currentScope: @MainActor @Sendable () -> MessagingScope?
    let photoLoader: @Sendable (UUID) async -> Data?
    let initialPeerID: UUID?
    let schoolName: String?
    @State private var workspace: MessagingWorkspace?
    @State private var keys: MatrixMessagingCryptography?
    @State private var failure: MessagingFailure?

    var body: some View {
        Group {
            if let workspace {
                MessagingInboxView(workspace: workspace, initialPeerID: initialPeerID, keys: keys,
                                   schoolName: schoolName, currentScope: currentScope)
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
                let cryptography = try MatrixMessagingCryptography(scope: scope, relay: relay)
                keys = cryptography
                workspace = MessagingWorkspace(scope: scope, service: MessagingAPIClient(transport: http),
                    cryptography: cryptography, outbox: store, drafts: store,
                    directory: http, actions: http,
                    // Sans historique scellé disponible, la recherche se limite à la mémoire : pas de repli en clair.
                    history: (try? MessagingSealedHistory(scope: scope)) ?? UnavailableMessagingHistory(),
                    reports: store, mutations: store,
                    photoLoader: photoLoader,
                    currentScope: currentScope)
            } catch { failure = .protectionUnavailable }
        }
    }
}
