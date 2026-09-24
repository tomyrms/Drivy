import Foundation

struct SchoolLesson: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let schoolId: UUID
    let version: Int
    let trainingId: UUID
    let learnerId: UUID
    let instructorMembershipId: UUID
    let plannedStart: String
    let plannedEnd: String
    let timeZone: String
    let meetingPoint: String
    let status: String
    let priceCentsSnapshot: Int64
    let bufferMinutesSnapshot: Int
    let actualStart: String?
    let actualEnd: String?
    let permitWarning: Bool
    let publicationVersion: Int
    let currentPublishedRevisionId: UUID?
    let commercialRevisionVersion: Int

    var startsAt: Date? { Self.date(plannedStart) }
    var endsAt: Date? { Self.date(plannedEnd) }
    var durationMinutes: Int { guard let start = startsAt, let end = endsAt else { return 0 }; return Int(end.timeIntervalSince(start) / 60) }
    var statusLabel: String {
        switch status {
        case "PLANNED": "Planifiée"
        case "COMPLETED": "Terminée"
        case "CANCELLED": "Annulée"
        case "NO_SHOW": "Absence"
        default: "À vérifier"
        }
    }
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum SchoolAgendaFailure: Error, LocalizedError {
    case unavailable, authentication, forbidden, invalidResponse
    var errorDescription: String? {
        switch self {
        case .unavailable: "L’agenda est momentanément indisponible. Réessayez dans quelques instants."
        case .authentication: "Reconnectez-vous pour retrouver votre agenda."
        case .forbidden: "Votre accès à cet agenda a changé. Actualisez votre école."
        case .invalidResponse: "L’agenda n’a pas pu être chargé correctement."
        }
    }
}

@MainActor
final class SchoolAgendaClient {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    var planningClient: SchoolPlanningClient { SchoolPlanningClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport) }
    var reportClient: SchoolLessonReportClient { SchoolLessonReportClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport) }
    var captureClient: SchoolCaptureClient { SchoolCaptureClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport) }
    var reader: any SchoolAPI { DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport) }
    func scope(person: SchoolPerson, membership: SchoolMembership) -> SchoolCommandScope {
        SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: baseURL.absoluteString)
    }

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    func lessons(schoolID: UUID, from: Date, to: Date, cursor: String?) async throws -> SchoolPage<SchoolLesson> {
        let iso = ISO8601DateFormatter()
        var query = [URLQueryItem(name: "from", value: iso.string(from: from)), URLQueryItem(name: "to", value: iso.string(from: to)), URLQueryItem(name: "limit", value: "100")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let result: SchoolPage<SchoolLesson> = try await read(["v1", "schools", schoolID.uuidString, "lessons"], query: query)
        guard result.items.allSatisfy({ valid($0, schoolID: schoolID) }), Set(result.items.map(\.id)).count == result.items.count else { throw SchoolAgendaFailure.invalidResponse }
        return result
    }

    func lesson(schoolID: UUID, id: UUID) async throws -> SchoolLesson {
        let lesson: SchoolLesson = try await read(["v1", "schools", schoolID.uuidString, "lessons", id.uuidString])
        guard lesson.id == id, valid(lesson, schoolID: schoolID) else { throw SchoolAgendaFailure.invalidResponse }
        return lesson
    }

    private func valid(_ lesson: SchoolLesson, schoolID: UUID) -> Bool {
        guard lesson.schoolId == schoolID, lesson.version > 0, lesson.commercialRevisionVersion > 0,
              lesson.priceCentsSnapshot >= 0, lesson.priceCentsSnapshot <= 9_007_199_254_740_991,
              TimeZone(identifier: lesson.timeZone) != nil, let start = lesson.startsAt, let end = lesson.endsAt else { return false }
        return end > start
    }

    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: UUID; let serverTime: String }
    private func read<Value: Decodable>(_ path: [String], query: [URLQueryItem] = []) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolAgendaFailure.invalidResponse }
        var url = baseURL
        for part in path { url.appendPathComponent(part) }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolAgendaFailure.invalidResponse }
        if !query.isEmpty { parts.queryItems = query }
        guard let target = parts.url else { throw SchoolAgendaFailure.invalidResponse }
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let token = try await tokenSource.accessToken()
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolAgendaFailure.authentication }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolAgendaFailure.invalidResponse }
        if response.status == 401 { throw SchoolAgendaFailure.authentication }
        if response.status == 403 { throw SchoolAgendaFailure.forbidden }
        guard response.status == 200 else { throw SchoolAgendaFailure.unavailable }
        guard response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else { throw SchoolAgendaFailure.invalidResponse }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: response.data).data }
        catch { throw SchoolAgendaFailure.invalidResponse }
    }
}
