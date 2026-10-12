import Foundation

/// L’ordre des signalements d’un moniteur : celui de l’école (`manual`), ou celui que l’école calcule d’après
/// ses propres usages (`smart`). L’app ne calcule aucun score : elle lit un ordre de clés et l’applique.
/// Contrat : docs/implementation/classement-intelligent-ios-20261013.md.
enum SchoolObservationRankingMode: String, Codable, Sendable, Equatable {
    case manual = "MANUAL"
    case smart = "SMART"
}

/// Projection de l’école pour une adhésion : la même à la lecture et après un changement de mode.
struct SchoolObservationRanking: Codable, Sendable, Equatable {
    let id: UUID
    let schoolId: UUID
    let membershipId: UUID
    let version: Int
    let mode: SchoolObservationRankingMode
    /// En mode `smart`, les clés de tous les thèmes affichés de l’école, dans l’ordre du classement ; sinon vide.
    let order: [String]
    /// Date locale (`AAAA-MM-JJ`) du dernier classement, ou `nil` s’il n’y en a jamais eu.
    let rankedOn: String?

    func isValid(for scope: SchoolCommandScope) -> Bool {
        guard schoolId == scope.schoolID, id == scope.membershipID, membershipId == scope.membershipID,
              (1...2_147_483_647).contains(version), Set(order).count == order.count,
              order.allSatisfy(Self.isWellFormed(key:)) else { return false }
        if let rankedOn, !Self.isLocalDate(rankedOn) { return false }
        switch mode {
        case .manual: return order.isEmpty
        case .smart: return (1...64).contains(order.count)
        }
    }

    /// `^[a-z][a-z0-9-]{0,39}$`
    static func isWellFormed(key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard let first = bytes.first, bytes.count <= 40, (97...122).contains(first) else { return false }
        return bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    /// `AAAA-MM-JJ`, sans interprétation : la date n’est jamais calculée par l’app.
    static func isLocalDate(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 10 else { return false }
        for (index, byte) in bytes.enumerated() {
            if index == 4 || index == 7 {
                guard byte == 45 else { return false }
            } else {
                guard (48...57).contains(byte) else { return false }
            }
        }
        return true
    }
}

struct SchoolObservationRankingBody: Codable, Sendable, Equatable {
    let operationId: UUID
    let mode: SchoolObservationRankingMode
}

/// Règle d’ordre, sans vue ni réseau. Le classement ne remplace jamais l’ordre manuel : il le réarrange à
/// l’affichage, pour un nombre quelconque de thèmes.
enum SchoolObservationRankingOrder {
    /// `order` absent ou vide : `themes` tel quel (ordre de l’école). Sinon : les thèmes affichés dans l’ordre de
    /// `order` (clé inconnue ou masquée ignorée, doublon ignoré), puis les thèmes affichés que `order` ne nomme
    /// pas, dans l’ordre de l’école, puis les thèmes masqués, dans l’ordre de l’école.
    static func arranged(_ themes: [SchoolObservationTheme], order: [String]?) -> [SchoolObservationTheme] {
        guard let order, !order.isEmpty else { return themes }
        var displayed: [String: SchoolObservationTheme] = [:]
        for theme in themes where theme.visible && displayed[theme.key] == nil { displayed[theme.key] = theme }
        var placed = Set<String>()
        var result: [SchoolObservationTheme] = []
        result.reserveCapacity(themes.count)
        for key in order {
            guard let theme = displayed[key], placed.insert(key).inserted else { continue }
            result.append(theme)
        }
        result.append(contentsOf: themes.filter { $0.visible && !placed.contains($0.key) })
        result.append(contentsOf: themes.filter { !$0.visible })
        return result
    }
}

/// Lecture et écriture du classement d’une adhésion. Calqué sur `SchoolObservationThemeClient` : même contrôle
/// du compte avant une écriture, mêmes en-têtes, mêmes erreurs typées (`SchoolObservationThemeFailure`).
@MainActor final class SchoolObservationRankingClient {
    let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    func ranking(scope: SchoolCommandScope) async throws -> SchoolObservationRanking {
        try await request(scope, version: nil, body: nil)
    }

    /// `version` est celle de la dernière lecture confirmée (`If-Match`) ; `body.operationId` rend le renvoi sans effet double.
    func save(scope: SchoolCommandScope, version: Int, body: SchoolObservationRankingBody) async throws -> SchoolObservationRanking {
        guard version > 0 else { throw SchoolObservationThemeFailure.invalidResponse }
        let result = try await request(scope, version: version, body: body)
        guard result.version > version else { throw SchoolObservationThemeFailure.invalidResponse }
        return result
    }

    private struct Envelope: Decodable { let data: SchoolObservationRanking; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String }
    @MainActor private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
    }

    private func request(_ scope: SchoolCommandScope, version: Int?, body: SchoolObservationRankingBody?) async throws -> SchoolObservationRanking {
        guard DrivyAPIClient.permits(baseURL), scope.apiBaseURL == baseURL.absoluteString, scope.accessEpoch > 0 else {
            throw SchoolObservationThemeFailure.forbidden
        }
        var target = baseURL
        for part in ["v1", "schools", scope.schoolID.uuidString, "observation-ranking"] { target.appendPathComponent(part) }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolObservationThemeFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolObservationThemeFailure.unauthorized }
        catch { throw error.unlessCancelled(SchoolObservationThemeFailure.unavailable) }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolObservationThemeFailure.unauthorized }
        var request = URLRequest(url: target)
        request.httpMethod = body == nil ? "GET" : "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body, let version {
            // Même jeton pour relire le compte puis écrire : aucune écriture sous un autre compte que celui de l’écran.
            try await verify(scope, token: token)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(body.operationId.uuidString, forHTTPHeaderField: "Idempotency-Key")
            request.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match")
        }
        try Task.checkCancellation()
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw error.unlessCancelled(SchoolObservationThemeFailure.unavailable) }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else {
            throw SchoolObservationThemeFailure.invalidResponse
        }
        let media = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == 200 else {
            let code = media == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data))?.code : nil
            throw SchoolObservationThemeClient.failure(response.status, code: code)
        }
        guard media == "application/json", let envelope = try? JSONDecoder().decode(Envelope.self, from: response.data),
              !envelope.requestId.isEmpty, envelope.requestId.count <= 150, SchoolLesson.date(envelope.serverTime) != nil,
              envelope.data.isValid(for: scope) else { throw SchoolObservationThemeFailure.invalidResponse }
        return envelope.data
    }

    private func verify(_ scope: SchoolCommandScope, token: String) async throws {
        let person: SchoolPerson
        do { person = try await DrivyAPIClient(baseURL: baseURL, tokenSource: PinnedToken(token), transport: transport).me() }
        catch is CancellationError { throw CancellationError() }
        catch SchoolAPIError.unauthorized { throw SchoolObservationThemeFailure.unauthorized }
        catch SchoolAPIError.forbidden { throw SchoolObservationThemeFailure.forbidden }
        catch SchoolAPIError.identityNotLinked { throw SchoolObservationThemeFailure.forbidden }
        catch { throw SchoolObservationThemeFailure.unavailable }
        guard person.personId == scope.personID, person.memberships.contains(where: {
            $0.schoolId == scope.schoolID && $0.membershipId == scope.membershipID && $0.accessEpoch == scope.accessEpoch
        }) else { throw SchoolObservationThemeFailure.forbidden }
    }
}
