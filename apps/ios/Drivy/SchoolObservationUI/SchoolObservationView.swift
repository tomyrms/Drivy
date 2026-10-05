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
                    DrivySkeletonRows(count: 4)
                        .drivySkeleton("Vérification de la leçon…")
                        .drivyPageContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(DrivyTheme.surface)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
                }
            }
        }
        .task(id: scopeKey) {
            model?.invalidate(); model = nil
            // Portée momentanément illisible (compte en relecture) : la feuille attend, elle ne se ferme pas.
            guard let scope else { return }
            model = SchoolObservationWorkspace(scope: scope, lessonID: lessonID, client: client)
        }
    }
}

struct SchoolObservationView: View {
    @Bindable var model: SchoolObservationWorkspace
    @Bindable var schoolWorkspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var route: ObservationRoute?
    @State private var observationNotice: ObservationNotice?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ObservationNotice: Identifiable {
        let receipt: SchoolLiveObservationReceipt
        let recorder: SchoolLiveObservationRecorder
        var id: UUID { receipt.id }
    }

    private enum ObservationRoute: Identifiable {
        case signal(SignalRoute)
        case edit(SchoolObservationEditor)
        case remove(SchoolObservation)
        case pending(PendingSchoolCommand)
        var id: UUID {
            switch self { case .signal(let value): value.id; case .edit(let value): value.id; case .remove(let value): value.id; case .pending(let value): value.id }
        }
    }
    private struct SignalRoute: Identifiable {
        let id = UUID()
        let observedAt = Date()
        let recorder: SchoolLiveObservationRecorder
    }
    private var scopeMatches: Bool {
        // Compte en cours de relecture : rien à comparer, ce n’est pas un retrait de droits.
        guard schoolWorkspace.person != nil, schoolWorkspace.membership != nil else { return true }
        return model.scope.personID == schoolWorkspace.person?.personId
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
                    if model.loaded || model.lesson != nil {
                        observationList
                    }
                    // Réservée à une demande restée en attente : un envoi normal, en cours, ne la montre pas.
                    if let pending = model.pending, model.pendingAwaitsReview { pendingCard(pending) }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let notice = observationNotice {
                        SchoolObservationUndoBanner(recorder: notice.recorder, receipt: notice.receipt) {
                            guard observationNotice?.id == notice.id else { return }
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { observationNotice = nil }
                        }
                        .padding(.horizontal, DrivySpacing.m)
                        .padding(.vertical, DrivySpacing.xs)
                    }
                    if model.acceptsAdd { DrivyStickyActionBar { actions } }
                }
                .background(DrivyTheme.surface)
            }
            .navigationTitle("Observations").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Relecture ou envoi déjà en cours : l’appui est ignoré, le bouton ne se grise pas.
                        guard !model.isBusy, !model.isLoading else { return }
                        Task { await model.load() }
                    } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                        .disabled(model.accessRevoked)
                }
            }
            .task { await model.load() }
            .sheet(item: $route, onDismiss: { Task { await model.load() } }) { route in
                switch route {
                case .signal(let value):
                    SchoolLiveObservationSheet(recorder: value.recorder, observedAt: value.observedAt,
                        onRecorded: { showObservationNotice(value.recorder) })
                case .edit(let editor): SchoolObservationComposer(model: model, editor: editor)
                case .remove(let observation): SchoolObservationRemoval(model: model, observation: observation)
                case .pending(let command): SchoolObservationPendingView(model: model, command: command)
                }
            }
            .onChange(of: scopeMatches) { _, matches in
                if !matches { stopObservationFeedback(); route = nil; model.invalidate(); dismiss() }
            }
            .onChange(of: model.accessRevoked) { _, revoked in
                if revoked { stopObservationFeedback(); route = nil }
            }
        }
        .tint(DrivyTheme.accent).foregroundStyle(DrivyTheme.text)
        .interactiveDismissDisabled(model.isBusy)
        .sensoryFeedback(.success, trigger: observationNotice?.id) { _, newValue in newValue != nil }
    }

    private func showObservationNotice(_ recorder: SchoolLiveObservationRecorder) {
        guard let receipt = recorder.lastAdded else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            observationNotice = .init(receipt: receipt, recorder: recorder)
        }
    }

    private func stopObservationFeedback() {
        if let route, case .signal(let value) = route { value.recorder.stop() }
        observationNotice?.recorder.stop()
        observationNotice = nil
    }
    /// Rappel de l’élève sur une ligne, comme sur les pages secondaires du dossier : la fiche de leçon l’a déjà
    /// présenté et le titre dit où l’on est. Rien avant la lecture, donc aucun titre qui change sous les yeux.
    /// Partage automatique (28 septembre 2026) : l’élève voit les observations d’une leçon terminée,
    /// sauf celles que le moniteur garde pour lui depuis l’écran de la leçon.
    @ViewBuilder private var heading: some View {
        if !model.learnerName.isEmpty {
            DrivyLearnerIdentity(name: model.learnerName, variant: .inline)
        }
    }
    @ViewBuilder private var feedback: some View {
        if model.isLoading && model.lesson == nil {
            DrivySkeletonRows(count: 4)
                .drivySkeleton("Chargement des observations…")
        }
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
                // Même bouton, même symbole que « Signaler » sur le trajet en cours : une action, une apparence.
                Button {
                    if let recorder = model.liveRecorder() { route = .signal(.init(recorder: recorder)) }
                } label: { Label("Signaler", systemImage: "text.bubble.fill") }
                    .buttonStyle(DrivyPrimaryButtonStyle(size: .field)).accessibilityIdentifier("school-observation-signal")
            } else {
                Button("Ajouter une observation") {
                    if let editor = model.begin(marker: false) { route = .edit(editor) }
                }
                    .buttonStyle(DrivyPrimaryButtonStyle())
            }
        }
    }
    /// Liste sur page de lecture : lignes séparées par un filet (DrivyRowGroup), pas une carte par
    /// observation ; même pastille de statut (symbole, libellé, ton) que le replay et le signalement.
    private var observationList: some View {
        DrivyRowGroup {
            if model.observations.isEmpty {
                DrivyEmptyState(title: "Aucune observation", symbol: "text.bubble")
            } else {
                ForEach(model.observations.reversed()) { observation in observationRow(observation) }
            }
        }
    }
    private func observationRow(_ observation: SchoolObservation) -> some View {
        let meta = [model.timeLabel(observation.observedAt), observation.hasPosition ? "Sur le trajet" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: DrivySpacing.s) {
            DrivyObservationSummary(observation: observation, detail: meta)
            Menu {
                Button(observation.isMarker ? "Préciser" : "Modifier") {
                    if let editor = model.edit(observation) { route = .edit(editor) }
                }
                Button("Retirer", role: .destructive) { route = .remove(observation) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(DrivyTheme.muted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!model.acceptsChanges)
            .accessibilityLabel("Actions pour l’observation : \(observation.text)")
        }
        .padding(.vertical, DrivySpacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("school-observation-\(observation.id.uuidString)")
    }
    private func pendingCard(_ command: PendingSchoolCommand) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Label("Demande à vérifier", systemImage: "clock.arrow.circlepath").font(.headline)
                    .foregroundStyle(DrivyTheme.warning)
                Text(model.pendingBelongsHere ? "La demande est conservée sur cet appareil. Vérifie son résultat avant une autre modification." : model.pendingText)
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if model.pendingBelongsHere {
                    Button("Relire la demande") { route = .pending(command) }
                        .buttonStyle(DrivySecondaryButtonStyle())
                }
            }
        }
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
        return model.competencies.first(where: { $0.id == competencyID })?.displayLabel
    }
    private var changed: Bool {
        text != (editor.original?.text ?? "") || marker != editor.marker || competencyID != editor.original?.competencyId
            || status?.rawValue != editor.original?.eventStatus
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(contextLine)
                        .font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                    .drivyFormRows()
                if editor.origin == "LIVE" {
                    Section {
                        Toggle("Repère simple, à préciser ensuite", isOn: $marker)
                    }
                        .drivyFormRows()
                }
                if !marker { qualification }
                Section {
                    TextField(editor.origin == "LIVE" ? "Précision facultative" : "Ce que tu souhaites retenir", text: $text, axis: .vertical)
                        .lineLimit(4...10).accessibilityIdentifier("school-observation-text")
                    Text("\(text.unicodeScalars.count) / 4 000").font(.caption.monospacedDigit())
                        .foregroundStyle(text.unicodeScalars.count > 4_000 ? DrivyTheme.danger : DrivyTheme.muted)
                } header: { Text(editor.origin == "LIVE" ? "Précision facultative" : "Observation").drivyFormSectionHeader() }
                  footer: {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let label = emptyNoteLabel {
                        Text("Libellé conservé sans commentaire : « \(label) ».")
                    }
                  }
                    .drivyFormRows()
                if model.pendingAwaitsReview {
                    Section {
                        Label("La demande est conservée. Ferme cette saisie pour vérifier son résultat dans les observations.", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .drivyFormRows()
                }
            }
            .disabled(model.isBusy || model.pendingAwaitsReview)
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let message = model.errorMessage { DrivyActionNote(text: message, isError: true) }
                    else if let hint = saveHint { DrivyActionNote(text: hint) }
                    Button {
                        Task { if await model.save(editor, text: text, marker: marker, competencyID: competencyID, status: status) { dismiss() } }
                    } label: {
                        DrivyBusyLabel(title: "Enregistrer l’observation", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!valid || !model.canMutate)
                    .accessibilityIdentifier("school-observation-save")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if changed && !model.pendingAwaitsReview { confirmsDiscard = true } else { dismiss() } }.disabled(model.isBusy)
                }
            }
            .alert("Quitter sans enregistrer ?", isPresented: $confirmsDiscard) {
                Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) { }
            }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(changed || model.isBusy)
    }
    /// Le titre reprend le verbe du geste qui a ouvert la feuille : ajouter, préciser un repère, modifier.
    private var title: String {
        guard editor.original != nil else { return "Nouvelle observation" }
        return editor.marker ? "Préciser l’observation" : "Modifier l’observation"
    }
    /// Moment et position de l’observation, sur une seule ligne de contexte.
    private var contextLine: String {
        let parts: [String?] = [model.timeLabel(editor.observedAt),
                                editor.original?.hasPosition == true ? "Sur le trajet" : "Sans position"]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
    /// Explains a disabled save. Mirrors `valid`; never a second rule.
    private var saveHint: String? {
        if model.isBusy || model.isLoading || valid && model.canMutate { return nil }
        if text.unicodeScalars.count > 4_000 { return "Le texte est limité à 4 000 caractères." }
        if editor.origin == "LIVE" && !marker && competencyID == nil { return "Choisis une compétence, ou garde un repère simple." }
        if editor.origin == "LIVE" && !marker && status == nil { return "Choisis une appréciation pour cette compétence." }
        if !valid { return "Écris ce que tu souhaites retenir." }
        return "Enregistrement indisponible pour l’instant. Vérifie les observations."
    }
    private var qualification: some View {
        Section {
            Picker("Compétence", selection: $competencyID) {
                Text(editor.origin == "LIVE" ? "Choisir une compétence" : "Sans compétence associée").tag(Optional<UUID>.none)
                ForEach(model.competencies) { value in Text(value.displayLabel).tag(Optional(value.id)) }
                if let id = editor.original?.competencyId, !model.competencies.contains(where: { $0.id == id }) {
                    Text("Compétence déjà associée").tag(Optional(id))
                }
            }
            if editor.origin == "LIVE" {
                ForEach(SchoolObservationStatus.allCases) { value in
                    Button { status = value } label: {
                        HStack(spacing: DrivySpacing.s) {
                            // Même pastille que les tuiles du signalement : le symbole et le mot portent l’état.
                            Image(systemName: value.symbol)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(value.fieldTone.foreground)
                                .frame(width: 32, height: 32)
                                .background(value.fieldTone.background, in: Circle())
                                .accessibilityHidden(true)
                            Text(value.label).foregroundStyle(DrivyTheme.text)
                            Spacer(minLength: DrivySpacing.xs)
                            DrivySelectionMark(isSelected: status == value)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(status == value ? [.isSelected] : [])
                }
            }
        } header: { Text("Compétence et appréciation").drivyFormSectionHeader() }
            .drivyFormRows()
    }
}

private struct SchoolObservationRemoval: View {
    @Bindable var model: SchoolObservationWorkspace
    let observation: SchoolObservation
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var acknowledged = false
    @State private var confirmsDiscard = false
    private var hasChanges: Bool { !reason.isEmpty || acknowledged }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(observation.text).fixedSize(horizontal: false, vertical: true) } header: { Text("Observation concernée").drivyFormSectionHeader() }
                    .drivyFormRows()
                Section {
                    TextField("Pourquoi retirer cette observation ?", text: $reason, axis: .vertical).lineLimit(3...6)
                    Toggle("Je confirme son retrait", isOn: $acknowledged)
                } header: { Text("Motif du retrait").drivyFormSectionHeader() }
                footer: { Text("Ce retrait ne modifie pas un bilan déjà partagé.") }
                    .drivyFormRows()
                if model.pendingAwaitsReview {
                    Section {
                        Label("La demande est conservée. Retrouve-la dans les observations pour vérifier le résultat.", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline).foregroundStyle(DrivyTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .drivyFormRows()
                }
            }
            .disabled(model.isBusy || model.pendingAwaitsReview)
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DrivyStickyActionBar {
                    if let error = model.errorMessage { DrivyActionNote(text: error, isError: true) }
                    else if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { DrivyActionNote(text: "Indique le motif du retrait.") }
                    else if reason.unicodeScalars.count > 1_000 { DrivyActionNote(text: "Le motif est limité à 1 000 caractères.") }
                    else if !acknowledged { DrivyActionNote(text: "Confirme le retrait pour continuer.") }
                    Button(role: .destructive) { Task { if await model.remove(observation, reason: reason) { dismiss() } } } label: {
                        DrivyBusyLabel(title: "Retirer l’observation", busyTitle: "Retrait en cours…", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyDangerButtonStyle())
                    .disabled(!acknowledged || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.unicodeScalars.count > 1_000 || !model.canMutate)
                }
            }
            .navigationTitle("Retirer l’observation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if hasChanges && !model.pendingAwaitsReview { confirmsDiscard = true } else { dismiss() }
                    }.disabled(model.isBusy)
                }
            }
            .alert("Quitter sans enregistrer ?", isPresented: $confirmsDiscard) {
                Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) { }
            }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(hasChanges || model.isBusy)
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
                    .drivyFormRows()
                Section {
                    Text("Référence : \(command.id.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
                    if command.scope != model.scope {
                        Label("Tes droits ont changé depuis cette demande. Elle reste conservée et ne peut pas être renvoyée avec ces nouveaux accès.", systemImage: "exclamationmark.triangle.fill")
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
                    .drivyFormRows()
                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(DrivyTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .drivyFormRows()
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Demande conservée").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
        }.tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }
}

private extension SchoolObservationStatus {
    /// Mêmes teintes que les tuiles du signalement et le replay.
    var fieldTone: DrivyTone {
        switch self { case .positive: .success; case .attention: .warning; case .toWorkOn: .danger }
    }
}
