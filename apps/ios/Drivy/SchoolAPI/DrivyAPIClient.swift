import Foundation

struct SchoolHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let url: URL
    let contentType: String?
}

protocol SchoolHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse
}

private final class NoAPIRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Aucun jeton n'est transmis à une URL de redirection, même sur le même hôte.
        completionHandler(nil)
    }
}

actor SchoolURLSessionTransport: SchoolHTTPTransport {
    private let session: URLSession
    static let maximumResponseBytes = 2 * 1_024 * 1_024

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoAPIRedirects(), delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> SchoolHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            throw SchoolAPIError.invalidResponse
        }
        guard http.expectedContentLength <= Int64(Self.maximumResponseBytes) else {
            throw SchoolAPIError.tooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumResponseBytes else { throw SchoolAPIError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return SchoolHTTPResponse(data: data, status: http.statusCode, url: url,
                                  contentType: http.value(forHTTPHeaderField: "Content-Type"))
    }
}

@MainActor
final class DrivyAPIClient: SchoolAPI {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource,
         transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL
        self.tokenSource = tokenSource
        self.transport = transport
    }

    func me() async throws -> SchoolPerson {
        let person: SchoolPerson = try await read(["v1", "me"])
        guard person.version > 0, person.memberships.allSatisfy({ $0.accessEpoch > 0 }),
              Set(person.memberships.map(\.schoolId)).count == person.memberships.count else {
            throw SchoolAPIError.invalidResponse
        }
        return person
    }

    func school(id: UUID) async throws -> SchoolDetails {
        let result: SchoolDetails = try await read(["v1", "schools", id.uuidString])
        guard result.id == id, result.schoolId == id, result.version > 0,
              result.configurationVersion > 0, TimeZone(identifier: result.timeZone) != nil else {
            throw SchoolAPIError.invalidResponse
        }
        return result
    }

    func learners(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> {
        var items = [URLQueryItem(name: "limit", value: "50")]
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        let page: SchoolPage<SchoolLearner> = try await read(["v1", "schools", schoolID.uuidString, "learners"], query: items)
        guard page.items.allSatisfy({ valid($0, schoolID: schoolID) }),
              Set(page.items.map(\.id)).count == page.items.count else { throw SchoolAPIError.invalidResponse }
        return page
    }

    func learner(schoolID: UUID, id: UUID) async throws -> SchoolLearner {
        let learner: SchoolLearner = try await read(["v1", "schools", schoolID.uuidString, "learners", id.uuidString])
        guard learner.id == id, valid(learner, schoolID: schoolID) else { throw SchoolAPIError.invalidResponse }
        return learner
    }

    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining> {
        var items = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "learnerId", value: learnerID.uuidString)]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        let page: SchoolPage<SchoolTraining> = try await read(["v1", "schools", schoolID.uuidString, "trainings"], query: items)
        guard page.items.allSatisfy({ valid($0, schoolID: schoolID) && $0.learnerId == learnerID }),
              Set(page.items.map(\.id)).count == page.items.count else { throw SchoolAPIError.invalidResponse }
        return page
    }

    func training(schoolID: UUID, id: UUID) async throws -> SchoolTraining {
        let training: SchoolTraining = try await read(["v1", "schools", schoolID.uuidString, "trainings", id.uuidString])
        guard training.id == id, valid(training, schoolID: schoolID) else { throw SchoolAPIError.invalidResponse }
        return training
    }

    private func valid(_ learner: SchoolLearner, schoolID: UUID) -> Bool {
        learner.schoolId == schoolID && learner.version > 0
    }

    private func valid(_ training: SchoolTraining, schoolID: UUID) -> Bool {
        training.schoolId == schoolID && training.version > 0 &&
        Self.isCivilDate(training.startedOn) && Self.isCivilDate(training.closedOn)
    }

    static func isCivilDate(_ text: String?) -> Bool {
        guard let text else { return true }
        guard text.utf8.count == 10 else { return false }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.utf8.allSatisfy({ (48...57).contains($0) }) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == year && actual.month == month && actual.day == day
    }

    private func read<Value: Decodable & Sendable>(_ path: [String], query: [URLQueryItem] = []) async throws -> Value {
        guard Self.permits(baseURL) else { throw SchoolAPIError.invalidConfiguration }
        var url = baseURL
        for component in path { url.appendPathComponent(component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SchoolAPIError.invalidConfiguration
        }
        if !query.isEmpty {
            components.queryItems = query
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let target = components.url else { throw SchoolAPIError.invalidConfiguration }
        let token = try await tokenSource.accessToken()
        try Task.checkCancellation()
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolAPIError.unauthorized }
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as SchoolAPIError { throw error }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw SchoolAPIError.unavailable }
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else {
            throw SchoolAPIError.invalidResponse
        }
        switch response.status {
        case 200: break
        case 401: throw SchoolAPIError.unauthorized
        case 403:
            let problem = try? JSONDecoder().decode(ProblemCode.self, from: response.data)
            throw problem?.code == "IDENTITY_NOT_LINKED" ? SchoolAPIError.identityNotLinked : .forbidden
        case 404: throw SchoolAPIError.notFound
        case 400:
            let problem = try? JSONDecoder().decode(ProblemCode.self, from: response.data)
            throw problem?.code == "INVALID_CURSOR" ? SchoolAPIError.invalidCursor : .invalidResponse
        case 429, 500...599: throw SchoolAPIError.unavailable
        default: throw SchoolAPIError.invalidResponse
        }
        guard response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
            throw SchoolAPIError.invalidResponse
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard Self.isTimestamp(envelope.serverTime) else {
                throw SchoolAPIError.invalidResponse
            }
            return envelope.data
        } catch { throw SchoolAPIError.invalidResponse }
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        let requestId: String
        let serverTime: String
    }
    private struct ProblemCode: Decodable { let code: String }

    private static func isTimestamp(_ value: String) -> Bool {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if format.date(from: value) != nil { return true }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: value) != nil
    }

    static func permits(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty, components.user == nil,
              components.password == nil, components.query == nil, components.fragment == nil else { return false }
        if components.scheme == "https" { return true }
        #if DEBUG && targetEnvironment(simulator)
        return components.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)
        #else
        return false
        #endif
    }
}
