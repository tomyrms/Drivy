import Foundation

@MainActor final class SchoolObservationClient {
    let baseURL: URL
    let reader: DrivyAPIClient
    let agenda: SchoolAgendaClient
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    var reportClient: SchoolLessonReportClient { agenda.reportClient }

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        agenda = SchoolAgendaClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }

    func verifyScope(_ scope: SchoolCommandScope) async throws {
        guard scope.apiBaseURL == baseURL.absoluteString else { throw SchoolObservationFailure.forbidden }
        let token = try await accessToken()
        try await verify(scope, token: token)
    }

    func observationPage(scope: SchoolCommandScope, lessonID: UUID, trainingID: UUID, cursor: String? = nil) async throws -> SchoolPage<SchoolObservation> {
        var query = [URLQueryItem(name: "limit", value: "25")]
        if let cursor {
            guard !cursor.isEmpty, cursor.utf8.count <= 2000 else { throw SchoolObservationFailure.invalidResponse }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let value: SchoolPage<SchoolObservation> = try await request(scope, ["lessons", lessonID.uuidString, "geo-observations"], query: query)
        guard value.items.count <= 25, Set(value.items.map(\.id)).count == value.items.count,
              value.nextCursor == nil || value.nextCursor!.utf8.count <= 2000,
              value.items.allSatisfy({ $0.hasValidObservation && $0.schoolId == scope.schoolID && $0.lessonId == lessonID
                  && $0.trainingId == trainingID && $0.authorMembershipId == scope.membershipID }) else { throw SchoolObservationFailure.invalidResponse }
        return value
    }

    func observations(scope: SchoolCommandScope, lessonID: UUID, trainingID: UUID) async throws -> [SchoolObservation] {
        var items: [SchoolObservation] = [], cursor: String?, seen = Set<String>()
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 20 else { throw SchoolObservationFailure.invalidResponse }
            let page = try await observationPage(scope: scope, lessonID: lessonID, trainingID: trainingID, cursor: cursor)
            guard items.count + page.items.count <= 100 else { throw SchoolObservationFailure.invalidResponse }
            items.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolObservationFailure.invalidResponse }
        } while cursor != nil
        guard Set(items.map(\.id)).count == items.count else { throw SchoolObservationFailure.invalidResponse }
        return items
    }

    /// Résout le référentiel exact de la formation, jamais le catalogue universel d'une maquette.
    func competencies(scope: SchoolCommandScope, trainingID: UUID) async throws -> [SchoolCatalogCompetency] {
        let training: SchoolTraining = try await request(scope, ["trainings", trainingID.uuidString])
        guard training.id == trainingID, training.schoolId == scope.schoolID, training.version > 0 else { throw SchoolObservationFailure.invalidResponse }
        let offerings: [SchoolOffering] = try await catalogPages(scope, ["offerings"])
        // Une formation héritée peut n'avoir aucun référentiel publié. Le repère temporel reste possible.
        guard let offering = offerings.first(where: { $0.id == training.offeringId }) else { return [] }
        let curricula: [SchoolCurriculum] = try await catalogPages(scope, ["curricula"])
        guard let curriculum = curricula.first(where: { $0.id == offering.curriculumVersionId }) else { return [] }
        guard curriculum.categoryCode == training.categoryCode, curriculum.approved, curriculum.competencies.count <= 200,
              Set(curriculum.competencies.map(\.id)).count == curriculum.competencies.count,
              curriculum.competencies.allSatisfy({ $0.schoolId == scope.schoolID && $0.curriculumVersionId == curriculum.id && $0.version > 0
                  && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.label.unicodeScalars.count <= 200 }) else { throw SchoolObservationFailure.invalidResponse }
        return curriculum.competencies.sorted { ($0.sortOrder, $0.id.uuidString) < ($1.sortOrder, $1.id.uuidString) }
    }

    func receipt(for command: PendingSchoolCommand) async throws -> SchoolOperationReceipt {
        guard command.kind.isObservation, command.hasValidTarget else { throw SchoolObservationFailure.invalidResponse }
        let value: SchoolOperationReceipt = try await request(command.scope, ["operations", command.id.uuidString])
        guard command.matches(value), SchoolLesson.date(value.committedAt) != nil else { throw SchoolObservationFailure.invalidResponse }
        return value
    }

    /// L'appelant fournit l'intention relue dans l'outbox chiffrée et acquitte seulement ce résultat.
    func send(_ command: PendingSchoolCommand) async throws -> SchoolObservationMutationResult {
        guard command.kind.isObservation, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              command.body.count <= 24_000, let lessonID = command.routeResourceID,
              let payload = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              UUID(uuidString: payload["operationId"] as? String ?? "") == command.id else { throw SchoolObservationFailure.invalidResponse }
        if command.kind == .removeObservation {
            guard let id = command.resourceID, let body = try? JSONDecoder().decode(SchoolRemoveObservationBody.self, from: command.body),
                  body.isValid, body.operationId == command.id, Set(payload.keys) == ["operationId", "reason"] else { throw SchoolObservationFailure.invalidResponse }
            let value: Removal = try await request(command.scope, ["geo-observations", id.uuidString, "remove"], method: "POST", command: command)
            guard value.operationId == command.id, value.accepted else { throw SchoolObservationFailure.invalidResponse }
            return .removed(id)
        }
        let required: Set<String> = ["operationId", "draftId", "captureId", "segmentId", "pointSequence", "competencyId", "text", "origin", "eventStatus"]
        let allowed = required.union(["observedAt", "eventKind"])
        guard let body = try? JSONDecoder().decode(SchoolObservationBody.self, from: command.body), body.isValid, body.operationId == command.id,
              required.isSubset(of: Set(payload.keys)), Set(payload.keys).isSubset(of: allowed) else { throw SchoolObservationFailure.invalidResponse }
        let path: [String], method: String
        if command.kind == .createObservation { path = ["lessons", lessonID.uuidString, "geo-observations"]; method = "POST" }
        else if let id = command.resourceID { path = ["geo-observations", id.uuidString]; method = "PUT" }
        else { throw SchoolObservationFailure.invalidResponse }
        let value: SchoolObservation = try await request(command.scope, path, method: method, command: command)
        guard value.hasValidObservation, value.schoolId == command.scope.schoolID, value.lessonId == lessonID,
              value.authorMembershipId == command.scope.membershipID, value.version > command.resourceVersion,
              command.resourceID == nil || command.resourceID == value.id else { throw SchoolObservationFailure.invalidResponse }
        return .observation(value)
    }

    private func catalogPages<Value: SchoolCatalogRecord>(_ scope: SchoolCommandScope, _ path: [String]) async throws -> [Value] {
        var items: [Value] = [], cursor: String?, seen = Set<String>()
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 20 else { throw SchoolObservationFailure.invalidResponse }
            var query = [URLQueryItem(name: "limit", value: "25")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page: SchoolPage<Value> = try await request(scope, path, query: query)
            guard page.items.count <= 25, items.count + page.items.count <= 500,
                  page.items.allSatisfy({ $0.schoolId == scope.schoolID && $0.version > 0 }) else { throw SchoolObservationFailure.invalidResponse }
            items.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolObservationFailure.invalidResponse }
        } while cursor != nil
        guard Set(items.map(\.id)).count == items.count else { throw SchoolObservationFailure.invalidResponse }
        return items
    }

    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String }
    private struct Removal: Decodable { let operationId: UUID; let accepted: Bool }
    @MainActor private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
    }
    private func accessToken() async throws -> String {
        let value: String
        do { value = try await tokenSource.accessToken() }
        catch is CancellationError { throw CancellationError() }
        catch IdentityFailure.reauthentication { throw SchoolObservationFailure.unauthorized }
        catch { throw SchoolObservationFailure.unavailable }
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolObservationFailure.unauthorized }
        return value
    }
    private func verify(_ scope: SchoolCommandScope, token: String) async throws {
        let person: SchoolPerson
        do { person = try await DrivyAPIClient(baseURL: baseURL, tokenSource: PinnedToken(token), transport: transport).me() }
        catch is CancellationError { throw CancellationError() }
        catch SchoolAPIError.unauthorized { throw SchoolObservationFailure.unauthorized }
        catch SchoolAPIError.forbidden { throw SchoolObservationFailure.forbidden }
        catch SchoolAPIError.identityNotLinked { throw SchoolObservationFailure.forbidden }
        catch { throw SchoolObservationFailure.unavailable }
        guard person.personId == scope.personID, person.memberships.contains(where: {
            $0.schoolId == scope.schoolID && $0.membershipId == scope.membershipID && $0.accessEpoch == scope.accessEpoch && $0.roles.contains("INSTRUCTOR")
        }) else { throw SchoolObservationFailure.forbidden }
    }
    private func request<Value: Decodable>(_ scope: SchoolCommandScope, _ path: [String], query: [URLQueryItem] = [],
                                          method: String = "GET", command: PendingSchoolCommand? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL), scope.apiBaseURL == baseURL.absoluteString, scope.accessEpoch > 0 else { throw SchoolObservationFailure.forbidden }
        var url = baseURL
        for part in ["v1", "schools", scope.schoolID.uuidString] + path { url.appendPathComponent(part) }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolObservationFailure.invalidResponse }
        if !query.isEmpty { parts.queryItems = query }
        guard let target = parts.url else { throw SchoolObservationFailure.invalidResponse }
        let token = try await accessToken()
        // Le même jeton sert à vérifier /me puis à envoyer ; aucun changement de compte entre les deux appels.
        try await verify(scope, token: token)
        try Task.checkCancellation()
        var request = URLRequest(url: target); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        if let command {
            request.httpBody = command.body; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(command.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
            if command.kind != .createObservation { request.setValue("\"\(command.resourceVersion)\"", forHTTPHeaderField: "If-Match") }
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SchoolObservationFailure.unavailable }
        // Une annulation tardive ne transforme pas l'accusé reçu en erreur : l'outbox doit pouvoir l'acquitter.
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolObservationFailure.invalidResponse }
        let type = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let expectedStatus = command?.kind == .createObservation ? 201 : 200
        guard response.status == expectedStatus else {
            let code = type == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data).code) : nil
            throw Self.failure(status: response.status, code: code)
        }
        guard type == "application/json", let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: response.data),
              !envelope.requestId.isEmpty, envelope.requestId.count <= 150, SchoolLesson.date(envelope.serverTime) != nil else { throw SchoolObservationFailure.invalidResponse }
        return envelope.data
    }
    private static func failure(status: Int, code: String?) -> SchoolObservationFailure {
        if status == 401 { return .unauthorized }; if status == 403 { return .forbidden }; if status == 404 { return .notFound }
        if status == 409, code == "ANCHOR_NOT_READY" { return .anchorNotReady }
        if status == 409, code == "OBSERVATION_REVIEW_REQUIRED" { return .reviewRequired }
        if status == 412, code == "VERSION_CONFLICT" { return .conflict }
        let messages = [
            "ANCHOR_INVALID": "Cette position n’est plus admissible. Relisez et confirmez explicitement une observation sans position.",
            "LESSON_STATE_CONFLICT": "Cette leçon est annulée ou non réalisée. L’observation ne peut pas y être ajoutée.",
            "CURRICULUM_VERSION_MISMATCH": "Choisissez un thème du référentiel actuel de cette formation.",
            "OBSERVATION_LIMIT_REACHED": "Cette leçon contient déjà 100 observations privées. Relisez-les avant un nouvel ajout.",
            "OBSERVATION_TIME_CHANGED": "La qualification conserve l’instant du signalement. Corrigez l’heure explicitement en revue.",
            "OBSERVATION_TIME_INVALID": "Relisez l’heure du signalement avant de confirmer.",
            "INVALID_REQUEST": "Vérifiez les informations et les longueurs saisies."
        ]
        if (400...499).contains(status), let code, let message = messages[code] { return .rejected(message) }
        if code == "IDEMPOTENCY_MISMATCH" || code == "OBSERVATION_REMOVED" || status == 202 { return .uncertain }
        return status >= 500 || status == 429 ? .unavailable : .invalidResponse
    }
}
