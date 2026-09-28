import Foundation

@MainActor
final class SchoolInvitationClient: SchoolInvitationAPI {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    private let reader: DrivyAPIClient
    private let catalog: SchoolCatalogClient

    init(baseURL: URL, tokenSource: any AccessTokenSource,
         transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        catalog = SchoolCatalogClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }

    func trainingOfferings(schoolID: UUID) async throws -> [SchoolOffering] {
        do {
            let offerings = try await collect { try await self.catalog.offerings(schoolID: schoolID, cursor: $0) }
            let curricula = try await collect { try await self.catalog.curricula(schoolID: schoolID, cursor: $0) }
            let policies = try await collect { try await self.catalog.policies(schoolID: schoolID, cursor: $0) }
            let approvedCurricula = Set(curricula.filter(\.approved).map(\.id))
            let approvedPolicies = Set(policies.filter(\.approved).map(\.id))
            return Dictionary(grouping: offerings, by: \.offeringKey).values.compactMap { $0.max { $0.version < $1.version } }
                .filter { $0.schoolId == schoolID && $0.enabled && approvedCurricula.contains($0.curriculumVersionId)
                    && approvedPolicies.contains($0.policyVersionId) }
                .sorted { ($0.categoryCode, $0.offeringKey) < ($1.categoryCode, $1.offeringKey) }
        } catch SchoolCatalogFailure.unauthorized { throw SchoolInvitationFailure.unauthorized }
        catch SchoolCatalogFailure.forbidden { throw SchoolInvitationFailure.forbidden }
        catch { throw SchoolInvitationFailure.unavailable }
    }

    private func collect<Value: SchoolCatalogRecord>(_ fetch: (String?) async throws -> SchoolPage<Value>) async throws -> [Value] {
        var values: [Value] = []
        var cursor: String?
        var seen = Set<String>()
        repeat {
            let page = try await fetch(cursor)
            values.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted || values.count > 10_000 { throw SchoolInvitationFailure.invalidResponse }
        } while cursor != nil
        return values
    }

    func school(id: UUID) async throws -> SchoolDetails {
        do { return try await reader.school(id: id) }
        catch SchoolAPIError.unauthorized { throw SchoolInvitationFailure.unauthorized }
        catch SchoolAPIError.forbidden { throw SchoolInvitationFailure.forbidden }
        catch SchoolAPIError.identityNotLinked { throw SchoolInvitationFailure.forbidden }
        catch { throw SchoolInvitationFailure.unavailable }
    }

    func invitations(schoolID: UUID, cursor: String?) async throws -> SchoolPage<SchoolInvitation> {
        var query = [URLQueryItem(name: "limit", value: "50")]
        if let cursor {
            guard !cursor.isEmpty, cursor.utf8.count <= 6000 else { throw SchoolInvitationFailure.invalidCursor }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let page: SchoolPage<SchoolInvitation> = try await request(schoolID: schoolID, path: ["invitations"], query: query)
        guard page.items.count <= 100, Set(page.items.map(\.id)).count == page.items.count,
              page.items.allSatisfy({ Self.valid($0, schoolID: schoolID) }),
              page.nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 6000 }) ?? true else {
            throw SchoolInvitationFailure.invalidResponse
        }
        return page
    }

    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        let receipt: SchoolOperationReceipt = try await request(schoolID: schoolID, path: ["operations", id.uuidString])
        guard receipt.operationId == id, receipt.resourceVersion > 0, SchoolInvitation.date(receipt.committedAt) != nil else {
            throw SchoolInvitationFailure.invalidResponse
        }
        return receipt
    }

    func send(_ command: PendingSchoolCommand) async throws -> SchoolInvitation {
        guard command.kind.isInvitation, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let body = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              let operation = body["operationId"] as? String, UUID(uuidString: operation) == command.id else {
            throw SchoolInvitationFailure.invalidResponse
        }
        var path = ["invitations"]
        if let id = command.resourceID {
            path += [id.uuidString, command.kind == .resendInvitation ? "resend" : "revoke"]
        }
        let result: SchoolInvitation = try await request(schoolID: command.scope.schoolID, path: path, command: command)
        guard Self.valid(result, schoolID: command.scope.schoolID), result.version > command.resourceVersion,
              command.resourceID.map({ $0 == result.id }) ?? true,
              result.status == (command.kind == .revokeInvitation ? .revoked : .pending) else {
            throw SchoolInvitationFailure.invalidResponse
        }
        if command.kind == .createInvitation {
            guard let original = try? JSONDecoder().decode(SchoolInviteCommand.self, from: command.body),
                  Set(original.roles) == Set(result.roles),
                  result.delivery == (original.delivery ?? .email) else { throw SchoolInvitationFailure.invalidResponse }
        }
        // A code is only ever handed back for a code invitation, when it is created or renewed.
        if result.code != nil, command.kind == .revokeInvitation { throw SchoolInvitationFailure.invalidResponse }
        return result
    }

    private func request<Value: Decodable & Sendable>(schoolID: UUID, path: [String], query: [URLQueryItem] = [],
        command: PendingSchoolCommand? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolInvitationFailure.invalidResponse }
        var url = baseURL
        for component in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(component) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SchoolInvitationFailure.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let target = components.url else { throw SchoolInvitationFailure.invalidResponse }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolInvitationFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolInvitationFailure.unauthorized }
        catch { throw SchoolInvitationFailure.unavailable }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolInvitationFailure.unauthorized }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = command == nil ? "GET" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let command {
            request.httpBody = command.body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(command.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
            if command.kind != .createInvitation {
                request.setValue("\"\(command.resourceVersion)\"", forHTTPHeaderField: "If-Match")
            }
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw SchoolInvitationFailure.unavailable }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else {
            throw SchoolInvitationFailure.invalidResponse
        }
        let media = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let problem: Problem?
        if media == "application/problem+json" { problem = try? JSONDecoder().decode(Problem.self, from: response.data) }
        else { problem = nil }
        let expected = command?.kind == .createInvitation ? 201 : 200
        if response.status != expected {
            switch response.status {
            case 401: throw SchoolInvitationFailure.unauthorized
            case 403: throw SchoolInvitationFailure.forbidden
            case 409:
                switch problem?.code {
                case "SCHOOL_NOT_ACTIVE", "SCHOOL_ARCHIVED": throw SchoolInvitationFailure.schoolInactive
                case "POLICY_REVIEW_REQUIRED": throw SchoolInvitationFailure.policyRequired
                case "ALREADY_MEMBER": throw SchoolInvitationFailure.alreadyMember
                case "INVITATION_ALREADY_PENDING": throw SchoolInvitationFailure.alreadyInvited
                case "INVITATION_USED": throw SchoolInvitationFailure.invitationUsed
                case "INVITATION_REVOKED": throw SchoolInvitationFailure.invitationRevoked
                default: throw SchoolInvitationFailure.pendingCommand
                }
            case 412 where problem?.code == "VERSION_CONFLICT": throw SchoolInvitationFailure.conflict
            case 400 where problem?.code == "INVALID_REQUEST": throw SchoolInvitationFailure.rejected
            case 422 where problem?.code == "INVITATION_TRAINING_INVALID": throw SchoolInvitationFailure.trainingInvalid
            case 400 where problem?.code == "INVALID_CURSOR": throw SchoolInvitationFailure.invalidCursor
            case 428 where problem?.code == "PRECONDITION_REQUIRED": throw SchoolInvitationFailure.rejected
            case 404 where path.first == "operations": throw SchoolInvitationFailure.operationUnknown
            case 503 where problem?.code == "INVITATION_DELIVERY_UNAVAILABLE": throw SchoolInvitationFailure.deliveryUnavailable
            case 429, 500...599: throw SchoolInvitationFailure.unavailable
            default: throw SchoolInvitationFailure.invalidResponse
            }
        }
        guard media == "application/json" else { throw SchoolInvitationFailure.invalidResponse }
        do {
            let envelope = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !envelope.requestId.isEmpty, SchoolInvitation.date(envelope.serverTime) != nil else {
                throw SchoolInvitationFailure.invalidResponse
            }
            return envelope.data
        } catch { throw SchoolInvitationFailure.invalidResponse }
    }

    static func valid(_ invitation: SchoolInvitation, schoolID: UUID) -> Bool {
        guard invitation.schoolId == schoolID, invitation.version > 0, !invitation.roles.isEmpty,
              Set(invitation.roles).count == invitation.roles.count, SchoolInvitation.date(invitation.expiresAt) != nil,
              (invitation.maskedEmail?.unicodeScalars.count ?? 0) <= 320,
              (invitation.trainingCategoryCode.map { !$0.isEmpty && $0.unicodeScalars.count <= 20 } ?? true) else { return false }
        switch invitation.delivery {
        case .email:
            // An e-mail invitation always shows its masked address and never carries a code.
            return !(invitation.maskedEmail ?? "").isEmpty && invitation.code == nil
        case .code:
            // Its code, when present, has the published format.
            return invitation.code.map { SchoolInvitationCode.normalized($0) != nil } ?? true
        }
    }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: String; let serverTime: String }
    private struct Problem: Decodable { let code: String }
}
