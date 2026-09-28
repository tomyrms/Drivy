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
                SchoolLessonReportContent(model: model, learnerName: learnerName, schoolWorkspace: schoolWorkspace, agenda: client.agenda)
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
    /// Contrôleur de séance de l’app ; absent, rien de ce qui dépend du GPS de l’appareil n’est proposé.
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @State private var showComplete = false
    @State private var showReloadConfirmation = false
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

    private var isCompleted: Bool { model.lesson?.status == "COMPLETED" }
    private var isPlanned: Bool { model.lesson?.status == "PLANNED" }
    /// L’élève ne reçoit que ce qui lui est partagé ; le moniteur voit tout, y compris ce qu’il garde pour lui.
    private var readsLesson: Bool { model.isAuthor || model.isOwnLearner }
    private var captureStatus: SchoolLessonCaptureStatus { SchoolLessonCaptureStatus(controller: capture, lessonID: model.lessonID) }

    var body: some View {
        Form {
            headerSection
            if model.pending != nil { pendingSection }
            if isCompleted, readsLesson, !model.track.isEmpty { trackSection }
            if isCompleted, readsLesson { observationsSection }
            if model.isAuthor, isCompleted, model.draft != nil { reportEditor }
            if model.isOwnLearner, isCompleted { sharedReportSection }
            if isPlanned, model.isAuthor { goalsEditor }
            if isPlanned, model.isOwnLearner, let goals = model.preparation?.goals, !goals.isEmpty { goalsReader(goals) }
            if isPlanned, model.isAuthor { plannedObservationsSection }
            if let wish = model.wish, model.isOwnLearner || !wish.text.isEmpty { wishSection(wish) }
            priceSection
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isAuthor && isPlanned { plannedBar }
            else if model.isAuthor && isCompleted && model.draft != nil { saveBar }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { if model.hasLocalEdits { showReloadConfirmation = true } else { Task { await model.load() } } } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy || model.isLoading)
            }
            ToolbarItem(placement: .topBarTrailing) { lessonMenu }
        }
        .tint(DrivyTheme.accent)
        .confirmationDialog("Recharger et perdre la saisie ?", isPresented: $showReloadConfirmation, titleVisibility: .visible) {
            Button("Recharger", role: .destructive) { Task { await model.load(discardingEdits: true) } }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showComplete) { SchoolLessonCompletionSheet(model: model).environment(capture) }
        .sheet(item: $observationRoute, onDismiss: { Task { await model.load() } }) { route in
            SchoolObservationEntryView(client: route.client, schoolWorkspace: schoolWorkspace, lessonID: route.lessonID)
        }
        .sheet(item: $capturePreparation, onDismiss: {
            // Départ réussi : le trajet en cours s’ouvre directement.
            if SchoolLessonCaptureStatus(controller: capture, lessonID: model.lessonID) == .collecting { showsLive = true }
        }) { preparation in
            SchoolCapturePreparationView(model: preparation, schoolWorkspace: schoolWorkspace)
        }
        .sheet(item: $planningRoute, onDismiss: { Task { await model.load() } }) { route in
            SchoolPlanningView(model: route.model, cancelling: route.cancelling)
        }
        .navigationDestination(isPresented: $showsLive) {
            if let capture { SchoolCaptureLiveView(controller: capture, learnerName: learnerName) }
        }
        .onChange(of: captureStatus) { _, status in if status != .collecting && status != .stopped { showsLive = false } }
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
            if let lesson = model.lesson, ["CANCELLED", "NO_SHOW"].contains(lesson.status) { lesson.drivyState.badge }
            if let lesson = model.lesson, model.isAuthor, lesson.status == "PLANNED", lesson.permitWarning, !model.permitRecorded {
                DrivyStatusBadge(title: "Permis à vérifier", symbol: "exclamationmark.triangle", tone: .warning)
            }
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

    @ViewBuilder private var lessonMenu: some View {
        if let lesson = model.lesson {
            let moves = SchoolLessonHubRules.mayMove(lesson, roles: model.membership.roles, now: Date())
            let cancels = SchoolLessonHubRules.mayCancel(lesson, roles: model.membership.roles)
            if moves || cancels {
                Menu {
                    if moves {
                        Button("Déplacer", systemImage: "calendar.badge.clock") { openPlanning(lesson, cancelling: false) }
                    }
                    if cancels {
                        Button("Annuler la leçon", systemImage: "calendar.badge.minus", role: .destructive) { openPlanning(lesson, cancelling: true) }
                    }
                } label: {
                    Label("Plus d’actions", systemImage: "ellipsis.circle")
                }
                .disabled(model.isBusy || model.isLoading)
                .accessibilityIdentifier("lesson-more-actions")
            }
        }
    }

    /// Leçon planifiée du moniteur : démarrer le trajet (ou y revenir), puis terminer.
    private var plannedBar: some View {
        TimelineView(.everyMinute) { context in
            DrivyStickyActionBar {
                if captureStatus == .collecting {
                    Button { showsLive = true } label: { Label("Trajet en cours", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityHint("Ouvre le trajet")
                        .accessibilityIdentifier("lesson-live-capture")
                    completeButton(primary: false)
                } else if mayStartCapture(now: context.date) {
                    Button { openCapturePreparation() } label: { Label("Démarrer le trajet", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("lesson-prepare-gps")
                    completeButton(primary: false)
                } else {
                    completeButton(primary: true)
                }
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

    private var plannedObservationsSection: some View {
        Section {
            Button("Noter une observation", systemImage: "square.and.pencil") { openObservations() }
                .disabled(model.isBusy || model.isLoading)
                .accessibilityIdentifier("lesson-private-observations")
        } header: { Text("Pendant la leçon") }
    }

    private var observationsSection: some View {
        Section {
            if model.lessonObservations.isEmpty {
                Text("Aucune observation.").foregroundStyle(DrivyTheme.muted)
            }
            ForEach(model.lessonObservations) { observation in
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    Circle().fill(color(observation)).frame(width: 10, height: 10).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(observation.text).fixedSize(horizontal: false, vertical: true)
                        if let label = competencyLabel(observation) {
                            Text(label).font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                    }
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
                        .accessibilityLabel(kept ? "Gardée pour moi" : "Visible par l’élève")
                        .accessibilityHint(kept ? "Montrer à l’élève" : "Garder pour moi")
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if model.isAuthor {
                Button("Modifier les observations", systemImage: "square.and.pencil") { openObservations() }
                    .disabled(model.isBusy || model.isLoading)
            }
        } header: { Text("Pendant la leçon") }
    }

    private func color(_ observation: SchoolObservation) -> Color {
        switch observation.eventStatus ?? "" {
        case "POSITIVE": DrivyTheme.success
        case "ATTENTION": DrivyTheme.warning
        case "TO_REWORK": DrivyTheme.danger
        default: DrivyTheme.muted
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
                // Un niveau choisi suffit : la situation est proposée (jour et lieu), modifiable.
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

    private var goalsEditor: some View {
        Section {
            ForEach(model.goals.indices, id: \.self) { index in
                HStack {
                    TextField("Objectif \(index + 1)", text: goalBinding(index), axis: .vertical)
                    Button(role: .destructive) { if model.goals.indices.contains(index) { model.goals.remove(at: index) } } label: {
                        Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Retirer l’objectif \(index + 1)")
                }
                .disabled(!model.canMutate)
            }
            if model.goals.count < 3 {
                Button("Ajouter un objectif", systemImage: "plus") {
                    model.goals.append(SchoolLessonGoal(label: "", competencyId: nil, context: nil))
                }
                .disabled(!model.canMutate)
            }
            TextField("Note pour moi", text: $model.administrativeNote, axis: .vertical).lineLimit(1...4).disabled(!model.canMutate)
            Button("Enregistrer") { Task { await model.savePreparation() } }
                .disabled(!model.canMutate || !model.preparationValid || !model.preparationChanged)
        } header: { Text("Objectifs") }
    }
    /// Un objectif retiré peut encore être relu par son champ pendant la mise à jour : jamais d’index hors limites.
    private func goalBinding(_ index: Int) -> Binding<String> {
        Binding(get: { model.goals.indices.contains(index) ? model.goals[index].label : "" },
                set: { value in if model.goals.indices.contains(index) { model.goals[index].label = value } })
    }

    private func goalsReader(_ goals: [SchoolLessonGoal]) -> some View {
        Section {
            ForEach(goals.indices, id: \.self) { index in Text(goals[index].label) }
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

    @ViewBuilder private var priceSection: some View {
        if let account = model.account {
            Section {
                LabeledContent("À payer") { Text(SchoolCatalogFormatting.price(account.balanceCents)).monospacedDigit() }
            }
        } else if isPlanned, let lesson = model.lesson {
            Section {
                LabeledContent("Prix") { Text(SchoolCatalogFormatting.price(lesson.priceCentsSnapshot)).monospacedDigit() }
            }
        }
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
