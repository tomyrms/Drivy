import SwiftUI

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
        return model.draftChanged || (model.preparation.map { model.goals != $0.goals || model.administrativeNote != ($0.administrativeCheckNote ?? "") } ?? false)
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
                ContentUnavailableView("Sélectionnez votre école", systemImage: "building.2", description: Text("Le bilan est lié à votre compte et à cette école."))
            }
        }
        .navigationTitle(model?.draft != nil ? "Bilan de leçon" : model?.isAuthor == true ? "Préparer la leçon" : "Ma leçon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") {
                    if hasUnsavedChanges { confirmsDiscard = true } else { model?.invalidate(); dismiss() }
                }.disabled(model?.isBusy == true)
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges || model?.isBusy == true)
        .confirmationDialog("Fermer sans enregistrer cette saisie ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Fermer sans enregistrer", role: .destructive) { model?.invalidate(); dismiss() }
            Button("Continuer la saisie", role: .cancel) { }
        }
        .task(id: scopeKey) {
            // A full-height child sheet can make this view appear again. Keep
            // its current editing model until the real account/school changes.
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
    @State private var showPreview = false
    @State private var showReloadConfirmation = false
    @State private var observationRoute: ObservationRoute?
    @State private var observationsWereOpened = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct ObservationRoute: Identifiable {
        let id = UUID()
        let client: SchoolObservationClient
        let lessonID: UUID
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: DrivySpacing.m) {
                    DrivyAvatar(name: learnerName, size: 52)
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(learnerName).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                        if let date = model.lesson?.startsAt, let lesson = model.lesson {
                            Text(SchoolPlanningFormat.instant(date, zone: lesson.timeZone)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                if let lesson = model.lesson {
                    if model.isAuthor && model.draft != nil {
                        DrivyStatusBadge(title: "Brouillon privé", symbol: "lock", tone: .neutral)
                    } else {
                        DrivyStatusBadge(title: lesson.statusLabel, symbol: "steeringwheel",
                            tone: lesson.status == "COMPLETED" ? .success : lesson.status == "PLANNED" ? .accent : .warning)
                    }
                }
                if model.isLoading || model.isBusy { ProgressView(model.isBusy ? "Enregistrement…" : "Chargement…") }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline).foregroundStyle(DrivyTheme.danger)
                        .padding(DrivySpacing.s).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DrivyTheme.dangerSurface, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                        .accessibilityLabel("Erreur : \(error)")
                }
                if let message = model.confirmation {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(DrivyTheme.success)
                        .padding(DrivySpacing.s).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DrivyTheme.successSurface, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
                }
                if let message = model.information { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }.listRowBackground(Color.clear)
            if model.pending != nil { pendingSection }
            if model.isAuthor, !(model.draft?.geoObservationIds?.isEmpty ?? true) {
                Section {
                    Button("Relire les observations privées", systemImage: "list.bullet") {
                        observationRoute = ObservationRoute(client: observationClient, lessonID: model.lessonID)
                    }.disabled(model.isBusy || model.isLoading)
                    if observationsWereOpened {
                        Button("Actualiser les références du brouillon", systemImage: "arrow.clockwise") {
                            showReloadConfirmation = true
                        }.disabled(model.isBusy || model.isLoading)
                    }
                } footer: {
                    Text("Ces observations restent privées. Elles ne sont pas partagées avec le bilan.")
                }
            }
            if model.isAuthor, model.draft != nil { draftSection }
            if let wish = model.wish {
                Section("Souhait pour la prochaine leçon") {
                    if model.isOwnLearner {
                        TextField("Ce que j’aimerais travailler", text: $model.wishText, axis: .vertical).lineLimit(3...8).disabled(!model.canMutate)
                        Text("\(model.wishText.unicodeScalars.count)/500 caractères").font(.caption).foregroundStyle(.secondary)
                        Button("Enregistrer mon souhait") { Task { await model.saveWish() } }
                            .disabled(!model.canMutate || model.wishText.unicodeScalars.count > 500 || model.wishText == wish.text)
                    } else { Text(wish.text.isEmpty ? "L’élève n’a pas encore exprimé de souhait." : wish.text) }
                }
            }
            if model.isAuthor, model.lesson?.status == "PLANNED" { preparationSection }
            if model.isAuthor, model.lesson?.status == "PLANNED" {
                Section {
                    Button { showComplete = true } label: { Label("Constater la leçon réalisée", systemImage: "checkmark.seal") }
                        .disabled(!model.canMutate)
                } footer: { Text("À confirmer après la conduite et l’arrêt de toute collecte. Le constat ouvre le brouillon privé et inscrit le prix convenu au compte de la leçon.") }
            }
            if !model.revisions.isEmpty { publishedSection }
            if let error = model.revisionsError {
                Section("Bilan partagé") {
                    SchoolErrorNotice(message: error, retry: { showReloadConfirmation = true })
                }
            } else if model.revisions.isEmpty, model.lesson != nil, !model.isLoading {
                Section("Bilan partagé") { Text("Aucun bilan n’a encore été publié.").foregroundStyle(.secondary) }
            }
            if let account = model.account {
                Section("Compte de cette leçon") {
                    LabeledContent("Montant dû", value: money(account.chargeCents))
                    LabeledContent("Montant reçu", value: money(account.netReceivedCents))
                    LabeledContent("Solde restant", value: money(account.balanceCents))
                }
            }
            if let progress = model.progress, !progress.items.isEmpty {
                Section("Progression issue des bilans publiés") {
                    ForEach(progress.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.label).font(.headline)
                            Text(level(item.level)).font(.subheadline)
                            Text(item.context)
                            if let date = SchoolLesson.date(item.observedAt) { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isAuthor && model.draft != nil { draftActionBar }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showReloadConfirmation = true } label: { Label("Actualiser les informations", systemImage: "arrow.clockwise") }
                    .disabled(model.isBusy || model.isLoading)
            }
        }
        .confirmationDialog("Recharger les données de l’école ?", isPresented: $showReloadConfirmation, titleVisibility: .visible) {
            Button("Recharger et remplacer la saisie non enregistrée") {
                Task {
                    await model.load()
                    if model.draft != nil && model.errorMessage == nil { observationsWereOpened = false }
                }
            }
            Button("Garder ma saisie", role: .cancel) {}
        }
        .sheet(isPresented: $showComplete) { SchoolLessonCompletionSheet(model: model) }
        .sheet(isPresented: $showPreview) { SchoolReportPreviewSheet(model: model, learnerName: learnerName) }
        .sheet(item: $observationRoute, onDismiss: { observationsWereOpened = true }) { route in
            SchoolObservationEntryView(client: route.client, schoolWorkspace: schoolWorkspace, lessonID: route.lessonID)
        }
    }
    private var pendingSection: some View {
        Section("Confirmation en attente") {
            Text("Cette demande est conservée de façon protégée sur cet appareil. Aucune nouvelle modification n’est envoyée avant sa résolution.")
                .font(.footnote)
            DisclosureGroup("Relire la demande conservée") { Text(model.pendingDescription).textSelection(.enabled) }
            Button("Vérifier son enregistrement") { Task { await model.verifyPending() } }.disabled(model.isBusy || model.isLoading)
            if model.pending?.kind.isReport == true {
                Toggle("J’ai relu cette demande", isOn: Binding(get: { model.pendingReviewed }, set: { if $0 { model.reviewPending() } }))
                Button("Renvoyer exactement cette demande") { Task { await model.retryPending() } }.disabled(!model.canRetry)
            }
        }
    }
    private var preparationSection: some View {
        Section {
            ForEach(model.goals.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Objectif \(index + 1)", text: $model.goals[index].label, axis: .vertical)
                    TextField("Contexte prévu", text: Binding(get: { model.goals[index].context ?? "" }, set: { model.goals[index].context = $0 }), axis: .vertical)
                    Text("Objectif et contexte : 500 caractères maximum chacun.").font(.caption).foregroundStyle(.secondary)
                    Button("Retirer cet objectif", role: .destructive) { model.goals.remove(at: index) }.font(.caption)
                }.disabled(!model.canMutate)
            }
            if model.goals.count < 3 {
                Button("Ajouter un objectif") { model.goals.append(SchoolLessonGoal(label: "", competencyId: nil, context: nil)) }.disabled(!model.canMutate)
            }
            TextField("Note sur les vérifications administratives", text: $model.administrativeNote, axis: .vertical).lineLimit(2...6).disabled(!model.canMutate)
            if let preparation = model.preparation, !preparation.plannedWaypoints.isEmpty {
                Text("\(preparation.plannedWaypoints.count) repère(s) manuel(s) conservé(s) dans cette préparation.").font(.footnote)
            }
            Button("Enregistrer la préparation") { Task { await model.savePreparation() } }.disabled(!model.canMutate || !model.preparationValid)
        } header: { Text("Préparation privée du moniteur") }
        footer: { Text("Jusqu’à trois objectifs. La préparation n’est pas une observation de ce qui a été réalisé.") }
    }
    private var draftSection: some View {
        Section {
            reportField("Travail réalisé", prompt: "Les situations et exercices abordés", text: $model.workedOn)
            reportField("À retenir", prompt: "Ce qui a progressé et ce qui reste à travailler", text: $model.observationText)
            reportField("Prochaine étape", prompt: "L’objectif de la prochaine séance", text: $model.nextStep)
            if !model.competencies.isEmpty {
                Text("Compétences observées").font(.headline).padding(.top, 8)
                ForEach(model.competencies) { competency in
                    DisclosureGroup(competency.label) {
                        Picker("Niveau observé", selection: Binding(get: { model.observations.first(where: { $0.id == competency.id })?.level ?? "" }, set: { value in
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
                            TextField("Contexte de cette observation", text: Binding(get: { model.observations.first(where: { $0.id == competency.id })?.context ?? "" }, set: { value in
                                if let index = model.observations.firstIndex(where: { $0.id == competency.id }) { model.observations[index].context = value }
                            }), axis: .vertical)
                            Text("Contexte requis, 500 caractères maximum.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(!model.canMutate)
                }
            }
            if (model.lesson?.publicationVersion ?? 0) > 0 {
                TextField("Motif de la nouvelle version", text: $model.correctionReason, axis: .vertical).disabled(!model.canMutate)
            }
        } header: { Text("Le bilan") }
        footer: {
            Text(model.draftChanged ? "Des modifications ne sont pas encore enregistrées. Enregistrez-les avant de relire l’aperçu et publier." : "Ce brouillon reste privé. Aucun niveau n’est choisi automatiquement ; seules les compétences observées ont besoin d’un contexte.")
        }
    }
    private var publishedSection: some View {
        Section("Bilans partagés avec l’élève") {
            ForEach(model.revisions) { revision in
                DisclosureGroup {
                    SchoolReportTexts(workedOn: revision.workedOn, observationText: revision.observationText, nextStep: revision.nextStep)
                    ForEach(revision.observations) { observation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.competencies.first(where: { $0.id == observation.id })?.label ?? "Observation de compétence").font(.headline)
                            Text(observation.levelLabel); Text(observation.context)
                        }
                    }
                    if let reason = revision.correctionReason { Text("Motif de correction : \(reason)").font(.footnote) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(revision.id == model.lesson?.currentPublishedRevisionId ? "Bilan actuel" : "Version \(revision.sequence)").font(.headline)
                        if let date = SchoolLesson.date(revision.publishedAt) { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
    private var draftActionBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 10) {
            Text(draftHint).font(.caption).foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            layout {
                Button { Task { await model.saveDraft() } } label: {
                    Label("Enregistrer", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .disabled(!model.canMutate || !model.validTexts || !model.observationsValid || !model.draftChanged)
                Button { showPreview = true } label: { Label("Aperçu élève", systemImage: "eye") }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canPublish)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: 680).frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private var draftHint: String {
        if model.isBusy { return "Enregistrement…" }
        if model.pending != nil { return "Vérifiez la confirmation en attente avant de poursuivre." }
        if !model.canMutate { return "Vérifiez les informations du bilan avant de poursuivre." }
        if !model.validTexts { return "Un des textes dépasse 4 000 caractères." }
        if !model.observationsValid { return "Précisez le contexte de chaque compétence retenue." }
        if model.draftChanged { return "Modifications à enregistrer · le brouillon reste privé." }
        if [model.workedOn, model.observationText, model.nextStep].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Complétez les trois parties pour ouvrir l’aperçu élève."
        }
        if (model.lesson?.publicationVersion ?? 0) > 0 && model.correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Indiquez le motif de cette nouvelle version."
        }
        return "Brouillon enregistré · prêt à relire."
    }

    private func reportField(_ label: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.headline)
            TextField(prompt, text: text, axis: .vertical).lineLimit(3...10).disabled(!model.canMutate)
                .accessibilityLabel(label)
            if text.wrappedValue.unicodeScalars.count > 3_500 {
                Text("\(text.wrappedValue.unicodeScalars.count)/4 000 caractères").font(.caption)
                    .foregroundStyle(text.wrappedValue.unicodeScalars.count > 4_000 ? DrivyTheme.danger : DrivyTheme.muted)
            }
        }.padding(.vertical, 4)
    }
    private func money(_ cents: Int64) -> String { SchoolCatalogFormatting.price(cents) }
    private func level(_ value: String) -> String { switch value { case "DISCOVERING": "En découverte"; case "GUIDED": "Avec accompagnement"; case "INDEPENDENT": "En autonomie"; default: "À vérifier" } }
}

private struct SchoolLessonCompletionSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()
    @State private var reason = ""
    @State private var reviewed = false
    @State private var captureStopped = false
    init(model: SchoolLessonReportWorkspace) {
        self.model = model
        let initial = Date()
        _start = State(initialValue: initial); _end = State(initialValue: initial)
    }
    private var valid: Bool { model.canMutate && reviewed && captureStopped && end > start && end <= Date().addingTimeInterval(300) && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.unicodeScalars.count <= 1_000 }
    var body: some View {
        NavigationStack {
            Form {
                Section("Heures réellement réalisées") {
                    DatePicker("Début réel", selection: $start)
                    DatePicker("Fin réelle", selection: $end)
                    Toggle("J’ai vérifié les heures réelles", isOn: $reviewed)
                    Toggle("La séance est terminée et aucune collecte n’est en cours", isOn: $captureStopped)
                }
                Section {
                    TextField("Motif et contexte du constat", text: $reason, axis: .vertical).lineLimit(3...8)
                    Text("\(reason.unicodeScalars.count)/1 000 caractères").font(.caption).foregroundStyle(.secondary)
                } header: { Text("Contrôle de permis non confirmé") }
                footer: { Text("Décrivez la situation constatée et les éventuels écarts horaires. Ce texte ne valide pas le permis.") }
                Section {
                    if let message = model.errorMessage { Text(message).foregroundStyle(DrivyTheme.danger) }
                    Button("Confirmer la réalisation") {
                        Task { if await model.complete(start: start, end: end, reason: reason, localCaptureStopped: captureStopped) { dismiss() } }
                    }.disabled(!valid)
                } footer: { Text("Cette confirmation crée le brouillon privé et la charge au prix convenu. Elle ne publie pas le bilan et n’enregistre aucun paiement.") }
            }
            .navigationTitle("Constater la leçon")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .interactiveDismissDisabled(model.isBusy)
        }
    }
}

private struct SchoolReportPreviewSheet: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let learnerName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(learnerName).font(.title2.bold())
                        if let lesson = model.lesson, let date = lesson.startsAt {
                            Text(SchoolPlanningFormat.instant(date, zone: lesson.timeZone))
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                        Label("Non publié · aperçu seulement", systemImage: "eye")
                            .font(.caption.weight(.medium)).foregroundStyle(DrivyTheme.muted)
                            .padding(.top, 2)
                    }
                    SchoolReportTexts(workedOn: model.workedOn, observationText: model.observationText, nextStep: model.nextStep)
                    if !model.observations.isEmpty {
                        Divider()
                        Text("Compétences observées").font(.title3.weight(.semibold))
                        ForEach(model.observations) { observation in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(model.competencies.first(where: { $0.id == observation.id })?.label ?? "Observation de compétence").font(.headline)
                                Text(observation.levelLabel).font(.subheadline).foregroundStyle(DrivyTheme.accent)
                                Text(observation.context)
                            }
                        }
                    }
                    if !model.correctionReason.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Motif de la nouvelle version").font(.headline)
                            Text(model.correctionReason)
                        }
                    }
                    Text("La publication partage ce bilan avec l’élève. Les notes de préparation restent privées.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.surface)
            .safeAreaInset(edge: .bottom, spacing: 0) { publicationBar }
            .navigationTitle("Aperçu élève")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour", systemImage: "chevron.left") { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
        }
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
    }

    private var publicationBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 10) {
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(DrivyTheme.danger)
            }
            if model.isBusy { ProgressView("Publication…").font(.subheadline) }
            layout {
                Button("Modifier") { dismiss() }
                    .buttonStyle(DrivySecondaryButtonStyle()).disabled(model.isBusy)
                Button("Publier") { Task { if await model.publish() { dismiss() } } }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canPublish)
                    .accessibilityLabel("Publier ce bilan à l’élève")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: 680).frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct SchoolReportTexts: View {
    let workedOn: String, observationText: String, nextStep: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            part("Travail réalisé", workedOn)
            part("À retenir", observationText)
            part("Prochaine étape", nextStep)
        }.padding(.vertical, 8)
    }
    private func part(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(text).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
