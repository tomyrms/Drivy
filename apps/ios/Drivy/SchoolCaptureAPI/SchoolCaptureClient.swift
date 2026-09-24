import Foundation

enum SchoolCaptureFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, notFound, choiceNotSet, unavailable, invalidResponse, expired, changed
    case rejected(String)

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
        case .rejected(let message): message
        }
    }
}

/// Transport spécialisé. La collecte reste fermée tant que la signature, le bail et la
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

    func verifyScope(_ scope: SchoolCommandScope) async throws {
        guard scope.apiBaseURL == baseURL.absoluteString else { throw SchoolCaptureFailure.forbidden }
        let person: SchoolPerson = try await read(["v1", "me"])
        guard person.personId == scope.personID, person.memberships.contains(where: {
            $0.schoolId == scope.schoolID && $0.membershipId == scope.membershipID && $0.accessEpoch == scope.accessEpoch
        }) else { throw SchoolCaptureFailure.forbidden }
    }

    func recordingNotice(schoolID: UUID) async throws -> SchoolRecordingNotice {
        let value: SchoolRecordingNotice = try await read(schoolPath(schoolID, ["recording-notice"]))
        guard !value.noticeText.isEmpty, value.noticeText.utf8.count <= 200_000,
              !value.retentionText.isEmpty, value.retentionText.utf8.count <= 200_000,
              !value.contactEmail.isEmpty, SchoolLesson.date(value.approvedAt) != nil else { throw SchoolCaptureFailure.invalidResponse }
        return value
    }

    func receipt(for command: SchoolCapturePendingMutation) async throws -> SchoolOperationReceipt {
        guard command.isValid, command.scope.apiBaseURL == baseURL.absoluteString else { throw SchoolCaptureFailure.invalidResponse }
        let value: SchoolOperationReceipt = try await read(schoolPath(command.scope.schoolID, ["operations", command.id.uuidString]), verifying: command.scope)
        guard command.matches(value) else { throw SchoolCaptureFailure.invalidResponse }
        return value
    }

    /// Le coordinateur doit fournir la copie relue du journal durable, puis persister
    /// l’accusé validé. Ce transport ne supprime jamais une intention incertaine.
    func send(_ command: SchoolCapturePendingMutation) async throws -> SchoolCaptureMutationResult {
        guard command.isValid, command.scope.apiBaseURL == baseURL.absoluteString else { throw SchoolCaptureFailure.invalidResponse }
        let schoolID = command.scope.schoolID
        let target = command.targetID.uuidString
        switch command.kind {
        case .assessDevice:
            let value: SchoolDeviceAssessment = try await read(schoolPath(schoolID, ["devices", target, "assessments"]), mutation: command)
            guard let sent = try? JSONDecoder().decode(SchoolDeviceAssessmentBody.self, from: command.body),
                  value.schoolId == schoolID, value.version > 0, value.deviceId == command.targetID,
                  value.membershipId == command.scope.membershipID, value.platform == sent.platform,
                  value.deviceClass == sent.deviceClass, value.modelCode == sent.modelCode,
                  value.osVersion == sent.osVersion, value.appBuild == sent.appBuild,
                  let issued = SchoolLesson.date(value.assessedAt), let expiry = SchoolLesson.date(value.expiresAt), issued < expiry,
                  value.blockers.count <= 20, value.status != .qualified || value.blockers.isEmpty else { throw SchoolCaptureFailure.invalidResponse }
            return .assessment(value)
        case .recordChoice:
            let value: SchoolRecordingChoice = try await read(schoolPath(schoolID, ["learners", target, "recording-choice"]), mutation: command)
            guard let sent = try? JSONDecoder().decode(SchoolRecordingChoiceBody.self, from: command.body),
                  value.schoolId == schoolID, value.version > 0, value.learnerId == command.targetID,
                  value.lessonId == sent.lessonId, value.status == sent.status, value.source == sent.source,
                  value.noticeVersionId == sent.noticeVersionId, value.recordedBy == command.scope.membershipID,
                  SchoolLesson.date(value.recordedAt) != nil else { throw SchoolCaptureFailure.invalidResponse }
            return .choice(value)
        case .startCapture:
            let value: SchoolCaptureAuthorization = try await read(schoolPath(schoolID, ["lessons", target, "captures"]), mutation: command)
            guard let sent = try? JSONDecoder().decode(SchoolStartCaptureBody.self, from: command.body),
                  value.capture.schoolId == schoolID, value.capture.lessonId == command.targetID,
                  value.capture.deviceId == sent.deviceId, value.capture.deviceAssessmentId == sent.deviceAssessmentId,
                  value.capture.choiceId == sent.choiceId, value.capture.instructorMembershipId == command.scope.membershipID,
                  value.capture.hasValidTimeline, SchoolLesson.date(value.serverTime) != nil,
                  !value.signedCaptureAuthorization.isEmpty, value.signedCaptureAuthorization.utf8.count <= 12_000,
                  !value.signedUploadAuthorization.isEmpty, value.signedUploadAuthorization.utf8.count <= 12_000 else { throw SchoolCaptureFailure.invalidResponse }
            // Un rejeu peut rendre STOPPED/REVOKED/EXPIRED : restituer cet état courant,
            // seul le vérificateur de bail peut autoriser un départ après persistance.
            return .authorization(value)
        case .uploadChunk:
            guard let segmentID = command.segmentID, let index = command.chunkIndex,
                  let sent = try? JSONDecoder().decode(SchoolCaptureChunkBody.self, from: command.body) else { throw SchoolCaptureFailure.invalidResponse }
            let value: SchoolCaptureChunkReceipt = try await read(schoolPath(schoolID, ["captures", target, "segments", segmentID.uuidString, "chunks", String(index)]), mutation: command)
            guard value.captureId == command.targetID, value.segmentId == segmentID, value.chunkIndex == index,
                  value.contentHash == sent.contentHash, SchoolLesson.date(value.acknowledgedAt) != nil else { throw SchoolCaptureFailure.invalidResponse }
            return .chunk(value)
        case .stopCapture, .finalizeCapture:
            let action = command.kind == .stopCapture ? "stop" : "finalize"
            let value: SchoolCaptureSession = try await read(schoolPath(schoolID, ["captures", target, action]), mutation: command)
            guard value.id == command.targetID, value.schoolId == schoolID, value.hasValidTimeline,
                  value.captureState != .authorized else { throw SchoolCaptureFailure.invalidResponse }
            return .capture(value)
        }
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

    func capture(schoolID: UUID, captureID: UUID, scope: SchoolCommandScope? = nil) async throws -> SchoolCaptureSession {
        if let scope, scope.schoolID != schoolID || scope.apiBaseURL != baseURL.absoluteString { throw SchoolCaptureFailure.forbidden }
        let value: SchoolCaptureSession = try await read(schoolPath(schoolID, ["captures", captureID.uuidString]), verifying: scope)
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

    private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
    }

    private func read<Value: Decodable>(_ path: [String], query: [URLQueryItem] = [],
                                       mutation: SchoolCapturePendingMutation? = nil,
                                       verifying scope: SchoolCommandScope? = nil) async throws -> Value {
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
        if let expected = scope ?? mutation?.scope {
            let person: SchoolPerson
            do { person = try await DrivyAPIClient(baseURL: baseURL, tokenSource: PinnedToken(token), transport: transport).me() }
            catch is CancellationError { throw CancellationError() }
            catch SchoolAPIError.unauthorized { throw SchoolCaptureFailure.unauthorized }
            catch SchoolAPIError.forbidden { throw SchoolCaptureFailure.forbidden }
            catch SchoolAPIError.identityNotLinked { throw SchoolCaptureFailure.forbidden }
            catch { throw SchoolCaptureFailure.unavailable }
            guard person.personId == expected.personID, person.memberships.contains(where: {
                $0.schoolId == expected.schoolID && $0.membershipId == expected.membershipID && $0.accessEpoch == expected.accessEpoch
            }) else { throw SchoolCaptureFailure.forbidden }
        }
        try Task.checkCancellation()
        var request = URLRequest(url: target)
        request.httpMethod = mutation.map { $0.kind == .uploadChunk ? "PUT" : "POST" } ?? "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        if let mutation {
            request.httpBody = mutation.body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(mutation.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
            if let version = mutation.expectedVersion { request.setValue("\"\(version)\"", forHTTPHeaderField: "If-Match") }
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw SchoolCaptureFailure.unavailable }
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolCaptureFailure.invalidResponse }
        let type = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let expectedStatus = mutation.map { $0.kind == .assessDevice || $0.kind == .startCapture ? 201 : 200 } ?? 200
        guard response.status == expectedStatus else {
            let code = type == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data).code) : nil
            if response.status == 401 { throw SchoolCaptureFailure.unauthorized }
            if let code, let message = Self.rejections[code], (400...499).contains(response.status) { throw SchoolCaptureFailure.rejected(message) }
            if response.status == 403 { throw SchoolCaptureFailure.forbidden }
            if response.status == 404 { throw code == "RECORDING_CHOICE_NOT_SET" ? SchoolCaptureFailure.choiceNotSet : .notFound }
            if response.status == 409 || response.status == 412 { throw SchoolCaptureFailure.changed }
            throw response.status >= 500 || response.status == 429 ? SchoolCaptureFailure.unavailable : .invalidResponse
        }
        guard type == "application/json", let envelope = try? JSONDecoder().decode(Envelope<Value>.self, from: response.data),
              !envelope.requestId.isEmpty, envelope.requestId.count <= 150, SchoolLesson.date(envelope.serverTime) != nil else { throw SchoolCaptureFailure.invalidResponse }
        return envelope.data
    }

    private static let rejections: [String: String] = [
        "DEVICE_NOT_QUALIFIED": "Le GPS de cet appareil doit encore être vérifié pour cette version. La leçon reste disponible sans GPS.",
        "DEVICE_ASSESSMENT_SUPERSEDED": "Un diagnostic plus récent existe. Relisez-le avant de démarrer.",
        "DEVICE_ASSESSMENT_EXPIRED": "Le diagnostic a expiré. Vérifiez à nouveau cet appareil.",
        "RECORDING_NOTICE_NOT_READY": "L’école doit d’abord adopter sa notice de localisation.",
        "RECORDING_NOT_ALLOWED": "Le choix actuel de l’élève ne permet pas le GPS. La leçon peut continuer sans localisation.",
        "RECORDING_CHOICE_PROTECTED": "Le refus de l’élève ne peut pas être remplacé par un accord verbal.",
        "RECORDING_NOTICE_CHANGED": "La notice a changé. Relisez-la avant de confirmer le choix GPS.",
        "RECORDING_CHOICE_CHANGED": "Le choix de l’élève a changé. Relisez-le avant de démarrer.",
        "CAPTURE_DISABLED": "Le GPS scolaire n’est pas activé. La leçon reste disponible sans GPS.",
        "CAPTURE_START_WINDOW": "Le GPS peut démarrer à proximité de l’horaire prévu de cette leçon.",
        "CAPTURE_ALREADY_ACTIVE": "Un trajet est déjà ouvert pour cette leçon, ce moniteur ou cet appareil.",
        "CAPTURE_INCOMPLETE": "Certains lots attendent leur transfert. Réessayez avant de confirmer un trajet partiel.",
        "CAPTURE_MANIFEST_MISMATCH": "Les lots et le manifeste ne correspondent pas. Les données locales restent conservées.",
        "CHUNK_HASH_MISMATCH": "Le contenu du lot ne correspond pas à son empreinte. Le transfert est interrompu.",
        "CHUNK_CUTOFF_REJECTED": "Ce lot dépasse la fin de collecte autorisée et ne peut pas être envoyé.",
        "LESSON_CLOSED": "Cette leçon est clôturée. Aucun nouveau trajet ne peut démarrer."
    ]
}
