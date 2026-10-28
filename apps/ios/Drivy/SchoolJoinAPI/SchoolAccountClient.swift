import Foundation

/// Ce qu’ouvre un code, tel que le serveur l’a lu.
enum SchoolAccessKind: String, Codable, Sendable, Equatable {
    case learnerInvitation = "LEARNER_INVITATION"
    case schoolOpening = "SCHOOL_OPENING"
    case emailInvitation = "EMAIL_INVITATION"
}

/// Un code tapé (XXXX-XXXX) ou un lien collé : d’ouverture d’école (`/app/ouvrir#token=…`)
/// ou d’invitation reçue par e-mail (`/app/invitation#token=…`).
enum SchoolAccessInput: Equatable, Sendable {
    case code(String)
    case openingLink(String)
    case invitationLink(String)

    /// Valeur envoyée au serveur pour lire ou utiliser ce droit.
    var secret: String {
        switch self {
        case .code(let value): value
        case .openingLink(let token), .invitationLink(let token): token
        }
    }

    static func parse(_ input: String, configuration: AppConfiguration) -> SchoolAccessInput? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = SchoolInvitationCode.display(value) { return .code(code) }
        guard value.utf8.count <= 2_048, let parts = URLComponents(string: value), parts.scheme == "https",
              parts.host?.lowercased() == configuration.apiBaseURL.host?.lowercased(),
              (parts.port ?? 443) == (configuration.apiBaseURL.port ?? 443), parts.user == nil, parts.password == nil, parts.query == nil,
              let fragment = parts.percentEncodedFragment, fragment.hasPrefix("token=") else { return nil }
        let token = String(fragment.dropFirst(6))
        switch parts.path {
        case "/app/ouvrir":
            if let code = SchoolInvitationCode.display(token) { return .openingLink(code) }
            return SchoolJoinClient.validToken(token) ? .openingLink(token) : nil
        case "/app/invitation":
            return SchoolJoinClient.validToken(token) ? .invitationLink(token) : nil
        default:
            return nil
        }
    }
}

struct SchoolAccessPreview: Decodable, Equatable, Sendable {
    let kind: SchoolAccessKind
    let schoolName: String?
    let expiresAt: String
}

struct SchoolNewAccount: Encodable, Sendable {
    let code: String
    let firstName: String
    let lastName: String
    let email: String
    let password: String
}

enum SchoolAccountFailure: Error, LocalizedError, Equatable {
    case invalidCode, attempts, accountExists, passwordRejected, invitationAddress, unavailable, invalidRequest, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidCode: "Ce code n’est pas valable ou n’est plus utilisable."
        case .attempts: "Trop d’essais. Patiente quelques minutes avant de réessayer."
        case .accountExists: "Un compte existe déjà avec cette adresse. Connecte-toi : ton code sera repris."
        case .passwordRejected: "Ce mot de passe n’est pas accepté. Choisis-en un plus long ou moins courant."
        case .invitationAddress: "Utilise l’adresse à laquelle l’école a envoyé l’invitation."
        case .unavailable: "La connexion n’a pas abouti. Vérifie le réseau puis réessaie."
        case .invalidRequest: "Vérifie les champs puis réessaie."
        case .invalidResponse: "La réponse reçue ne peut pas être vérifiée. Réessaie."
        }
    }
}

/// Les deux routes ouvertes sans connexion : lire un code, créer un compte avec lui.
/// Aucun jeton n’est envoyé ; le mot de passe ne fait que traverser cette requête.
@MainActor final class SchoolAccountClient {
    let configuration: AppConfiguration
    private let transport: any SchoolHTTPTransport
    init(configuration: AppConfiguration, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.configuration = configuration; self.transport = transport
    }

    func recoveryClient() -> SchoolAccountRecoveryClient {
        SchoolAccountRecoveryClient(configuration: configuration, transport: transport)
    }

    func preview(_ input: SchoolAccessInput) async throws -> SchoolAccessPreview {
        // Une invitation par e-mail ne se lit qu’avec l’adresse invitée : elle se vérifie à la création du compte.
        if case .invitationLink = input {
            return SchoolAccessPreview(kind: .emailInvitation, schoolName: nil, expiresAt: "")
        }
        let value: SchoolAccessPreview = try await send(["v1", "access-codes", "preview"],
                                                        body: JSONEncoder().encode(["code": input.secret]), expected: 200)
        guard value.kind != .emailInvitation, value.schoolName.map({ $0.unicodeScalars.count <= 300 }) ?? true,
              SchoolLesson.date(value.expiresAt) != nil else { throw SchoolAccountFailure.invalidResponse }
        return value
    }

    func create(_ account: SchoolNewAccount, input: SchoolAccessInput) async throws -> SchoolAccessKind {
        struct Created: Decodable { let kind: SchoolAccessKind }
        do {
            let value: Created = try await send(["v1", "accounts"], body: JSONEncoder().encode(account), expected: 201)
            return value.kind
        } catch SchoolAccountFailure.invalidCode {
            if case .invitationLink = input { throw SchoolAccountFailure.invitationAddress }
            throw SchoolAccountFailure.invalidCode
        }
    }

    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let serverTime: String }
    private struct Problem: Decodable { let code: String }
    private func send<Value: Decodable>(_ path: [String], body: Data, expected: Int) async throws -> Value {
        guard configuration.isValid else { throw SchoolAccountFailure.unavailable }
        var target = configuration.apiBaseURL
        for part in path { target.appendPathComponent(part) }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        try Task.checkCancellation()
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw error.unlessCancelled(SchoolAccountFailure.unavailable) }
        guard response.url == target else { throw SchoolAccountFailure.invalidResponse }
        let type = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == expected else {
            let code = type == "application/problem+json" || type == "application/json"
                ? (try? JSONDecoder().decode(Problem.self, from: response.data).code) : nil
            throw Self.failure(response.status, code: code)
        }
        guard type == "application/json", let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: response.data),
              SchoolLesson.date(envelope.serverTime) != nil else { throw SchoolAccountFailure.invalidResponse }
        return envelope.data
    }

    nonisolated static func failure(_ status: Int, code: String?) -> SchoolAccountFailure {
        switch code {
        case "ACCESS_CODE_INVALID": return .invalidCode
        case "ACCESS_CODE_ATTEMPTS": return .attempts
        case "ACCOUNT_EXISTS": return .accountExists
        case "ACCOUNT_PASSWORD_REJECTED": return .passwordRejected
        case "INVALID_REQUEST" where status == 400: return .invalidRequest
        default: return status == 429 ? .attempts : status >= 500 || status == 408 ? .unavailable : .invalidResponse
        }
    }
}
