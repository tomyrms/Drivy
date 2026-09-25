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
                ContentUnavailableView("Choisissez votre école", systemImage: "building.2", description: Text("Le bilan est lié à votre compte et à cette école."))
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
                        Text(learnerName).font(.drivyTitle).fixedSize(horizontal: false, vertical: true)
                        if let date = model.lesson?.startsAt, let lesson = model.lesson {
                            Text(SchoolPlanningFormat.instant(date, zone: lesson.timeZone)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if let lesson = model.lesson {
                    stateBadges(lesson)
                }
                if model.isLoading || model.isBusy {
                    ProgressView(model.isBusy ? "Enregistrement auprès de l’école…" : "Chargement de la leçon…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.errorMessage {
                    SchoolErrorNotice(message: error, retry: model.isBusy || model.isLoading ? nil : { showReloadConfirmation = true })
                }
                if let message = model.confirmation {
                    DrivyInlineMessage(text: message)
                }
                if let message = model.information {
                    DrivyInlineMessage(text: message, tone: .neutral)
                }
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
                } header: { Label("Observations privées", systemImage: "lock.fill") }
                footer: {
                    Text("Ces observations restent privées. Elles ne sont pas partagées avec le bilan.")
                }
            }
            if model.isAuthor, model.draft != nil { draftSection }
            if let wish = model.wish {
                Section {
                    if model.isOwnLearner {
                        TextField("Ce que j’aimerais travailler", text: $model.wishText, axis: .vertical).lineLimit(3...8).disabled(!model.canMutate)
                        Text("\(model.wishText.unicodeScalars.count) / 500 caractères").font(.caption.monospacedDigit())
                            .foregroundStyle(model.wishText.unicodeScalars.count > 500 ? DrivyTheme.danger : DrivyTheme.muted)
                        Button("Enregistrer mon souhait") { Task { await model.saveWish() } }
                            .disabled(!model.canMutate || model.wishText.unicodeScalars.count > 500 || model.wishText == wish.text)
                    } else if wish.text.isEmpty {
                        Text("L’élève n’a pas encore exprimé de souhait.").foregroundStyle(DrivyTheme.muted)
                    } else { Text(wish.text) }
                } header: { Text("Souhait pour la prochaine leçon") }
                footer: {
                    if model.isOwnLearner { Text("Votre moniteur peut lire ce souhait.") }
                }
            }
            if model.isAuthor, model.lesson?.status == "PLANNED" { preparationSection }
            if model.isAuthor, model.lesson?.status == "PLANNED" {
                Section {
                    Button { showComplete = true } label: { Label("Constater la leçon réalisée", systemImage: "checkmark.seal") }
                        .disabled(!model.canMutate)
                } header: { Text("Après la conduite") }
                footer: { Text("À confirmer après la conduite et l’arrêt de toute collecte. Le constat ouvre le brouillon privé et inscrit le prix convenu au compte de la leçon.") }
            }
            if !model.revisions.isEmpty { publishedSection }
            if let error = model.revisionsError {
                Section("Bilans partagés") {
                    SchoolErrorNotice(message: error, retry: { showReloadConfirmation = true })
                }
            } else if model.revisions.isEmpty, model.lesson != nil, !model.isLoading {
                Section("Bilans partagés") {
                    DrivyEmptyState(title: "Pas encore de bilan partagé",
                        message: model.isAuthor
                            ? "Rien n’est partagé avec l’élève tant que le bilan n’est pas publié."
                            : "Le bilan s’affichera ici quand le moniteur l’aura publié.",
                        symbol: "doc.text")
                }
            }
            if let account = model.account {
                Section("Compte de cette leçon") {
                    LabeledContent("Montant dû") { Text(money(account.chargeCents)).monospacedDigit() }
                    LabeledContent("Montant reçu") { Text(money(account.netReceivedCents)).monospacedDigit() }
                    LabeledContent("Solde restant") { Text(money(account.balanceCents)).monospacedDigit().fontWeight(.semibold) }
                }
            }
            if let progress = model.progress, !progress.items.isEmpty {
                Section {
                    ForEach(progress.items) { item in
                        DrivyCompetencyNote(label: item.label, level: level(item.level), context: item.context,
                            date: SchoolLesson.date(item.observedAt).map { $0.formatted(date: .abbreviated, time: .omitted) })
                            .padding(.vertical, DrivySpacing.xxs)
                    }
                } header: { Text("Progression") }
                footer: { Text("Issue des bilans publiés. Chaque appréciation garde sa date et son contexte ; aucun score global.") }
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
        .tint(DrivyTheme.accent)
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
        Section {
            Label("Confirmation en attente", systemImage: "clock.arrow.circlepath").font(.headline).foregroundStyle(DrivyTheme.warning)
            Text("Cette demande est conservée de façon protégée sur cet appareil. Aucune nouvelle modification n’est envoyée avant sa résolution.")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Relire la demande conservée") { Text(model.pendingDescription).textSelection(.enabled) }
            Button("Vérifier son enregistrement") { Task { await model.verifyPending() } }.disabled(model.isBusy || model.isLoading)
            if model.pending?.kind.isReport == true {
                Toggle("J’ai relu cette demande", isOn: Binding(get: { model.pendingReviewed }, set: { if $0 { model.reviewPending() } }))
                Button("Renvoyer exactement cette demande") { Task { await model.retryPending() } }.disabled(!model.canRetry)
            }
        } footer: { Text("Une absence de réponse ne signifie pas que l’école a refusé la demande.") }
    }
    /// Lesson state, plus the report state for its author: private stays visibly private.
    private func stateBadges(_ lesson: SchoolLesson) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(spacing: DrivySpacing.xs))
        return layout {
            lesson.drivyState.badge
            if model.isAuthor && model.draft != nil { DrivyReportState.privateDraft.badge }
            else if lesson.currentPublishedRevisionId != nil { DrivyReportState.shared.badge }
        }
    }
    private var preparationSection: some View {
        Section {
            ForEach(model.goals.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text("Objectif \(index + 1)").font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                        .accessibilityHidden(true)
                    TextField("Objectif \(index + 1)", text: $model.goals[index].label, axis: .vertical)
                    TextField("Contexte prévu", text: Binding(get: { model.goals[index].context ?? "" }, set: { model.goals[index].context = $0 }), axis: .vertical)
                    Text("Objectif et contexte : 500 caractères maximum chacun.").font(.caption).foregroundStyle(DrivyTheme.muted)
                    Button("Retirer cet objectif", role: .destructive) { model.goals.remove(at: index) }
                        .font(.subheadline).frame(minHeight: 44).buttonStyle(.borderless)
                }
                .padding(.vertical, DrivySpacing.xxs)
                .disabled(!model.canMutate)
            }
            if model.goals.count < 3 {
                Button { model.goals.append(SchoolLessonGoal(label: "", competencyId: nil, context: nil)) } label: {
                    Label("Ajouter un objectif", systemImage: "plus")
                }.disabled(!model.canMutate)
            }
            TextField("Note sur les vérifications administratives", text: $model.administrativeNote, axis: .vertical).lineLimit(2...6).disabled(!model.canMutate)
            if let preparation = model.preparation, !preparation.plannedWaypoints.isEmpty {
                Text("\(preparation.plannedWaypoints.count) repère(s) manuel(s) conservé(s) dans cette préparation.").font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
            Button("Enregistrer la préparation") { Task { await model.savePreparation() } }
                .fontWeight(.semibold)
                .disabled(!model.canMutate || !model.preparationValid)
        } header: { Label("Préparation privée", systemImage: "lock.fill") }
        footer: { Text("Elle n’est pas partagée avec l’élève. Jusqu’à trois objectifs. La préparation n’est pas une observation de ce qui a été réalisé.") }
    }
    @ViewBuilder private var draftSection: some View {
        Section {
            reportField("Travail réalisé", prompt: "Les situations et exercices abordés", text: $model.workedOn)
            reportField("À retenir", prompt: "Ce qui a progressé et ce qui reste à travailler", text: $model.observationText)
            reportField("Prochaine étape", prompt: "L’objectif de la prochaine séance", text: $model.nextStep)
            if (model.lesson?.publicationVersion ?? 0) > 0 {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text("Motif de la correction").font(.headline)
                    TextField("Ce qui change par rapport au bilan partagé", text: $model.correctionReason, axis: .vertical)
                        .disabled(!model.canMutate)
                        .accessibilityLabel("Motif de la correction")
                }.padding(.vertical, DrivySpacing.xxs)
            }
        } header: { Label("Bilan · brouillon privé", systemImage: "lock.fill") }
        footer: { Text(draftFooter) }
        if !model.competencies.isEmpty {
            Section {
                ForEach(model.competencies) { competency in
                    DisclosureGroup {
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
                            Text("Contexte requis, 500 caractères maximum.").font(.caption).foregroundStyle(DrivyTheme.muted)
                        }
                    } label: {
                        competencyLabel(competency)
                    }
                    .disabled(!model.canMutate)
                }
            } header: { Text("Compétences observées") }
            footer: { Text("Aucun niveau n’est choisi automatiquement ; seules les compétences observées ont besoin d’un contexte.") }
        }
    }
    private func competencyLabel(_ competency: SchoolCatalogCompetency) -> some View {
        let observed = model.observations.first(where: { $0.id == competency.id })
        return VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(competency.label).foregroundStyle(DrivyTheme.text)
            if let observed {
                DrivyStatusBadge(title: level(observed.level), tone: .accent)
            }
        }
        .padding(.vertical, DrivySpacing.xxs)
    }
    private var publishedSection: some View {
        Section("Bilans partagés") {
            ForEach(model.revisions) { revision in
                DisclosureGroup {
                    DrivyReportBody(nextStep: revision.nextStep, workedOn: revision.workedOn,
                        observationText: revision.observationText, compact: true)
                    ForEach(revision.observations) { observation in
                        DrivyCompetencyNote(label: model.competencies.first(where: { $0.id == observation.id })?.label ?? "Observation de compétence",
                            level: observation.levelLabel, context: observation.context)
                            .padding(.vertical, DrivySpacing.xxs)
                    }
                    if let reason = revision.correctionReason, !reason.isEmpty {
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text("Motif de la correction").font(.headline)
                            Text(reason).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, DrivySpacing.xxs)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("Version \(revision.sequence)").font(.headline).foregroundStyle(DrivyTheme.text)
                        if let date = SchoolLesson.date(revision.publishedAt) {
                            Text("Publiée le \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                        }
                        (revision.id == model.lesson?.currentPublishedRevisionId ? DrivyReportState.shared : DrivyReportState.historical).badge
                    }
                    .padding(.vertical, DrivySpacing.xxs)
                }
            }
        }
    }
    private var draftActionBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
        return DrivyStickyActionBar {
            DrivyActionNote(text: draftHint)
            layout {
                Button { Task { await model.saveDraft() } } label: {
                    Label("Enregistrer", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(DrivySecondaryButtonStyle())
                .disabled(!model.canMutate || !model.validTexts || !model.observationsValid || !model.draftChanged)
                .accessibilityLabel("Enregistrer le brouillon privé")
                Button { showPreview = true } label: { Label("Aperçu élève", systemImage: "eye") }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canPublish)
            }
        }
    }

    private var draftFooter: String {
        if model.draftChanged { return "Des modifications ne sont pas encore enregistrées. Enregistrez-les avant de relire l’aperçu et publier." }
        if (model.lesson?.publicationVersion ?? 0) > 0 { return "L’élève verra cette nouvelle version et son motif de correction après la publication." }
        return "L’élève ne voit ce bilan qu’après sa publication."
    }
    private var draftHint: String {
        if model.isBusy { return "Enregistrement auprès de l’école…" }
        if model.pending != nil { return "Vérifiez la confirmation en attente avant de poursuivre." }
        if !model.canMutate { return "Vérifiez les informations du bilan avant de poursuivre." }
        if !model.validTexts { return "Un des textes dépasse 4 000 caractères." }
        if !model.observationsValid { return "Précisez le contexte de chaque compétence retenue." }
        if model.draftChanged { return "Modifications à enregistrer · le brouillon reste privé." }
        if [model.workedOn, model.observationText, model.nextStep].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Complétez les trois parties pour ouvrir l’aperçu élève."
        }
        if (model.lesson?.publicationVersion ?? 0) > 0 && model.correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Indiquez le motif de la correction."
        }
        return "Brouillon enregistré, toujours privé · prêt à relire avant publication."
    }

    private func reportField(_ label: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(label).font(.headline).accessibilityHidden(true)
            TextField(prompt, text: text, axis: .vertical).lineLimit(3...10).disabled(!model.canMutate)
                .accessibilityLabel(label)
            if text.wrappedValue.unicodeScalars.count > 3_500 {
                Text("\(text.wrappedValue.unicodeScalars.count) / 4 000 caractères").font(.caption.monospacedDigit())
                    .foregroundStyle(text.wrappedValue.unicodeScalars.count > 4_000 ? DrivyTheme.danger : DrivyTheme.muted)
            }
        }.padding(.vertical, DrivySpacing.xxs)
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
    /// Explains a disabled confirmation. Mirrors `valid`; never a second rule.
    private var hint: String? {
        if model.isBusy { return "Enregistrement du constat auprès de l’école…" }
        if !model.canMutate { return "Le constat n’est pas disponible pour l’instant. Fermez puis actualisez la leçon." }
        if end <= start { return "La fin réelle doit suivre le début réel." }
        if end > Date().addingTimeInterval(300) { return "La fin réelle ne peut pas être à venir." }
        if !reviewed { return "Confirmez avoir vérifié les heures réelles." }
        if !captureStopped { return "Confirmez que la séance est terminée et qu’aucune collecte n’est en cours." }
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Décrivez la situation constatée." }
        if reason.unicodeScalars.count > 1_000 { return "Le motif est limité à 1 000 caractères." }
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Début réel", selection: $start)
                    DatePicker("Fin réelle", selection: $end)
                    Toggle("J’ai vérifié les heures réelles", isOn: $reviewed)
                    Toggle("La séance est terminée et aucune collecte n’est en cours", isOn: $captureStopped)
                } header: { Text("Heures réellement réalisées") }
                footer: { Text("Indiquez les heures de la conduite, pas celles prévues au planning.") }
                Section {
                    TextField("Motif et contexte du constat", text: $reason, axis: .vertical).lineLimit(3...8)
                    Text("\(reason.unicodeScalars.count) / 1 000 caractères").font(.caption.monospacedDigit())
                        .foregroundStyle(reason.unicodeScalars.count > 1_000 ? DrivyTheme.danger : DrivyTheme.muted)
                } header: { Text("Contrôle de permis non confirmé") }
                footer: { Text("Décrivez la situation constatée et les éventuels écarts horaires. Ce texte ne valide pas le permis.") }
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
                            Label("Confirmer la réalisation", systemImage: "checkmark.seal")
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!valid)
                    Text("Cette confirmation crée le brouillon privé et la charge au prix convenu. Elle ne publie pas le bilan et n’enregistre aucun paiement.")
                        .font(.caption).foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Constater la leçon").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
        }
        .tint(DrivyTheme.accent)
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
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text(learnerName).font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let lesson = model.lesson, let date = lesson.startsAt {
                            Text(SchoolPlanningFormat.instant(date, zone: lesson.timeZone))
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                        DrivyReportState.privateDraft.badge
                        Text("Aperçu : l’élève verra ce bilan tel quel après publication.")
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DrivyReportBody(nextStep: model.nextStep, workedOn: model.workedOn, observationText: model.observationText)
                    if !model.observations.isEmpty {
                        VStack(alignment: .leading, spacing: DrivySpacing.s) {
                            DrivySectionHeader(title: "Compétences observées")
                            DrivyRowGroup {
                                ForEach(model.observations) { observation in
                                    DrivyCompetencyNote(label: model.competencies.first(where: { $0.id == observation.id })?.label ?? "Observation de compétence",
                                        level: observation.levelLabel, context: observation.context)
                                        .padding(.vertical, DrivySpacing.s)
                                }
                            }
                        }
                    }
                    if !model.correctionReason.isEmpty {
                        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                            Text("Motif de la correction").font(.drivySection).accessibilityAddTraits(.isHeader)
                            Text(model.correctionReason).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .drivyPageContent()
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
            ? AnyLayout(VStackLayout(spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
        return DrivyStickyActionBar {
            if let error = model.errorMessage {
                DrivyActionNote(text: error, isError: true)
            } else if model.isBusy {
                ProgressView("Publication du bilan…").font(.subheadline)
            } else {
                DrivyActionNote(text: "La publication partage ce bilan avec l’élève. Les notes de préparation restent privées.")
            }
            layout {
                Button("Modifier") { dismiss() }
                    .buttonStyle(DrivySecondaryButtonStyle()).disabled(model.isBusy)
                Button("Publier") { Task { if await model.publish() { dismiss() } } }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canPublish)
                    .accessibilityLabel("Publier ce bilan à l’élève")
            }
        }
    }
}
