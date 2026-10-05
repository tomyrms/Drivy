import SwiftUI

/// L’écran unique d’une leçon : avant (objectifs, départ du trajet), pendant (trajet en cours, observations),
/// après (objectifs prévus, bilan, trajet, observations). Une leçon annulée ou manquée garde ses objectifs prévus. Tout est partagé avec l’élève automatiquement ; le moniteur garde
/// pour lui ce qu’il choisit.
/// Une leçon terminée se relit ici. Le moniteur rédige son bilan dans des étapes poussées depuis cette fiche
/// (`SchoolReportStepView`) ; dès que la fenêtre est assez large, il le rédige sur place, en deux colonnes.
struct SchoolLessonReportView: View {
    let client: SchoolLessonReportClient
    @Bindable var schoolWorkspace: SchoolWorkspace
    let lessonID: UUID
    let learnerName: String
    /// Propose la fin dès que la leçon est lue (« À terminer » d’Aujourd’hui, fin du trajet).
    var opensCompletion = false
    /// Seule la carte transmet ce consentement après sa confirmation explicite.
    var completionConfirmed = false
    /// Élève : le souhait se modifie sur la prochaine leçon seulement ; `nil` quand l’appelant ne le sait pas.
    var isNextPlanned: Bool? = nil
    var outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()
    @State private var model: SchoolLessonReportWorkspace?
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmsDiscard = false
    @State private var isCompletingLesson = false

    private var hasUnsavedChanges: Bool { model?.hasLocalEdits ?? false }

    private var scopeKey: String {
        "\(schoolWorkspace.person?.personId.uuidString ?? ""):\(schoolWorkspace.membership?.membershipId.uuidString ?? ""):\(schoolWorkspace.membership?.accessEpoch ?? 0):\(schoolWorkspace.membership?.roles.joined(separator: ",") ?? ""):\(schoolWorkspace.membership?.grants.joined(separator: ",") ?? ""):\(lessonID):\(client.baseURL.absoluteString)"
    }
    private func matches(_ value: SchoolLessonReportWorkspace) -> Bool {
        value.scope.personID == schoolWorkspace.person?.personId && value.scope.membershipID == schoolWorkspace.membership?.membershipId
            && value.scope.schoolID == schoolWorkspace.membership?.schoolId && value.scope.accessEpoch == schoolWorkspace.membership?.accessEpoch
            && value.membership.roles == schoolWorkspace.membership?.roles && value.membership.grants == schoolWorkspace.membership?.grants
            && value.scope.apiBaseURL == client.baseURL.absoluteString
    }
    var body: some View {
        Group {
            if let model, matches(model) {
                SchoolLessonReportContent(model: model, learnerName: learnerName, schoolWorkspace: schoolWorkspace, agenda: client.agenda,
                    opensCompletion: opensCompletion, completionConfirmed: completionConfirmed, isNextPlanned: isNextPlanned,
                    isFinishing: $isCompletingLesson)
            } else if schoolWorkspace.membership != nil {
                if opensCompletion && completionConfirmed {
                    SchoolLessonFinishingView()
                } else {
                    DrivySkeletonRows(count: 4)
                        .drivySkeleton("Chargement de la leçon…")
                        .drivyPageContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(DrivyTheme.canvas)
                }
            } else {
                ContentUnavailableView("Choisis ton école", systemImage: "building.2")
            }
        }
        // La fiche reste « Leçon » : le bilan se rédige dans des étapes qui portent leur propre titre.
        .navigationTitle("Leçon")
        .navigationBarTitleDisplayMode(.inline)
        .presentationSizing(.page)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") {
                    if hasUnsavedChanges {
                        confirmsDiscard = true
                    } else {
                        // Sans saisie à garder, le brouillon local éventuel est retiré avec la fiche.
                        model?.persistLocalDraft(); model?.invalidate(); dismiss()
                    }
                }
                // Un réglage de partage, bref, ne grise pas « Fermer » : sa demande reste dans la file chiffrée.
                .disabled(model?.holdsScreen == true || isCompletingLesson)
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges || model?.isBusy == true || isCompletingLesson)
        .onChange(of: scenePhase) { _, phase in
            guard let model, matches(model) else { return }
            // L’app quitte le premier plan : la saisie du bilan est écrite sur l’appareil avant tout verrouillage.
            guard phase == .active else { model.persistLocalDraft(); return }
            guard !model.isLoading, !model.isBusy, !isCompletingLesson else { return }
            Task { await model.load() }
        }
        .onChange(of: model?.reportSaveConfirmed) { _, confirmed in
            guard confirmed == true else { return }
            capture?.closeLessonFlow(lessonID: lessonID)
            model?.invalidate()
            dismiss()
        }
        .alert("Quitter sans enregistrer ?", isPresented: $confirmsDiscard) {
            Button("Quitter sans enregistrer", role: .destructive) { model?.discardLocalDraft(); model?.invalidate(); dismiss() }
            Button("Continuer", role: .cancel) { }
        }
        .task(id: scopeKey) {
            // Une feuille enfant plein écran peut faire réapparaître cette vue : garder le modèle
            // tant que le compte et l’école ne changent pas.
            if let model, matches(model) { return }
            model?.invalidate(); model = nil
            guard let person = schoolWorkspace.person, let membership = schoolWorkspace.membership else { return }
            let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId, membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
            // Le brouillon local suit la file chiffrée de l’app. Une file de substitution (revue visuelle, tests)
            // n’écrit rien sur l’appareil : la saisie y reste en mémoire.
            let drafts: (any SchoolReportLocalDraftStore)? = outbox is EncryptedSchoolCommandOutbox ? EncryptedSchoolReportDraftStore() : nil
            let value = SchoolLessonReportWorkspace(scope: scope, membership: membership, lessonID: lessonID, client: client, outbox: outbox,
                localDrafts: drafts)
            model = value; await value.load()
        }
    }
}

/// Une seule attente pendant le constat durable et la lecture du bilan, sans fiche planifiée intermédiaire.
private struct SchoolLessonFinishingView: View {
    var body: some View {
        ProgressView("Préparation du bilan…")
            .controlSize(.large)
            .font(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DrivyTheme.canvas)
            .accessibilityIdentifier("lesson-finishing")
    }
}

/// Seuils et colonnes de la leçon : contexte à gauche, bilan à droite dès que la fenêtre le permet.
private enum LessonLayout {
    static let splitBreakpoint: CGFloat = 900
    static let contextColumnWidth = DrivyMapLayout.sidebarWidth
    static let splitMaxWidth: CGFloat = 1248
    static let formMaxWidth = DrivyLayout.formColumn
}

private struct SchoolLessonReportContent: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let learnerName: String
    @Bindable var schoolWorkspace: SchoolWorkspace
    let agenda: SchoolAgendaClient
    let opensCompletion: Bool
    let completionConfirmed: Bool
    let isNextPlanned: Bool?
    /// Contrôleur de séance de l’app ; absent, rien de ce qui dépend du GPS de l’appareil n’est proposé.
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lessonSheet: LessonSheet?
    @State private var router = SchoolReportRouter()
    /// Rédaction du bilan en étapes : ouverte seule après « Terminer », sinon depuis la barre basse.
    @State private var showsReport = false
    @State private var reportSteps: [SchoolReportStep] = []
    /// La leçon vient d’être terminée ici : la rédaction s’ouvre dès que la fiche est de nouveau à l’écran.
    @State private var opensReportWhenReady = false
    @Binding var isFinishing: Bool
    @State private var finishError: String?
    @State private var completionOpened = false
    @State private var confirmsCompletion = false
    @State private var completionQueued = false
    @State private var showReloadConfirmation = false
    @State private var confirmsNoShow = false
    @State private var showsLive = false
    @State private var capturePreparation: SchoolCapturePreparationWorkspace?
    @State private var planningRoute: PlanningRoute?

    private enum LessonSheet: String, Identifiable {
        case permit
        var id: String { rawValue }
    }

    private struct PlanningRoute: Identifiable {
        let id = UUID()
        let model: SchoolPlanningWorkspace
        let cancelling: Bool
    }
    /// Barre du bas d’une leçon planifiée du moniteur, selon l’heure et le trajet.
    private enum PlannedBar: Equatable {
        case live(finishable: Bool)
        case start(finishable: Bool)
        case finish
        case goals(startsAt: String?)
    }

    private var isCompleted: Bool { model.lesson?.status == "COMPLETED" }
    private var isPlanned: Bool { model.lesson?.status == "PLANNED" }
    /// L’élève ne reçoit que ce qui lui est partagé ; le moniteur voit tout, y compris ce qu’il garde pour lui.
    private var readsLesson: Bool { model.canReadLessonContent }
    private var captureStatus: SchoolLessonCaptureStatus { SchoolLessonCaptureStatus(controller: capture, lessonID: model.lessonID) }
    private var reportContext: SchoolReportContext {
        SchoolReportContext(agenda: agenda, learnerName: learnerName, schoolWorkspace: schoolWorkspace)
    }
    /// Le moniteur de la leçon rédige ou reprend son bilan.
    private var editsReport: Bool { model.isAuthor && isCompleted && model.draft != nil }

    var body: some View {
        TimelineView(.everyMinute) { context in
            if isFinishing || completionQueued || awaitsConfirmedCompletion {
                SchoolLessonFinishingView()
            } else {
                form(now: context.date)
            }
        }
        .tint(DrivyTheme.accent)
        .alert("Terminer la leçon ?", isPresented: $confirmsCompletion) {
            Button("Terminer") { beginCompletion() }
                .accessibilityIdentifier("lesson-confirm-completion")
            Button("Continuer", role: .cancel) { }
        }
        .alert("Recharger et perdre la saisie ?", isPresented: $showReloadConfirmation) {
            Button("Recharger", role: .destructive) { Task { await model.load(discardingEdits: true) } }
            Button("Annuler", role: .cancel) {}
        }
        .alert("L’élève est absent ?", isPresented: $confirmsNoShow) {
            Button("Élève absent", role: .destructive) { Task { _ = await model.markNoShow(reason: "Élève absent au rendez-vous.") } }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(item: $lessonSheet) { sheet in
            switch sheet {
            case .permit: SchoolLessonCompletionSheet(model: model, finish: finishLesson)
            }
        }
        .modifier(SchoolReportPresentations(router: router, model: model, context: reportContext))
        .modifier(SchoolReportLocalDraftKeeper(model: model))
        .sheet(item: $capturePreparation, onDismiss: { captureSheetClosed() }) { preparation in
            SchoolCapturePreparationView(model: preparation, schoolWorkspace: schoolWorkspace)
        }
        .sheet(item: $planningRoute, onDismiss: { Task { await model.load() } }) { route in
            SchoolPlanningView(model: route.model, cancelling: route.cancelling)
        }
        .navigationDestination(isPresented: $showsLive) {
            if let capture {
                SchoolCaptureLiveView(controller: capture, learnerName: learnerName, openLesson: { _, completing in
                    if completing { beginCompletion() }
                    showsLive = false
                }, observationClient: agenda.observationClient)
            }
        }
        .navigationDestination(isPresented: $showsReport) {
            if !reportSteps.isEmpty {
                SchoolReportStepView(model: model, context: reportContext, steps: reportSteps, index: 0)
            }
        }
        // Retour sur la fiche : la saisie reste dans le modèle et se garde aussi sur l’appareil.
        .onChange(of: showsReport) { _, shown in if !shown { model.persistLocalDraft() } }
        .onChange(of: captureStatus) { _, status in if status != .collecting && status != .stopped { showsLive = false } }
        .onChange(of: showsLive) { _, visible in
            if !visible { Task { await model.refreshObservations() } }
        }
        .onChange(of: model.lesson?.status) { _, _ in openCompletionIfAsked() }
        .onChange(of: model.isLoading) { _, loading in if !loading { openCompletionIfAsked() } }
        .onChange(of: capture?.finalizedSyncState) { _, state in
            if isCompleted && !isFinishing && (state == .synced || state == .partial) { Task { await model.load() } }
        }
        .onAppear { openCompletionIfAsked() }
        .interactiveDismissDisabled(isFinishing || completionQueued || awaitsConfirmedCompletion)
    }

    private func form(now: Date) -> some View {
        let bar = plannedBar(now: now)
        return GeometryReader { geometry in
            // Fenêtre large : le contexte reste à portée pendant la rédaction, sur un seul écran. Plus étroite
            // (iPhone, Slide Over, grand texte) : la fiche se relit et le bilan se rédige en étapes. La saisie vit
            // dans le modèle, au-dessus de ce changement de composition et des rotations de la fenêtre.
            let split = geometry.size.width >= LessonLayout.splitBreakpoint && hasCompletedReport && !typeSize.isAccessibilitySize
            layout(split: split, bar: bar)
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(bar, split: split) }
                .onChange(of: opensReportWhenReady, initial: true) { _, wanted in
                    guard wanted else { return }
                    opensReportWhenReady = false
                    if !split { openReport() }
                }
        }
        .background(DrivyTheme.canvas)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Relecture ou envoi déjà en cours : l’appui est ignoré, le bouton ne se grise pas.
                    guard !model.isBusy, !model.isLoading else { return }
                    if model.hasLocalEdits { showReloadConfirmation = true } else { Task { await model.load() } }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { lessonMenu(now: now) }
        }
    }

    private var hasCompletedReport: Bool {
        isCompleted && ((model.isAuthor && model.draft != nil) || (!model.isAuthor && model.canReadSharedReport))
    }

    @ViewBuilder private func layout(split: Bool, bar: PlannedBar?) -> some View {
        if split {
            HStack(spacing: 0) {
                Form { lessonContext }
                    .scrollContentBackground(.hidden)
                    .frame(width: LessonLayout.contextColumnWidth)
                Form { completedReport(editing: true) }
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    // Le bilan démarre à la hauteur du nom de l’élève, pas au bord de la barre.
                    .contentMargins(.top, DrivySpacing.m, for: .scrollContent)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: LessonLayout.splitMaxWidth)
            .frame(maxWidth: .infinity)
        } else {
            Form {
                headerSection
                lessonNotices
                plannedGoals
                completedReport(editing: false)
                lessonEvidence(mapHeight: DrivyMapLayout.previewHeight)
                // Avant la leçon : le souhait de l’élève éclaire les objectifs, puis viennent les observations.
                plannedSections(bar: bar)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: LessonLayout.formMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func plannedSections(bar: PlannedBar?) -> some View {
        Group {
            if let wish = model.wish, showsWish(wish) { wishSection(wish) }
            if isPlanned, model.isAuthor { goalsEditor(savesInline: !isGoalsBar(bar)) }
            if isPlanned, model.isOwnLearner, let goals = model.preparation?.goals, !goals.isEmpty { goalsReader(goals) }
        }
        .drivyFormRows()
        if isPlanned, model.isAuthor { SchoolReportObservationsSection(model: model, router: router, context: reportContext) }
    }

    /// Barre basse : les gestes d’une leçon planifiée ; pour une leçon terminée, l’enregistrement du bilan quand
    /// il se rédige sur place, sinon l’entrée dans sa rédaction.
    @ViewBuilder private func bottomBar(_ bar: PlannedBar?, split: Bool) -> some View {
        if let bar {
            plannedBarView(bar)
        } else if editsReport {
            if split { SchoolReportSaveBar(model: model) } else { editReportBar }
        }
    }

    /// « Rédiger », « Modifier » ou « Reprendre le bilan » : l’action domine tant que rien n’est enregistré.
    private var editReportBar: some View {
        let empty = model.reportIsEmpty, unsaved = model.draftChanged
        let title = SchoolReportFlowRules.editTitle(isEmpty: empty, unsaved: unsaved)
        return DrivyStickyActionBar {
            if empty || unsaved {
                Button(title) { openReport() }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("lesson-report-edit")
            } else {
                Button(title) { openReport() }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .accessibilityIdentifier("lesson-report-edit")
            }
        }
    }

    /// Les étapes sont figées à l’entrée, d’après ce que la leçon contient à cet instant.
    private func openReport() {
        guard editsReport, !showsReport else { return }
        reportSteps = model.reportSteps
        showsReport = true
    }

    /// Colonne de contexte en fenêtre large : la leçon, ses objectifs, son trajet et ses observations.
    @ViewBuilder private var lessonContext: some View {
        headerSection
        lessonNotices
        plannedGoals
        lessonEvidence(mapHeight: SchoolReportLayout.evidenceMapHeight)
    }

    /// Après la leçon (terminée, annulée, manquée), les objectifs prévus se relisent sans se modifier : l’école
    /// ferme la préparation dès que la leçon a un résultat. Le moniteur de la leçon et l’élève les reçoivent ;
    /// la note que le moniteur garde pour lui n’est rendue qu’à lui par l’école, et relue ici par lui seul.
    @ViewBuilder private var plannedGoals: some View {
        if let lesson = model.lesson, lesson.status != "PLANNED" {
            let goals = model.preparation?.goals ?? []
            let note = model.isAuthor
                ? (model.preparation?.administrativeCheckNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if !goals.isEmpty || !note.isEmpty { goalsReader(goals, note: note) }
        }
    }

    private var lessonNotices: some View { SchoolReportNotices(model: model) }

    @ViewBuilder private func lessonEvidence(mapHeight: CGFloat) -> some View {
        if isCompleted, readsLesson, !model.captures.isEmpty || !model.track.isEmpty {
            SchoolReportTripSection(model: model, router: router, context: reportContext, mapHeight: mapHeight)
        }
        if isCompleted, model.isAuthor || model.isOwnLearner {
            SchoolReportObservationsSection(model: model, router: router, context: reportContext)
        }
    }

    /// Le moniteur relit son bilan sur la fiche et le rédige en étapes ; en fenêtre large, il le rédige ici.
    /// Les autres lecteurs reçoivent le bilan partagé.
    @ViewBuilder private func completedReport(editing: Bool) -> some View {
        if editsReport {
            if editing {
                SchoolReportTextSection(model: model)
                SchoolReportCompetenciesSection(model: model)
            } else {
                SchoolReportReadSection(model: model)
            }
        }
        if !model.isAuthor, model.canReadSharedReport, isCompleted { sharedReportSection }
    }

    private func isGoalsBar(_ bar: PlannedBar?) -> Bool {
        if case .goals = bar { return true }
        return false
    }

    /// Le souhait de l’élève vaut pour la formation : il se lit (moniteur) ou se modifie (élève) avant une leçon,
    /// pas sur chaque leçon passée.
    private func showsWish(_ wish: SchoolLearnerWish) -> Bool {
        guard isPlanned else { return false }
        if model.isOwnLearner { return isNextPlanned ?? true }
        return !wish.text.isEmpty
    }

    private func openCompletionIfAsked() {
        guard opensCompletion, !completionOpened, !model.isLoading, model.lesson != nil else { return }
        completionOpened = true
        guard isPlanned, model.isAuthor, model.canMutate else { return }
        if completionConfirmed { beginCompletion() }
        else { confirmsCompletion = true }
    }

    /// Le formulaire planifié ne s’affiche pas entre le chargement de la leçon et son constat.
    /// Une panne ou une demande conservée libère la place pour les contrôles de reprise existants.
    private var awaitsConfirmedCompletion: Bool {
        opensCompletion && completionConfirmed && !completionOpened
            && (model.isLoading || (isPlanned && model.isAuthor && model.canMutate))
    }

    private func beginCompletion() {
        guard !completionQueued, !isFinishing, model.acceptsInput, isPlanned, model.isAuthor else { return }
        completionQueued = true
        Task {
            // Relecture en cours : le constat confirmé attend sa fin au lieu d’être ignoré.
            await model.settled()
            _ = await finishLesson("")
            completionQueued = false
        }
    }

    /// L’arrêt est écrit sur l’appareil avant le constat. Le transfert du trajet continue sans retenir le bilan.
    private func finishLesson(_ reason: String) async -> Bool {
        guard !isFinishing, model.canMutate, isPlanned, model.isAuthor else { return false }
        isFinishing = true; finishError = nil
        defer { isFinishing = false }
        if let capture, !(await capture.finishForLesson(lessonID: model.lessonID)) {
            finishError = capture.errorMessage ?? "Le trajet n’a pas pu être enregistré. Réessaie pour terminer la leçon."
            return false
        }
        if model.completionNeedsReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lessonSheet = .permit
            return false
        }
        await model.refreshCaptures()
        var times = model.completionTimes()
        if let local = capture?.lessonTimes(lessonID: model.lessonID),
           let start = SchoolLesson.date(local.startedAt), let end = SchoolLesson.date(local.stoppedAt), end > start {
            times = (start, end)
        }
        let completed = await model.complete(start: times.start, end: times.end, reason: reason, localCaptureStopped: true)
        // La leçon est terminée : la rédaction du bilan s’ouvre d’elle-même dès que la fiche revient à l’écran.
        if completed { opensReportWhenReady = true }
        return completed
    }

    /// Départ réussi depuis cette feuille : elle se ferme pour laisser le trajet en cours à l’écran.
    private func captureSheetClosed() {
        guard captureStatus == .collecting else { return }
        if model.hasLocalEdits { showsLive = true } else { model.invalidate(); dismiss() }
    }

    // MARK: En-tête

    /// L’élève (pour l’élève qui lit sa leçon : son moniteur), puis les faits de la leçon. Un enregistrement en cours se lit dans le bouton qui l’a lancé,
    /// pas dans une ligne d’en-tête qui décale toute la fiche puis disparaît.
    private var headerSection: some View {
        let identity = SchoolLessonHubRules.headerIdentity(learnerName: learnerName,
            instructorName: model.lesson?.providedInstructorName, isOwnLearner: model.isOwnLearner, roles: model.membership.roles)
        return Section {
            if identity != nil || model.lesson != nil {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    if let identity { DrivyLearnerIdentity(name: identity.name, detail: identity.role, variant: .compact) }
                    if let lesson = model.lesson { lessonFacts(lesson) }
                }
            }
            if model.isLoading && model.lesson == nil {
                DrivySkeletonRows(count: 4)
                    .drivySkeleton("Chargement de la leçon…")
            }
            if let error = model.errorMessage {
                SchoolErrorNotice(message: error, retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
            }
            if let finishError { DrivyInlineMessage(text: finishError, tone: .danger) }
            if let message = model.confirmation { DrivyInlineMessage(text: message) }
            if let message = model.information { DrivyInlineMessage(text: message, tone: .neutral) }
        }
        .listRowBackground(Color.clear)
        // En-tête posé sur le canevas : aucun filet entre l’élève, les faits de la leçon et les messages.
        .listRowSeparator(.hidden)
    }

    /// Faits de la leçon sous l’élève : son état s’il est inhabituel, quand, où, avec qui, à quel prix.
    /// Du texte seul, sans symbole, pastille ni colonne de montants.
    private func lessonFacts(_ lesson: SchoolLesson) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            // L’inhabituel (à terminer, annulée, absence) se lit en premier, du même mot que dans les listes :
            // du texte dans la hiérarchie, sans pastille. Planifiée, en cours ou terminée : rien, l’écran le dit déjà.
            if let note = lesson.drivyState.rowNote {
                DrivyRowNoteText(note: note)
                    .accessibilityIdentifier("lesson-state")
            }
            scheduleLines(lesson)
                .accessibilityElement(children: .combine)
            if let actual = SchoolLessonHubRules.actualSchedule(lesson) {
                factLine(actual, color: DrivyTheme.muted)
            }
            if let instructor = SchoolLessonHubRules.instructorLine(instructorName: lesson.providedInstructorName,
                isAuthor: model.isAuthor, isOwnLearner: model.isOwnLearner, roles: model.membership.roles) {
                factLine(instructor, color: DrivyTheme.muted)
            }
            ForEach(SchoolLessonHubRules.priceLines(lesson: lesson, account: model.account)) { line in
                priceLine(line)
            }
        }
    }

    /// Date, horaire et lieu. La date et l’horaire tiennent sur une ligne quand la colonne le permet, sinon l’un
    /// sous l’autre : l’intervalle horaire ne se coupe jamais entre ses deux heures. Le lieu passe à la ligne seul.
    private func scheduleLines(_ lesson: SchoolLesson) -> some View {
        let schedule = SchoolLessonHubRules.schedule(lesson)?.replacingOccurrences(of: " – ", with: "\u{00A0}–\u{00A0}")
        let parts = schedule?.components(separatedBy: " · ") ?? []
        return VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            if let schedule {
                ViewThatFits(in: .horizontal) {
                    factLine(schedule, color: DrivyTheme.text).fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        ForEach(parts, id: \.self) { part in factLine(part, color: DrivyTheme.text) }
                    }
                }
            }
            if !lesson.meetingPoint.isEmpty { factLine(lesson.meetingPoint, color: DrivyTheme.muted) }
        }
    }

    /// Une ligne de l’en-tête : l’horaire en encre pleine, le lieu et le prix en retrait.
    private func factLine(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Le prix se lit à la suite de la date et du lieu, sous son intitulé ; il n’ouvre rien et ne promet aucun suivi.
    private func priceLine(_ line: SchoolLessonPriceLine) -> some View {
        let amount = SchoolCatalogFormatting.price(line.cents)
        return factLine("\(line.title)\u{00A0}: \(amount)", color: DrivyTheme.muted)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.title)
            .accessibilityValue(amount)
            .accessibilityIdentifier(line.kind == .agreed ? "lesson-tariff" : "lesson-balance")
    }

    // MARK: Actions de la leçon

    @ViewBuilder private func lessonMenu(now: Date) -> some View {
        if let lesson = model.lesson {
            let moves = SchoolLessonHubRules.mayMove(lesson, roles: model.membership.roles, now: now)
            let cancels = SchoolLessonHubRules.mayCancel(lesson, roles: model.membership.roles)
            let absent = model.mayMarkNoShow(now: now)
            if moves || cancels || absent {
                // Menus en texte seul : ces actions sont propres à Drivy, un symbole n’y serait qu’un ornement.
                Menu {
                    if absent {
                        Button("Élève absent") { confirmsNoShow = true }
                            .disabled(!model.canMutate || isFinishing)
                    }
                    if moves {
                        Button("Déplacer") { openPlanning(lesson, cancelling: false) }
                            .disabled(!model.canMutate || isFinishing)
                    }
                    if cancels {
                        Button("Annuler la leçon", role: .destructive) { openPlanning(lesson, cancelling: true) }
                            .disabled(!model.canMutate || isFinishing)
                    }
                } label: {
                    // Même symbole « plus » que sur les rangées d’observation et le trajet en cours.
                    Label("Plus d’actions", systemImage: "ellipsis")
                }
                .accessibilityIdentifier("lesson-more-actions")
            }
        }
    }

    /// Leçon planifiée du moniteur : démarrer le trajet (ou y revenir), terminer dès 15 minutes avant le début
    /// (LESSON_NOT_STARTED côté serveur) ; plus tôt, enregistrer les objectifs.
    private func plannedBar(now: Date) -> PlannedBar? {
        guard model.isAuthor, isPlanned, let lesson = model.lesson else { return nil }
        let finishable = SchoolLessonHubRules.mayFinish(lesson, now: now)
        if captureStatus == .collecting { return .live(finishable: finishable) }
        if mayStartCapture(now: now) { return .start(finishable: finishable) }
        if finishable { return .finish }
        return .goals(startsAt: captureOpensLater(now: now))
    }

    /// Boutons en texte seul. Seule la flèche de localisation reste, celle du système : elle signale que le geste
    /// utilise le GPS, comme sur Aujourd’hui et la préparation du trajet.
    @ViewBuilder private func plannedBarView(_ bar: PlannedBar) -> some View {
        DrivyStickyActionBar {
            switch bar {
            case .live(let finishable):
                Button { showsLive = true } label: { Label("Trajet en cours", systemImage: "location.fill") }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityHint("Ouvre le trajet")
                    .accessibilityIdentifier("lesson-live-capture")
                if finishable { completeButton(primary: false) }
            case .start(let finishable):
                Button { openCapturePreparation() } label: { Label("Démarrer le trajet", systemImage: "location.fill") }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("lesson-prepare-gps")
                if finishable { completeButton(primary: false) }
            case .finish:
                completeButton(primary: true)
            case .goals(let startsAt):
                if let startsAt { DrivyActionNote(text: "Trajet dès \(startsAt)") }
                Button { Task { await model.savePreparation() } } label: {
                    DrivyBusyLabel(title: "Enregistrer les objectifs", isBusy: isSending(.savePreparation))
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.acceptsInput || !model.preparationValid || !model.preparationChanged)
                .accessibilityIdentifier("lesson-save-goals")
            }
        }
    }

    /// L’envoi en cours est celui de ce bouton : l’attente se lit là où le geste a été fait.
    private func isSending(_ kind: SchoolCommandKind) -> Bool {
        model.isBusy && model.pending?.kind == kind
    }

    @ViewBuilder private func completeButton(primary: Bool) -> some View {
        if primary {
            Button { confirmsCompletion = true } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if isFinishing { ProgressView().accessibilityHidden(true) }
                    Text("Terminer la leçon")
                }
            }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.acceptsInput || isFinishing)
                .accessibilityIdentifier("lesson-complete")
        } else {
            // Action alternative sous « Démarrer le trajet » ou « Trajet en cours » : même composant que partout.
            Button { confirmsCompletion = true } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if isFinishing { ProgressView().accessibilityHidden(true) }
                    Text("Terminer la leçon")
                }
            }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!model.acceptsInput || isFinishing)
            .accessibilityIdentifier("lesson-complete")
        }
    }

    private func mayStartCapture(now: Date) -> Bool {
        guard let lesson = model.lesson, let capture else { return false }
        return SchoolLessonHubRules.mayStartCapture(lesson: lesson, isAuthor: model.isAuthor, school: schoolWorkspace.school,
            capture: captureStatus, controllerCanPrepare: capture.canPrepareCapture, now: now)
    }
    /// « Trajet dès 13:30 » : le départ sera possible plus tard aujourd’hui.
    private func captureOpensLater(now: Date) -> String? {
        guard let lesson = model.lesson, let capture,
              let opening = SchoolLessonHubRules.captureOpening(lesson: lesson, isAuthor: model.isAuthor, school: schoolWorkspace.school,
                capture: captureStatus, controllerCanPrepare: capture.canPrepareCapture, now: now) else { return nil }
        return SchoolLessonHubRules.openingLabel(opening, zone: lesson.timeZone, now: now)
    }

    private func openCapturePreparation() {
        guard let capture, mayStartCapture(now: Date()) else { return }
        capturePreparation = agenda.capturePreparation(scope: model.scope, lessonID: model.lessonID, controller: capture)
    }

    private func openPlanning(_ lesson: SchoolLesson, cancelling: Bool) {
        let planning = SchoolPlanningWorkspace(scope: model.scope, client: agenda.planningClient, lesson: lesson)
        planningRoute = PlanningRoute(model: planning, cancelling: cancelling)
    }

    // MARK: Bilan partagé

    @ViewBuilder private var sharedReportSection: some View {
        if let revision = model.revisions.first {
            Section {
                DrivyReportBody(nextStep: revision.nextStep, workedOn: revision.workedOn, observationText: revision.observationText, compact: true)
                ForEach(revision.observations) { observation in
                    DrivyCompetencyNote(label: model.competencies.first(where: { $0.id == observation.id })?.displayLabel ?? "Compétence",
                        level: observation.levelLabel, context: observation.context)
                }
            } header: { Text("Bilan").drivyFormSectionHeader() }
                .drivyFormRows()
        } else if model.sharedReportWasRead {
            Section {
                Text(SchoolLessonHubRules.missingReportText(isOwnLearner: model.isOwnLearner)).foregroundStyle(DrivyTheme.muted)
            } header: { Text("Bilan").drivyFormSectionHeader() }
                .drivyFormRows()
        }
    }

    // MARK: Avant la leçon

    private func goalsEditor(savesInline: Bool) -> some View {
        Section {
            // Identifiants stables : retirer un objectif ne relit jamais un index disparu.
            ForEach($model.goals) { $goal in
                let number = (model.goals.firstIndex { $0.id == goal.id } ?? 0) + 1
                HStack {
                    TextField("Objectif \(number)", text: $goal.label, axis: .vertical)
                    Button(role: .destructive) { model.goals.removeAll { $0.id == goal.id } } label: {
                        Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Retirer l’objectif \(number)")
                }
                .disabled(!model.acceptsInput)
            }
            if model.goals.count < 3 {
                Button("Ajouter un objectif") {
                    model.goals.append(SchoolLessonGoal(label: ""))
                }
                .disabled(!model.acceptsInput)
            }
            // Jamais montrée à l’élève. Le cadenas reste : une fois la note écrite, l’invite « Note pour moi »
            // disparaît et lui seul distingue cette ligne des objectifs, que l’élève lit.
            HStack(alignment: .center, spacing: DrivySpacing.s) {
                DrivyPrivacyMark(isPrivate: true).accessibilityHidden(true)
                    .frame(width: DrivySpacing.l)
                TextField("Note pour moi", text: $model.administrativeNote, axis: .vertical).lineLimit(1...4).disabled(!model.acceptsInput)
            }
            // Le bouton n’apparaît qu’avec une modification : désactivé, il n’était qu’un texte fantôme.
            if savesInline && model.preparationChanged {
                Button { Task { await model.savePreparation() } } label: {
                    DrivyBusyLabel(title: "Enregistrer les objectifs", isBusy: isSending(.savePreparation))
                }
                .disabled(!model.acceptsInput || !model.preparationValid || !model.preparationChanged)
            }
        } header: { Text("Objectifs").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    private func goalsReader(_ goals: [SchoolLessonGoal], note: String = "") -> some View {
        Section {
            ForEach(goals) { goal in Text(goal.label) }
            if !note.isEmpty {
                // Même cadenas que dans la préparation : cette ligne reste au moniteur, l’élève ne la reçoit pas.
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    DrivyPrivacyMark(isPrivate: true)
                    Text(note).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("lesson-private-note")
            }
        } header: { Text("Objectifs").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    private func wishSection(_ wish: SchoolLearnerWish) -> some View {
        Section {
            if model.isOwnLearner {
                TextField("Ce que j’aimerais travailler", text: $model.wishText, axis: .vertical).lineLimit(2...6).disabled(!model.acceptsInput)
                Button { Task { await model.saveWish() } } label: {
                    DrivyBusyLabel(title: "Enregistrer le souhait", isBusy: isSending(.saveWish))
                }
                .disabled(!model.acceptsInput || model.wishText.unicodeScalars.count > 500 || model.wishText == wish.text)
            } else {
                Text(wish.text)
            }
        } header: { Text(model.isOwnLearner ? "Mon souhait" : "Souhait de l’élève").drivyFormSectionHeader() }
            .drivyFormRows()
    }
}
