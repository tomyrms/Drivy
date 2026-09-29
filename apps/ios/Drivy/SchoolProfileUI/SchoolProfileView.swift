import SwiftUI

struct SchoolProfileView: View {
    @Bindable var model: SchoolProfileWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsSave = false
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
                .task { await model.load() }
                .confirmationDialog("Enregistrer ces informations dans le dossier de l’école ?", isPresented: $confirmsSave, titleVisibility: .visible) {
                    Button("Enregistrer le profil") {
                        attemptedSave = true
                        Task { _ = await model.saveProfileAfterConfirmation() }
                    }
                } message: {
                    Text("L’auteur de la saisie sera conservé. Le nom du compte de connexion ne sera pas modifié.")
                }
                .sheet(isPresented: $showsGuidedWelcome) { SchoolOnboardingView(model: model) }
                .confirmationDialog("Quitter sans enregistrer les changements du formulaire ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                    Button("Quitter le formulaire", role: .destructive) { dismiss() }
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
                Section {
                    DrivyFormIntro(context: model.school?.name ?? "Dossier scolaire",
                        message: model.isOwnProfile ? "Saisissez vos noms administratifs tels qu’ils doivent figurer dans le dossier."
                            : "Complétez uniquement les informations confirmées avec l’élève.")
                    if !model.isOwnProfile && !model.roles.contains("ADMIN") {
                        Text("Votre affectation vous permet de mettre à jour les contacts utiles à l’enseignement.")
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(DrivyTheme.canvas)
                identitySection(profile)
                contactSection
                if model.editableFields.contains(.birthDate) { birthSection }
                if model.editableFields.contains(.postalAddress) { addressSection }
                Section {
                    Label(profile.profilePhotoDocumentId == nil ? "Photo facultative" : "Une photo est associée au dossier", systemImage: "person.crop.circle")
                        .foregroundStyle(DrivyTheme.muted)
                } header: { Text("Photo") }
                readinessSection
            }
            if let onboarding = model.onboarding { onboardingSection(onboarding) }
            if let notice = model.notice, notice.status == "APPROVED" { noticeSection(notice) }
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            if model.profile != nil, !model.editableFields.isEmpty {
                DrivyFormActionBar(hint: saveHint.text, hintTone: saveHint.tone) {
                    Button {
                        confirmsSave = true
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
            ? "Modifications à enregistrer dans cette école." : "Vérifiez les champs signalés.", .neutral)
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
        } header: { Text("Identité scolaire") }
        .disabled(!model.canMutate || confirmsSave)
    }

    @ViewBuilder private var contactSection: some View {
        if model.editableFields.contains(.contactEmail) || model.editableFields.contains(.contactPhone) {
            Section {
                if model.editableFields.contains(.contactEmail) {
                    profileField("E-mail", text: $model.draft.contactEmail, identifier: "profile-email")
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    fieldExplanation(.contactEmail)
                }
                if model.editableFields.contains(.contactPhone) {
                    profileField("Téléphone", text: $model.draft.contactPhone, identifier: "profile-phone")
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    fieldExplanation(.contactPhone)
                }
            } header: { Text("Contacts") }
            .disabled(!model.canMutate || confirmsSave)
        }
    }
    private var birthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text("Date de naissance").font(.subheadline).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                TextField("JJ.MM.AAAA", text: $model.draft.birthDate).keyboardType(.numbersAndPunctuation)
                    .accessibilityLabel("Date de naissance, jour point mois point année")
                    .accessibilityIdentifier("profile-birth-date")
            }
            .padding(.vertical, DrivySpacing.xxs)
            fieldExplanation(.birthDate)
        } header: { Text("Date de naissance") }
        .disabled(!model.canMutate || confirmsSave)
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
        } header: { Text("Adresse postale") }
        .disabled(!model.canMutate || confirmsSave)
    }
    @ViewBuilder private func fieldExplanation(_ field: SchoolProfileField) -> some View {
        if let rule = model.applicablePolicy?.fields.first(where: { $0.field == field }) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(rule.requirement == .optional ? "Facultatif" : "\(rule.requirement.label) · \(rule.stage.label)").font(.caption.weight(.semibold))
                Text(rule.explanation).font(.footnote)
            }
            .foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
        if model.hasEdits, model.editableFields.contains(field),
           !model.draft.isValid(allowed: [field], timeZone: model.school?.timeZone ?? "Europe/Zurich") {
            Label(fieldError(field), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(DrivyTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func fieldError(_ field: SchoolProfileField) -> String {
        switch field {
        case .firstName: "Renseignez le prénom, limité à 150 caractères."
        case .lastName: "Renseignez le nom, limité à 150 caractères."
        case .contactEmail: "Vérifiez le format de l’adresse e-mail."
        case .contactPhone: "Le téléphone est limité à 32 caractères."
        case .birthDate: "Utilisez JJ.MM.AAAA pour une date réelle, non future."
        case .postalAddress: "Vérifiez la rue, le code postal, la localité et le code pays à deux lettres."
        case .profilePhotoDocumentId: "Vérifiez la photo du profil."
        }
    }
    private func profileField(_ title: String, text: Binding<String>, identifier: String? = nil) -> some View {
        DrivyFormField(label: title, text: text, identifier: identifier)
    }
    @ViewBuilder private var readinessSection: some View {
        if let readiness = model.readiness {
            Section {
                Label(readiness.ready ? "Accès à l’espace scolaire possible" : "Accès à l’espace scolaire à préparer",
                    systemImage: readiness.ready ? "checkmark.circle.fill" : "list.bullet.clipboard")
                    .font(.headline)
                    .foregroundStyle(readiness.ready ? DrivyTheme.success : DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                SchoolProfileBlockers(blockers: readiness.blockers)
            } header: { Text("Prochaine étape") }
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
                Text("Quelques étapes courtes : vos informations, votre formation, puis le GPS pendant les leçons.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reprendre l’accueil") { showsGuidedWelcome = true }
                    .frame(minHeight: 44)
                    .disabled(model.isBusy || model.hasEdits)
                    .accessibilityIdentifier("onboarding-resume")
                if model.hasEdits {
                    Text("Enregistrez d’abord les modifications du formulaire.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: { Text("Accueil dans l’école") }
    }
    private func noticeSection(_ notice: SchoolDataPolicy) -> some View {
        Section {
            DisclosureGroup("Comment l’école utilise vos données · version \(notice.version)") {
                Text(notice.noticeText).textSelection(.enabled)
                Text(notice.retentionText).textSelection(.enabled)
                if let email = notice.contactEmail { Text(email).textSelection(.enabled) }
            }
        }
    }
}

struct SchoolProfileStatusSections: View {
    @Bindable var model: SchoolProfileWorkspace
    var body: some View {
        Group {
            if model.isLoading { Section { ProgressView("Vérification du dossier…").frame(maxWidth: .infinity, minHeight: 44) } }
            if let error = model.errorMessage {
                Section {
                    SchoolErrorNotice(message: error,
                        retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
                }
            }
            if let success = model.successMessage, !model.hasEdits {
                Section { DrivyFormMessage(text: success) }
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
            }
        }
    }
}
extension SchoolProfileStatusSections {
    fileprivate func pendingNotes(_ pending: PendingSchoolCommand) -> [String] {
        var notes: [String] = []
        if !pending.kind.isProfile { notes.append("Cette demande vient d’un autre écran de l’école.") }
        if pending.scope != model.scope { notes.append("Vos accès ont changé depuis l’envoi. Le renvoi reste désactivé.") }
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
