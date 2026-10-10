import SwiftUI

/// L’écran unique d’une leçon : avant (objectifs, départ du trajet), pendant (trajet en cours, observations),
/// après (objectifs prévus, bilan, trajet, observations). Une leçon annulée ou manquée garde ses objectifs prévus. Tout est partagé avec l’élève automatiquement ; le moniteur garde
/// pour lui ce qu’il choisit.
/// Une leçon qui n’est plus à venir s’ouvre toujours sur son récapitulatif (`SchoolLessonSummaryView`), à toute largeur.
/// La rédaction du bilan ne s’ouvre que sur un geste (« Rédiger », « Modifier », « Reprendre le bilan ») ou juste après
/// « Terminer la leçon » : en étapes poussées (`SchoolReportStepView`), ou sur place en deux colonnes en fenêtre large.
struct SchoolLessonReportView: View {
    let client: SchoolLessonReportClient
    @Bindable var schoolWorkspace: SchoolWorkspace
    let lessonID: UUID
    let learnerName: String
    /// Propose la fin dès que la leçon est lue (« À terminer » d’Aujourd’hui, fin du trajet).
    var opensCompletion = false
    /// Geste explicite « Commencer la leçon » depuis Aujourd’hui.
    var opensStart = false
    /// Seule la carte transmet ce consentement après sa confirmation explicite.
    var completionConfirmed = false
    /// Élève : le souhait se modifie sur la prochaine leçon seulement ; `nil` quand l’appelant ne le sait pas.
    var isNextPlanned: Bool? = nil
    /// « Commencer la leçon » direct depuis Aujourd’hui qui n’a pas abouti : sa raison, au-dessus de la fiche.
    var startIssue: String? = nil
    var outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()
    @State private var model: SchoolLessonReportWorkspace?
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmsDiscard = false
    @State private var isCompletingLesson = false
    @State private var startIssueDismissed = false
    /// Bilan enregistré : le trajet terminé se referme une fois la feuille descendue, pas pendant sa descente.
    @State private var closesLessonFlowOnDisappear = false
    /// La racine de la fiche est à l’écran (une étape du bilan poussée la cache).
    @State private var isOnScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    opensCompletion: opensCompletion, opensStart: opensStart, completionConfirmed: completionConfirmed, isNextPlanned: isNextPlanned,
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if let startIssue, !startIssueDismissed {
                SchoolTripIssueBanner(text: startIssue) {
                    withAnimation(DrivyMotion.reveal(reduceMotion)) { startIssueDismissed = true }
                }
                .transition(.opacity)
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
                        model?.persistLocalDraft(); model?.close(); dismiss()
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
            // Racine visible : le trajet se ferme après la descente de la feuille. Bilan enregistré depuis une étape
            // poussée : la racine a déjà disparu, le trajet se ferme tout de suite, sous la feuille.
            if isOnScreen { closesLessonFlowOnDisappear = true } else { capture?.closeLessonFlow(lessonID: lessonID) }
            model?.close()
            dismiss()
        }
        .alert("Quitter sans enregistrer ?", isPresented: $confirmsDiscard) {
            Button("Quitter sans enregistrer", role: .destructive) { model?.discardLocalDraft(); model?.close(); dismiss() }
            Button("Continuer", role: .cancel) { }
        }
        .onAppear { isOnScreen = true }
        .onDisappear {
            isOnScreen = false
            if closesLessonFlowOnDisappear { capture?.closeLessonFlow(lessonID: lessonID) }
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

/// Colonnes de la rédaction en fenêtre large : contexte à gauche, bilan à droite.
private enum LessonLayout {
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
    let opensStart: Bool
    let completionConfirmed: Bool
    let isNextPlanned: Bool?
    /// Contrôleur de séance de l’app ; absent, rien de ce qui dépend du GPS de l’appareil n’est proposé.
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lessonSheet: LessonSheet?
    @State private var router = SchoolReportRouter()
    /// Origine de la rédaction en cours ; `nil` : la fiche se lit. Seul `openReport` lui donne une valeur.
    @State private var reportEntry: SchoolReportEntry?
    /// Étapes de la rédaction poussées dans la pile (largeur compacte).
    @State private var showsReport = false
    @State private var reportSteps: [SchoolReportStep] = []
    /// Largeur de la fiche, relevée à l’affichage : elle choisit la forme de la rédaction, jamais son ouverture.
    @State private var isWide = false
    /// La leçon vient d’être terminée ici : la rédaction s’ouvre dès que la fiche est de nouveau à l’écran.
    @State private var opensReportWhenReady = false
    @Binding var isFinishing: Bool
    @State private var finishError: String?
    /// Départs et fins de leçon que l’école vient de confirmer depuis cette fiche : un retour haptique chacun.
    @State private var confirmedSteps = 0
    @State private var completionOpened = false
    /// Leçon terminée depuis la feuille du permis : la rédaction attend que cette feuille soit descendue.
    @State private var opensReportAfterPermit = false
    @State private var startOpened = false
    @State private var confirmsCompletion = false
    @State private var completionQueued = false
    @State private var showReloadConfirmation = false
    @State private var confirmsNoShow = false
    @State private var showsLive = false
    @State private var capturePreparation: SchoolCapturePreparationWorkspace?
    /// L’accord GPS de l’élève se lit avant tout rideau : l’attente se lit dans le bouton « Démarrer le trajet ».
    @State private var isOpeningTrip = false
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
        case begin
        case live
        case start
        case finish
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
        // Seulement après la confirmation durable de l’école, jamais à l’appui.
        .sensoryFeedback(.success, trigger: confirmedSteps)
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
        .sheet(item: $lessonSheet, onDismiss: {
            if opensReportAfterPermit { opensReportAfterPermit = false; opensReportWhenReady = true }
        }) { sheet in
            switch sheet {
            case .permit: SchoolLessonCompletionSheet(model: model, finish: finishLesson, finishError: finishError)
            }
        }
        .modifier(SchoolReportPresentations(router: router, model: model, context: reportContext))
        .modifier(SchoolReportLocalDraftKeeper(model: model))
        .fullScreenCover(item: $capturePreparation, onDismiss: { captureSheetClosed() }) { preparation in
            SchoolCapturePreparationView(model: preparation, schoolWorkspace: schoolWorkspace)
        }
        .sheet(item: $planningRoute, onDismiss: { Task { await model.load() } }) { route in planningSheet(route) }
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
        // Retour sur la fiche : la saisie reste dans le modèle et se garde aussi sur l’appareil. En largeur compacte,
        // quitter les étapes quitte la rédaction ; en fenêtre large, elle continue sur place.
        .onChange(of: showsReport) { _, shown in
            guard !shown else { return }
            model.persistLocalDraft()
            if !isWide { reportEntry = nil }
        }
        // La fenêtre change de largeur pendant la rédaction : la saisie vit dans le modèle, seule sa forme change.
        .onChange(of: isWide) { _, wide in
            guard reportEntry != nil else { return }
            showsReport = !wide && !reportSteps.isEmpty
        }
        .onChange(of: captureStatus) { _, status in if status != .collecting && status != .stopped { showsLive = false } }
        .onChange(of: showsLive) { _, visible in
            if !visible { Task { await model.refreshObservations() } }
        }
        .onChange(of: model.lesson?.status) { _, _ in openCompletionIfAsked() }
        .onChange(of: model.isLoading) { _, loading in if !loading { openCompletionIfAsked(); openStartIfAsked() } }
        .onChange(of: capture?.finalizedSyncState) { _, state in
            if isCompleted && !isFinishing && (state == .synced || state == .partial) { Task { await model.load() } }
        }
        .onAppear { openCompletionIfAsked(); openStartIfAsked() }
        .interactiveDismissDisabled(isFinishing || completionQueued || awaitsConfirmedCompletion)
    }

    private func form(now: Date) -> some View {
        let bar = plannedBar(now: now)
        return GeometryReader { geometry in
            // La fiche se lit, quelle que soit sa largeur. Une fois la rédaction demandée, la largeur en choisit la
            // forme : étapes poussées (iPhone, Slide Over, grand texte) ou deux colonnes sur place. La saisie vit dans
            // le modèle, au-dessus de ce changement de composition et des rotations de la fenêtre.
            let wide = SchoolReportFlowRules.isWide(width: geometry.size.width, accessibilitySize: typeSize.isAccessibilitySize)
            let presentation = SchoolReportFlowRules.presentation(entry: reportEntry, canEdit: editsReport, isWide: wide)
            layout(presentation: presentation, wide: wide, bar: bar)
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(bar, presentation: presentation) }
                .onChange(of: wide, initial: true) { _, value in isWide = value }
                .onChange(of: opensReportWhenReady, initial: true) { _, wanted in
                    guard wanted else { return }
                    opensReportWhenReady = false
                    openReport(.lessonCompleted, wide: wide)
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
                .disabled(model.isInvalidated)
            }
            ToolbarItem(placement: .topBarTrailing) { lessonMenu(now: now) }
        }
    }

    /// Trois compositions : la rédaction sur place (fenêtre large, sur demande), le formulaire d’une leçon à venir,
    /// et le récapitulatif de toute leçon qui a eu lieu ou n’aura pas lieu. Pendant la rédaction en étapes, le
    /// récapitulatif reste sous la pile.
    @ViewBuilder private func layout(presentation: SchoolReportPresentation, wide: Bool, bar: PlannedBar?) -> some View {
        if presentation == .sideBySide {
            HStack(spacing: 0) {
                Form { lessonContext }
                    .scrollContentBackground(.hidden)
                    .frame(width: LessonLayout.contextColumnWidth)
                Form {
                    SchoolReportTextSection(model: model)
                    SchoolReportCompetenciesSection(model: model)
                }
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    // Le bilan démarre à la hauteur du nom de l’élève, pas au bord de la barre.
                    .contentMargins(.top, DrivySpacing.m, for: .scrollContent)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: LessonLayout.splitMaxWidth)
            .frame(maxWidth: .infinity)
        } else if isPlanned || model.lesson == nil {
            Form {
                headerSection
                lessonNotices
                // Leçon restée à terminer : son trajet déjà reçu par l’école se revoit d’ici, sans réglage.
                if showsPlannedTrip {
                    SchoolReportTripSection(model: model, router: router, context: reportContext, editable: false)
                }
                // Avant la leçon : le souhait de l’élève éclaire les objectifs, puis viennent les observations.
                plannedSections(bar: bar)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: LessonLayout.formMaxWidth)
            .frame(maxWidth: .infinity)
        } else {
            SchoolLessonSummaryView(model: model, router: router, context: reportContext, learnerName: learnerName,
                finishError: finishError, isWide: wide)
        }
    }

    private var showsPlannedTrip: Bool {
        isPlanned && SchoolReportFlowRules.showsTrip(readsLesson: readsLesson, hasTrack: !model.track.isEmpty,
            replayableCount: model.replayableCaptures.count, noteCount: 0, isPlanned: true)
    }

    @ViewBuilder private func plannedSections(bar: PlannedBar?) -> some View {
        Group {
            if let wish = model.wish, showsWish(wish) { wishSection(wish) }
            if isPlanned, model.isAuthor { goalsEditor() }
            if isPlanned, model.isOwnLearner, let goals = model.preparation?.goals, !goals.isEmpty { goalsReader(goals) }
        }
        .drivyFormRows()
        if isPlanned, model.isAuthor { SchoolReportObservationsSection(model: model, router: router, context: reportContext) }
    }

    /// Barre basse : les gestes d’une leçon planifiée ; pour une leçon terminée, l’enregistrement du bilan quand
    /// il se rédige sur place, sinon l’entrée dans sa rédaction quand elle a sa place en bas.
    @ViewBuilder private func bottomBar(_ bar: PlannedBar?, presentation: SchoolReportPresentation) -> some View {
        if let bar {
            plannedBarView(bar)
        } else if editsReport {
            if presentation == .sideBySide { SchoolReportSaveBar(model: model) } else { reportEntryBar }
        }
    }

    /// Le geste proposé sur la fiche lue, d’après l’état du bilan.
    private var offeredEntry: SchoolReportEntry {
        SchoolReportFlowRules.entry(isEmpty: model.reportIsEmpty, unsaved: model.draftChanged)
    }
    private var entryTitle: String {
        SchoolReportFlowRules.editTitle(isEmpty: model.reportIsEmpty, unsaved: model.draftChanged)
    }

    /// « Reprendre le bilan » domine (une saisie attend) ; « Rédiger le bilan » se propose sans dominer.
    /// « Modifier le bilan » n’est pas ici : il vit dans le menu de la barre d’outils.
    @ViewBuilder private var reportEntryBar: some View {
        let entry = offeredEntry
        if case .bottomBar(let primary) = SchoolReportFlowRules.placement(of: entry) {
            DrivyStickyActionBar {
                if primary {
                    Button(entryTitle) { openReport(entry) }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("lesson-report-edit")
                } else {
                    Button(entryTitle) { openReport(entry) }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .accessibilityIdentifier("lesson-report-edit")
                }
            }
        }
    }

    /// Seule entrée dans la rédaction. Ses origines sont celles de `SchoolReportEntry` : la fin de la leçon depuis
    /// cette fiche, ou l’un des trois gestes. Les étapes sont figées à l’entrée, d’après ce que la leçon contient.
    private func openReport(_ origin: SchoolReportEntry, wide: Bool? = nil) {
        guard editsReport, reportEntry == nil else { return }
        reportSteps = model.reportSteps
        reportEntry = origin
        if !(wide ?? isWide) { showsReport = true }
    }

    /// Fenêtre large : quitter la rédaction sur place sans rien perdre. La saisie reste dans le modèle et sur
    /// l’appareil ; la fiche relue propose alors « Reprendre le bilan ».
    private func leaveReport() {
        model.persistLocalDraft()
        showsReport = false
        reportEntry = nil
    }

    /// Colonne de contexte de la rédaction en fenêtre large : la leçon, ses objectifs, son trajet et ses observations.
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
        guard isPlanned, model.lesson?.hasStarted == true, model.isAuthor, model.canMutate else { return }
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
        guard !completionQueued, !isFinishing, model.acceptsInput, isPlanned, model.lesson?.hasStarted == true, model.isAuthor else { return }
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
        guard !isFinishing, model.canMutate, isPlanned, model.lesson?.hasStarted == true, model.isAuthor else { return false }
        if model.completionNeedsReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // La question du permis vient tout de suite, sans attente devant elle. Le trajet s’arrête pendant ce
            // temps (même tâche d’arrêt durable, que la fin reprendra) : rien n’est enregistré après « Terminer ».
            if let capture {
                let lessonID = model.lessonID
                Task { _ = await capture.finishForLesson(lessonID: lessonID) }
            }
            lessonSheet = .permit
            return false
        }
        isFinishing = true; finishError = nil
        defer { isFinishing = false }
        if let capture, !(await capture.finishForLesson(lessonID: model.lessonID)) {
            finishError = capture.errorMessage ?? "Le trajet n’a pas pu être enregistré. Réessaie pour terminer la leçon."
            return false
        }
        // Leçon démarrée : ses heures sont celles de son départ et de maintenant, sans relire les trajets.
        let times = model.completionTimes()
        let completed = await model.complete(start: times.start, end: times.end, reason: reason, localCaptureStopped: true)
        // La leçon est terminée : la rédaction du bilan s’ouvre d’elle-même dès que la fiche revient à l’écran.
        if completed {
            capture?.noteLessonCompleted(model.lessonID)
            if lessonSheet != nil { opensReportAfterPermit = true } else { opensReportWhenReady = true }
            confirmedSteps += 1
        } else if model.errorMessage == nil, model.pending == nil, !model.isInvalidated {
            // Le constat n’est pas parti et le modèle n’en dit rien (objectif laissé vide, horloge de l’appareil en
            // retard sur celle de l’école) : le geste ne reste jamais sans réponse.
            finishError = model.preparationChanged && !model.preparationValid
                ? "Complète ou retire les objectifs vides avant de terminer la leçon."
                : "La leçon n’a pas pu être terminée. Actualise-la, puis réessaie."
        }
        return completed
    }

    /// Départ réussi depuis cette feuille : elle se ferme pour laisser le trajet en cours à l’écran.
    private func captureSheetClosed() {
        guard captureStatus == .collecting else { Task { await model.load() }; return }
        if model.hasLocalEdits { showsLive = true } else { model.close(); dismiss() }
    }

    // MARK: En-tête

    /// L’en-tête commun (`SchoolLessonHeaderView`), posé sur le canevas du formulaire : aucun filet entre l’élève,
    /// les faits de la leçon et les messages.
    private var headerSection: some View {
        Section {
            SchoolLessonHeaderView(model: model, learnerName: learnerName, finishError: finishError)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Actions de la leçon

    /// « Modifier le bilan » vit ici quand le bilan est enregistré : la fiche lue ne porte alors aucune barre.
    private var offersEditInMenu: Bool {
        editsReport && reportEntry == nil && SchoolReportFlowRules.placement(of: offeredEntry) == .menu
    }
    /// Rédaction sur place, en fenêtre large : le menu permet de revenir à la lecture.
    private var offersLeaveInMenu: Bool { editsReport && reportEntry != nil && isWide }

    @ViewBuilder private func lessonMenu(now: Date) -> some View {
        if let lesson = model.lesson {
            let moves = SchoolLessonHubRules.mayMove(lesson, roles: model.membership.roles, membershipID: model.membership.membershipId, now: now)
            let cancels = SchoolLessonHubRules.mayCancel(lesson, roles: model.membership.roles, membershipID: model.membership.membershipId)
            let absent = model.mayMarkNoShow(now: now)
            let edits = offersEditInMenu, leaves = offersLeaveInMenu
            if moves || cancels || absent || edits || leaves {
                // Menus en texte seul : ces actions sont propres à Drivy, un symbole n’y serait qu’un ornement.
                Menu {
                    if edits {
                        Button(entryTitle) { openReport(offeredEntry) }
                            .accessibilityIdentifier("lesson-report-edit")
                    }
                    if leaves {
                        Button("Quitter la rédaction") { leaveReport() }
                            .disabled(model.holdsScreen)
                            .accessibilityIdentifier("lesson-report-leave")
                    }
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

    /// Leçon du moniteur : commencer explicitement, puis gérer le trajet facultatif ou terminer.
    private func plannedBar(now: Date) -> PlannedBar? {
        guard model.isAuthor, isPlanned, let lesson = model.lesson else { return nil }
        if !lesson.hasStarted { return .begin }
        if captureStatus == .collecting { return .live }
        if mayStartCapture(now: now) { return .start }
        return .finish
    }

    /// Boutons en texte seul. Seule la flèche de localisation reste, celle du système : elle signale que le geste
    /// utilise le GPS, comme sur Aujourd’hui et la préparation du trajet.
    @ViewBuilder private func plannedBarView(_ bar: PlannedBar) -> some View {
        DrivyStickyActionBar {
            switch bar {
            case .begin:
                Button { Task { await startLesson() } } label: {
                    DrivyBusyLabel(title: "Commencer la leçon", isBusy: isSending(.startLesson) || isSending(.savePreparation))
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.acceptsInput)
                .accessibilityIdentifier("lesson-start")
            case .live:
                Button { showsLive = true } label: { Label("Trajet en cours", systemImage: "location.fill") }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityHint("Ouvre le trajet")
                    .accessibilityIdentifier("lesson-live-capture")
                completeButton(primary: false)
            case .start:
                Button { Task { await openCapturePreparation() } } label: {
                    if isOpeningTrip {
                        DrivyBusyLabel(title: "Démarrer le trajet", busyTitle: "Vérification de l’accord GPS…", isBusy: true)
                    } else {
                        Label("Démarrer le trajet", systemImage: "location.fill")
                    }
                }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!model.acceptsInput)
                    .accessibilityIdentifier("lesson-prepare-gps")
                completeButton(primary: false)
            case .finish:
                completeButton(primary: true)
            }
        }
    }

    /// L’envoi en cours est celui de ce bouton : l’attente se lit là où le geste a été fait.
    private func isSending(_ kind: SchoolCommandKind) -> Bool {
        model.isBusy && model.pending?.kind == kind
    }

    private func openStartIfAsked() {
        guard opensStart, !startOpened, !model.isLoading, model.lesson != nil else { return }
        startOpened = true
        Task { await startLesson() }
    }

    private func startLesson() async {
        guard await model.start() else { return }
        confirmedSteps += 1
        if mayStartCapture(now: Date()) { await openCapturePreparation() }
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
    /// La préparation se lit d’abord (leçon, accord de l’élève) : le rideau ne se lève que pour un départ qui peut
    /// partir sans question. Sinon la feuille s’ouvre sur la question d’accord, sans rideau qui se couperait.
    private func openCapturePreparation() async {
        guard capturePreparation == nil, !isOpeningTrip, let capture, mayStartCapture(now: Date()) else { return }
        isOpeningTrip = true
        defer { isOpeningTrip = false }
        guard await model.savePreparationBeforeDeparture(), capturePreparation == nil,
              mayStartCapture(now: Date()) else { return }
        let preparation = agenda.capturePreparation(scope: model.scope, lessonID: model.lessonID, controller: capture)
        await preparation.load()
        guard capturePreparation == nil else { preparation.invalidate(); return }
        if preparation.readyForOneStepStart { DrivyLaunchCurtain.shared.show() }
        capturePreparation = preparation
    }

    /// Annuler pendant un trajet l’arrête d’abord, comme depuis l’écran du trajet : aucune position après l’annulation.
    private func planningSheet(_ route: PlanningRoute) -> some View {
        let controller = capture
        var beforeCancellation: (@MainActor () async -> Bool)?
        if route.cancelling && captureStatus == .collecting {
            beforeCancellation = { @MainActor in await controller?.stopAndSynchronize() ?? true }
        }
        return SchoolPlanningView(model: route.model, cancelling: route.cancelling, beforeCancellation: beforeCancellation)
            .onChange(of: route.model.confirmedCancellationLessonID) { _, id in
                if let id, id == model.lessonID, capture?.lessonID == id { capture?.closeSaved() }
            }
    }

    private func openPlanning(_ lesson: SchoolLesson, cancelling: Bool) {
        let planning = SchoolPlanningWorkspace(scope: model.scope, client: agenda.planningClient, lesson: lesson)
        planningRoute = PlanningRoute(model: planning, cancelling: cancelling)
    }

    // MARK: Avant la leçon

    private func goalsEditor() -> some View {
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
            if model.preparationChanged {
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
