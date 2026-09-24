import CryptoKit
import Foundation

/// Bail volontairement non Codable : une relance exige une nouvelle validation serveur.
/// L’origine monotone est prise AVANT l’appel AP154, afin de ne pas gagner le temps réseau.
struct SchoolCaptureLease: Sendable {
    let captureID: UUID
    let schoolID: UUID
    let personID: UUID
    let deviceID: UUID
    private let requestStartedAt: ContinuousClock.Instant
    private let remainingAtServerResponse: Duration

    fileprivate init(capture: SchoolCaptureSession, personID: UUID, requestStartedAt: ContinuousClock.Instant, remainingSeconds: TimeInterval) {
        captureID = capture.id
        schoolID = capture.schoolId
        self.personID = personID
        deviceID = capture.deviceId
        self.requestStartedAt = requestStartedAt
        remainingAtServerResponse = .seconds(remainingSeconds)
    }

    func permitsCollection(at instant: ContinuousClock.Instant = .now) -> Bool {
        let elapsed = requestStartedAt.duration(to: instant)
        return elapsed >= .zero && elapsed < remainingAtServerResponse
    }

    var collectionDeadline: ContinuousClock.Instant {
        requestStartedAt.advanced(by: remainingAtServerResponse)
    }
}

enum SchoolCaptureAuthorizationVerifier {
    private struct Header: Decodable {
        let alg: String
        let kid: String
        let typ: String
        let crit: [String]?
    }
    private struct Claims: Decodable {
        let iss: String
        let aud: String
        let sub: UUID
        let jti: String
        let iat: Int64
        let exp: Int64
        let scope: String
        let schoolId: UUID
        let captureId: UUID
        let lessonId: UUID
        let deviceId: UUID
        let deviceAssessmentId: UUID
        let authorizedAt: String
        let expiresAt: String
        let uploadDeadline: String
    }

    /// Les clés proviennent uniquement de la route HTTPS de l’API configurée, jamais
    /// de jku/x5u ou d’un issuer tiré du jeton. Cette vérification n’ouvre pas le GPS.
    @MainActor static func verify(_ authorization: SchoolCaptureAuthorization, keys: SchoolCapturePublicKeys,
                       expectedIssuer: URL, scope: SchoolCommandScope, lessonID: UUID, deviceID: UUID,
                       assessmentID: UUID, requestStartedAt: ContinuousClock.Instant) throws -> SchoolCaptureLease {
        let capture = authorization.capture
        guard DrivyAPIClient.permits(expectedIssuer), expectedIssuer.absoluteString == scope.apiBaseURL,
              capture.hasValidTimeline, capture.schoolId == scope.schoolID, capture.lessonId == lessonID,
              capture.deviceId == deviceID, capture.deviceAssessmentId == assessmentID,
              capture.instructorMembershipId == scope.membershipID,
              capture.captureState == .authorized, capture.publicationState == .privateCapture,
              capture.stoppedAt == nil, capture.cutoffAt == nil,
              let serverTime = SchoolLesson.date(authorization.serverTime),
              let authorizedAt = SchoolLesson.date(capture.authorizedAt),
              let expiresAt = SchoolLesson.date(capture.expiresAt),
              let uploadDeadline = SchoolLesson.date(capture.uploadDeadline),
              serverTime >= authorizedAt, expiresAt.timeIntervalSince(authorizedAt) <= 10_800,
              expiresAt > serverTime, uploadDeadline >= expiresAt else { throw SchoolCaptureFailure.invalidResponse }
        try verifyToken(authorization.signedCaptureAuthorization, keys: keys, capture: capture,
                        expectedIssuer: expectedIssuer.absoluteString, personID: scope.personID,
                        expectedScope: "capture:collect", expiry: expiresAt, serverTime: serverTime)
        try verifyToken(authorization.signedUploadAuthorization, keys: keys, capture: capture,
                        expectedIssuer: expectedIssuer.absoluteString, personID: scope.personID,
                        expectedScope: "capture:upload", expiry: uploadDeadline, serverTime: serverTime)
        // exp est entier : les fractions de seconde de la projection ne prolongent pas le JWT.
        let signedDeadline = Date(timeIntervalSince1970: floor(expiresAt.timeIntervalSince1970))
        let lease = SchoolCaptureLease(capture: capture, personID: scope.personID,
                                      requestStartedAt: requestStartedAt, remainingSeconds: signedDeadline.timeIntervalSince(serverTime))
        guard lease.permitsCollection() else { throw SchoolCaptureFailure.expired }
        return lease
    }

    private static func verifyToken(_ token: String, keys: SchoolCapturePublicKeys, capture: SchoolCaptureSession,
                                    expectedIssuer: String, personID: UUID, expectedScope: String,
                                    expiry: Date, serverTime: Date) throws {
        guard !token.isEmpty, token.utf8.count <= 12_000 else { throw SchoolCaptureFailure.invalidResponse }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let headerData = base64URL(parts[0]), let claimsData = base64URL(parts[1]),
              let signature = base64URL(parts[2]), signature.count == 64,
              let header = try? JSONDecoder().decode(Header.self, from: headerData),
              header.alg == "EdDSA", header.typ == "drivy-capture+jwt", header.crit?.isEmpty ?? true,
              !header.kid.isEmpty else { throw SchoolCaptureFailure.invalidResponse }
        let matchingKeys = keys.keys.filter { $0.kid == header.kid }
        guard matchingKeys.count == 1, let key = matchingKeys.first,
              key.kty == "OKP", key.crv == "Ed25519", key.alg == "EdDSA", key.use == "sig",
              let rawKey = base64URL(Substring(key.x)), rawKey.count == 32,
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else { throw SchoolCaptureFailure.invalidResponse }
        let signedBytes = Data("\(parts[0]).\(parts[1])".utf8)
        guard publicKey.isValidSignature(signature, for: signedBytes),
              let claims = try? JSONDecoder().decode(Claims.self, from: claimsData),
              claims.iss == expectedIssuer, claims.aud == "drivy-native-capture", claims.sub == personID,
              claims.scope == expectedScope, claims.jti.lowercased() == "\(capture.id.uuidString.lowercased()):\(expectedScope)",
              claims.schoolId == capture.schoolId, claims.captureId == capture.id, claims.lessonId == capture.lessonId,
              claims.deviceId == capture.deviceId, claims.deviceAssessmentId == capture.deviceAssessmentId,
              claims.authorizedAt == capture.authorizedAt, claims.expiresAt == capture.expiresAt,
              claims.uploadDeadline == capture.uploadDeadline,
              let authorizedAt = SchoolLesson.date(capture.authorizedAt),
              claims.iat == Int64(floor(authorizedAt.timeIntervalSince1970)),
              claims.exp == Int64(floor(expiry.timeIntervalSince1970)),
              claims.exp > Int64(floor(serverTime.timeIntervalSince1970)), claims.exp > claims.iat else { throw SchoolCaptureFailure.invalidResponse }
    }

    private static func base64URL(_ value: Substring) -> Data? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
            || (48...57).contains($0) || $0 == 45 || $0 == 95 }), value.utf8.count % 4 != 1 else { return nil }
        let raw = String(value).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - raw.utf8.count % 4) % 4)
        guard let decoded = Data(base64Encoded: raw + padding),
              decoded.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "") == value else { return nil }
        return decoded
    }
}
