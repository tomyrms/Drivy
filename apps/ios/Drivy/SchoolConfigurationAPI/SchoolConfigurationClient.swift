import Foundation

@MainActor
final class SchoolConfigurationClient: SchoolConfigurationAPI {
    private let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    private let reader: DrivyAPIClient

    init(baseURL: URL, tokenSource: any AccessTokenSource,
         transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL
        self.tokenSource = tokenSource
        self.transport = transport
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }

    func school(id: UUID) async throws -> SchoolDetails {
        do { return try await reader.school(id: id) }
        catch SchoolAPIError.unauthorized { throw SchoolConfigurationFailure.unauthorized }
        catch SchoolAPIError.forbidden { throw SchoolConfigurationFailure.forbidden }
        catch SchoolAPIError.identityNotLinked { throw SchoolConfigurationFailure.forbidden }
        catch { throw SchoolConfigurationFailure.unavailable }
    }

    func setup(schoolID: UUID) async throws -> SchoolSetup {
        let result: SchoolSetup = try await request(schoolID: schoolID, suffix: "setup")
        guard result.schoolId == schoolID, result.version > 0,
              ["IN_PROGRESS", "READY", "COMPLETED"].contains(result.status),
              ["IDENTITY", "ORGANISATION", "OFFERINGS", "COLLECTIVE", "DATA", "REVIEW"].contains(result.currentStep),
              result.completedSteps.count <= 6, Self.valid(result.readiness, schoolID: schoolID) else {
            throw SchoolConfigurationFailure.invalidResponse
        }
        return result
    }

    func readiness(schoolID: UUID) async throws -> SchoolReadiness {
        let result: SchoolReadiness = try await request(schoolID: schoolID, suffix: "readiness")
        guard Self.valid(result, schoolID: schoolID) else { throw SchoolConfigurationFailure.invalidResponse }
        return result
    }

    func dataPolicy(schoolID: UUID) async throws -> SchoolDataPolicy {
        let result: SchoolDataPolicy = try await request(schoolID: schoolID, suffix: "data-policy")
        guard Self.valid(result, schoolID: schoolID) else { throw SchoolConfigurationFailure.invalidResponse }
        return result
    }

    func operation(schoolID: UUID, id: UUID) async throws -> SchoolOperationReceipt {
        let result: SchoolOperationReceipt = try await request(schoolID: schoolID, suffix: "operations", recordID: id)
        guard result.operationId == id, result.resourceId == schoolID, result.resourceVersion > 0,
              Self.timestamp(result.committedAt) else { throw SchoolConfigurationFailure.invalidResponse }
        return result
    }

    func send(_ command: PendingSchoolCommand) async throws -> SchoolCommandResult {
        guard command.scope.apiBaseURL == baseURL.absoluteString, command.resourceVersion > 0,
              let object = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              let operation = object["operationId"] as? String, UUID(uuidString: operation) == command.id else {
            throw SchoolConfigurationFailure.invalidResponse
        }
        let id = command.scope.schoolID
        switch command.kind {
        case .updateSchool, .activate:
            let result: SchoolDetails = try await request(schoolID: id,
                suffix: command.kind == .activate ? "activate" : nil,
                method: command.kind == .activate ? "POST" : "PATCH", command: command)
            guard result.id == id, result.schoolId == id, result.version > command.resourceVersion,
                  result.configurationVersion > 0, command.kind != .activate || result.status == "ACTIVE" else {
                throw SchoolConfigurationFailure.invalidResponse
            }
            return .school(result)
        case .saveSetup:
            let result: SchoolSetup = try await request(schoolID: id, suffix: "setup", method: "PATCH", command: command)
            guard result.schoolId == id, result.version > command.resourceVersion, Self.valid(result.readiness, schoolID: id) else {
                throw SchoolConfigurationFailure.invalidResponse
            }
            return .setup(result)
        case .saveDataPolicy:
            let result: SchoolDataPolicy = try await request(schoolID: id, suffix: "data-policy", method: "PUT", command: command)
            guard Self.valid(result, schoolID: id), result.version > command.resourceVersion, result.status == "APPROVED" else {
                throw SchoolConfigurationFailure.invalidResponse
            }
            return .dataPolicy(result)
        }
    }

    private func request<Value: Decodable & Sendable>(schoolID: UUID, suffix: String?,
        method: String = "GET", command: PendingSchoolCommand? = nil, recordID: UUID? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolConfigurationFailure.invalidResponse }
        var target = baseURL
        for component in ["v1", "schools", schoolID.uuidString] { target.appendPathComponent(component) }
        if let suffix { target.appendPathComponent(suffix) }
        if let recordID { target.appendPathComponent(recordID.uuidString) }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolConfigurationFailure.unauthorized }
        catch SchoolAPIError.unauthorized { throw SchoolConfigurationFailure.unauthorized }
        catch { throw SchoolConfigurationFailure.unavailable }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw SchoolConfigurationFailure.unauthorized
        }
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
            request.setValue("\"\(command.resourceVersion)\"", forHTTPHeaderField: "If-Match")
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw SchoolConfigurationFailure.unavailable }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else {
            throw SchoolConfigurationFailure.invalidResponse
        }
        let mediaType = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let problem: Problem?
        if mediaType == "application/problem+json" { problem = try? JSONDecoder().decode(Problem.self, from: response.data) }
        else { problem = nil }
        switch response.status {
        case 200: break
        case 401: throw SchoolConfigurationFailure.unauthorized
        case 403: throw SchoolConfigurationFailure.forbidden
        case 409:
            if problem?.code == "SETUP_INCOMPLETE" { throw SchoolConfigurationFailure.incomplete }
            if let code = problem?.code, ["CONFIG_IMPACT_REVIEW_REQUIRED", "MODULE_NOT_READY", "POLICY_REVIEW_REQUIRED",
                "SCHOOL_ALREADY_ACTIVE", "SCHOOL_ARCHIVED", "SETUP_NOT_INITIALIZED"].contains(code) {
                throw SchoolConfigurationFailure.rejected
            }
            // A reused idempotency key must never be replaced automatically.
            throw SchoolConfigurationFailure.pendingCommand
        case 412 where problem?.code == "VERSION_CONFLICT": throw SchoolConfigurationFailure.conflict
        case 400 where problem?.code == "INVALID_REQUEST": throw SchoolConfigurationFailure.rejected
        case 422 where problem?.code == "INVALID_TIME_ZONE": throw SchoolConfigurationFailure.rejected
        case 428 where problem?.code == "PRECONDITION_REQUIRED": throw SchoolConfigurationFailure.rejected
        case 404 where suffix == "operations": throw SchoolConfigurationFailure.operationUnknown
        case 429, 500...599: throw SchoolConfigurationFailure.unavailable
        default: throw SchoolConfigurationFailure.invalidResponse
        }
        guard mediaType == "application/json" else { throw SchoolConfigurationFailure.invalidResponse }
        do {
            let result = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard !result.requestId.isEmpty, Self.timestamp(result.serverTime) else {
                throw SchoolConfigurationFailure.invalidResponse
            }
            return result.data
        } catch { throw SchoolConfigurationFailure.invalidResponse }
    }

    private static func valid(_ result: SchoolReadiness, schoolID: UUID) -> Bool {
        let expected: Set<String> = ["CAN_USE_WORKSPACE", "CAN_PLAN_LESSON", "CAN_CAPTURE", "CAN_PUBLISH_COURSE"]
        return result.schoolId == schoolID && result.configurationVersion > 0 && timestamp(result.computedAt)
            && result.capabilities.count == 4 && Set(result.capabilities.map(\.capability)) == expected
            && result.activationReady == result.activationBlockers.isEmpty
            && result.capabilities.allSatisfy { $0.ready == $0.blockers.isEmpty && $0.blockers.count <= 50 }
            && result.activationBlockers.count <= 50
    }

    private static func valid(_ result: SchoolDataPolicy, schoolID: UUID) -> Bool {
        guard result.schoolId == schoolID, result.version > 0,
              ["DRAFT", "APPROVED"].contains(result.status),
              result.noticeText.unicodeScalars.count <= 20_000, result.retentionText.unicodeScalars.count <= 20_000 else { return false }
        if result.status == "APPROVED" {
            return !result.noticeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !result.retentionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && result.approvedAt.map(timestamp) == true && result.approvedByMembershipId != nil
        }
        return result.approvedAt == nil && result.approvedByMembershipId == nil
    }

    private static func timestamp(_ value: String) -> Bool {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if format.date(from: value) != nil { return true }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: value) != nil
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        let requestId: String
        let serverTime: String
    }
    private struct Problem: Decodable { let code: String }
}
