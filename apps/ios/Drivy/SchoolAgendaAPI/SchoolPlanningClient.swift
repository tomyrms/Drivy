import Foundation

struct SchoolCommercialTerms: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID
    let version: Int
    let label: String, termsText: String, validFrom: String
    let validUntil: String?
    let approved: Bool
}
struct SchoolServiceProduct: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID
    let version: Int
    let productKey: String, label: String, type: String
    let categoryCode: String?, durationMinutes: Int?
    let siteId: UUID?
    let unitLabel: String
    let unitPriceCents: Int64
    let validFrom: String, validUntil: String?
    let termsVersionId: UUID
    let enabled: Bool
}
struct SchoolAvailabilityRule: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID
    let version: Int
    let instructorMembershipId: UUID
    let weekdays: [Int]
    let localStart: String, localEnd: String, validFrom: String
    let validUntil: String?
}
struct SchoolClosure: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID
    let version: Int
    let instructorMembershipId: UUID
    let startsAt: String, endsAt: String
    let reason: String?
}

enum SchoolPlanningFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, unavailable, invalidResponse, notFound, conflict, rejected(String)
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Reconnectez-vous pour retrouver votre planning."
        case .forbidden: "Vos accès ont changé. Actualisez votre école avant de continuer."
        case .unavailable: "L’école est momentanément inaccessible. Toute demande en attente reste conservée."
        case .invalidResponse: "La réponse de l’école n’a pas pu être vérifiée."
        case .notFound: "Cette information n’est pas disponible avec vos accès actuels."
        case .conflict: "Ces informations ont changé. Rechargez-les avant de confirmer."
        case .rejected(let message): message
        }
    }
    var definitiveRejection: Bool {
        switch self { case .conflict, .rejected: true; default: false }
    }
}

@MainActor final class SchoolPlanningClient {
    let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    let catalog: SchoolCatalogClient
    let reader: DrivyAPIClient
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
        catalog = SchoolCatalogClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }

    func records<Value: SchoolCatalogRecord>(_ schoolID: UUID, path: [String], query: [URLQueryItem] = []) async throws -> [Value] {
        var records: [Value] = [], cursor: String?, seen = Set<String>()
        repeat {
            var parameters = query + [URLQueryItem(name: "limit", value: "100")]
            if let cursor { parameters.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page: SchoolPage<Value> = try await request(schoolID, path, query: parameters)
            guard page.items.allSatisfy({ $0.schoolId == schoolID && $0.version > 0 }), records.count + page.items.count <= 10_000 else { throw SchoolPlanningFailure.invalidResponse }
            records.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolPlanningFailure.invalidResponse }
        } while cursor != nil
        guard Set(records.map(\.id)).count == records.count else { throw SchoolPlanningFailure.invalidResponse }
        return records
    }
    func receipt(for command: PendingSchoolCommand) async throws -> SchoolOperationReceipt {
        let result: SchoolOperationReceipt = try await request(command.scope.schoolID, ["operations", command.id.uuidString])
        guard command.matches(result) else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func lesson(schoolID: UUID, id: UUID) async throws -> SchoolLesson {
        let lesson: SchoolLesson = try await request(schoolID, ["lessons", id.uuidString])
        guard lesson.id == id, lesson.schoolId == schoolID, lesson.version > 0,
              lesson.startsAt != nil, lesson.endsAt != nil else { throw SchoolPlanningFailure.invalidResponse }
        return lesson
    }
    func send(_ command: PendingSchoolCommand) async throws {
        guard command.kind.isPlanning, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let object = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              UUID(uuidString: object["operationId"] as? String ?? "") == command.id else { throw SchoolPlanningFailure.invalidResponse }
        var path: [String]
        switch command.kind {
        case .createLesson: path = ["lessons"]
        case .moveLesson, .cancelLesson:
            guard let id = command.resourceID else { throw SchoolPlanningFailure.invalidResponse }
            path = ["lessons", id.uuidString, command.kind == .moveLesson ? "move" : "cancel"]
        case .createCommercialTerms: path = ["commercial-terms"]
        case .createServiceProduct: path = ["service-products"]
        case .createAvailabilityRule: path = ["availability-rules"]
        case .updateAvailabilityRule:
            guard let id = command.resourceID else { throw SchoolPlanningFailure.invalidResponse }
            path = ["availability-rules", id.uuidString]
        case .createClosure: path = ["closures"]
        case .removeAvailabilityRule, .removeClosure:
            guard let id = command.resourceID else { throw SchoolPlanningFailure.invalidResponse }
            path = [command.kind == .removeClosure ? "closures" : "availability-rules", id.uuidString, "remove"]
        default: throw SchoolPlanningFailure.invalidResponse
        }
        let _: MutationAcknowledgement = try await request(command.scope.schoolID, path, command: command)
        // AP72 confirms both the operation and its target; a bare HTTP success is insufficient.
        _ = try await receipt(for: command)
    }
    private struct MutationAcknowledgement: Decodable { }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String }
    private func request<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem] = [], command: PendingSchoolCommand? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolPlanningFailure.invalidResponse }
        var url = baseURL
        for part in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(part) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolPlanningFailure.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolPlanningFailure.invalidResponse }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolPlanningFailure.unauthorized }
        catch { throw SchoolPlanningFailure.unavailable }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolPlanningFailure.unauthorized }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = command == nil ? "GET" : command?.kind == .updateAvailabilityRule ? "PUT" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let command {
            request.httpBody = command.body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(command.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
            if command.resourceVersion > 0 { request.setValue("\"\(command.ifMatchVersion)\"", forHTTPHeaderField: "If-Match") }
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) } catch { throw SchoolPlanningFailure.unavailable }
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolPlanningFailure.invalidResponse }
        let contentType = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let expectedStatus = command.map { $0.resourceVersion == 0 ? 201 : 200 } ?? 200
        guard response.status == expectedStatus else {
            let code: String?
            if contentType == "application/problem+json" { code = try? JSONDecoder().decode(Problem.self, from: response.data).code }
            else { code = nil }
            throw Self.failure(response.status, code)
        }
        guard contentType == "application/json" else { throw SchoolPlanningFailure.invalidResponse }
        do {
            let result = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !result.requestId.isEmpty, SchoolLesson.date(result.serverTime) != nil else { throw SchoolPlanningFailure.invalidResponse }
            return result.data
        } catch { throw SchoolPlanningFailure.invalidResponse }
    }
    private static func failure(_ status: Int, _ code: String?) -> SchoolPlanningFailure {
        if status == 401 { return .unauthorized }; if status == 403 { return .forbidden }
        if status == 404 { return .notFound }; if status == 412 && code == "VERSION_CONFLICT" { return .conflict }
        let messages = [
            "SLOT_UNAVAILABLE": "Ce créneau n’est pas disponible pour ce moniteur.",
            "RESERVATION_CONFLICT": "Le moniteur ou l’élève a déjà un rendez-vous sur ce créneau.",
            "SLOT_CONFLICT": "Le moniteur ou l’élève a déjà un rendez-vous sur ce créneau.",
            "EXISTING_BOOKINGS": "Des leçons sont déjà planifiées sur cette période. Déplacez-les avant de fermer ce créneau.",
            "PROFILE_POLICY_NOT_READY": "L’administration doit publier les champs du profil avant de planifier.",
            "PROFILE_INCOMPLETE": "Le profil de l’élève doit être complété avant de planifier.",
            "PROFILE_ACTION_REQUIRED": "Le profil de l’élève doit être complété avant de planifier.",
            "INSTRUCTOR_NOT_ASSIGNED": "Le moniteur doit être affecté à cette formation, avec des dates couvrant le rendez-vous.",
            "LEARNER_NOT_ACTIVE": "Le compte de cet élève n’est plus actif dans cette école.",
            "TRAINING_NOT_ACTIVE": "La formation doit être active dans un dossier non archivé.",
            "COMMERCIAL_SELECTION_INVALID": "La prestation et ses conditions doivent être valides à la date choisie.",
            "COMMERCIAL_QUANTITY_MISMATCH": "La durée doit correspondre à la quantité de la prestation choisie.",
            "PRICE_OVERRIDE_REQUIRED": "Le prix doit correspondre à la prestation choisie.",
            "LESSON_COMMERCIAL_CHANGE_REQUIRED": "Un changement de durée exige un nouvel accord commercial.",
            "INVALID_TIME_ZONE": "Utilisez le fuseau horaire de l’école affiché.",
            "INVALID_SERVICE_PRODUCT": "Précisez la catégorie et la durée de cette prestation.",
            "SCHOOL_NOT_ACTIVE": "L’école doit être active pour planifier une leçon.",
            "OFFERING_NOT_READY": "La formation nécessite une offre active et une procédure approuvée.",
            "SCHOOL_POLICY_CHANGED": "La procédure de la formation a changé. Rechargez-la avant de confirmer.",
            "COMMERCIAL_TERMS_NOT_APPROVED": "Choisissez des conditions commerciales approuvées.",
            "LESSON_CLOSED": "Cette leçon est déjà terminée ou annulée.",
            "LESSON_STARTED": "Le début prévu est passé. Le moniteur doit maintenant constater la séance.",
            "INVALID_INTERVAL": "Vérifiez les dates, les horaires et la durée de cette réservation.",
            "INVALID_REQUEST": "Vérifiez les informations saisies avant de confirmer."
        ]
        if (400...499).contains(status), let code, let message = messages[code] { return .rejected(message) }
        return status >= 500 || status == 429 ? .unavailable : .invalidResponse
    }
}
