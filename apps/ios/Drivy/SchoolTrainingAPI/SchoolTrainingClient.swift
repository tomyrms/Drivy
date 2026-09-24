import Foundation

/// Read-only projections for a formation. Mutations keep the existing catalogue outbox protocol.
@MainActor final class SchoolTrainingClient {
    let baseURL: URL
    let reader: DrivyAPIClient
    let catalog: SchoolCatalogClient
    let reports: SchoolLessonReportClient
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        catalog = SchoolCatalogClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        reports = SchoolLessonReportClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }

    func checkScope(_ scope: SchoolCommandScope, membership: SchoolMembership) async throws {
        let person = try await reader.me()
        guard scope.apiBaseURL == baseURL.absoluteString, person.personId == scope.personID,
              let current = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
              current.schoolId == scope.schoolID, current.accessEpoch == scope.accessEpoch,
              Set(current.roles) == Set(membership.roles), Set(current.grants) == Set(membership.grants) else {
            throw SchoolAPIError.forbidden
        }
    }

    func lessons(schoolID: UUID, trainingID: UUID, cursor: String?) async throws -> SchoolPage<SchoolLesson> {
        var query = [URLQueryItem(name: "trainingId", value: trainingID.uuidString), URLQueryItem(name: "limit", value: "100")]
        if let cursor {
            guard !cursor.isEmpty, cursor.utf8.count <= 6_000 else { throw SchoolAPIError.invalidResponse }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let page: SchoolPage<SchoolLesson> = try await read(schoolID, ["lessons"], query: query)
        guard Set(page.items.map(\.id)).count == page.items.count, page.nextCursor == nil || page.nextCursor != cursor,
              page.items.allSatisfy({ lesson in
                  lesson.schoolId == schoolID && lesson.trainingId == trainingID && lesson.version > 0
                    && lesson.startsAt != nil && lesson.endsAt != nil && lesson.endsAt! > lesson.startsAt!
                    && TimeZone(identifier: lesson.timeZone) != nil && lesson.publicationVersion >= 0
                    && lesson.priceCentsSnapshot >= 0 && lesson.priceCentsSnapshot <= 9_007_199_254_740_991
              }) else { throw SchoolAPIError.invalidResponse }
        return page
    }

    func revision(schoolID: UUID, id: UUID) async throws -> SchoolReportRevision {
        let value: SchoolReportRevision = try await read(schoolID, ["report-revisions", id.uuidString])
        guard value.id == id, value.schoolId == schoolID, value.version > 0, value.sequence > 0,
              SchoolLesson.date(value.publishedAt) != nil, Set(value.observations.map(\.id)).count == value.observations.count,
              value.observations.allSatisfy({ ["DISCOVERING", "GUIDED", "INDEPENDENT"].contains($0.level) && !$0.context.isEmpty }) else {
            throw SchoolAPIError.invalidResponse
        }
        return value
    }

    func collect<Value: SchoolCatalogRecord>(_ fetch: (String?) async throws -> SchoolPage<Value>) async throws -> [Value] {
        var values: [Value] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            try Task.checkCancellation()
            let page = try await fetch(cursor)
            guard values.count + page.items.count <= 10_000,
                  Set(values.map(\.id)).isDisjoint(with: Set(page.items.map(\.id))) else { throw SchoolAPIError.invalidResponse }
            values.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolAPIError.invalidResponse }
        } while cursor != nil
        return values
    }

    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: UUID; let serverTime: String }
    private func read<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem] = []) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolAPIError.invalidConfiguration }
        var url = baseURL
        for part in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(part) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolAPIError.invalidConfiguration }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolAPIError.invalidConfiguration }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolAPIError.unauthorized }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolAPIError.unauthorized }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SchoolAPIError.unavailable }
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolAPIError.invalidResponse }
        switch response.status {
        case 200: break
        case 401: throw SchoolAPIError.unauthorized
        case 403: throw SchoolAPIError.forbidden
        case 404: throw SchoolAPIError.notFound
        case 429, 500...599: throw SchoolAPIError.unavailable
        default: throw SchoolAPIError.invalidResponse
        }
        guard response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
            throw SchoolAPIError.invalidResponse
        }
        do {
            let value = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard SchoolLesson.date(value.serverTime) != nil else { throw SchoolAPIError.invalidResponse }
            return value.data
        } catch { throw SchoolAPIError.invalidResponse }
    }
}

enum SchoolTrainingAccess {
    static func isRevoked(_ error: Error) -> Bool {
        error as? SchoolAPIError == .unauthorized || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .identityNotLinked
            || error as? SchoolCatalogFailure == .unauthorized || error as? SchoolCatalogFailure == .forbidden
            || error as? SchoolReportFailure == .unauthorized || error as? SchoolReportFailure == .forbidden
    }
    static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Ces informations sont momentanément indisponibles."
    }
}
