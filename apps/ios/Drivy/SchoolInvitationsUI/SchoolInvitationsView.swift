import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SchoolInvitationsView: View {
    @Bindable var model: SchoolInvitationWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var showsCreation = false

    /// A code renewed from the detail opens here; the creation sheet shows its own.
    private var issuedCode: Binding<SchoolIssuedInvitationCode?> {
        Binding(get: { showsCreation ? nil : model.issuedCode }, set: { if $0 == nil { model.dismissIssuedCode() } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedID) {
                if let pending = model.pending { InvitationPendingSection(model: model, pending: pending) }
                if model.pending == nil, model.codeRecovery != nil, !showsCreation {
                    Section { InvitationCodeRecovery(model: model) }
                }
                if let success = model.successMessage {
                    Section { DrivyFormMessage(text: success) }
                }
                if let error = model.errorMessage {
                    Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                }
                if model.isLoading { Section { ProgressView().frame(maxWidth: .infinity, minHeight: 44) } }
                if model.school != nil && model.invitations.isEmpty && !model.isLoading && model.errorMessage == nil {
                    Section {
                        DrivyEmptyState(title: "Aucune invitation", symbol: "envelope",
                            actionTitle: model.mayEdit ? "Inviter un élève" : nil,
                            action: { showsCreation = true })
                            .buttonStyle(.borderless)
                    }
                }
                Section {
                    ForEach(model.invitations) { invitation in
                        NavigationLink(value: invitation.id) {
                            InvitationRow(invitation: invitation, training: model.trainingLabel(invitation))
                        }
                        .accessibilityIdentifier("invitation-\(invitation.id.uuidString)")
                    }
                    if model.nextCursor != nil {
                        Button { Task { await model.loadMore() } } label: {
                            if model.isLoadingMore { ProgressView() }
                            else { Text("Afficher la suite").font(.subheadline.weight(.semibold)) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(model.isLoadingMore || model.isLoading || model.isBusy)
                        .accessibilityIdentifier("invitations-more")
                    }
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
                    Button { showsCreation = true } label: { Label("Inviter un élève", systemImage: "plus") }
                        .disabled(!model.mayEdit)
                        .accessibilityIdentifier("invitation-create")
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 460)
        } detail: {
            if let invitation = model.selectedInvitation {
                InvitationDetailView(model: model, invitation: invitation)
            } else {
                ContentUnavailableView("Choisissez une invitation", systemImage: "envelope.open")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DrivyTheme.surface)
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .task { await model.load() }
        .sheet(isPresented: $showsCreation, onDismiss: { model.dismissIssuedCode() }) { InvitationCreationView(model: model) }
        .sheet(item: issuedCode) { issued in
            NavigationStack {
                InvitationCodeResultView(issued: issued, schoolName: model.school?.name)
                    .navigationTitle("Code élève")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Terminé") { model.dismissIssuedCode() } }
                    }
            }
            .tint(DrivyTheme.accent)
        }
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

/// The invitation exists but its code never came back: only a new code can be handed over.
private struct InvitationCodeRecovery: View {
    @Bindable var model: SchoolInvitationWorkspace
    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Label("Le code n’a pas été reçu. Créez-en un nouveau : l’ancien ne fonctionnera plus.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Button { Task { await model.renewRecoveredCode() } } label: {
                DrivyBusyLabel(title: "Nouveau code", busyTitle: "Création…", isBusy: model.isBusy)
            }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!model.mayEdit)
            .accessibilityIdentifier("invitation-renew-recovered-code")
        }
        .padding(.vertical, DrivySpacing.xxs)
    }
}

enum InvitationPresentation {
    static func title(_ invitation: SchoolInvitation, training: String?) -> String {
        guard invitation.isCode else { return invitation.maskedEmail ?? "Invitation" }
        return ["Code élève", training].compactMap { $0 }.joined(separator: " · ")
    }
    static func tone(_ status: SchoolInvitationStatus) -> DrivyTone {
        switch status { case .pending: .accent; case .accepted: .success; case .revoked, .expired: .neutral }
    }
    static func symbol(_ status: SchoolInvitationStatus) -> String {
        switch status { case .pending: "clock"; case .accepted: "checkmark"; case .revoked: "xmark"; case .expired: "hourglass" }
    }
    static func codeStatus(_ status: SchoolInvitationStatus) -> String {
        switch status { case .pending: "Valable"; case .accepted: "Utilisé"; case .revoked: "Révoqué"; case .expired: "Expiré" }
    }
}

private struct InvitationRow: View {
    let invitation: SchoolInvitation
    let training: String?
    var body: some View {
        if invitation.isCode {
            // A badge only for what is not the usual waiting state.
            DrivyEntityRow(title: InvitationPresentation.title(invitation, training: training), leading: .symbol("number"),
                badge: invitation.status == .pending ? nil
                    : DrivyStatusBadge(title: InvitationPresentation.codeStatus(invitation.status),
                        symbol: InvitationPresentation.symbol(invitation.status), tone: InvitationPresentation.tone(invitation.status)))
        } else {
            DrivyEntityRow(title: InvitationPresentation.title(invitation, training: training), meta: invitation.roleLabel,
                leading: .symbol("envelope"),
                badge: DrivyStatusBadge(title: invitation.status.label, symbol: InvitationPresentation.symbol(invitation.status),
                    tone: InvitationPresentation.tone(invitation.status)))
        }
    }
}

private struct InvitationDetailView: View {
    @Bindable var model: SchoolInvitationWorkspace
    let invitation: SchoolInvitation
    @State private var confirmsResend = false
    @State private var showsRevocation = false

    private var statusTitle: String {
        invitation.isCode ? InvitationPresentation.codeStatus(invitation.status) : invitation.status.label
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Text(InvitationPresentation.title(invitation, training: model.trainingLabel(invitation)))
                        .font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    DrivyStatusBadge(title: statusTitle, symbol: InvitationPresentation.symbol(invitation.status),
                        tone: InvitationPresentation.tone(invitation.status))
                }
                DrivyRowGroup {
                    if !invitation.isCode {
                        DrivyContactRow(title: "Rôles", value: invitation.roleLabel, symbol: "person.crop.circle")
                    }
                    DrivyContactRow(title: invitation.isCode ? "Échéance du code" : "Échéance du lien",
                        value: invitation.expirationLabel(timeZone: model.school?.timeZone ?? "Europe/Zurich"), symbol: "calendar")
                }
                if let error = model.errorMessage { SchoolErrorNotice(message: error) }
                if let pending = model.pending { DrivyPanel { InvitationPendingNotice(model: model, pending: pending) } }
                if let success = model.successMessage {
                    DrivyInlineMessage(text: success)
                }
                if invitation.status.canBeManaged {
                    VStack(spacing: DrivySpacing.s) {
                        Button { confirmsResend = true } label: {
                            if invitation.isCode {
                                DrivyBusyLabel(title: "Nouveau code", busyTitle: "Création…", isBusy: model.isBusy)
                            } else {
                                Label("Renvoyer l’invitation", systemImage: "paperplane")
                            }
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canManage(invitation))
                        .accessibilityIdentifier("invitation-resend")
                        Button(role: .destructive) { showsRevocation = true } label: {
                            Label(invitation.isCode ? "Révoquer le code" : "Révoquer l’invitation", systemImage: "xmark.circle")
                        }
                        .buttonStyle(DrivyDestructiveButtonStyle())
                        .disabled(!model.canManage(invitation))
                        .accessibilityIdentifier("invitation-revoke")
                    }
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
        .alert(invitation.isCode ? "Créer un nouveau code ?" : "Renvoyer cette invitation ?", isPresented: $confirmsResend) {
            Button("Annuler", role: .cancel) {}
            Button(invitation.isCode ? "Nouveau code" : "Renvoyer") { Task { await model.resendAfterConfirmation(invitation) } }
        } message: {
            Text(invitation.isCode ? "L’ancien code cessera de fonctionner." : "L’ancien lien cessera de fonctionner.")
        }
        .sheet(isPresented: $showsRevocation) { InvitationRevocationView(model: model, invitation: invitation) }
    }
}

/// Inviter un élève : sa formation, puis un code à usage unique à lui transmettre.
/// L’invitation par e-mail reste lisible dans la liste, l’app ne la propose plus.
struct InvitationCreationView: View {
    @Bindable var model: SchoolInvitationWorkspace
    /// Depuis l’onglet Élèves : la liste n’est pas encore chargée, elle se charge ici.
    var learnerOnly = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let issued = model.issuedCode {
                    InvitationCodeResultView(issued: issued, schoolName: model.school?.name)
                } else {
                    form
                }
            }
            .navigationTitle(model.issuedCode == nil ? "Inviter un élève" : "Code élève")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.issuedCode == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Terminé") { model.dismissIssuedCode(); dismiss() }
                            .accessibilityIdentifier("invitation-code-done")
                    }
                }
            }
            .task {
                guard learnerOnly else { return }
                model.selectedRoles = [.learner]
                await model.load()
            }
        }
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy)
    }

    private var form: some View {
        Form {
            if model.isLoading && model.school == nil {
                Section { DrivyLoadingState(title: "Chargement de l’école…") }
            }
            if model.carriesTraining && !model.offerings.isEmpty {
                Section {
                    Picker("Formation", selection: $model.selectedOfferingID) {
                        if model.selectedOfferingID == nil { Text("Choisir").tag(nil as UUID?) }
                        ForEach(model.offerings) { offering in
                            Text(offeringLabel(offering)).tag(Optional(offering.id))
                        }
                    }
                    .accessibilityIdentifier("invitation-training")
                }
                .disabled(!model.mayEdit)
            }
            if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
            if let pending = model.pending {
                InvitationPendingSection(model: model, pending: pending)
            } else if model.codeRecovery != nil {
                Section { InvitationCodeRecovery(model: model) }
            } else if model.needsReload && !model.isLoading {
                Section { Button("Actualiser") { Task { await model.load() } } }
            }
        }
        .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            if model.codeRecovery == nil {
                DrivyFormActionBar(hint: hint) {
                    Button { Task { await model.createCode(offeringID: model.selectedOfferingID) } } label: {
                        DrivyBusyLabel(title: "Créer le code", busyTitle: "Création…", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!model.mayEdit || !model.codeDraftIsValid)
                    .accessibilityIdentifier("invitation-create-code")
                }
            }
        }
    }

    private var hint: String? {
        guard model.mayEdit, model.carriesTraining, !model.offerings.isEmpty, model.selectedOffering == nil else { return nil }
        return "Choisissez la formation."
    }

    private func offeringLabel(_ offering: SchoolOffering) -> String {
        let shared = model.offerings.filter { $0.categoryCode == offering.categoryCode }.count > 1
        return shared ? "Permis \(offering.categoryCode) · \(offering.offeringKey)" : "Permis \(offering.categoryCode)"
    }
}

/// The code, very large, to show or send to the learner. Read aloud character by character.
struct InvitationCodeResultView: View {
    let issued: SchoolIssuedInvitationCode
    let schoolName: String?
    var now = Date()
    @State private var copied = false
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 46

    var body: some View {
        ScrollView {
            VStack(spacing: DrivySpacing.l) {
                VStack(spacing: DrivySpacing.s) {
                    Text(issued.code)
                        .font(.system(size: codeSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(DrivyTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .textSelection(.enabled)
                        .accessibilityLabel("Code")
                        .accessibilityValue(Text(issued.code.replacingOccurrences(of: "-", with: " ")).speechSpellsOutCharacters())
                        .accessibilityIdentifier("invitation-code-value")
                    Text(Self.validity(until: issued.expiresAt, now: now))
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                }
                .padding(.vertical, DrivySpacing.xl)
                .padding(.horizontal, DrivySpacing.m)
                .frame(maxWidth: .infinity)
                .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.m))
                VStack(spacing: DrivySpacing.s) {
                    ShareLink(item: Self.message(code: issued.code, schoolName: schoolName)) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("invitation-code-share")
                    Button(action: copy) {
                        Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .accessibilityIdentifier("invitation-code-copy")
                }
            }
            .drivyPageContent(maxWidth: 560)
        }
        .background(DrivyTheme.surface)
    }

    private func copy() {
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if let expiry = SchoolInvitation.date(issued.expiresAt) { options[.expirationDate] = expiry }
        UIPasteboard.general.setItems([[UTType.plainText.identifier: issued.code]], options: options)
        copied = true
        AccessibilityNotification.Announcement("Code copié").post()
    }

    static func message(code: String, schoolName: String?) -> String {
        let school = schoolName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } ?? "mon auto-école"
        return "Rejoins \(school) sur Drivy : ouvre l’app, crée ton compte puis saisis le code \(code)."
    }

    /// « Valable 7 jours »; under a day, the hour it stops working.
    static func validity(until expiresAt: String, now: Date) -> String {
        guard let expiry = SchoolInvitation.date(expiresAt), expiry > now else { return "Expiré" }
        let days = Int((expiry.timeIntervalSince(now) / 86_400).rounded())
        if days >= 1 { return days == 1 ? "Valable 1 jour" : "Valable \(days) jours" }
        return "Valable jusqu’à \(expiry.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_CH"))))"
    }
}

private struct InvitationRevocationView: View {
    @Bindable var model: SchoolInvitationWorkspace
    let invitation: SchoolInvitation
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var confirms = false
    @State private var didSubmit = false

    private var context: String { InvitationPresentation.title(invitation, training: model.trainingLabel(invitation)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DrivyFormIntro(context: context,
                        message: invitation.isCode ? "Le code ne permettra plus de rejoindre l’école."
                            : "La personne ne pourra plus rejoindre l’école avec ce lien.")
                }
                .listRowBackground(DrivyTheme.canvas)
                Section("Motif") {
                    TextField(invitation.isCode ? "Pourquoi révoquer ce code ?" : "Expliquez pourquoi ce lien doit être révoqué",
                        text: $reason, axis: .vertical).lineLimit(3...8)
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
                        DrivyBusyLabel(title: invitation.isCode ? "Révoquer le code" : "Révoquer l’invitation", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyDestructiveButtonStyle())
                    .disabled(!model.canManage(invitation) || !SchoolInvitationWorkspace.reasonIsValid(reason))
                    .accessibilityIdentifier("invitation-confirm-revoke")
                }
            }
            .navigationTitle(invitation.isCode ? "Révoquer le code" : "Révoquer le lien").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .alert("Confirmer la révocation ?", isPresented: $confirms) {
                Button("Annuler", role: .cancel) {}
                Button("Révoquer", role: .destructive) {
                    let confirmedReason = reason
                    didSubmit = true
                    Task { if await model.revokeAfterConfirmation(invitation, reason: confirmedReason) { dismiss() } }
                }
            } message: { Text("\(context)\n\n\(reason)") }
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
