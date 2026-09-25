import SwiftUI

/// Entrée injectable ; la leçon et les accès sont relus avant d'afficher le contenu privé.
struct SchoolObservationEntryView: View {
    let client: SchoolObservationClient
    @Bindable var schoolWorkspace: SchoolWorkspace
    let lessonID: UUID
    @State private var model: SchoolObservationWorkspace?
    @Environment(\.dismiss) private var dismiss

    private var scope: SchoolCommandScope? {
        guard let person = schoolWorkspace.person, let membership = schoolWorkspace.membership else { return nil }
        return client.agenda.scope(person: person, membership: membership)
    }
    private var scopeKey: String {
        "\(scope?.personID.uuidString ?? ""):\(scope?.membershipID.uuidString ?? ""):\(scope?.accessEpoch ?? 0):\(lessonID)"
    }
    var body: some View {
        Group {
            if let model, model.scope == scope {
                SchoolObservationView(model: model, schoolWorkspace: schoolWorkspace)
            } else {
                NavigationStack {
                    ProgressView("Vérification de la leçon…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DrivyTheme.surface)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
                }
            }
        }
        .task(id: scopeKey) {
            model?.invalidate(); model = nil
            guard let scope else { dismiss(); return }
            model = SchoolObservationWorkspace(scope: scope, lessonID: lessonID, client: client)
        }
    }
}

struct SchoolObservationView: View {
    @Bindable var model: SchoolObservationWorkspace
    @Bindable var schoolWorkspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var route: ObservationRoute?

    private enum ObservationRoute: Identifiable {
        case edit(SchoolObservationEditor)
        case remove(SchoolObservation)
        case pending(PendingSchoolCommand)
        var id: UUID {
            switch self { case .edit(let value): value.id; case .remove(let value): value.id; case .pending(let value): value.id }
        }
    }
    private var scopeMatches: Bool {
        model.scope.personID == schoolWorkspace.person?.personId
            && model.scope.schoolID == schoolWorkspace.membership?.schoolId
            && model.scope.membershipID == schoolWorkspace.membership?.membershipId
            && model.scope.accessEpoch == schoolWorkspace.membership?.accessEpoch
            && schoolWorkspace.membership?.roles.contains("INSTRUCTOR") == true
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    heading
                    feedback
                    if model.loaded {
                        if model.canAdd { actions }
                        observationList
                    }
                    if let pending = model.pending { pendingCard(pending) }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Observations").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.load() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                        .disabled(model.isBusy || model.isLoading || model.accessRevoked)
                }
            }
            .task { await model.load() }
            .sheet(item: $route) { route in
                switch route {
                case .edit(let editor): SchoolObservationComposer(model: model, editor: editor)
                case .remove(let observation): SchoolObservationRemoval(model: model, observation: observation)
                case .pending(let command): SchoolObservationPendingView(model: model, command: command)
                }
            }
            .onChange(of: scopeMatches) { _, matches in
                if !matches { route = nil; model.invalidate(); dismiss() }
            }
            .onChange(of: model.accessRevoked) { _, revoked in if revoked { route = nil } }
        }
        .tint(DrivyTheme.accent).foregroundStyle(DrivyTheme.text)
        .interactiveDismissDisabled(model.isBusy)
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyStatusBadge(title: "Carnet privé", symbol: "lock.fill")
            Text(model.learnerName.isEmpty ? "Pendant la leçon" : model.learnerName)
                .font(.drivyScreenTitle).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Gardez un repère, puis précisez ce qui mérite d’être repris. Ces observations ne sont pas partagées avec l’élève.")
                .font(.subheadline).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private var feedback: some View {
        if model.isLoading { ProgressView("Lecture du carnet…").frame(maxWidth: .infinity, alignment: .leading) }
        if let error = model.errorMessage {
            SchoolErrorNotice(message: error, retry: model.accessRevoked || model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
        }
        if let message = model.confirmation { DrivyInlineMessage(text: message) }
        if let message = model.competenciesMessage { DrivyInlineMessage(text: message, tone: .neutral) }
        if let message = model.draftMessage { DrivyInlineMessage(text: message, tone: .neutral) }
    }
    private var actions: some View {
        VStack(spacing: DrivySpacing.s) {
            if model.lesson?.status == "PLANNED" {
                Button {
                    if let editor = model.begin(marker: true) { route = .edit(editor) }
                } label: { Label("Garder un repère maintenant", systemImage: "bookmark") }
                    .buttonStyle(DrivyPrimaryButtonStyle()).accessibilityIdentifier("school-observation-marker")
                if !model.competencies.isEmpty {
                    Button {
                        if let editor = model.begin(marker: false) { route = .edit(editor) }
                    } label: { Label("Observer une compétence", systemImage: "eye") }
                        .buttonStyle(DrivySecondaryButtonStyle()).accessibilityIdentifier("school-observation-qualified")
                }
                Text("L’heure est gardée dès votre appui. Aucune position GPS n’est ajoutée.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    if let editor = model.begin(marker: false) { route = .edit(editor) }
                } label: { Label("Ajouter une note de relecture", systemImage: "square.and.pencil") }
                    .buttonStyle(DrivyPrimaryButtonStyle())
            }
        }
    }
    private var observationList: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Repères et observations").font(.drivySection).accessibilityAddTraits(.isHeader)
                Spacer(minLength: DrivySpacing.xs)
                Text(model.observations.count.formatted()).font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                    .accessibilityLabel("\(model.observations.count) au total")
            }
            if model.observations.isEmpty {
                DrivyEmptyState(title: "Le carnet est encore vide",
                    message: "Un repère fonctionne aussi sans enregistrer le trajet.", symbol: "text.bubble")
            } else {
                ForEach(model.observations.reversed()) { observation in observationCard(observation) }
            }
        }
    }
    private func observationCard(_ observation: SchoolObservation) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                HStack(alignment: .top, spacing: DrivySpacing.s) {
                    Image(systemName: observation.isMarker ? "bookmark.fill" : "text.bubble.fill")
                        .font(.title3).foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(model.competencyLabel(observation.competencyId) ?? (observation.isMarker ? "Repère" : "Note de relecture"))
                            .font(.headline)
                        if let time = model.timeLabel(observation.observedAt) {
                            Text(time).font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let status = observation.statusLabel {
                    DrivyStatusBadge(title: status, symbol: statusSymbol(observation.eventStatus), tone: statusTone(observation.eventStatus))
                }
                Text(observation.text).fixedSize(horizontal: false, vertical: true)
                if observation.hasPosition {
                    Label("Position déjà enregistrée par l’école", systemImage: "mappin")
                        .font(.caption).foregroundStyle(DrivyTheme.muted)
                }
                HStack(spacing: DrivySpacing.l) {
                    Button(observation.isMarker ? "Préciser" : "Modifier") {
                        if let editor = model.edit(observation) { route = .edit(editor) }
                    }.frame(minHeight: 44).disabled(!model.canMutate)
                    Spacer(minLength: 0)
                    Button("Retirer", role: .destructive) { route = .remove(observation) }
                        .frame(minHeight: 44).disabled(!model.canMutate)
                }.font(.subheadline.weight(.semibold))
            }
        }.accessibilityIdentifier("school-observation-\(observation.id.uuidString)")
    }
    private func pendingCard(_ command: PendingSchoolCommand) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Label("Enregistrement à vérifier", systemImage: "clock.badge.exclamationmark").font(.headline)
                    .foregroundStyle(DrivyTheme.warning)
                Text(model.pendingBelongsHere ? "La demande est conservée sur cet appareil. Vérifiez son résultat avant une autre modification." : model.pendingText)
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                if model.pendingBelongsHere {
                    Button("Relire la demande") { route = .pending(command) }.frame(minHeight: 44)
                }
            }
        }
    }
    /// Same symbols and tones as the local signalement tiles (ObservationStatus).
    private func statusTone(_ raw: String?) -> DrivyTone {
        switch raw { case "POSITIVE": .success; case "ATTENTION": .warning; default: .danger }
    }
    private func statusSymbol(_ raw: String?) -> String {
        switch raw { case "POSITIVE": "checkmark"; case "ATTENTION": "exclamationmark"; default: "xmark" }
    }
}

private struct SchoolObservationComposer: View {
    @Bindable var model: SchoolObservationWorkspace
    let editor: SchoolObservationEditor
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var marker: Bool
    @State private var competencyID: UUID?
    @State private var status: SchoolObservationStatus?
    @State private var confirmsDiscard = false

    init(model: SchoolObservationWorkspace, editor: SchoolObservationEditor) {
        self.model = model; self.editor = editor
        _text = State(initialValue: editor.original?.text ?? "")
        _marker = State(initialValue: editor.marker)
        _competencyID = State(initialValue: editor.original?.competencyId)
        _status = State(initialValue: editor.original?.eventStatus.flatMap(SchoolObservationStatus.init(rawValue:)))
    }
    private var valid: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || emptyNoteLabel != nil) && text.unicodeScalars.count <= 4_000
            && (editor.origin != "LIVE" || marker || (competencyID != nil && status != nil))
    }
    private var emptyNoteLabel: String? {
        guard editor.origin == "LIVE" else { return nil }
        if marker { return "Moment à revoir" }
        return model.competencies.first(where: { $0.id == competencyID })?.label
    }
    private var changed: Bool {
        text != (editor.original?.text ?? "") || marker != editor.marker || competencyID != editor.original?.competencyId
            || status?.rawValue != editor.original?.eventStatus
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let label = model.timeLabel(editor.observedAt) { Label(label, systemImage: "clock").font(.subheadline.monospacedDigit()) }
                    Label(editor.original?.hasPosition == true ? "La position enregistrée et l’instant sont conservés." : "Observation privée, sans position GPS ajoutée.",
                          systemImage: "lock.fill")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if editor.origin == "LIVE" {
                    Section {
                        Toggle("Repère simple, à préciser ensuite", isOn: $marker)
                    } footer: { Text("Un repère garde l’instant ; vous pourrez choisir la compétence plus tard.") }
                }
                if !marker { qualification }
                Section {
                    TextField(editor.origin == "LIVE" ? "Précision facultative" : "Ce que vous souhaitez retenir", text: $text, axis: .vertical)
                        .lineLimit(4...10).accessibilityIdentifier("school-observation-text")
                    Text("\(text.unicodeScalars.count) / 4 000").font(.caption.monospacedDigit())
                        .foregroundStyle(text.unicodeScalars.count > 4_000 ? DrivyTheme.danger : DrivyTheme.muted)
                } header: { Text(editor.origin == "LIVE" ? "Précision facultative" : "Observation") }
                  footer: {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let label = emptyNoteLabel {
                        Text("Libellé conservé sans commentaire : « \(label) ».")
                    }
                  }
                if model.pending != nil {
                    Section {
                        Label("La demande est conservée. Fermez cette saisie pour vérifier son résultat dans le carnet.", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    else if let hint = saveHint { DrivyActionNote(text: hint) }
                    Button {
                        Task { if await model.save(editor, text: text, marker: marker, competencyID: competencyID, status: status) { dismiss() } }
                    } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isBusy { ProgressView() }
                            Text(model.isBusy ? "Enregistrement…" : "Enregistrer dans le carnet")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!valid || !model.canMutate)
                    .accessibilityIdentifier("school-observation-save")
                }
            }
            .navigationTitle(editor.original == nil ? "Garder une observation" : "Préciser l’observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if changed && model.pending == nil { confirmsDiscard = true } else { dismiss() } }.disabled(model.isBusy)
                }
            }
            .confirmationDialog("Quitter cette saisie ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Abandonner la saisie", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) { }
            }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(changed || model.isBusy)
    }
    /// Explains a disabled save. Mirrors `valid`; never a second rule.
    private var saveHint: String? {
        if model.isBusy || valid && model.canMutate { return nil }
        if text.unicodeScalars.count > 4_000 { return "Le texte est limité à 4 000 caractères." }
        if editor.origin == "LIVE" && !marker && competencyID == nil { return "Choisissez une compétence, ou gardez un repère simple." }
        if editor.origin == "LIVE" && !marker && status == nil { return "Choisissez un constat pour cette compétence." }
        if !valid { return "Écrivez ce que vous souhaitez retenir." }
        return "Enregistrement indisponible pour l’instant. Vérifiez le carnet."
    }
    private var qualification: some View {
        Section {
            Picker("Compétence", selection: $competencyID) {
                Text(editor.origin == "LIVE" ? "Choisir une compétence" : "Sans compétence associée").tag(Optional<UUID>.none)
                ForEach(model.competencies) { value in Text(value.label).tag(Optional(value.id)) }
                if let id = editor.original?.competencyId, !model.competencies.contains(where: { $0.id == id }) {
                    Text("Compétence déjà associée").tag(Optional(id))
                }
            }
            if editor.origin == "LIVE" {
                ForEach(SchoolObservationStatus.allCases) { value in
                    Button { status = value } label: {
                        HStack(spacing: DrivySpacing.s) {
                            Text(value.label).foregroundStyle(DrivyTheme.text)
                            Spacer(minLength: DrivySpacing.xs)
                            DrivySelectionMark(isSelected: status == value)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(status == value ? [.isSelected] : [])
                }
            }
        } header: { Text("Compétence et constat") }
    }
}

private struct SchoolObservationRemoval: View {
    @Bindable var model: SchoolObservationWorkspace
    let observation: SchoolObservation
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Observation concernée") { Text(observation.text).fixedSize(horizontal: false, vertical: true) }
                Section {
                    TextField("Pourquoi retirer cette observation ?", text: $reason, axis: .vertical).lineLimit(3...6)
                    Toggle("Je confirme son retrait du carnet privé", isOn: $acknowledged)
                } header: { Text("Motif du retrait") }
                footer: { Text("Ce retrait ne modifie pas un bilan déjà partagé.") }
                if model.pending != nil {
                    Section {
                        Label("La demande est conservée. Retrouvez-la dans le carnet pour vérifier le résultat.", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let error = model.errorMessage { DrivyActionNote(text: error, isError: true) }
                    else if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { DrivyActionNote(text: "Indiquez le motif du retrait.") }
                    else if reason.unicodeScalars.count > 1_000 { DrivyActionNote(text: "Le motif est limité à 1 000 caractères.") }
                    else if !acknowledged { DrivyActionNote(text: "Confirmez le retrait pour continuer.") }
                    Button(role: .destructive) { Task { if await model.remove(observation, reason: reason) { dismiss() } } } label: {
                        HStack(spacing: DrivySpacing.xs) {
                            if model.isBusy { ProgressView() }
                            Text(model.isBusy ? "Retrait en cours…" : "Retirer du carnet")
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(!acknowledged || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.unicodeScalars.count > 1_000 || !model.canMutate)
                }
            }
            .navigationTitle("Retirer l’observation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(model.isBusy) }
            }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }
}

private struct SchoolObservationPendingView: View {
    @Bindable var model: SchoolObservationWorkspace
    let command: PendingSchoolCommand
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(model.pendingText).fixedSize(horizontal: false, vertical: true) }
                Section {
                    Text("Référence : \(command.id.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                    if command.scope != model.scope {
                        Label("Vos droits ont changé depuis cette demande. Elle reste conservée et ne peut pas être renvoyée avec ces nouveaux accès.", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                    } else {
                        Button("Vérifier auprès de l’école") { Task { await model.verifyPending(); if model.pending == nil { dismiss() } } }
                            .disabled(!model.canRetry)
                        Toggle("J’ai relu cette demande", isOn: $acknowledged)
                        Button("Renvoyer exactement cette demande") {
                            Task { if await model.retryPending() { dismiss() } }
                        }.disabled(!acknowledged || !model.canRetry)
                    }
                } footer: { Text("Le contenu et la référence restent identiques. Une absence de réponse ne signifie pas que l’école a refusé la demande.") }
                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(DrivyTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Demande conservée").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }
}
