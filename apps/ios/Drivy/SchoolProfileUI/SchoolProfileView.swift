import SwiftUI

struct SchoolProfileView: View {
    @Bindable var model: SchoolProfileWorkspace
    var loadsOnAppear = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsGuidedWelcome = false
    @State private var confirmsDiscard = false
    @State private var attemptedSave = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.learnerID == nil ? "Mon accueil" : (model.isOwnProfile ? "Mes informations" : "Profil de l’élève"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") {
                            if model.hasEdits { confirmsDiscard = true } else { dismiss() }
                        }.disabled(model.isBusy)
                    }
                }
                .task { if loadsOnAppear { await model.load() } }
                .sheet(isPresented: $showsGuidedWelcome) { SchoolOnboardingView(model: model) }
                .alert("Quitter sans enregistrer tes changements ?", isPresented: $confirmsDiscard) {
                    Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                } message: {
                    Text("Une demande déjà envoyée reste conservée sur cet appareil jusqu’à confirmation.")
                }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.hasEdits || model.isBusy)
    }

    private var content: some View {
        Form {
            SchoolProfileStatusSections(model: model)
            if let profile = model.profile {
                heading(profile)
                identitySection(profile)
                contactSection
                if model.editableFields.contains(.birthDate) { birthSection }
                if model.editableFields.contains(.postalAddress) { addressSection }
                if profile.profilePhotoDocumentId != nil {
                    Section {
                        Label("Une photo est associée au dossier", systemImage: "person.crop.circle")
                            .foregroundStyle(DrivyTheme.muted)
                    } header: { Text("Photo").drivyFormSectionHeader() }
                        .drivyFormRows()
                }
                readinessSection
            }
            if let onboarding = model.onboarding, onboarding.status != "COMPLETED" { onboardingSection(onboarding) }
            explanationsSection
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            if model.profile != nil, !model.editableFields.isEmpty, model.hasEdits || model.isBusy {
                DrivyFormActionBar(hint: saveHint.text, hintTone: saveHint.tone) {
                    Button {
                        attemptedSave = true
                        Task { _ = await model.saveProfileAfterConfirmation() }
                    } label: {
                        DrivyBusyLabel(title: "Enregistrer les modifications", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canSaveProfile)
                    .accessibilityIdentifier("profile-save")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var saveHint: (text: String?, tone: DrivyTone) {
        if attemptedSave, let error = model.errorMessage { return (error, .danger) }
        guard model.hasEdits else { return (nil, .neutral) }
        return (model.draft.isValid(allowed: model.editableFields, timeZone: model.school?.timeZone ?? "Europe/Zurich")
            ? nil : "Vérifie les champs signalés.", .neutral)
    }

    /// Même tête que l’écran Compte : avatar, nom, école. Elle ne redit pas les champs, elle nomme la personne.
    @ViewBuilder private func heading(_ profile: SchoolAdministrativeProfile) -> some View {
        let name = [profile.firstName, profile.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty {
            Section {
                HStack(spacing: DrivySpacing.m) {
                    if !typeSize.isAccessibilitySize { DrivyAvatar(name: name, size: 52) }
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(name)
                            .font(.drivyTitle)
                            .foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let school = model.school?.name {
                            Text(school)
                                .font(.subheadline)
                                .foregroundStyle(DrivyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DrivySpacing.xs, leading: 0, bottom: DrivySpacing.xs, trailing: 0))
            }
        }
    }

    private func identitySection(_ profile: SchoolAdministrativeProfile) -> some View {
        Section {
            if model.editableFields.contains(.firstName) {
                profileField("Prénom", text: $model.draft.firstName, identifier: "profile-first-name").textContentType(.givenName)
                fieldExplanation(.firstName)
            } else { LabeledContent("Prénom", value: profile.firstName ?? "À compléter") }
            if model.editableFields.contains(.lastName) {
                profileField("Nom", text: $model.draft.lastName, identifier: "profile-last-name").textContentType(.familyName)
                fieldExplanation(.lastName)
            } else { LabeledContent("Nom", value: profile.lastName ?? "À compléter") }
        } header: { Text("Identité scolaire").drivyFormSectionHeader() }
            .drivyFormRows()
        .disabled(!model.canMutate)
    }

    @ViewBuilder private var contactSection: some View {
        if model.editableFields.contains(.contactEmail) || model.editableFields.contains(.contactPhone) {
            Section {
                if model.editableFields.contains(.contactEmail) {
                    profileField("E-mail", text: $model.draft.contactEmail, prompt: "nom@exemple.ch", identifier: "profile-email")
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    fieldExplanation(.contactEmail)
                }
                if model.editableFields.contains(.contactPhone) {
                    profileField("Téléphone", text: $model.draft.contactPhone, identifier: "profile-phone")
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    fieldExplanation(.contactPhone)
                }
            } header: { Text("Contacts").drivyFormSectionHeader() }
                .drivyFormRows()
            .disabled(!model.canMutate)
        }
    }
    private var birthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                TextField("JJ.MM.AAAA", text: $model.draft.birthDate).keyboardType(.numbersAndPunctuation)
                    .accessibilityLabel("Date de naissance, jour point mois point année")
                    .accessibilityIdentifier("profile-birth-date")
            }
            .padding(.vertical, DrivySpacing.xxs)
            fieldExplanation(.birthDate)
        } header: { Text("Date de naissance").drivyFormSectionHeader() }
            .drivyFormRows()
        .disabled(!model.canMutate)
    }
    private var addressSection: some View {
        Section {
            Toggle("Renseigner une adresse", isOn: $model.draft.hasAddress)
            if model.draft.hasAddress {
                profileField("Rue et numéro", text: $model.draft.address.line1).textContentType(.streetAddressLine1)
                profileField("Complément · facultatif", text: Binding(get: { model.draft.address.line2 ?? "" }, set: { model.draft.address.line2 = $0.isEmpty ? nil : $0 }))
                    .textContentType(.streetAddressLine2)
                profileField("Code postal", text: $model.draft.address.postalCode).textContentType(.postalCode)
                profileField("Localité", text: $model.draft.address.locality).textContentType(.addressCity)
                profileField("Code pays · deux lettres", text: $model.draft.address.countryCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            fieldExplanation(.postalAddress)
        } header: { Text("Adresse postale").drivyFormSectionHeader() }
            .drivyFormRows()
        .disabled(!model.canMutate)
    }
    @ViewBuilder private func fieldExplanation(_ field: SchoolProfileField) -> some View {
        if model.hasEdits, model.editableFields.contains(field),
           !model.draft.isValid(allowed: [field], timeZone: model.school?.timeZone ?? "Europe/Zurich") {
            Label(fieldError(field), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(DrivyTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func fieldError(_ field: SchoolProfileField) -> String {
        switch field {
        case .firstName: "Renseigne le prénom, limité à 150 caractères."
        case .lastName: "Renseigne le nom, limité à 150 caractères."
        case .contactEmail: "Vérifie le format de l’adresse e-mail."
        case .contactPhone: "Le téléphone est limité à 32 caractères."
        case .birthDate: "Utilise JJ.MM.AAAA pour une date réelle, non future."
        case .postalAddress: "Vérifie la rue, le code postal, la localité et le code pays à deux lettres."
        case .profilePhotoDocumentId: "Vérifie la photo du profil."
        }
    }
    private func profileField(_ title: String, text: Binding<String>, prompt: String? = nil, identifier: String? = nil) -> some View {
        DrivyFormField(label: title, text: text, prompt: prompt, identifier: identifier)
    }
    @ViewBuilder private var readinessSection: some View {
        if let readiness = model.readiness, !readiness.ready {
            Section {
                Label("Accès à l’espace scolaire à préparer", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                SchoolProfileBlockers(blockers: readiness.blockers)
            } header: { Text("Prochaine étape").drivyFormSectionHeader() }
                .drivyFormRows()
        }
    }
    /// The welcome itself is the guided flow (SchoolOnboardingView); this screen
    /// only says where it stands and reopens it. No step is chosen from a list here.
    private func onboardingSection(_ onboarding: SchoolOnboarding) -> some View {
        let completed = onboarding.status == "COMPLETED"
        return Section {
            Label(completed ? "Accueil terminé" : "Accueil à terminer",
                systemImage: completed ? "checkmark.circle.fill" : "figure.wave")
                .font(.headline)
                .foregroundStyle(completed ? DrivyTheme.success : DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            if !completed {
                Button("Reprendre l’accueil") { showsGuidedWelcome = true }
                    .frame(minHeight: 44)
                    .disabled(model.isBusy || model.hasEdits)
                    .accessibilityIdentifier("onboarding-resume")
                if model.hasEdits {
                    Text("Enregistre d’abord tes modifications.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: { Text("Accueil dans l’école").drivyFormSectionHeader() }
            .drivyFormRows()
    }
    /// Les deux explications (champs demandés, usage des données) forment un seul groupe :
    /// deux lignes séparées d’un filet plutôt que deux pastilles isolées.
    @ViewBuilder private var explanationsSection: some View {
        let policy = model.applicablePolicy
        let notice = model.notice.flatMap { $0.status == "APPROVED" ? $0 : nil }
        if policy != nil || notice != nil {
            Section {
                if let policy {
                    DisclosureGroup("Pourquoi ces informations ?") {
                        ForEach(policy.fields) { rule in
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text(rule.field.label).font(.subheadline.weight(.semibold))
                                Text(rule.requirement == .optional ? "Facultatif" : "\(rule.requirement.label) · \(rule.stage.label)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                                Text(rule.explanation).font(.footnote).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let notice {
                    // Same wording and content as the notice sheet of the guided welcome.
                    DisclosureGroup("Comment l’école utilise tes données") {
                        Text(notice.noticeText).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text(notice.retentionText).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if let email = notice.contactEmail {
                            DrivyContactRow(title: "Contact pour tes données", value: email, symbol: "envelope")
                        }
                        Text("Version \(notice.version)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(DrivyTheme.muted)
                    }
                }
            }
            .drivyFormRows()
        }
    }
}

struct SchoolProfileStatusSections: View {
    @Bindable var model: SchoolProfileWorkspace
    var body: some View {
        Group {
            if model.profile == nil && model.onboarding == nil && model.errorMessage == nil
                && (model.isLoading || model.school == nil) {
                Section { DrivySkeletonRows(count: 4).drivySkeleton("Chargement du dossier…") }
                    .drivyFormRows()
            }
            if let error = model.errorMessage {
                // The notice is the whole row: no white card around the red one.
                Section {
                    SchoolErrorNotice(message: error,
                        retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(DrivyTheme.dangerSurface)
                }
            }
            if let success = model.successMessage, !model.hasEdits {
                Section { DrivyFormMessage(text: success) }
                    .drivyFormRows()
            }
            if let pending = model.pending {
                Section {
                    DrivyPendingRequest(
                        message: "Une nouvelle modification sera possible après vérification du résultat.",
                        notes: pendingNotes(pending),
                        reference: pending.id,
                        verify: { Task { await model.verifyPending() } }, canVerify: model.canVerifyPending,
                        retry: model.canRetryPending ? { Task { await model.retryPending() } } : nil)
                }
                    .drivyFormRows()
            }
        }
    }
}
extension SchoolProfileStatusSections {
    fileprivate func pendingNotes(_ pending: PendingSchoolCommand) -> [String] {
        var notes: [String] = []
        if pending.observationUndoOperationID != nil {
            notes.append("L’annulation du signalement doit être vérifiée depuis la leçon.")
        } else if !pending.kind.isProfile {
            notes.append("Cette demande vient d’un autre écran de l’école.")
        }
        if pending.scope != model.scope { notes.append("Tes accès ont changé depuis l’envoi. Le renvoi reste désactivé.") }
        return notes
    }
}

struct SchoolProfileBlockers: View {
    let blockers: [SchoolActionBlocker]
    var body: some View {
        ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                Image(systemName: "circle")
                    .font(.caption)
                    .foregroundStyle(DrivyTheme.controlBorder)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    if let code = blocker.field, let field = SchoolProfileField(rawValue: code) {
                        Text("\(field.label) — \(blocker.message)").font(.subheadline)
                    } else { Text(blocker.message).font(.subheadline) }
                    if let purpose = blocker.purpose { Text(purpose).font(.footnote).foregroundStyle(DrivyTheme.muted) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
