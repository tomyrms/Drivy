import MapKit
import SwiftUI

/// Une leçon : objectifs avant, puis trajet, observations et bilan après.
/// Tout est partagé avec l’élève automatiquement ; le moniteur garde pour lui ce qu’il choisit.
struct SchoolLessonReportView: View {
    let client: SchoolLessonReportClient
    @Bindable var schoolWorkspace: SchoolWorkspace
    let lessonID: UUID
    let learnerName: String
    @State private var model: SchoolLessonReportWorkspace?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDiscard = false

    private var hasUnsavedChanges: Bool {
        guard let model else { return false }
        return model.draftChanged || (model.isAuthor && model.preparation.map { model.goals != $0.goals || model.administrativeNote != ($0.administrativeCheckNote ?? "") } ?? false)
            || (model.isOwnLearner && model.wish.map { model.wishText != $0.text } == true)
    }

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
                SchoolLessonReportContent(model: model, learnerName: learnerName, schoolWorkspace: schoolWorkspace,
                    observationClient: client.agenda.observationClient)
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
    let observationClient: SchoolObservationClient
    @State private var showComplete = false
    @State private var showReloadConfirmation = false
    @State private var observationRoute: ObservationRoute?

    private struct ObservationRoute: Identifiable {
        let id = UUID()
        let client: SchoolObservationClient
        let lessonID: UUID
    }

    private var isCompleted: Bool { model.lesson?.status == "COMPLETED" }
    private var isPlanned: Bool { model.lesson?.status == "PLANNED" }
    /// L’élève ne reçoit que ce qui lui est partagé ; le moniteur voit tout, y compris ce qu’il garde pour lui.
    private var readsLesson: Bool { model.isAuthor || model.isOwnLearner }

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
            if let wish = model.wish { wishSection(wish) }
            if let account = model.account {
                Section {
                    LabeledContent("À payer") { Text(SchoolCatalogFormatting.price(account.balanceCents)).monospacedDigit() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isAuthor && isPlanned { completeBar }
            else if model.isAuthor && isCompleted && model.draft != nil { saveBar }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { if model.draftChanged { showReloadConfirmation = true } else { Task { await model.load() } } } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy || model.isLoading)
            }
        }
        .tint(DrivyTheme.accent)
        .confirmationDialog("Recharger et perdre la saisie ?", isPresented: $showReloadConfirmation, titleVisibility: .visible) {
            Button("Recharger", role: .destructive) { Task { await model.load() } }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $showComplete) { SchoolLessonCompletionSheet(model: model) }
        .sheet(item: $observationRoute, onDismiss: { Task { await model.load() } }) { route in
            SchoolObservationEntryView(client: route.client, schoolWorkspace: schoolWorkspace, lessonID: route.lessonID)
        }
    }

    // MARK: En-tête

    private var headerSection: some View {
        Section {
            HStack(alignment: .center, spacing: DrivySpacing.m) {
                DrivyAvatar(name: learnerName, size: 52)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(learnerName).font(.drivyTitle).fixedSize(horizontal: false, vertical: true)
                    if let lesson = model.lesson, let date = lesson.startsAt {
                        Text(SchoolPlanningFormat.instant(date, zone: lesson.timeZone)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Un badge seulement pour l’inhabituel.
            if let lesson = model.lesson, ["CANCELLED", "NO_SHOW"].contains(lesson.status) { lesson.drivyState.badge }
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
                Button("Modifier les observations", systemImage: "square.and.pencil") {
                    observationRoute = ObservationRoute(client: observationClient, lessonID: model.lessonID)
                }
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
                ForEach(model.competencies) { competency in
                    DisclosureGroup {
                        Picker("Niveau", selection: Binding(get: { model.observations.first(where: { $0.id == competency.id })?.level ?? "" }, set: { value in
                            if value.isEmpty { model.observations.removeAll { $0.id == competency.id } }
                            else if let index = model.observations.firstIndex(where: { $0.id == competency.id }) { model.observations[index].level = value }
                            else { model.observations.append(SchoolReportObservation(competencyId: competency.id, level: value, context: "")) }
                        })) {
                            Text("Non observé").tag("")
                            Text("En découverte").tag("DISCOVERING")
                            Text("Avec accompagnement").tag("GUIDED")
                            Text("En autonomie").tag("INDEPENDENT")
                        }
                        if model.observations.contains(where: { $0.id == competency.id }) {
                            TextField("Situation", text: Binding(get: { model.observations.first(where: { $0.id == competency.id })?.context ?? "" }, set: { value in
                                if let index = model.observations.firstIndex(where: { $0.id == competency.id }) { model.observations[index].context = value }
                            }), axis: .vertical)
                        }
                    } label: {
                        HStack {
                            Text(competency.label).foregroundStyle(DrivyTheme.text)
                            Spacer(minLength: DrivySpacing.s)
                            if let observed = model.observations.first(where: { $0.id == competency.id }) {
                                Text(observed.levelLabel).font(.caption).foregroundStyle(DrivyTheme.accent)
                            }
                        }
                    }
                    .disabled(!model.canMutate)
                }
            } header: { Text("Compétences") }
        }
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
                    TextField("Objectif \(index + 1)", text: $model.goals[index].label, axis: .vertical)
                    Button(role: .destructive) { model.goals.remove(at: index) } label: {
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
                .disabled(!model.canMutate || !model.preparationValid || !preparationChanged)
        } header: { Text("Objectifs") }
    }
    private var preparationChanged: Bool {
        guard let preparation = model.preparation else { return false }
        return model.goals != preparation.goals || model.administrativeNote != (preparation.administrativeCheckNote ?? "")
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
            } else if !wish.text.isEmpty {
                Text(wish.text)
            }
        } header: { Text(model.isOwnLearner ? "Mon souhait" : "Souhait de l’élève") }
    }

    // MARK: Actions

    private var completeBar: some View {
        DrivyStickyActionBar {
            Button { showComplete = true } label: { Label("Terminer la leçon", systemImage: "checkmark.circle") }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.canMutate)
        }
    }

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

private struct SchoolLessonCompletionSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var reason = ""
    @State private var captureStopped = false

    init(model: SchoolLessonReportWorkspace) {
        self.model = model
        // Préremplir avec l’horaire prévu, sans jamais proposer une fin à venir.
        let now = Date()
        let plannedEnd = min(model.lesson?.endsAt ?? now, now)
        let plannedStart = min(model.lesson?.startsAt ?? plannedEnd.addingTimeInterval(-3000), plannedEnd.addingTimeInterval(-60))
        _start = State(initialValue: plannedStart); _end = State(initialValue: plannedEnd)
    }
    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        model.canMutate && captureStopped && end > start && end <= Date().addingTimeInterval(300)
            && (!model.completionNeedsReason || !trimmedReason.isEmpty) && reason.unicodeScalars.count <= 1_000
    }
    private var hint: String? {
        if end <= start { return "La fin doit suivre le début." }
        if end > Date().addingTimeInterval(300) { return "La fin ne peut pas être à venir." }
        if !captureStopped { return "Arrêtez d’abord le trajet." }
        if model.completionNeedsReason && trimmedReason.isEmpty { return "Précisez la situation du permis." }
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Début", selection: $start)
                    DatePicker("Fin", selection: $end)
                    Toggle("Aucun trajet en cours", isOn: $captureStopped)
                }
                if model.completionNeedsReason {
                    Section {
                        TextField("Permis non vérifié : précisez", text: $reason, axis: .vertical).lineLimit(2...6)
                    } header: { Text("Permis") }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    else if let hint { DrivyActionNote(text: hint) }
                    Button {
                        Task { if await model.complete(start: start, end: end, reason: reason, localCaptureStopped: captureStopped) { dismiss() } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isBusy { ProgressView() }
                            Label("Terminer la leçon", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!valid)
                }
            }
            .navigationTitle("Terminer").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
        }
        .tint(DrivyTheme.accent)
    }
}
