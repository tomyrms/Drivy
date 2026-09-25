import SwiftUI

struct SchoolConfigurationView: View {
    @Bindable var model: SchoolConfigurationWorkspace
    let openSchool: () -> Void
    var openProfilePolicy: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation: Confirmation?
    @State private var editingPolicy = false
    @State private var submittingConfirmation = false
    @State private var confirmationAttempted = false

    private enum Confirmation: String, Identifiable {
        case identity, policy, activation
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let pending = model.pending { pendingSection(pending) }
                if let error = model.errorMessage {
                    Section {
                        SchoolErrorNotice(message: error,
                            retry: model.pending == nil ? { Task { await model.load() } } : nil)
                    }
                }
                if model.isLoading { Section { ProgressView("Vérification de l’école…") } }
                if let success = model.successMessage {
                    Section { Label(success, systemImage: "checkmark.circle.fill").foregroundStyle(DrivyTheme.success) }
                }
                if let school = model.school {
                    Section {
                        Text(school.name).font(.drivyTitle)
                        Label(school.status == "ACTIVE" ? "École active" : school.status == "DRAFT" ? "École en préparation" : "École inactive",
                              systemImage: school.status == "ACTIVE" ? "checkmark.seal" : "building.2")
                            .foregroundStyle(school.status == "ACTIVE" ? DrivyTheme.success : DrivyTheme.muted)
                        if school.status == "DRAFT" {
                            Text("Coordonnées, textes de l’école, puis activation.")
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                    }
                    identitySection
                    policySection
                    if let openProfilePolicy, model.policy?.status == "APPROVED" {
                        Section {
                            Button("Définir les champs du profil", action: openProfilePolicy)
                                .frame(minHeight: 48).disabled(model.isBusy)
                        }
                    }
                    reviewSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .navigationTitle(model.school?.status == "DRAFT" ? "Préparer l’école" : "Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isBusy { ProgressView().accessibilityLabel("Enregistrement en cours") }
                }
            }
            .task { await model.load() }
            .sheet(item: $confirmation) { action in confirmationSheet(action) }
            .interactiveDismissDisabled(model.isBusy)
        }
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
    }

    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nom de l’école").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                TextField("Nom", text: $model.name)
                    .textContentType(.organizationName).accessibilityIdentifier("school-config-name")
                    .accessibilityLabel("Nom de l’école")
            }.padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("E-mail de l’école").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                TextField("Adresse e-mail", text: $model.contactEmail)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("school-config-email").accessibilityLabel("E-mail de l’école")
            }.padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("Téléphone · facultatif").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                TextField("Numéro", text: $model.contactPhone)
                    .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    .accessibilityLabel("Téléphone, facultatif")
            }.padding(.vertical, 4)
            if let zone = model.school?.timeZone, let timeZone = TimeZone(identifier: zone) {
                LabeledContent("Fuseau horaire", value: timeZone.localizedName(for: .standard, locale: Locale(identifier: "fr_CH")) ?? zone)
                    .foregroundStyle(DrivyTheme.muted)
            }
            Button("Relire les modifications") { review(.identity) }
                .frame(minHeight: 44)
                .disabled(!model.identityIsValid || !model.identityIsEdited)
                .accessibilityIdentifier("school-config-save-identity")
        } header: { Text("Coordonnées") }
        .disabled(!model.mayEdit)
    }

    private var policySection: some View {
        Section {
            if let policy = model.policy {
                Label(policy.status == "APPROVED" ? "Version \(policy.version) adoptée" : "Textes à préparer",
                      systemImage: policy.status == "APPROVED" ? "checkmark.document" : "doc.text")
                    .foregroundStyle(policy.status == "APPROVED" ? DrivyTheme.success : DrivyTheme.muted)
            }
            if model.policy?.status != "APPROVED" || editingPolicy || model.policyIsEdited {
                policyFields
            } else if let policy = model.policy {
                DisclosureGroup("Consulter les textes adoptés") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Information des personnes").font(.headline)
                        Text(policy.noticeText).textSelection(.enabled)
                        Text("Conservation des données").font(.headline)
                        Text(policy.retentionText).textSelection(.enabled)
                        if let contact = policy.contactEmail { Text(contact).foregroundStyle(DrivyTheme.muted) }
                    }.padding(.vertical, 12)
                }
                Button("Préparer une nouvelle version") { editingPolicy = true }
                    .frame(minHeight: 44).disabled(!model.mayEdit)
            }
        } header: { Text("Information et conservation") } footer: {
            if model.policy?.status != "APPROVED" || editingPolicy || model.policyIsEdited {
                Text("L’adoption s’effectue après relecture des deux textes. La version précédente reste conservée.")
            }
        }
    }

    @ViewBuilder private var policyFields: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("Information des personnes").font(.headline)
                TextEditor(text: $model.noticeText)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Information des personnes")
                    .accessibilityIdentifier("school-config-notice")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Conservation des données").font(.headline)
                TextEditor(text: $model.retentionText)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Conservation des données")
                    .accessibilityIdentifier("school-config-retention")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Contact pour les données").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                TextField("Adresse e-mail", text: $model.policyContactEmail)
                    .textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("E-mail de contact pour les données")
            }.padding(.vertical, 4)
            Button("Relire et adopter les textes") { review(.policy) }
                .frame(minHeight: 44)
                .disabled(!model.policyIsValid || (model.policy?.status == "APPROVED" && !model.policyIsEdited))
                .accessibilityIdentifier("school-config-review-policy")
        }
        .disabled(!model.mayEdit)
    }

    private var reviewSection: some View {
        Section {
            if let readiness = model.readiness {
                if model.school?.status == "DRAFT", readiness.activationReady {
                    Label("Préparation vérifiée", systemImage: "checkmark.circle")
                        .foregroundStyle(DrivyTheme.success)
                } else if model.school?.status == "DRAFT" {
                    ForEach(Array(readiness.activationBlockers.enumerated()), id: \.offset) { _, blocker in
                        Label(blocker.message, systemImage: "exclamationmark.circle")
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(DrivyTheme.muted)
                    }
                }
                if !readiness.capabilities.isEmpty {
                    DisclosureGroup("Fonctions de l’école") {
                        ForEach(readiness.capabilities, id: \.capability) { capability in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(capabilityTitle(capability.capability), systemImage: capability.ready ? "checkmark.circle" : "circle")
                                    .font(.headline)
                                Text(capability.ready ? "Disponible" : "À configurer pour l’utiliser")
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                ForEach(Array(capability.blockers.enumerated()), id: \.offset) { _, blocker in
                                    Text(blocker.message).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
            if model.identityIsEdited || model.policyIsEdited {
                Text("Des modifications attendent encore votre confirmation.")
                    .foregroundStyle(DrivyTheme.muted)
            }
            if let setup = model.setup, setup.status != "COMPLETED" {
                Button("Enregistrer l’avancement") { Task { await model.saveProgress() } }
                    .frame(minHeight: 44)
                    .disabled(!model.mayEdit || model.identityIsEdited || model.policyIsEdited)
            }
            Button("Actualiser la vérification") { Task { await model.load() } }
                .frame(minHeight: 44)
                .disabled(model.isBusy || model.isLoading)
            if model.school?.status == "ACTIVE" {
                Button("Ouvrir mon école", action: openSchool)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("school-config-open-school")
            } else {
                Button("Relire et activer l’école") { review(.activation) }
                    .frame(minHeight: 44)
                    .disabled(!model.canActivate)
                    .accessibilityIdentifier("school-config-review-activation")
            }
        } header: { Text(model.school?.status == "ACTIVE" ? "Fonctionnement" : "Activation") } footer: {
            if model.school?.status == "DRAFT" {
                Text("L’activation ouvre l’espace de l’école. Les formations et les cours se préparent ensuite.")
            }
        }
    }

    private func pendingSection(_ pending: PendingSchoolCommand) -> some View {
        Section {
            Label("Confirmation en attente", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            if pending.kind.isInvitation {
                Text("Une invitation attend sa confirmation. Vous pouvez vérifier son résultat ici ou retrouver sa demande dans Invitations.")
            }
            if pending.kind.isProfile {
                Text("Cette demande concerne un profil ou ses champs. Ouvrez cet écran pour reprendre la même demande.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
            if pending.scope != model.scope {
                Text("Vos accès ont changé. Cette demande doit être vérifiée par l’école avant toute nouvelle modification.")
            } else if model.pendingRequiresReview {
                Text("Cette demande nécessite une vérification par l’école. Sa référence est conservée pour retrouver son résultat.")
            } else {
                Text("La demande est protégée sur cet appareil. Vérifiez son résultat avant une nouvelle modification.")
            }
            Button("Vérifier le résultat") { Task { await model.verifyPending() } }
                .frame(minHeight: 44).disabled(model.isBusy || model.isLoading)
                .accessibilityIdentifier("school-config-verify-command")
            if pending.kind.isConfiguration && pending.scope == model.scope && !model.pendingRequiresReview {
                Button("Renvoyer la même demande") { Task { await model.retryPending() } }
                    .frame(minHeight: 44).disabled(!model.canRetryPending)
                    .accessibilityIdentifier("school-config-retry-command")
            }
            DisclosureGroup("Référence de la demande") {
                Text(pending.id.uuidString)
                    .font(.caption.monospaced()).foregroundStyle(DrivyTheme.muted).textSelection(.enabled)
            }
        }
    }

    private func confirmationSheet(_ action: Confirmation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch action {
                    case .identity:
                        Text(model.name).font(.drivyTitle)
                        Text(model.contactEmail)
                        if !model.contactPhone.isEmpty { Text(model.contactPhone) }
                        Text("Ces coordonnées remplaceront celles affichées par votre école.")
                    case .policy:
                        Text("Information des personnes").font(.headline)
                        Text(model.noticeText).textSelection(.enabled)
                        Text("Conservation des données").font(.headline)
                        Text(model.retentionText).textSelection(.enabled)
                        if !model.policyContactEmail.isEmpty { Text(model.policyContactEmail) }
                        Text("En confirmant, vous adoptez exactement ces textes pour votre école. Leur version sera conservée.")
                            .font(.headline)
                    case .activation:
                        Text(model.school?.name ?? "Votre école").font(.drivyTitle)
                        Text("Les coordonnées et les textes d’information ont été vérifiés. L’activation ouvre l’espace de l’école à ses membres.")
                        Text("Les formations, réservations et cours se créent séparément.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                    if confirmationAttempted, let error = model.errorMessage {
                        SchoolErrorNotice(message: error, retry: model.pending == nil && model.needsReload ? {
                            Task { await model.load() }
                        } : nil)
                    }
                    if confirmationAttempted, model.pending != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Le résultat reste à vérifier. Votre demande est conservée.")
                                .font(.headline)
                            Button("Vérifier le résultat") {
                                Task {
                                    await model.verifyPending()
                                    closeConfirmedSheet()
                                }
                            }
                            .frame(minHeight: 44).disabled(model.isBusy || model.isLoading)
                            if model.canRetryPending {
                                Button("Renvoyer la même demande") {
                                    Task { await model.retryPending(); closeConfirmedSheet() }
                                }.frame(minHeight: 44)
                            }
                        }
                    }
                }
                .drivyPageContent()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard canConfirm(action), !submittingConfirmation else { return }
                    confirmationAttempted = true
                    submittingConfirmation = true
                    Task {
                        switch action {
                        case .identity: await model.saveIdentityAfterConfirmation()
                        case .policy: await model.adoptPolicyAfterReview()
                        case .activation: await model.activateAfterReview()
                        }
                        submittingConfirmation = false
                        closeConfirmedSheet()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if submittingConfirmation || model.isBusy { ProgressView() }
                        Text(submittingConfirmation || model.isBusy ? "Enregistrement…" : model.pending != nil ? "Résultat à vérifier" : confirmationLabel(action))
                    }
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!canConfirm(action) || submittingConfirmation)
                .accessibilityIdentifier("school-config-confirm-\(action.rawValue)")
                .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                .background(DrivyTheme.surface)
            }
            .background(DrivyTheme.surface)
            .navigationTitle(confirmationTitle(action))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(confirmationAttempted ? "Fermer" : "Retour") { confirmation = nil }
                        .disabled(submittingConfirmation || model.isBusy)
                }
            }
            .interactiveDismissDisabled(submittingConfirmation || model.isBusy)
        }
    }

    private func review(_ action: Confirmation) {
        confirmationAttempted = false
        confirmation = action
    }

    private func canConfirm(_ action: Confirmation) -> Bool {
        switch action {
        case .identity: model.mayEdit && model.identityIsValid && model.identityIsEdited
        case .policy: model.mayEdit && model.policyIsValid && (model.policy?.status != "APPROVED" || model.policyIsEdited)
        case .activation: model.canActivate
        }
    }

    private func closeConfirmedSheet() {
        guard model.pending == nil, model.successMessage != nil, model.school != nil,
              model.accessFailure == nil else { return }
        confirmation = nil
        editingPolicy = false
    }

    private func confirmationTitle(_ action: Confirmation) -> String {
        switch action {
        case .identity: "Vos coordonnées"
        case .policy: "Relire les textes"
        case .activation: "Activer l’école"
        }
    }

    private func capabilityTitle(_ capability: String) -> String {
        switch capability {
        case "CAN_USE_WORKSPACE": "Espace de l’école"
        case "CAN_PLAN_LESSON": "Planification des leçons"
        case "CAN_CAPTURE": "Enregistrement des trajets"
        case "CAN_PUBLISH_COURSE": "Publication des cours"
        default: "Autre fonction"
        }
    }

    private func confirmationLabel(_ action: Confirmation) -> String {
        switch action {
        case .identity: "Confirmer les coordonnées"
        case .policy: "J’adopte ces textes"
        case .activation: "Activer mon école"
        }
    }
}

struct SchoolPreparationLanding: View {
    let school: SchoolDetails
    let mayConfigure: Bool
    let configure: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "building.2").font(.largeTitle).foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                Text(school.name).font(.drivyScreenTitle)
                Text(school.status == "DRAFT" ? "Votre école se prépare." : "Cet espace n’est pas actif.")
                    .font(.drivyTitle)
                Text(mayConfigure ? "Vérifiez ses coordonnées, adoptez les textes d’information et confirmez son activation."
                     : "L’administration de votre école doit terminer sa préparation avant l’ouverture des dossiers.")
                    .foregroundStyle(DrivyTheme.muted)
                if mayConfigure {
                    Button("Préparer mon école", action: configure)
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("open-school-configuration")
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
    }
}
