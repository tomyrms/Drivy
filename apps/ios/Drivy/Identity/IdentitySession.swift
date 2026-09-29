import Foundation
import Observation
import UIKit
@preconcurrency import AppAuth

@MainActor
@Observable
final class IdentitySession: AccessTokenSource {
    private(set) var isAuthenticated = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let configuration: AppConfiguration?
    @ObservationIgnored private let vault: any IdentityVault
    @ObservationIgnored private let authorizer: any IdentityAuthorizing
    @ObservationIgnored private var state: OIDAuthState?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var restored = false
    @ObservationIgnored private var refreshTask: Task<String, Error>?
    @ObservationIgnored private var refreshID: UUID?

    convenience init(configuration: AppConfiguration?) {
        self.init(configuration: configuration, vault: KeychainIdentityVault(), authorizer: AppAuthAuthorization())
    }

    init(configuration: AppConfiguration?, vault: any IdentityVault, authorizer: any IdentityAuthorizing) {
        self.configuration = configuration.flatMap { $0.isValid ? $0 : nil }
        self.vault = vault
        self.authorizer = authorizer
    }

    func restore() async {
        guard !restored, !isWorking else { return }
        restored = true
        guard let configuration else { errorMessage = IdentityFailure.notConfigured.localizedDescription; return }
        let expected = generation
        isWorking = true
        defer { if generation == expected { isWorking = false } }
        do {
            guard let data = try vault.read() else { return }
            let restoredState = try StoredIdentity.decode(data, configuration: configuration)
            guard restoredState.isAuthorized else { throw IdentityFailure.reauthentication }
            state = restoredState
            _ = try await accessToken()
        } catch {
            guard generation == expected else { return }
            isAuthenticated = false
            if !(error is CancellationError) { errorMessage = message(for: error) }
        }
    }

    func signIn(presenting: UIViewController) async {
        guard !isWorking, !isAuthenticated else { return }
        guard let configuration else { errorMessage = IdentityFailure.notConfigured.localizedDescription; return }
        generation = UUID()
        authorizer.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        state = nil
        let expected = generation
        isWorking = true
        errorMessage = nil
        defer { if generation == expected { isWorking = false } }
        do {
            try Task.checkCancellation()
            let newState = try await withTaskCancellationHandler {
                try await authorizer.authorize(configuration: configuration, presenting: presenting)
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == expected else { return }
                    self.authorizer.cancel()
                }
            }
            try Task.checkCancellation()
            guard generation == expected else { throw CancellationError() }
            guard newState.isAuthorized, OIDCPolicy.accepts(newState, configuration: configuration),
                  newState.lastTokenResponse?.accessToken?.isEmpty == false,
                  newState.lastTokenResponse?.tokenType?.lowercased() == "bearer" else { throw IdentityFailure.reauthentication }
            // La session n'est annoncée connectée qu'après écriture durable dans le Trousseau.
            try vault.write(StoredIdentity.encode(newState, configuration: configuration))
            state = newState
            restored = true
            isAuthenticated = true
        } catch {
            guard generation == expected else { return }
            if !(error is CancellationError) { errorMessage = message(for: error) }
        }
    }

    func accessToken() async throws -> String {
        try Task.checkCancellation()
        guard let configuration else { throw IdentityFailure.notConfigured }
        guard let state, state.isAuthorized else { throw IdentityFailure.reauthentication }
        let expected = generation
        if let refreshTask {
            let token = try await refreshTask.value
            try Task.checkCancellation()
            guard generation == expected else { throw CancellationError() }
            return token
        }
        let id = UUID()
        refreshID = id
        let task = Task { @MainActor [self] in
            defer {
                if refreshID == id { refreshTask = nil; refreshID = nil }
            }
            do {
                let token = try await authorizer.freshToken(for: state)
                try Task.checkCancellation()
                guard generation == expected else { throw CancellationError() }
                try vault.write(StoredIdentity.encode(state, configuration: configuration))
                isAuthenticated = true
                errorMessage = nil
                return token
            } catch {
                guard generation == expected else { throw CancellationError() }
                if !state.isAuthorized {
                    self.state = nil
                    isAuthenticated = false
                    do { try vault.clear() } catch { errorMessage = IdentityFailure.storage.localizedDescription }
                }
                if let failure = error as? IdentityFailure, case .storage = failure {
                    self.state = nil
                    isAuthenticated = false
                }
                if !(error is CancellationError) { errorMessage = message(for: error) }
                if error is CancellationError { throw CancellationError() }
                throw error as? IdentityFailure ?? IdentityFailure.unavailable
            }
        }
        refreshTask = task
        let token = try await task.value
        try Task.checkCancellation()
        guard generation == expected else { throw CancellationError() }
        return token
    }

    /// A fresh provider login is checked against the current server Person before
    /// replacing the durable session. The API still validates signed auth_time.
    func reauthenticate(presenting: UIViewController, expectedPersonID: UUID) async -> Bool {
        guard !isWorking, isAuthenticated, let configuration else { return false }
        generation = UUID(); let expected = generation
        authorizer.cancel(); refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        isWorking = true; errorMessage = nil
        defer { if generation == expected { isWorking = false } }
        do {
            let candidate = try await withTaskCancellationHandler {
                try await authorizer.reauthorize(configuration: configuration, presenting: presenting)
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == expected else { return }
                    self.authorizer.cancel()
                }
            }
            try Task.checkCancellation()
            guard generation == expected else { return false }
            guard candidate.isAuthorized, OIDCPolicy.accepts(candidate, configuration: configuration),
                  candidate.lastTokenResponse?.tokenType?.lowercased() == "bearer",
                  let token = candidate.lastTokenResponse?.accessToken, !token.isEmpty else { throw IdentityFailure.reauthentication }
            let source = ReauthenticationTokenSource(token: token)
            let person: SchoolPerson
            do { person = try await DrivyAPIClient(baseURL: configuration.apiBaseURL, tokenSource: source).me() }
            catch SchoolAPIError.identityNotLinked { throw IdentityFailure.differentAccount }
            guard generation == expected, !Task.isCancelled else { return false }
            guard person.personId == expectedPersonID else { throw IdentityFailure.differentAccount }
            try vault.write(StoredIdentity.encode(candidate, configuration: configuration))
            state = candidate
            restored = true
            isAuthenticated = true
            return true
        } catch {
            guard generation == expected else { return false }
            if !(error is CancellationError) { errorMessage = message(for: error) }
            return false
        }
    }

    func signOut() async {
        // Changer la génération avant d'annuler : aucun callback tardif ne réécrit les jetons.
        generation = UUID()
        authorizer.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        state = nil
        restored = true
        isAuthenticated = false
        isWorking = false
        errorMessage = nil
        do { try vault.clear() }
        catch { errorMessage = "La session est fermée dans l’app, mais son effacement du Trousseau a échoué. Déverrouillez l’appareil puis réessayez de vous déconnecter." }
    }

    @discardableResult
    func handleRedirect(_ url: URL) -> Bool {
        guard url.scheme == AppConfiguration.callback.scheme, url.host == nil,
              url.path == AppConfiguration.callback.path, url.fragment == nil else { return false }
        return authorizer.handleRedirect(url)
    }

    private func message(for error: Error) -> String {
        // Les messages du fournisseur peuvent contenir des réponses sensibles : ne pas les exposer.
        (error as? IdentityFailure ?? .unavailable).localizedDescription
    }
}

@MainActor private final class ReauthenticationTokenSource: AccessTokenSource {
    let token: String
    init(token: String) { self.token = token }
    func accessToken() async throws -> String { token }
}
