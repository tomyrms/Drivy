import Foundation

// Cours collectifs (#38) : extension hors canon, contrat dans apps/api/src/courses.ts.
// Les instants restent des chaînes ISO 8601 du serveur ; les dates se lisent par `SchoolLesson.date`.

struct SchoolCourseType: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID?
    let stableKey: String?
    let title: String
    let description: String
    let version: Int
    let predefined: Bool
}

struct SchoolCoursePolicy: Codable, Sendable, Equatable {
    let version: Int
    let selfCancelHours: Int
    let offerResponseMinutes: Int?
}

struct SchoolCourseInstructor: Codable, Sendable, Equatable, Identifiable {
    let membershipId: UUID
    let displayName: String
    var id: UUID { membershipId }
}

struct SchoolCourseCatalogue: Codable, Sendable, Equatable {
    let schoolId: UUID
    let canManage: Bool
    let types: [SchoolCourseType]
    let policy: SchoolCoursePolicy
    let instructors: [SchoolCourseInstructor]
}

struct SchoolCourseOccurrence: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let position: Int
    let startsAt: String, endsAt: String
    let timeZone: String
    let instructorMembershipId: UUID
    let instructorDisplayName: String
    let attendanceRequired: Bool
    var start: Date? { SchoolLesson.date(startsAt) }
    var end: Date? { SchoolLesson.date(endsAt) }
}

struct SchoolCourseSeries: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable { case draft = "DRAFT", published = "PUBLISHED", cancelled = "CANCELLED", closed = "CLOSED" }
    let id: UUID, schoolId: UUID
    let version: Int
    let status: Status
    let typeId: UUID
    let typeTitle: String
    let title: String, description: String, location: String, conditions: String
    let teachingLanguage: String?
    let responsibleMembershipId: UUID
    let responsibleDisplayName: String
    let capacity: Int, seatsTaken: Int, remainingSeats: Int
    let minParticipants: Int?
    let policyVersion: Int
    let selfCancelHours: Int
    let selfCancellationDeadline: String
    let firstStartsAt: String, lastEndsAt: String
    let totalMinutes: Int
    let publishedAt: String?
    let occurrences: [SchoolCourseOccurrence]
    let canManage: Bool

    var isDraft: Bool { status == .draft }
}

/// Une séance saisie, telle qu’envoyée au serveur.
struct SchoolCourseOccurrenceInput: Codable, Sendable, Equatable {
    let startsAt: String, endsAt: String
    let instructorMembershipId: UUID
    let attendanceRequired: Bool
}

/// Corps de POST et PUT `course-series` : `teachingLanguage` et `minParticipants` partent en `null` explicite.
struct SchoolCourseSeriesBody: Encodable, Sendable, Equatable {
    let operationId: UUID
    let typeId: UUID
    let title: String, description: String, location: String, conditions: String
    let teachingLanguage: String?
    let responsibleMembershipId: UUID
    let capacity: Int
    let minParticipants: Int?
    let timeZone: String
    let occurrences: [SchoolCourseOccurrenceInput]

    private enum CodingKeys: String, CodingKey {
        case operationId, typeId, title, description, location, conditions, teachingLanguage, responsibleMembershipId,
             capacity, minParticipants, timeZone, occurrences
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId, forKey: .operationId); try values.encode(typeId, forKey: .typeId)
        try values.encode(title, forKey: .title); try values.encode(description, forKey: .description)
        try values.encode(location, forKey: .location); try values.encode(conditions, forKey: .conditions)
        try values.encode(teachingLanguage, forKey: .teachingLanguage)
        try values.encode(responsibleMembershipId, forKey: .responsibleMembershipId)
        try values.encode(capacity, forKey: .capacity); try values.encode(minParticipants, forKey: .minParticipants)
        try values.encode(timeZone, forKey: .timeZone); try values.encode(occurrences, forKey: .occurrences)
    }
}

struct SchoolCourseTypeBody: Encodable, Sendable, Equatable { let operationId: UUID; let title: String; let description: String }
struct SchoolCoursePublishBody: Encodable, Sendable, Equatable { let operationId: UUID }
struct SchoolCourseCapacityBody: Encodable, Sendable, Equatable { let operationId: UUID; let capacity: Int }

@MainActor final class SchoolCourseClient {
    let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    func catalogue(schoolID: UUID) async throws -> SchoolCourseCatalogue {
        let result: SchoolCourseCatalogue = try await request(schoolID, ["course-catalogue"])
        guard result.schoolId == schoolID, result.policy.selfCancelHours >= 0,
              result.types.allSatisfy({ $0.version > 0 && ($0.schoolId == nil || $0.schoolId == schoolID) }),
              Set(result.types.map(\.id)).count == result.types.count else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func series(schoolID: UUID, from: Date, to: Date) async throws -> [SchoolCourseSeries] {
        let iso = ISO8601DateFormatter()
        let page: Items = try await request(schoolID, ["course-series"], query: [
            URLQueryItem(name: "from", value: iso.string(from: from)), URLQueryItem(name: "to", value: iso.string(from: to))])
        guard page.items.allSatisfy({ Self.valid($0, schoolID: schoolID) }),
              Set(page.items.map(\.id)).count == page.items.count else { throw SchoolPlanningFailure.invalidResponse }
        return page.items
    }
    func series(schoolID: UUID, id: UUID) async throws -> SchoolCourseSeries {
        let result: SchoolCourseSeries = try await request(schoolID, ["course-series", id.uuidString])
        guard result.id == id, Self.valid(result, schoolID: schoolID) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func createType(schoolID: UUID, body: SchoolCourseTypeBody) async throws -> SchoolCourseType {
        let result: SchoolCourseType = try await command(schoolID, ["course-types"], method: "POST", body: body, operation: body.operationId, version: nil)
        guard result.schoolId == schoolID, !result.predefined, result.version > 0 else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    /// Création (version `nil`) ou réécriture d’un brouillon (`If-Match`).
    func save(schoolID: UUID, seriesID: UUID?, version: Int?, body: SchoolCourseSeriesBody) async throws -> SchoolCourseSeries {
        let path = seriesID.map { ["course-series", $0.uuidString] } ?? ["course-series"]
        let result: SchoolCourseSeries = try await command(schoolID, path, method: seriesID == nil ? "POST" : "PUT", body: body,
            operation: body.operationId, version: seriesID == nil ? nil : version)
        guard Self.valid(result, schoolID: schoolID), seriesID == nil || result.id == seriesID, result.isDraft else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func publish(schoolID: UUID, seriesID: UUID, version: Int, operationID: UUID) async throws -> SchoolCourseSeries {
        let result: SchoolCourseSeries = try await command(schoolID, ["course-series", seriesID.uuidString, "publish"], method: "POST",
            body: SchoolCoursePublishBody(operationId: operationID), operation: operationID, version: version)
        guard result.id == seriesID, Self.valid(result, schoolID: schoolID), result.status == .published else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func changeCapacity(schoolID: UUID, seriesID: UUID, version: Int, operationID: UUID, capacity: Int) async throws -> SchoolCourseSeries {
        let result: SchoolCourseSeries = try await command(schoolID, ["course-series", seriesID.uuidString, "capacity"], method: "POST",
            body: SchoolCourseCapacityBody(operationId: operationID, capacity: capacity), operation: operationID, version: version)
        guard result.id == seriesID, Self.valid(result, schoolID: schoolID), result.capacity == capacity else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }

    static func valid(_ series: SchoolCourseSeries, schoolID: UUID) -> Bool {
        guard series.schoolId == schoolID, series.version > 0, (1...200).contains(series.capacity),
              series.seatsTaken >= 0, series.remainingSeats >= 0, !series.occurrences.isEmpty else { return false }
        return series.occurrences.allSatisfy { occurrence in
            guard let start = occurrence.start, let end = occurrence.end else { return false }
            return end > start && TimeZone(identifier: occurrence.timeZone) != nil
        }
    }

    /// Refus propres aux cours ; le reste suit la planification des leçons.
    static func failure(_ status: Int, _ code: String?, title: String? = nil) -> SchoolPlanningFailure {
        let messages = [
            "COURSE_ACCESS_REQUIRED": "Tu n’as pas le droit de gérer les cours de cette école.",
            "COURSE_INSTRUCTOR_CONFLICT": "Un moniteur a déjà un rendez-vous pendant une séance. Le brouillon est conservé.",
            "COURSE_OCCURRENCES_OVERLAP": "Deux séances de ce cours se chevauchent.",
            "COURSE_OCCURRENCES_REQUIRED": "Ajoute au moins une séance.",
            "COURSE_IN_PAST": "La première séance est déjà passée.",
            "COURSE_NOT_DRAFT": "Ce cours est déjà publié.",
            "COURSE_TYPE_UNKNOWN": "Choisis un type de cours de l’école.",
            "COURSE_TYPE_EXISTS": "Un type de cours porte déjà ce nom.",
            "COURSE_CAPACITY_BELOW_TAKEN": "La capacité ne peut pas descendre sous les places déjà prises.",
            "COURSE_CAPACITY_BELOW_MINIMUM": "La capacité doit rester au moins égale au minimum.",
            "INSTRUCTOR_NOT_ACTIVE": "Choisis un moniteur actif de l’école.",
            "RESPONSIBLE_NOT_ACTIVE": "Choisis un responsable actif de l’école."
        ]
        if (400...499).contains(status), let code, let message = messages[code] { return .rejected(message) }
        return SchoolPlanningClient.failure(status, code, title: title)
    }

    private struct Items: Decodable { let items: [SchoolCourseSeries] }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }

    private func request<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem] = []) async throws -> Value {
        try await send(schoolID, path, query: query, method: "GET", body: nil, operation: nil, version: nil, expected: 200)
    }
    private func command<Value: Decodable, Body: Encodable>(_ schoolID: UUID, _ path: [String], method: String, body: Body,
                                                            operation: UUID, version: Int?) async throws -> Value {
        let data: Data
        do { data = try JSONEncoder().encode(body) } catch { throw SchoolPlanningFailure.invalidResponse }
        // Une création répond 201, une commande sur une ressource existante 200 ; la rejouer rend la même réponse.
        let expected = method == "POST" && version == nil ? 201 : 200
        return try await send(schoolID, path, query: [], method: method, body: data, operation: operation, version: version, expected: expected)
    }
    private func send<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem], method: String, body: Data?,
                                        operation: UUID?, version: Int?, expected: Int) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolPlanningFailure.invalidResponse }
        var url = baseURL
        for part in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(part) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolPlanningFailure.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolPlanningFailure.invalidResponse }
        let token = try await accessToken()
        do { return try await perform(target, method: method, body: body, operation: operation, version: version, expected: expected, token: token) }
        catch SchoolPlanningFailure.unauthorized {
            // Un seul renouvellement forcé, même opération et même clé d’idempotence (le 401 précède tout traitement).
            guard await tokenSource.invalidateAccessToken(token) else { throw SchoolPlanningFailure.unauthorized }
            let renewed = try await accessToken()
            guard renewed != token else { throw SchoolPlanningFailure.unauthorized }
            return try await perform(target, method: method, body: body, operation: operation, version: version, expected: expected, token: renewed)
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
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolPlanningFailure.invalidResponse }
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
