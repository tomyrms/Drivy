import SwiftUI

/// Composition réelle pour le simulateur de développement ou l'IPA explicite de qualification.
/// Aucune fixture, aucun service serveur activé implicitement.
@MainActor
enum MessagingDevelopmentEntry {
    static func make(scope: MessagingScope, baseURL: URL, tokenSource: any AccessTokenSource,
                     transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
                     session: MessagingDevelopmentSession? = nil,
                     photoLoader: @escaping @Sendable (UUID) async -> Data? = { _ in nil },
                     schoolWorkspace: SchoolWorkspace? = nil,
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
        let session = session ?? MessagingDevelopmentSession()
        return SchoolMessagingEntry(scopeID: scopeID,
            isQualification: SchoolMessagingDevelopment.isQualificationBuild, makeView: { peerID in
            AnyView(MessagingDevelopmentContainer(scope: scope, http: http, relay: relay, session: session,
                baseURL: baseURL, tokenSource: tokenSource,
                currentScope: currentScope, photoLoader: photoLoader, schoolWorkspace: schoolWorkspace, initialPeerID: peerID, schoolName: schoolName))
        }, makeSettingsView: {
            AnyView(MessagingDevelopmentContainer(scope: scope, http: http, relay: relay, session: session,
                baseURL: baseURL, tokenSource: tokenSource,
                currentScope: currentScope, photoLoader: photoLoader, schoolWorkspace: schoolWorkspace, initialPeerID: nil,
                schoolName: schoolName, settingsOnly: true))
        })
    }
}

/// Les entrées de la même racine partagent la machine crypto déjà ouverte (notamment son activation du backup).
/// La référence faible ne prolonge pas la vie de l’historique ou des clés après fermeture des vues.
@MainActor
final class MessagingDevelopmentSession {
    fileprivate weak var current: MessagingDevelopmentResources?

    fileprivate func resources(scope: MessagingScope, http: MessagingHTTPTransport, relay: MessagingCryptoHTTPRelay,
        baseURL: URL, tokenSource: any AccessTokenSource,
        photoLoader: @escaping @Sendable (UUID) async -> Data?, schoolWorkspace: SchoolWorkspace?,
        currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) throws -> MessagingDevelopmentResources {
        guard currentScope() == scope else { throw MessagingFailure.contextChanged }
        if let current, current.scope == scope, current.isCurrent() { return current }
        let created = try MessagingDevelopmentResources(scope: scope, http: http, relay: relay,
            baseURL: baseURL, tokenSource: tokenSource,
            photoLoader: photoLoader, schoolWorkspace: schoolWorkspace, currentScope: currentScope)
        current = created
        return created
    }
}

@MainActor
fileprivate final class MessagingDevelopmentResources {
    let scope: MessagingScope
    let keys: MatrixMessagingCryptography
    let workspace: MessagingWorkspace
    private let currentScope: @MainActor @Sendable () -> MessagingScope?
    func isCurrent() -> Bool { currentScope() == scope }

    init(scope: MessagingScope, http: MessagingHTTPTransport, relay: MessagingCryptoHTTPRelay,
        baseURL: URL, tokenSource: any AccessTokenSource,
        photoLoader: @escaping @Sendable (UUID) async -> Data?, schoolWorkspace: SchoolWorkspace?,
        currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) throws {
        self.scope = scope; self.currentScope = currentScope
        let store = try MessagingProtectedStore(scope: scope)
        let cryptography = try MatrixMessagingCryptography(scope: scope, relay: relay)
        keys = cryptography
        let api = MessagingAPIClient(transport: http)
        // Le média est une capacité additive : une ouverture de coffre média impossible
        // laisse la messagerie texte et les sondages strictement inchangés.
        let mediaRuntime: (any MessagingMediaRuntime)?
        do {
            let mediaOutbox = try MessagingProtectedMediaOutbox(scope: scope)
            let mediaCache = try MessagingProtectedMediaCache(scope: scope)
            let factory: MessagingMediaTransportFactory = {
                let deviceID = try await cryptography.currentDeviceID(scope: scope)
                return MessagingHTTPMediaTransport.using(baseURL: baseURL, deviceID: deviceID,
                    tokenSource: tokenSource, currentScope: currentScope)
            }
            mediaRuntime = MessagingMediaCoordinator(scope: scope,
                preparer: MessagingMediaPreparer(), cryptography: AESCTRMediaCryptography(),
                outbox: mediaOutbox, cache: mediaCache, encryption: cryptography,
                sending: api, transportFactory: factory, currentScope: currentScope)
        } catch {
            mediaRuntime = nil
        }
        workspace = MessagingWorkspace(scope: scope, service: api,
            cryptography: cryptography, outbox: store, drafts: store, directory: http, actions: http,
            history: (try? MessagingSealedHistory(scope: scope)) ?? UnavailableMessagingHistory(),
            reportSealing: cryptography, reports: store, mutations: store, photoLoader: photoLoader,
            schoolWorkspace: schoolWorkspace, mediaRuntime: mediaRuntime, currentScope: currentScope)
    }
}

private struct MessagingDevelopmentContainer: View {
    let scope: MessagingScope
    let http: MessagingHTTPTransport
    let relay: MessagingCryptoHTTPRelay
    let session: MessagingDevelopmentSession
    let baseURL: URL
    let tokenSource: any AccessTokenSource
    let currentScope: @MainActor @Sendable () -> MessagingScope?
    let photoLoader: @Sendable (UUID) async -> Data?
    let schoolWorkspace: SchoolWorkspace?
    let initialPeerID: UUID?
    let schoolName: String?
    var settingsOnly = false
    @State private var resources: MessagingDevelopmentResources?
    @State private var failure: MessagingFailure?

    var body: some View {
        Group {
            if let resources {
                if settingsOnly {
                    MessagingSettingsView(keys: resources.keys, scope: scope, currentScope: currentScope)
                } else {
                    MessagingInboxView(workspace: resources.workspace, initialPeerID: initialPeerID, keys: resources.keys,
                                       schoolName: schoolName, currentScope: currentScope)
                }
            } else if let failure {
                ContentUnavailableView("Messages indisponibles", systemImage: "lock.shield",
                    description: Text(failure.localizedDescription))
            } else {
                ProgressView("Ouverture de Messages")
            }
        }
        .task {
            guard resources == nil, failure == nil else { return }
            guard currentScope() == scope else { failure = .contextChanged; return }
            do {
                // Ouverture du Keychain et des fichiers uniquement après ouverture de la sheet.
                resources = try session.resources(scope: scope, http: http, relay: relay,
                    baseURL: baseURL, tokenSource: tokenSource,
                    photoLoader: photoLoader, schoolWorkspace: schoolWorkspace, currentScope: currentScope)
            } catch { failure = .protectionUnavailable }
        }
    }
}
