import Foundation

// Examens théorique et pratique d'une formation (#54) : extension hors canon, contrat dans apps/api/contracts/exams.json.
// Saisie manuelle du personnel ; l'élève lit les siens. Une date passée n'est jamais un résultat : le serveur le dit (`needsResult`).
// Les instants restent des chaînes ISO 8601 du serveur ; les dates se lisent par `SchoolLesson.date`.
// Les écritures passent par la file chiffrée des commandes de l'école : l'intention est conservée sur l'appareil avant tout envoi,
// et rejouée à l'identique (même opération, même corps, même version) tant que l'école n'a pas répondu.

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
    /// Moniteur actif actuellement affecté à la formation, proposable à l'accompagnement.
    struct Candidate: Codable, Sendable, Equatable, Identifiable {
        let membershipId: UUID
        let displayName: String
        var id: UUID { membershipId }
    }

    let trainingId: UUID
    /// Vrai pour l'administration et le moniteur affecté à la formation.
    let canManage: Bool
    /// Vide pour qui ne peut pas gérer la formation.
    let escortCandidates: [Candidate]
    let exams: [SchoolExam]
    let summary: [SchoolExamSummary]

    func summary(for kind: SchoolExam.Kind) -> SchoolExamSummary? { summary.first { $0.kind == kind.rawValue } }
    /// Une épreuve se prévoit tant qu'elle n'est ni réussie ni déjà prévue.
    func canSchedule(_ kind: SchoolExam.Kind) -> Bool {
        guard let value = summary(for: kind) else { return false }
        return !value.passed && value.scheduledExamId == nil
    }
}

/// Un examen prévu de l'école, avec l'élève concerné : « à renseigner » pour le personnel, « à venir » pour l'élève.
struct SchoolExamListItem: Codable, Sendable, Equatable, Identifiable {
    let exam: SchoolExam
    let learnerId: UUID
    let learnerDisplayName: String
    var id: UUID { exam.id }
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
}

/// Corps d'une commande d'examen. Les champs absents ne sont pas envoyés : le serveur refuse toute clé qu'une commande ne connaît pas.
struct SchoolExamBody: Encodable, Sendable {
    private struct EscortBody: Encodable, Sendable { let instructorMembershipId: UUID; let startsAt: String; let endsAt: String }
    let operationId: UUID
    private var kind: String?
    private var startsAt: String?
    private var timeZone: String?
    private var location: String?
    private var escort: EscortBody?
    private var reason: String?
    private var result: String?
    private var note: String?

    private init(operationId: UUID) { self.operationId = operationId }

    static func create(operationID: UUID, kind: SchoolExam.Kind, schedule: SchoolExamSchedule) -> Self {
        var body = Self(operationId: operationID)
        body.kind = kind.rawValue; body.apply(schedule)
        return body
    }

    /// Modification ou report : même corps, route différente.
    static func reschedule(operationID: UUID, schedule: SchoolExamSchedule, reason: String) -> Self {
        var body = Self(operationId: operationID)
        body.reason = reason; body.apply(schedule)
        return body
    }

    static func result(operationID: UUID, result: SchoolExam.Status, note: String, reason: String) -> Self {
        var body = Self(operationId: operationID)
        body.result = result.rawValue; body.note = note; body.reason = reason
        return body
    }

    private mutating func apply(_ schedule: SchoolExamSchedule) {
        let iso = ISO8601DateFormatter()
        startsAt = iso.string(from: schedule.startsAt); timeZone = schedule.timeZone; location = schedule.location
        escort = schedule.escort.map { EscortBody(instructorMembershipId: $0.instructorMembershipID, startsAt: iso.string(from: $0.startsAt), endsAt: iso.string(from: $0.endsAt)) }
    }

    func encoded() throws -> Data {
        do { return try JSONEncoder().encode(self) } catch { throw SchoolPlanningFailure.invalidResponse }
    }
}

@MainActor
final class SchoolExamClient {
    let baseURL: URL
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

    enum Filter: String { case pendingResult = "PENDING_RESULT", upcoming = "UPCOMING" }

    /// Examens prévus de l'école dans le périmètre de lecture de l'appelant.
    func list(schoolID: UUID, filter: Filter) async throws -> [SchoolExamListItem] {
        struct Page: Decodable { let filter: String; let items: [SchoolExamListItem] }
        let page: Page = try await send(schoolID, ["exams"], query: [URLQueryItem(name: "filter", value: filter.rawValue)], method: "GET", body: nil,
            operation: nil, version: nil, expected: 200)
        guard page.filter == filter.rawValue, Set(page.items.map(\.id)).count == page.items.count else { throw SchoolPlanningFailure.invalidResponse }
        return page.items
    }

    /// Envoie ou rejoue une commande de la file : mêmes octets, même clé d'idempotence, même version à chaque essai. Une commande
    /// déjà enregistrée par l'école rend sa propre réponse, jamais un second effet.
    func replay(_ command: PendingSchoolCommand) async throws -> SchoolExamState {
        guard command.kind.isExam, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let object = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              UUID(uuidString: object["operationId"] as? String ?? "") == command.id,
              let trainingID = command.routeResourceID else { throw SchoolPlanningFailure.invalidResponse }
        let path: [String], expected: Int
        switch command.kind {
        case .createExam: path = ["trainings", trainingID.uuidString, "exams"]; expected = 201
        case .updateExam, .postponeExam, .setExamResult:
            guard let examID = command.resourceID else { throw SchoolPlanningFailure.invalidResponse }
            let action = command.kind == .updateExam ? "update" : command.kind == .postponeExam ? "postpone" : "result"
            path = ["exams", examID.uuidString, action]; expected = 200
        default: throw SchoolPlanningFailure.invalidResponse
        }
        let state: SchoolExamState = try await send(command.scope.schoolID, path, method: "POST", body: command.body, operation: command.id,
            version: command.resourceVersion > 0 ? command.resourceVersion : nil, expected: expected, scope: command.scope)
        guard state.trainingId == trainingID else { throw SchoolPlanningFailure.invalidResponse }
        return state
    }

    // MARK: Refus

    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }
    @MainActor private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
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

    private func send<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem] = [], method: String, body: Data?,
                                        operation: UUID?, version: Int?, expected: Int, scope: SchoolCommandScope? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolPlanningFailure.invalidResponse }
        var base = baseURL
        for part in ["v1", "schools", schoolID.uuidString] + path { base.appendPathComponent(part) }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw SchoolPlanningFailure.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SchoolPlanningFailure.invalidResponse }
        let token = try await accessToken()
        do { return try await perform(url, method: method, body: body, operation: operation, version: version, expected: expected, scope: scope, token: token) }
        catch SchoolPlanningFailure.unauthorized {
            guard !Task.isCancelled else { throw SchoolPlanningFailure.unauthorized }
            // Un seul renouvellement forcé, même opération et même clé d'idempotence (le 401 précède tout traitement).
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolPlanningFailure.unauthorized }
            let renewed = try await accessToken()
            guard renewed != token else { throw SchoolPlanningFailure.unauthorized }
            return try await perform(url, method: method, body: body, operation: operation, version: version, expected: expected, scope: scope, token: renewed)
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
                                           expected: Int, scope: SchoolCommandScope?, token: String) async throws -> Value {
        // Une commande conservée sur l'appareil ne part que sous le compte et l'adhésion qui l'ont écrite.
        if let scope {
            let person = try await DrivyAPIClient(baseURL: baseURL, tokenSource: PinnedToken(token), transport: transport).me()
            guard person.personId == scope.personID, person.memberships.contains(where: {
                $0.membershipId == scope.membershipID && $0.schoolId == scope.schoolID && $0.accessEpoch == scope.accessEpoch
            }) else { throw SchoolPlanningFailure.forbidden }
        }
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
