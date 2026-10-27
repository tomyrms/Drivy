import Foundation

struct SchoolAccountRecoveryOptions: Decodable, Equatable, Sendable {
    let available: Bool
    let recoveryUrl: URL?
}

enum SchoolAccountRecoveryFailure: Error, LocalizedError, Equatable {
    case unavailable, attempts, invalidResponse
    var errorDescription: String? {
        switch self {
        case .unavailable: "La récupération n’a pas pu s’ouvrir. Vérifie le réseau puis réessaie."
        case .attempts: "Trop d’essais. Patiente quelques minutes avant de réessayer."
        case .invalidResponse: "Le lien de récupération n’a pas pu être vérifié. Réessaie."
        }
    }
}

/// Lit seulement la disponibilité du fournisseur. Ni adresse, ni mot de passe, ni session ne transitent ici.
@MainActor final class SchoolAccountRecoveryClient {
    let configuration: AppConfiguration
    private let transport: any SchoolHTTPTransport
    init(configuration: AppConfiguration, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.configuration = configuration; self.transport = transport
    }

    func options() async throws -> SchoolAccountRecoveryOptions {
        guard configuration.isValid else { throw SchoolAccountRecoveryFailure.unavailable }
        let target = configuration.apiBaseURL.appendingPathComponent("v1/account-recovery/options")
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        try Task.checkCancellation()
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw error.unlessCancelled(SchoolAccountRecoveryFailure.unavailable) }
        try Task.checkCancellation()
        guard response.url == target else { throw SchoolAccountRecoveryFailure.invalidResponse }
        guard response.status == 200 else {
            throw response.status == 429 ? SchoolAccountRecoveryFailure.attempts : SchoolAccountRecoveryFailure.unavailable
        }
        let type = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard type == "application/json", response.data.count <= 8_192,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: response.data),
              SchoolLesson.date(envelope.serverTime) != nil else { throw SchoolAccountRecoveryFailure.invalidResponse }
        let value = envelope.data
        if value.available {
            guard let url = value.recoveryUrl, acceptsRecoveryURL(url) else { throw SchoolAccountRecoveryFailure.invalidResponse }
        } else if value.recoveryUrl != nil { throw SchoolAccountRecoveryFailure.invalidResponse }
        return value
    }

    private func acceptsRecoveryURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "https",
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.query == nil,
              parts.percentEncodedPath == "/app/recover",
              url.absoluteString.utf8.count <= 2_048 else { return false }
        return parts.host?.lowercased() == configuration.apiBaseURL.host?.lowercased()
            && (parts.port ?? 443) == (configuration.apiBaseURL.port ?? 443)
    }
    private struct Envelope: Decodable { let data: SchoolAccountRecoveryOptions; let serverTime: String }
}
