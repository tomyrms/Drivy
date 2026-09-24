import SwiftUI

struct SchoolInvitationsView: View {
    @Bindable var model: SchoolInvitationWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                Section {
                    Text(model.school?.name ?? "Votre école").font(.headline)
                    if !model.roles.contains("ADMIN") {
                        Text("Vos invitations d’élèves").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
                if let pending = model.pending { InvitationPendingSection(model: model, pending: pending) }
                if let success = model.successMessage {
                    Section { Label(success, systemImage: "checkmark.circle").foregroundStyle(DrivyTheme.success) }
                }
                if let error = model.errorMessage {
                    Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                }
                if model.isLoading { Section { ProgressView("Chargement des invitations…") } }
                if model.school != nil && model.invitations.isEmpty && !model.isLoading && model.errorMessage == nil {
                    Section {
                        Text("Aucune invitation enregistrée.").foregroundStyle(DrivyTheme.muted)
                        Button("Inviter une personne") { showsCreation = true }.disabled(!model.mayEdit).frame(minHeight: 44)
                    }
                }
                Section {
                    ForEach(model.invitations) { invitation in
                        NavigationLink(value: invitation.id) {
                            InvitationRow(invitation: invitation)
                        }
                        .accessibilityIdentifier("invitation-\(invitation.id.uuidString)")
                    }
                    if model.nextCursor != nil {
                        Button { Task { await model.loadMore() } } label: {
                            if model.isLoadingMore { ProgressView("Chargement…") }
                            else { Text("Afficher la suite") }
                        }
                        .frame(minHeight: 44)
                        .disabled(model.isLoadingMore || model.isLoading || model.isBusy)
                        .accessibilityIdentifier("invitations-more")
                    }
                } footer: {
                    Text("Les adresses sont masquées. Une invitation n’atteste pas la réception de l’e-mail.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .refreshable { await model.load() }
            .navigationTitle("Invitations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsCreation = true } label: { Label("Inviter", systemImage: "plus") }
                        .disabled(!model.mayEdit)
                        .accessibilityIdentifier("invitation-create")
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 460)
        } detail: {
            if let invitation = model.selectedInvitation {
                InvitationDetailView(model: model, invitation: invitation)
            } else {
                ContentUnavailableView("Choisissez une invitation", systemImage: "envelope.open",
                    description: Text("Son état et les actions disponibles apparaîtront ici."))
                    .background(DrivyTheme.canvas)
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .task { await model.load() }
        .sheet(isPresented: $showsCreation) { InvitationCreationView(model: model) }
    }

}

private struct InvitationPendingSection: View {
    @Bindable var model: SchoolInvitationWorkspace
    let pending: PendingSchoolCommand
    var body: some View {
        Section {
            Label("Résultat à vérifier", systemImage: "clock.arrow.circlepath").font(.headline)
            Text(pending.kind.isInvitation
                 ? "La demande est conservée sur cet appareil. Vérifiez son résultat avant une nouvelle action."
                 : "Une modification de l’école attend sa confirmation. La consultation des invitations reste disponible.")
                .font(.subheadline)
            if pending.scope != model.scope {
                Text("Vos accès ont changé. La demande ne sera pas renvoyée avec ces nouveaux accès.")
                    .font(.subheadline)
            } else if model.pendingRequiresReview {
                Text("La demande nécessite une vérification par l’école. Conservez sa référence.")
                    .font(.subheadline)
            }
            Button("Vérifier le résultat") { Task { await model.verifyPending() } }
                .frame(minHeight: 44).disabled(!model.canVerifyPending)
                .accessibilityIdentifier("invitation-verify-command")
            if model.canRetryPending {
                Button("Renvoyer la même demande") { Task { await model.retryPending() } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("invitation-retry-command")
            }
            DisclosureGroup("Référence de la demande") {
                Text(pending.id.uuidString).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(DrivyTheme.muted)
            }
        }
    }
}

private struct InvitationRow: View {
    let invitation: SchoolInvitation
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(invitation.maskedEmail).font(.headline)
            Text(invitation.roleLabel).font(.subheadline)
            Label(invitation.status.label, systemImage: invitation.status == .accepted ? "checkmark.circle" : "envelope")
                .font(.caption.weight(.medium))
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct InvitationDetailView: View {
    @Bindable var model: SchoolInvitationWorkspace
    let invitation: SchoolInvitation
    @State private var confirmsResend = false
    @State private var showsRevocation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(invitation.maskedEmail).font(.title2.weight(.bold)).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 18) {
                    LabeledContent("État", value: invitation.status.label)
                    Divider()
                    LabeledContent("Rôles", value: invitation.roleLabel)
                    Divider()
                    LabeledContent("Échéance du lien", value: invitation.expirationLabel(timeZone: model.school?.timeZone ?? "Europe/Zurich"))
                }
                if let error = model.errorMessage { SchoolErrorNotice(message: error) }
                if let pending = model.pending { InvitationPendingSection(model: model, pending: pending) }
                if let success = model.successMessage {
                    Label(success, systemImage: "checkmark.circle").foregroundStyle(DrivyTheme.success)
                }
                if invitation.status.canBeManaged {
                    Button { confirmsResend = true } label: { Label("Renvoyer l’invitation", systemImage: "paperplane") }
                        .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canManage(invitation))
                        .accessibilityIdentifier("invitation-resend")
                    Button(role: .destructive) { showsRevocation = true } label: {
                        Label("Révoquer l’invitation", systemImage: "xmark.circle").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .disabled(!model.canManage(invitation))
                    .accessibilityIdentifier("invitation-revoke")
                }
                Text(invitation.status == .accepted
                     ? "L’invitation a été acceptée. Les formations et les affectations se gèrent séparément."
                     : invitation.status == .revoked ? "Ce lien ne permet plus de rejoindre l’école. Une nouvelle invitation est nécessaire."
                     : "Le renvoi remplace le lien précédent. La révocation empêche de rejoindre l’école avec ce lien.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            .padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Renvoyer cette invitation ?", isPresented: $confirmsResend) {
            Button("Annuler", role: .cancel) {}
            Button("Renvoyer") { Task { await model.resendAfterConfirmation(invitation) } }
        } message: {
            Text("\(invitation.maskedEmail) · \(invitation.roleLabel)\n\nL’ancien lien cessera de fonctionner. Un nouveau lien sera préparé pour cette personne.")
        }
        .sheet(isPresented: $showsRevocation) { InvitationRevocationView(model: model, invitation: invitation) }
    }
}

struct InvitationCreationView: View {
    @Bindable var model: SchoolInvitationWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var reviewedDraft: ReviewedDraft?
    @State private var didSubmit = false

    private struct ReviewedDraft: Identifiable {
        let id = UUID()
        let email: String
        let roles: Set<SchoolInvitationRole>
        let school: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(model.school?.name ?? "Votre école").font(.headline) }
                Section("Destinataire") {
                    TextField("Adresse e-mail", text: $model.email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("invitation-email")
                }.disabled(!model.mayEdit)
                Section {
                    ForEach(model.allowedRoles, id: \.self) { role in
                        Toggle(role.label, isOn: Binding(get: { model.selectedRoles.contains(role) }, set: { enabled in
                            if enabled { model.selectedRoles.insert(role) } else { model.selectedRoles.remove(role) }
                        }))
                        .accessibilityIdentifier("invitation-role-\(role.rawValue.lowercased())")
                    }
                } header: { Text("Rôles dans cette école") } footer: {
                    Text("Les rôles seront attribués après acceptation par la personne invitée. Aucun dossier pédagogique ni formation n’est créé par l’envoi.")
                }.disabled(!model.mayEdit)
                if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
                if let pending = model.pending {
                    InvitationPendingSection(model: model, pending: pending)
                } else if model.needsReload {
                    Section { Button("Actualiser avant de confirmer") { Task { await model.load() } } }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.selectedRoles.isEmpty {
                        Text("Choisissez au moins un rôle.").font(.footnote).foregroundStyle(DrivyTheme.muted)
                    } else if !model.email.isEmpty && !model.draftIsValid {
                        Text("Vérifiez l’adresse e-mail.").font(.footnote).foregroundStyle(DrivyTheme.muted)
                    }
                    Button {
                        reviewedDraft = ReviewedDraft(email: model.email.trimmingCharacters(in: .whitespacesAndNewlines),
                            roles: model.selectedRoles, school: model.school?.name ?? "Votre école")
                    } label: {
                        if model.isBusy { ProgressView("Enregistrement…") }
                        else { Text("Relire l’invitation") }
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.mayEdit || !model.draftIsValid)
                    .accessibilityIdentifier("invitation-review")
                }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity).background(DrivyTheme.surface)
            }
            .navigationTitle("Inviter une personne").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .sheet(item: $reviewedDraft) { draft in
                NavigationStack {
                    Form {
                        Section("Votre invitation") {
                            Text(draft.school).font(.headline)
                            Text(draft.email).textSelection(.enabled)
                            Text(SchoolInvitationRole.allCases.filter { draft.roles.contains($0) }.map(\.label).joined(separator: ", "))
                        }
                        Section {
                            Text("L’école enregistrera l’invitation et préparera son e-mail. La réception par le destinataire n’est pas garantie par cet écran.")
                                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        }
                        if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
                        if let pending = model.pending { InvitationPendingSection(model: model, pending: pending) }
                        else if model.needsReload {
                            Section { Button("Actualiser avant de confirmer") { Task { await model.load() } }.disabled(model.isBusy || model.isLoading) }
                        }
                    }
                    .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            didSubmit = true
                            Task {
                                if await model.inviteAfterConfirmation(email: draft.email, roles: draft.roles) {
                                    reviewedDraft = nil; dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if model.isBusy { ProgressView() }
                                Text(model.isBusy ? "Enregistrement…" : "Confirmer l’invitation")
                            }
                        }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.mayEdit)
                            .accessibilityIdentifier("invitation-confirm-create")
                            .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity).background(DrivyTheme.surface)
                    }
                    .navigationTitle("Votre confirmation").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Retour") { reviewedDraft = nil }.disabled(model.isBusy) } }
                }.interactiveDismissDisabled(model.isBusy)
            }
            .onChange(of: model.isLoading) { _, loading in
                if didSubmit && !loading && !model.needsReload && model.pending == nil && model.successMessage != nil {
                    reviewedDraft = nil; dismiss()
                }
            }
        }
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }
}

private struct InvitationRevocationView: View {
    @Bindable var model: SchoolInvitationWorkspace
    let invitation: SchoolInvitation
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirms = false
    @State private var didSubmit = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(invitation.maskedEmail).font(.headline)
                    Text("La personne ne pourra plus rejoindre l’école avec ce lien.")
                }
                Section("Motif") {
                    TextField("Expliquez pourquoi ce lien doit être révoqué", text: $reason, axis: .vertical).lineLimit(3...8)
                        .accessibilityLabel("Motif de révocation").accessibilityIdentifier("invitation-revoke-reason")
                    if reason.unicodeScalars.count > 800 {
                        Text("\(reason.unicodeScalars.count)/1 000 caractères").font(.caption)
                            .foregroundStyle(reason.unicodeScalars.count > 1000 ? DrivyTheme.danger : DrivyTheme.muted)
                    }
                }.disabled(!model.mayEdit)
                if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
                if let pending = model.pending {
                    InvitationPendingSection(model: model, pending: pending)
                } else if model.needsReload {
                    Section { Button("Actualiser avant de confirmer") { Task { await model.load() } } }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Indiquez le motif de la révocation.").font(.footnote).foregroundStyle(DrivyTheme.muted)
                    }
                    Button("Révoquer l’invitation", role: .destructive) { confirms = true }
                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
                        .disabled(!model.canManage(invitation) || !SchoolInvitationWorkspace.reasonIsValid(reason))
                        .accessibilityIdentifier("invitation-confirm-revoke")
                }.padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity).background(DrivyTheme.surface)
            }
            .navigationTitle("Révoquer le lien").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .alert("Confirmer la révocation ?", isPresented: $confirms) {
                Button("Annuler", role: .cancel) {}
                Button("Révoquer", role: .destructive) {
                    let confirmedReason = reason
                    didSubmit = true
                    Task { if await model.revokeAfterConfirmation(invitation, reason: confirmedReason) { dismiss() } }
                }
            } message: { Text("\(invitation.maskedEmail)\n\n\(reason)") }
            .onChange(of: model.isLoading) { _, loading in
                if didSubmit && !loading && model.pending == nil,
                   model.invitations.contains(where: { $0.id == invitation.id && $0.status == .revoked }) {
                    dismiss()
                }
            }
        }
        .interactiveDismissDisabled(model.isBusy)
    }
}
