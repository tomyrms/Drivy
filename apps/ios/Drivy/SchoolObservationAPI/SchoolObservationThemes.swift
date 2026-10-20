import Foundation

/// Un thème du catalogue des signalements, tel que l’école l’a rangé. La clé est stable : elle nomme aussi le
/// pictogramme (`Observation-<clé>`) et reste sur chaque observation qualifiée.
/// Contrat : docs/implementation/signalements-configurables-20261012.md.
struct SchoolObservationTheme: Codable, Sendable, Equatable, Identifiable {
    let key: String
    let title: String
    /// Déprécié (#56) : plus aucune règle ne le lit. Relu s’il est présent, vide sinon, pour qu’un service qui cessera de
    /// le publier ne rende pas la configuration illisible.
    let competencyKeys: [String]
    var visible: Bool
    let defaultVisible: Bool
    let defaultPosition: Int
    var id: String { key }
}

extension SchoolObservationTheme {
    private enum CodingKeys: String, CodingKey { case key, title, competencyKeys, visible, defaultVisible, defaultPosition }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(String.self, forKey: .key), title: try c.decode(String.self, forKey: .title),
                  competencyKeys: try c.decodeIfPresent([String].self, forKey: .competencyKeys) ?? [],
                  visible: try c.decode(Bool.self, forKey: .visible), defaultVisible: try c.decode(Bool.self, forKey: .defaultVisible),
                  defaultPosition: try c.decode(Int.self, forKey: .defaultPosition))
    }
}

/// Copie embarquée du catalogue : le repli tant que l’école n’a jamais répondu, et la liste des clés que
/// cette version de l’app sait dessiner.
enum SchoolObservationThemeCatalog {
    static let embedded: [SchoolObservationTheme] = ([
        ("vehicle", "Maîtrise du véhicule", ["vehicule"], true),
        ("observation", "Observation et contrôles", ["observation"], true),
        ("right-priority", "Priorité à droite", ["priorites"], true),
        ("signage", "Signalisation", ["priorites"], true),
        ("give-way", "Céder le passage", ["priorites"], true),
        ("intersections", "Intersections et giratoires", ["intersections"], true),
        ("speed", "Vitesse", ["vitesse"], true),
        ("placement", "Placement sur la chaussée", ["placement"], true),
        ("manoeuvres", "Manœuvres", ["manoeuvres", "parking"], true),
        ("motorway", "Autoroute", ["autoroute", "motorway"], true),
        ("anticipation", "Anticipation", ["anticipation"], true),
        ("indicators", "Clignotants", ["observation"], true),
        ("following-distance", "Distance de sécurité", ["vitesse"], false),
        ("braking", "Freinage", ["vehicule"], false),
        ("lane-change", "Changement de voie", ["placement"], false),
        ("moving-off", "Démarrage", ["vehicule"], false),
        ("bends", "Virages", ["placement"], false),
        ("eco-driving", "Éco-conduite", ["vehicule"], false),
    ] as [(String, String, [String], Bool)]).enumerated().map { index, value in
        SchoolObservationTheme(key: value.0, title: value.1, competencyKeys: value.2, visible: value.3,
                               defaultVisible: value.3, defaultPosition: index)
    }

    static let keys = Set(embedded.map(\.key))

    /// Une configuration reçue ou relue, ramenée au catalogue de cette version : une clé inconnue est ignorée,
    /// un thème manquant retrouve sa place et son affichage d’origine. Une liste qui masquerait tout ne vide
    /// pas « Signaler » : elle redevient la configuration d’origine.
    static func arranged(_ received: [SchoolObservationTheme]) -> [SchoolObservationTheme] {
        var seen = Set<String>()
        var result = received.filter { keys.contains($0.key) && seen.insert($0.key).inserted }
        for theme in embedded where !seen.contains(theme.key) {
            result.insert(theme, at: min(theme.defaultPosition, result.count))
        }
        return result.contains(where: \.visible) ? result : embedded
    }

    /// Thèmes reçus de l’école que cette version ne connaît pas (catalogue de l’école plus récent). Ils ne se
    /// montrent pas, mais chaque écriture les renvoie : l’école refuse une liste incomplète. Chacun garde sa
    /// place par rapport au thème connu qui le précède.
    static func foreign(in received: [SchoolObservationTheme]) -> [SchoolObservationForeignTheme] {
        var seen = Set<String>(), result: [SchoolObservationForeignTheme] = []
        var anchor: String?
        for theme in received where seen.insert(theme.key).inserted {
            if keys.contains(theme.key) { anchor = theme.key }
            else { result.append(SchoolObservationForeignTheme(key: theme.key, visible: theme.visible, after: anchor)) }
        }
        return result
    }

    /// Clés de cette version que l’école n’a pas listées (école plus ancienne) : elle les refuserait.
    static func unlisted(in received: [SchoolObservationTheme]) -> Set<String> {
        keys.subtracting(received.map(\.key))
    }

    /// L’ordre d’origine, sans toucher à l’affichage choisi.
    static func originalOrder(_ themes: [SchoolObservationTheme]) -> [SchoolObservationTheme] {
        themes.enumerated().sorted { ($0.element.defaultPosition, $0.offset) < ($1.element.defaultPosition, $1.offset) }
            .map(\.element)
    }

    /// L’ordre et l’affichage d’origine.
    static func original(_ themes: [SchoolObservationTheme]) -> [SchoolObservationTheme] {
        originalOrder(themes).map { theme in
            var value = theme
            value.visible = theme.defaultVisible
            return value
        }
    }
}

/// La configuration qu’un écran utilise, avec sa provenance : seule une configuration venue de l’école
/// (lue à l’instant ou relue de la copie locale) autorise l’envoi de `themeKey`.
struct SchoolObservationThemeConfiguration: Sendable, Equatable {
    enum Source: String, Sendable { case embedded, server }
    var themes: [SchoolObservationTheme]
    /// Version de l’école ; 0 pour le repli embarqué, qui n’a jamais été confirmé.
    var version: Int
    var source: Source
    /// Thèmes de l’école inconnus de cette version : jamais montrés, toujours renvoyés.
    var foreign: [SchoolObservationForeignTheme] = []
    /// Thèmes de cette version que l’école ne liste pas : ni renvoyés, ni réglables, ni nommés par `themeKey`.
    var unlisted: Set<String> = []

    static let embedded = SchoolObservationThemeConfiguration(themes: SchoolObservationThemeCatalog.embedded,
                                                              version: 0, source: .embedded)

    /// Configuration reçue de l’école, ramenée au catalogue de cette version sans rien perdre de ce qu’elle a listé.
    static func server(_ received: [SchoolObservationTheme], version: Int) -> SchoolObservationThemeConfiguration {
        SchoolObservationThemeConfiguration(themes: SchoolObservationThemeCatalog.arranged(received), version: version,
            source: .server, foreign: SchoolObservationThemeCatalog.foreign(in: received),
            unlisted: SchoolObservationThemeCatalog.unlisted(in: received))
    }

    var isFromServer: Bool { source == .server }
    /// Une observation ne nomme son thème que si l’école a répondu et connaît cette clé.
    func sendsThemeKey(_ key: String?) -> Bool {
        guard let key else { return false }
        return isFromServer && !unlisted.contains(key)
    }
    var visibleCount: Int { themes.filter(\.visible).count }
}

struct SchoolObservationForeignTheme: Codable, Sendable, Equatable {
    let key: String
    let visible: Bool
    /// Clé du thème connu qui le précède dans la liste de l’école ; `nil` s’il est en tête.
    let after: String?
}

/// Projection de l’école : la même à la lecture et après une modification.
struct SchoolObservationThemeSettings: Codable, Sendable, Equatable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let canManage: Bool
    let themes: [SchoolObservationTheme]

    func isValid(for schoolID: UUID) -> Bool {
        guard id == schoolID, schoolId == schoolID, (1...2_147_483_647).contains(version),
              (1...64).contains(themes.count), Set(themes.map(\.key)).count == themes.count,
              themes.contains(where: \.visible) else { return false }
        for theme in themes {
            guard !theme.key.isEmpty, theme.key.utf8.count <= 40, theme.title.unicodeScalars.count <= 200,
                  !theme.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (0...8).contains(theme.competencyKeys.count), (0...63).contains(theme.defaultPosition) else { return false }
            guard theme.competencyKeys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 100 }) else { return false }
        }
        return true
    }
}

struct SchoolObservationThemesBody: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        let key: String
        let visible: Bool
    }
    let operationId: UUID
    let themes: [Entry]

    /// La liste que l’école attend : exactement les clés qu’elle a listées. Les thèmes connus dans leur nouvel
    /// ordre, sans ceux qu’elle ne liste pas (`unlisted`) ; les thèmes inconnus de cette version (`foreign`)
    /// replacés après le thème connu qui les précédait, avec leur affichage intact.
    init(operationId: UUID, themes: [SchoolObservationTheme], foreign: [SchoolObservationForeignTheme] = [],
         unlisted: Set<String> = []) {
        self.operationId = operationId
        var entries = foreign.filter { $0.after == nil }.map { Entry(key: $0.key, visible: $0.visible) }
        var placed = Set(entries.map(\.key))
        for theme in themes {
            if !unlisted.contains(theme.key) { entries.append(Entry(key: theme.key, visible: theme.visible)) }
            for follower in foreign where follower.after == theme.key {
                entries.append(Entry(key: follower.key, visible: follower.visible))
                placed.insert(follower.key)
            }
        }
        // Un repère disparu ne fait perdre aucune clé : elle part en fin de liste.
        for orphan in foreign where !placed.contains(orphan.key) {
            entries.append(Entry(key: orphan.key, visible: orphan.visible))
        }
        self.themes = entries
    }

    /// Chaque clé une fois, et au moins un thème affiché. Le nombre de clés est celui de l’école, pas celui de l’app.
    var isValid: Bool {
        !themes.isEmpty && Set(themes.map(\.key)).count == themes.count && themes.contains(where: \.visible)
    }
}

enum SchoolObservationThemeFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, conflict, preconditionRequired, notFound, unavailable, invalidResponse, rejected

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Reconnecte-toi pour retrouver les signalements de l’école."
        case .forbidden: "Tes accès ne permettent plus de gérer les signalements."
        case .conflict: "Les signalements avaient changé. Voici leur version actuelle."
        case .preconditionRequired: "La version des signalements n’a pas pu être vérifiée. Recharge-les avant de modifier."
        case .notFound: "L’école ne propose pas encore le réglage des signalements."
        case .unavailable: "L’école est momentanément inaccessible. Rien n’a été modifié."
        case .invalidResponse: "La réponse de l’école n’a pas pu être vérifiée."
        case .rejected: "L’école a refusé cette modification. Recharge les signalements puis réessaie."
        }
    }
}

/// Lecture et écriture de la configuration des signalements d’une école. Petite et versionnée : pas de flux,
/// pas de file ; l’appelant garde l’état confirmé et rejoue une écriture incertaine avec la même opération.
@MainActor final class SchoolObservationThemeClient {
    let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    func settings(scope: SchoolCommandScope) async throws -> SchoolObservationThemeSettings {
        try await request(scope, version: nil, body: nil)
    }

    /// `version` est celle de la dernière lecture confirmée (`If-Match`) ; `body.operationId` rend le renvoi sans effet double.
    func save(scope: SchoolCommandScope, version: Int, body: SchoolObservationThemesBody) async throws -> SchoolObservationThemeSettings {
        guard version > 0, body.isValid else { throw SchoolObservationThemeFailure.invalidResponse }
        let result = try await request(scope, version: version, body: body)
        guard result.version > version else { throw SchoolObservationThemeFailure.invalidResponse }
        return result
    }

    private struct Envelope: Decodable { let data: SchoolObservationThemeSettings; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String }
    @MainActor private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
    }

    private func request(_ scope: SchoolCommandScope, version: Int?, body: SchoolObservationThemesBody?) async throws -> SchoolObservationThemeSettings {
        guard DrivyAPIClient.permits(baseURL), scope.apiBaseURL == baseURL.absoluteString, scope.accessEpoch > 0 else {
            throw SchoolObservationThemeFailure.forbidden
        }
        var target = baseURL
        for part in ["v1", "schools", scope.schoolID.uuidString, "observation-themes"] { target.appendPathComponent(part) }
        let token = try await accessToken()
        do { return try await perform(scope, target, version: version, body: body, token: token) }
        catch SchoolObservationThemeFailure.unauthorized {
            // Un premier 401 peut viser un jeton que l’appareil croit encore valable : un seul renouvellement forcé
            // et un seul nouvel essai, même opération et même clé d’idempotence.
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolObservationThemeFailure.unauthorized }
            let renewed = try await accessToken()
            guard renewed != token else { throw SchoolObservationThemeFailure.unauthorized }
            return try await perform(scope, target, version: version, body: body, token: renewed)
        }
    }

    private func accessToken() async throws -> String {
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolObservationThemeFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolObservationThemeFailure.unauthorized }
        catch { throw error.unlessCancelled(SchoolObservationThemeFailure.unavailable) }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolObservationThemeFailure.unauthorized }
        return token
    }

    private func perform(_ scope: SchoolCommandScope, _ target: URL, version: Int?, body: SchoolObservationThemesBody?,
                         token: String) async throws -> SchoolObservationThemeSettings {
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
            throw Self.failure(response.status, code: code)
        }
        guard media == "application/json", let envelope = try? JSONDecoder().decode(Envelope.self, from: response.data),
              !envelope.requestId.isEmpty, envelope.requestId.count <= 150, SchoolLesson.date(envelope.serverTime) != nil,
              envelope.data.isValid(for: scope.schoolID) else { throw SchoolObservationThemeFailure.invalidResponse }
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

    static func failure(_ status: Int, code: String?) -> SchoolObservationThemeFailure {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 412: return .conflict
        case 428: return .preconditionRequired
        // Un identifiant d’opération déjà utilisé pour une autre demande ne dit rien du résultat.
        case 400, 409, 422: return code == "IDEMPOTENCY_MISMATCH" ? .unavailable : .rejected
        case 408, 429, 500...599: return .unavailable
        default: return .invalidResponse
        }
    }
}
