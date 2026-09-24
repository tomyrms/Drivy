import SwiftUI

struct SchoolProfilePolicyView: View {
    @Bindable var model: SchoolProfileWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var showsEditor = false
    @State private var publication: SchoolProfilePolicy?

    var body: some View {
        NavigationStack {
            Form {
                SchoolProfileStatusSections(model: model)
                introduction
                Section {
                    Button { showsEditor = true } label: {
                        Label("Préparer une politique", systemImage: "plus")
                    }
                    .frame(minHeight: 48).disabled(!model.canCreatePolicy)
                    .accessibilityIdentifier("profile-policy-create")
                }
                ForEach(model.policies) { policy in policySection(policy) }
                if model.nextCursor != nil {
                    Section {
                        Button("Afficher les autres versions") { Task { await model.loadMorePolicies() } }
                            .disabled(model.isLoading || model.isBusy).frame(minHeight: 44)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Champs du profil").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { await model.load() }
            .sheet(isPresented: $showsEditor) { SchoolProfilePolicyEditor(model: model) }
            .sheet(item: $publication) { policy in publicationReview(policy) }
        }
        .tint(DrivyTheme.accent)
    }
    private var introduction: some View {
        Section {
            Text("Demandez chaque information au bon moment.").font(.headline)
            Text("Les noms sont requis à l’entrée. La photo reste toujours facultative. Expliquez à quoi sert chaque autre information et quand elle devient utile.")
                .foregroundStyle(DrivyTheme.muted)
            if let notice = model.notice, notice.status == "APPROVED", notice.noticeVersionId != nil {
                Label("Notice de données adoptée · version \(notice.version)", systemImage: "checkmark.document")
                    .foregroundStyle(DrivyTheme.success)
            } else {
                Text("Adoptez d’abord la notice de données depuis Préparer l’école.").foregroundStyle(DrivyTheme.muted)
            }
            if !model.isLoading && model.policies.isEmpty {
                Text("Aucune politique publiée pour le moment.")
            }
        }
    }
    private func policySection(_ policy: SchoolProfilePolicy) -> some View {
        Section {
            HStack {
                Text(status(policy.status)).font(.headline)
                Spacer()
                Text("Version \(policy.version)").font(.caption).foregroundStyle(DrivyTheme.muted)
            }
            Text("Prise d’effet : \(effectiveDate(policy.effectiveFrom))").font(.subheadline)
            SchoolProfileRulesReview(rules: policy.fields)
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
                    Text("Publier ces règles pour l’école ?").font(.title2.weight(.bold))
                    Text("Les profils concernés seront vérifiés selon ces champs, leur finalité et leur stade. Les informations existantes ne seront pas complétées à la place des personnes.")
                    Text("Prise d’effet : \(effectiveDate(policy.effectiveFrom))")
                }
                Section { SchoolProfileRulesReview(rules: policy.fields) }
                if model.isLoadingPublication { Section { ProgressView("Lecture de la notice liée à ce brouillon…") } }
                if let notice = model.publicationNotice, notice.noticeVersionId == policy.noticeVersionId {
                    Section("Notice liée à cette politique · version \(notice.version)") {
                        Text(notice.noticeText).textSelection(.enabled)
                        Text(notice.retentionText).textSelection(.enabled)
                        if let email = notice.contactEmail { Text(email).textSelection(.enabled) }
                    }
                }
                if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
                Section {
                    Button("Publier ces règles") {
                        Task { if await model.publishAfterConfirmation(policy) { publication = nil } }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canPublish(policy))
                    .accessibilityIdentifier("profile-policy-publish")
                }
            }
            .navigationTitle("Publication").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { publication = nil } } }
            .task(id: policy.id) { await model.preparePublication(policy) }
        }
        .interactiveDismissDisabled(model.isBusy)
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Prise d’effet", selection: $draft.effectiveFrom)
                    Text("Heure de l’école : \(model.school?.timeZone ?? "Europe/Zurich")")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
                ForEach(draft.rules.indices, id: \.self) { index in ruleEditor(index) }
                if let error = model.errorMessage {
                    Section { SchoolErrorNotice(message: error) }
                }
                Section {
                    Button("Créer ce brouillon") { confirms = true }
                        .frame(minHeight: 48).disabled(!model.canCreatePolicy || !draft.isValid)
                        .accessibilityIdentifier("profile-policy-save-draft")
                    Text("La création prépare une version. La publication demandera une nouvelle confirmation.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
            .environment(\.timeZone, TimeZone(identifier: model.school?.timeZone ?? "Europe/Zurich") ?? .current)
            .disabled(model.isBusy)
            .navigationTitle("Nouvelle politique").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .confirmationDialog("Créer un brouillon avec ces champs et cette date d’effet ?", isPresented: $confirms, titleVisibility: .visible) {
                Button("Confirmer la création") {
                    let reviewed = draft
                    Task { if await model.createPolicyAfterConfirmation(reviewed) { dismiss() } }
                }
            } message: {
                Text("J’ai relu l’utilité des champs et leur effet sur les profils. La politique sera liée à la notice de données adoptée affichée précédemment.")
            }
        }
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
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
                TextField("Expliquez à la personne pourquoi ce champ est utile", text: $draft.rules[index].explanation, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("profile-rule-explanation-\(field.rawValue)")
                Text("1 000 caractères maximum").font(.caption).foregroundStyle(DrivyTheme.muted)
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
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.field.label).font(.headline)
                Text("\(rule.requirement.label) · \(rule.stage.label)").font(.subheadline)
                Text(rule.purposeCode.label).font(.footnote).foregroundStyle(DrivyTheme.muted)
                Text(rule.explanation).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
    }
}
