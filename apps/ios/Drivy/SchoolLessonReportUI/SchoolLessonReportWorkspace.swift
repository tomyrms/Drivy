import Foundation
import Observation

@MainActor @Observable final class SchoolLessonReportWorkspace {
    let scope: SchoolCommandScope
    let membership: SchoolMembership
    let lessonID: UUID
    private(set) var lesson: SchoolLesson?
    private(set) var preparation: SchoolLessonPreparation?
    private(set) var wish: SchoolLearnerWish?
    private(set) var draft: SchoolReportDraft?
    private(set) var revisions: [SchoolReportRevision] = []
    private(set) var competencies: [SchoolCatalogCompetency] = []
    private(set) var account: SchoolLessonAccount?
    /// Partage automatique : ce que le moniteur garde pour lui (auteur seulement).
    private(set) var sharing: SchoolLessonSharing?
    /// Observations de la leçon : toutes celles de l’auteur, ou celles partagées avec l’élève.
    private(set) var lessonObservations: [SchoolObservation] = []
    /// Trajet reconstruit (segments) et position de chaque mesure, pour ancrer les observations sur la carte.
    private(set) var track: [[SchoolCapturePoint]] = []
    private(set) var trackAnchors: [String: SchoolCapturePoint] = [:]
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var isOwnLearner = false
    private(set) var errorMessage: String?
    private(set) var revisionsError: String?
    private(set) var information: String?
    private(set) var confirmation: String?
    private(set) var pendingReviewed = false
    private(set) var needsReload = true
    var goals: [SchoolLessonGoal] = []
    var administrativeNote = ""
    var wishText = ""
    var workedOn = ""
    var observationText = ""
    var nextStep = ""
    var observations: [SchoolReportObservation] = []
    @ObservationIgnored private let client: SchoolLessonReportClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAccessible = false

    init(scope: SchoolCommandScope, membership: SchoolMembership, lessonID: UUID, client: SchoolLessonReportClient,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.membership = membership; self.lessonID = lessonID; self.client = client; self.outbox = outbox
    }
    var isAuthor: Bool { membership.roles.contains("INSTRUCTOR") && lesson?.instructorMembershipId == membership.membershipId }
    var canMutate: Bool { !invalidated && !isLoading && !isBusy && !needsReload && storageAccessible && pending == nil }
    var validTexts: Bool { [workedOn, observationText, nextStep].allSatisfy { $0.unicodeScalars.count <= 4_000 } }
    var preparationValid: Bool {
        goals.count <= 3 && administrativeNote.unicodeScalars.count <= 4_000 && goals.allSatisfy {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.label.unicodeScalars.count <= 500 && ($0.context?.unicodeScalars.count ?? 0) <= 500
        }
    }
    var observationsValid: Bool { observations.count <= 100 && Set(observations.map(\.id)).count == observations.count && observations.allSatisfy { !$0.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.context.unicodeScalars.count <= 500 } }
    var draftChanged: Bool {
        guard let draft else { return false }
        return workedOn != draft.workedOn || observationText != draft.observationText || nextStep != draft.nextStep || observations != draft.observations
    }
    var reportShared: Bool { !(sharing?.reportPrivate ?? false) }
    var captureShared: Bool { !(sharing?.captureHidden ?? false) }
    func isPrivate(_ observation: SchoolObservation) -> Bool { sharing?.privateObservationIds.contains(observation.id) ?? false }
    /// Position enregistrée d’une observation ancrée, si le trajet visible la contient.
    func anchor(of observation: SchoolObservation) -> SchoolCapturePoint? {
        guard let segment = observation.segmentId, let sequence = observation.pointSequence else { return nil }
        return trackAnchors["\(segment.uuidString.lowercased()):\(sequence)"]
    }
    var canRetry: Bool {
        guard let pending, pending.kind.isReport, pending.scope == scope, pendingReviewed, !invalidated, !isBusy, !isLoading else { return false }
        switch pending.kind {
        case .completeLesson: return isAuthor && pending.resourceID == lessonID
        case .savePreparation: return isAuthor && pending.routeResourceID == lessonID
        case .saveWish: return isOwnLearner && pending.routeResourceID == lesson?.trainingId
        case .saveReportDraft: return isAuthor && pending.resourceID == draft?.id
        case .publishReportDraft: return isAuthor && pending.routeResourceID == draft?.id
        case .updateLessonSharing: return isAuthor && pending.resourceID == lessonID
        default: return false
        }
    }
    var pendingDescription: String {
        guard let pending else { return "" }
        let title: String
        switch pending.kind {
        case .savePreparation: title = "Enregistrement de la préparation"
        case .saveWish: title = "Enregistrement du souhait"
        case .completeLesson: title = "Constat de réalisation"
        case .saveReportDraft: title = "Enregistrement du brouillon privé"
        case .publishReportDraft: title = "Publication du bilan à l’élève"
        case .updateLessonSharing: title = "Partage avec l’élève"
        default: return "Une demande provenant d’un autre écran est en attente dans cette école."
        }
        guard let body = try? JSONSerialization.jsonObject(with: pending.body) as? [String: Any] else { return title }
        let fields = [("workedOn", "Travail"), ("observationText", "À retenir"), ("nextStep", "Prochaine étape"), ("text", "Souhait"), ("anomalyReason", "Motif")]
        return ([title] + fields.compactMap { key, label in (body[key] as? String).map { "\(label) : \($0)" } }).joined(separator: "\n\n")
    }
    func reviewPending() { pendingReviewed = true }
    func invalidate() {
        invalidated = true; generation = UUID(); lesson = nil; preparation = nil; wish = nil; draft = nil; revisions = []
        competencies = []; account = nil; pending = nil; goals = []; administrativeNote = ""; wishText = ""
        workedOn = ""; observationText = ""; nextStep = ""; observations = []
        sharing = nil; lessonObservations = []; track = []; trackAnchors = [:]
        isLoading = false; isBusy = false; storageAccessible = false; revisionsError = nil
    }
    func load() async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); let request = generation
        isLoading = true; needsReload = true; errorMessage = nil; revisionsError = nil; information = nil; pendingReviewed = false
        do { pending = try outbox.pending(for: scope); storageAccessible = true }
        catch { storageAccessible = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let person = try await client.reader.me()
            guard person.personId == scope.personID, let current = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
                  current.schoolId == scope.schoolID, current.accessEpoch == scope.accessEpoch, current.roles.sorted() == membership.roles.sorted(),
                  current.grants.sorted() == membership.grants.sorted() else { throw SchoolReportFailure.forbidden }
            let lesson = try await client.agenda.lesson(schoolID: scope.schoolID, id: lessonID)
            let learner = try await client.reader.learner(schoolID: scope.schoolID, id: lesson.learnerId)
            let isOwn = current.roles.contains("LEARNER") && learner.personId == scope.personID
            let author = current.roles.contains("INSTRUCTOR") && lesson.instructorMembershipId == current.membershipId
            let wishRead = try await readSupplement(request: request, unavailable: "Le souhait de l’élève n’a pas pu être chargé.") {
                try await self.client.wish(schoolID: self.scope.schoolID, trainingID: lesson.trainingId)
            }
            let revisionsRead = try await readSupplement(request: request, unavailable: "Les bilans partagés n’ont pas pu être chargés. Actualisez pour les retrouver.") {
                try await self.client.revisions(schoolID: self.scope.schoolID, lessonID: self.lessonID)
            }
            var preparationRead: (value: SchoolLessonPreparation?, message: String?) = (nil, nil)
            var draftsRead: (value: [SchoolReportDraft]?, message: String?) = (nil, nil)
            var accountRead: (value: SchoolLessonAccount?, message: String?) = (nil, nil)
            // Les objectifs sont partagés avec l’élève ; la note administrative lui reste masquée par le serveur.
            if author || isOwn {
                preparationRead = try await readSupplement(request: request, unavailable: "Les objectifs n’ont pas pu être chargés.") {
                    try await self.client.preparation(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                }
            }
            if author {
                if lesson.status == "COMPLETED" {
                    draftsRead = try await readSupplement(request: request, unavailable: "Le brouillon privé n’a pas pu être chargé. Actualisez avant de le modifier.") {
                        let values = try await self.client.drafts(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                        guard values.count <= 1, values.allSatisfy({ $0.authorMembershipId == current.membershipId }) else { throw SchoolReportFailure.invalidResponse }
                        return values
                    }
                }
            }
            if lesson.status == "COMPLETED" && (author || isOwn) {
                accountRead = try await readSupplement(request: request, unavailable: "Le compte de la leçon n’a pas pu être chargé.") {
                    try await self.client.account(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                }
            }
            var observationsRead: (value: [SchoolObservation]?, message: String?) = (nil, nil)
            var trackRead: (value: (segments: [[SchoolCapturePoint]], observations: [SchoolPrivateGeoObservation], pointsByAnchor: [String: SchoolCapturePoint])?, message: String?) = (nil, nil)
            var sharingRead: (value: SchoolLessonSharing?, message: String?) = (nil, nil)
            if lesson.status == "COMPLETED" && (author || isOwn) {
                observationsRead = try await readSupplement(request: request, unavailable: "Les observations de la leçon n’ont pas pu être chargées.") {
                    try await self.client.agenda.observationClient.observations(scope: self.scope, lessonID: self.lessonID, trainingID: lesson.trainingId, authorOnly: author)
                }
                trackRead = try await readSupplement(request: request, unavailable: "Le trajet n’a pas pu être chargé.") {
                    let captures = try await self.client.agenda.captureClient.lessonCaptures(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                    guard let capture = captures.last(where: { $0.syncState == .synced || $0.syncState == .partial }) else { return ([], [], [:]) }
                    return try await self.client.agenda.captureClient.replayTrack(schoolID: self.scope.schoolID, captureID: capture.id)
                }
                if author {
                    sharingRead = try await readSupplement(request: request, unavailable: "Le réglage du partage n’a pas pu être chargé.") {
                        try await self.client.sharing(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                    }
                }
            }
            let curriculumRead = try await readSupplement(request: request, unavailable: "Le référentiel est momentanément indisponible. Le bilan textuel peut être enregistré sans ajouter de compétence.") {
                let training = try await self.client.reader.training(schoolID: self.scope.schoolID, id: lesson.trainingId)
                let offerings = try await self.collect { try await self.client.catalog.offerings(schoolID: self.scope.schoolID, cursor: $0) }
                guard let offering = offerings.first(where: { $0.id == training.offeringId }) else { throw SchoolReportFailure.notFound }
                let curricula = try await self.collect { try await self.client.catalog.curricula(schoolID: self.scope.schoolID, cursor: $0) }
                guard let curriculum = curricula.first(where: { $0.id == offering.curriculumVersionId }) else { throw SchoolReportFailure.notFound }
                return curriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }
            }
            guard request == generation, !invalidated else { return }
            self.lesson = lesson; preparation = preparationRead.value; wish = wishRead.value
            revisions = revisionsRead.value ?? []; revisionsError = revisionsRead.message
            draft = draftsRead.value?.first; account = accountRead.value; isOwnLearner = isOwn
            goals = preparation?.goals ?? []; administrativeNote = preparation?.administrativeCheckNote ?? ""; wishText = wish?.text ?? ""
            workedOn = draft?.workedOn ?? ""; observationText = draft?.observationText ?? ""; nextStep = draft?.nextStep ?? ""
            observations = draft?.observations ?? []; competencies = curriculumRead.value ?? []
            lessonObservations = observationsRead.value ?? []; sharing = sharingRead.value
            track = trackRead.value?.segments ?? []; trackAnchors = trackRead.value?.pointsByAnchor ?? [:]
            let notes = [wishRead.message, preparationRead.message, draftsRead.message, accountRead.message,
                         observationsRead.message, trackRead.message, sharingRead.message, curriculumRead.message].compactMap { $0 }
            information = notes.isEmpty ? nil : notes.joined(separator: "\n\n")
            isLoading = false; needsReload = false
        } catch { guard request == generation, !invalidated else { return }; isLoading = false; fail(error) }
    }
    // A failed secondary read must not hide independently authorized content. Only
    // authentication/access changes invalidate the whole projection; missing resources
    // and transient failures leave that section unavailable, never editable as empty data.
    private func readSupplement<Value>(request: UUID, unavailable: String, fetch: () async throws -> Value) async throws -> (value: Value?, message: String?) {
        guard request == generation, !invalidated else { throw CancellationError() }
        do {
            let value = try await fetch()
            guard request == generation, !invalidated else { throw CancellationError() }
            return (value, nil)
        } catch {
            guard request == generation, !invalidated else { throw CancellationError() }
            if error is CancellationError || isAccessRevoked(error) { throw error }
            return (nil, unavailable)
        }
    }
    func savePreparation() async {
        guard let preparation, canMutate, isAuthor, preparationValid else { return }
        let operation = UUID()
        _ = await prepare(SchoolSavePreparation(operationId: operation, goals: goals, administrativeCheckNote: administrativeNote), id: operation, kind: .savePreparation, version: preparation.version, resourceID: preparation.id, routeID: lessonID)
    }
    func saveWish() async {
        guard let wish, canMutate, isOwnLearner, wishText.unicodeScalars.count <= 500 else { return }
        let operation = UUID()
        _ = await prepare(SchoolSaveWish(operationId: operation, text: wishText), id: operation, kind: .saveWish, version: wish.version, resourceID: wish.id, routeID: wish.trainingId)
    }
    /// Motif exigé seulement tant que le permis n’est pas confirmé (R07).
    var completionNeedsReason: Bool { lesson?.permitWarning ?? true }
    func complete(start: Date, end: Date, reason: String, localCaptureStopped: Bool) async -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lesson, canMutate, isAuthor, lesson.status == "PLANNED", localCaptureStopped, end > start,
              end <= Date().addingTimeInterval(300), !completionNeedsReason || !trimmed.isEmpty, reason.unicodeScalars.count <= 1_000 else { return false }
        let operation = UUID(), iso = ISO8601DateFormatter()
        return await prepare(SchoolCompleteLesson(operationId: operation, actualStart: iso.string(from: start), actualEnd: iso.string(from: end), workedOn: "", observationText: "", nextStep: "", anomalyReason: trimmed.isEmpty ? nil : reason), id: operation, kind: .completeLesson, version: lesson.version, resourceID: lessonID)
    }
    func saveDraft() async {
        guard let draft, canMutate, isAuthor, validTexts, observationsValid else { return }
        let operation = UUID()
        _ = await prepare(SchoolSaveReport(operationId: operation, workedOn: workedOn, observationText: observationText, nextStep: nextStep, observations: observations), id: operation, kind: .saveReportDraft, version: draft.version, resourceID: draft.id)
    }
    /// Garder pour soi le bilan, le trajet ou certaines observations ; tout le reste est vu par l’élève.
    func updateSharing(reportPrivate: Bool? = nil, captureHidden: Bool? = nil, observation: UUID? = nil, observationPrivate: Bool = false) async {
        guard let sharing, canMutate, isAuthor else { return }
        var hidden = sharing.privateObservationIds
        if let observation {
            hidden.removeAll { $0 == observation }
            if observationPrivate { hidden.append(observation) }
        }
        let operation = UUID()
        _ = await prepare(SchoolUpdateSharing(operationId: operation, reportPrivate: reportPrivate ?? sharing.reportPrivate,
            captureHidden: captureHidden ?? sharing.captureHidden, privateObservationIds: hidden),
            id: operation, kind: .updateLessonSharing, version: sharing.version, resourceID: lessonID)
    }
    func retryPending() async { _ = await transmit(firstAttempt: false) }
    func verifyPending() async {
        guard let pending, !invalidated, !isLoading, !isBusy else { return }
        let request = generation; isBusy = true; errorMessage = nil
        do {
            _ = try await client.receipt(for: pending)
            try outbox.remove(pending)
            guard request == generation, !invalidated else { return }
            self.pending = nil; isBusy = false; confirmation = "L’école confirme l’enregistrement de la demande."
            await load()
        } catch { guard request == generation, !invalidated else { return }; isBusy = false; fail(error) }
    }
    private func prepare<Value: Encodable>(_ value: Value, id: UUID, kind: SchoolCommandKind, version: Int, resourceID: UUID? = nil, routeID: UUID? = nil, expectedVersion: Int? = nil) async -> Bool {
        guard canMutate else { return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(value)
            guard body.count <= 200_000 else { errorMessage = "Le contenu dépasse la taille de sauvegarde protégée. Raccourcissez les textes avant de confirmer."; return false }
            let command = PendingSchoolCommand(id: id, scope: scope, kind: kind, resourceVersion: version, createdAt: Date(), body: body, resourceID: resourceID, routeResourceID: routeID, expectedVersion: expectedVersion)
            try outbox.save(command); pending = command; pendingReviewed = true
        } catch { storageAccessible = false; fail(error); return false }
        return await transmit(firstAttempt: true)
    }
    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetry, let command = pending else { return false }
        let request = generation; isBusy = true; errorMessage = nil; confirmation = nil
        do {
            try outbox.save(command)
            try await client.send(command)
            try outbox.remove(command)
            guard request == generation, !invalidated else { return true }
            pending = nil; isBusy = false
            confirmation = command.kind == .updateLessonSharing ? nil : "Enregistré."
            await load(); return true
        } catch {
            if firstAttempt, let failure = error as? SchoolReportFailure, failure.permitsFreshCorrection {
                do { try outbox.remove(command) }
                catch { guard request == generation else { return false }; isBusy = false; storageAccessible = false; fail(error); return false }
                guard request == generation, !invalidated else { return false }
                pending = nil; needsReload = failure == .conflict
            }
            guard request == generation, !invalidated else { return false }
            isBusy = false; pendingReviewed = false; fail(error); return false
        }
    }
    private func collect<Value: SchoolCatalogRecord>(_ fetch: (String?) async throws -> SchoolPage<Value>) async throws -> [Value] {
        var values: [Value] = [], cursor: String?, seen = Set<String>()
        repeat {
            let page = try await fetch(cursor)
            guard page.items.allSatisfy({ $0.schoolId == scope.schoolID }), values.count + page.items.count <= 10_000 else { throw SchoolReportFailure.invalidResponse }
            values.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolReportFailure.invalidResponse }
        } while cursor != nil
        return values
    }
    private func fail(_ error: any Error) {
        let denied = isAccessRevoked(error) || error as? SchoolReportFailure == .notFound || error as? SchoolAPIError == .notFound
        if denied { invalidate() }
        errorMessage = (error as? SchoolReportFailure)?.localizedDescription
            ?? (error as? SchoolConfigurationFailure)?.localizedDescription
            ?? (error as? SchoolAPIError)?.localizedDescription ?? SchoolReportFailure.unavailable.localizedDescription
    }
    private func isAccessRevoked(_ error: any Error) -> Bool {
        if SchoolTrainingAccess.isRevoked(error) || error as? SchoolAPIError == .identityNotLinked { return true }
        if let failure = error as? SchoolAgendaFailure {
            switch failure { case .authentication, .forbidden: return true; default: break }
        }
        return false
    }
}
