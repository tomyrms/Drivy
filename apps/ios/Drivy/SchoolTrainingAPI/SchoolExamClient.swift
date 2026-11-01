import Foundation

// Examens théorique et pratique d'une formation (#54) : extension hors canon, contrat dans apps/api/contracts/exams.json.
// Saisie manuelle du personnel ; l'élève lit les siens. Une date passée n'est jamais un résultat : le serveur le dit (`needsResult`).
// Les instants restent des chaînes ISO 8601 du serveur ; les dates se lisent par `SchoolLesson.date`.

struct SchoolExam: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable, CaseIterable { case theory = "THEORY", practical = "PRACTICAL" }
    enum Status: String, Sendable { case scheduled = "SCHEDULED", postponed = "POSTPONED", absent = "ABSENT", passed = "PASSED", failed = "FAILED" }
    struct Escort: Codable, Sendable, Equatable {
        let instructorMembershipId: UUID
        let startsAt: String
        let endsAt: String
    }

    let id: UUID
    let trainingId: UUID
    let kind: String
    let categoryCode: String
    let status: String
    let startsAt: String
    let timeZone: String
    let location: String
    let escort: Escort?
    let resultNote: String
    let resultRecordedAt: String?
    let postponedToExamId: UUID?
    /// Rang de la tentative dans son épreuve ; absent pour un examen reporté.
    let attempt: Int?
    /// Prévu et dont la date est passée : le résultat reste à renseigner, il n'est jamais déduit.
    let needsResult: Bool
    let version: Int
    let createdAt: String

    var examKind: Kind? { Kind(rawValue: kind) }
    var examStatus: Status? { Status(rawValue: status) }
    var date: Date? { SchoolLesson.date(startsAt) }
    var hasResult: Bool { examStatus == .passed || examStatus == .failed || examStatus == .absent }
}

struct SchoolExamSummary: Codable, Sendable, Equatable {
    let kind: String
    let passed: Bool
    let attempts: Int
    let scheduledExamId: UUID?
}

struct SchoolExamState: Codable, Sendable, Equatable {
    let trainingId: UUID
    /// Vrai pour l'administration et le moniteur affecté à la formation.
    let canManage: Bool
    let exams: [SchoolExam]
    let summary: [SchoolExamSummary]

    func summary(for kind: SchoolExam.Kind) -> SchoolExamSummary? { summary.first { $0.kind == kind.rawValue } }
    /// Une épreuve se prévoit tant qu'elle n'est ni réussie ni déjà prévue.
    func canSchedule(_ kind: SchoolExam.Kind) -> Bool {
        guard let value = summary(for: kind) else { return false }
        return !value.passed && value.scheduledExamId == nil
    }
}

/// Date, lieu et accompagnement facultatif d'un examen.
struct SchoolExamSchedule: Equatable, Sendable {
    struct Escort: Equatable, Sendable {
        var instructorMembershipID: UUID
        var startsAt: Date
        var endsAt: Date
    }
    var startsAt: Date
    var timeZone: String
    var location: String
    var escort: Escort?

    /// Identifie le geste : un nouvel essai identique rejoue la même opération, une saisie changée en ouvre une autre.
    var key: String {
        "\(startsAt.timeIntervalSince1970)|\(timeZone)|\(location)|\(escort.map { "\($0.instructorMembershipID)|\($0.startsAt.timeIntervalSince1970)|\($0.endsAt.timeIntervalSince1970)" } ?? "")"
    }
}

@MainActor
final class SchoolExamClient {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    func state(schoolID: UUID, trainingID: UUID) async throws -> SchoolExamState {
        let state: SchoolExamState = try await send(schoolID, ["trainings", trainingID.uuidString, "exams"], method: "GET", body: nil, operation: nil, version: nil, expected: 200)
        guard state.trainingId == trainingID else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    func create(schoolID: UUID, trainingID: UUID, operationID: UUID, kind: SchoolExam.Kind, schedule: SchoolExamSchedule) async throws -> SchoolExamState {
        let body = try encode(Body(operationId: operationID, kind: kind.rawValue, schedule: schedule))
        let state: SchoolExamState = try await send(schoolID, ["trainings", trainingID.uuidString, "exams"], method: "POST", body: body,
            operation: operationID, version: nil, expected: 201)
        guard state.trainingId == trainingID else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    func update(schoolID: UUID, exam: SchoolExam, operationID: UUID, schedule: SchoolExamSchedule, reason: String) async throws -> SchoolExamState {
        try await write(schoolID, exam, "update", Body(operationId: operationID, schedule: schedule, reason: reason), operationID)
    }

    func postpone(schoolID: UUID, exam: SchoolExam, operationID: UUID, schedule: SchoolExamSchedule, reason: String) async throws -> SchoolExamState {
        try await write(schoolID, exam, "postpone", Body(operationId: operationID, schedule: schedule, reason: reason), operationID)
    }

    func setResult(schoolID: UUID, exam: SchoolExam, operationID: UUID, result: SchoolExam.Status, note: String, reason: String) async throws -> SchoolExamState {
        try await write(schoolID, exam, "result", Body(operationId: operationID, reason: reason, result: result.rawValue, note: note), operationID)
    }

    private func write(_ schoolID: UUID, _ exam: SchoolExam, _ action: String, _ body: Body, _ operationID: UUID) async throws -> SchoolExamState {
        let state: SchoolExamState = try await send(schoolID, ["exams", exam.id.uuidString, action], method: "POST", body: try encode(body),
            operation: operationID, version: exam.version, expected: 200)
        guard state.trainingId == exam.trainingId else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    // MARK: Corps et refus

    private struct EscortBody: Encodable { let instructorMembershipId: UUID; let startsAt: String; let endsAt: String }
    /// Les champs absents ne sont pas envoyés : le serveur refuse toute clé qu'une commande ne connaît pas.
    private struct Body: Encodable {
        let operationId: UUID
        var kind: String?
        var startsAt: String?
        var timeZone: String?
        var location: String?
        var escort: EscortBody?
        var reason: String?
        var result: String?
        var note: String?

        init(operationId: UUID, kind: String? = nil, schedule: SchoolExamSchedule? = nil, reason: String? = nil, result: String? = nil, note: String? = nil) {
            self.operationId = operationId; self.kind = kind; self.reason = reason; self.result = result; self.note = note
            guard let schedule else { return }
            let iso = ISO8601DateFormatter()
            startsAt = iso.string(from: schedule.startsAt); timeZone = schedule.timeZone; location = schedule.location
            escort = schedule.escort.map { EscortBody(instructorMembershipId: $0.instructorMembershipID, startsAt: iso.string(from: $0.startsAt), endsAt: iso.string(from: $0.endsAt)) }
        }
    }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do { return try JSONEncoder().encode(value) } catch { throw SchoolPlanningFailure.invalidResponse }
    }

    /// Refus propres aux examens ; le reste suit la planification des leçons.
    static func failure(_ status: Int, _ code: String?, title: String? = nil) -> SchoolPlanningFailure {
        let messages = [
            "EXAM_ALREADY_SCHEDULED": "Une date est déjà prévue pour cette épreuve. Reporte-la ou renseigne son résultat.",
            "EXAM_ALREADY_PASSED": "Cette épreuve est déjà réussie. Corrige d’abord son résultat pour la replanifier.",
            "EXAM_CLOSED": "Cet examen n’est plus modifiable.",
            "EXAM_NOT_STARTED": "La date de l’examen n’est pas encore passée.",
            "EXAM_REASON_REQUIRED": "Indique le motif de la correction.",
            "EXAM_ESCORT_CONFLICT": "Le moniteur a déjà un rendez-vous pendant l’accompagnement.",
            "INVALID_EXAM_DATE": "Choisis une date d’examen récente ou à venir.",
            "INVALID_ESCORT": "L’accompagnement doit durer au plus 12 heures.",
            "INSTRUCTOR_NOT_ASSIGNED": "Le moniteur d’accompagnement doit être affecté à cette formation.",
            "TRAINING_NOT_ACTIVE": "La formation doit être active dans un dossier non archivé."
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
