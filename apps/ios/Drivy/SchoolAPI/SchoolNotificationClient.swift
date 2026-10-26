import Foundation

// Préférences de notification (#44) et appareils push (#43) : contrat de apps/api/src/notification-preferences.ts.
// La personne connectée ne gère que ses propres données ; le jeton d’appareil n’est jamais relu ni journalisé.

/// Préférences lues (`GET /v1/me/notification-preferences`) : la version part en `If-Match` à l’écriture.
struct SchoolNotificationPreferences: Codable, Sendable, Equatable {
    let version: Int
    var courseOffers: Bool
    var courseReminders: Bool
    var courseChanges: Bool
    var courseStaffAlerts: Bool

    var body: SchoolNotificationPreferencesBody {
        SchoolNotificationPreferencesBody(courseOffers: courseOffers, courseReminders: courseReminders,
                                          courseChanges: courseChanges, courseStaffAlerts: courseStaffAlerts)
    }
}

/// Corps de `PUT /v1/me/notification-preferences` : le même que la lecture, sans version (le serveur le refuse strictement).
struct SchoolNotificationPreferencesBody: Codable, Sendable, Equatable {
    let courseOffers: Bool
    let courseReminders: Bool
    let courseChanges: Bool
    let courseStaffAlerts: Bool
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

struct SchoolPushDeviceBody: Encodable, Sendable, Equatable {
    let token: String
    let environment: SchoolPushEnvironment
}
struct SchoolPushRevokeBody: Encodable, Sendable, Equatable { let token: String }

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
        guard result.version > version, result.body == body else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func register(token: String, environment: SchoolPushEnvironment) async throws {
        guard SchoolPushToken.valid(token) else { throw SchoolPlanningFailure.invalidResponse }
        let data: Data
        do { data = try JSONEncoder().encode(SchoolPushDeviceBody(token: token, environment: environment)) } catch { throw SchoolPlanningFailure.invalidResponse }
        let result: Registered = try await send(["push-devices"], method: "PUT", body: data, version: nil)
        guard result.registered else { throw SchoolPlanningFailure.invalidResponse }
    }
    func revoke(token: String) async throws {
        guard SchoolPushToken.valid(token) else { throw SchoolPlanningFailure.invalidResponse }
        let data: Data
        do { data = try JSONEncoder().encode(SchoolPushRevokeBody(token: token)) } catch { throw SchoolPlanningFailure.invalidResponse }
        let result: Revoked = try await send(["push-devices", "revoke"], method: "POST", body: data, version: nil)
        guard result.revoked else { throw SchoolPlanningFailure.invalidResponse }
    }

    private struct Registered: Decodable { let registered: Bool }
    private struct Revoked: Decodable { let revoked: Bool }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }

    private func send<Value: Decodable>(_ path: [String], method: String, body: Data?, version: Int?, contextIsCurrent: @escaping @MainActor () -> Bool = { true }) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolPlanningFailure.invalidResponse }
        guard contextIsCurrent() else { throw CancellationError() }
        var target = baseURL
        for part in ["v1", "me"] + path { target.appendPathComponent(part) }
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
    private func perform<Value: Decodable>(_ target: URL, method: String, body: Data?, version: Int?, token: String) async throws -> Value {
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
