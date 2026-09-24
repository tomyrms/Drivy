import SwiftUI

struct SchoolConfigurationView: View {
    @Bindable var model: SchoolConfigurationWorkspace
    let openSchool: () -> Void
    var openProfilePolicy: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation: Confirmation?

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
                    Section { Label(success, systemImage: "checkmark.circle").foregroundStyle(DrivyTheme.success) }
                }
                if let school = model.school {
                    Section {
                        Text(school.name).font(.title2.weight(.bold))
                        Label(school.status == "ACTIVE" ? "École active" : "École en préparation",
                              systemImage: school.status == "ACTIVE" ? "checkmark.seal" : "building.2")
                            .foregroundStyle(DrivyTheme.muted)
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
            .navigationTitle("Préparer l’école")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isBusy { ProgressView().accessibilityLabel("Enregistrement en cours") }
                }
            }
            .task { await model.load() }
            .sheet(item: $confirmation) { action in confirmationSheet(action) }
        }
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
    }

    private var identitySection: some View {
        Section {
            TextField("Nom de l’école", text: $model.name)
                .textContentType(.organizationName).accessibilityIdentifier("school-config-name")
            TextField("E-mail de l’école", text: $model.contactEmail)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("school-config-email")
            TextField("Téléphone, facultatif", text: $model.contactPhone)
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
            if let zone = model.school?.timeZone, let timeZone = TimeZone(identifier: zone) {
                LabeledContent("Fuseau horaire", value: timeZone.localizedName(for: .standard, locale: Locale(identifier: "fr_CH")) ?? zone)
                    .foregroundStyle(DrivyTheme.muted)
            }
            Button("Enregistrer les coordonnées") { confirmation = .identity }
                .frame(minHeight: 44)
                .disabled(!model.identityIsValid || !model.identityIsEdited)
                .accessibilityIdentifier("school-config-save-identity")
        } header: { Text("1. Coordonnées") }
        .disabled(!model.mayEdit)
    }

    private var policySection: some View {
        Section {
            if let policy = model.policy {
                Label(policy.status == "APPROVED" ? "Version \(policy.version) adoptée" : "Textes à préparer",
                      systemImage: policy.status == "APPROVED" ? "checkmark.document" : "doc.text")
                    .foregroundStyle(DrivyTheme.muted)
            }
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
            TextField("E-mail de contact pour les données", text: $model.policyContactEmail)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Relire et adopter les textes") { confirmation = .policy }
                .frame(minHeight: 44)
                .disabled(!model.policyIsValid || (model.policy?.status == "APPROVED" && !model.policyIsEdited))
                .accessibilityIdentifier("school-config-review-policy")
        } header: { Text("2. Information et conservation") } footer: {
            Text("Rédigez les textes de votre école. Leur adoption nécessite votre confirmation après relecture. Aucun texte n’est approuvé automatiquement.")
        }
        .disabled(!model.mayEdit)
    }

    private var reviewSection: some View {
        Section {
            if let readiness = model.readiness {
                if readiness.activationReady {
                    Label("Préparation vérifiée", systemImage: "checkmark.circle")
                        .foregroundStyle(DrivyTheme.success)
                } else {
                    ForEach(Array(readiness.activationBlockers.enumerated()), id: \.offset) { _, blocker in
                        Label(blocker.message, systemImage: "exclamationmark.circle")
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(DrivyTheme.muted)
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
                Button("Relire et activer l’école") { confirmation = .activation }
                    .frame(minHeight: 44)
                    .disabled(!model.canActivate)
                    .accessibilityIdentifier("school-config-review-activation")
            }
        } header: { Text("3. Vérification") } footer: {
            Text("L’activation ouvre l’espace de l’école. Elle ne crée aucun élève et ne publie aucun cours.")
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
            Text("Référence : \(pending.id.uuidString)")
                .font(.caption).foregroundStyle(DrivyTheme.muted).textSelection(.enabled)
        }
    }

    private func confirmationSheet(_ action: Confirmation) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch action {
                    case .identity:
                        Text(model.name).font(.title2.weight(.bold))
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
                        Text(model.school?.name ?? "Votre école").font(.title2.weight(.bold))
                        Text("Vous avez vérifié les coordonnées et adopté les textes d’information et de conservation. Confirmez l’ouverture de l’espace de l’école.")
                    }
                    Button(confirmationLabel(action)) {
                        confirmation = nil
                        Task {
                            switch action {
                            case .identity: await model.saveIdentityAfterConfirmation()
                            case .policy: await model.adoptPolicyAfterReview()
                            case .activation: await model.activateAfterReview()
                            }
                        }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("school-config-confirm-\(action.rawValue)")
                }
                .padding(24).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
            .navigationTitle("Votre confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { confirmation = nil } }
            }
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
                Text(school.name).font(.largeTitle.weight(.bold))
                Text(school.status == "DRAFT" ? "Votre école se prépare." : "Cet espace n’est pas actif.")
                    .font(.title2.weight(.semibold))
                Text(mayConfigure ? "Vérifiez ses coordonnées, adoptez les textes d’information et confirmez son activation."
                     : "L’administration de votre école doit terminer sa préparation avant l’ouverture des dossiers.")
                    .foregroundStyle(DrivyTheme.muted)
                if mayConfigure {
                    Button("Préparer mon école", action: configure)
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("open-school-configuration")
                }
            }
            .padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
    }
}
