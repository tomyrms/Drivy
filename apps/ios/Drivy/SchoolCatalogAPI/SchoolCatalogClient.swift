import Foundation

/// Lecture du catalogue : offres, référentiels et procédures. Sa gestion vit sur le web.
@MainActor final class SchoolCatalogClient: SchoolCatalogAPI {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }
    func offerings(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolOffering> {
        let result: SchoolPage<SchoolOffering> = try await page(schoolID, ["offerings"], cursor: cursor)
        guard result.items.allSatisfy({ !$0.offeringKey.isEmpty && !$0.categoryCode.isEmpty && (1...480).contains($0.defaultDurationMinutes)
            && (0...9_007_199_254_740_991).contains($0.defaultPriceCents) }) else { throw SchoolCatalogFailure.invalidResponse }
        return result
    }
    func curricula(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolCurriculum> {
        try await page(schoolID, ["curricula"], cursor: cursor)
    }
    func policies(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolCatalogPolicy> {
        try await page(schoolID, ["policy-versions"], cursor: cursor)
    }
    private func page<Value: SchoolCatalogRecord>(_ schoolID: UUID, _ path: [String], cursor: String?,
        extraQuery: [URLQueryItem] = []) async throws -> SchoolPage<Value> {
        var query = extraQuery + [URLQueryItem(name: "limit", value: "100")]
        if let cursor {
            guard !cursor.isEmpty, cursor.utf8.count <= 6_000 else { throw SchoolCatalogFailure.invalidResponse }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let result: SchoolPage<Value> = try await request(schoolID, path, query: query)
        guard result.items.allSatisfy({ $0.schoolId == schoolID && $0.version > 0 }),
              Set(result.items.map(\.id)).count == result.items.count, result.nextCursor == nil || result.nextCursor != cursor else {
            throw SchoolCatalogFailure.invalidResponse
        }
        return result
    }
    private func request<Value: Decodable & Sendable>(_ schoolID: UUID, _ path: [String],
        query: [URLQueryItem] = []) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolCatalogFailure.invalidResponse }
        var url = baseURL
        for component in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolCatalogFailure.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolCatalogFailure.invalidResponse }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolCatalogFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolCatalogFailure.unauthorized }
        catch { throw error.unlessCancelled(SchoolCatalogFailure.unavailable) }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolCatalogFailure.unauthorized }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw error.unlessCancelled(SchoolCatalogFailure.unavailable) }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolCatalogFailure.invalidResponse }
        let media = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let problem: Problem?
        if media == "application/problem+json" { problem = try? JSONDecoder().decode(Problem.self, from: response.data) }
        else { problem = nil }
        guard response.status == 200 else { throw Self.failure(response.status, code: problem?.code) }
        guard media == "application/json" else { throw SchoolCatalogFailure.invalidResponse }
        do {
            let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !envelope.requestId.isEmpty, SchoolInvitation.date(envelope.serverTime) != nil else { throw SchoolCatalogFailure.invalidResponse }
            return envelope.data
        } catch { throw SchoolCatalogFailure.invalidResponse }
    }
    private static func failure(_ status: Int, code: String?) -> SchoolCatalogFailure {
        if status == 401 { return code == "REAUTH_REQUIRED" ? .reauthentication : .unauthorized }
        if status == 403 { return .forbidden }
        if status == 404 { return .notFound }
        if status == 429 || status >= 500 { return .unavailable }
        return .invalidResponse
    }
    private struct Problem: Decodable { let code: String }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
}
