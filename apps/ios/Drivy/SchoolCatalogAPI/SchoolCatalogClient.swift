import Foundation

@MainActor final class SchoolCatalogClient: SchoolCatalogAPI {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    private let reader: DrivyAPIClient
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }
    func school(id: UUID) async throws -> SchoolDetails {
        do { return try await reader.school(id: id) }
        catch SchoolAPIError.unauthorized { throw SchoolCatalogFailure.unauthorized }
        catch SchoolAPIError.forbidden { throw SchoolCatalogFailure.forbidden }
        catch { throw SchoolCatalogFailure.unavailable }
    }
    func offerings(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolOffering> {
        let result: SchoolPage<SchoolOffering> = try await page(schoolID, ["offerings"], cursor: cursor)
        guard result.items.allSatisfy({ !$0.offeringKey.isEmpty && !$0.categoryCode.isEmpty && (1...480).contains($0.defaultDurationMinutes)
            && (0...9_007_199_254_740_991).contains($0.defaultPriceCents) }) else { throw SchoolCatalogFailure.invalidResponse }
        return result
    }
    func curricula(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolCurriculum> {
        try await page(schoolID, ["curricula"], cursor: cursor)
    }
    func policies(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolCatalogPolicy> {
        try await page(schoolID, ["policy-versions"], cursor: cursor)
    }
    func members(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolMember> {
        try await page(schoolID, ["members"], cursor: cursor)
    }
    func trainings(schoolID: UUID, learnerID: UUID, cursor: String?) async throws -> SchoolPage<SchoolTraining> {
        let result: SchoolPage<SchoolTraining> = try await page(schoolID, ["trainings"], cursor: cursor,
            extraQuery: [URLQueryItem(name: "learnerId", value: learnerID.uuidString)])
        guard result.items.allSatisfy({ $0.learnerId == learnerID }) else { throw SchoolCatalogFailure.invalidResponse }
        return result
    }
    func assignments(schoolID: UUID, trainingID: UUID, cursor: String?) async throws -> SchoolPage<SchoolAssignment> {
        let result: SchoolPage<SchoolAssignment> = try await page(schoolID, ["trainings", trainingID.uuidString, "assignments"], cursor: cursor)
        guard result.items.allSatisfy({ $0.trainingId == trainingID && SchoolInvitation.date($0.validFrom) != nil
            && ($0.validUntil.map { SchoolInvitation.date($0) != nil } ?? true) }) else { throw SchoolCatalogFailure.invalidResponse }
        return result
    }
    private func page<Value: SchoolCatalogRecord>(_ schoolID: UUID, _ path: [String], cursor: String?,
        extraQuery: [URLQueryItem] = []) async throws -> SchoolPage<Value> {
        var query = extraQuery + [URLQueryItem(name: "limit", value: "100")]
        if let cursor {
            guard !cursor.isEmpty, cursor.utf8.count <= 6_000 else { throw SchoolCatalogFailure.invalidResponse }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let result: SchoolPage<Value> = try await request(schoolID, path, query: query)
        guard result.items.allSatisfy({ $0.schoolId == schoolID && $0.version > 0 }),
              Set(result.items.map(\.id)).count == result.items.count, result.nextCursor == nil || result.nextCursor != cursor else {
            throw SchoolCatalogFailure.invalidResponse
        }
        return result
    }
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        let result: SchoolOperationReceipt = try await request(schoolID, ["operations", id.uuidString])
        guard result.operationId == id, result.resourceVersion > 0, SchoolInvitation.date(result.committedAt) != nil else {
            throw SchoolCatalogFailure.invalidResponse
        }
        return result
    }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolCatalogResult {
        guard command.kind.isCatalog, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let object = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              let operation = object["operationId"] as? String, UUID(uuidString: operation) == command.id else {
            throw SchoolCatalogFailure.invalidResponse
        }
        let schoolID = command.scope.schoolID
        let result: SchoolCatalogResult
        switch command.kind {
        case .createOffering:
            result = .offering(try await request(schoolID, ["offerings"], command: command))
        case .createCurriculum:
            result = .curriculum(try await request(schoolID, ["curricula"], command: command))
        case .createCatalogPolicy:
            result = .policy(try await request(schoolID, ["policy-versions"], command: command))
        case .createTraining:
            let value: SchoolTraining = try await request(schoolID, ["trainings"], command: command)
            guard value.learnerId == command.routeResourceID,
                  UUID(uuidString: object["offeringId"] as? String ?? "") == value.offeringId else { throw SchoolCatalogFailure.invalidResponse }
            result = .training(value)
        case .createAssignment:
            guard let trainingID = command.routeResourceID else { throw SchoolCatalogFailure.invalidResponse }
            let value: SchoolAssignment = try await request(schoolID, ["trainings", trainingID.uuidString, "assignments"], command: command)
            guard value.trainingId == trainingID,
                  UUID(uuidString: object["instructorMembershipId"] as? String ?? "") == value.instructorMembershipId else { throw SchoolCatalogFailure.invalidResponse }
            result = .assignment(value)
        case .updateMember:
            guard let memberID = command.resourceID else { throw SchoolCatalogFailure.invalidResponse }
            result = .member(try await request(schoolID, ["members", memberID.uuidString], command: command))
        default: throw SchoolCatalogFailure.invalidResponse
        }
        guard result.schoolID == schoolID, result.version > command.resourceVersion,
              command.resourceID.map({ $0 == result.id }) ?? true else { throw SchoolCatalogFailure.invalidResponse }
        return result
    }
    private func request<Value: Decodable & Sendable>(_ schoolID: UUID, _ path: [String],
        query: [URLQueryItem] = [], command: PendingSchoolCommand? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolCatalogFailure.invalidResponse }
        var url = baseURL
        for component in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolCatalogFailure.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolCatalogFailure.invalidResponse }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolCatalogFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolCatalogFailure.unauthorized }
        catch { throw SchoolCatalogFailure.unavailable }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolCatalogFailure.unauthorized }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = command == nil ? "GET" : command?.kind == .updateMember ? "PATCH" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let command {
            request.httpBody = command.body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(command.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
            if command.kind == .updateMember { request.setValue("\"\(command.ifMatchVersion)\"", forHTTPHeaderField: "If-Match") }
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw SchoolCatalogFailure.unavailable }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolCatalogFailure.invalidResponse }
        let media = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let problem: Problem?
        if media == "application/problem+json" { problem = try? JSONDecoder().decode(Problem.self, from: response.data) }
        else { problem = nil }
        let expected = command == nil || command?.kind == .updateMember ? 200 : 201
        guard response.status == expected else { throw Self.failure(response.status, code: problem?.code, operationLookup: path.first == "operations") }
        guard media == "application/json" else { throw SchoolCatalogFailure.invalidResponse }
        do {
            let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !envelope.requestId.isEmpty, SchoolInvitation.date(envelope.serverTime) != nil else { throw SchoolCatalogFailure.invalidResponse }
            return envelope.data
        } catch { throw SchoolCatalogFailure.invalidResponse }
    }
    private static func failure(_ status: Int, code: String?, operationLookup: Bool) -> SchoolCatalogFailure {
        if status == 401 { return code == "REAUTH_REQUIRED" ? .reauthentication : .unauthorized }
        if status == 403 { return .forbidden }
        if status == 404 { return operationLookup ? .operationUnknown : .notFound }
        if status == 412 && code == "VERSION_CONFLICT" { return .conflict }
        if status == 400 && code == "INVALID_REQUEST" { return .rejected("Vérifiez les informations saisies avant de confirmer.") }
        if status == 409 {
            let messages = [
                "LAST_ADMIN": "L’école doit conserver au moins un administrateur.",
                "MEMBER_RELATIONS_REQUIRE_REVIEW": "Les affectations de cette personne doivent être revues avant de changer ses rôles.",
                "OFFERING_NOT_READY": "Cette offre a changé ou n’est pas activée. Rechargez le catalogue et choisissez une offre disponible.",
                "OFFERING_CATEGORY_CHANGED": "Une offre existante conserve sa catégorie. Utilisez une nouvelle référence pour une autre catégorie.",
                "ACTIVE_TRAINING_EXISTS": "Une formation est déjà ouverte pour cet élève et cette offre.",
                "ASSIGNMENT_CONFLICT": "Ce moniteur a déjà une affectation qui recouvre ces dates.",
                "INSTRUCTOR_REQUIRED": "Choisissez un membre actif disposant du rôle Moniteur.",
                "TRAINING_NOT_ACTIVE": "Cette formation ne permet pas de nouvelle affectation dans son état actuel.",
                "LEARNER_ARCHIVED": "Ce dossier est archivé. L’administration doit le traiter avant d’ouvrir une formation.",
                "LEARNER_NOT_ACTIVE": "L’élève ne dispose plus d’un accès actif dans cette école.",
                "SCHOOL_NOT_ACTIVE": "Cette école doit être active avant cette modification."
            ]
            if let code, let message = messages[code] { return .rejected(message) }
            return .pending
        }
        if status == 429 || status >= 500 { return .unavailable }
        return .invalidResponse
    }
    private struct Problem: Decodable { let code: String }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
}
