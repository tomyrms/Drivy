import Foundation

@MainActor
final class SchoolProfileClient: SchoolProfileAPI {
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
        catch SchoolAPIError.unauthorized { throw SchoolProfileFailure.unauthorized }
        catch SchoolAPIError.forbidden { throw SchoolProfileFailure.forbidden }
        catch SchoolAPIError.identityNotLinked { throw SchoolProfileFailure.forbidden }
        catch { throw SchoolProfileFailure.unavailable }
    }
    func policies(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolProfilePolicy> {
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let cursor {
            guard !cursor.isEmpty, cursor.utf8.count <= 500 else { throw SchoolProfileFailure.invalidResponse }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let page: SchoolPage<SchoolProfilePolicy> = try await request(schoolID, ["profile-field-policies"], query: query)
        guard Set(page.items.map(\.id)).count == page.items.count,
              page.items.allSatisfy({ Self.valid($0, schoolID: schoolID) }),
              page.nextCursor.map({ $0.utf8.count <= 500 }) ?? true else { throw SchoolProfileFailure.invalidResponse }
        return page
    }
    func notice(schoolID: UUID, id: UUID?) async throws -> SchoolDataPolicy {
        let query = id.map { [URLQueryItem(name: "noticeVersionId", value: $0.uuidString)] } ?? []
        let notice: SchoolDataPolicy = try await request(schoolID, ["data-policy"], query: query)
        guard notice.schoolId == schoolID, notice.version > 0, id == nil || notice.noticeVersionId == id else {
            throw SchoolProfileFailure.invalidResponse
        }
        return notice
    }
    func profile(schoolID: UUID, learnerID: UUID) async throws -> SchoolAdministrativeProfile {
        let profile: SchoolAdministrativeProfile = try await request(schoolID, ["learners", learnerID.uuidString, "administrative-profile"])
        guard Self.valid(profile, schoolID: schoolID, learnerID: learnerID) else { throw SchoolProfileFailure.invalidResponse }
        return profile
    }
    func readiness(schoolID: UUID, learnerID: UUID, action: String) async throws -> SchoolLearnerReadiness {
        let value: SchoolLearnerReadiness = try await request(schoolID, ["learners", learnerID.uuidString, "action-readiness"],
            query: [URLQueryItem(name: "action", value: action)])
        guard value.learnerId == learnerID, value.action == action, value.resourceId == nil,
              value.blockers.count <= 50, !value.ready || value.blockers.isEmpty,
              SchoolInvitation.date(value.computedAt) != nil else { throw SchoolProfileFailure.invalidResponse }
        return value
    }
    func onboarding(schoolID: UUID, kind: SchoolOnboardingKind) async throws -> SchoolOnboarding {
        let value: SchoolOnboarding = try await request(schoolID, ["my-onboarding"], query: [URLQueryItem(name: "kind", value: kind.rawValue)])
        guard Self.valid(value, schoolID: schoolID), value.kind == kind else { throw SchoolProfileFailure.invalidResponse }
        return value
    }
    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        let result: SchoolOperationReceipt = try await request(schoolID, ["operations", id.uuidString])
        guard result.operationId == id, result.resourceVersion > 0, SchoolInvitation.date(result.committedAt) != nil else {
            throw SchoolProfileFailure.invalidResponse
        }
        return result
    }
    func send(_ command: PendingSchoolCommand) async throws -> SchoolProfileResult {
        guard command.kind.isProfile, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let body = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              let operation = body["operationId"] as? String, UUID(uuidString: operation) == command.id else {
            throw SchoolProfileFailure.invalidResponse
        }
        let schoolID = command.scope.schoolID
        let result: SchoolProfileResult
        switch command.kind {
        case .createProfilePolicy, .publishProfilePolicy:
            var path = ["profile-field-policies"]
            if let id = command.resourceID { path += [id.uuidString, "publish"] }
            let value: SchoolProfilePolicy = try await request(schoolID, path, method: "POST", command: command)
            guard Self.valid(value, schoolID: schoolID),
                  value.status == (command.kind == .createProfilePolicy ? "DRAFT" : "PUBLISHED") else {
                throw SchoolProfileFailure.invalidResponse
            }
            result = .policy(value)
        case .updateProfile:
            guard let learnerID = command.routeResourceID else { throw SchoolProfileFailure.invalidResponse }
            let value: SchoolAdministrativeProfile = try await request(schoolID,
                ["learners", learnerID.uuidString, "administrative-profile"], method: "PATCH", command: command)
            guard Self.valid(value, schoolID: schoolID, learnerID: learnerID) else { throw SchoolProfileFailure.invalidResponse }
            result = .profile(value)
        case .saveOnboarding, .completeOnboarding:
            var path = ["my-onboarding"]
            if command.kind == .completeOnboarding { path.append("complete") }
            let value: SchoolOnboarding = try await request(schoolID, path,
                method: command.kind == .completeOnboarding ? "POST" : "PATCH", command: command)
            guard Self.valid(value, schoolID: schoolID), value.personId == command.scope.personID,
                  value.membershipId == command.scope.membershipID, value.kind.rawValue == body["kind"] as? String else {
                throw SchoolProfileFailure.invalidResponse
            }
            result = .onboarding(value)
        default: throw SchoolProfileFailure.invalidResponse
        }
        guard result.version > command.resourceVersion,
              command.resourceID.map({ $0 == result.id }) ?? true else { throw SchoolProfileFailure.invalidResponse }
        return result
    }

    private func request<Value: Decodable & Sendable>(_ schoolID: UUID, _ path: [String],
        query: [URLQueryItem] = [], method: String = "GET", command: PendingSchoolCommand? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolProfileFailure.invalidResponse }
        var url = baseURL
        for item in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(item) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolProfileFailure.invalidResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolProfileFailure.invalidResponse }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolProfileFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolProfileFailure.unauthorized }
        catch { throw SchoolProfileFailure.unavailable }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolProfileFailure.unauthorized }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let command {
            request.httpBody = command.body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(command.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
            request.setValue("\"\(command.ifMatchVersion)\"", forHTTPHeaderField: "If-Match")
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw SchoolProfileFailure.unavailable }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolProfileFailure.invalidResponse }
        let media = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let problem: Problem?
        if media == "application/problem+json" { problem = try? JSONDecoder().decode(Problem.self, from: response.data) }
        else { problem = nil }
        let expected = command?.kind == .createProfilePolicy ? 201 : 200
        guard response.status == expected else {
            switch response.status {
            case 401: throw SchoolProfileFailure.unauthorized
            case 403: throw SchoolProfileFailure.forbidden
            case 404 where path.first == "operations": throw SchoolProfileFailure.operationUnknown
            case 404: throw SchoolProfileFailure.notFound
            case 412 where problem?.code == "VERSION_CONFLICT": throw SchoolProfileFailure.conflict
            case 400 where problem?.code == "INVALID_REQUEST": throw SchoolProfileFailure.rejected("Vérifiez les champs saisis avant de confirmer.")
            case 428 where problem?.code == "PRECONDITION_REQUIRED": throw SchoolProfileFailure.conflict
            case 409:
                if problem?.code == "IDEMPOTENCY_MISMATCH" { throw SchoolProfileFailure.pendingCommand }
                switch problem?.code {
                case "PROFILE_POLICY_NOT_READY": throw SchoolProfileFailure.notInitialized
                case "PROFILE_POLICY_CHANGED": throw SchoolProfileFailure.conflict
                case "ONBOARDING_NOT_READY": throw SchoolProfileFailure.rejected("Complétez le profil utile et relisez l’accueil avant de terminer.")
                case "PROFILE_POLICY_ALREADY_PUBLISHED": throw SchoolProfileFailure.rejected("Cette politique est déjà publiée. Relisez les versions de l’école.")
                case "PROFILE_POLICY_DATE_CONFLICT": throw SchoolProfileFailure.rejected("Une politique publiée utilise déjà cette date d’effet.")
                case "POLICY_REVIEW_REQUIRED": throw SchoolProfileFailure.rejected("La notice de données doit être adoptée dans cette école.")
                case "SCHOOL_NOT_ACTIVE", "SCHOOL_ARCHIVED": throw SchoolProfileFailure.rejected("Cette école ne permet pas cette modification dans son état actuel.")
                case "LEARNER_ARCHIVED": throw SchoolProfileFailure.rejected("Le dossier est archivé. L’administration doit le traiter avant une modification.")
                case "DOCUMENT_NOT_READY": throw SchoolProfileFailure.rejected("Cette photo ne peut pas être utilisée. Elle reste facultative.")
                default: break
                }
                throw SchoolProfileFailure.pendingCommand
            case 422 where problem?.code == "PROFILE_POLICY_RULE_INVALID": throw SchoolProfileFailure.rejected("Vérifiez les finalités et les étapes de chaque champ.")
            case 422 where problem?.code == "INVALID_BIRTH_DATE": throw SchoolProfileFailure.rejected("La naissance doit être une date réelle, non future.")
            case 429, 500...599: throw SchoolProfileFailure.unavailable
            default: throw SchoolProfileFailure.invalidResponse
            }
        }
        guard media == "application/json" else { throw SchoolProfileFailure.invalidResponse }
        do {
            let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !envelope.requestId.isEmpty, SchoolInvitation.date(envelope.serverTime) != nil else { throw SchoolProfileFailure.invalidResponse }
            return envelope.data
        } catch { throw SchoolProfileFailure.invalidResponse }
    }
    static func valid(_ value: SchoolProfilePolicy, schoolID: UUID) -> Bool {
        value.schoolId == schoolID && value.version > 0 && ["DRAFT", "PUBLISHED", "RETIRED"].contains(value.status)
            && SchoolInvitation.date(value.effectiveFrom) != nil && (2...7).contains(value.fields.count)
            && Set(value.fields.map(\.field)).count == value.fields.count && value.fields.allSatisfy(\.isValid)
            && value.fields.contains(where: { $0.field == .firstName }) && value.fields.contains(where: { $0.field == .lastName })
            && (value.status != "PUBLISHED" || value.approvedByMembershipId != nil)
    }
    static func valid(_ value: SchoolAdministrativeProfile, schoolID: UUID, learnerID: UUID) -> Bool {
        value.schoolId == schoolID && value.learnerId == learnerID && value.version > 0
            && ["SELF", "STAFF_ASSISTED"].contains(value.entrySource) && SchoolInvitation.date(value.updatedAt) != nil
            && (value.firstName?.unicodeScalars.count ?? 0) <= 150 && (value.lastName?.unicodeScalars.count ?? 0) <= 150
            && (value.contactPhone?.unicodeScalars.count ?? 0) <= 32
    }
    static func valid(_ value: SchoolOnboarding, schoolID: UUID) -> Bool {
        value.schoolId == schoolID && value.version > 0 && ["IN_PROGRESS", "READY", "COMPLETED"].contains(value.status)
            && SchoolInvitation.date(value.lastSavedAt) != nil && value.pendingActions.count <= 50
            && Set(value.skippedOptionalSteps).isSubset(of: ["PHOTO", "NOTIFICATIONS", "DEVICE"])
    }
    private struct Problem: Decodable { let code: String }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
}
