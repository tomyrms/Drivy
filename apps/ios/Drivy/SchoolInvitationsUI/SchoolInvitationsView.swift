import SwiftUI

struct SchoolInvitationsView: View {
    @Bindable var model: SchoolInvitationWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                Section {
                    DrivyFormIntro(context: model.school?.name ?? "Votre école",
                        message: model.roles.contains("ADMIN") ? nil : "Vos invitations d’élèves")
                }
                .listRowBackground(DrivyTheme.canvas)
                if let pending = model.pending { InvitationPendingSection(model: model, pending: pending) }
                if let success = model.successMessage {
                    Section { DrivyFormMessage(text: success) }
                }
                if let error = model.errorMessage {
                    Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                }
                if model.isLoading { Section { ProgressView("Chargement des invitations…").frame(maxWidth: .infinity, minHeight: 44) } }
                if model.school != nil && model.invitations.isEmpty && !model.isLoading && model.errorMessage == nil {
                    Section {
                        DrivyEmptyState(title: "Aucune invitation",
                            message: "Invitez une personne à rejoindre l’école avec son propre compte.",
                            symbol: "envelope",
                            actionTitle: model.mayEdit ? "Inviter une personne" : nil,
                            action: { showsCreation = true })
                            .buttonStyle(.borderless)
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
                            if model.isLoadingMore { ProgressView("Chargement des invitations suivantes…") }
                            else { Text("Afficher la suite").font(.subheadline.weight(.semibold)) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DrivyTheme.surface)
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
        Section { InvitationPendingNotice(model: model, pending: pending) }
    }
}

/// Uncertain request in the shared presentation; the Section wrapper above is
/// for Forms and Lists, the notice alone sits in a DrivyPanel on a page.
private struct InvitationPendingNotice: View {
    @Bindable var model: SchoolInvitationWorkspace
    let pending: PendingSchoolCommand
    var body: some View {
        DrivyPendingRequest(
            message: pending.kind.isInvitation
                ? "La demande est conservée sur cet appareil. Vérifiez son résultat avant une nouvelle action."
                : "Une modification de l’école attend sa confirmation. La consultation des invitations reste disponible.",
            notes: notes,
            reference: pending.id,
            verify: { Task { await model.verifyPending() } }, canVerify: model.canVerifyPending,
            verifyIdentifier: "invitation-verify-command",
            retry: model.canRetryPending ? { Task { await model.retryPending() } } : nil,
            retryIdentifier: "invitation-retry-command")
    }
    private var notes: [String] {
        if pending.scope != model.scope { return ["Vos accès ont changé. La demande ne sera pas renvoyée avec ces nouveaux accès."] }
        if model.pendingRequiresReview { return ["La demande nécessite une vérification par l’école. Conservez sa référence."] }
        return []
    }
}

private struct InvitationRow: View {
    let invitation: SchoolInvitation
    private var statusTone: DrivyTone {
        switch invitation.status { case .pending: .accent; case .accepted: .success; case .revoked, .expired: .neutral }
    }
    private var statusSymbol: String {
        switch invitation.status { case .pending: "clock"; case .accepted: "checkmark"; case .revoked: "xmark"; case .expired: "hourglass" }
    }
    var body: some View {
        DrivyEntityRow(title: invitation.maskedEmail, meta: invitation.roleLabel, leading: .symbol("envelope"),
            badge: DrivyStatusBadge(title: invitation.status.label, symbol: statusSymbol, tone: statusTone))
    }
}

private struct InvitationDetailView: View {
    @Bindable var model: SchoolInvitationWorkspace
    let invitation: SchoolInvitation
    @State private var confirmsResend = false
    @State private var showsRevocation = false

    private var statusTone: DrivyTone {
        switch invitation.status { case .pending: .accent; case .accepted: .success; case .revoked, .expired: .neutral }
    }
    private var statusSymbol: String {
        switch invitation.status { case .pending: "clock"; case .accepted: "checkmark"; case .revoked: "xmark"; case .expired: "hourglass" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Text(invitation.maskedEmail).font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    DrivyStatusBadge(title: invitation.status.label, symbol: statusSymbol, tone: statusTone)
                }
                DrivyRowGroup {
                    DrivyContactRow(title: "Rôles", value: invitation.roleLabel, symbol: "person.crop.circle")
                    DrivyContactRow(title: "Échéance du lien", value: invitation.expirationLabel(timeZone: model.school?.timeZone ?? "Europe/Zurich"),
                        symbol: "calendar")
                }
                if let error = model.errorMessage { SchoolErrorNotice(message: error) }
                if let pending = model.pending { DrivyPanel { InvitationPendingNotice(model: model, pending: pending) } }
                if let success = model.successMessage {
                    DrivyInlineMessage(text: success)
                }
                if invitation.status.canBeManaged {
                    VStack(spacing: DrivySpacing.s) {
                        Button { confirmsResend = true } label: { Label("Renvoyer l’invitation", systemImage: "paperplane") }
                            .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canManage(invitation))
                            .accessibilityIdentifier("invitation-resend")
                        Button(role: .destructive) { showsRevocation = true } label: {
                            Label("Révoquer l’invitation", systemImage: "xmark.circle")
                        }
                        .buttonStyle(DrivyDestructiveButtonStyle())
                        .disabled(!model.canManage(invitation))
                        .accessibilityIdentifier("invitation-revoke")
                    }
                }
                Text(invitation.status == .accepted
                     ? "L’invitation a été acceptée. Les formations et les affectations se gèrent séparément."
                     : invitation.status == .revoked ? "Ce lien ne permet plus de rejoindre l’école. Une nouvelle invitation est nécessaire."
                     : "Le renvoi remplace le lien précédent. La révocation empêche de rejoindre l’école avec ce lien.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
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
                Section {
                    DrivyFormIntro(context: model.school?.name ?? "Votre école",
                        message: "La personne rejoindra l’école avec son propre compte, après avoir accepté l’invitation.")
                }
                .listRowBackground(DrivyTheme.canvas)
                Section {
                    DrivyFormField(label: "Adresse e-mail", text: $model.email, prompt: "nom@exemple.ch", identifier: "invitation-email")
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Destinataire") }
                .disabled(!model.mayEdit)
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
                DrivyFormActionBar(hint: creationHint) {
                    Button {
                        reviewedDraft = ReviewedDraft(email: model.email.trimmingCharacters(in: .whitespacesAndNewlines),
                            roles: model.selectedRoles, school: model.school?.name ?? "Votre école")
                    } label: {
                        DrivyBusyLabel(title: "Relire l’invitation", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.mayEdit || !model.draftIsValid)
                    .accessibilityIdentifier("invitation-review")
                }
            }
            .navigationTitle("Inviter une personne").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .sheet(item: $reviewedDraft) { draft in
                NavigationStack {
                    Form {
                        Section {
                            LabeledContent("École", value: draft.school)
                            LabeledContent("Adresse e-mail") { Text(draft.email).textSelection(.enabled) }
                            LabeledContent("Rôles", value: SchoolInvitationRole.allCases.filter { draft.roles.contains($0) }.map(\.label).joined(separator: ", "))
                        } header: { Text("Votre invitation") } footer: {
                            Text("L’école enregistrera l’invitation et préparera son e-mail. La réception par le destinataire n’est pas garantie par cet écran.")
                        }
                        if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
                        if let pending = model.pending { InvitationPendingSection(model: model, pending: pending) }
                        else if model.needsReload {
                            Section { Button("Actualiser avant de confirmer") { Task { await model.load() } }.disabled(model.isBusy || model.isLoading) }
                        }
                    }
                    .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
                    .safeAreaInset(edge: .bottom) {
                        DrivyFormActionBar {
                            Button {
                                didSubmit = true
                                Task {
                                    if await model.inviteAfterConfirmation(email: draft.email, roles: draft.roles) {
                                        reviewedDraft = nil; dismiss()
                                    }
                                }
                            } label: {
                                DrivyBusyLabel(title: "Confirmer l’invitation", isBusy: model.isBusy)
                            }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.mayEdit)
                                .accessibilityIdentifier("invitation-confirm-create")
                        }
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

    private var creationHint: String? {
        if model.selectedRoles.isEmpty { return "Choisissez au moins un rôle." }
        if !model.email.isEmpty && !model.draftIsValid { return "Vérifiez l’adresse e-mail." }
        return nil
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
                    DrivyFormIntro(context: invitation.maskedEmail,
                        message: "La personne ne pourra plus rejoindre l’école avec ce lien.")
                }
                .listRowBackground(DrivyTheme.canvas)
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
                DrivyFormActionBar(hint: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Indiquez le motif de la révocation." : nil) {
                    Button(role: .destructive) { confirms = true } label: {
                        DrivyBusyLabel(title: "Révoquer l’invitation", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyDestructiveButtonStyle())
                    .disabled(!model.canManage(invitation) || !SchoolInvitationWorkspace.reasonIsValid(reason))
                    .accessibilityIdentifier("invitation-confirm-revoke")
                }
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
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
    }
}
