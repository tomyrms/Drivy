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
                if let pending = model.pending { pendingSection(pending) }
                if let success = model.successMessage {
                    Section { Label(success, systemImage: "checkmark.circle").foregroundStyle(DrivyTheme.success) }
                }
                if let error = model.errorMessage {
                    Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                }
                if model.isLoading { Section { ProgressView("Chargement des invitations…") } }
                if model.invitations.isEmpty && !model.isLoading && model.errorMessage == nil {
                    ContentUnavailableView("Aucune invitation", systemImage: "envelope",
                        description: Text("Invitez une personne à rejoindre votre école."))
                }
                Section {
                    ForEach(model.invitations) { invitation in
                        NavigationLink(value: invitation.id) {
                            InvitationRow(invitation: invitation, selected: model.selectedID == invitation.id)
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
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
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
                ContentUnavailableView("Les invitations de votre école", systemImage: "envelope.open",
                    description: Text("Choisissez une invitation pour consulter son état ou gérer son lien."))
                    .background(DrivyTheme.canvas)
            }
        }
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
        .task { await model.load() }
        .sheet(isPresented: $showsCreation) { InvitationCreationView(model: model) }
    }

    private func pendingSection(_ pending: PendingSchoolCommand) -> some View {
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
            Text("Référence : \(pending.id.uuidString)")
                .font(.caption).textSelection(.enabled).foregroundStyle(DrivyTheme.muted)
        }
    }
}

private struct InvitationRow: View {
    let invitation: SchoolInvitation
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(invitation.maskedEmail).font(.headline)
            Text(invitation.roleLabel).font(.subheadline)
            Label(invitation.status.label, systemImage: invitation.status == .accepted ? "checkmark.circle" : "envelope")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(selected ? DrivyTheme.onAccent : DrivyTheme.text)
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
                Image(systemName: "envelope.open").font(.largeTitle).foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                Text(invitation.maskedEmail).font(.title2.weight(.bold)).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("État", value: invitation.status.label)
                    LabeledContent("Rôles", value: invitation.roleLabel)
                    LabeledContent("Échéance du lien", value: invitation.expirationLabel(timeZone: model.school?.timeZone ?? "Europe/Zurich"))
                }
                .padding(20).background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                if let error = model.errorMessage { SchoolErrorNotice(message: error) }
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
                if model.pending != nil {
                    Section { Text("Une demande attend sa confirmation. Revenez à la liste pour vérifier son résultat.") }
                } else if model.needsReload {
                    Section { Button("Actualiser avant de confirmer") { Task { await model.load() } } }
                }
                Section {
                    Button {
                        reviewedDraft = ReviewedDraft(email: model.email.trimmingCharacters(in: .whitespacesAndNewlines),
                            roles: model.selectedRoles, school: model.school?.name ?? "Votre école")
                    } label: {
                        if model.isBusy { ProgressView("Enregistrement…") }
                        else { Text("Relire l’invitation") }
                    }
                    .frame(minHeight: 44).disabled(!model.mayEdit || !model.draftIsValid)
                    .accessibilityIdentifier("invitation-review")
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Inviter une personne").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .sheet(item: $reviewedDraft) { draft in
                NavigationStack {
                    Form {
                        Section("Votre invitation") {
                            Text(draft.school).font(.headline)
                            Text(draft.email).textSelection(.enabled)
                            Text(SchoolInvitationRole.allCases.filter { draft.roles.contains($0) }.map(\.label).joined(separator: ", "))
                        }
                        Section {
                            Button("Confirmer l’invitation") {
                                reviewedDraft = nil
                                Task { if await model.inviteAfterConfirmation(email: draft.email, roles: draft.roles) { dismiss() } }
                            }
                            .frame(minHeight: 44).disabled(!model.mayEdit)
                            .accessibilityIdentifier("invitation-confirm-create")
                        } footer: {
                            Text("L’école enregistrera l’invitation et préparera son e-mail. La réception par le destinataire n’est pas garantie par cet écran.")
                        }
                    }
                    .navigationTitle("Votre confirmation").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { reviewedDraft = nil } } }
                }
            }
        }
        .tint(DrivyTheme.accent)
    }
}

private struct InvitationRevocationView: View {
    @Bindable var model: SchoolInvitationWorkspace
    let invitation: SchoolInvitation
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirms = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(invitation.maskedEmail).font(.headline)
                    Text("La personne ne pourra plus rejoindre l’école avec ce lien.")
                }
                Section("Motif") {
                    TextEditor(text: $reason).frame(minHeight: 140)
                        .accessibilityLabel("Motif de révocation").accessibilityIdentifier("invitation-revoke-reason")
                    Text("1 000 caractères maximum").font(.caption).foregroundStyle(DrivyTheme.muted)
                }.disabled(!model.mayEdit)
                if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
                if model.pending != nil {
                    Section { Text("La demande est conservée. Revenez à la liste pour vérifier son résultat.") }
                } else if model.needsReload {
                    Section { Button("Actualiser avant de confirmer") { Task { await model.load() } } }
                }
                Section {
                    Button("Révoquer l’invitation", role: .destructive) { confirms = true }
                        .frame(minHeight: 44)
                        .disabled(!model.canManage(invitation) || !SchoolInvitationWorkspace.reasonIsValid(reason))
                        .accessibilityIdentifier("invitation-confirm-revoke")
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Révoquer le lien").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .alert("Confirmer la révocation ?", isPresented: $confirms) {
                Button("Annuler", role: .cancel) {}
                Button("Révoquer", role: .destructive) {
                    let confirmedReason = reason
                    Task { if await model.revokeAfterConfirmation(invitation, reason: confirmedReason) { dismiss() } }
                }
            } message: { Text("\(invitation.maskedEmail)\n\n\(reason)") }
        }
    }
}
