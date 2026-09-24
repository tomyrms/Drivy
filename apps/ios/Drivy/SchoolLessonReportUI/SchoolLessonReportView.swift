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
    }
    var body: some View {
        Group {
            if let model, matches(model) {
                SchoolLessonReportContent(model: model, learnerName: learnerName)
            } else {
                ContentUnavailableView("Sélectionnez votre école", systemImage: "building.2", description: Text("Le bilan est lié à votre compte et à cette école."))
            }
        }
        .navigationTitle("Préparation et bilan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") {
                    if hasUnsavedChanges { confirmsDiscard = true } else { dismiss() }
                }.disabled(model?.isBusy == true)
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges || model?.isBusy == true)
        .confirmationDialog("Fermer sans enregistrer cette saisie ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Fermer sans enregistrer", role: .destructive) { dismiss() }
            Button("Continuer la saisie", role: .cancel) { }
        }
        .task(id: scopeKey) {
            model?.invalidate(); model = nil
            guard let person = schoolWorkspace.person, let membership = schoolWorkspace.membership else { return }
            let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId, membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
            let value = SchoolLessonReportWorkspace(scope: scope, membership: membership, lessonID: lessonID, client: client)
            model = value; await value.load()
        }
        .onDisappear { model?.invalidate() }
    }
}

private struct SchoolLessonReportContent: View {
    @Bindable var model: SchoolLessonReportWorkspace
    let learnerName: String
    @State private var showComplete = false
    @State private var showPreview = false
    @State private var showReloadConfirmation = false

    var body: some View {
        Form {
            Section {
                Text(learnerName).font(.title2.bold())
                if let lesson = model.lesson {
                    Label(lesson.statusLabel, systemImage: "steeringwheel")
                    if let date = lesson.startsAt { Text(date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                }
                if model.isLoading || model.isBusy { ProgressView(model.isBusy ? "Enregistrement…" : "Chargement…") }
                if let error = model.errorMessage { Text(error).foregroundStyle(DrivyTheme.danger).accessibilityLabel("Erreur : \(error)") }
                if let message = model.confirmation { Label(message, systemImage: "checkmark.circle").foregroundStyle(DrivyTheme.accent) }
                if let message = model.information { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Button("Actualiser les informations") { showReloadConfirmation = true }.disabled(model.isBusy || model.isLoading)
            }
            if model.pending != nil { pendingSection }
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
            if model.isAuthor, model.draft != nil { draftSection }
            if !model.revisions.isEmpty { publishedSection }
            else if model.lesson != nil {
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
        .confirmationDialog("Recharger les données de l’école ?", isPresented: $showReloadConfirmation, titleVisibility: .visible) {
            Button("Recharger et remplacer la saisie non enregistrée") { Task { await model.load() } }
            Button("Garder ma saisie", role: .cancel) {}
        }
        .sheet(isPresented: $showComplete) { SchoolLessonCompletionSheet(model: model) }
        .sheet(isPresented: $showPreview) { SchoolReportPreviewSheet(model: model, learnerName: learnerName) }
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
            reportField("Travail réalisé", text: $model.workedOn)
            reportField("Constat", text: $model.observationText)
            reportField("Prochaine étape", text: $model.nextStep)
            if !model.competencies.isEmpty {
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
            Button("Enregistrer le brouillon privé") { Task { await model.saveDraft() } }
                .disabled(!model.canMutate || !model.validTexts || !model.observationsValid || !model.draftChanged)
            if (model.lesson?.publicationVersion ?? 0) > 0 {
                TextField("Motif de la nouvelle version", text: $model.correctionReason, axis: .vertical).disabled(!model.canMutate)
            }
            Button { showPreview = true } label: { Label("Relire l’aperçu élève", systemImage: "eye") }.disabled(!model.canPublish)
        } header: { Text("Brouillon privé") }
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
    private func reportField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.headline)
            TextField(label, text: text, axis: .vertical).lineLimit(3...10).disabled(!model.canMutate)
            Text("\(text.wrappedValue.unicodeScalars.count)/4 000 caractères").font(.caption).foregroundStyle(.secondary)
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
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(learnerName).font(.title2.bold()); Text("Voici le contenu qui sera partagé avec l’élève.") }
                Section { SchoolReportTexts(workedOn: model.workedOn, observationText: model.observationText, nextStep: model.nextStep) }
                if !model.observations.isEmpty {
                    Section("Compétences observées") {
                        ForEach(model.observations) { observation in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.competencies.first(where: { $0.id == observation.id })?.label ?? "Observation de compétence").font(.headline)
                                Text(observation.levelLabel); Text(observation.context)
                            }
                        }
                    }
                }
                if !model.correctionReason.isEmpty { Section("Motif de correction") { Text(model.correctionReason) } }
                Section {
                    if let error = model.errorMessage { Text(error).foregroundStyle(DrivyTheme.danger) }
                    Button("Publier ce bilan à l’élève") { Task { if await model.publish() { dismiss() } } }
                        .disabled(!model.canPublish)
                } footer: { Text("Seul le contenu de cet aperçu sera partagé. La préparation et le souhait de l’élève restent séparés.") }
            }
            .navigationTitle("Aperçu élève")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Revenir au brouillon") { dismiss() } } }
            .interactiveDismissDisabled(model.isBusy)
        }
    }
}

private struct SchoolReportTexts: View {
    let workedOn: String, observationText: String, nextStep: String
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            part("Travail réalisé", workedOn)
            part("Constat", observationText)
            part("Prochaine étape", nextStep)
        }.padding(.vertical, 8)
    }
    private func part(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(text).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
