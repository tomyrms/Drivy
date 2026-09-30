import Foundation

enum SchoolReportFailure: Error, LocalizedError, Equatable {
    case unauthorized, forbidden, unavailable, invalidResponse, notFound, conflict, rejected(String), uncertain
    /// Contrôle du permis refusé à ce compte (grant `permit_review` ou affectation absents) :
    /// ce n’est pas une perte d’accès à la leçon.
    case permitReviewRequired
    var errorDescription: String? {
        switch self {
        case .unauthorized: "Reconnecte-toi pour retrouver cette leçon."
        case .forbidden: "Ton accès à cette leçon a changé. Actualise ton école."
        case .unavailable: "L’école est momentanément inaccessible. Ta demande en attente reste conservée."
        case .invalidResponse: "Les informations reçues ne peuvent pas être vérifiées."
        case .notFound: "Ce contenu n’est pas disponible avec tes droits actuels."
        case .conflict: "Cette version a changé. Recharge les informations avant de confirmer."
        case .rejected(let message): message
        case .uncertain: "La confirmation reste à vérifier. Conserve cette demande et vérifie son résultat avant toute nouvelle modification."
        case .permitReviewRequired: "Tu n’as pas le droit de contrôler ce permis. Précise la situation du permis."
        }
    }
    var permitsFreshCorrection: Bool { switch self { case .conflict, .rejected, .permitReviewRequired: true; default: false } }
}

@MainActor final class SchoolLessonReportClient {
    let baseURL: URL
    let reader: DrivyAPIClient
    let agenda: SchoolAgendaClient
    let catalog: SchoolCatalogClient
    private let tokenSource: any AccessTokenSource
    private let transport: any SchoolHTTPTransport
    init(baseURL: URL, tokenSource: any AccessTokenSource, transport: any SchoolHTTPTransport = SchoolURLSessionTransport()) {
        self.baseURL = baseURL; self.tokenSource = tokenSource; self.transport = transport
        reader = DrivyAPIClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        agenda = SchoolAgendaClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
        catalog = SchoolCatalogClient(baseURL: baseURL, tokenSource: tokenSource, transport: transport)
    }
    func preparation(schoolID: UUID, lessonID: UUID) async throws -> SchoolLessonPreparation {
        let value: SchoolLessonPreparation = try await request(schoolID, ["lessons", lessonID.uuidString, "preparation"])
        guard value.schoolId == schoolID, value.lessonId == lessonID, value.version > 0,
              value.goals.count <= 3, value.plannedWaypoints.count <= 20,
              value.plannedWaypoints.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }) else { throw SchoolReportFailure.invalidResponse }
        return value
    }
    func wish(schoolID: UUID, trainingID: UUID) async throws -> SchoolLearnerWish {
        let value: SchoolLearnerWish = try await request(schoolID, ["trainings", trainingID.uuidString, "wish"])
        guard value.schoolId == schoolID, value.trainingId == trainingID, value.version > 0, value.text.unicodeScalars.count <= 500 else { throw SchoolReportFailure.invalidResponse }
        return value
    }
    func drafts(schoolID: UUID, lessonID: UUID) async throws -> [SchoolReportDraft] {
        let values: [SchoolReportDraft] = try await pages(schoolID, ["lessons", lessonID.uuidString, "report-drafts"])
        guard values.allSatisfy({ $0.lessonId == lessonID && $0.basePublicationVersion >= 0 && valid($0.observations) && $0.attachmentIds.isEmpty
            && ($0.geoObservationIds?.count ?? 0) <= 100 && Set($0.geoObservationIds ?? []).count == ($0.geoObservationIds?.count ?? 0) }) else { throw SchoolReportFailure.invalidResponse }
        return values
    }
    func revisions(schoolID: UUID, lessonID: UUID) async throws -> [SchoolReportRevision] {
        let values: [SchoolReportRevision] = try await pages(schoolID, ["lessons", lessonID.uuidString, "reports"])
        guard values.allSatisfy({ $0.lessonId == lessonID && $0.sequence > 0 && SchoolLesson.date($0.publishedAt) != nil && valid($0.observations) }) else { throw SchoolReportFailure.invalidResponse }
        return values.sorted { $0.sequence > $1.sequence }
    }
    func progress(schoolID: UUID, trainingID: UUID) async throws -> SchoolReportProgress {
        let value: SchoolReportProgress = try await request(schoolID, ["trainings", trainingID.uuidString, "progress"])
        guard value.trainingId == trainingID, SchoolLesson.date(value.computedAt) != nil, Set(value.items.map(\.id)).count == value.items.count,
              value.items.allSatisfy({ SchoolLesson.date($0.observedAt) != nil && ["DISCOVERING", "GUIDED", "INDEPENDENT"].contains($0.level) }) else { throw SchoolReportFailure.invalidResponse }
        return value
    }
    func sharing(schoolID: UUID, lessonID: UUID) async throws -> SchoolLessonSharing {
        let value: SchoolLessonSharing = try await request(schoolID, ["lessons", lessonID.uuidString, "sharing"])
        guard value.schoolId == schoolID, value.lessonId == lessonID, value.version > 0, value.privateObservationIds.count <= 100,
              Set(value.privateObservationIds).count == value.privateObservationIds.count else { throw SchoolReportFailure.invalidResponse }
        return value
    }
    func account(schoolID: UUID, lessonID: UUID) async throws -> SchoolLessonAccount {
        let value: SchoolLessonAccount = try await request(schoolID, ["lessons", lessonID.uuidString, "account"])
        guard value.ownerType == "LESSON", value.ownerId == lessonID, value.lessonId == lessonID, value.version > 0, value.currency == "CHF",
              [value.plannedPriceCents, value.chargeCents, value.netReceivedCents, value.balanceCents].allSatisfy({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }),
              value.charges.allSatisfy({ $0.schoolId == schoolID && $0.accountId == value.id && $0.version > 0
                  && (-9_007_199_254_740_991...9_007_199_254_740_991).contains($0.amountSignedCents)
                  && ["INITIAL", "ADJUSTMENT", "REVERSAL"].contains($0.kind) }) else { throw SchoolReportFailure.invalidResponse }
        return value
    }
    func receipt(for command: PendingSchoolCommand) async throws -> SchoolOperationReceipt {
        let value: SchoolOperationReceipt = try await request(command.scope.schoolID, ["operations", command.id.uuidString])
        guard command.scope.apiBaseURL == baseURL.absoluteString, command.matches(value) else { throw SchoolReportFailure.invalidResponse }
        return value
    }
    /// Envoie une demande relue dans la file chiffrée. Le partage renvoie l’état confirmé par l’école,
    /// appliqué sans relire toute la leçon.
    @discardableResult func send(_ command: PendingSchoolCommand) async throws -> SchoolLessonSharing? {
        guard command.kind.isReport, command.hasValidTarget, command.scope.apiBaseURL == baseURL.absoluteString,
              let body = try? JSONSerialization.jsonObject(with: command.body) as? [String: Any],
              UUID(uuidString: body["operationId"] as? String ?? "") == command.id else { throw SchoolReportFailure.invalidResponse }
        let path: [String], method: String
        switch command.kind {
        case .savePreparation:
            guard let target = command.routeResourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["lessons", target.uuidString, "preparation"]; method = "PUT"
        case .saveWish:
            guard let target = command.routeResourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["trainings", target.uuidString, "wish"]; method = "PUT"
        case .completeLesson:
            guard let target = command.resourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["lessons", target.uuidString, "complete"]; method = "POST"
        case .saveReportDraft:
            guard let target = command.resourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["report-drafts", target.uuidString]; method = "PUT"
        case .publishReportDraft:
            guard let target = command.routeResourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["report-drafts", target.uuidString, "publish"]; method = "POST"
        case .updateLessonSharing:
            guard let target = command.resourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["lessons", target.uuidString, "sharing"]; method = "PUT"
        case .recordPermitCheck:
            guard let target = command.routeResourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["trainings", target.uuidString, "permit-checks"]; method = "POST"
        case .markNoShow:
            guard let target = command.resourceID else { throw SchoolReportFailure.invalidResponse }
            path = ["lessons", target.uuidString, "no-show"]; method = "POST"
        default: throw SchoolReportFailure.invalidResponse
        }
        var sharing: SchoolLessonSharing?
        if command.kind == .updateLessonSharing {
            let value: SchoolLessonSharing = try await request(command.scope.schoolID, path, method: method, command: command)
            guard let target = command.resourceID, value.lessonId == target, value.schoolId == command.scope.schoolID,
                  value.version > command.resourceVersion, value.privateObservationIds.count <= 100 else { throw SchoolReportFailure.uncertain }
            sharing = value
        } else {
            let _: Acknowledgement = try await request(command.scope.schoolID, path, method: method, command: command)
        }
        // Dès le succès HTTP, tout problème de preuve est une incertitude, jamais un refus frais.
        do { _ = try await receipt(for: command) } catch { throw SchoolReportFailure.uncertain }
        return sharing
    }
    private func valid(_ values: [SchoolReportObservation]) -> Bool {
        values.count <= 100 && Set(values.map(\.id)).count == values.count
            && values.allSatisfy { ["DISCOVERING", "GUIDED", "INDEPENDENT"].contains($0.level) && $0.context.unicodeScalars.count <= 500 }
    }
    private func pages<Value: SchoolCatalogRecord>(_ schoolID: UUID, _ path: [String]) async throws -> [Value] {
        var values: [Value] = [], cursor: String?, seen = Set<String>()
        repeat {
            // Un bilan peut contenir des textes longs : conserver chaque page sous le plafond réseau.
            var query = [URLQueryItem(name: "limit", value: "5")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page: SchoolPage<Value> = try await request(schoolID, path, query: query)
            guard page.items.allSatisfy({ $0.schoolId == schoolID && $0.version > 0 }), values.count + page.items.count <= 500 else { throw SchoolReportFailure.invalidResponse }
            values.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolReportFailure.invalidResponse }
        } while cursor != nil
        guard Set(values.map(\.id)).count == values.count else { throw SchoolReportFailure.invalidResponse }
        return values
    }
    private struct Acknowledgement: Decodable {}
    private struct Envelope<Value: Decodable>: Decodable { let data: Value; let requestId: UUID; let serverTime: String }
    private struct Problem: Decodable { let code: String; let title: String? }
    @MainActor private final class PinnedToken: AccessTokenSource {
        let value: String
        init(_ value: String) { self.value = value }
        func accessToken() async throws -> String { value }
    }
    private func request<Value: Decodable>(_ schoolID: UUID, _ path: [String], query: [URLQueryItem] = [], method: String = "GET", command: PendingSchoolCommand? = nil) async throws -> Value {
        guard DrivyAPIClient.permits(baseURL) else { throw SchoolReportFailure.invalidResponse }
        var url = baseURL
        for part in ["v1", "schools", schoolID.uuidString] + path { url.appendPathComponent(part) }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw SchoolReportFailure.invalidResponse }
        if !query.isEmpty { parts.queryItems = query }
        guard let target = parts.url else { throw SchoolReportFailure.invalidResponse }
        let token: String
        do { token = try await tokenSource.accessToken() } catch IdentityFailure.reauthentication { throw SchoolReportFailure.unauthorized } catch { throw error.unlessCancelled(SchoolReportFailure.unavailable) }
        guard !token.isEmpty, token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw SchoolReportFailure.unauthorized }
        if let command {
            let person = try await DrivyAPIClient(baseURL: baseURL, tokenSource: PinnedToken(token), transport: transport).me()
            guard person.personId == command.scope.personID, person.memberships.contains(where: {
                $0.membershipId == command.scope.membershipID && $0.schoolId == command.scope.schoolID
                    && $0.accessEpoch == command.scope.accessEpoch
            }) else { throw SchoolReportFailure.forbidden }
        }
        try Task.checkCancellation()
        var request = URLRequest(url: target); request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json, application/problem+json", forHTTPHeaderField: "Accept")
        if let command {
            request.httpBody = command.body; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(command.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
            request.setValue("\"\(command.ifMatchVersion)\"", forHTTPHeaderField: "If-Match")
        }
        let response: SchoolHTTPResponse
        do { response = try await transport.send(request) }
        catch { throw error.unlessCancelled(SchoolReportFailure.unavailable) }
        try Task.checkCancellation()
        guard response.url == target, response.data.count <= SchoolURLSessionTransport.maximumResponseBytes else { throw SchoolReportFailure.invalidResponse }
        let type = response.contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard response.status == 200 else {
            let problem = type == "application/problem+json" ? (try? JSONDecoder().decode(Problem.self, from: response.data)) : nil
            throw Self.failure(response.status, problem?.code, kind: command?.kind, title: problem?.title)
        }
        guard type == "application/json" else { throw SchoolReportFailure.invalidResponse }
        do {
            let value = try JSONDecoder().decode(Envelope<Value>.self, from: response.data)
            guard SchoolLesson.date(value.serverTime) != nil else { throw SchoolReportFailure.invalidResponse }
            return value.data
        } catch { throw SchoolReportFailure.invalidResponse }
    }
    static func failure(_ status: Int, _ code: String?, kind: SchoolCommandKind? = nil, title: String? = nil) -> SchoolReportFailure {
        // AP30 : sans grant `permit_review` (403) ou sans affectation à la formation (404), seul le contrôle
        // du permis est refusé ; la leçon reste lisible et le motif écrit reste possible.
        if kind == .recordPermitCheck && ((status == 403 && code == "PERMIT_REVIEW_REQUIRED") || status == 404) { return .permitReviewRequired }
        if status == 401 { return .unauthorized }; if status == 403 { return .forbidden }; if status == 404 { return .notFound }
        if (status == 412 && code == "VERSION_CONFLICT") || (status == 409 && code == "PUBLICATION_VERSION_CONFLICT") { return .conflict }
        let messages = [
            "REPORT_INCOMPLETE": "Complète le travail réalisé, le constat et la prochaine étape avant de publier.",
            "ANOMALY_REASON_REQUIRED": "Explique le constat avec un contrôle de permis non confirmé et les éventuels écarts horaires.",
            "INVALID_ACTUAL_INTERVAL": "La fin réelle doit suivre le début et ne pas être future.",
            "LESSON_NOT_STARTED": "La leçon n’a pas encore commencé. Termine-la au plus tôt 15 minutes avant son début.",
            "LESSON_NOT_ENDED": "Une absence se note après la fin prévue du rendez-vous.",
            "CORRECTION_REASON_REQUIRED": "Explique la correction avant de publier une nouvelle version.",
            "CURRICULUM_VERSION_MISMATCH": "Le référentiel de cette formation a changé. Relis les compétences.",
            "LESSON_CLOSED": "La leçon possède déjà un résultat. Recharge-la pour retrouver le bilan.",
            "LESSON_NOT_COMPLETED": "Le constat de réalisation doit être enregistré avant ce bilan.",
            "ENTITLEMENT_NOT_READY": "La consommation du pack doit être disponible avant ce constat. Contacte l’école.",
            "WISH_LESSON_INVALID": "Le souhait doit concerner une leçon planifiée de cette formation.",
            "ATTACHMENT_NOT_READY": "Cette pièce n’est pas encore disponible pour le bilan.",
            "OBSERVATION_PUBLICATION_NOT_READY": "Cette sélection d’annotations nécessite encore une qualification avant partage.",
            "OBSERVATION_NOT_IN_LESSON": "Cette observation n’appartient plus à la leçon. Actualise.",
            "CATEGORY_MISMATCH": "La catégorie de cette formation a changé. Actualise la leçon.",
            "TRAINING_NOT_ACTIVE": "La formation n’est plus en cours. Précise la situation du permis.",
            "PERMIT_EXPIRED": "Ce permis est échu. Précise la situation du permis.",
            "INVALID_REQUEST": "Vérifie les informations saisies et leurs longueurs."
        ]
        if (400...499).contains(status), let code, let message = messages[code] { return .rejected(message) }
        // Tout autre refus 4xx motivé par l’école est définitif : son explication (en français) est affichée.
        // Un identifiant d’opération déjà utilisé reste une incertitude à vérifier.
        if (400...499).contains(status), status != 429, let code, code != "IDEMPOTENCY_MISMATCH" {
            let text = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .rejected(text.isEmpty || text.count > 300 ? "L’école a refusé cette demande. Vérifie les informations puis réessaie." : text)
        }
        if code == "IDEMPOTENCY_MISMATCH" { return .uncertain }
        return status >= 500 || status == 429 ? .unavailable : .invalidResponse
    }
}
