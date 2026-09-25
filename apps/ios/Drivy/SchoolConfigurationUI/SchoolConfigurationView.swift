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
                if model.isLoading { Section { ProgressView("Vérification de l’école…").frame(maxWidth: .infinity, minHeight: 44) } }
                if let success = model.successMessage {
                    Section { DrivyFormMessage(text: success) }
                }
                if let school = model.school {
                    Section {
                        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                            Text(school.name).font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            DrivyStatusBadge(title: school.status == "ACTIVE" ? "École active" : school.status == "DRAFT" ? "En préparation" : "École inactive",
                                symbol: school.status == "ACTIVE" ? "checkmark.seal" : school.status == "DRAFT" ? "hammer" : "building.2",
                                tone: school.status == "ACTIVE" ? .success : school.status == "DRAFT" ? .warning : .neutral)
                            if school.status == "DRAFT" {
                                Text("Trois étapes : coordonnées, textes d’information, puis activation.")
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .listRowBackground(DrivyTheme.canvas)
                    identitySection
                    policySection
                    if let openProfilePolicy, model.policy?.status == "APPROVED" {
                        Section {
                            Button(action: openProfilePolicy) {
                                Label("Définir les champs du profil", systemImage: "list.bullet.rectangle")
                                    .frame(minHeight: 44)
                            }
                            .disabled(model.isBusy)
                        } footer: {
                            Text("Informations demandées aux élèves, avec leur utilité.")
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
            DrivyFormField(label: "Nom de l’école", text: $model.name, prompt: "Nom", identifier: "school-config-name")
                .textContentType(.organizationName)
            DrivyFormField(label: "E-mail de l’école", text: $model.contactEmail, prompt: "Adresse e-mail", identifier: "school-config-email")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            DrivyFormField(label: "Téléphone · facultatif", text: $model.contactPhone, prompt: "Numéro")
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
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
                DrivyStatusBadge(title: policy.status == "APPROVED" ? "Version \(policy.version) adoptée" : "Textes à préparer",
                    symbol: policy.status == "APPROVED" ? "checkmark.seal" : "doc.text",
                    tone: policy.status == "APPROVED" ? .success : .neutral)
            }
            if model.policy?.status != "APPROVED" || editingPolicy || model.policyIsEdited {
                policyFields
            } else if let policy = model.policy {
                DisclosureGroup("Consulter les textes adoptés") {
                    VStack(alignment: .leading, spacing: DrivySpacing.m) {
                        Text("Information des personnes").font(.headline)
                        Text(policy.noticeText).textSelection(.enabled)
                        Text("Conservation des données").font(.headline)
                        Text(policy.retentionText).textSelection(.enabled)
                        if let contact = policy.contactEmail { Text(contact).foregroundStyle(DrivyTheme.muted) }
                    }.padding(.vertical, DrivySpacing.s)
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
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text("Information des personnes").font(.subheadline).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                TextEditor(text: $model.noticeText)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Information des personnes")
                    .accessibilityIdentifier("school-config-notice")
            }
            .padding(.vertical, DrivySpacing.xxs)
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text("Conservation des données").font(.subheadline).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                TextEditor(text: $model.retentionText)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Conservation des données")
                    .accessibilityIdentifier("school-config-retention")
            }
            .padding(.vertical, DrivySpacing.xxs)
            DrivyFormField(label: "Contact pour les données", text: $model.policyContactEmail, prompt: "Adresse e-mail")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
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
                    DrivyFormMessage(text: "Préparation vérifiée")
                } else if model.school?.status == "DRAFT" {
                    ForEach(Array(readiness.activationBlockers.enumerated()), id: \.offset) { _, blocker in
                        Label(blocker.message, systemImage: "circle")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(DrivyTheme.text)
                    }
                }
                if !readiness.capabilities.isEmpty {
                    DisclosureGroup("Fonctions de l’école") {
                        ForEach(readiness.capabilities, id: \.capability) { capability in
                            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                                Label(capabilityTitle(capability.capability), systemImage: capability.ready ? "checkmark.circle" : "circle")
                                    .font(.headline)
                                Text(capability.ready ? "Disponible" : "À configurer pour l’utiliser")
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                ForEach(Array(capability.blockers.enumerated()), id: \.offset) { _, blocker in
                                    Text(blocker.message).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.vertical, DrivySpacing.xs)
                        }
                    }
                }
            }
            if model.identityIsEdited || model.policyIsEdited {
                DrivyFormMessage(text: "Des modifications attendent encore votre confirmation.", tone: .warning)
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
            DrivyPendingRequest(message: pendingMessage(pending), notes: pendingNotes(pending), reference: pending.id,
                verify: { Task { await model.verifyPending() } }, canVerify: !model.isBusy && !model.isLoading,
                verifyIdentifier: "school-config-verify-command",
                retry: pending.kind.isConfiguration && pending.scope == model.scope && !model.pendingRequiresReview
                    ? { Task { await model.retryPending() } } : nil,
                canRetry: model.canRetryPending,
                retryIdentifier: "school-config-retry-command")
        }
    }

    private func pendingMessage(_ pending: PendingSchoolCommand) -> String {
        if pending.scope != model.scope {
            return "Vos accès ont changé. Cette demande doit être vérifiée par l’école avant toute nouvelle modification."
        }
        if model.pendingRequiresReview {
            return "Cette demande nécessite une vérification par l’école. Sa référence est conservée pour retrouver son résultat."
        }
        return "La demande est protégée sur cet appareil. Vérifiez son résultat avant une nouvelle modification."
    }

    private func pendingNotes(_ pending: PendingSchoolCommand) -> [String] {
        var notes: [String] = []
        if pending.kind.isInvitation {
            notes.append("Une invitation attend sa confirmation. Vous pouvez vérifier son résultat ici ou retrouver sa demande dans Invitations.")
        }
        if pending.kind.isProfile {
            notes.append("Cette demande concerne un profil ou ses champs. Ouvrez cet écran pour reprendre la même demande.")
        }
        return notes
    }

    private func confirmationSheet(_ action: Confirmation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    switch action {
                    case .identity:
                        Text(model.name).font(.drivyTitle)
                        DrivyRowGroup {
                            DrivyContactRow(title: "E-mail", value: model.contactEmail, symbol: "envelope")
                            if !model.contactPhone.isEmpty { DrivyContactRow(title: "Téléphone", value: model.contactPhone, symbol: "phone") }
                        }
                        Text("Ces coordonnées remplaceront celles affichées par votre école.")
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    case .policy:
                        reviewText("Information des personnes", model.noticeText)
                        reviewText("Conservation des données", model.retentionText)
                        if !model.policyContactEmail.isEmpty { reviewText("Contact pour les données", model.policyContactEmail) }
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
                    if confirmationAttempted, let pending = model.pending {
                        DrivyPanel {
                            DrivyPendingRequest(message: "Le résultat reste à vérifier. Votre demande est conservée.",
                                reference: pending.id,
                                verify: {
                                    Task {
                                        await model.verifyPending()
                                        closeConfirmedSheet()
                                    }
                                }, canVerify: !model.isBusy && !model.isLoading,
                                retry: model.canRetryPending ? { Task { await model.retryPending(); closeConfirmedSheet() } } : nil)
                        }
                    }
                }
                .drivyPageContent()
            }
            .safeAreaInset(edge: .bottom) {
                DrivyFormActionBar {
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
                        DrivyBusyLabel(title: model.pending != nil ? "Demande à vérifier" : confirmationLabel(action),
                            isBusy: submittingConfirmation || model.isBusy)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!canConfirm(action) || submittingConfirmation)
                    .accessibilityIdentifier("school-config-confirm-\(action.rawValue)")
                }
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

    private func reviewText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(title).font(.headline).foregroundStyle(DrivyTheme.text).accessibilityAddTraits(.isHeader)
            Text(value).font(.body).foregroundStyle(DrivyTheme.text)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                Image(systemName: "building.2").font(.largeTitle).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text(school.name).font(.drivyScreenTitle).fixedSize(horizontal: false, vertical: true)
                    DrivyStatusBadge(title: school.status == "DRAFT" ? "En préparation" : "Inactive",
                        symbol: school.status == "DRAFT" ? "hammer" : "pause.circle", tone: school.status == "DRAFT" ? .warning : .neutral)
                }
                Text(school.status == "DRAFT" ? "Votre école se prépare." : "Cet espace n’est pas actif.")
                    .font(.drivyTitle)
                Text(mayConfigure ? "Vérifiez ses coordonnées, adoptez les textes d’information et confirmez son activation."
                     : "L’administration de votre école doit terminer sa préparation avant l’ouverture des dossiers.")
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
