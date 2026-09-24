import SwiftUI

struct SchoolProfileView: View {
    @Bindable var model: SchoolProfileWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsSave = false
    @State private var confirmsComplete = false
    @State private var confirmsDiscard = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(model.learnerID == nil ? "Mon arrivée" : "Profil de l’élève")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") {
                            if model.hasEdits { confirmsDiscard = true } else { dismiss() }
                        }
                    }
                }
                .task { await model.load() }
                .confirmationDialog("Enregistrer ces informations dans le dossier de l’école ?", isPresented: $confirmsSave, titleVisibility: .visible) {
                    Button("Enregistrer le profil") { Task { _ = await model.saveProfileAfterConfirmation() } }
                } message: {
                    Text("L’auteur de la saisie sera conservé. Le nom du compte de connexion ne sera pas modifié.")
                }
                .confirmationDialog("Terminer votre arrivée ?", isPresented: $confirmsComplete, titleVisibility: .visible) {
                    Button("Terminer mon arrivée") { Task { _ = await model.completeOnboardingAfterConfirmation() } }
                } message: {
                    Text("Les conditions propres à chaque future leçon ou cours seront vérifiées au moment utile.")
                }
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
                    Text(model.isOwnProfile ? "Vos informations dans cette école" : "Informations du dossier scolaire")
                        .font(.headline)
                    Text(model.isOwnProfile ? "Saisissez vos noms administratifs tels qu’ils doivent figurer dans le dossier."
                         : "Complétez uniquement les informations confirmées avec l’élève.")
                        .foregroundStyle(DrivyTheme.muted)
                    if !model.isOwnProfile && !model.roles.contains("ADMIN") {
                        Text("Votre affectation vous permet de mettre à jour les contacts utiles à l’enseignement.")
                            .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    }
                }
                identitySection(profile)
                contactSection
                if model.editableFields.contains(.birthDate) { birthSection }
                if model.editableFields.contains(.postalAddress) { addressSection }
                Section {
                    Label(profile.profilePhotoDocumentId == nil ? "Photo facultative" : "Une photo est associée au dossier", systemImage: "person.crop.circle")
                    Text("L’absence de photo n’empêche pas de compléter le profil ni de consulter les formations.")
                        .font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
                Section {
                    Button("Enregistrer mes modifications") { confirmsSave = true }
                        .frame(minHeight: 48)
                        .disabled(!model.canSaveProfile)
                        .accessibilityIdentifier("profile-save")
                    if model.hasEdits && !model.draft.isValid(allowed: model.editableFields, timeZone: model.school?.timeZone ?? "Europe/Zurich") {
                        Text("Vérifiez les noms, l’e-mail et les champs renseignés. Une naissance doit être une date réelle, non future.")
                            .font(.footnote).foregroundStyle(DrivyTheme.danger)
                    }
                }
                readinessSection
            }
            if let onboarding = model.onboarding { onboardingSection(onboarding) }
            if let notice = model.notice, notice.status == "APPROVED" { noticeSection(notice) }
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
    }

    private func identitySection(_ profile: SchoolAdministrativeProfile) -> some View {
        Section {
            if model.editableFields.contains(.firstName) {
                TextField("Prénom", text: $model.draft.firstName).textContentType(.givenName)
                    .accessibilityIdentifier("profile-first-name")
                fieldExplanation(.firstName)
            } else { LabeledContent("Prénom", value: profile.firstName ?? "À compléter") }
            if model.editableFields.contains(.lastName) {
                TextField("Nom", text: $model.draft.lastName).textContentType(.familyName)
                    .accessibilityIdentifier("profile-last-name")
                fieldExplanation(.lastName)
            } else { LabeledContent("Nom", value: profile.lastName ?? "À compléter") }
        } header: { Text("Identité scolaire") }
        .disabled(!model.canMutate || confirmsSave)
    }

    @ViewBuilder private var contactSection: some View {
        if model.editableFields.contains(.contactEmail) || model.editableFields.contains(.contactPhone) {
            Section {
                if model.editableFields.contains(.contactEmail) {
                    TextField("E-mail", text: $model.draft.contactEmail)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("profile-email")
                    fieldExplanation(.contactEmail)
                }
                if model.editableFields.contains(.contactPhone) {
                    TextField("Téléphone", text: $model.draft.contactPhone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                        .accessibilityIdentifier("profile-phone")
                    fieldExplanation(.contactPhone)
                }
            } header: { Text("Contacts") }
            .disabled(!model.canMutate || confirmsSave)
        }
    }
    private var birthSection: some View {
        Section {
            TextField("JJ.MM.AAAA", text: $model.draft.birthDate).keyboardType(.numbersAndPunctuation)
                .accessibilityLabel("Date de naissance, jour point mois point année")
                .accessibilityIdentifier("profile-birth-date")
            fieldExplanation(.birthDate)
        } header: { Text("Date de naissance") }
        .disabled(!model.canMutate || confirmsSave)
    }
    private var addressSection: some View {
        Section {
            Toggle("Renseigner une adresse", isOn: $model.draft.hasAddress)
            if model.draft.hasAddress {
                TextField("Rue et numéro", text: $model.draft.address.line1).textContentType(.streetAddressLine1)
                TextField("Complément, facultatif", text: Binding(get: { model.draft.address.line2 ?? "" }, set: { model.draft.address.line2 = $0.isEmpty ? nil : $0 }))
                    .textContentType(.streetAddressLine2)
                TextField("Code postal", text: $model.draft.address.postalCode).textContentType(.postalCode)
                TextField("Localité", text: $model.draft.address.locality).textContentType(.addressCity)
                TextField("Code pays, deux lettres", text: $model.draft.address.countryCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            fieldExplanation(.postalAddress)
        } header: { Text("Adresse postale") }
        .disabled(!model.canMutate || confirmsSave)
    }
    @ViewBuilder private func fieldExplanation(_ field: SchoolProfileField) -> some View {
        if let rule = model.applicablePolicy?.fields.first(where: { $0.field == field }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(rule.requirement.label) · \(rule.stage.label)").font(.caption.weight(.medium))
                Text(rule.explanation).font(.footnote)
            }
            .foregroundStyle(DrivyTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private var readinessSection: some View {
        if let readiness = model.readiness {
            Section {
                Label(readiness.ready ? "Accès à l’espace scolaire possible" : "Accès à l’espace scolaire à préparer",
                    systemImage: readiness.ready ? "checkmark.circle" : "list.bullet.clipboard")
                    .foregroundStyle(readiness.ready ? DrivyTheme.success : DrivyTheme.text)
                SchoolProfileBlockers(blockers: readiness.blockers)
            } header: { Text("Prochaine étape") }
        }
    }
    private func onboardingSection(_ onboarding: SchoolOnboarding) -> some View {
        Section {
            Text(onboarding.status == "COMPLETED" ? "Votre arrivée est terminée" : "Votre arrivée dans l’école")
                .font(.headline)
            SchoolProfileBlockers(blockers: onboarding.pendingActions)
            if model.profile == nil && onboarding.kind == .student && !onboarding.pendingActions.isEmpty {
                Text("Vous pouvez compléter les informations demandées depuis votre dossier scolaire.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
            if onboarding.status != "COMPLETED" {
                Menu {
                    ForEach(SchoolOnboardingStep.allCases, id: \.self) { step in
                        Button(step.label) { Task { _ = await model.saveOnboarding(step: step, skipOptional: false) } }
                    }
                } label: { Label("Reprendre à l’étape : \(onboarding.currentStep.label)", systemImage: "list.number") }
                .frame(minHeight: 44).disabled(!model.canMutate)
                if !Set(["PHOTO", "NOTIFICATIONS", "DEVICE"]).isSubset(of: Set(onboarding.skippedOptionalSteps)) {
                    Button("Continuer sans photo ni réglages de l’appareil") {
                        Task { _ = await model.saveOnboarding(step: .review, skipOptional: true) }
                    }
                    .frame(minHeight: 44).disabled(!model.canMutate)
                    .accessibilityIdentifier("onboarding-skip-optional")
                }
                Button("Terminer mon arrivée") { confirmsComplete = true }
                    .frame(minHeight: 48)
                    .disabled(!model.canMutate || !onboarding.pendingActions.isEmpty)
                    .accessibilityIdentifier("onboarding-complete")
            }
        }
    }
    private func noticeSection(_ notice: SchoolDataPolicy) -> some View {
        Section {
            DisclosureGroup("Information sur vos données · version \(notice.version)") {
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
            if model.isLoading { Section { ProgressView("Vérification du dossier…") } }
            if let error = model.errorMessage {
                Section {
                    SchoolErrorNotice(message: error)
                    Button("Relire les informations de l’école") { Task { await model.load() } }
                        .frame(minHeight: 44).disabled(model.isBusy || model.isLoading)
                }
            }
            if let success = model.successMessage {
                Section { Label(success, systemImage: "checkmark.circle").foregroundStyle(DrivyTheme.success) }
            }
            if let pending = model.pending {
                Section {
                    Label("Demande à confirmer", systemImage: "clock.arrow.circlepath").font(.headline)
                    Text("Conservez cette référence. Une nouvelle modification sera possible après vérification du résultat.")
                    Text(pending.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                    if !pending.kind.isProfile { Text("Cette demande vient d’un autre écran de l’école.") }
                    if pending.scope != model.scope { Text("Vos accès ont changé depuis l’envoi. Le renvoi reste désactivé.") }
                    Button("Vérifier le résultat") { Task { await model.verifyPending() } }
                        .disabled(!model.canVerifyPending).frame(minHeight: 44)
                    if model.canRetryPending {
                        Button("Renvoyer la même demande") { Task { await model.retryPending() } }
                            .frame(minHeight: 44)
                    }
                } header: { Text("En attente") }
            }
        }
    }
}
struct SchoolProfileBlockers: View {
    let blockers: [SchoolActionBlocker]
    var body: some View {
        ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
            VStack(alignment: .leading, spacing: 4) {
                if let code = blocker.field, let field = SchoolProfileField(rawValue: code) {
                    Text("\(field.label) — \(blocker.message)")
                } else { Text(blocker.message) }
                if let purpose = blocker.purpose { Text(purpose).font(.footnote).foregroundStyle(DrivyTheme.muted) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
