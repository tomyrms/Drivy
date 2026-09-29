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
    @State private var model: SchoolLessonReportWorkspace?
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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(DrivyTheme.canvas)
            } else {
                ContentUnavailableView("Choisissez votre école", systemImage: "building.2")
            }
        }
        .navigationTitle("Leçon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") {
                    if hasUnsavedChanges { confirmsDiscard = true } else { model?.invalidate(); dismiss() }
                }.disabled(model?.isBusy == true)
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges || model?.isBusy == true)
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
            let value = SchoolLessonReportWorkspace(scope: scope, membership: membership, lessonID: lessonID, client: client)
            model = value; await value.load()
        }
    }
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
    @State private var showComplete = false
    @State private var completionOpened = false
    @State private var showReloadConfirmation = false
    @State private var confirmsNoShow = false
    @State private var showsLive = false
    @State private var observationRoute: ObservationRoute?
    @State private var capturePreparation: SchoolCapturePreparationWorkspace?
    @State private var planningRoute: PlanningRoute?

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
    private var readsLesson: Bool { model.isAuthor || model.isOwnLearner }
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
        .sheet(isPresented: $showComplete) { SchoolLessonCompletionSheet(model: model).environment(capture) }
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
                    if completing { showComplete = true }
                })
            }
        }
        .onChange(of: captureStatus) { _, status in if status != .collecting && status != .stopped { showsLive = false } }
        .onChange(of: model.lesson?.status) { _, _ in openCompletionIfAsked() }
        .onAppear { openCompletionIfAsked() }
    }

    private func form(now: Date) -> some View {
        let bar = plannedBar(now: now)
        return Form {
            headerSection
            if model.pending != nil { pendingSection }
            if isCompleted, readsLesson, !model.track.isEmpty { trackSection }
            if isCompleted, readsLesson { observationsSection }
            if model.isAuthor, isCompleted, model.draft != nil { reportEditor }
            if model.isOwnLearner, isCompleted { sharedReportSection }
            if isPlanned, model.isAuthor { goalsEditor(savesInline: !isGoalsBar(bar)) }
            if isPlanned, model.isOwnLearner, let goals = model.preparation?.goals, !goals.isEmpty { goalsReader(goals) }
            if isPlanned, model.isAuthor { observationsSection }
            if let wish = model.wish, showsWish(wish) { wishSection(wish) }
        }
        .scrollContentBackground(.hidden)
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
        guard opensCompletion, !completionOpened, isPlanned, model.isAuthor else { return }
        completionOpened = true; showComplete = true
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
                DrivyAvatar(name: learnerName, size: 52)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(learnerName).font(.drivyTitle).fixedSize(horizontal: false, vertical: true)
                    if let lesson = model.lesson {
                        if let schedule = SchoolLessonHubRules.schedule(lesson) {
                            Text(schedule).font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Label(lesson.meetingPoint, systemImage: "mappin").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Un badge seulement pour l’inhabituel.
            if let lesson = model.lesson, lesson.drivyState.isUnusual { lesson.drivyState.badge }
            if model.isLoading || model.isBusy {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.errorMessage {
                SchoolErrorNotice(message: error, retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
            }
            if let message = model.confirmation { DrivyInlineMessage(text: message) }
            if let message = model.information { DrivyInlineMessage(text: message, tone: .neutral) }
        }
        .listRowBackground(Color.clear)
    }

    private var pendingSection: some View {
        Section {
            Label("Envoi en attente de confirmation", systemImage: "clock.arrow.circlepath").foregroundStyle(DrivyTheme.warning)
            DisclosureGroup("Voir la demande") { Text(model.pendingDescription).textSelection(.enabled) }
            Button("Vérifier") { Task { await model.verifyPending() } }.disabled(model.isBusy || model.isLoading)
            if model.pending?.kind.isReport == true {
                Button("Renvoyer") { model.reviewPending(); Task { await model.retryPending() } }
                    .disabled(model.isBusy || model.isLoading)
            }
        }
    }

    // MARK: Actions de la leçon

    @ViewBuilder private func lessonMenu(now: Date) -> some View {
        if let lesson = model.lesson {
            let moves = SchoolLessonHubRules.mayMove(lesson, roles: model.membership.roles, now: now)
            let cancels = SchoolLessonHubRules.mayCancel(lesson, roles: model.membership.roles)
            let absent = model.mayMarkNoShow(now: now)
            if moves || cancels || absent {
                Menu {
                    if absent {
                        Button("Élève absent", systemImage: "person.crop.circle.badge.xmark") { confirmsNoShow = true }
                    }
                    if moves {
                        Button("Déplacer", systemImage: "calendar.badge.clock") { openPlanning(lesson, cancelling: false) }
                    }
                    if cancels {
                        Button("Annuler la leçon", systemImage: "calendar.badge.minus", role: .destructive) { openPlanning(lesson, cancelling: true) }
                    }
                } label: {
                    Label("Plus d’actions", systemImage: "ellipsis.circle")
                }
                .disabled(model.isBusy || model.isLoading || !model.canMutate)
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
            Button { showComplete = true } label: { Label("Terminer la leçon", systemImage: "checkmark.circle") }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.canMutate)
                .accessibilityIdentifier("lesson-complete")
        } else {
            Button { showComplete = true } label: {
                Text("Terminer la leçon")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.canMutate ? DrivyTheme.accent : DrivyTheme.disabledText)
            .disabled(!model.canMutate)
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
            LessonTrackMap(segments: model.track, pins: pins)
                .listRowInsets(EdgeInsets())
            if model.isAuthor, model.sharing != nil {
                Toggle("Visible par l’élève", isOn: Binding(get: { model.captureShared },
                    set: { shared in Task { await model.updateSharing(captureHidden: !shared) } }))
                    .disabled(!model.canMutate)
            }
        } header: { Text("Trajet") }
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
                            Image(systemName: kept ? "lock.fill" : "lock.open")
                                .foregroundStyle(kept ? DrivyTheme.warning : DrivyTheme.muted)
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
        return model.competencies.first(where: { $0.id == id })?.label
    }

    // MARK: Bilan

    @ViewBuilder private var reportEditor: some View {
        Section {
            if model.sharing != nil {
                Toggle("Visible par l’élève", isOn: Binding(get: { model.reportShared },
                    set: { shared in Task { await model.updateSharing(reportPrivate: !shared) } }))
                    .disabled(!model.canMutate)
            }
            reportField("Travail réalisé", text: $model.workedOn)
            reportField("À retenir", text: $model.observationText)
            reportField("Prochaine étape", text: $model.nextStep)
        } header: { Text("Bilan") }
        if !model.competencies.isEmpty {
            Section {
                let suggestions = model.suggestedObservations
                if !suggestions.isEmpty {
                    Button("Reprendre les niveaux notés (\(suggestions.count))", systemImage: "wand.and.stars") { model.applySuggestedLevels() }
                        .disabled(!model.canMutate)
                        .accessibilityIdentifier("lesson-apply-suggested-levels")
                }
                // Un niveau choisi suffit : la situation est proposée (observation liée, sinon jour et lieu), modifiable.
                ForEach(model.competencies) { competency in
                    Picker(competency.label, selection: levelBinding(competency.id)) {
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
                            .accessibilityLabel("Situation, \(competency.label)")
                    }
                }
            } header: { Text("Compétences") }
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
                    DrivyCompetencyNote(label: model.competencies.first(where: { $0.id == observation.id })?.label ?? "Compétence",
                        level: observation.levelLabel, context: observation.context)
                }
            } header: { Text("Bilan") }
        } else if model.revisionsError == nil, !model.isLoading {
            Section {
                Text("Votre moniteur n’a pas encore écrit le bilan.").foregroundStyle(DrivyTheme.muted)
            } header: { Text("Bilan") }
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
            TextField("Note pour moi", text: $model.administrativeNote, axis: .vertical).lineLimit(1...4).disabled(!model.canMutate)
            if savesInline {
                Button("Enregistrer") { Task { await model.savePreparation() } }
                    .disabled(!model.canMutate || !model.preparationValid || !model.preparationChanged)
            }
        } header: { Text("Objectifs") }
    }

    private func goalsReader(_ goals: [SchoolLessonGoal]) -> some View {
        Section {
            ForEach(goals) { goal in Text(goal.label) }
        } header: { Text("Objectifs") }
    }

    private func wishSection(_ wish: SchoolLearnerWish) -> some View {
        Section {
            if model.isOwnLearner {
                TextField("Ce que j’aimerais travailler", text: $model.wishText, axis: .vertical).lineLimit(2...6).disabled(!model.canMutate)
                Button("Enregistrer") { Task { await model.saveWish() } }
                    .disabled(!model.canMutate || model.wishText.unicodeScalars.count > 500 || model.wishText == wish.text)
            } else {
                Text(wish.text)
            }
        } header: { Text(model.isOwnLearner ? "Mon souhait" : "Souhait de l’élève") }
    }

    // MARK: Bilan : enregistrement

    private var saveBar: some View {
        DrivyStickyActionBar {
            if !model.validTexts { DrivyActionNote(text: "Un texte dépasse 4 000 caractères.", isError: true) }
            else if !model.observationsValid { DrivyActionNote(text: "Décrivez la situation de chaque compétence.", isError: true) }
            Button { Task { await model.saveDraft() } } label: { Label("Enregistrer le bilan", systemImage: "square.and.arrow.down") }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.canMutate || !model.validTexts || !model.observationsValid || !model.draftChanged)
        }
    }

    private func reportField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(label).font(.headline).accessibilityHidden(true)
            TextField(label, text: text, axis: .vertical).lineLimit(2...10).disabled(!model.canMutate)
                .accessibilityLabel(label)
        }
        .padding(.vertical, DrivySpacing.xxs)
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
