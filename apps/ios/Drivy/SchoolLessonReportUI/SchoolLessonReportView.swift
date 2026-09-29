import MapKit
import SwiftUI

/// L’écran unique d’une leçon : avant (objectifs, départ du trajet), pendant (trajet en cours, observations),
/// après (trajet, observations, bilan). Tout est partagé avec l’élève automatiquement ; le moniteur garde
/// pour lui ce qu’il choisit.
struct SchoolLessonReportView: View {
    let client: SchoolLessonReportClient
    @Bindable var schoolWorkspace: SchoolWorkspace
    let lessonID: UUID
    let learnerName: String
    /// Ouvre « Terminer » dès que la leçon est lue (« À terminer » d’Aujourd’hui, fin du trajet).
    var opensCompletion = false
    /// Élève : le souhait se modifie sur la prochaine leçon seulement ; `nil` quand l’appelant ne le sait pas.
    var isNextPlanned: Bool? = nil
    var outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()
    @State private var model: SchoolLessonReportWorkspace?
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDiscard = false

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
                    opensCompletion: opensCompletion, isNextPlanned: isNextPlanned)
            } else if schoolWorkspace.membership != nil {
                ProgressView("Chargement de la leçon…")
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(DrivyTheme.canvas)
            } else {
                ContentUnavailableView("Choisissez votre école", systemImage: "building.2")
            }
        }
        .navigationTitle("Leçon")
        .navigationBarTitleDisplayMode(.inline)
        .presentationSizing(.page)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") {
                    if hasUnsavedChanges { confirmsDiscard = true } else { model?.invalidate(); dismiss() }
                }.disabled(model?.isBusy == true)
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges || model?.isBusy == true)
        .onChange(of: model?.reportSaveConfirmed) { _, confirmed in
            guard confirmed == true else { return }
            capture?.closeLessonFlow(lessonID: lessonID)
            model?.invalidate()
            dismiss()
        }
        .confirmationDialog("Fermer sans enregistrer ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Fermer sans enregistrer", role: .destructive) { model?.invalidate(); dismiss() }
            Button("Continuer", role: .cancel) { }
        }
        .task(id: scopeKey) {
            // Une feuille enfant plein écran peut faire réapparaître cette vue : garder le modèle
            // tant que le compte et l’école ne changent pas.
            if let model, matches(model) { return }
            model?.invalidate(); model = nil
            guard let person = schoolWorkspace.person, let membership = schoolWorkspace.membership else { return }
            let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId, membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
            let value = SchoolLessonReportWorkspace(scope: scope, membership: membership, lessonID: lessonID, client: client, outbox: outbox)
            model = value; await value.load()
        }
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
    let isNextPlanned: Bool?
    /// Contrôleur de séance de l’app ; absent, rien de ce qui dépend du GPS de l’appareil n’est proposé.
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var lessonSheet: LessonSheet?
    @State private var replay: SchoolTripReplayRoute?
    @State private var isFinishing = false
    @State private var finishError: String?
    @State private var completionOpened = false
    @State private var showReloadConfirmation = false
    @State private var confirmsNoShow = false
    @State private var showsLive = false
    @State private var observationRoute: ObservationRoute?
    @State private var capturePreparation: SchoolCapturePreparationWorkspace?
    @State private var planningRoute: PlanningRoute?

    private enum LessonSheet: String, Identifiable {
        case permit, tariff
        var id: String { rawValue }
    }

    private struct ObservationRoute: Identifiable {
        let id = UUID()
        let client: SchoolObservationClient
        let lessonID: UUID
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

    var body: some View {
        TimelineView(.everyMinute) { context in
            form(now: context.date)
        }
        .tint(DrivyTheme.accent)
        .confirmationDialog("Recharger et perdre la saisie ?", isPresented: $showReloadConfirmation, titleVisibility: .visible) {
            Button("Recharger", role: .destructive) { Task { await model.load(discardingEdits: true) } }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("L’élève est absent ?", isPresented: $confirmsNoShow, titleVisibility: .visible) {
            Button("Élève absent", role: .destructive) { Task { _ = await model.markNoShow(reason: "Élève absent au rendez-vous.") } }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(item: $lessonSheet) { sheet in
            switch sheet {
            case .permit: SchoolLessonCompletionSheet(model: model, finish: finishLesson)
            case .tariff: SchoolLessonTariffSheet(model: model)
            }
        }
        .fullScreenCover(item: $replay) { route in
            SchoolCaptureReplayView(model: route.model, learnerName: route.learnerName)
        }
        .sheet(item: $observationRoute, onDismiss: { Task { await model.load() } }) { route in
            SchoolObservationEntryView(client: route.client, schoolWorkspace: schoolWorkspace, lessonID: route.lessonID)
        }
        .sheet(item: $capturePreparation, onDismiss: { captureSheetClosed() }) { preparation in
            SchoolCapturePreparationView(model: preparation, schoolWorkspace: schoolWorkspace)
        }
        .sheet(item: $planningRoute, onDismiss: { Task { await model.load() } }) { route in
            SchoolPlanningView(model: route.model, cancelling: route.cancelling)
        }
        .navigationDestination(isPresented: $showsLive) {
            if let capture {
                SchoolCaptureLiveView(controller: capture, learnerName: learnerName, openLesson: { _, completing in
                    showsLive = false
                    if completing { Task { _ = await finishLesson("") } }
                }, observationClient: agenda.observationClient)
            }
        }
        .onChange(of: captureStatus) { _, status in if status != .collecting && status != .stopped { showsLive = false } }
        .onChange(of: showsLive) { _, visible in
            if !visible { Task { await model.refreshObservations() } }
        }
        .onChange(of: model.lesson?.status) { _, _ in openCompletionIfAsked() }
        .onChange(of: model.isLoading) { _, loading in if !loading { openCompletionIfAsked() } }
        .onChange(of: capture?.finalizedSyncState) { _, state in
            if isCompleted && (state == .synced || state == .partial) { Task { await model.load() } }
        }
        .onAppear { openCompletionIfAsked() }
        .interactiveDismissDisabled(isFinishing)
    }

    private func form(now: Date) -> some View {
        let bar = plannedBar(now: now)
        return GeometryReader { geometry in
            // Le contexte reste à portée pendant la rédaction. La saisie vit dans le modèle,
            // au-dessus de ce changement de composition et des rotations de la fenêtre.
            if geometry.size.width >= LessonLayout.splitBreakpoint && hasCompletedReport && !typeSize.isAccessibilitySize {
                HStack(spacing: 0) {
                    Form { lessonContext }
                        .scrollContentBackground(.hidden)
                        .frame(width: LessonLayout.contextColumnWidth)
                    Form { completedReport }
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: LessonLayout.splitMaxWidth)
                .frame(maxWidth: .infinity)
            } else {
                Form {
                    lessonContext
                    completedReport
                    // Avant la leçon : le souhait de l’élève éclaire les objectifs, puis viennent les observations.
                    Group {
                        if let wish = model.wish, showsWish(wish) { wishSection(wish) }
                        if isPlanned, model.isAuthor { goalsEditor(savesInline: !isGoalsBar(bar)) }
                        if isPlanned, model.isOwnLearner, let goals = model.preparation?.goals, !goals.isEmpty { goalsReader(goals) }
                        if isPlanned, model.isAuthor { observationsSection }
                    }
                    .drivyFormRows()
                }
                .scrollContentBackground(.hidden)
                .frame(maxWidth: LessonLayout.formMaxWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let bar { plannedBarView(bar) }
            else if model.isAuthor && isCompleted && model.draft != nil { saveBar }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { if model.hasLocalEdits { showReloadConfirmation = true } else { Task { await model.load() } } } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy || model.isLoading)
            }
            ToolbarItem(placement: .topBarTrailing) { lessonMenu(now: now) }
        }
    }

    private var hasCompletedReport: Bool {
        isCompleted && ((model.isAuthor && model.draft != nil) || (!model.isAuthor && model.canReadSharedReport))
    }

    /// Les lignes des sections prennent la surface du thème (le gris système du sombre ne s’accorde pas au canevas).
    @ViewBuilder private var lessonContext: some View {
        headerSection
        Group {
            if model.needsReload && model.hasLocalEdits {
                Section("Saisie conservée") { Text(model.retainedEditsText).textSelection(.enabled) }
                    .drivyFormRows()
            }
            if model.pending != nil { pendingSection }
            if isCompleted, readsLesson, !model.captures.isEmpty || !model.track.isEmpty { trackSection }
            if isCompleted, model.isAuthor || model.isOwnLearner { observationsSection }
        }
        .drivyFormRows()
    }

    @ViewBuilder private var completedReport: some View {
        Group {
            if model.isAuthor, isCompleted, model.draft != nil { reportEditor }
            if !model.isAuthor, model.canReadSharedReport, isCompleted { sharedReportSection }
        }
        .drivyFormRows()
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
        guard opensCompletion, !completionOpened, isPlanned, model.isAuthor, model.canMutate else { return }
        completionOpened = true
        Task { _ = await finishLesson("") }
    }

    /// L’arrêt est écrit sur l’appareil avant le constat. Le transfert du trajet continue sans retenir le bilan.
    private func finishLesson(_ reason: String) async -> Bool {
        guard !isFinishing, model.canMutate, isPlanned, model.isAuthor else { return false }
        isFinishing = true; finishError = nil
        defer { isFinishing = false }
        if let capture, !(await capture.finishForLesson(lessonID: model.lessonID)) {
            finishError = capture.errorMessage ?? "Le trajet n’a pas pu être enregistré. Réessayez pour terminer la leçon."
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
        return await model.complete(start: times.start, end: times.end, reason: reason, localCaptureStopped: true)
    }

    /// Départ réussi depuis cette feuille : elle se ferme pour laisser le trajet en cours à l’écran.
    private func captureSheetClosed() {
        guard captureStatus == .collecting else { return }
        if model.hasLocalEdits { showsLive = true } else { model.invalidate(); dismiss() }
    }

    // MARK: En-tête

    private var headerSection: some View {
        Section {
            HStack(alignment: .center, spacing: DrivySpacing.m) {
                DrivyAvatar(name: learnerName, size: 56)
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text(learnerName).font(.drivyTitle).fixedSize(horizontal: false, vertical: true)
                    if let lesson = model.lesson {
                        scheduleLines(lesson)
                        // Le badge de l’inhabituel vit dans l’en-tête, sous le lieu, dans la même colonne de texte.
                        if lesson.drivyState.isUnusual { lesson.drivyState.badge }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if model.isLoading || model.isBusy {
                DrivyLoadingState(title: model.isLoading ? "Chargement de la leçon…" : "Enregistrement…")
            }
            if let error = model.errorMessage {
                SchoolErrorNotice(message: error, retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
            }
            if let finishError { DrivyInlineMessage(text: finishError, tone: .danger) }
            if let message = model.confirmation { DrivyInlineMessage(text: message) }
            if let message = model.information { DrivyInlineMessage(text: message, tone: .neutral) }
        }
        .listRowBackground(Color.clear)
        // En-tête posé sur le canevas : aucun filet entre le nom, l’état et les messages.
        .listRowSeparator(.hidden)
    }

    /// Date, horaire et lieu : sur une ligne quand la colonne le permet, sinon la date, l’horaire puis le lieu.
    /// L’intervalle horaire ne se coupe jamais entre ses deux heures.
    @ViewBuilder private func scheduleLines(_ lesson: SchoolLesson) -> some View {
        let schedule = SchoolLessonHubRules.schedule(lesson)?.replacingOccurrences(of: " – ", with: "\u{00A0}–\u{00A0}")
        let parts = schedule?.components(separatedBy: " · ") ?? []
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                if let schedule { headerLine("clock", schedule).fixedSize(horizontal: true, vertical: false) }
                headerLine("mappin", lesson.meetingPoint).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                if parts.count == 2 {
                    headerLine("calendar", parts[0])
                    headerLine("clock", parts[1])
                } else if let schedule {
                    headerLine("clock", schedule)
                }
                headerLine("mappin", lesson.meetingPoint)
            }
        }
    }

    /// Ligne de contexte de l’en-tête : symbole collé au texte, aligné sur la ligne de base, graisse constante.
    private func headerLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
            Image(systemName: symbol).font(.footnote.weight(.semibold)).accessibilityHidden(true)
            Text(text).monospacedDigit().fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
    }

    /// Même présentation que partout ailleurs pour une demande au résultat inconnu.
    private var pendingSection: some View {
        let idle = !(model.isBusy || model.isLoading)
        let retry: (() -> Void)? = model.pending?.kind.isReport == true
            ? { model.reviewPending(); Task { await model.retryPending() } }
            : nil
        return Section {
            DrivyPendingRequest(
                message: "La demande est conservée sur cet appareil. Vérifiez son résultat avant une nouvelle action.",
                verify: { Task { await model.verifyPending() } }, canVerify: idle,
                retry: retry, canRetry: idle
            ) {
                DisclosureGroup {
                    Text(model.pendingDescription)
                        .font(.footnote)
                        .foregroundStyle(DrivyTheme.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Voir la demande").font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
        }
            .drivyFormRows()
    }

    // MARK: Actions de la leçon

    @ViewBuilder private func lessonMenu(now: Date) -> some View {
        if let lesson = model.lesson {
            let moves = SchoolLessonHubRules.mayMove(lesson, roles: model.membership.roles, now: now)
            let cancels = SchoolLessonHubRules.mayCancel(lesson, roles: model.membership.roles)
            let absent = model.mayMarkNoShow(now: now)
                Menu {
                    Button("Tarif", systemImage: "creditcard") { lessonSheet = .tariff }
                    if absent {
                        Button("Élève absent", systemImage: "person.crop.circle.badge.xmark") { confirmsNoShow = true }
                            .disabled(!model.canMutate || isFinishing)
                    }
                    if moves {
                        Button("Déplacer", systemImage: "calendar.badge.clock") { openPlanning(lesson, cancelling: false) }
                            .disabled(!model.canMutate || isFinishing)
                    }
                    if cancels {
                        Button("Annuler la leçon", systemImage: "calendar.badge.minus", role: .destructive) { openPlanning(lesson, cancelling: true) }
                            .disabled(!model.canMutate || isFinishing)
                    }
                } label: {
                    Label("Plus d’actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("lesson-more-actions")
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
                    Label("Enregistrer les objectifs", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.canMutate || !model.preparationValid || !model.preparationChanged)
                .accessibilityIdentifier("lesson-save-goals")
            }
        }
    }

    @ViewBuilder private func completeButton(primary: Bool) -> some View {
        if primary {
            Button { Task { _ = await finishLesson("") } } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if isFinishing { ProgressView().accessibilityHidden(true) }
                    Label("Terminer la leçon", systemImage: "checkmark.circle")
                }
            }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.canMutate || isFinishing)
                .accessibilityIdentifier("lesson-complete")
        } else {
            // Action alternative sous « Démarrer le trajet » ou « Trajet en cours » : même composant que partout.
            Button { Task { _ = await finishLesson("") } } label: {
                HStack(spacing: DrivySpacing.xs) {
                    if isFinishing { ProgressView().accessibilityHidden(true) }
                    Label("Terminer la leçon", systemImage: "checkmark.circle")
                }
            }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!model.canMutate || isFinishing)
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

    private func openObservations() {
        observationRoute = ObservationRoute(client: agenda.observationClient, lessonID: model.lessonID)
    }

    // MARK: Trajet et observations

    private var pins: [LessonTrackMap.Pin] {
        model.lessonObservations.compactMap { observation in
            guard let point = model.anchor(of: observation) else { return nil }
            return LessonTrackMap.Pin(id: observation.id, latitude: point.latitude, longitude: point.longitude, color: color(observation))
        }
    }

    private var trackSection: some View {
        Section {
            if !model.track.isEmpty {
                LessonTrackMap(segments: model.track, pins: pins)
                    .listRowInsets(EdgeInsets())
            }
            ForEach(Array(model.replayableCaptures.enumerated()), id: \.element.id) { index, capture in
                Button {
                    replay = SchoolTripReplayRoute(model: SchoolCaptureReplayWorkspace(scope: model.scope, client: agenda.captureClient,
                        captureID: capture.id), learnerName: learnerName)
                } label: {
                    Label(model.replayableCaptures.count == 1 ? "Revoir le trajet" : "Revoir le trajet \(index + 1)", systemImage: "play.circle")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("lesson-replay-\(capture.id.uuidString)")
            }
            if model.captures.contains(where: { $0.syncState != .synced && $0.syncState != .partial && $0.publicationState == .privateCapture }) {
                Label("Trajet en cours d’envoi", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(DrivyTheme.muted)
            }
            if model.isAuthor, model.sharing != nil {
                sharingToggle(Binding(get: { model.captureShared },
                    set: { shared in Task { await model.updateSharing(captureHidden: !shared) } }))
            }
        } header: { Text("Trajet") }
            .drivyFormRows()
    }

    private var observationsSection: some View {
        Section {
            if model.lessonObservations.isEmpty && isCompleted {
                Text("Aucune observation.").foregroundStyle(DrivyTheme.muted)
            }
            ForEach(model.lessonObservations) { observation in
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    observationContent(observation)
                    Spacer(minLength: 0)
                    if model.isAuthor, model.sharing != nil {
                        let kept = model.isPrivate(observation)
                        Button {
                            Task { await model.updateSharing(observation: observation.id, observationPrivate: !kept) }
                        } label: {
                            DrivyPrivacyMark(isPrivate: kept)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!model.canMutate)
                        .accessibilityLabel(kept ? "Pour moi" : "Visible par l’élève")
                        .accessibilityHint(kept ? "Montrer à l’élève" : "Garder pour moi")
                    }
                }
            }
            if model.isAuthor {
                Button(isPlanned ? "Noter une observation" : "Modifier les observations", systemImage: "square.and.pencil") { openObservations() }
                    .disabled(model.isBusy || model.isLoading)
                    .accessibilityIdentifier("lesson-private-observations")
            }
        } header: { Text("Pendant la leçon") }
            .drivyFormRows()
    }

    /// Constat par symbole, libellé et couleur : jamais par la couleur seule.
    private func observationContent(_ observation: SchoolObservation) -> some View {
        let status = SchoolLessonHubRules.status(of: observation)
        return HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            Image(systemName: status?.symbol ?? (observation.isMarker ? "bookmark.fill" : "text.bubble.fill"))
                .font(.caption.weight(.bold))
                .foregroundStyle(color(observation))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                if let status {
                    Text(status.label).font(.caption.weight(.semibold)).foregroundStyle(color(observation))
                }
                if observation.text != status?.label {
                    Text(observation.text).fixedSize(horizontal: false, vertical: true)
                }
                if let label = competencyLabel(observation) {
                    Text(label).font(.caption).foregroundStyle(DrivyTheme.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ observation: SchoolObservation) -> Color {
        switch SchoolLessonHubRules.status(of: observation) {
        case .positive: DrivyTheme.success
        case .attention: DrivyTheme.warning
        case .toWorkOn: DrivyTheme.danger
        case nil: DrivyTheme.muted
        }
    }
    private func competencyLabel(_ observation: SchoolObservation) -> String? {
        guard let id = observation.competencyId else { return nil }
        return model.competencies.first(where: { $0.id == id })?.displayLabel
    }

    // MARK: Bilan

    @ViewBuilder private var reportEditor: some View {
        Section {
            if model.sharing != nil {
                sharingToggle(Binding(get: { model.reportShared },
                    set: { shared in Task { await model.updateSharing(reportPrivate: !shared) } }))
            }
            reportField("Travail réalisé", text: $model.workedOn)
            reportField("À retenir", text: $model.observationText)
            reportField("Prochaine étape", text: $model.nextStep)
        } header: { Text("Bilan") }
            .drivyFormRows()
        if !model.competencies.isEmpty {
            Section {
                // Un niveau choisi suffit : le jour et le lieu sont proposés comme situation, modifiable.
                ForEach(model.competencies) { competency in
                    Picker(competency.displayLabel, selection: levelBinding(competency.id)) {
                        Text("Non observé").tag("")
                        Text("En découverte").tag("DISCOVERING")
                        Text("Avec accompagnement").tag("GUIDED")
                        Text("En autonomie").tag("INDEPENDENT")
                    }
                    .pickerStyle(.menu)
                    .disabled(!model.canMutate)
                    if model.observations.contains(where: { $0.id == competency.id }) {
                        TextField("Situation", text: contextBinding(competency.id), axis: .vertical)
                            .font(.subheadline)
                            .foregroundStyle(DrivyTheme.muted)
                            .disabled(!model.canMutate)
                            .accessibilityLabel("Situation, \(competency.displayLabel)")
                    }
                }
            } header: { Text("Compétences") }
                .drivyFormRows()
        }
    }

    private func levelBinding(_ competencyID: UUID) -> Binding<String> {
        Binding(get: { model.observations.first(where: { $0.id == competencyID })?.level ?? "" },
                set: { model.setObservationLevel($0, for: competencyID) })
    }
    private func contextBinding(_ competencyID: UUID) -> Binding<String> {
        Binding(get: { model.observations.first(where: { $0.id == competencyID })?.context ?? "" },
                set: { value in
                    if let index = model.observations.firstIndex(where: { $0.id == competencyID }) { model.observations[index].context = value }
                })
    }

    @ViewBuilder private var sharedReportSection: some View {
        if let revision = model.revisions.first {
            Section {
                DrivyReportBody(nextStep: revision.nextStep, workedOn: revision.workedOn, observationText: revision.observationText, compact: true)
                ForEach(revision.observations) { observation in
                    DrivyCompetencyNote(label: model.competencies.first(where: { $0.id == observation.id })?.displayLabel ?? "Compétence",
                        level: observation.levelLabel, context: observation.context)
                }
            } header: { Text("Bilan") }
                .drivyFormRows()
        } else if model.revisionsError == nil, !model.isLoading {
            Section {
                Text("Votre moniteur n’a pas encore écrit le bilan.").foregroundStyle(DrivyTheme.muted)
            } header: { Text("Bilan") }
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
                .disabled(!model.canMutate)
            }
            if model.goals.count < 3 {
                Button("Ajouter un objectif", systemImage: "plus") {
                    model.goals.append(SchoolLessonGoal(label: ""))
                }
                .disabled(!model.canMutate)
            }
            // Jamais montrée à l’élève : le cadenas le dit sans texte.
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                DrivyPrivacyMark(isPrivate: true).accessibilityHidden(true)
                TextField("Note pour moi", text: $model.administrativeNote, axis: .vertical).lineLimit(1...4).disabled(!model.canMutate)
            }
            if savesInline {
                Button("Enregistrer les objectifs") { Task { await model.savePreparation() } }
                    .disabled(!model.canMutate || !model.preparationValid || !model.preparationChanged)
            }
        } header: { Text("Objectifs") }
            .drivyFormRows()
    }

    private func goalsReader(_ goals: [SchoolLessonGoal]) -> some View {
        Section {
            ForEach(goals) { goal in Text(goal.label) }
        } header: { Text("Objectifs") }
            .drivyFormRows()
    }

    private func wishSection(_ wish: SchoolLearnerWish) -> some View {
        Section {
            if model.isOwnLearner {
                TextField("Ce que j’aimerais travailler", text: $model.wishText, axis: .vertical).lineLimit(2...6).disabled(!model.canMutate)
                Button("Enregistrer le souhait") { Task { await model.saveWish() } }
                    .disabled(!model.canMutate || model.wishText.unicodeScalars.count > 500 || model.wishText == wish.text)
            } else {
                Text(wish.text)
            }
        } header: { Text(model.isOwnLearner ? "Mon souhait" : "Souhait de l’élève") }
            .drivyFormRows()
    }

    // MARK: Bilan : enregistrement

    private var saveBar: some View {
        DrivyStickyActionBar {
            if !model.validTexts { DrivyActionNote(text: "Un texte dépasse 4 000 caractères.", isError: true) }
            else if !model.observationsValid { DrivyActionNote(text: "Vérifiez les niveaux et limitez chaque situation à 500 caractères.", isError: true) }
            Button { Task { await model.saveDraft() } } label: { Label("Enregistrer le bilan", systemImage: "square.and.arrow.down") }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.canMutate || !model.validTexts || !model.observationsValid)
                .accessibilityIdentifier("lesson-save-report")
        }
    }

    /// Partage d’un bloc avec l’élève : le cadenas fermé signale ce que le moniteur garde pour lui.
    private func sharingToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text("Visible par l’élève")
            } icon: {
                DrivyPrivacyMark(isPrivate: !isOn.wrappedValue)
            }
        }
        .disabled(!model.canMutate)
    }

    private func reportField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
            TextField("Facultatif", text: text, axis: .vertical).lineLimit(1...10).disabled(!model.canMutate)
                .accessibilityLabel(label)
                .accessibilityHint("Facultatif")
        }
        .padding(.vertical, DrivySpacing.xs)
    }
}

/// Carte d’un trajet enregistré, avec les observations ancrées. Aucune position n’est inventée :
/// sans mesure, la section n’est pas affichée.
struct LessonTrackMap: View {
    struct Pin: Identifiable {
        let id: UUID
        let latitude: Double
        let longitude: Double
        let color: Color
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }
    private struct Line: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
    }
    let segments: [[SchoolCapturePoint]]
    let pins: [Pin]

    private var lines: [Line] {
        segments.enumerated().map { index, points in
            Line(id: index, coordinates: points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
        }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(lines) { line in
                if line.coordinates.count > 1 {
                    MapPolyline(coordinates: line.coordinates).stroke(DrivyTheme.routeHalo, lineWidth: 8)
                    MapPolyline(coordinates: line.coordinates).stroke(DrivyTheme.route, lineWidth: 4)
                }
            }
            ForEach(pins) { pin in
                Annotation("", coordinate: pin.coordinate) {
                    Circle().fill(pin.color).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(DrivyTheme.routeHalo, lineWidth: 2))
                        .accessibilityHidden(true)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 260)
        .accessibilityLabel("Trajet de la leçon")
    }
}
