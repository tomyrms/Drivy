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
    var current: Bool? = nil
}
struct SchoolPlanningDefaults: SchoolCatalogRecord {
    let id: UUID, schoolId: UUID
    let version: Int
    let trainingCategoryCode: String?, serviceProductKey: String?

    /// Une préférence choisit seulement une formation existante, sans arbitrer une ambiguïté.
    func trainingID(in trainings: [SchoolTraining]) -> UUID? {
        let active = trainings.filter { $0.status == "ACTIVE" }
        if active.count == 1 { return active.first?.id }
        let matching = active.filter { $0.categoryCode == trainingCategoryCode }
        return matching.count == 1 ? matching.first?.id : nil
    }
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
        case .unauthorized: "Reconnecte-toi pour retrouver ton planning."
        case .forbidden: "Tes accès ont changé. Actualise ton école avant de continuer."
        case .unavailable: "L’école est momentanément inaccessible. Toute demande en attente reste conservée."
        case .invalidResponse: "La réponse de l’école n’a pas pu être vérifiée."
        case .notFound: "Cette information n’est pas disponible avec tes accès actuels."
        case .conflict: "Ces informations ont changé. Recharge-les avant de confirmer."
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
    func defaults(schoolID: UUID, membershipID: UUID) async throws -> SchoolPlanningDefaults {
        let result: SchoolPlanningDefaults = try await request(schoolID, ["planning-defaults"])
        guard result.schoolId == schoolID, result.id == membershipID, result.version > 0 else { throw SchoolPlanningFailure.invalidResponse }
        return result
    }
    func send(_ command: PendingSchoolCommand) async throws {
        guard command.kind.isPlanning, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let object = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              UUID(uuidString: object["operationId"] as? String ?? "") == command.id else { throw SchoolPlanningFailure.invalidResponse }
        if command.kind == .startLessonNow { _ = try await startNow(command); return }
        var path: [String]
        switch command.kind {
        case .savePlanningDefaults: path = ["planning-defaults"]
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
    /// « Démarrer une leçon » (extension start-now) : le serveur fixe le début à maintenant, la durée, la prestation
    /// courante et le moniteur appelant, puis renvoie la leçon. La leçon renvoyée tient lieu de preuve ;
    /// une réponse perdue se vérifie ensuite par le reçu AP72.
    func startNow(_ command: PendingSchoolCommand) async throws -> SchoolLesson {
        guard command.kind == .startLessonNow, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let trainingID = command.routeResourceID,
              let object = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              UUID(uuidString: object["operationId"] as? String ?? "") == command.id else { throw SchoolPlanningFailure.invalidResponse }
        let lesson: SchoolLesson
        do { lesson = try await request(command.scope.schoolID, ["lessons", "start-now"], command: command, statuses: [200, 201]) }
        catch SchoolPlanningFailure.rejected(let text) where text == Self.slotConflictMessage {
            // Le serveur reste anonyme sur le rendez-vous en cause ; pour une leçon immédiate, on dit quoi faire.
            throw SchoolPlanningFailure.rejected(Self.startNowConflictMessage)
        }
        guard lesson.schoolId == command.scope.schoolID, lesson.trainingId == trainingID, lesson.status == "PLANNED",
              lesson.instructorMembershipId == command.scope.membershipID, lesson.version > 0,
              let start = lesson.startsAt, let end = lesson.endsAt, end > start else { throw SchoolPlanningFailure.invalidResponse }
        return lesson
    }
    private struct MutationAcknowledgement: Decodable { }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }
    @MainActor private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
    }
    private func request<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem] = [], command: PendingSchoolCommand? = nil,
                                          statuses: Set<Int>? = nil) async throws -> Value {
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
        if let command {
            let person = try await DrivyAPIClient(baseURL: baseURL, tokenSource: PinnedToken(token), transport: transport).me()
            guard person.personId == command.scope.personID, person.memberships.contains(where: {
                $0.membershipId == command.scope.membershipID && $0.schoolId == command.scope.schoolID
                    && $0.accessEpoch == command.scope.accessEpoch
            }) else { throw SchoolPlanningFailure.forbidden }
        }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        if let command { request.httpMethod = [.updateAvailabilityRule, .savePlanningDefaults].contains(command.kind) ? "PUT" : "POST" }
        else { request.httpMethod = "GET" }
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
        guard (statuses ?? [expectedStatus]).contains(response.status) else {
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
    static let slotConflictMessage = "Le moniteur ou l’élève a déjà un rendez-vous sur ce créneau."
    static let startNowConflictMessage = "Toi ou l’élève avez un rendez-vous pendant la durée de cette leçon. Planifie-la à un autre moment."
    static func failure(_ status: Int, _ code: String?, title: String? = nil) -> SchoolPlanningFailure {
        if status == 401 { return .unauthorized }; if status == 403 { return .forbidden }
        if status == 404 { return .notFound }; if status == 412 && code == "VERSION_CONFLICT" { return .conflict }
        let messages = [
            "SLOT_UNAVAILABLE": "Ce créneau n’est pas disponible pour ce moniteur.",
            "RESERVATION_CONFLICT": "Le moniteur ou l’élève a déjà un rendez-vous sur ce créneau.",
            "SLOT_CONFLICT": slotConflictMessage,
            "EXISTING_BOOKINGS": "Des leçons sont déjà planifiées sur cette période. Déplace-les avant de fermer ce créneau.",
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
            "INVALID_TIME_ZONE": "Utilise le fuseau horaire de l’école affiché.",
            "INVALID_SERVICE_PRODUCT": "Précise la catégorie et la durée de cette prestation.",
            "SCHOOL_NOT_ACTIVE": "L’école doit être active pour planifier une leçon.",
            "OFFERING_NOT_READY": "La formation nécessite une offre active et une procédure approuvée.",
            "SCHOOL_POLICY_CHANGED": "La procédure de la formation a changé. Recharge-la avant de confirmer.",
            "COMMERCIAL_TERMS_NOT_APPROVED": "Choisis des conditions commerciales approuvées.",
            "LESSON_CLOSED": "Cette leçon est déjà terminée ou annulée.",
            "LESSON_STARTED": "Le début prévu est passé. Le moniteur doit maintenant constater la séance.",
            "INVALID_INTERVAL": "Vérifie les dates, les horaires et la durée de cette réservation.",
            "INVALID_REQUEST": "Vérifie les informations saisies avant de confirmer."
        ]
        if (400...499).contains(status), let code, let message = messages[code] { return .rejected(message) }
        // Tout autre refus 4xx motivé par l’école est définitif : son explication (en français) est affichée.
        // Un identifiant d’opération déjà utilisé reste à vérifier.
        if (400...499).contains(status), status != 429, let code, code != "IDEMPOTENCY_MISMATCH" {
            let text = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .rejected(text.isEmpty || text.count > 300 ? "L’école a refusé cette demande. Vérifie les informations puis réessaie." : text)
        }
        return status >= 500 || status == 429 ? .unavailable : .invalidResponse
    }
}
