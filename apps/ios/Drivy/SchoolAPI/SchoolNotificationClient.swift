import Foundation

// Préférences de notification (#44) et appareils push (#43) : contrat de apps/api/src/notification-preferences.ts.
// La personne connectée ne gère que ses propres données ; le jeton d’appareil n’est jamais relu ni journalisé.
// Révocation sans jeton d’accès (#120) : apps/api/contracts/push-device-revocation.json. Le secret rendu à
// l’enregistrement n’est ni journalisé ni relu depuis l’école ; l’app le garde au Trousseau.

/// Préférences lues (`GET /v1/me/notification-preferences`) : la version part en `If-Match` à l’écriture.
struct SchoolNotificationPreferences: Codable, Sendable, Equatable {
    let version: Int
    var courseOffers: Bool
    var courseReminders: Bool
    var courseChanges: Bool
    var courseStaffAlerts: Bool
    /// Messagerie (#74). Absents d'une API plus ancienne : l'écran ne propose alors aucun interrupteur de messagerie
    /// et l'écriture ne les envoie pas. Valeurs d'une personne sans ligne : privés et mentions actifs, général désactivé.
    var messagingPrivate: Bool? = nil
    var messagingGeneral: Bool? = nil
    var messagingMentions: Bool? = nil
    /// Demandes de leçon et examens (#43, #44). Absents d'une API plus ancienne : aucun interrupteur et aucun envoi.
    /// Valeurs d'une personne sans ligne : les deux actifs.
    var lessonRequests: Bool? = nil
    var examUpdates: Bool? = nil

    /// Les trois catégories de messagerie sont connues de l'API qui a répondu.
    var supportsMessaging: Bool { messagingPrivate != nil && messagingGeneral != nil && messagingMentions != nil }
    /// Les deux alertes de leçon sont connues de l'API qui a répondu : jamais d'interrupteur pour une alerte inexistante.
    var supportsLessonNotifications: Bool { lessonRequests != nil && examUpdates != nil }

    var body: SchoolNotificationPreferencesBody {
        SchoolNotificationPreferencesBody(courseOffers: courseOffers, courseReminders: courseReminders,
                                          courseChanges: courseChanges, courseStaffAlerts: courseStaffAlerts,
                                          messagingPrivate: messagingPrivate, messagingGeneral: messagingGeneral,
                                          messagingMentions: messagingMentions,
                                          lessonRequests: lessonRequests, examUpdates: examUpdates)
    }
}

/// Corps de `PUT /v1/me/notification-preferences` : le même que la lecture, sans version (le serveur le refuse strictement).
/// Les champs de messagerie et de leçon sont omis quand l'API ne les a pas annoncés ; une écriture en vol enregistrée avant #74 reste lisible.
struct SchoolNotificationPreferencesBody: Codable, Sendable, Equatable {
    let courseOffers: Bool
    let courseReminders: Bool
    let courseChanges: Bool
    let courseStaffAlerts: Bool
    var messagingPrivate: Bool? = nil
    var messagingGeneral: Bool? = nil
    var messagingMentions: Bool? = nil
    var lessonRequests: Bool? = nil
    var examUpdates: Bool? = nil

    /// La réponse de l'école reflète ce corps : chaque champ envoyé y figure avec la même valeur.
    func isReflected(in saved: SchoolNotificationPreferencesBody) -> Bool {
        courseOffers == saved.courseOffers && courseReminders == saved.courseReminders
            && courseChanges == saved.courseChanges && courseStaffAlerts == saved.courseStaffAlerts
            && (messagingPrivate == nil || messagingPrivate == saved.messagingPrivate)
            && (messagingGeneral == nil || messagingGeneral == saved.messagingGeneral)
            && (messagingMentions == nil || messagingMentions == saved.messagingMentions)
            && (lessonRequests == nil || lessonRequests == saved.lessonRequests)
            && (examUpdates == nil || examUpdates == saved.examUpdates)
    }
}

/// Environnement APNs du jeton : celui du profil qui a signé l’app (iLoader ou Xcode), lu dans
/// `embedded.mobileprovision`. Sans profil lisible : bac à sable en Debug, production sinon.
enum SchoolPushEnvironment: String, Codable, Sendable, Equatable {
    case sandbox = "SANDBOX", production = "PRODUCTION"

    static var current: SchoolPushEnvironment {
        if let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: profile), let value = provisioned(in: data) { return value }
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }

    /// Le profil est un PKCS#7 dont le contenu est une plist en clair : on en extrait `aps-environment`.
    static func provisioned(in data: Data) -> SchoolPushEnvironment? {
        guard let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>", range: start.lowerBound..<text.endIndex),
              let plist = text[start.lowerBound..<end.upperBound].data(using: .isoLatin1),
              let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let entitlements = object["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String else { return nil }
        return environment == "production" ? .production : .sandbox
    }
}

enum SchoolPushToken {
    /// Jeton APNs en hexadécimal minuscule, sans séparateur ; `nil` hors des bornes acceptées par l’école (64 à 200).
    static func hex(_ data: Data) -> String? {
        let value = data.map { String(format: "%02x", $0) }.joined()
        return valid(value) ? value : nil
    }
    static func valid(_ value: String) -> Bool {
        (64...200).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Secret de révocation propre à l’appareil (#120) : 32 octets aléatoires rendus une seule fois par l’école, en base64url.
/// Une API plus ancienne n’en rend pas : la révocation authentifiée reste alors le seul chemin.
enum SchoolPushRevocationSecret {
    static let length = 43
    static func valid(_ value: String) -> Bool {
        guard value.utf8.count == length else { return false }
        return value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

struct SchoolPushDeviceBody: Encodable, Sendable, Equatable {
    let token: String
    let environment: SchoolPushEnvironment
}
struct SchoolPushRevokeBody: Encodable, Sendable, Equatable { let token: String }
/// Corps strict de la route anonyme (#120) : `{token, revocationSecret}`, sans autre champ.
struct SchoolPushAnonymousRevokeBody: Encodable, Sendable, Equatable {
    let token: String
    let revocationSecret: String
}

@MainActor final class SchoolNotificationClient {
    let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    func preferences(contextIsCurrent: @escaping @MainActor () -> Bool = { true }) async throws -> SchoolNotificationPreferences {
        let result: SchoolNotificationPreferences = try await send(["notification-preferences"], method: "GET", body: nil, version: nil, contextIsCurrent: contextIsCurrent)
        guard result.version > 0 else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    /// Rend les préférences écrites par l’école ; 412 (`conflict`) si elles ont changé ailleurs.
    func save(_ body: SchoolNotificationPreferencesBody, version: Int, contextIsCurrent: @escaping @MainActor () -> Bool = { true }) async throws -> SchoolNotificationPreferences {
        let data: Data
        do { data = try JSONEncoder().encode(body) } catch { throw SchoolPlanningFailure.invalidResponse }
        let result: SchoolNotificationPreferences = try await send(["notification-preferences"], method: "PUT", body: data, version: version, contextIsCurrent: contextIsCurrent)
        guard result.version > version, body.isReflected(in: result.body) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    /// Rend le secret de révocation quand l’école en donne un (#120) ; `nil` avec une API plus ancienne, qui ne le connaît pas.
    @discardableResult
    func register(token: String, environment: SchoolPushEnvironment) async throws -> String? {
        guard SchoolPushToken.valid(token) else { throw SchoolPlanningFailure.invalidResponse }
        let data: Data
        do { data = try JSONEncoder().encode(SchoolPushDeviceBody(token: token, environment: environment)) } catch { throw SchoolPlanningFailure.invalidResponse }
        let result: Registered = try await send(["push-devices"], method: "PUT", body: data, version: nil)
        guard result.registered else { throw SchoolPlanningFailure.invalidResponse }
        // Un secret hors du format du contrat n’est pas retenu : sans lui, la révocation authentifiée reste seule possible.
        guard let secret = result.revocationSecret, SchoolPushRevocationSecret.valid(secret) else { return nil }
        return secret
    }
    func revoke(token: String) async throws {
        guard SchoolPushToken.valid(token) else { throw SchoolPlanningFailure.invalidResponse }
        let data: Data
        do { data = try JSONEncoder().encode(SchoolPushRevokeBody(token: token)) } catch { throw SchoolPlanningFailure.invalidResponse }
        let result: Revoked = try await send(["push-devices", "revoke"], method: "POST", body: data, version: nil)
        guard result.revoked else { throw SchoolPlanningFailure.invalidResponse }
    }
    /// Révocation sans jeton d’accès (#120) : même base que l’API, aucun en-tête d’autorisation, corps strict
    /// `{token, revocationSecret}`. L’école répond de la même façon que le secret corresponde ou non.
    func revokeAnonymously(token: String, secret: String) async throws {
        guard SchoolPushToken.valid(token), SchoolPushRevocationSecret.valid(secret) else { throw SchoolPlanningFailure.invalidResponse }
        let data: Data
        do { data = try JSONEncoder().encode(SchoolPushAnonymousRevokeBody(token: token, revocationSecret: secret)) } catch { throw SchoolPlanningFailure.invalidResponse }
        let result: Revoked = try await send(["push-devices", "revoke"], method: "POST", body: data, version: nil, authenticated: false)
        guard result.revoked else { throw SchoolPlanningFailure.invalidResponse }
    }

    private struct Registered: Decodable {
        let registered: Bool
        /// Absent d’une API plus ancienne (#120).
        let revocationSecret: String?
    }
    private struct Revoked: Decodable { let revoked: Bool }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }

    /// `authenticated` faux : route anonyme, sans « me », sans jeton et sans renouvellement (révocation #120).
    private func send<Value: Decodable>(_ path: [String], method: String, body: Data?, version: Int?,
                                        authenticated: Bool = true,
                                        contextIsCurrent: @escaping @MainActor () -> Bool = { true }) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolPlanningFailure.invalidResponse }
        guard contextIsCurrent() else { throw CancellationError() }
        var target = baseURL
        for part in (authenticated ? ["v1", "me"] : ["v1"]) + path { target.appendPathComponent(part) }
        guard authenticated else {
            return try await perform(target, method: method, body: body, version: version, token: nil)
        }
        let token = try await accessToken()
        guard contextIsCurrent() else { throw CancellationError() }
        do { return try await perform(target, method: method, body: body, version: version, token: token) }
        catch SchoolPlanningFailure.unauthorized {
            guard contextIsCurrent() else { throw CancellationError() }
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolPlanningFailure.unauthorized }
            let renewed = try await accessToken()
            guard contextIsCurrent() else { throw CancellationError() }
            guard renewed != token else { throw SchoolPlanningFailure.unauthorized }
            return try await perform(target, method: method, body: body, version: version, token: renewed)
        }
    }
    private func accessToken() async throws -> String {
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolPlanningFailure.unauthorized }
        catch { throw error.unlessCancelled(SchoolPlanningFailure.unavailable) }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolPlanningFailure.unauthorized }
        return token
    }
    private func perform<Value: Decodable>(_ target: URL, method: String, body: Data?, version: Int?, token: String?) async throws -> Value {
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let version { request.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match") }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) } catch { throw error.unlessCancelled(SchoolPlanningFailure.unavailable) }
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolPlanningFailure.invalidResponse }
        let contentType = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == 200 else {
            let problem = contentType == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data)) : nil
            if response.status == 412 { throw SchoolPlanningFailure.conflict }
            throw SchoolPlanningClient.failure(response.status, problem?.code, title: problem?.title)
        }
        guard contentType == "application/json" else { throw SchoolPlanningFailure.invalidResponse }
        do {
            let result = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !result.requestId.isEmpty, SchoolLesson.date(result.serverTime) != nil else { throw SchoolPlanningFailure.invalidResponse }
            return result.data
        } catch { throw SchoolPlanningFailure.invalidResponse }
    }
}
