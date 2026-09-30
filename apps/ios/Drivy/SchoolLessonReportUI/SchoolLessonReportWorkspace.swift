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
    /// Partage automatique : ce que le moniteur garde pour lui (auteur seulement).
    private(set) var sharing: SchoolLessonSharing?
    /// Réglage demandé, affiché tout de suite puis remplacé par la réponse de l’école (ou annulé en cas d’échec).
    private(set) var optimisticSharing: SchoolUpdateSharing?
    /// Observations de la leçon : toutes celles de l’auteur, ou celles partagées avec l’élève.
    private(set) var lessonObservations: [SchoolObservation] = []
    /// Trajet reconstruit (segments) et position de chaque mesure, pour ancrer les observations sur la carte.
    private(set) var track: [[SchoolCapturePoint]] = []
    private(set) var trackAnchors: [String: SchoolCapturePoint] = [:]
    /// Formation de la leçon : catégorie et version exigées par le contrôle du permis (AP30).
    private(set) var training: SchoolTraining?
    private(set) var account: SchoolLessonAccount?
    /// Niveaux actuels de l’élève (dernier bilan de chaque compétence, toutes leçons confondues) : point de départ du bilan.
    private(set) var currentLevels: [UUID: SchoolReportProgressItem] = [:]
    /// Trajets de cette leçon connus de l’école (auteur, leçon planifiée) : horaires réels proposés au constat.
    private(set) var captures: [SchoolCaptureSession] = []
    /// Contrôle du permis enregistré depuis cet écran, ou refusé à ce compte par l’école.
    private(set) var permitRecorded = false
    private(set) var permitReviewDenied = false
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var isOwnLearner = false
    private(set) var errorMessage: String?
    private(set) var revisionsError: String?
    private(set) var information: String?
    private(set) var confirmation: String?
    /// Vrai uniquement après le reçu de sauvegarde de ce bilan et le retrait durable de sa demande.
    private(set) var reportSaveConfirmed = false
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
    var canReadLessonContent: Bool { isAuthor || isOwnLearner || membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") }
    var canReadSharedReport: Bool { isAuthor || isOwnLearner || membership.roles.contains("INSTRUCTOR") }
    var replayableCaptures: [SchoolCaptureSession] { captures.filter(SchoolTripsWorkspace.isReplayable) }
    var canMutate: Bool { !invalidated && !isLoading && !isBusy && !needsReload && storageAccessible && pending == nil }
    var validTexts: Bool { [workedOn, observationText, nextStep].allSatisfy { $0.unicodeScalars.count <= 4_000 } }
    var preparationValid: Bool {
        goals.count <= 3 && administrativeNote.unicodeScalars.count <= 4_000 && goals.allSatisfy {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.label.unicodeScalars.count <= 500 && ($0.context?.unicodeScalars.count ?? 0) <= 500
        }
    }
    var observationsValid: Bool {
        observations.count <= 100 && Set(observations.map(\.id)).count == observations.count
            && observations.allSatisfy { ["DISCOVERING", "GUIDED", "INDEPENDENT"].contains($0.level) && $0.context.unicodeScalars.count <= 500 }
    }
    var draftChanged: Bool {
        guard let draft else { return false }
        return workedOn != draft.workedOn || observationText != draft.observationText || nextStep != draft.nextStep || observations != draft.observations
    }
    var preparationChanged: Bool {
        guard isAuthor, let preparation else { return false }
        return goals != preparation.goals || administrativeNote != (preparation.administrativeCheckNote ?? "")
    }
    var wishChanged: Bool {
        guard isOwnLearner, let wish else { return false }
        return wishText != wish.text
    }
    /// Saisie non enregistrée : bilan, objectifs ou souhait.
    var hasLocalEdits: Bool { draftChanged || preparationChanged || wishChanged }
    var retainedEditsText: String {
        ([workedOn, observationText, nextStep] + goals.map(\.label) + [administrativeNote, wishText]
            + observations.map { "\($0.levelLabel) : \($0.context)" })
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    /// Libellé du choix « aucun changement » d’une compétence : son niveau actuel, ou « Pas encore vu ».
    func unchangedChoiceLabel(for competencyID: UUID) -> String {
        SchoolLessonHubRules.unchangedChoiceLabel(current: currentLevels[competencyID], lessonID: lessonID)
    }
    /// Niveau choisi dans un bilan « Pour moi » : il ne compte pas encore dans la progression.
    func levelIsHeldBack(for competencyID: UUID) -> Bool {
        SchoolLessonHubRules.levelIsHeldBack(chosen: observations.contains { $0.id == competencyID }, reportShared: reportShared)
    }
    /// Situation proposée quand une compétence reçoit un niveau.
    var defaultObservationContext: String { lesson.map(SchoolLessonHubRules.observationContext(for:)) ?? "Leçon" }
    /// Le jour et le lieu donnent le contexte. Le texte d'une observation reste attaché à son propre
    /// réglage de confidentialité et n'est jamais recopié automatiquement dans le bilan partagé.
    func setObservationLevel(_ level: String, for competencyID: UUID) {
        observations = SchoolLessonHubRules.observations(observations, setting: level, for: competencyID,
            context: defaultObservationContext)
    }
    /// Horaires proposés au constat : ceux du trajet s’il existe, sinon l’horaire prévu, jamais dans le futur.
    func completionTimes(now: Date = Date()) -> (start: Date, end: Date) {
        guard let lesson else { return (now.addingTimeInterval(-3_000), now) }
        return SchoolLessonHubRules.completionTimes(lesson: lesson, captures: captures, now: now)
    }
    /// « J’ai vu le permis d’élève » : grant `permit_review` du moniteur de la leçon ; l’affectation est relue par le serveur.
    var mayRecordPermit: Bool {
        isAuthor && membership.grants.contains("permit_review") && !permitReviewDenied && !permitRecorded
            && lesson?.status == "PLANNED" && training != nil && training?.id == lesson?.trainingId
    }
    var reportShared: Bool { !(optimisticSharing?.reportPrivate ?? sharing?.reportPrivate ?? false) }
    var captureShared: Bool { !(optimisticSharing?.captureHidden ?? sharing?.captureHidden ?? false) }
    func isPrivate(_ observation: SchoolObservation) -> Bool {
        (optimisticSharing?.privateObservationIds ?? sharing?.privateObservationIds ?? []).contains(observation.id)
    }
    /// Absence de l’élève : après la fin prévue, par le moniteur de la leçon ou l’administration (AP44).
    func mayMarkNoShow(now: Date = Date()) -> Bool {
        guard let lesson, lesson.status == "PLANNED", let end = lesson.endsAt, end <= now else { return false }
        return isAuthor || membership.roles.contains("ADMIN")
    }
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
        case .recordPermitCheck: return isAuthor && pending.routeResourceID == lesson?.trainingId
        case .markNoShow: return (isAuthor || membership.roles.contains("ADMIN")) && pending.resourceID == lessonID
        default: return false
        }
    }
    var pendingDescription: String {
        guard let pending else { return "" }
        let title: String
        switch pending.kind {
        case .savePreparation: title = "Enregistrement de la préparation"
        case .saveWish: title = "Enregistrement du souhait"
        case .completeLesson: title = "Fin de la leçon"
        case .saveReportDraft: title = "Enregistrement du bilan"
        case .publishReportDraft: title = "Publication du bilan à l’élève"
        case .updateLessonSharing: title = "Partage avec l’élève"
        case .recordPermitCheck: title = "Permis d’élève vu"
        case .markNoShow: title = "Élève absent"
        default: return "Une demande provenant d’un autre écran est en attente dans cette école."
        }
        guard let body = try? JSONSerialization.jsonObject(with: pending.body) as? [String: Any] else { return title }
        let fields = [("workedOn", "Travail"), ("observationText", "À retenir"), ("nextStep", "Prochaine étape"), ("text", "Souhait"), ("anomalyReason", "Motif"), ("reason", "Motif")]
        return ([title] + fields.compactMap { key, label in (body[key] as? String).map { "\(label) : \($0)" } }).joined(separator: "\n\n")
    }
    func reviewPending() { pendingReviewed = true }
    func invalidate() {
        invalidated = true; generation = UUID(); lesson = nil; preparation = nil; wish = nil; draft = nil; revisions = []
        competencies = []; pending = nil; goals = []; administrativeNote = ""; wishText = ""; optimisticSharing = nil
        workedOn = ""; observationText = ""; nextStep = ""; observations = []
        sharing = nil; lessonObservations = []; track = []; trackAnchors = [:]
        training = nil; account = nil; currentLevels = [:]; captures = []; permitRecorded = false; permitReviewDenied = false
        isLoading = false; isBusy = false; storageAccessible = false; revisionsError = nil; reportSaveConfirmed = false
    }
    private struct DraftContent: Equatable {
        let id: UUID
        let workedOn: String, observationText: String, nextStep: String
        let observations: [SchoolReportObservation]
        init(_ value: SchoolReportDraft) {
            id = value.id; workedOn = value.workedOn; observationText = value.observationText
            nextStep = value.nextStep; observations = value.observations
        }
        init(id: UUID, workedOn: String, observationText: String, nextStep: String, observations: [SchoolReportObservation]) {
            self.id = id; self.workedOn = workedOn; self.observationText = observationText
            self.nextStep = nextStep; self.observations = observations
        }
    }
    private struct PreparationContent: Equatable {
        let goals: [SchoolLessonGoal]
        let note: String
        init(_ value: SchoolLessonPreparation) { goals = value.goals; note = value.administrativeCheckNote ?? "" }
        init(goals: [SchoolLessonGoal], note: String) { self.goals = goals; self.note = note }
    }
    /// La saisie survit aussi à une panne secondaire ou une modification concurrente. Dans ce dernier
    /// cas, la version ancienne reste attachée au texte et toute écriture attend une relecture explicite.
    func load(discardingEdits: Bool = false) async {
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
            let readsContent = author || isOwn || current.roles.contains("ADMIN") || current.roles.contains("INSTRUCTOR")
            var wishRead: (value: SchoolLearnerWish?, message: String?) = (nil, nil)
            if author || isOwn {
                wishRead = try await readSupplement(request: request, unavailable: "Le souhait de l’élève n’a pas pu être chargé.") {
                    try await self.client.wish(schoolID: self.scope.schoolID, trainingID: lesson.trainingId)
                }
            }
            var revisionsRead: (value: [SchoolReportRevision]?, message: String?) = (nil, nil)
            if author || isOwn || current.roles.contains("INSTRUCTOR") {
                revisionsRead = try await readSupplement(request: request, unavailable: "Les bilans partagés n’ont pas pu être chargés. Actualise pour les retrouver.") {
                    try await self.client.revisions(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                }
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
                    draftsRead = try await readSupplement(request: request, unavailable: "Le brouillon privé n’a pas pu être chargé. Actualise avant de le modifier.") {
                        let values = try await self.client.drafts(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                        guard values.count <= 1, values.allSatisfy({ $0.authorMembershipId == current.membershipId }) else { throw SchoolReportFailure.invalidResponse }
                        return values
                    }
                }
            }
            var observationsRead: (value: [SchoolObservation]?, message: String?) = (nil, nil)
            var capturesRead: (value: [SchoolCaptureSession]?, message: String?) = (nil, nil)
            var trackRead: (value: (segments: [[SchoolCapturePoint]], observations: [SchoolPrivateGeoObservation], pointsByAnchor: [String: SchoolCapturePoint])?, message: String?) = (nil, nil)
            var sharingRead: (value: SchoolLessonSharing?, message: String?) = (nil, nil)
            // Leçon planifiée : le moniteur retrouve ce qu’il a noté pendant le trajet (et le constat le reprend).
            if (lesson.status == "COMPLETED" && (author || isOwn)) || (lesson.status == "PLANNED" && author) {
                observationsRead = try await readSupplement(request: request, unavailable: "Les observations de la leçon n’ont pas pu être chargées.") {
                    try await self.client.agenda.observationClient.observations(scope: self.scope, lessonID: self.lessonID, trainingID: lesson.trainingId, authorOnly: author)
                }
            }
            if lesson.status == "COMPLETED" && readsContent {
                accountRead = try await readSupplement(request: request, unavailable: "Le solde n’a pas pu être chargé.") {
                    try await self.client.account(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                }
                capturesRead = try await readSupplement(request: request, unavailable: "Les trajets n’ont pas pu être chargés. Actualise pour ouvrir le replay.") {
                    try await self.client.agenda.captureClient.lessonCaptures(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                }
                if let capture = capturesRead.value?.last(where: { SchoolTripsWorkspace.isReplayable($0) }) {
                    trackRead = try await readSupplement(request: request, unavailable: "L’aperçu du trajet n’a pas pu être chargé. Tu peux ouvrir le replay pour réessayer.") {
                        try await self.client.agenda.captureClient.replayTrack(schoolID: self.scope.schoolID, captureID: capture.id)
                    }
                }
                if author {
                    sharingRead = try await readSupplement(request: request, unavailable: "Le réglage du partage n’a pas pu être chargé.") {
                        try await self.client.sharing(schoolID: self.scope.schoolID, lessonID: self.lessonID)
                    }
                }
            }
            let trainingRead = try await readSupplement(request: request, unavailable: "Le référentiel est momentanément indisponible. Le bilan textuel peut être enregistré sans ajouter de compétence.") {
                let training = try await self.client.reader.training(schoolID: self.scope.schoolID, id: lesson.trainingId)
                guard training.id == lesson.trainingId, training.learnerId == lesson.learnerId else { throw SchoolReportFailure.invalidResponse }
                return training
            }
            var curriculumRead: (value: [SchoolCatalogCompetency]?, message: String?) = (nil, trainingRead.message)
            if let training = trainingRead.value {
                curriculumRead = try await readSupplement(request: request, unavailable: "Le référentiel est momentanément indisponible. Le bilan textuel peut être enregistré sans ajouter de compétence.") {
                    let offerings = try await self.collect { try await self.client.catalog.offerings(schoolID: self.scope.schoolID, cursor: $0) }
                    guard let offering = offerings.first(where: { $0.id == training.offeringId }) else { throw SchoolReportFailure.notFound }
                    let curricula = try await self.collect { try await self.client.catalog.curricula(schoolID: self.scope.schoolID, cursor: $0) }
                    guard let curriculum = curricula.first(where: { $0.id == offering.curriculumVersionId }) else { throw SchoolReportFailure.notFound }
                    return curriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }
                }
            }
            // Niveaux actuels de l’élève : lecture facultative, leur absence ne bloque ni le bilan ni les autres sections.
            let progressRead = try await readSupplement(request: request, unavailable: "Les niveaux actuels n’ont pas pu être chargés.") {
                let value = try await self.client.progress(schoolID: self.scope.schoolID, trainingID: lesson.trainingId)
                guard value.trainingId == lesson.trainingId else { throw SchoolReportFailure.invalidResponse }
                return value
            }
            guard request == generation, !invalidated else { return }
            let draftPolicy = SchoolLessonRefreshPolicy.decide(previous: draft.map(DraftContent.init),
                edited: DraftContent(id: draft?.id ?? UUID(), workedOn: workedOn, observationText: observationText,
                    nextStep: nextStep, observations: observations), received: draftsRead.value?.first.map(DraftContent.init),
                discardingEdits: discardingEdits || !author)
            let preparationPolicy = SchoolLessonRefreshPolicy.decide(previous: preparation.map(PreparationContent.init),
                edited: PreparationContent(goals: goals, note: administrativeNote), received: preparationRead.value.map(PreparationContent.init),
                discardingEdits: discardingEdits || !author)
            let wishPolicy = SchoolLessonRefreshPolicy.decide(previous: wish?.text, edited: wishText,
                received: wishRead.value?.text, discardingEdits: discardingEdits || !isOwn)
            let conflict = draftPolicy == .conflict || preparationPolicy == .conflict || wishPolicy == .conflict
            self.lesson = lesson
            if preparationPolicy != .conflict { preparation = preparationRead.value }
            if wishPolicy != .conflict { wish = wishRead.value }
            revisions = revisionsRead.value ?? []; revisionsError = revisionsRead.message
            if draftPolicy != .conflict { draft = draftsRead.value?.first }
            isOwnLearner = isOwn
            training = trainingRead.value
            account = accountRead.value
            if preparationPolicy == .replace { goals = preparation?.goals ?? []; administrativeNote = preparation?.administrativeCheckNote ?? "" }
            if wishPolicy == .replace { wishText = wish?.text ?? "" }
            if draftPolicy == .replace {
                workedOn = draft?.workedOn ?? ""; observationText = draft?.observationText ?? ""; nextStep = draft?.nextStep ?? ""
                observations = draft?.observations ?? []
            }
            competencies = curriculumRead.value ?? []
            currentLevels = Dictionary((progressRead.value?.items ?? []).map { ($0.competencyId, $0) }, uniquingKeysWith: { first, _ in first })
            lessonObservations = (observationsRead.value ?? []).sorted { ($0.observedAt ?? "") < ($1.observedAt ?? "") }
            sharing = sharingRead.value; optimisticSharing = nil
            track = trackRead.value?.segments ?? []; trackAnchors = trackRead.value?.pointsByAnchor ?? [:]
            if lesson.status == "COMPLETED" { captures = capturesRead.value ?? [] }
            else if !author { captures = [] }
            let notes = [wishRead.message, preparationRead.message, draftsRead.message, accountRead.message,
                         observationsRead.message, capturesRead.message, trackRead.message, sharingRead.message, curriculumRead.message, progressRead.message].compactMap { $0 }
            information = notes.isEmpty ? nil : notes.joined(separator: "\n\n")
            isLoading = false; needsReload = conflict
            if conflict {
                errorMessage = "Ta saisie est conservée. Le contenu enregistré a changé ou n’a pas pu être relu. Copie ton texte si nécessaire, puis actualise avant d’enregistrer."
            }
            if author && lesson.status == "PLANNED" { await refreshCaptures() }
        } catch { guard request == generation, !invalidated else { return }; isLoading = false; fail(error) }
    }
    /// Lecture discrète des trajets de la leçon : une panne laisse simplement l’horaire prévu au constat.
    func refreshCaptures() async {
        guard let lesson, isAuthor, lesson.status == "PLANNED", !invalidated else { return }
        let request = generation
        guard let values = try? await client.agenda.captureClient.lessonCaptures(schoolID: scope.schoolID, lessonID: lessonID),
              request == generation, !invalidated, self.lesson?.id == lesson.id else { return }
        captures = values
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
    @discardableResult func savePreparation() async -> Bool {
        guard let preparation, canMutate, isAuthor, preparationValid else { return false }
        let operation = UUID()
        return await prepare(SchoolSavePreparation(operationId: operation, goals: goals, administrativeCheckNote: administrativeNote), id: operation, kind: .savePreparation, version: preparation.version, resourceID: preparation.id, routeID: lessonID)
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
        // Terminer depuis des objectifs en cours de saisie ne doit ni les perdre ni clôturer sur leur ancienne version.
        if preparationChanged {
            guard preparationValid, await savePreparation(), !preparationChanged else { return false }
        }
        guard let lesson, canMutate, isAuthor, lesson.status == "PLANNED", localCaptureStopped, end > start,
              end <= Date().addingTimeInterval(300), !completionNeedsReason || !trimmed.isEmpty, reason.unicodeScalars.count <= 1_000 else { return false }
        let operation = UUID(), iso = ISO8601DateFormatter()
        // Le bilan part des objectifs enregistrés et de ce qui a été noté pendant la leçon ; il reste modifiable.
        let prefill = SchoolLessonHubRules.completionReport(goals: preparation?.goals ?? [], observations: lessonObservations,
            competencies: competencies)
        return await prepare(SchoolCompleteLesson(operationId: operation, actualStart: iso.string(from: start), actualEnd: iso.string(from: end),
            workedOn: prefill.workedOn, observationText: prefill.observationText, nextStep: "", anomalyReason: trimmed.isEmpty ? nil : reason),
            id: operation, kind: .completeLesson, version: lesson.version, resourceID: lessonID)
    }
    func markNoShow(reason: String) async -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lesson, canMutate, mayMarkNoShow(), !trimmed.isEmpty, reason.unicodeScalars.count <= 1_000 else { return false }
        let operation = UUID()
        return await prepare(SchoolMarkNoShow(operationId: operation, reason: trimmed), id: operation, kind: .markNoShow,
            version: lesson.version, resourceID: lessonID)
    }
    /// Relit discrètement les observations d’une leçon planifiée (avant le constat qui les reprend).
    func refreshObservations() async {
        guard let lesson, isAuthor, lesson.status == "PLANNED", !invalidated, !isBusy else { return }
        let request = generation
        guard let values = try? await client.agenda.observationClient.observations(scope: scope, lessonID: lessonID, trainingID: lesson.trainingId),
              request == generation, !invalidated else { return }
        lessonObservations = values.sorted { ($0.observedAt ?? "") < ($1.observedAt ?? "") }
    }
    /// « J’ai vu le permis d’élève » (AP30) : décision APPROVED sur examen physique, sans date de validité inventée.
    /// La demande est chiffrée dans la file avant l’envoi ; la leçon est relue après la preuve de l’école.
    func recordPermitSeen() async -> Bool {
        guard let lesson, let training, mayRecordPermit, canMutate, completionNeedsReason else { return false }
        let operation = UUID()
        let recorded = await prepare(SchoolRecordPermitCheck.seen(operationId: operation, categoryCode: training.categoryCode),
            id: operation, kind: .recordPermitCheck, version: 0, routeID: lesson.trainingId, expectedVersion: training.version)
        if recorded { permitRecorded = true }
        return recorded
    }
    @discardableResult func saveDraft() async -> Bool {
        guard let draft, canMutate, isAuthor, validTexts, observationsValid else { return false }
        let operation = UUID()
        return await prepare(SchoolSaveReport(operationId: operation, workedOn: workedOn, observationText: observationText, nextStep: nextStep, observations: observations), id: operation, kind: .saveReportDraft, version: draft.version, resourceID: draft.id)
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
        let requested = SchoolUpdateSharing(operationId: operation, reportPrivate: reportPrivate ?? sharing.reportPrivate,
            captureHidden: captureHidden ?? sharing.captureHidden, privateObservationIds: hidden)
        optimisticSharing = requested
        _ = await prepare(requested, id: operation, kind: .updateLessonSharing, version: sharing.version, resourceID: lessonID)
        optimisticSharing = nil
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
            if confirmsThisReport(pending) { reportSaveConfirmed = true; return }
            await load()
        } catch { guard request == generation, !invalidated else { return }; isBusy = false; fail(error) }
    }
    private func prepare<Value: Encodable>(_ value: Value, id: UUID, kind: SchoolCommandKind, version: Int, resourceID: UUID? = nil, routeID: UUID? = nil, expectedVersion: Int? = nil) async -> Bool {
        guard canMutate else { return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let body = try encoder.encode(value)
            guard body.count <= 200_000 else { errorMessage = "Le contenu dépasse la taille de sauvegarde protégée. Raccourcis les textes avant de confirmer."; return false }
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
            let confirmedSharing = try await client.send(command)
            try outbox.remove(command)
            guard request == generation, !invalidated else { return false }
            pending = nil; isBusy = false
            if confirmsThisReport(command) { reportSaveConfirmed = true; return true }
            confirmation = command.kind == .updateLessonSharing || command.kind == .recordPermitCheck ? nil : "Enregistré."
            // Partage : l’état confirmé suffit. Seul un bilan passé privé ou rendu visible change le brouillon côté école.
            if command.kind == .updateLessonSharing, let confirmedSharing {
                let reportChanged = confirmedSharing.reportPrivate != sharing?.reportPrivate
                sharing = confirmedSharing
                if !reportChanged { return true }
            }
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
    private func confirmsThisReport(_ command: PendingSchoolCommand) -> Bool {
        command.scope == scope && command.kind == .saveReportDraft && command.resourceID == draft?.id
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
        if error as? SchoolReportFailure == .permitReviewRequired { permitReviewDenied = true }
        let denied = isAccessRevoked(error) || error as? SchoolReportFailure == .notFound || error as? SchoolAPIError == .notFound
        if denied { invalidate() }
        if error is CancellationError, pending == nil {
            // Écran relancé ou fermé pendant la lecture : ce n’est pas une panne de l’école.
            errorMessage = "Le chargement a été interrompu. Actualise pour réessayer."
            return
        }
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
