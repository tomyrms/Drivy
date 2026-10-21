import Foundation

struct SchoolHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let url: URL
    let contentType: String?
}

extension Error {
    /// Une requête interrompue parce que l’écran s’est fermé ou relancé : ce n’est pas une panne du réseau
    /// et elle ne doit jamais s’afficher comme telle.
    var isRequestCancellation: Bool { self is CancellationError || (self as? URLError)?.code == .cancelled }

    /// L’interruption reste une interruption ; toute autre panne devient l’erreur du domaine.
    func unlessCancelled(_ failure: any Error) -> any Error {
        if isRequestCancellation { return CancellationError() }
        return failure
    }
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
        #if DEBUG && targetEnvironment(simulator)
        if let fixture = await SchoolRootEntryFixture.current {
            return try await fixture.send(request)
        }
        #endif
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let url = http.url else {
            throw SchoolAPIError.invalidResponse
        }
        guard http.expectedContentLength <= Int64(Self.maximumResponseBytes) else {
            throw SchoolAPIError.tooLarge
        }
        var data = Data()
        // Taille annoncée et déjà bornée : une seule allocation au lieu de doublements successifs.
        if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
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
        try await learners(schoolID: schoolID, query: query, cursor: cursor, instructorMembershipID: nil)
    }

    /// La personne connectée, même administratrice, retrouve son seul dossier ; `ALL` inclut un dossier archivé.
    func ownLearners(schoolID: UUID) async throws -> SchoolPage<SchoolLearner> {
        try await learners(schoolID: schoolID, query: "", cursor: nil, instructorMembershipID: nil, status: "ALL", own: true)
    }

    func learners(schoolID: UUID, query: String, cursor: String?, instructorMembershipID: UUID?,
                  status: String? = nil, own: Bool = false, pageSize: Int = 50) async throws -> SchoolPage<SchoolLearner> {
        var items = [URLQueryItem(name: "limit", value: String(min(100, max(1, pageSize))))]
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        if own { items.append(URLQueryItem(name: "own", value: "true")) }
        if let instructorMembershipID { items.append(URLQueryItem(name: "instructorMembershipId", value: instructorMembershipID.uuidString)) }
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        let page: SchoolPage<SchoolLearner> = try await read(["v1", "schools", schoolID.uuidString, "learners"], query: items)
        guard page.items.allSatisfy({ valid($0, schoolID: schoolID) }),
              Set(page.items.map(\.id)).count == page.items.count else { throw SchoolAPIError.invalidResponse }
        return page
    }

    /// Au plus vingt pages de cent : au-delà, la lecture s’arrête plutôt que de boucler sur un curseur.
    func learnersToComplete(schoolID: UUID) async throws -> [SchoolLearner]? {
        var learners: [SchoolLearner] = []
        var cursor: String?
        var cursors = Set<String>()
        repeat {
            var items = [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "status", value: "ACTIVE"),
                         URLQueryItem(name: "requiresAction", value: "true")]
            if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page: SchoolPage<SchoolLearner> = try await read(["v1", "schools", schoolID.uuidString, "learners"], query: items)
            guard page.items.allSatisfy({ valid($0, schoolID: schoolID) }) else { throw SchoolAPIError.invalidResponse }
            learners += page.items
            if let next = page.nextCursor, !cursors.insert(next).inserted { throw SchoolAPIError.invalidCursor }
            cursor = page.nextCursor
        } while cursor != nil && cursors.count < 20
        return learners
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
        try await send(path, query: query, method: "GET", body: nil, ifMatch: nil)
    }

    func renameSelf(displayName: String, version: Int) async throws -> SchoolSelfProfile {
        let current = try await selfProfile()
        var edit = SchoolSelfProfileEdit(current)
        edit.displayName = displayName
        return try await saveSelfProfile(edit, version: version)
    }

    func selfProfile() async throws -> SchoolSelfProfile {
        do { return try await read(["v1", "me", "profile"]) }
        catch SchoolAPIError.notFound { throw SchoolSelfProfileFailure.unsupported }
    }

    func saveSelfProfile(_ edit: SchoolSelfProfileEdit, version: Int) async throws -> SchoolSelfProfile {
        let body = try JSONEncoder().encode(edit)
        let value: SchoolSelfProfile = try await send(["v1", "me", "profile"], query: [], method: "PATCH", body: body, ifMatch: version)
        guard value.version >= version, !value.displayName.isEmpty else { throw SchoolAPIError.invalidResponse }
        return value
    }

    func setSelfPhoto(_ jpeg: Data?, version: Int) async throws -> SchoolSelfProfile {
        let value: SchoolSelfProfile = try await send(["v1", "me", "profile", "photo"], query: [], method: jpeg == nil ? "DELETE" : "PUT",
            body: jpeg, ifMatch: version, contentType: "image/jpeg")
        guard value.version >= version else { throw SchoolAPIError.invalidResponse }
        return value
    }

    /// Octets JPEG bruts : la réponse n’est pas une enveloppe JSON. 404 : pas de photo (ou pas visible), les initiales s’affichent.
    func personPhoto(personID: UUID) async throws -> Data? {
        guard Self.permits(baseURL) else { throw SchoolAPIError.invalidConfiguration }
        var target = baseURL
        for part in ["v1", "people", personID.uuidString.lowercased(), "photo"] { target.appendPathComponent(part) }
        let token = try await accessToken()
        var request = URLRequest(url: target)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch let error where error.isRequestCancellation { throw CancellationError() }
        catch { throw SchoolAPIError.unavailable }
        switch response.status {
        case 200:
            guard response.contentType?.lowercased().hasPrefix("image/jpeg") == true, response.data.count <= 300_000,
                  response.data.starts(with: [0xFF, 0xD8]) else { throw SchoolAPIError.invalidResponse }
            return response.data
        case 404: return nil
        case 401: throw SchoolAPIError.unauthorized
        case 403: throw SchoolAPIError.forbidden
        default: throw SchoolAPIError.unavailable
        }
    }

    private func send<Value: Decodable & Sendable>(_ path: [String], query: [URLQueryItem], method: String,
                                                    body: Data?, ifMatch: Int?, contentType: String = "application/json") async throws -> Value {
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
        let token = try await accessToken()
        do { return try await perform(target, token: token, method: method, body: body, ifMatch: ifMatch, contentType: contentType) }
        catch SchoolAPIError.unauthorized {
            // Un premier 401 peut viser un jeton que l’appareil croit encore valable (horloge en retard, session
            // révoquée chez le fournisseur) : un seul renouvellement forcé et un seul nouvel essai avant de
            // conclure à une session expirée. Une source qui ne renouvelle rien garde le 401.
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolAPIError.unauthorized }
            let renewed = try await accessToken()
            guard renewed != token else { throw SchoolAPIError.unauthorized }
            return try await perform(target, token: renewed, method: method, body: body, ifMatch: ifMatch, contentType: contentType)
        }
    }

    private func accessToken() async throws -> String {
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolAPIError.unauthorized }
        catch let error where error.isRequestCancellation { throw CancellationError() }
        catch let error as SchoolAPIError { throw error }
        catch { throw SchoolAPIError.unavailable }
        try Task.checkCancellation()
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolAPIError.unauthorized }
        return token
    }

    private func perform<Value: Decodable & Sendable>(_ target: URL, token: String, method: String = "GET",
                                                       body: Data? = nil, ifMatch: Int? = nil, contentType: String = "application/json") async throws -> Value {
        var request = URLRequest(url: target)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let ifMatch { request.setValue("\"\(ifMatch)\"", forHTTPHeaderField: "If-Match") }
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
        case 404 where method != "GET": throw SchoolSelfProfileFailure.unsupported
        case 404: throw SchoolAPIError.notFound
        case 412 where method != "GET": throw SchoolSelfProfileFailure.changed
        case 400 where method != "GET": throw SchoolSelfProfileFailure.invalidName
        case 415 where method != "GET", 422 where method != "GET": throw SchoolSelfProfileFailure.invalidPhoto
        case 400:
            let problem = try? JSONDecoder().decode(ProblemCode.self, from: response.data)
            throw problem?.code == "INVALID_CURSOR" ? SchoolAPIError.invalidCursor : .invalidResponse
        case 408, 429, 500...599: throw SchoolAPIError.unavailable
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
