import Foundation

enum SchoolCaptureFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, notFound, choiceNotSet, unavailable, invalidResponse, expired, changed

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Reconnectez-vous pour retrouver cette séance."
        case .forbidden: "L’accès à cette capture n’est plus autorisé."
        case .notFound: "Cette capture n’est pas disponible avec vos droits actuels."
        case .choiceNotSet: "Le choix de l’élève concernant le GPS n’est pas renseigné."
        case .unavailable: "L’école est momentanément inaccessible. Les données déjà enregistrées restent conservées."
        case .invalidResponse: "L’autorisation de capture ne peut pas être vérifiée."
        case .expired: "L’autorisation GPS a expiré. La leçon peut continuer sans GPS."
        case .changed: "La capture a changé. Rechargez son état avant de continuer."
        }
    }
}

/// Transport en lecture. La collecte reste fermée tant que la signature, le bail et la
/// persistance du contexte scolaire ne sont pas confirmés par le coordinateur.
@MainActor final class SchoolCaptureClient {
    let baseURL: URL
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport

    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL
        self.tokenSource = tokenSource
        self.transport = transport
    }

    func publicKeys() async throws -> SchoolCapturePublicKeys {
        let value: SchoolCapturePublicKeys = try await read(["v1", "capture-keys"])
        guard !value.keys.isEmpty, value.keys.count <= 20,
              Set(value.keys.map(\.kid)).count == value.keys.count,
              value.keys.allSatisfy({ $0.kty == "OKP" && $0.crv == "Ed25519" && $0.alg == "EdDSA" && $0.use == "sig"
                  && !$0.kid.isEmpty && $0.kid.count <= 100 && $0.x.count <= 100 }) else { throw SchoolCaptureFailure.invalidResponse }
        return value
    }

    func recordingChoice(schoolID: UUID, learnerID: UUID, lessonID: UUID? = nil) async throws -> SchoolRecordingChoice? {
        let query = lessonID.map { [URLQueryItem(name: "lessonId", value: $0.uuidString)] } ?? []
        do {
            let value: SchoolRecordingChoice = try await read(schoolPath(schoolID, ["learners", learnerID.uuidString, "recording-choice"]), query: query)
            guard value.schoolId == schoolID, value.learnerId == learnerID, value.version > 0,
                  value.lessonId == nil || value.lessonId == lessonID,
                  SchoolLesson.date(value.recordedAt) != nil else { throw SchoolCaptureFailure.invalidResponse }
            return value
        } catch SchoolCaptureFailure.choiceNotSet {
            // Le serveur a contrôlé le dossier ; aucune ligne UNKNOWN n’est créée par cette lecture.
            return nil
        }
    }

    func capture(schoolID: UUID, captureID: UUID) async throws -> SchoolCaptureSession {
        let value: SchoolCaptureSession = try await read(schoolPath(schoolID, ["captures", captureID.uuidString]))
        guard value.id == captureID, value.schoolId == schoolID, value.hasValidTimeline else { throw SchoolCaptureFailure.invalidResponse }
        return value
    }

    func assessment(schoolID: UUID, deviceID: UUID, assessmentID: UUID) async throws -> SchoolDeviceAssessment {
        let value: SchoolDeviceAssessment = try await read(schoolPath(schoolID, ["devices", deviceID.uuidString, "assessments", assessmentID.uuidString]))
        guard value.id == assessmentID, value.schoolId == schoolID, value.deviceId == deviceID, value.version > 0,
              ["IOS", "ANDROID"].contains(value.platform), ["PHONE", "TABLET"].contains(value.deviceClass),
              let assessed = SchoolLesson.date(value.assessedAt), let expiry = SchoolLesson.date(value.expiresAt), assessed < expiry,
              value.blockers.count <= 20,
              [value.modelCode, value.osVersion, value.appBuild, value.qualificationProfileVersion].allSatisfy({ !$0.isEmpty && $0.count <= 100 }),
              value.status != .qualified || value.blockers.isEmpty else { throw SchoolCaptureFailure.invalidResponse }
        return value
    }

    func privateReplayPage(schoolID: UUID, captureID: UUID, cursor: String? = nil) async throws -> SchoolPrivateReplayPage {
        var query = [URLQueryItem(name: "limit", value: "100")]
        if let cursor {
            guard !cursor.isEmpty, cursor.count <= 2000 else { throw SchoolCaptureFailure.invalidResponse }
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let value: SchoolPrivateReplayPage = try await read(schoolPath(schoolID, ["captures", captureID.uuidString, "replay"]), query: query)
        guard value.captureId == captureID, value.reportRevisionId == nil, value.geometrySnapshotId == nil,
              ["SYNCED", "PARTIAL"].contains(value.quality), SchoolLesson.date(value.generatedAt) != nil,
              value.segments.count <= 100, value.observations.count <= 100,
              value.nextCursor == nil || (!value.nextCursor!.isEmpty && value.nextCursor!.count <= 2000),
              Set(value.segments.map(\.segmentId)).count == value.segments.count,
              value.segments.reduce(0, { $0 + $1.points.count }) <= 100,
              value.segments.allSatisfy(Self.validSegment),
              Set(value.observations.map(\.id)).count == value.observations.count,
              value.observations.allSatisfy({ $0.schoolId == schoolID && $0.version > 0 && $0.captureId == captureID
                  && !$0.text.isEmpty && $0.text.unicodeScalars.count <= 4000 }) else { throw SchoolCaptureFailure.invalidResponse }
        switch value.publicationState {
        case .privateCapture: return value
        case .withdrawn, .deleted:
            guard value.segments.isEmpty, value.observations.isEmpty, value.nextCursor == nil else { throw SchoolCaptureFailure.invalidResponse }
            return value
        case .published: throw SchoolCaptureFailure.invalidResponse
        }
    }

    private static func validSegment(_ value: SchoolPrivateReplaySegment) -> Bool {
        guard value.segmentIndex >= 0, ["AVAILABLE", "LOW_ACCURACY", "PARTIAL"].contains(value.qualityLabel),
              value.points.allSatisfy(\.isValid), Set(value.points.map(\.sequence)).count == value.points.count else { return false }
        return zip(value.points, value.points.dropFirst()).allSatisfy { previous, next in
            previous.sequence < next.sequence && previous.elapsedMs <= next.elapsedMs
                && SchoolLesson.date(previous.capturedAt)! <= SchoolLesson.date(next.capturedAt)!
        }
    }

    private func schoolPath(_ schoolID: UUID, _ path: [String]) -> [String] {
        ["v1", "schools", schoolID.uuidString] + path
    }

    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        let requestId: String
        let serverTime: String
    }
    private struct Problem: Decodable { let code: String }

    private func read<Value: Decodable>(_ path: [String], query: [URLQueryItem] = []) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolCaptureFailure.invalidResponse }
        var url = baseURL
        for part in path { url.appendPathComponent(part) }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolCaptureFailure.invalidResponse }
        if !query.isEmpty { parts.queryItems = query }
        guard let target = parts.url else { throw SchoolCaptureFailure.invalidResponse }
        let token: String
        do { token = try await tokenSource.accessToken() }
        catch IdentityFailure.reauthentication { throw SchoolCaptureFailure.unauthorized }
        catch { throw SchoolCaptureFailure.unavailable }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolCaptureFailure.unauthorized }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SchoolCaptureFailure.unavailable }
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolCaptureFailure.invalidResponse }
        let type = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == 200 else {
            let code = type == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data).code) : nil
            if response.status == 401 { throw SchoolCaptureFailure.unauthorized }
            if response.status == 403 { throw SchoolCaptureFailure.forbidden }
            if response.status == 404 { throw code == "RECORDING_CHOICE_NOT_SET" ? SchoolCaptureFailure.choiceNotSet : .notFound }
            if response.status == 409 || response.status == 412 { throw SchoolCaptureFailure.changed }
            throw response.status >= 500 || response.status == 429 ? SchoolCaptureFailure.unavailable : .invalidResponse
        }
        guard type == "application/json", let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: response.data),
              !envelope.requestId.isEmpty, envelope.requestId.count <= 150, SchoolLesson.date(envelope.serverTime) != nil else { throw SchoolCaptureFailure.invalidResponse }
        return envelope.data
    }
}
