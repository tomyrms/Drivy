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
    private(set) var progress: SchoolReportProgress?
    private(set) var account: SchoolLessonAccount?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var isOwnLearner = false
    private(set) var errorMessage: String?
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
    var correctionReason = ""
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
    var canPublish: Bool {
        canMutate && isAuthor && draft != nil && !draftChanged && validTexts && observationsValid
            && observations.allSatisfy { observation in competencies.contains(where: { $0.id == observation.id }) }
            && [workedOn, observationText, nextStep].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && ((lesson?.publicationVersion ?? 0) == 0 || (!correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && correctionReason.unicodeScalars.count <= 1_000))
    }
    var canRetry: Bool {
        guard let pending, pending.kind.isReport, pending.scope == scope, pendingReviewed, !invalidated, !isBusy, !isLoading else { return false }
        switch pending.kind {
        case .completeLesson: return isAuthor && pending.resourceID == lessonID
        case .savePreparation: return isAuthor && pending.routeResourceID == lessonID
        case .saveWish: return isOwnLearner && pending.routeResourceID == lesson?.trainingId
        case .saveReportDraft: return isAuthor && pending.resourceID == draft?.id
        case .publishReportDraft: return isAuthor && pending.routeResourceID == draft?.id
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
        default: return "Une demande provenant d’un autre écran est en attente dans cette école."
        }
        guard let body = try? JSONSerialization.jsonObject(with: pending.body) as? [String: Any] else { return title }
        let fields = [("workedOn", "Travail"), ("observationText", "Constat"), ("nextStep", "Prochaine étape"), ("text", "Souhait"), ("anomalyReason", "Motif"), ("correctionReason", "Correction")]
        return ([title] + fields.compactMap { key, label in (body[key] as? String).map { "\(label) : \($0)" } }).joined(separator: "\n\n")
    }
    func reviewPending() { pendingReviewed = true }
    func invalidate() {
        invalidated = true; generation = UUID(); lesson = nil; preparation = nil; wish = nil; draft = nil; revisions = []
        competencies = []; progress = nil; account = nil; pending = nil; goals = []; administrativeNote = ""; wishText = ""
        workedOn = ""; observationText = ""; nextStep = ""; observations = []; correctionReason = ""
        isLoading = false; isBusy = false; storageAccessible = false
    }
    func load() async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); let request = generation
        isLoading = true; needsReload = true; errorMessage = nil; information = nil; pendingReviewed = false
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
            let wish = try await client.wish(schoolID: scope.schoolID, trainingID: lesson.trainingId)
            let revisions = try await client.revisions(schoolID: scope.schoolID, lessonID: lessonID)
            let progress = try await client.progress(schoolID: scope.schoolID, trainingID: lesson.trainingId)
            let preparation = author ? try await client.preparation(schoolID: scope.schoolID, lessonID: lessonID) : nil
            let drafts = author && lesson.status == "COMPLETED" ? try await client.drafts(schoolID: scope.schoolID, lessonID: lessonID) : []
            guard drafts.count <= 1, drafts.allSatisfy({ $0.authorMembershipId == current.membershipId }) else { throw SchoolReportFailure.invalidResponse }
            let account = lesson.status == "COMPLETED" && (author || isOwn) ? try await client.account(schoolID: scope.schoolID, lessonID: lessonID) : nil
            guard request == generation, !invalidated else { return }
            self.lesson = lesson; self.preparation = preparation; self.wish = wish; self.revisions = revisions; self.progress = progress
            self.draft = drafts.first; self.account = account; isOwnLearner = isOwn
            goals = preparation?.goals ?? []; administrativeNote = preparation?.administrativeCheckNote ?? ""; wishText = wish.text
            workedOn = draft?.workedOn ?? ""; observationText = draft?.observationText ?? ""; nextStep = draft?.nextStep ?? ""
            observations = draft?.observations ?? []; correctionReason = ""; competencies = []
            do {
                do {
                    let training = try await client.reader.training(schoolID: scope.schoolID, id: lesson.trainingId)
                    let offerings = try await collect { try await self.client.catalog.offerings(schoolID: self.scope.schoolID, cursor: $0) }
                    if let offering = offerings.first(where: { $0.id == training.offeringId }) {
                        let curricula = try await collect { try await self.client.catalog.curricula(schoolID: self.scope.schoolID, cursor: $0) }
                        guard request == generation, !invalidated else { return }
                        competencies = curricula.first(where: { $0.id == offering.curriculumVersionId })?.competencies.sorted { $0.sortOrder < $1.sortOrder } ?? []
                    }
                } catch {
                    if error as? SchoolCatalogFailure == .unauthorized || error as? SchoolCatalogFailure == .forbidden { throw SchoolReportFailure.forbidden }
                    guard request == generation, !invalidated else { return }
                    information = "Le référentiel est momentanément indisponible. Le bilan textuel peut être enregistré sans ajouter de compétence."
                }
            }
            guard request == generation, !invalidated else { return }
            isLoading = false; needsReload = false
        } catch { guard request == generation, !invalidated else { return }; isLoading = false; fail(error) }
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
    func complete(start: Date, end: Date, reason: String, localCaptureStopped: Bool) async -> Bool {
        guard let lesson, canMutate, isAuthor, lesson.status == "PLANNED", localCaptureStopped, end > start,
              end <= Date().addingTimeInterval(300), !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.unicodeScalars.count <= 1_000 else { return false }
        let operation = UUID(), iso = ISO8601DateFormatter()
        return await prepare(SchoolCompleteLesson(operationId: operation, actualStart: iso.string(from: start), actualEnd: iso.string(from: end), workedOn: "", observationText: "", nextStep: "", anomalyReason: reason), id: operation, kind: .completeLesson, version: lesson.version, resourceID: lessonID)
    }
    func saveDraft() async {
        guard let draft, canMutate, isAuthor, validTexts, observationsValid else { return }
        let operation = UUID()
        _ = await prepare(SchoolSaveReport(operationId: operation, workedOn: workedOn, observationText: observationText, nextStep: nextStep, observations: observations), id: operation, kind: .saveReportDraft, version: draft.version, resourceID: draft.id)
    }
    func publish() async -> Bool {
        guard let draft, let lesson, canPublish else { return false }
        let operation = UUID()
        return await prepare(SchoolPublishReport(operationId: operation, expectedPublicationVersion: lesson.publicationVersion, correctionReason: correctionReason.isEmpty ? nil : correctionReason), id: operation, kind: .publishReportDraft, version: 0, routeID: draft.id, expectedVersion: draft.version)
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
            confirmation = command.kind == .publishReportDraft ? "Bilan publié : l’élève peut maintenant le consulter." : "Enregistrement confirmé par l’école."
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
        var denied = error as? SchoolReportFailure == .forbidden || error as? SchoolReportFailure == .unauthorized || error as? SchoolReportFailure == .notFound
            || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .unauthorized
        if let failure = error as? SchoolAgendaFailure {
            switch failure { case .authentication, .forbidden: denied = true; default: break }
        }
        if denied { invalidate() }
        errorMessage = (error as? SchoolReportFailure)?.localizedDescription
            ?? (error as? SchoolConfigurationFailure)?.localizedDescription
            ?? (error as? SchoolAPIError)?.localizedDescription ?? SchoolReportFailure.unavailable.localizedDescription
    }
}
