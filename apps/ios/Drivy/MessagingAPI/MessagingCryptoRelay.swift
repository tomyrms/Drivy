import Foundation

/// Relais de clés Olm/Megolm par l'API Drivy (docs/implementation/messaging-api-v2.md, section crypto).
/// Les corps sont des JSON Matrix opaques produits par matrix-sdk-crypto ; ce module ne les lit pas.
enum MessagingCryptoRelayFailure: Error, Equatable, Sendable {
    case notFound, backupVersionConflict, deviceLimitReached
    /// 409 sans code connu : ce n'est pas une sauvegarde existante.
    case conflict
}

protocol MessagingCryptoRelay: Sendable {
    /// Renvoie le JSON brut du champ `data` de la réponse, après vérification du contexte.
    func call(scope: MessagingScope, deviceID: String, method: String, path: [String],
              query: [URLQueryItem], body: Data?) async throws -> Data
    /// Membres qui peuvent écrire dans la conversation (privée ou général) et époque de membres.
    func members(scope: MessagingScope, deviceID: String, conversationID: UUID) async throws -> MessagingConversationMembers
}

/// `membersEpoch` augmente à chaque départ et à chaque retour d'un membre (absent : ancien serveur).
struct MessagingConversationMembers: Sendable, Equatable {
    let members: [UUID]
    let membersEpoch: Int?
}

actor MessagingCryptoHTTPRelay: MessagingCryptoRelay {
    private let baseURL: URL
    private let sendHTTP: any SchoolHTTPTransport
    private let token: @MainActor @Sendable () async throws -> String
    private let invalidate: @MainActor @Sendable (String) async -> Bool
    private let currentScope: @MainActor @Sendable () -> MessagingScope?

    private let diagnostics: MessagingDiagnostics

    init(baseURL: URL, transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
         diagnostics: MessagingDiagnostics = .shared,
         token: @escaping @MainActor @Sendable () async throws -> String,
         invalidate: @escaping @MainActor @Sendable (String) async -> Bool,
         currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) {
        self.baseURL = baseURL; self.sendHTTP = transport; self.token = token
        self.invalidate = invalidate; self.currentScope = currentScope
        self.diagnostics = diagnostics
    }

    @MainActor static func using(baseURL: URL, tokenSource: any AccessTokenSource,
                                 transport: any SchoolHTTPTransport = SchoolURLSessionTransport(),
                                 currentScope: @escaping @MainActor @Sendable () -> MessagingScope?) -> MessagingCryptoHTTPRelay {
        MessagingCryptoHTTPRelay(baseURL: baseURL, transport: transport,
            token: { try await tokenSource.accessToken() },
            invalidate: { await tokenSource.invalidateAccessToken($0) }, currentScope: currentScope)
    }

    func call(scope: MessagingScope, deviceID: String, method: String, path: [String],
              query: [URLQueryItem], body: Data?) async throws -> Data {
        try await request(scope: scope, deviceID: deviceID, method: method, path: ["crypto"] + path, query: query, body: body)
    }

    func members(scope: MessagingScope, deviceID: String, conversationID: UUID) async throws -> MessagingConversationMembers {
        struct Members: Decodable { struct Member: Decodable { let personId: UUID }; let members: [Member]; let membersEpoch: Int? }
        let raw = try await request(scope: scope, deviceID: deviceID, method: "GET",
            path: ["conversations", conversationID.uuidString.lowercased(), "members"], query: [], body: nil)
        guard let decoded = try? JSONDecoder().decode(Members.self, from: raw), decoded.members.count <= 5_000,
              (decoded.membersEpoch ?? 0) >= 0 else {
            throw MessagingFailure.invalidResponse
        }
        return MessagingConversationMembers(members: decoded.members.map(\.personId), membersEpoch: decoded.membersEpoch)
    }

    static func validDeviceID(_ value: String) -> Bool {
        (10...32).contains(value.utf8.count) && value.utf8.allSatisfy { ($0 >= 65 && $0 <= 90) || ($0 >= 48 && $0 <= 57) }
    }

    private func request(scope: MessagingScope, deviceID: String, method: String, path: [String],
                         query: [URLQueryItem], body: Data?) async throws -> Data {
        guard Self.validDeviceID(deviceID), scope.apiBaseURL == baseURL.absoluteString,
              await DrivyAPIClient.permits(baseURL), let origin = baseURL.host else { throw MessagingFailure.contextChanged }
        try await verifyCurrent(scope)
        var url = baseURL
        for part in ["v1", "schools", scope.schoolID.uuidString, "messaging"] + path { url.appendPathComponent(part) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw MessagingFailure.invalidResponse }
        components.queryItems = query.isEmpty ? nil : query
        guard let target = components.url, target.host == origin else { throw MessagingFailure.invalidResponse }
        var bearer = try await token()
        for attempt in 0...1 {
            guard !bearer.isEmpty, bearer.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw MessagingFailure.accessChanged }
            try await verifyCurrent(scope)
            var request = URLRequest(url: target)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
            request.setValue(scope.accountID.uuidString.lowercased(), forHTTPHeaderField: "X-Drivy-Expected-Person-Id")
            request.setValue(String(scope.accessEpoch), forHTTPHeaderField: "X-Drivy-Expected-Access-Epoch")
            request.setValue(deviceID, forHTTPHeaderField: "X-Drivy-Device-Id")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            let response: SchoolHTTPResponse
            do { response = try await sendHTTP.send(request) }
            catch {
                if !(error is CancellationError) { diagnostics.recordIfEmpty(MessagingDiagnostics.network(path)) }
                throw error.unlessCancelled(MessagingFailure.unavailable)
            }
            try Task.checkCancellation()
            try await verifyCurrent(scope)
            guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw MessagingFailure.invalidResponse }
            if response.status == 401 && attempt == 0, await invalidate(bearer) { bearer = try await token(); continue }
            if !(200...299).contains(response.status), !(response.status == 401 && attempt == 0) {
                diagnostics.recordIfEmpty(MessagingDiagnostics.http(path, response.status))
            }
            if response.status == 409 {
                let code = String(decoding: response.data.prefix(4_096), as: UTF8.self)
                if code.contains("BACKUP_VERSION_CONFLICT") {
                    throw MessagingCryptoRelayFailure.backupVersionConflict
                }
                // Enregistrement refusé : aucun repli, l'appareil reste sans clé et rien ne part.
                if code.contains("DEVICE_LIMIT_REACHED") { throw MessagingCryptoRelayFailure.deviceLimitReached }
                throw MessagingCryptoRelayFailure.conflict
            }
            if response.status == 404 { throw MessagingCryptoRelayFailure.notFound }
            if response.status == 401 || response.status == 403 { throw MessagingFailure.accessChanged }
            guard (200...299).contains(response.status) else { throw MessagingFailure.unavailable }
            guard response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
                diagnostics.recordIfEmpty("H-\(MessagingDiagnostics.route(path))-TYPE")
                throw MessagingFailure.invalidResponse
            }
            do { return try Self.unwrap(response.data, scope: scope) }
            catch {
                diagnostics.recordIfEmpty("H-\(MessagingDiagnostics.route(path))-\(error as? MessagingFailure == .contextChanged ? "CTX" : "BODY")")
                throw error
            }
        }
        throw MessagingFailure.accessChanged
    }

    /// Vérifie `context` puis renvoie `data` tel quel (JSON Matrix brut).
    static func unwrap(_ bytes: Data, scope: MessagingScope) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let context = object["context"] as? [String: Any], let data = object["data"],
              let school = (context["schoolId"] as? String).flatMap(UUID.init(uuidString:)),
              let actor = (context["actorPersonId"] as? String).flatMap(UUID.init(uuidString:)),
              let epoch = context["accessEpoch"] as? Int else { throw MessagingFailure.invalidResponse }
        guard school == scope.schoolID, actor == scope.accountID, epoch == scope.accessEpoch else { throw MessagingFailure.contextChanged }
        guard JSONSerialization.isValidJSONObject(data),
              let raw = try? JSONSerialization.data(withJSONObject: data) else { throw MessagingFailure.invalidResponse }
        return raw
    }

    private func verifyCurrent(_ scope: MessagingScope) async throws {
        guard await currentScope() == scope else { throw MessagingFailure.contextChanged }
    }
}
