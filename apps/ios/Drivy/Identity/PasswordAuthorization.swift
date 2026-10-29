import Foundation
@preconcurrency import AppAuth

/// Connexion par le formulaire de l’app : l’e-mail et le mot de passe vont au fournisseur d’identité
/// (point de jeton du realm), jamais à l’API Drivy ; ils ne sont ni conservés ni journalisés.
@MainActor
protocol PasswordAuthorizing: AnyObject {
    func signIn(email: String, password: String, configuration: AppConfiguration) async throws -> OIDAuthState
}

@MainActor
final class AppAuthPasswordAuthorization: PasswordAuthorizing {
    func signIn(email: String, password: String, configuration: AppConfiguration) async throws -> OIDAuthState {
        let service = try await discover(configuration)
        let request = OIDTokenRequest(configuration: service, grantType: "password", authorizationCode: nil,
                                      redirectURL: nil, clientID: configuration.clientID, clientSecret: nil,
                                      scopes: OIDCPolicy.scopes, refreshToken: nil, codeVerifier: nil,
                                      additionalParameters: ["username": email, "password": password])
        let token = try await perform(request)
        guard token.tokenType?.lowercased() == "bearer", token.accessToken?.isEmpty == false else {
            throw IdentityFailure.unavailable
        }
        // AppAuth renouvelle la session avec la configuration et le client de la demande d’autorisation enregistrée.
        // Cette demande, jamais présentée, porte donc les mêmes valeurs que la connexion par navigateur (PKCE S256,
        // redirection de l’app) : la session se range, se relit et se renouvelle exactement comme avant.
        let authorization = OIDCPolicy.request(service: service, configuration: configuration)
        let response = OIDAuthorizationResponse(request: authorization, parameters: [
            "code": "password-sign-in" as NSString, "state": (authorization.state ?? "") as NSString
        ])
        let state = OIDAuthState(authorizationResponse: response, tokenResponse: token)
        guard state.isAuthorized, OIDCPolicy.accepts(state, configuration: configuration) else { throw IdentityFailure.invalidProvider }
        return state
    }

    private func discover(_ configuration: AppConfiguration) async throws -> OIDServiceConfiguration {
        let archive: Data = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(forIssuer: configuration.issuer) { service, error in
                // Le callback Objective-C ne transfère qu’une valeur immuable.
                if let service, let data = try? NSKeyedArchiver.archivedData(withRootObject: service, requiringSecureCoding: true) {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: Self.failure(error))
                }
            }
        }
        guard let service = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDServiceConfiguration.self, from: archive),
              OIDCPolicy.accepts(service, configuration: configuration) else { throw IdentityFailure.invalidProvider }
        return service
    }

    private func perform(_ request: OIDTokenRequest) async throws -> OIDTokenResponse {
        let archive: Data = try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(request) { response, error in
                if let response, let data = try? NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: true) {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: Self.failure(error))
                }
            }
        }
        guard let response = try? NSKeyedUnarchiver.unarchivedObject(ofClass: OIDTokenResponse.self, from: archive) else {
            throw IdentityFailure.unavailable
        }
        return response
    }

    /// Seuls les codes structurés du fournisseur sont lus, jamais sa description ni son corps brut.
    /// AppAuth peut envelopper un HTTP 429 dans une erreur OAuth : le transport garde la priorité.
    nonisolated static func failure(_ error: (any Error)?) -> IdentityFailure {
        guard let error = error as NSError? else { return .unavailable }
        var underlying: NSError? = error
        for _ in 0..<8 {
            guard let current = underlying else { break }
            if current.domain == OIDHTTPErrorDomain {
                if current.code == 429 { return .attempts }
                if current.code == 408 || current.code >= 500 { return .unavailable }
            }
            underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        guard error.domain == OIDOAuthTokenErrorDomain,
              let response = error.userInfo[OIDOAuthErrorResponseErrorKey] as? [String: Any],
              let code = response[OIDOAuthErrorFieldError] as? String else { return .unavailable }
        switch code {
        case "invalid_grant": return .invalidCredentials
        case "invalid_client", "unauthorized_client", "unsupported_grant_type", "invalid_scope": return .invalidProvider
        default: return .unavailable
        }
    }
}
