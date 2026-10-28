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
    /// L’école a répondu à la lecture des bilans partagés : une liste vide est alors un bilan absent, pas un bilan refusé.
    private(set) var sharedReportWasRead = false
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
    /// Échec du coffre local, distinct d'une écriture refusée par l'école.
    private(set) var localDraftError: String?
    private(set) var localDraftReadFailed = false
    /// Vrai uniquement après le reçu de sauvegarde de ce bilan et le retrait durable de sa demande.
    private(set) var reportSaveConfirmed = false
    private(set) var pendingReviewed = false
    /// Demande que l’école a déclaré ne pas connaître : elle peut être renvoyée comme neuve, ou abandonnée.
    private(set) var absentPendingID: UUID?
    private(set) var needsReload = true
    /// Accès retiré : plus aucune relecture n’aboutira depuis cette fiche.
    var isInvalidated: Bool { invalidated }
    /// Premier envoi d’une demande, juste après le geste : bref, il ne se présente pas comme une demande à vérifier.
    private(set) var isFirstSend = false
    /// L’école vient de confirmer un contenu qu’aucune relecture n’a encore appliqué. La saisie attend cette
    /// relecture : faite avant, elle se comparerait à la version d’avant l’envoi et passerait pour un conflit.
    private(set) var awaitsRereadAfterWrite = false
    var goals: [SchoolLessonGoal] = []
    var administrativeNote = ""
    var wishText = ""
    var workedOn = ""
    var observationText = ""
    var nextStep = ""
    var observations: [SchoolReportObservation] = []
    /// « Travail réalisé » proposé à partir des objectifs, juste après la fin de la leçon. Tant que le moniteur n’y
    /// touche pas, ce n’est pas une saisie à protéger : rien n’en est envoyé avant l’enregistrement du bilan.
    private(set) var workedOnProposal: String?
    @ObservationIgnored private let client: SchoolLessonReportClient
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private let notifications: NotificationCenter
    /// Brouillon chiffré sur l’appareil ; absent, la saisie ne vit qu’en mémoire.
    @ObservationIgnored private let localDrafts: (any SchoolReportLocalDraftStore)?
    /// Cette fiche vient de terminer la leçon : la prochaine lecture propose les objectifs comme travail réalisé.
    @ObservationIgnored private var proposesWorkedOn = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAccessible = false
    @ObservationIgnored private var localDraftRemovalFailed = false
    @ObservationIgnored private var localDraftDiscardRequested = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Dernière révision des objectifs ou du souhait confirmée par l’école, pas encore relue : sa relecture la
    /// reconnaît comme point de départ, et une saisie faite pendant l’envoi n’y passe pas pour un conflit (#113).
    @ObservationIgnored private var confirmedPreparation: PreparationContent?
    @ObservationIgnored private var confirmedWish: String?
    /// Bilan tel qu’il part au premier envoi, puis tel que l’école l’a confirmé alors que la saisie a continué (#114) :
    /// la relecture le reconnaît comme point de départ, la saisie suivante n’est ni remplacée ni prise pour un conflit.
    @ObservationIgnored private var sendingReport: DraftContent?
    @ObservationIgnored private var confirmedReport: DraftContent?

    init(scope: SchoolCommandScope, membership: SchoolMembership, lessonID: UUID, client: SchoolLessonReportClient,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox(), notifications: NotificationCenter = .default,
         localDrafts: (any SchoolReportLocalDraftStore)? = nil) {
        self.scope = scope; self.membership = membership; self.lessonID = lessonID; self.client = client; self.outbox = outbox
        self.notifications = notifications; self.localDrafts = localDrafts
    }
    var isAuthor: Bool { membership.roles.contains("INSTRUCTOR") && lesson?.instructorMembershipId == membership.membershipId }
    var canReadLessonContent: Bool { isAuthor || isOwnLearner || membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") }
    var canReadSharedReport: Bool { isAuthor || isOwnLearner || membership.roles.contains("INSTRUCTOR") }
    var replayableCaptures: [SchoolCaptureSession] { captures.filter(SchoolTripsWorkspace.isReplayable) }
    var canMutate: Bool { !invalidated && !isLoading && !isBusy && !needsReload && storageAccessible && pending == nil && !localDraftReadFailed }
    /// Réglage de partage tout juste demandé, en cours d’envoi : la saisie n’en dépend pas.
    private var isSendingSharing: Bool { isBusy && isFirstSend && pending?.kind == .updateLessonSharing }
    /// Objectifs ou souhait tout juste envoyés (#113) : la saisie continue, la révision suivante attendra leur résultat.
    private var isSendingTextRevision: Bool {
        isBusy && isFirstSend && (pending?.kind == .savePreparation || pending?.kind == .saveWish)
    }
    /// Bilan tout juste envoyé (#114) : la rédaction continue ; ce qui est saisi pendant l’envoi reste à enregistrer.
    var isSendingReport: Bool { isBusy && isFirstSend && pending?.kind == .saveReportDraft }
    /// Saisie possible. Une relecture silencieuse ou l’envoi d’un réglage de partage ne ferment rien à l’écran ;
    /// seul un état qui dure le fait : accès retiré, conflit à relire, stockage fermé, demande à vérifier,
    /// contenu en cours d’enregistrement. L’envoi d’une commande reste gardé par `canMutate`.
    var acceptsInput: Bool {
        guard !invalidated, !needsReload, storageAccessible, !awaitsRereadAfterWrite, !localDraftReadFailed else { return false }
        return pending == nil ? !isBusy : (isSendingSharing || isSendingTextRevision || isSendingReport)
    }
    /// Partage et actions sur les observations : pas pendant l’envoi du bilan, qui peut fermer la fiche.
    var acceptsOtherRequests: Bool { acceptsInput && !isSendingReport }
    /// Demande restée en attente après un envoi sans réponse sûre. Le premier envoi, en cours, n’en est pas une.
    var pendingAwaitsReview: Bool { pending != nil && !(isBusy && isFirstSend) }
    var pendingAbsent: Bool { pending != nil && pending?.id == absentPendingID }
    /// Envoi qui retient la fiche jusqu’à son résultat ; un réglage de partage ou une révision des objectifs, déjà
    /// conservés dans la file chiffrée, ne la retiennent pas.
    var holdsScreen: Bool { isBusy && !isSendingSharing && !isSendingTextRevision }
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
    /// Bilan modifié par le moniteur. Une proposition laissée telle quelle n’en est pas une.
    var reportEdited: Bool {
        guard let draft, draftChanged else { return false }
        if let workedOnProposal, workedOn == workedOnProposal, draft.workedOn.isEmpty, observationText == draft.observationText,
           nextStep == draft.nextStep, observations == draft.observations { return false }
        return true
    }
    /// Saisie non enregistrée : bilan, objectifs ou souhait.
    var hasLocalEdits: Bool { reportEdited || preparationChanged || wishChanged }
    /// Le bilan tel qu’il est saisi : ce que le brouillon local conserve, et ce qu’une pause de frappe surveille.
    var editedReport: SchoolReportLocalDraft.Content {
        .init(workedOn: workedOn, observationText: observationText, nextStep: nextStep, observations: observations)
    }
    var reportIsEmpty: Bool { editedReport.isEmpty }
    /// Étapes de la rédaction en largeur compacte, selon ce que la leçon contient.
    var reportSteps: [SchoolReportStep] {
        SchoolReportFlowRules.steps(hasTrip: !track.isEmpty || !replayableCaptures.isEmpty,
            observationCount: lessonObservations.count, competencyCount: competencies.count)
    }
    /// Écrit la saisie du bilan dans le brouillon chiffré de l’appareil, ou le retire quand il n’y a plus rien à garder.
    /// Un coffre illisible n’écrit rien : la saisie reste en mémoire, jamais en clair sur le disque.
    @discardableResult func persistLocalDraft() -> Bool {
        guard let localDrafts, !invalidated, isAuthor, let draft, lesson?.status == "COMPLETED" else { return false }
        guard !localDraftReadFailed else { return false }
        localDraftRemovalFailed = false
        localDraftDiscardRequested = false
        do {
            if reportEdited {
                try localDrafts.save(SchoolReportLocalDraft(draftID: draft.id, lessonID: lessonID, base: Self.content(of: draft),
                    edited: editedReport, savedAt: Date()), scope: scope)
            } else {
                try localDrafts.remove(scope: scope, draftID: draft.id)
            }
            localDraftError = nil
            return true
        } catch {
            localDraftError = reportEdited
                ? "Le brouillon n’a pas pu être conservé sur cet appareil. Garde cette fiche ouverte et réessaie."
                : "Le brouillon n’a pas pu être supprimé de cet appareil. Réessaie avant de quitter."
            return false
        }
    }
    var requiresLocalDraftResolution: Bool { localDraftReadFailed || localDraftError != nil }

    /// Même sans différence affichée, le retrait de l'ancien brouillon doit être effectif avant la sortie.
    func closeWithoutLocalEdits() -> Bool {
        guard !invalidated, !hasLocalEdits, !holdsScreen, !localDraftReadFailed else { return false }
        if localDrafts != nil, isAuthor, draft != nil, lesson?.status == "COMPLETED" {
            guard persistLocalDraft() else { return false }
        }
        close()
        return true
    }
    /// Le coffre ne contient que le bilan, pas les objectifs ni le souhait : ne pas promettre leur conservation.
    var canKeepLocalDraft: Bool {
        localDrafts != nil && !invalidated && !localDraftReadFailed && isAuthor && draft != nil && lesson?.status == "COMPLETED"
            && reportEdited && !preparationChanged && !wishChanged && !holdsScreen
    }
    /// Aucun envoi à l'école. Une demande déjà en file y reste, même après fermeture de la fiche.
    func keepLocalDraftAndClose() -> Bool {
        guard canKeepLocalDraft, persistLocalDraft() else { return false }
        close()
        return true
    }
    /// Le moniteur renonce à sa saisie, ou l’école vient de l’enregistrer.
    @discardableResult func discardLocalDraft(explicit: Bool = false) -> Bool {
        guard let localDrafts, let draft else { return true }
        guard explicit || !localDraftReadFailed else { return false }
        localDraftDiscardRequested = explicit
        do {
            if explicit { try localDrafts.discard(scope: scope, draftID: draft.id) }
            else { try localDrafts.remove(scope: scope, draftID: draft.id) }
            localDraftReadFailed = false
            localDraftRemovalFailed = false
            localDraftError = nil
            return true
        } catch {
            localDraftRemovalFailed = true
            localDraftError = "Le brouillon n’a pas pu être supprimé de cet appareil. Réessaie avant de quitter."
            return false
        }
    }
    func retryLocalDraft() {
        guard !invalidated else { return }
        if localDraftRemovalFailed { discardLocalDraft(explicit: localDraftDiscardRequested) }
        else if localDraftReadFailed {
            if restoreUnsentReport() {
                needsReload = true
                errorMessage = "Ta saisie est conservée. Le contenu enregistré a changé. Copie ton texte si nécessaire, puis actualise avant d’enregistrer."
            }
        } else { persistLocalDraft() }
    }
    private static func content(of draft: SchoolReportDraft) -> SchoolReportLocalDraft.Content {
        .init(workedOn: draft.workedOn, observationText: draft.observationText, nextStep: draft.nextStep, observations: draft.observations)
    }
    /// Après une lecture qui a remis le bilan sur la version de l’école : reprend la saisie gardée sur l’appareil,
    /// sinon propose les objectifs comme travail réalisé juste après la fin de la leçon.
    /// Rend `true` quand la saisie reprise ne part plus de ce que l’école a enregistré.
    private func restoreUnsentReport() -> Bool {
        guard isAuthor, let draft, lesson?.status == "COMPLETED" else { return false }
        let server = Self.content(of: draft)
        if let localDrafts {
            do {
                let stored = try localDrafts.read(scope: scope, draftID: draft.id)
                localDraftReadFailed = false
                localDraftRemovalFailed = false; localDraftDiscardRequested = false
                localDraftError = nil
                if let stored {
                    if stored.edited == server {
                        _ = discardLocalDraft()
                    } else {
                        workedOn = stored.edited.workedOn; observationText = stored.edited.observationText
                        nextStep = stored.edited.nextStep; observations = stored.edited.observations
                        return stored.base != server
                    }
                }
            } catch {
                localDraftReadFailed = true
                localDraftRemovalFailed = false; localDraftDiscardRequested = false
                localDraftError = "Le brouillon de cet appareil n’a pas pu être relu. Réessaie avant de modifier le bilan."
                return false
            }
        }
        guard proposesWorkedOn, server.isEmpty else { return false }
        proposesWorkedOn = false
        let proposal = SchoolLessonHubRules.completionReport(goals: preparation?.goals ?? [], observations: [], competencies: []).workedOn
        guard !proposal.isEmpty else { return false }
        workedOn = proposal; workedOnProposal = proposal
        return false
    }
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
    /// Permis d’élève vu : par le moniteur de la leçon ; l’école relit son affectation et peut refuser.
    var mayRecordPermit: Bool {
        isAuthor && !permitReviewDenied && !permitRecorded
            && lesson?.status == "PLANNED" && training != nil && training?.id == lesson?.trainingId
    }
    var reportShared: Bool { !(optimisticSharing?.reportPrivate ?? sharing?.reportPrivate ?? false) }
    var captureShared: Bool { !(optimisticSharing?.captureHidden ?? sharing?.captureHidden ?? false) }
    func isPrivate(_ observation: SchoolObservation) -> Bool {
        (optimisticSharing?.privateObservationIds ?? sharing?.privateObservationIds ?? []).contains(observation.id)
    }
    /// Absence de l’élève : après la fin prévue, par le moniteur de la leçon ou l’administration (AP44).
    func mayMarkNoShow(now: Date = Date()) -> Bool {
        guard let lesson, lesson.status == "PLANNED", !lesson.hasStarted, let end = lesson.endsAt, end <= now else { return false }
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
        case .startLesson, .completeLesson: return isAuthor && pending.resourceID == lessonID
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
        case .startLesson: title = "Début de la leçon"
        case .savePreparation: title = "Enregistrement de la préparation"
        case .saveWish: title = "Enregistrement du souhait"
        case .completeLesson: title = "Fin de la leçon"
        case .saveReportDraft: title = "Enregistrement du bilan"
        case .publishReportDraft: title = "Publication du bilan à l’élève"
        case .updateLessonSharing: title = "Partage avec l’élève"
        case .recordPermitCheck: title = "Permis d’élève vu"
        case .markNoShow: title = "Élève absent"
        default: return pending.kind.requestTitle
        }
        guard let body = try? JSONSerialization.jsonObject(with: pending.body) as? [String: Any] else { return title }
        let fields = [("workedOn", "Travail"), ("observationText", "À retenir"), ("nextStep", "Prochaine étape"), ("text", "Souhait"), ("anomalyReason", "Motif"), ("reason", "Motif")]
        return ([title] + fields.compactMap { key, label in (body[key] as? String).map { "\(label) : \($0)" } }).joined(separator: "\n\n")
    }
    func reviewPending() { pendingReviewed = true }
    /// Fiche qui se ferme : plus aucune lecture ni écriture ne s’applique, mais ce qui est affiché reste en place
    /// pendant que la feuille descend (vider l’écran à cet instant faisait apparaître un formulaire vide).
    func close() {
        invalidated = true; generation = UUID(); isLoading = false; isBusy = false
        wake()
    }

    func invalidate() {
        invalidated = true; generation = UUID(); lesson = nil; preparation = nil; wish = nil; draft = nil; revisions = []
        competencies = []; pending = nil; goals = []; administrativeNote = ""; wishText = ""; optimisticSharing = nil
        sharedReportWasRead = false
        workedOn = ""; observationText = ""; nextStep = ""; observations = []
        workedOnProposal = nil; proposesWorkedOn = false
        sharing = nil; lessonObservations = []; track = []; trackAnchors = [:]
        training = nil; account = nil; currentLevels = [:]; captures = []; permitRecorded = false; permitReviewDenied = false
        isLoading = false; isBusy = false; storageAccessible = false; revisionsError = nil; reportSaveConfirmed = false
        isFirstSend = false; awaitsRereadAfterWrite = false
        localDraftError = nil
        localDraftReadFailed = false; localDraftRemovalFailed = false; localDraftDiscardRequested = false
        wake()
    }
    /// Attend la fin de la relecture ou de l’envoi en cours. Un appui fait pendant ce bref passage n’est ni grisé
    /// ni perdu : la commande part ensuite, sur les versions relues, une à la fois.
    func settled() async {
        while !invalidated, isLoading || isBusy { await withCheckedContinuation { waiters.append($0) } }
    }
    private func wake() {
        guard !isLoading, !isBusy else { return }
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting { waiter.resume() }
    }
    private func editedDraft(id: UUID) -> DraftContent {
        DraftContent(id: id, workedOn: workedOn, observationText: observationText, nextStep: nextStep, observations: observations)
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
        if discardingEdits {
            guard discardLocalDraft(explicit: true) else { return }
            proposesWorkedOn = false
        }
        generation = UUID(); let request = generation
        // Une relecture garde l’état affiché : `needsReload`, les notes et la saisie ne changent qu’à son résultat.
        isLoading = true; errorMessage = nil; pendingReviewed = false
        defer { wake() }
        do { pending = try outbox.pending(for: scope, domain: .teaching); storageAccessible = true }
        catch { storageAccessible = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            // Le compte et la leçon se lisent ensemble ; rien n’est montré avant que les droits du compte soient relus.
            let lessonRead = Task { @MainActor in try await self.client.agenda.lesson(schoolID: self.scope.schoolID, id: self.lessonID) }
            defer { lessonRead.cancel() }
            let person = try await client.reader.me()
            guard person.personId == scope.personID, let current = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
                  current.schoolId == scope.schoolID, current.accessEpoch == scope.accessEpoch, current.roles.sorted() == membership.roles.sorted(),
                  current.grants.sorted() == membership.grants.sorted() else { throw SchoolReportFailure.forbidden }
            let lesson = try await lessonRead.value
            let learner = try await client.reader.learner(schoolID: scope.schoolID, id: lesson.learnerId)
            let isOwn = current.roles.contains("LEARNER") && learner.personId == scope.personID
            let author = current.roles.contains("INSTRUCTOR") && lesson.instructorMembershipId == current.membershipId
            let readsContent = author || isOwn || current.roles.contains("ADMIN") || current.roles.contains("INSTRUCTOR")
            // Hors de sa propre leçon, un moniteur ne lit le souhait et le bilan partagé que s’il est affecté à la
            // formation : un refus de l’école laisse alors la section absente, sans message de panne.
            let asColleague = !author && !isOwn
            let id = lessonID, schoolID = scope.schoolID, trainingID = lesson.trainingId
            let learnerID = lesson.learnerId, membershipID = current.membershipId
            let completed = lesson.status == "COMPLETED" && readsContent
            // Leçon à terminer, annulée ou manquée dont l’école dit qu’elle a un trajet : il reste à revoir depuis la
            // fiche. Lecture discrète : un refus ou une panne laisse la section absente, sans message.
            let discreetCaptures = !completed && readsContent && lesson.captureSummary?.hasCapture == true
            // Lectures indépendantes, lancées ensemble : chacune garde sa règle d’absence et son message, et rien n’est
            // publié avant la fin de toutes (une seule mise à jour de l’écran).
            // Le souhait ne se montre qu’avant une leçon : une fiche passée ne le lit plus.
            let wishTask = supplement(request, when: lesson.status == "PLANNED" && (author || isOwn || current.roles.contains("INSTRUCTOR")),
                unavailable: "Le souhait de l’élève n’a pas pu être chargé.", absentWhenRefused: asColleague) {
                try await self.client.wish(schoolID: schoolID, trainingID: trainingID)
            }
            let revisionsTask = supplement(request, when: author || isOwn || current.roles.contains("INSTRUCTOR"),
                unavailable: "Les bilans partagés n’ont pas pu être chargés. Actualise pour les retrouver.", absentWhenRefused: asColleague) {
                try await self.client.revisions(schoolID: schoolID, lessonID: id)
            }
            // Les objectifs sont partagés avec l’élève ; la note administrative lui reste masquée par le serveur.
            let preparationTask = supplement(request, when: author || isOwn, unavailable: "Les objectifs n’ont pas pu être chargés.") {
                try await self.client.preparation(schoolID: schoolID, lessonID: id)
            }
            let draftsTask = supplement(request, when: author && lesson.status == "COMPLETED",
                unavailable: "Le brouillon privé n’a pas pu être chargé. Actualise avant de le modifier.") {
                let values = try await self.client.drafts(schoolID: schoolID, lessonID: id)
                guard values.count <= 1, values.allSatisfy({ $0.authorMembershipId == membershipID }) else { throw SchoolReportFailure.invalidResponse }
                return values
            }
            // Leçon planifiée : le moniteur retrouve ce qu’il a noté pendant le trajet (et le constat le reprend).
            let observationsTask = supplement(request, when: (lesson.status == "COMPLETED" && (author || isOwn)) || (lesson.status == "PLANNED" && author),
                unavailable: "Les observations de la leçon n’ont pas pu être chargées.") {
                try await self.client.agenda.observationClient.observations(scope: self.scope, lessonID: id, trainingID: trainingID, authorOnly: author)
            }
            let accountTask = supplement(request, when: completed, unavailable: "Le solde n’a pas pu être chargé.") {
                try await self.client.account(schoolID: schoolID, lessonID: id)
            }
            let capturesTask = supplement(request, when: completed || discreetCaptures,
                unavailable: "Les trajets n’ont pas pu être chargés. Actualise pour ouvrir le replay.", absentWhenRefused: discreetCaptures) {
                try await self.client.agenda.captureClient.lessonCaptures(schoolID: schoolID, lessonID: id)
            }
            let sharingTask = supplement(request, when: completed && author, unavailable: "Le réglage du partage n’a pas pu être chargé.") {
                try await self.client.sharing(schoolID: schoolID, lessonID: id)
            }
            let curriculumUnavailable = "Le référentiel est momentanément indisponible. Le bilan textuel peut être enregistré sans ajouter de compétence."
            let trainingTask = supplement(request, unavailable: curriculumUnavailable) {
                let training = try await self.client.reader.training(schoolID: schoolID, id: trainingID)
                guard training.id == trainingID, training.learnerId == learnerID else { throw SchoolReportFailure.invalidResponse }
                return training
            }
            // Niveaux actuels de l’élève : ils ne servent qu’au bilan que rédige le moniteur de la leçon. Lecture
            // facultative, leur absence ne bloque ni le bilan ni les autres sections.
            let progressTask = supplement(request, when: author, unavailable: "Les niveaux actuels n’ont pas pu être chargés.") {
                let value = try await self.client.progress(schoolID: schoolID, trainingID: trainingID)
                guard value.trainingId == trainingID else { throw SchoolReportFailure.invalidResponse }
                return value
            }
            // Formation puis référentiel : une chaîne à elle, pour ne pas attendre l’aperçu du trajet.
            let curriculumTask = Task { @MainActor () throws -> (training: (value: SchoolTraining?, message: String?),
                                                                curriculum: (value: [SchoolCatalogCompetency]?, message: String?)) in
                let trainingRead = try await trainingTask.value
                guard let training = trainingRead.value else { return (trainingRead, (nil, trainingRead.message)) }
                let curriculumRead = try await self.readSupplement(request: request, unavailable: curriculumUnavailable) {
                    let curriculaRead = Task { @MainActor in
                        try await self.collect { try await self.client.catalog.curricula(schoolID: schoolID, cursor: $0) }
                    }
                    defer { curriculaRead.cancel() }
                    let offerings = try await self.collect { try await self.client.catalog.offerings(schoolID: schoolID, cursor: $0) }
                    guard let offering = offerings.first(where: { $0.id == training.offeringId }) else { throw SchoolReportFailure.notFound }
                    let curricula = try await curriculaRead.value
                    guard let curriculum = curricula.first(where: { $0.id == offering.curriculumVersionId }) else { throw SchoolReportFailure.notFound }
                    return curriculum.competencies.sorted { $0.sortOrder < $1.sortOrder }
                }
                return (trainingRead, curriculumRead)
            }
            defer {
                wishTask.cancel(); revisionsTask.cancel(); preparationTask.cancel(); draftsTask.cancel()
                observationsTask.cancel(); accountTask.cancel(); capturesTask.cancel(); sharingTask.cancel()
                trainingTask.cancel(); progressTask.cancel(); curriculumTask.cancel()
            }
            // Les lectures qui en attendent une autre partent dès qu’elle répond : l’aperçu du trajet, le référentiel.
            var capturesRead = try await capturesTask.value
            if discreetCaptures { capturesRead.message = nil }
            var trackRead: (value: (segments: [[SchoolCapturePoint]], observations: [SchoolPrivateGeoObservation], pointsByAnchor: [String: SchoolCapturePoint])?, message: String?) = (nil, nil)
            // Une leçon interrompue (fermeture, crash, redémarrage) puis reprise a plusieurs trajets : l’aperçu les
            // montre tous, dans l’ordre, chacun avec ses propres lacunes.
            let replayable = (capturesRead.value ?? []).filter(SchoolTripsWorkspace.isReplayable)
                .sorted { (SchoolLesson.date($0.authorizedAt) ?? .distantPast) < (SchoolLesson.date($1.authorizedAt) ?? .distantPast) }
            if !replayable.isEmpty {
                trackRead = try await readSupplement(request: request,
                    unavailable: "L’aperçu du trajet n’a pas pu être chargé. Tu peux ouvrir le replay pour réessayer.",
                    absentWhenRefused: discreetCaptures) { () async throws -> SchoolCapturePriorTrack.Track in
                    var segments: [[SchoolCapturePoint]] = [], observations: [SchoolPrivateGeoObservation] = []
                    var anchors: [String: SchoolCapturePoint] = [:]
                    for capture in replayable {
                        let part = try await self.client.agenda.captureClient.replayTrack(schoolID: schoolID, captureID: capture.id)
                        segments += part.segments; observations += part.observations
                        anchors.merge(part.pointsByAnchor) { first, _ in first }
                    }
                    return (segments: segments, observations: observations, pointsByAnchor: anchors)
                }
                if discreetCaptures { trackRead.message = nil }
            }
            let (trainingRead, curriculumRead) = try await curriculumTask.value
            let wishRead = try await wishTask.value
            let revisionsRead = try await revisionsTask.value
            let preparationRead = try await preparationTask.value
            let draftsRead = try await draftsTask.value
            let observationsRead = try await observationsTask.value
            let accountRead = try await accountTask.value
            let sharingRead = try await sharingTask.value
            let progressRead = try await progressTask.value
            guard request == generation, !invalidated else { return }
            // Une lecture échouée (message présent) ne remplace jamais ce qui est affiché : bilan, saisie et objectifs restent en place.
            let draftUnread = draftsRead.message != nil, preparationUnread = preparationRead.message != nil
            let receivedDraft = draftsRead.value?.first.map(DraftContent.init)
            let draftBase = confirmedReport.flatMap { $0 == receivedDraft ? $0 : nil } ?? draft.map(DraftContent.init)
            let draftPolicy = draftUnread ? SchoolLessonRefreshPolicy.keepEdits : SchoolLessonRefreshPolicy.decide(previous: draftBase,
                edited: editedDraft(id: draft?.id ?? UUID()), received: receivedDraft,
                discardingEdits: discardingEdits || !author)
            if !draftUnread { confirmedReport = nil }
            // La révision que l’école vient de confirmer, relue telle quelle, sert de point de départ : une saisie
            // poursuivie pendant son envoi est gardée, jamais remplacée par la réponse ni prise pour un conflit.
            let receivedPreparation = preparationRead.value.map(PreparationContent.init)
            let preparationBase = confirmedPreparation.flatMap { $0 == receivedPreparation ? $0 : nil }
                ?? preparation.map(PreparationContent.init)
            let preparationPolicy = preparationUnread ? SchoolLessonRefreshPolicy.keepEdits : SchoolLessonRefreshPolicy.decide(previous: preparationBase,
                edited: PreparationContent(goals: goals, note: administrativeNote), received: receivedPreparation,
                discardingEdits: discardingEdits || !author)
            let wishBase = confirmedWish.flatMap { $0 == wishRead.value?.text ? $0 : nil } ?? wish?.text
            let wishPolicy = SchoolLessonRefreshPolicy.decide(previous: wishBase, edited: wishText,
                received: wishRead.value?.text, discardingEdits: discardingEdits || !isOwn)
            if !preparationUnread { confirmedPreparation = nil }
            if wishRead.message == nil { confirmedWish = nil }
            var conflict = draftPolicy == .conflict || preparationPolicy == .conflict || wishPolicy == .conflict
            self.lesson = lesson
            if preparationPolicy != .conflict, !preparationUnread { preparation = preparationRead.value }
            if wishPolicy != .conflict { wish = wishRead.value }
            // Relecture des bilans partagés en échec : ceux déjà affichés restent, seul le message change.
            if revisionsRead.message == nil { revisions = revisionsRead.value ?? []; sharedReportWasRead = revisionsRead.value != nil }
            revisionsError = revisionsRead.message
            if draftPolicy != .conflict, !draftUnread { draft = draftsRead.value?.first }
            isOwnLearner = isOwn
            training = trainingRead.value
            account = accountRead.value
            if preparationPolicy == .replace { goals = preparation?.goals ?? []; administrativeNote = preparation?.administrativeCheckNote ?? "" }
            if wishPolicy == .replace { wishText = wish?.text ?? "" }
            if draftPolicy == .replace {
                workedOn = draft?.workedOn ?? ""; observationText = draft?.observationText ?? ""; nextStep = draft?.nextStep ?? ""
                observations = draft?.observations ?? []
                workedOnProposal = nil
                if !discardingEdits, restoreUnsentReport() { conflict = true }
            }
            competencies = curriculumRead.value ?? []
            currentLevels = Dictionary((progressRead.value?.items ?? []).map { ($0.competencyId, $0) }, uniquingKeysWith: { first, _ in first })
            if observationsRead.message == nil { lessonObservations = (observationsRead.value ?? []).sorted { ($0.observedAt ?? "") < ($1.observedAt ?? "") } }
            // Le réglage voulu reste affiché jusqu’à la fin de son propre envoi (`updateSharing`).
            sharing = sharingRead.value
            track = trackRead.value?.segments ?? []; trackAnchors = trackRead.value?.pointsByAnchor ?? [:]
            if lesson.status == "COMPLETED" { captures = capturesRead.value ?? [] }
            else if let values = capturesRead.value { captures = values }
            else if !author { captures = [] }
            let notes = [wishRead.message, preparationRead.message, draftsRead.message, accountRead.message,
                         observationsRead.message, capturesRead.message, trackRead.message, sharingRead.message, curriculumRead.message, progressRead.message].compactMap { $0 }
            information = notes.isEmpty ? nil : notes.joined(separator: "\n\n")
            isLoading = false; needsReload = conflict || draftUnread || preparationUnread; awaitsRereadAfterWrite = false
            if conflict {
                errorMessage = "Ta saisie est conservée. Le contenu enregistré a changé ou n’a pas pu être relu. Copie ton texte si nécessaire, puis actualise avant d’enregistrer."
            }
            wake()
            if author && lesson.status == "PLANNED" { await refreshCaptures() }
        } catch {
            guard request == generation, !invalidated else { return }
            // Relecture échouée : l’état de l’école n’est plus connu, toute écriture attend une relecture réussie.
            isLoading = false; needsReload = true; information = nil; revisionsError = nil; fail(error)
        }
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
    // `absentWhenRefused` : the school answers 404 to a colleague who is not assigned to the training. That is a
    // right the reader does not hold, not an outage: the section stays absent and no message is shown.
    /// `readSupplement` dans sa propre tâche, pour lancer ensemble les lectures indépendantes de `load()`.
    /// `when` faux : aucune requête, la section est simplement absente.
    private func supplement<Value: Sendable>(_ request: UUID, when condition: Bool = true, unavailable: String,
                                             absentWhenRefused: Bool = false,
                                             fetch: @escaping @Sendable @MainActor () async throws -> Value) -> Task<(value: Value?, message: String?), Error> {
        Task { @MainActor in
            guard condition else { return (nil, nil) }
            return try await self.readSupplement(request: request, unavailable: unavailable,
                absentWhenRefused: absentWhenRefused, fetch: fetch)
        }
    }
    private func readSupplement<Value>(request: UUID, unavailable: String, absentWhenRefused: Bool = false,
                                       fetch: () async throws -> Value) async throws -> (value: Value?, message: String?) {
        guard request == generation, !invalidated else { throw CancellationError() }
        do {
            let value = try await fetch()
            guard request == generation, !invalidated else { throw CancellationError() }
            return (value, nil)
        } catch {
            guard request == generation, !invalidated else { throw CancellationError() }
            if error is CancellationError || isAccessRevoked(error) { throw error }
            if absentWhenRefused, error as? SchoolReportFailure == .notFound { return (nil, nil) }
            return (nil, unavailable)
        }
    }
    @discardableResult func savePreparation() async -> Bool {
        await settled()
        // Relu après l’attente : un second appui n’envoie pas deux fois les mêmes objectifs.
        guard let preparation, canMutate, isAuthor, preparationValid, preparationChanged else { return false }
        let operation = UUID()
        return await prepare(SchoolSavePreparation(operationId: operation, goals: goals, administrativeCheckNote: administrativeNote), id: operation, kind: .savePreparation, version: preparation.version, resourceID: preparation.id, routeID: lessonID)
    }
    func saveWish() async {
        await settled()
        guard let wish, canMutate, isOwnLearner, wishChanged, wishText.unicodeScalars.count <= 500 else { return }
        let operation = UUID()
        _ = await prepare(SchoolSaveWish(operationId: operation, text: wishText), id: operation, kind: .saveWish, version: wish.version, resourceID: wish.id, routeID: wish.trainingId)
    }
    /// Motif exigé seulement tant que le permis n’est pas confirmé (R07).
    var completionNeedsReason: Bool { lesson?.permitWarning ?? true }
    /// Le départ peut remplacer la fiche par le trajet : sa préparation doit être durable avant cette transition.
    func savePreparationBeforeDeparture() async -> Bool {
        await settled()
        guard canMutate, isAuthor, lesson?.status == "PLANNED" else { return false }
        guard preparationChanged else { return true }
        guard preparationValid else {
            errorMessage = "Vérifie les objectifs et la note avant de continuer."
            return false
        }
        return await savePreparation() && !preparationChanged && canMutate
    }
    /// Même file durable et même preuve d’opération que la fin de leçon.
    func start() async -> Bool {
        // L’heure réelle du départ est celle du geste, avant l’enregistrement des objectifs.
        let gesture = Date()
        guard await savePreparationBeforeDeparture() else { return false }
        guard let lesson, canMutate, isAuthor, lesson.status == "PLANNED", !lesson.hasStarted else { return false }
        let operation = UUID()
        let confirmed = await prepare(SchoolStartLesson(operationId: operation, startedAt: gesture), id: operation, kind: .startLesson,
            version: lesson.version, resourceID: lessonID)
        return confirmed && self.lesson?.hasStarted == true
    }
    func complete(start: Date, end: Date, reason: String, localCaptureStopped: Bool) async -> Bool {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        // Terminer depuis des objectifs en cours de saisie ne doit ni les perdre ni clôturer sur leur ancienne version.
        if preparationChanged {
            guard preparationValid, await savePreparation(), !preparationChanged else { return false }
        }
        guard let lesson, canMutate, isAuthor, lesson.status == "PLANNED", lesson.hasStarted, localCaptureStopped, end > start,
              end <= Date().addingTimeInterval(300), !completionNeedsReason || !trimmed.isEmpty, reason.unicodeScalars.count <= 1_000 else { return false }
        let operation = UUID(), iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Le constat part sans texte : l’école partage tout bilan non vide, et rien n’a encore été rédigé.
        // Les objectifs sont proposés ensuite comme travail réalisé, sur l’appareil seulement.
        proposesWorkedOn = true
        return await prepare(SchoolCompleteLesson(operationId: operation, actualStart: iso.string(from: start), actualEnd: iso.string(from: end),
            workedOn: "", observationText: "", nextStep: "", anomalyReason: trimmed.isEmpty ? nil : reason),
            id: operation, kind: .completeLesson, version: lesson.version, resourceID: lessonID)
    }
    func markNoShow(reason: String) async -> Bool {
        // Une relecture en cours (retour au premier plan, trajet synchronisé) ne fait pas tomber la confirmation.
        await settled()
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
    /// Permis d’élève vu (AP30) : décision APPROVED sur examen physique, sans date de validité inventée.
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
        await settled()
        // Relu après l’attente : un second appui, parti pendant le premier envoi, ne renvoie pas le bilan que
        // l’école vient de confirmer sur une version déjà dépassée.
        guard let draft, canMutate, !awaitsRereadAfterWrite, isAuthor, validTexts, observationsValid else { return false }
        let operation = UUID()
        sendingReport = editedDraft(id: draft.id)
        defer { sendingReport = nil }
        return await prepare(SchoolSaveReport(operationId: operation, workedOn: workedOn, observationText: observationText, nextStep: nextStep, observations: observations), id: operation, kind: .saveReportDraft, version: draft.version, resourceID: draft.id)
    }
    /// Garder pour soi le bilan, le trajet ou certaines observations ; tout le reste est vu par l’élève.
    /// Le réglage se lit aussitôt. Demandé pendant une relecture ou un autre envoi, il attend son tour puis part
    /// de l’état confirmé par l’école : aucun interrupteur ne se grise, aucun geste n’est perdu ni envoyé deux fois.
    func updateSharing(reportPrivate: Bool? = nil, captureHidden: Bool? = nil, observation: UUID? = nil, observationPrivate: Bool = false) async {
        guard let shown = sharing, acceptsOtherRequests, isAuthor else { return }
        let operation = UUID()
        optimisticSharing = sharingRequest(operation,
            reportPrivate: reportPrivate ?? optimisticSharing?.reportPrivate ?? shown.reportPrivate,
            captureHidden: captureHidden ?? optimisticSharing?.captureHidden ?? shown.captureHidden,
            privateIDs: optimisticSharing?.privateObservationIds ?? shown.privateObservationIds,
            observation: observation, observationPrivate: observationPrivate)
        await settled()
        if let confirmed = sharing, canMutate, isAuthor {
            let requested = sharingRequest(operation, reportPrivate: reportPrivate ?? confirmed.reportPrivate,
                captureHidden: captureHidden ?? confirmed.captureHidden, privateIDs: confirmed.privateObservationIds,
                observation: observation, observationPrivate: observationPrivate)
            _ = await prepare(requested, id: operation, kind: .updateLessonSharing, version: confirmed.version, resourceID: lessonID)
        }
        // Un réglage demandé entre-temps garde son affichage : seul le dernier geste efface l’état voulu.
        if optimisticSharing?.operationId == operation { optimisticSharing = nil }
    }
    private func sharingRequest(_ operation: UUID, reportPrivate: Bool, captureHidden: Bool, privateIDs: [UUID],
                                observation: UUID?, observationPrivate: Bool) -> SchoolUpdateSharing {
        var hidden = privateIDs
        if let observation {
            hidden.removeAll { $0 == observation }
            if observationPrivate { hidden.append(observation) }
        }
        return SchoolUpdateSharing(operationId: operation, reportPrivate: reportPrivate, captureHidden: captureHidden,
            privateObservationIds: hidden)
    }
    func retryPending() async { _ = await transmit(firstAttempt: false) }
    func verifyPending() async {
        guard let pending, !invalidated, !isLoading, !isBusy else { return }
        let request = generation; isBusy = true; isFirstSend = false; errorMessage = nil
        defer { wake() }
        do {
            _ = try await client.receipt(for: pending)
            try outbox.remove(pending)
            guard request == generation, !invalidated else { return }
            self.pending = nil; isBusy = false; confirmation = "L’école confirme l’enregistrement de la demande."
            if pending.kind != .updateLessonSharing { awaitsRereadAfterWrite = true }
            announceConfirmedChange(pending)
            if confirmsThisReport(pending) { discardLocalDraft(); reportSaveConfirmed = true; return }
            await load()
        } catch SchoolReportFailure.operationUnknown {
            // L’école répond sans ambiguïté : la fiche reste lisible et la demande peut être renvoyée ou abandonnée.
            guard request == generation, !invalidated else { return }
            isBusy = false; absentPendingID = pending.id
        } catch { guard request == generation, !invalidated else { return }; isBusy = false; fail(error) }
    }
    /// Retire une demande que l’école ne connaît pas, puis relit la leçon : rien n’est supposé enregistré.
    func abandonPending() async {
        guard let pending, pendingAbsent, !invalidated, !isLoading, !isBusy else { return }
        do { try outbox.remove(pending) }
        catch { storageAccessible = false; fail(error); return }
        self.pending = nil; absentPendingID = nil; errorMessage = nil
        await load()
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
        let request = generation; isBusy = true; isFirstSend = firstAttempt; errorMessage = nil; confirmation = nil
        defer { wake() }
        do {
            try outbox.save(command)
            let confirmedSharing = try await client.send(command)
            try outbox.remove(command)
            guard request == generation, !invalidated else { return false }
            pending = nil; isBusy = false
            // Objectifs et souhait : la saisie continue jusqu’à la relecture, qui reconnaît la révision confirmée.
            switch command.kind {
            case .savePreparation:
                confirmedPreparation = (try? JSONDecoder().decode(SchoolSavePreparation.self, from: command.body))
                    .map { PreparationContent(goals: $0.goals, note: $0.administrativeCheckNote) }
            case .saveWish:
                confirmedWish = (try? JSONDecoder().decode(SchoolSaveWish.self, from: command.body))?.text
            case .updateLessonSharing: break
            default: awaitsRereadAfterWrite = true
            }
            announceConfirmedChange(command)
            if confirmsThisReport(command) {
                // Saisie poursuivie pendant l’envoi : la fiche reste ouverte, rien de saisi n’est perdu (#114).
                if let sent = sendingReport, sent != editedDraft(id: sent.id) {
                    confirmedReport = sent
                    confirmation = "Bilan enregistré. Tes dernières modifications restent à enregistrer."
                    await load()
                    persistLocalDraft()
                    return true
                }
                discardLocalDraft(); reportSaveConfirmed = true; return true
            }
            confirmation = Self.confirmationText(for: command.kind)
            // Partage : l’état confirmé suffit. Seul un bilan passé privé ou rendu visible change le brouillon côté école.
            if command.kind == .updateLessonSharing, let confirmedSharing {
                let reportChanged = confirmedSharing.reportPrivate != sharing?.reportPrivate
                sharing = confirmedSharing
                if !reportChanged { return true }
            }
            await load(); return true
        } catch {
            // Une demande que l’école ne connaît pas se renvoie comme neuve : son refus motivé est définitif.
            // Un 404 à l’envoi est aussi une réponse de l’école : rien n’a été enregistré. Un accès qui a changé
            // (autre compte, droits retirés) garde en revanche la demande : elle n’est jamais renvoyée sous ces accès.
            let fresh = firstAttempt || command.id == absentPendingID
            let refused = error as? SchoolReportFailure == .notFound
            if fresh, let failure = error as? SchoolReportFailure, failure.permitsFreshCorrection || refused {
                do { try outbox.remove(command) }
                catch { guard request == generation else { return false }; isBusy = false; storageAccessible = false; fail(error); return false }
                guard request == generation, !invalidated else { return false }
                pending = nil; absentPendingID = nil; needsReload = failure == .conflict || refused
                if failure == .notFound {
                    // L’accès à la leçon se juge à sa relecture, pas au refus d’une commande.
                    isBusy = false; pendingReviewed = false
                    errorMessage = "L’école n’a pas pu traiter « \(command.kind.requestTitle) » : la leçon n’est plus accessible, ou le service de l’école n’est pas à jour. Rien n’a été enregistré."
                    return false
                }
            }
            guard request == generation, !invalidated else { return false }
            isBusy = false; pendingReviewed = false; fail(error); return false
        }
    }
    /// La confirmation nomme ce que l’école vient d’enregistrer ; un réglage de partage, un permis vu, une leçon
    /// terminée ou une absence se lisent déjà dans la fiche et n’en reçoivent pas.
    static func confirmationText(for kind: SchoolCommandKind) -> String? {
        switch kind {
        case .updateLessonSharing, .recordPermitCheck: return nil
        // La fiche change d’état sous les yeux (bilan à rédiger, « Absence » en tête) : rien à redire.
        case .startLesson, .completeLesson, .markNoShow: return nil
        case .savePreparation: return "Objectifs enregistrés."
        case .saveWish: return "Souhait enregistré."
        default: return "Enregistré."
        }
    }
    private func confirmsThisReport(_ command: PendingSchoolCommand) -> Bool {
        command.scope == scope && command.kind == .saveReportDraft && command.resourceID == draft?.id
    }
    private func announceConfirmedChange(_ command: PendingSchoolCommand) {
        let affectsThisLesson = command.scope == scope && command.resourceID != nil && (
            command.resourceID == lessonID || command.resourceID == draft?.id
            || command.resourceID == preparation?.id || command.resourceID == wish?.id)
        // Une demande récupérée dans la file peut appartenir à une autre leçon. Sans cible prouvée,
        // les écrans relisent leurs données autorisées au lieu de publier l'identité de l'écran courant.
        let change = affectsThisLesson ? lesson.map {
            SchoolLessonChange(schoolID: scope.schoolID, trainingID: $0.trainingId, lessonID: lessonID, kind: command.kind)
        } : nil
        notifications.post(name: .drivyLessonsDidChange, object: change)
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
            || error as? SchoolAgendaFailure == .notFound
        if denied { invalidate() }
        if error is CancellationError, pending == nil {
            // Écran relancé ou fermé pendant la lecture : ce n’est pas une panne de l’école.
            errorMessage = "Le chargement a été interrompu. Actualise pour réessayer."
            return
        }
        errorMessage = (error as? SchoolReportFailure)?.localizedDescription
            ?? (error as? SchoolConfigurationFailure)?.localizedDescription
            ?? (error as? SchoolAPIError)?.localizedDescription ?? (error as? SchoolAgendaFailure)?.localizedDescription
            ?? SchoolReportFailure.unavailable.localizedDescription
    }
    private func isAccessRevoked(_ error: any Error) -> Bool {
        if SchoolTrainingAccess.isRevoked(error) || error as? SchoolAPIError == .identityNotLinked { return true }
        if let failure = error as? SchoolAgendaFailure {
            switch failure { case .authentication, .forbidden: return true; default: break }
        }
        return false
    }
}
