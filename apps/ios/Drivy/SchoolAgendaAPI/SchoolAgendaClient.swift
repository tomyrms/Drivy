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
    /// Extensions de lecture (hors canon) : absentes d’un serveur plus ancien.
    var learnerDisplayName: String? = nil
    var instructorDisplayName: String? = nil
    /// Sélection commerciale acceptée à la réservation ; lue seulement pour ne pas redemander des conditions déjà acceptées.
    var commercialSelection: SchoolLessonCommercialSelection? = nil
    /// Trajet de la leçon tel que le serveur le montre à ce lecteur ; absent d’un serveur plus ancien.
    var captureSummary: SchoolLessonCaptureSummary? = nil

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
    /// Noms fournis avec la leçon, s’ils existent : aucun nom n’est déduit d’une liste partielle.
    var providedLearnerName: String? { Self.name(learnerDisplayName) }
    var providedInstructorName: String? { Self.name(instructorDisplayName) }
    private static func name(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 200 else { return nil }
        return text
    }
}

/// Résumé du trajet joint à la leçon. `syncState` et `publicationState` gardent les valeurs brutes du serveur
/// (`SchoolCaptureSession.SyncState`, `.PublicationState`, plus « NONE » sans trajet) : une valeur inconnue
/// ne doit pas empêcher de lire la leçon.
struct SchoolLessonCaptureSummary: Codable, Sendable, Equatable {
    let hasCapture: Bool
    let syncState: String?
    let publicationState: String
}

/// Lecture tolérante : un champ absent ou d’une autre forme n’empêche jamais de lire la leçon.
struct SchoolLessonCommercialSelection: Codable, Sendable, Equatable {
    var serviceProductVersionId: UUID?
    var acceptedTermsVersionId: UUID?
    enum CodingKeys: String, CodingKey { case serviceProductVersionId, acceptedTermsVersionId }
    init(serviceProductVersionId: UUID? = nil, acceptedTermsVersionId: UUID? = nil) {
        self.serviceProductVersionId = serviceProductVersionId; self.acceptedTermsVersionId = acceptedTermsVersionId
    }
    init(from decoder: any Decoder) throws {
        let values = try? decoder.container(keyedBy: CodingKeys.self)
        serviceProductVersionId = try? values?.decodeIfPresent(UUID.self, forKey: .serviceProductVersionId)
        acceptedTermsVersionId = try? values?.decodeIfPresent(UUID.self, forKey: .acceptedTermsVersionId)
    }
}

/// Les leçons se lisent aussi par pages génériques (dernier lieu de rendez-vous, conditions déjà acceptées).
extension SchoolLesson: SchoolCatalogRecord {}

enum SchoolAgendaFailure: Error, LocalizedError {
    case unavailable, authentication, forbidden, invalidResponse
    var errorDescription: String? {
        switch self {
        case .unavailable: "L’agenda est momentanément indisponible. Réessaie dans quelques instants."
        case .authentication: "Reconnecte-toi pour retrouver ton agenda."
        case .forbidden: "Ton accès à cet agenda a changé. Actualise ton école."
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
    var observationClient: SchoolObservationClient { SchoolObservationClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport) }
    var reader: any SchoolAPI { DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport) }
    func scope(person: SchoolPerson, membership: SchoolMembership) -> SchoolCommandScope {
        SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: baseURL.absoluteString)
    }

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
    }

    /// `instructorMembershipID` : seulement les leçons de ce moniteur (filtre relu par le serveur).
    func lessons(schoolID: UUID, from: Date, to: Date, cursor: String?, instructorMembershipID: UUID? = nil) async throws -> SchoolPage<SchoolLesson> {
        let iso = ISO8601DateFormatter()
        var query = [URLQueryItem(name: "from", value: iso.string(from: from)), URLQueryItem(name: "to", value: iso.string(from: to)), URLQueryItem(name: "limit", value: "100")]
        if let instructorMembershipID { query.append(URLQueryItem(name: "instructorMembershipId", value: instructorMembershipID.uuidString.lowercased())) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let result: SchoolPage<SchoolLesson> = try await read(["v1", "schools", schoolID.uuidString, "lessons"], query: query)
        guard result.items.allSatisfy({ valid($0, schoolID: schoolID) && (instructorMembershipID == nil || $0.instructorMembershipId == instructorMembershipID) }),
              Set(result.items.map(\.id)).count == result.items.count else { throw SchoolAgendaFailure.invalidResponse }
        return result
    }

    /// Historique : les leçons commencées avant `before`, 100 par page, triées par le serveur
    /// (`newestFirst` : les plus récentes d’abord). Le curseur d’un sens est refusé dans l’autre.
    func lessonHistory(schoolID: UUID, before: Date, instructorMembershipID: UUID?,
                       newestFirst: Bool = true, cursor: String?) async throws -> SchoolPage<SchoolLesson> {
        var query = [URLQueryItem(name: "to", value: ISO8601DateFormatter().string(from: before)),
                     URLQueryItem(name: "limit", value: "100"),
                     URLQueryItem(name: "order", value: newestFirst ? "desc" : "asc")]
        if let instructorMembershipID { query.append(URLQueryItem(name: "instructorMembershipId", value: instructorMembershipID.uuidString.lowercased())) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        let result: SchoolPage<SchoolLesson> = try await read(["v1", "schools", schoolID.uuidString, "lessons"], query: query)
        guard result.nextCursor != cursor,
              result.items.allSatisfy({ lesson in
                  valid(lesson, schoolID: schoolID) && (instructorMembershipID == nil || lesson.instructorMembershipId == instructorMembershipID)
                      && (lesson.startsAt.map { $0 < before } ?? false)
              }),
              Set(result.items.map(\.id)).count == result.items.count else { throw SchoolAgendaFailure.invalidResponse }
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
