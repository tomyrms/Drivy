import Foundation

/// Un thème du catalogue dans les préférences du compte. `visible` est la visibilité EFFECTIVE dans l'école
/// ouverte (celle de l'école si elle l'impose, sinon la visibilité personnelle) ; `schoolVisible` celle de la
/// référence de l'école ; `visibilityEditable` dit si ce compte peut la modifier dans cette école.
/// Contrat : docs/implementation/r08-contrat-serveur-20261111.md.
struct SchoolObservationPreferencesTheme: Codable, Sendable, Equatable, Identifiable {
    let key: String
    let title: String
    var visible: Bool
    let defaultVisible: Bool
    let defaultPosition: Int
    let schoolVisible: Bool
    let visibilityEditable: Bool
    var id: String { key }

    /// Le thème tel que le reste de l'app le dessine (pictogramme, aperçu de la grille).
    var asTheme: SchoolObservationTheme {
        SchoolObservationTheme(key: key, title: title, competencyKeys: [], visible: visible,
                               defaultVisible: defaultVisible, defaultPosition: defaultPosition)
    }
}

struct SchoolObservationLearning: Codable, Sendable, Equatable {
    /// Augmente à chaque « Recommencer l'apprentissage ».
    let generation: Int
    /// Borne durable : aucun geste observé avant elle n'est lu par le classement.
    let since: String?
}

/// Une configuration héritée d'une ancienne école, proposée tant que la personne n'a rien enregistré et que ses
/// écoles divergeaient : le service ne choisit jamais à sa place.
struct SchoolObservationAdoptionCandidate: Codable, Sendable, Equatable, Identifiable {
    struct Entry: Codable, Sendable, Equatable {
        let key: String
        let visible: Bool
    }
    let schoolId: UUID
    let schoolName: String
    let mode: SchoolObservationRankingMode
    let themes: [Entry]
    var id: UUID { schoolId }
}

struct SchoolObservationAdoption: Codable, Sendable, Equatable {
    let candidates: [SchoolObservationAdoptionCandidate]
}

/// Projection des préférences du compte, vue depuis l'école ouverte : la même à la lecture et après chaque commande.
struct SchoolObservationPreferences: Codable, Sendable, Equatable {
    /// Identifiant de la personne connectée (pas de l'adhésion).
    let id: UUID
    let schoolId: UUID
    let version: Int
    let personalizationAllowed: Bool
    let orderCustomized: Bool
    let visibilityCustomized: Bool
    let mode: SchoolObservationRankingMode
    /// Le catalogue complet dans l'ordre manuel personnel.
    let themes: [SchoolObservationPreferencesTheme]
    /// Ce que « Signaler » affiche, dans l'ordre à afficher. Calculé par le service, jamais réécrit comme préférence.
    let palette: [String]
    let rankedOn: String?
    let learning: SchoolObservationLearning
    let adoption: SchoolObservationAdoption?

    func isValid(for scope: SchoolCommandScope) -> Bool {
        guard id == scope.personID, schoolId == scope.schoolID, (1...2_147_483_647).contains(version),
              (1...64).contains(themes.count), (1...64).contains(palette.count), learning.generation >= 0 else { return false }
        let keys = themes.map(\.key)
        guard Set(keys).count == keys.count, keys.allSatisfy(SchoolObservationKey.isWellFormed(_:)),
              Set(palette).count == palette.count, Set(palette).isSubset(of: Set(keys)) else { return false }
        for theme in themes {
            guard !theme.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, theme.title.unicodeScalars.count <= 200,
                  (0...63).contains(theme.defaultPosition) else { return false }
        }
        if let rankedOn, !SchoolObservationKey.isLocalDate(rankedOn) { return false }
        if let candidates = adoption?.candidates {
            guard candidates.count >= 2, candidates.count <= 64 else { return false }
        }
        return true
    }
}

/// Corps de `PUT observation-preferences` : au moins un des trois champs. L'ordre et la visibilité sont séparables.
struct SchoolObservationPreferencesBody: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let key: String
        let visible: Bool
    }
    let operationId: UUID
    var mode: SchoolObservationRankingMode? = nil
    var order: [String]? = nil
    var visibility: [Entry]? = nil

    var isValid: Bool {
        guard mode != nil || order != nil || visibility != nil else { return false }
        if let order, order.isEmpty || Set(order).count != order.count { return false }
        if let visibility {
            guard !visibility.isEmpty, Set(visibility.map(\.key)).count == visibility.count,
                  visibility.contains(where: \.visible) else { return false }
        }
        return true
    }
}

struct SchoolObservationResetBody: Codable, Sendable, Equatable {
    let operationId: UUID
}

enum SchoolObservationPreferencesFailure: Error, Equatable {
    case unauthorized, forbidden, conflict, preconditionRequired, notFound, unavailable, invalidResponse, rejected
    /// 403 `OBSERVATION_PERSONALIZATION_DISABLED` : l'école impose sa visibilité ; rien n'a été écrit.
    case personalizationDisabled
}

/// Ordre personnel filtré par la visibilité effective, et palette d'une leçon. Règles pures : la liste filtrée
/// n'est jamais une préférence.
enum SchoolObservationPalette {
    /// `order` est l'ordre personnel (clés de tout le catalogue) ; `visible` les clés effectivement affichées.
    static func compose(order: [String], visible: Set<String>) -> [String] {
        var seen = Set<String>()
        return order.filter { visible.contains($0) && seen.insert($0).inserted }
    }

    /// Palette d'une leçon : l'ordre figé à sa première ouverture pour les clés encore affichées, puis celles qui le
    /// sont devenues depuis, dans l'ordre courant. Un thème masqué depuis disparaît ; rien d'autre ne bouge.
    static func arranged(current: [String], frozen: [String]?) -> [String] {
        guard let frozen, !frozen.isEmpty else { return current }
        let allowed = Set(current)
        var seen = Set<String>()
        var result = frozen.filter { allowed.contains($0) && seen.insert($0).inserted }
        result.append(contentsOf: current.filter { seen.insert($0).inserted })
        return result
    }
}

/// Lecture et écriture des préférences de signalements du compte, depuis l'école ouverte. Même forme que
/// `SchoolObservationThemeClient` : contrôle du compte avant écriture, `If-Match`, `Idempotency-Key`, enveloppe.
@MainActor final class SchoolObservationPreferencesClient {
    let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    func preferences(scope: SchoolCommandScope) async throws -> SchoolObservationPreferences {
        try await request(scope, suffix: nil, method: "GET", version: nil, operation: nil, body: nil)
    }

    /// `version` est celle de la dernière lecture confirmée (`If-Match`) ; `body.operationId` rend le renvoi sans effet double.
    func save(scope: SchoolCommandScope, version: Int, body: SchoolObservationPreferencesBody) async throws -> SchoolObservationPreferences {
        guard version > 0, body.isValid, let data = try? Self.encode(body) else { throw SchoolObservationPreferencesFailure.invalidResponse }
        let result = try await request(scope, suffix: nil, method: "PUT", version: version, operation: body.operationId, body: data)
        guard result.version >= version else { throw SchoolObservationPreferencesFailure.invalidResponse }
        return result
    }

    /// Ordre et visibilité de référence de l'école ouverte copiés sur le compte.
    func resetPresentation(scope: SchoolCommandScope, version: Int, operationId: UUID) async throws -> SchoolObservationPreferences {
        try await reset(scope, suffix: "presentation-reset", version: version, operationId: operationId)
    }

    /// Nouvelle borne d'apprentissage : aucune observation n'est supprimée.
    func resetLearning(scope: SchoolCommandScope, version: Int, operationId: UUID) async throws -> SchoolObservationPreferences {
        try await reset(scope, suffix: "learning-reset", version: version, operationId: operationId)
    }

    private func reset(_ scope: SchoolCommandScope, suffix: String, version: Int, operationId: UUID) async throws -> SchoolObservationPreferences {
        guard version > 0, let data = try? Self.encode(SchoolObservationResetBody(operationId: operationId)) else {
            throw SchoolObservationPreferencesFailure.invalidResponse
        }
        let result = try await request(scope, suffix: suffix, method: "POST", version: version, operation: operationId, body: data)
        guard result.version >= version else { throw SchoolObservationPreferencesFailure.invalidResponse }
        return result
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private struct Envelope: Decodable { let data: SchoolObservationPreferences; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String }
    @MainActor private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
    }

    private func request(_ scope: SchoolCommandScope, suffix: String?, method: String, version: Int?, operation: UUID?,
                         body: Data?) async throws -> SchoolObservationPreferences {
        guard DrivyAPIClient.permits(baseURL), scope.apiBaseURL == baseURL.absoluteString, scope.accessEpoch > 0 else {
            throw SchoolObservationPreferencesFailure.forbidden
        }
        var target = baseURL
        var parts = ["v1", "schools", scope.schoolID.uuidString, "observation-preferences"]
        if let suffix { parts.append(suffix) }
        for part in parts { target.appendPathComponent(part) }
        let token = try await accessToken()
        do { return try await perform(scope, target, method: method, version: version, operation: operation, body: body, token: token) }
        catch SchoolObservationPreferencesFailure.unauthorized {
            // Un premier 401 peut viser un jeton que l'appareil croit encore valable : un seul renouvellement forcé
            // et un seul nouvel essai, même opération et même clé d'idempotence.
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolObservationPreferencesFailure.unauthorized }
            let renewed = try await accessToken()
            guard renewed != token else { throw SchoolObservationPreferencesFailure.unauthorized }
            return try await perform(scope, target, method: method, version: version, operation: operation, body: body, token: renewed)
        }
    }

    private func accessToken() async throws -> String {
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolObservationPreferencesFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolObservationPreferencesFailure.unauthorized }
        catch { throw error.unlessCancelled(SchoolObservationPreferencesFailure.unavailable) }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolObservationPreferencesFailure.unauthorized }
        return token
    }

    private func perform(_ scope: SchoolCommandScope, _ target: URL, method: String, version: Int?, operation: UUID?,
                         body: Data?, token: String) async throws -> SchoolObservationPreferences {
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body, let version, let operation {
            // Même jeton pour relire le compte puis écrire : aucune écriture sous un autre compte que celui de l'écran.
            try await verify(scope, token: token)
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(operation.uuidString, forHTTPHeaderField: "Idempotency-Key")
            request.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match")
        }
        try Task.checkCancellation()
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw error.unlessCancelled(SchoolObservationPreferencesFailure.unavailable) }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else {
            throw SchoolObservationPreferencesFailure.invalidResponse
        }
        let media = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == 200 else {
            let code = media == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data))?.code : nil
            throw Self.failure(response.status, code: code)
        }
        guard media == "application/json", let envelope = try? JSONDecoder().decode(Envelope.self, from: response.data),
              !envelope.requestId.isEmpty, envelope.requestId.count <= 150, SchoolLesson.date(envelope.serverTime) != nil,
              envelope.data.isValid(for: scope) else { throw SchoolObservationPreferencesFailure.invalidResponse }
        return envelope.data
    }

    private func verify(_ scope: SchoolCommandScope, token: String) async throws {
        let person: SchoolPerson
        do { person = try await DrivyAPIClient(baseURL: baseURL, tokenSource: PinnedToken(token), transport: transport).me() }
        catch is CancellationError { throw CancellationError() }
        catch SchoolAPIError.unauthorized { throw SchoolObservationPreferencesFailure.unauthorized }
        catch SchoolAPIError.forbidden { throw SchoolObservationPreferencesFailure.forbidden }
        catch SchoolAPIError.identityNotLinked { throw SchoolObservationPreferencesFailure.forbidden }
        catch { throw SchoolObservationPreferencesFailure.unavailable }
        guard person.personId == scope.personID, person.memberships.contains(where: {
            $0.schoolId == scope.schoolID && $0.membershipId == scope.membershipID && $0.accessEpoch == scope.accessEpoch
        }) else { throw SchoolObservationPreferencesFailure.forbidden }
    }

    static func failure(_ status: Int, code: String?) -> SchoolObservationPreferencesFailure {
        switch status {
        case 401: return .unauthorized
        case 403: return code == "OBSERVATION_PERSONALIZATION_DISABLED" ? .personalizationDisabled : .forbidden
        case 404: return .notFound
        case 412: return .conflict
        case 428: return .preconditionRequired
        // Un identifiant d'opération déjà utilisé pour une autre demande ne dit rien du résultat.
        case 400, 409, 422: return code == "IDEMPOTENCY_MISMATCH" ? .unavailable : .rejected
        case 408, 429, 500...599: return .unavailable
        default: return .invalidResponse
        }
    }
}
