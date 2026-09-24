import Foundation
import UIKit
@preconcurrency import AppAuth

@MainActor
enum OIDCPolicy {
    static func accepts(_ service: OIDServiceConfiguration, configuration: AppConfiguration) -> Bool {
        configuration.isValid && service.issuer?.absoluteString == configuration.issuer.absoluteString
            && configuration.acceptsIdentityEndpoint(service.authorizationEndpoint)
            && configuration.acceptsIdentityEndpoint(service.tokenEndpoint)
    }

    static func accepts(_ state: OIDAuthState, configuration: AppConfiguration) -> Bool {
        let request = state.lastAuthorizationResponse.request
        return accepts(request.configuration, configuration: configuration)
            && request.clientID == configuration.clientID && request.clientSecret == nil
            && request.redirectURL?.absoluteString == configuration.redirectURL.absoluteString
            && request.responseType == OIDResponseTypeCode && request.codeChallengeMethod == "S256"
    }

    static func request(service: OIDServiceConfiguration, configuration: AppConfiguration) -> OIDAuthorizationRequest {
        // AppAuth génère un state, un nonce et un vérificateur PKCE aléatoires, puis S256.
        OIDAuthorizationRequest(configuration: service, clientId: configuration.clientID, clientSecret: nil,
                                scopes: [OIDScopeOpenID, OIDScopeProfile, "offline_access"],
                                redirectURL: configuration.redirectURL, responseType: OIDResponseTypeCode,
                                additionalParameters: nil)
    }
}

@MainActor
protocol IdentityAuthorizing: AnyObject {
    func authorize(configuration: AppConfiguration, presenting: UIViewController) async throws -> OIDAuthState
    func freshToken(for state: OIDAuthState) async throws -> String
    func cancel()
    func handleRedirect(_ url: URL) -> Bool
}

@MainActor
final class AppAuthAuthorization: IdentityAuthorizing {
    private var operationID: UUID?
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var authorizedState: OIDAuthState?
    private var flow: (any OIDExternalUserAgentSession)?
    private var refreshID: UUID?
    private var refreshContinuation: CheckedContinuation<String, Error>?

    func authorize(configuration: AppConfiguration, presenting: UIViewController) async throws -> OIDAuthState {
        cancel()
        let id = UUID()
        operationID = id
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            authorizationContinuation = continuation
            OIDAuthorizationService.discoverConfiguration(forIssuer: configuration.issuer) { [weak self] service, _ in
                // AppAuth 3.0 livre ces callbacks sur la file principale.
                MainActor.assumeIsolated {
                    guard let self, self.operationID == id else { return }
                    guard let service else { self.finishAuthorization(error: IdentityFailure.unavailable); return }
                    guard OIDCPolicy.accepts(service, configuration: configuration) else {
                        self.finishAuthorization(error: IdentityFailure.invalidProvider); return
                    }
                    guard let agent = OIDExternalUserAgentIOS(presenting: presenting, prefersEphemeralSession: true) else {
                        self.finishAuthorization(error: IdentityFailure.unavailable); return
                    }
                    let request = OIDCPolicy.request(service: service, configuration: configuration)
                    self.flow = OIDAuthState.authState(byPresenting: request, externalUserAgent: agent) { [weak self] state, error in
                        MainActor.assumeIsolated {
                            guard let self, self.operationID == id else { return }
                            if let state, state.isAuthorized, OIDCPolicy.accepts(state, configuration: configuration) {
                                self.authorizedState = state
                                self.finishAuthorization(error: nil)
                            } else if let error = error as NSError?, error.domain == OIDGeneralErrorDomain,
                                      error.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue {
                                self.finishAuthorization(error: CancellationError())
                            } else {
                                self.finishAuthorization(error: IdentityFailure.unavailable)
                            }
                        }
                    }
                }
            }
        }
        guard let state = authorizedState else { throw CancellationError() }
        authorizedState = nil
        return state
    }

    private func finishAuthorization(error: Error?) {
        let continuation = authorizationContinuation
        authorizationContinuation = nil
        operationID = nil
        flow = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }

    func freshToken(for state: OIDAuthState) async throws -> String {
        let id = UUID()
        refreshID = id
        return try await withCheckedThrowingContinuation { continuation in
            refreshContinuation = continuation
            state.performAction { [weak self] token, _, error in
                MainActor.assumeIsolated {
                    guard let self, self.refreshID == id else { return }
                    let continuation = self.refreshContinuation
                    self.refreshContinuation = nil
                    self.refreshID = nil
                    if error == nil, let token, !token.isEmpty,
                       state.lastTokenResponse?.tokenType?.lowercased() == "bearer" {
                        continuation?.resume(returning: token)
                    } else {
                        continuation?.resume(throwing: state.isAuthorized ? IdentityFailure.unavailable : IdentityFailure.reauthentication)
                    }
                }
            }
        }
    }

    func cancel() {
        operationID = nil
        refreshID = nil
        authorizedState = nil
        let authorization = authorizationContinuation
        let refresh = refreshContinuation
        let externalFlow = flow
        authorizationContinuation = nil
        refreshContinuation = nil
        flow = nil
        authorization?.resume(throwing: CancellationError())
        refresh?.resume(throwing: CancellationError())
        externalFlow?.cancel()
    }

    func handleRedirect(_ url: URL) -> Bool {
        guard let flow else { return false }
        do { try flow.resumeExternalUserAgentFlow(url); return true }
        catch { return false }
    }
}
