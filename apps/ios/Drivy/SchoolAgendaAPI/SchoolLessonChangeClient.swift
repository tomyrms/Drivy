import Foundation

// Demandes de l'élève sur sa leçon (#52) : extension hors canon, contrat dans apps/api/contracts/lesson-change-requests.json.
// Une demande ne change ni la leçon ni son créneau : seul le personnel répond, par le déplacement ou l'annulation existants.
// Les instants restent des chaînes ISO 8601 du serveur ; les dates se lisent par `SchoolLesson.date`.

struct SchoolLessonChangeRequest: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case reschedule = "RESCHEDULE", cancel = "CANCEL" }
    enum Status: String, Sendable { case pending = "PENDING", accepted = "ACCEPTED", refused = "REFUSED", withdrawn = "WITHDRAWN", superseded = "SUPERSEDED" }

    let id: UUID
    let lessonId: UUID
    let kind: String
    let status: String
    let note: String
    /// Vrai pour la demande de l'appelant : le personnel lit la demande de l'élève, jamais l'inverse.
    let mine: Bool
    let late: Bool?
    let deadlineAt: String?
    let cancellationHours: Int?
    let policyVersionId: UUID?
    let resolvedAt: String?
    let resolutionNote: String?
    let version: Int
    let createdAt: String

    var requestKind: Kind? { Kind(rawValue: kind) }
    var requestStatus: Status? { Status(rawValue: status) }
    var isPending: Bool { requestStatus == .pending }
    var deadline: Date? { deadlineAt.flatMap(SchoolLesson.date) }
}

struct SchoolLessonChangeConditions: Codable, Sendable, Equatable {
    let policyVersionId: UUID?
    let policyVersion: Int?
    let cancellationPolicyText: String
    let cancellationHours: Int?
    let lateAction: String?
    let deadlineAt: String?
    let late: Bool?
    let canRequest: Bool
    let blockedReason: String?

    var deadline: Date? { deadlineAt.flatMap(SchoolLesson.date) }
}

struct SchoolLessonChangeState: Codable, Sendable, Equatable {
    let lessonId: UUID
    let conditions: SchoolLessonChangeConditions
    let requests: [SchoolLessonChangeRequest]

    /// La demande en attente, s'il y en a une : il n'y en a jamais plus d'une par leçon.
    var pending: SchoolLessonChangeRequest? { requests.first { $0.isPending } }
    /// La dernière réponse du personnel ou le dernier retrait, à rappeler à l'élève tant qu'aucune demande n'est en attente.
    var lastClosed: SchoolLessonChangeRequest? { pending == nil ? requests.first : nil }
}

struct SchoolLessonChangeInboxItem: Codable, Sendable, Equatable, Identifiable {
    struct Lesson: Codable, Sendable, Equatable {
        let id: UUID
        let plannedStart: String
        let plannedEnd: String
        let timeZone: String
        let version: Int
        let instructorMembershipId: UUID
        let learnerDisplayName: String
    }
    let request: SchoolLessonChangeRequest
    let lesson: Lesson
    var id: UUID { request.id }
}

@MainActor
final class SchoolLessonChangeClient {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    /// Conditions de la leçon et demandes, pour l'élève comme pour le personnel qui la gère.
    func state(schoolID: UUID, lessonID: UUID) async throws -> SchoolLessonChangeState {
        let state: SchoolLessonChangeState = try await send(schoolID, ["lessons", lessonID.uuidString, "change-requests"],
            method: "GET", body: nil, operation: nil, version: nil, expected: 200)
        guard state.lessonId == lessonID else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    /// Boîte du personnel : demandes en attente sur des leçons encore planifiées.
    func inbox(schoolID: UUID) async throws -> [SchoolLessonChangeInboxItem] {
        struct Items: Decodable { let items: [SchoolLessonChangeInboxItem] }
        let result: Items = try await send(schoolID, ["lesson-change-requests"], method: "GET", body: nil, operation: nil, version: nil, expected: 200)
        guard Set(result.items.map(\.id)).count == result.items.count else { throw SchoolPlanningFailure.invalidResponse }
        return result.items
    }

    /// Même `operationID` à chaque nouvel essai d'un même geste : une réponse perdue ne crée jamais une seconde demande.
    func create(schoolID: UUID, lessonID: UUID, operationID: UUID, kind: SchoolLessonChangeRequest.Kind, note: String) async throws -> SchoolLessonChangeState {
        let body = try encode(CreateBody(operationId: operationID, kind: kind.rawValue, note: note))
        let state: SchoolLessonChangeState = try await send(schoolID, ["lessons", lessonID.uuidString, "change-requests"],
            method: "POST", body: body, operation: operationID, version: nil, expected: 201)
        guard state.lessonId == lessonID else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    func withdraw(schoolID: UUID, request: SchoolLessonChangeRequest, operationID: UUID) async throws -> SchoolLessonChangeState {
        let body = try encode(OperationBody(operationId: operationID))
        let state: SchoolLessonChangeState = try await send(schoolID, ["lesson-change-requests", request.id.uuidString, "withdraw"],
            method: "POST", body: body, operation: operationID, version: request.version, expected: 200)
        guard state.lessonId == request.lessonId else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    func refuse(schoolID: UUID, request: SchoolLessonChangeRequest, operationID: UUID, note: String) async throws -> SchoolLessonChangeState {
        let body = try encode(RefuseBody(operationId: operationID, note: note.isEmpty ? nil : note))
        let state: SchoolLessonChangeState = try await send(schoolID, ["lesson-change-requests", request.id.uuidString, "refuse"],
            method: "POST", body: body, operation: operationID, version: request.version, expected: 200)
        guard state.lessonId == request.lessonId else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    // MARK: Corps et refus

    private struct OperationBody: Encodable { let operationId: UUID }
    private struct CreateBody: Encodable { let operationId: UUID; let kind: String; let note: String }
    private struct RefuseBody: Encodable { let operationId: UUID; let note: String? }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do { return try JSONEncoder().encode(body) } catch { throw SchoolPlanningFailure.invalidResponse }
    }

    /// Refus propres aux demandes ; le reste suit la planification des leçons.
    static func failure(_ status: Int, _ code: String?, title: String? = nil) -> SchoolPlanningFailure {
        let messages = [
            "LESSON_CHANGE_REQUEST_PENDING": "Une demande est déjà en attente pour cette leçon.",
            "LESSON_CHANGE_REQUEST_CLOSED": "Cette demande est déjà traitée.",
            "LESSON_CHANGE_REQUEST_KIND": "Cette demande ne porte pas sur cette action.",
            "LESSON_IN_PAST": "Le début de cette leçon est passé.",
            "LESSON_CLOSED": "Cette leçon n’est plus planifiée.",
            "LESSON_STARTED": "Cette leçon est déjà commencée."
        ]
        if (400...499).contains(status), let code, let message = messages[code] { return .rejected(message) }
        return SchoolPlanningClient.failure(status, code, title: title)
    }

    // MARK: Transport

    private func send<Value: Decodable>(_ schoolID: UUID, _ path: [String], method: String, body: Data?,
                                        operation: UUID?, version: Int?, expected: Int) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolPlanningFailure.invalidResponse }
        var url = baseURL
        for part in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(part) }
        let token = try await accessToken()
        do { return try await perform(url, method: method, body: body, operation: operation, version: version, expected: expected, token: token) }
        catch SchoolPlanningFailure.unauthorized {
            guard !Task.isCancelled else { throw SchoolPlanningFailure.unauthorized }
            // Un seul renouvellement forcé, même opération et même clé d'idempotence (le 401 précède tout traitement).
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolPlanningFailure.unauthorized }
            let renewed = try await accessToken()
            guard renewed != token else { throw SchoolPlanningFailure.unauthorized }
            return try await perform(url, method: method, body: body, operation: operation, version: version, expected: expected, token: renewed)
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

    private func perform<Value: Decodable>(_ target: URL, method: String, body: Data?, operation: UUID?, version: Int?,
                                           expected: Int, token: String) async throws -> Value {
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
        if let operation { request.setValue(operation.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        if let version { request.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match") }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) } catch { throw error.unlessCancelled(SchoolPlanningFailure.unavailable) }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolPlanningFailure.invalidResponse }
        // Un refus d'accès reçu reste connu même si l'appelant a annulé sa lecture.
        if [401, 403, 404].contains(response.status) { throw SchoolPlanningClient.failure(response.status, nil) }
        try Task.checkCancellation()
        let contentType = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == expected else {
            let problem = contentType == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data)) : nil
            throw Self.failure(response.status, problem?.code, title: problem?.title)
        }
        guard contentType == "application/json" else { throw SchoolPlanningFailure.invalidResponse }
        do {
            let result = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !result.requestId.isEmpty, SchoolLesson.date(result.serverTime) != nil else { throw SchoolPlanningFailure.invalidResponse }
            return result.data
        } catch { throw SchoolPlanningFailure.invalidResponse }
    }
}
