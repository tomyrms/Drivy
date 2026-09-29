import CryptoKit
import Foundation

struct SchoolJoinNotice: Codable, Equatable, Sendable {
    let version: Int
    let noticeText: String
    let retentionText: String
    let contactEmail: String
}
struct SchoolJoinPreview: Codable, Equatable, Sendable {
    let invitationId: UUID
    let schoolId: UUID
    let schoolName: String
    let roles: [String]
    let maskedEmail: String
    let expiresAt: String
    let notice: SchoolJoinNotice
}
struct SchoolJoinPrincipal: Codable, Equatable, Sendable {
    let apiBaseURL: String
    let issuer: String
    let subject: String
    var storageKey: String {
        let data = try! JSONEncoder().encode([apiBaseURL, issuer, subject])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
struct SchoolJoinBody: Codable, Equatable, Sendable {
    let operationId: UUID
    let token: String
}
/// What a learner sees before joining with a code: no address, no notice, only the school.
struct SchoolCodePreview: Codable, Equatable, Sendable {
    let schoolName: String
    let roles: [String]
    let trainingCategoryCode: String?
    let expiresAt: String
    var trainingCategoryCodes: [String]? = nil

    var categories: [String] { trainingCategoryCodes ?? trainingCategoryCode.map { [$0] } ?? [] }

    var isValid: Bool {
        !schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && schoolName.unicodeScalars.count <= 300
            && !roles.isEmpty && Set(roles).count == roles.count
            && roles == ["LEARNER"]
            && (trainingCategoryCode.map { !$0.isEmpty && $0.unicodeScalars.count <= 20 } ?? true)
            && categories.count <= 16 && categories.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.count <= 20 })
            && SchoolLesson.date(expiresAt) != nil
    }
}
/// Answer of an acceptance (link or code): the member context, and `trainingOpened: false`
/// when the invited training has no ready version yet (the key is absent otherwise).
struct SchoolJoinAnswer: Decodable, Sendable, Equatable {
    let membership: SchoolMembership
    let trainingOpened: Bool?

    init(membership: SchoolMembership, trainingOpened: Bool? = nil) {
        self.membership = membership; self.trainingOpened = trainingOpened
    }
    private enum CodingKeys: String, CodingKey { case trainingOpened }
    init(from decoder: any Decoder) throws {
        membership = try SchoolMembership(from: decoder)
        trainingOpened = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Bool.self, forKey: .trainingOpened)
    }
    /// The school joined, but the training still has to be opened by the school.
    var trainingNotOpened: Bool { trainingOpened == false }
}

struct SchoolJoinCodeBody: Codable, Equatable, Sendable {
    let operationId: UUID
    let code: String
}

enum SchoolJoinFailure: Error, LocalizedError, Equatable {
    case invalidLink, authentication, differentAccount, mismatch, expired, revoked, used, unavailable, invalidResponse, storage, pending, unknown
    case invalidCode, codeAttempts, notLinked
    case rejected(String)
    var errorDescription: String? { switch self {
        case .invalidLink: "Ce lien d’invitation n’est pas reconnu. Copiez le lien complet reçu de votre école."
        case .authentication: "Connectez-vous pour consulter cette invitation."
        case .differentAccount: "Cette demande appartient à un autre compte. Votre session et sa référence restent conservées."
        case .mismatch: "Cette invitation ne correspond pas à l’adresse vérifiée de votre compte, ou le lien a été remplacé. Connectez-vous avec le compte destinataire."
        case .expired: "Cette invitation a expiré. Demandez un nouveau lien à votre école."
        case .revoked: "L’école a retiré cette invitation. Demandez-lui un nouveau lien."
        case .used: "Cette invitation a déjà été acceptée par une autre personne."
        case .unavailable: "L’école est momentanément inaccessible. Toute demande envoyée reste conservée."
        case .invalidResponse: "La réponse de l’école ne peut pas être vérifiée."
        case .storage: "La demande ne peut pas être conservée sur cet appareil. Déverrouillez-le puis réessayez."
        case .pending: "Vérifiez la demande en attente avant d’accepter une autre invitation."
        case .unknown: "La confirmation reste inconnue. Gardez cette référence et vérifiez la demande avant de la renvoyer."
        case .invalidCode: "Ce code n’est pas valable. Vérifiez-le ou demandez un nouveau code à votre moniteur."
        case .codeAttempts: "Trop d’essais. Patientez quelques minutes avant de réessayer."
        case .notLinked: "Ce compte n’a pas encore accès à Drivy."
        case .rejected(let message): message
    } }
    var permitsFreshCorrection: Bool { switch self {
        case .mismatch, .expired, .revoked, .used, .rejected, .invalidCode, .codeAttempts: true
        default: false
    } }
    /// The same failures, told about a code rather than a link.
    var codeMessage: String {
        switch self {
        case .expired: "Ce code a expiré. Demandez-en un nouveau à votre moniteur."
        case .revoked: "Ce code a été retiré par l’école. Demandez-en un nouveau à votre moniteur."
        case .used: "Ce code a déjà été utilisé. Demandez-en un nouveau à votre moniteur."
        case .mismatch: "Ce code ne peut pas être utilisé avec ce compte. Demandez-en un nouveau à votre moniteur."
        case .rejected(let message): message.replacingOccurrences(of: "un nouveau lien", with: "un nouveau code")
        default: errorDescription ?? "La demande n’a pas abouti."
        }
    }
}

@MainActor final class SchoolJoinClient {
    let configuration: AppConfiguration
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    init(configuration: AppConfiguration, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.configuration = configuration; self.tokenSource = tokenSource; self.transport = transport
    }

    nonisolated static func token(from link: String, configuration: AppConfiguration) throws -> String {
        let input = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.utf8.count <= 2_048, let parts = URLComponents(string: input),
              parts.scheme == "https", parts.host?.lowercased() == configuration.apiBaseURL.host?.lowercased(),
              (parts.port ?? 443) == (configuration.apiBaseURL.port ?? 443), parts.user == nil, parts.password == nil, parts.query == nil,
              ["/app/invitation", configuration.apiBaseURL.appendingPathComponent("app/invitation").path].contains(parts.path),
              let fragment = parts.percentEncodedFragment, fragment.hasPrefix("token=") else { throw SchoolJoinFailure.invalidLink }
        let token = String(fragment.dropFirst(6))
        guard validToken(token) else { throw SchoolJoinFailure.invalidLink }
        return token
    }
    nonisolated static func validToken(_ value: String) -> Bool {
        value.utf8.count == 43 && value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    func principal() async throws -> SchoolJoinPrincipal { try await credentials().principal }

    // These unverified claims partition local storage only. Every API call verifies the actual
    // bearer token server-side; no local claim grants membership, verifies email or accepts a link.
    private func credentials(expected: SchoolJoinPrincipal? = nil) async throws -> (token: String, principal: SchoolJoinPrincipal) {
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolJoinFailure.authentication }
        catch { throw SchoolJoinFailure.unavailable }
        guard configuration.isValid, token.utf8.count <= 32_768,
              token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolJoinFailure.authentication }
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { throw SchoolJoinFailure.authentication }
        var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: encoded), let claims = try? JSONDecoder().decode(PartitionClaims.self, from: bytes),
              claims.iss == configuration.issuer.absoluteString, !claims.sub.isEmpty, claims.sub.utf8.count <= 512,
              !claims.sub.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw SchoolJoinFailure.authentication }
        let principal = SchoolJoinPrincipal(apiBaseURL: configuration.apiBaseURL.absoluteString, issuer: claims.iss, subject: claims.sub)
        if let expected, principal != expected { throw SchoolJoinFailure.differentAccount }
        return (token, principal)
    }
    private struct PartitionClaims: Decodable { let iss: String; let sub: String }

    func preview(token: String, principal: SchoolJoinPrincipal) async throws -> SchoolJoinPreview {
        guard Self.validToken(token) else { throw SchoolJoinFailure.invalidLink }
        let body = try JSONEncoder().encode(["token": token])
        let value: SchoolJoinPreview = try await request(["v1", "invitations", "preview"], principal: principal, body: body)
        guard !value.schoolName.isEmpty, value.schoolName.count <= 300, !value.maskedEmail.isEmpty,
              SchoolLesson.date(value.expiresAt) != nil, value.notice.version > 0,
              !value.notice.noticeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.notice.retentionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.notice.noticeText.unicodeScalars.count <= 20_000, value.notice.retentionText.unicodeScalars.count <= 20_000,
              !value.notice.contactEmail.isEmpty, !value.roles.isEmpty, Set(value.roles).count == value.roles.count,
              value.roles.allSatisfy({ ["ADMIN", "INSTRUCTOR", "LEARNER"].contains($0) }) else { throw SchoolJoinFailure.invalidResponse }
        return value
    }
    func accept(_ record: SchoolJoinRecord) async throws -> SchoolJoinAnswer {
        guard let body = record.body else { throw SchoolJoinFailure.invalidResponse }
        let answer: SchoolJoinAnswer = try await request(["v1", "invitations", "accept"], principal: record.principal,
            body: body, operationID: record.operationID)
        let value = answer.membership
        guard value.schoolId == record.preview.schoolId, value.accessEpoch > 0,
              value.roles.allSatisfy({ ["ADMIN", "INSTRUCTOR", "LEARNER"].contains($0) }),
              Set(record.preview.roles).isSubset(of: Set(value.roles)) else { throw SchoolJoinFailure.invalidResponse }
        return answer
    }
    func receipt(_ record: SchoolJoinRecord) async throws -> SchoolOperationReceipt {
        let value: SchoolOperationReceipt = try await request(["v1", "schools", record.preview.schoolId.uuidString,
            "operations", record.operationID.uuidString], principal: record.principal)
        guard record.matches(value) else { throw SchoolJoinFailure.invalidResponse }
        return value
    }
    func currentMember(_ record: SchoolJoinRecord, receipt: SchoolOperationReceipt) async throws -> SchoolMembership {
        let value: SchoolPerson = try await request(["v1", "me"], principal: record.principal)
        guard value.version > 0, let membership = value.memberships.first(where: { $0.schoolId == record.preview.schoolId }),
              membership.membershipId == receipt.resourceId, membership.accessEpoch > 0 else { throw SchoolJoinFailure.unknown }
        return membership
    }

    // MARK: Code

    /// `code` must already be normalized (eight characters, no dash).
    func previewCode(_ code: String, principal: SchoolJoinPrincipal) async throws -> SchoolCodePreview {
        guard SchoolInvitationCode.normalized(code) == code else { throw SchoolJoinFailure.invalidCode }
        let body = try JSONEncoder().encode(["code": code])
        let value: SchoolCodePreview = try await request(["v1", "invitations", "code", "preview"], principal: principal, body: body)
        guard value.isValid else { throw SchoolJoinFailure.invalidResponse }
        return value
    }

    /// Sends the stored bytes with the stored operation: a resend is the same request.
    func acceptCode(_ record: SchoolCodeJoinRecord) async throws -> SchoolJoinAnswer {
        guard let body = record.body else { throw SchoolJoinFailure.invalidResponse }
        let answer: SchoolJoinAnswer = try await request(["v1", "invitations", "code", "accept"], principal: record.principal,
            body: body, operationID: record.operationID)
        let value = answer.membership
        guard value.accessEpoch > 0, !value.schoolName.isEmpty,
              value.roles.allSatisfy({ ["ADMIN", "INSTRUCTOR", "LEARNER"].contains($0) }),
              Set(record.preview.roles).isSubset(of: Set(value.roles)) else { throw SchoolJoinFailure.invalidResponse }
        return answer
    }

    /// Schools this identity belongs to now; none while the identity is not linked to a person.
    func memberships(principal: SchoolJoinPrincipal) async throws -> [SchoolMembership] {
        do {
            let value: SchoolPerson = try await request(["v1", "me"], principal: principal)
            guard value.version > 0, value.memberships.allSatisfy({ $0.accessEpoch > 0 }) else { throw SchoolJoinFailure.invalidResponse }
            return value.memberships
        } catch SchoolJoinFailure.notLinked { return [] }
    }

    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: UUID; let serverTime: String }
    private struct Problem: Decodable { let code: String }
    private func request<Value: Decodable>(_ path: [String], principal: SchoolJoinPrincipal, body: Data? = nil, operationID: UUID? = nil) async throws -> Value {
        let credentials = try await credentials(expected: principal)
        var target = configuration.apiBaseURL
        for part in path { target.appendPathComponent(part) }
        var request = URLRequest(url: target)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let operationID { request.setValue(operationID.uuidString, forHTTPHeaderField: "Idempotency-Key") }
        try Task.checkCancellation()
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw SchoolJoinFailure.unavailable }
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolJoinFailure.invalidResponse }
        let type = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == (operationID == nil ? 200 : 201) else {
            let code = type == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data).code) : nil
            throw Self.failure(response.status, code: code)
        }
        guard type == "application/json", let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: response.data),
              SchoolLesson.date(envelope.serverTime) != nil else { throw SchoolJoinFailure.invalidResponse }
        return envelope.data
    }
    private static func failure(_ status: Int, code: String?) -> SchoolJoinFailure {
        if status == 401 { return .authentication }
        switch code {
        case "INVITATION_IDENTITY_MISMATCH": return .mismatch
        case "INVITATION_EXPIRED": return .expired
        case "INVITATION_REVOKED": return .revoked
        case "INVITATION_USED": return .used
        case "SCHOOL_NOT_ACTIVE": return .rejected("Cette école n’accepte pas de nouveaux accès pour le moment.")
        case "LEARNER_ARCHIVED": return .rejected("Votre dossier doit être traité par l’administration avant de rejoindre cette école.")
        case "INVITATION_ROLE_FORBIDDEN": return .rejected("L’émetteur ne peut plus accorder ces rôles. Demandez un nouveau lien à l’école.")
        case "INVITATION_CODE_INVALID": return .invalidCode
        case "INVITATION_CODE_ATTEMPTS": return .codeAttempts
        case "IDENTITY_NOT_LINKED": return .notLinked
        default: break
        }
        if status == 403 || status == 404 || code == "IDEMPOTENCY_MISMATCH" { return .unknown }
        return status == 429 || status >= 500 ? .unavailable : .invalidResponse
    }
}
