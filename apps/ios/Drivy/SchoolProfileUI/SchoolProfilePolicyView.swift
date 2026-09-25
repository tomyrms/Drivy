import SwiftUI

struct SchoolProfilePolicyView: View {
    @Bindable var model: SchoolProfileWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var showsEditor = false
    @State private var publication: SchoolProfilePolicy?

    var body: some View {
        NavigationStack {
            Form {
                introduction
                SchoolProfileStatusSections(model: model)
                ForEach(model.policies) { policy in policySection(policy) }
                if model.nextCursor != nil {
                    Section {
                        Button("Afficher les autres versions") { Task { await model.loadMorePolicies() } }
                            .disabled(model.isLoading || model.isBusy).frame(minHeight: 44)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                DrivyFormActionBar(hint: createHint) {
                    Button { showsEditor = true } label: {
                        Label("Préparer une nouvelle version", systemImage: "plus")
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canCreatePolicy)
                    .accessibilityIdentifier("profile-policy-create")
                }
            }
            .navigationTitle("Champs du profil").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task { await model.load() }
            .sheet(isPresented: $showsEditor) { SchoolProfilePolicyEditor(model: model) }
            .sheet(item: $publication) { policy in publicationReview(policy) }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
    }
    private var noticeAdopted: Bool {
        if let notice = model.notice, notice.status == "APPROVED", notice.noticeVersionId != nil { return true }
        return false
    }
    private var createHint: String? {
        guard !model.canCreatePolicy, !model.isLoading, !model.isBusy else { return nil }
        return noticeAdopted ? nil : "Adoptez d’abord la notice de données dans Configuration."
    }
    private var introduction: some View {
        Group {
            Section {
                DrivyFormIntro(context: model.school?.name ?? "Votre école",
                    message: "Choisissez les champs demandés, leur utilité et le moment où ils deviennent nécessaires.")
            }
            .listRowBackground(DrivyTheme.canvas)
            Section {
                if let notice = model.notice, noticeAdopted {
                    DrivyFormMessage(text: "Notice de données adoptée · version \(notice.version)")
                } else {
                    DrivyFormMessage(text: "Adoptez d’abord la notice de données dans Configuration.", tone: .neutral)
                }
                if !model.isLoading && model.policies.isEmpty && model.errorMessage == nil {
                    DrivyEmptyState(title: "Aucune version enregistrée",
                        message: "Préparez une première version pour indiquer les informations demandées aux élèves.",
                        symbol: "list.bullet.rectangle")
                }
            } header: { Text("Notice de données") }
        }
    }
    private func policySection(_ policy: SchoolProfilePolicy) -> some View {
        let isCurrent = model.applicablePolicy?.id == policy.id
        return Section {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                Text("Version \(policy.version)").font(.headline).foregroundStyle(DrivyTheme.text)
                Spacer(minLength: DrivySpacing.xs)
                DrivyStatusBadge(title: isCurrent ? "En vigueur" : status(policy.status),
                    symbol: isCurrent ? "checkmark.seal" : policy.status == "DRAFT" ? "pencil" : "clock",
                    tone: isCurrent ? .success : policy.status == "DRAFT" ? .warning : .neutral)
            }
            .accessibilityElement(children: .combine)
            LabeledContent("Prise d’effet", value: effectiveDate(policy.effectiveFrom))
                .font(.subheadline)
            DisclosureGroup("\(policy.fields.count) champs · consulter les règles") {
                SchoolProfileRulesReview(rules: policy.fields)
            }
            .font(.subheadline)
            if policy.status == "DRAFT" {
                Button("Relire avant publication") { publication = policy }
                    .frame(minHeight: 48).disabled(!model.canMutate)
                    .accessibilityIdentifier("profile-policy-review-\(policy.id.uuidString)")
            }
        }
    }
    private func publicationReview(_ policy: SchoolProfilePolicy) -> some View {
        NavigationStack {
            Form {
                Section {
                    DrivyFormIntro(context: "\(model.school?.name ?? "Votre école") · version \(policy.version)",
                        message: "Ces règles s’appliqueront aux profils concernés à la date prévue. Les informations existantes ne seront pas complétées automatiquement.")
                }
                .listRowBackground(DrivyTheme.canvas)
                Section {
                    LabeledContent("Prise d’effet", value: effectiveDate(policy.effectiveFrom))
                }
                Section { SchoolProfileRulesReview(rules: policy.fields) }
                if model.isLoadingPublication { Section { ProgressView("Lecture de la notice liée à ce brouillon…").frame(maxWidth: .infinity, minHeight: 44) } }
                if let notice = model.publicationNotice, notice.noticeVersionId == policy.noticeVersionId {
                    Section("Notice liée à cette politique · version \(notice.version)") {
                        Text(notice.noticeText).textSelection(.enabled)
                        Text(notice.retentionText).textSelection(.enabled)
                        if let email = notice.contactEmail { Text(email).textSelection(.enabled) }
                    }
                }
                if model.pending != nil {
                    SchoolProfileStatusSections(model: model)
                } else if let error = model.errorMessage {
                    Section {
                        SchoolErrorNotice(message: error)
                    }
                    Section {
                        if model.needsReload {
                            Button("Actualiser et relire") { Task { await reloadPublication(policy) } }
                                .frame(minHeight: 44).disabled(model.isBusy || model.isLoading)
                        } else {
                            Button("Relire la notice liée") { Task { await model.preparePublication(policy) } }
                                .frame(minHeight: 44).disabled(model.isBusy || model.isLoadingPublication)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .safeAreaInset(edge: .bottom) {
                DrivyFormActionBar {
                    Button {
                        Task { if await model.publishAfterConfirmation(policy) { publication = nil } }
                    } label: {
                        DrivyBusyLabel(title: "Publier ces règles", busyTitle: "Publication…", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canPublish(policy))
                    .accessibilityIdentifier("profile-policy-publish")
                }
            }
            .navigationTitle("Publication").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { publication = nil }.disabled(model.isBusy) } }
            .task(id: policy.id) { await model.preparePublication(policy) }
            .onChange(of: model.policies) { _, policies in
                if policies.contains(where: { $0.id == policy.id && $0.status == "PUBLISHED" }) {
                    publication = nil
                }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
    }
    private func reloadPublication(_ previous: SchoolProfilePolicy) async {
        await model.load()
        guard !model.needsReload else { return }
        guard let current = model.policies.first(where: { $0.id == previous.id }), current.status == "DRAFT" else {
            publication = nil
            return
        }
        publication = current
        await model.preparePublication(current)
    }
    private func effectiveDate(_ timestamp: String) -> String {
        guard let date = SchoolInvitation.date(timestamp) else { return "Date indisponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH")
        formatter.timeZone = TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich")
        formatter.dateStyle = .long; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func status(_ code: String) -> String {
        switch code { case "DRAFT": "Brouillon"; case "PUBLISHED": "Publiée"; default: "Ancienne politique" }
    }
}

private struct SchoolProfilePolicyEditor: View {
    @Bindable var model: SchoolProfileWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SchoolProfilePolicyDraft()
    @State private var confirms = false
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date d’effet", selection: $draft.effectiveFrom, displayedComponents: .date)
                    DatePicker("Heure", selection: $draft.effectiveFrom, displayedComponents: .hourAndMinute)
                } header: { Text("Prise d’effet") } footer: {
                    Text("Heure de l’école : \(model.school?.timeZone ?? "Europe/Zurich")")
                }
                ForEach(draft.rules.indices, id: \.self) { index in ruleEditor(index) }
                if model.pending != nil {
                    SchoolProfileStatusSections(model: model)
                } else if let error = model.errorMessage {
                    Section {
                        SchoolErrorNotice(message: error,
                            retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
                    }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                DrivyFormActionBar(hint: draftHint) {
                    Button { confirms = true } label: {
                        DrivyBusyLabel(title: "Créer le brouillon", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canCreatePolicy || !draft.isValid)
                    .accessibilityIdentifier("profile-policy-save-draft")
                }
            }
            .environment(\.timeZone, TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich") ?? .current)
            .disabled(model.isBusy)
            .navigationTitle("Nouvelle politique").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(model.isBusy) } }
            .confirmationDialog("Créer un brouillon avec ces champs et cette date d’effet ?", isPresented: $confirms, titleVisibility: .visible) {
                Button("Confirmer la création") {
                    let reviewed = draft
                    didSubmit = true
                    Task { if await model.createPolicyAfterConfirmation(reviewed) { dismiss() } }
                }
            } message: {
                Text("J’ai relu l’utilité des champs et leur effet sur les profils. La politique sera liée à la notice de données adoptée affichée précédemment.")
            }
            .onChange(of: model.isLoading) { _, loading in
                if didSubmit && !loading && !model.needsReload && model.pending == nil && model.successMessage != nil {
                    dismiss()
                }
            }
        }
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }
    private var draftHint: String {
        if let invalid = draft.selectedRules.first(where: { !$0.isValid }) {
            return invalid.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(invalid.field.label) : expliquez l’utilité de ce champ."
                : "\(invalid.field.label) : l’explication est limitée à 1 000 caractères."
        }
        return "Ce brouillon sera à relire avant publication."
    }
    private func ruleEditor(_ index: Int) -> some View {
        let field = draft.rules[index].field
        return Section {
            if field.isName { Text("Requis à l’entrée · identification").foregroundStyle(DrivyTheme.muted) }
            else {
                Toggle("Inclure ce champ", isOn: Binding(get: { draft.included.contains(field) }, set: {
                    if $0 { draft.included.insert(field) } else { draft.included.remove(field) }
                }))
            }
            if draft.included.contains(field) {
                if !field.isName && field != .profilePhotoDocumentId {
                    Picker("Caractère", selection: $draft.rules[index].requirement) {
                        ForEach(SchoolProfileRequirement.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .onChange(of: draft.rules[index].requirement) { _, requirement in
                        switch requirement {
                        case .optional: draft.rules[index].stage = .optional
                        case .conditional: draft.rules[index].stage = .beforeCourse
                        case .required: draft.rules[index].stage = .beforeLesson
                        }
                    }
                    Picker("Moment utile", selection: $draft.rules[index].stage) {
                        ForEach(allowedStages(draft.rules[index].requirement), id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Finalité", selection: $draft.rules[index].purposeCode) {
                        ForEach(field.purposes, id: \.self) { Text($0.label).tag($0) }
                    }
                } else if field == .profilePhotoDocumentId {
                    Text("Facultatif · personnalisation").foregroundStyle(DrivyTheme.muted)
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text("Utilité pour l’élève").font(.subheadline).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                    TextField("Expliquez pourquoi ce champ est demandé", text: $draft.rules[index].explanation, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityLabel("Utilité du champ \(field.label)")
                        .accessibilityIdentifier("profile-rule-explanation-\(field.rawValue)")
                }
                if draft.rules[index].explanation.unicodeScalars.count > 800 {
                    Text("\(draft.rules[index].explanation.unicodeScalars.count)/1 000 caractères").font(.caption)
                        .foregroundStyle(draft.rules[index].explanation.unicodeScalars.count > 1000 ? DrivyTheme.danger : DrivyTheme.muted)
                }
            }
        } header: { Text(field.label) }
    }
    private func allowedStages(_ requirement: SchoolProfileRequirement) -> [SchoolProfileStage] {
        switch requirement {
        case .optional: [.optional]
        case .conditional: [.beforeCourse]
        case .required: [.beforeLesson, .beforeCourse]
        }
    }
}

private struct SchoolProfileRulesReview: View {
    let rules: [SchoolProfileRule]
    var body: some View {
        ForEach(rules) { rule in
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(rule.field.label).font(.headline).foregroundStyle(DrivyTheme.text)
                Text(rule.requirement == .optional ? "Facultatif" : "\(rule.requirement.label) · \(rule.stage.label)").font(.subheadline)
                Text(rule.purposeCode.label).font(.footnote).foregroundStyle(DrivyTheme.muted)
                Text(rule.explanation).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DrivySpacing.xs)
        }
    }
}
