import Foundation

/// Ouvrir son école avec un code d’ouverture : la commande est rejouable (même opération, mêmes octets)
/// tant que sa réponse n’est pas connue ; le serveur rend alors le même reçu.
struct SchoolOpeningCommand: Codable, Equatable, Sendable {
    let operationId: UUID
    let token: String
    let schoolName: String
    let displayName: String
    let contactEmail: String
    let contactPhone: String?
    let timeZone: String
    let instructs: Bool

    // `contactPhone` absent s’envoie `null` : le serveur l’exige explicitement.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationId, forKey: .operationId); try container.encode(token, forKey: .token)
        try container.encode(schoolName, forKey: .schoolName); try container.encode(displayName, forKey: .displayName)
        try container.encode(contactEmail, forKey: .contactEmail); try container.encode(contactPhone, forKey: .contactPhone)
        try container.encode(timeZone, forKey: .timeZone); try container.encode(instructs, forKey: .instructs)
    }
}

struct SchoolOpeningReceipt: Decodable, Equatable, Sendable {
    let schoolId: UUID
    let schoolName: String
    let status: String
    let membershipId: UUID
    let roles: [String]
}

enum SchoolOpeningFailure: Error, LocalizedError, Equatable {
    case authentication, invalidCode, used, expired, invalidFields, unavailable, unknown
    var errorDescription: String? {
        switch self {
        case .authentication: "Ta session a expiré. Connecte-toi à nouveau."
        case .invalidCode: "Ce code d’ouverture n’est pas valable."
        case .used: "Ce code a déjà servi à ouvrir une école."
        case .expired: "Ce code a expiré. Demande un nouveau code à Drivy."
        case .invalidFields: "Vérifie les champs puis réessaie."
        case .unavailable: "La connexion n’a pas abouti. Ta demande est conservée : réessaie."
        case .unknown: "La réponse n’est pas arrivée. Réessaie : la même demande sera renvoyée."
        }
    }
    /// Le serveur a pu enregistrer la demande : seule la même opération peut être renvoyée.
    var keepsOperation: Bool { self == .unavailable || self == .unknown }
}

@MainActor final class SchoolOpeningClient {
    private let configuration: AppConfiguration
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    init(configuration: AppConfiguration, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.configuration = configuration; self.tokenSource = tokenSource; self.transport = transport
    }

    func open(_ command: SchoolOpeningCommand) async throws -> SchoolOpeningReceipt {
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolOpeningFailure.authentication }
        catch { throw error.unlessCancelled(SchoolOpeningFailure.unavailable) }
        let target = configuration.apiBaseURL.appendingPathComponent("v1").appendingPathComponent("school-openings")
        var request = URLRequest(url: target)
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(command)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(command.operationId.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        try Task.checkCancellation()
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw error.unlessCancelled(SchoolOpeningFailure.unavailable) }
        guard response.url == target else { throw SchoolOpeningFailure.unknown }
        struct Envelope: Decodable { let data: SchoolOpeningReceipt }
        struct Problem: Decodable { let code: String }
        guard response.status == 201 else {
            let code = try? JSONDecoder().decode(Problem.self, from: response.data).code
            switch (response.status, code ?? "") {
            case (401, _): throw SchoolOpeningFailure.authentication
            case (_, "OPENING_LINK_INVALID"): throw SchoolOpeningFailure.invalidCode
            case (_, "OPENING_LINK_USED"): throw SchoolOpeningFailure.used
            case (_, "OPENING_LINK_EXPIRED"), (_, "OPENING_LINK_REVOKED"): throw SchoolOpeningFailure.expired
            case (400, _): throw SchoolOpeningFailure.invalidFields
            default: throw response.status >= 500 || response.status == 408 || response.status == 429 ? SchoolOpeningFailure.unavailable : SchoolOpeningFailure.unknown
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: response.data), envelope.data.roles.contains("ADMIN") else {
            throw SchoolOpeningFailure.unknown
        }
        return envelope.data
    }
}
