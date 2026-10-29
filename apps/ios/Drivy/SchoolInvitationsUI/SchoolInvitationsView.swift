import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SchoolInvitationsView: View {
    @Bindable var model: SchoolInvitationWorkspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsCreation = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var query = ""
    @State private var statusFilter: SchoolInvitationListFilter = .all
    @State private var now = Date()

    private var isFiltering: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || statusFilter != .all }
    private var visibleInvitations: [SchoolInvitation] { model.matchingInvitations(query: query, filter: statusFilter, now: now) }
    private var nextDeadline: Date? {
        guard scenePhase == .active else { return nil }
        return model.invitations.filter { $0.status == .pending }
            .compactMap { SchoolInvitation.date($0.expiresAt) }.filter { $0 > now }.min()
    }

    /// A code renewed from the detail opens here; the creation sheet shows its own.
    private var issuedCode: Binding<SchoolIssuedInvitationCode?> {
        Binding(get: { showsCreation ? nil : model.issuedCode }, set: { if $0 == nil { model.dismissIssuedCode() } })
    }

    var body: some View {
        let displayedInvitations = visibleInvitations
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $model.selectedID) {
                if model.school != nil {
                    Section {
                        Picker("Statut", selection: $statusFilter) {
                            ForEach(SchoolInvitationListFilter.allCases) { filter in Text(filter.label).tag(filter) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("invitations-status-filter")
                    }
                    .drivyFormRows()
                }
                if let pending = model.pending { InvitationPendingSection(model: model, pending: pending) }
                if model.pending == nil, model.codeRecovery != nil, !showsCreation {
                    Section { InvitationCodeRecovery(model: model) }
                        .drivyFormRows()
                }
                if let success = model.successMessage {
                    Section { DrivyFormMessage(text: success) }
                        .drivyFormRows()
                }
                if let error = model.errorMessage {
                    Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                        .drivyFormRows()
                }
                if !model.hasLoaded && model.invitations.isEmpty && model.errorMessage == nil {
                    Section { DrivySkeletonRows(count: 4, leading: .avatar).drivySkeleton("Chargement des invitations…") }
                        .drivyFormRows()
                }
                if model.school != nil && model.invitations.isEmpty && model.nextCursor == nil && !isFiltering
                    && !model.isLoading && model.errorMessage == nil {
                    Section {
                        DrivyEmptyState(title: "Aucune invitation", symbol: "envelope",
                            actionTitle: model.mayEdit && model.canCreateCode ? "Inviter un élève" : nil,
                            action: { showsCreation = true })
                            .buttonStyle(.borderless)
                    }
                        .drivyFormRows()
                }
                Section {
                    if model.hasLoaded && displayedInvitations.isEmpty && (isFiltering || model.nextCursor != nil) {
                        DrivyEmptyState(title: model.nextCursor != nil ? "Aucun résultat sur les pages chargées" : "Aucun résultat",
                            symbol: "magnifyingglass", actionTitle: isFiltering ? "Effacer les filtres" : nil,
                            action: { query = ""; statusFilter = .all })
                            .buttonStyle(.borderless)
                            .drivyFormRows()
                    }
                    ForEach(displayedInvitations) { invitation in
                        NavigationLink(value: invitation.id) {
                            InvitationRow(invitation: invitation, training: model.trainingLabel(invitation),
                                reference: model.reference(invitation), timeZone: model.school?.timeZone, now: now,
                                isSelected: model.selectedID == invitation.id)
                        }
                        .accessibilityIdentifier("invitation-\(invitation.id.uuidString)")
                        // Le fond de sélection ne porte pas seul l’état : VoiceOver l’annonce.
                        .accessibilityAddTraits(model.selectedID == invitation.id ? .isSelected : [])
                        .drivyFormRows(isSelected: model.selectedID == invitation.id)
                    }
                    if model.nextCursor != nil {
                        Button { Task { await model.loadMore() } } label: {
                            DrivyBusyLabel(title: "Afficher la suite", busyTitle: "Chargement…", isBusy: model.isLoadingMore)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget)
                        .disabled(model.isLoadingMore || model.isLoading || model.isBusy)
                        .accessibilityIdentifier("invitations-more")
                    }
                } header: {
                    if model.nextCursor != nil { Text("Résultats parmi les invitations chargées").drivyFormSectionHeader() }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DrivyTheme.canvas)
            .searchable(text: $query, prompt: "Invitation ou référence")
            .refreshable { await model.load() }
            .navigationTitle("Invitations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) }
                if model.canCreateCode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsCreation = true } label: { Label("Inviter un élève", systemImage: "plus") }
                            .disabled(!model.mayEdit)
                            .accessibilityIdentifier("invitation-create")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: DrivyLayout.splitListMinWidth, ideal: DrivyLayout.splitListIdealWidth,
                max: DrivyLayout.splitListMaxWidth)
        } detail: {
            if let invitation = model.selectedInvitation {
                InvitationDetailView(model: model, invitation: invitation, now: now)
                    .id(invitation.id)
            } else {
                ContentUnavailableView("Choisis une invitation", systemImage: "envelope.open")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DrivyTheme.surface)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .presentationSizing(.page)
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            now = Date()
            await model.load()
        }
        .task(id: nextDeadline) {
            guard let deadline = nextDeadline else { return }
            do { try await Task.sleep(for: .seconds(max(0.05, deadline.timeIntervalSinceNow))) }
            catch { return }
            now = Date()
        }
        .sheet(isPresented: $showsCreation, onDismiss: { model.dismissIssuedCode() }) { InvitationCreationView(model: model) }
        .sheet(item: issuedCode) { issued in
            NavigationStack {
                InvitationCodeResultView(issued: issued, schoolName: model.school?.name)
                    .navigationTitle("Code élève")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Fermer") { model.dismissIssuedCode() } }
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
            .drivyFormRows()
    }
}

/// Uncertain request in the shared presentation; the Section wrapper above is
/// for Forms and Lists, the notice alone sits in a DrivyPanel on a page.
private struct InvitationPendingNotice: View {
    @Bindable var model: SchoolInvitationWorkspace
    let pending: PendingSchoolCommand
    var body: some View {
        DrivyPendingRequest(
            message: pending.waitingMessage(absent: model.pendingAbsent),
            notes: model.pendingAbsent ? [] : notes,
            verify: model.pendingAbsent ? nil : { Task { await model.verifyPending() } }, canVerify: model.canVerifyPending,
            verifyIdentifier: "invitation-verify-command",
            retry: model.canRetryPending ? { Task { await model.retryPending() } } : nil,
            retryIdentifier: "invitation-retry-command",
            abandon: model.pendingAbsent ? { Task { await model.abandonPending() } } : nil, canAbandon: model.canVerifyPending)
    }
    private var notes: [String] {
        if pending.scope != model.scope { return ["Tes accès ont changé. La demande ne sera pas renvoyée avec ces nouveaux accès."] }
        if model.pendingRequiresReview { return ["La demande nécessite une vérification par l’école. Conserve sa référence."] }
        return []
    }
}

/// The invitation exists but its code never came back: only a new code can be handed over.
private struct InvitationCodeRecovery: View {
    @Bindable var model: SchoolInvitationWorkspace
    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Label("Le code n’a pas été reçu. Crée-en un nouveau : l’ancien ne fonctionnera plus.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
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
        switch status { case .pending: .accent; case .accepted, .revoked, .expired: .neutral }
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
    let reference: String
    let timeZone: String?
    let now: Date
    let isSelected: Bool
    private var status: SchoolInvitationStatus { SchoolInvitationListPresentation.status(invitation, now: now) }
    private var deadline: String? { SchoolInvitationListPresentation.activeDeadline(invitation, now: now, timeZone: timeZone) }
    private var meta: String {
        let identification = [invitation.isCode ? nil : invitation.roleLabel, "Réf. \(reference)"]
            .compactMap { $0 }.joined(separator: " · ")
        return [identification, deadline].compactMap { $0 }.joined(separator: "\n")
    }
    var body: some View {
        DrivyEntityRow(title: InvitationPresentation.title(invitation, training: training), meta: meta,
            leading: .symbol(invitation.isCode ? "number" : "envelope"),
            badge: status == .pending ? nil : DrivyStatusBadge(
                title: SchoolInvitationListPresentation.statusLabel(invitation, now: now),
                symbol: InvitationPresentation.symbol(status), tone: InvitationPresentation.tone(status)),
            isSelected: isSelected)
            .accessibilityLabel([InvitationPresentation.title(invitation, training: training), invitation.roleLabel,
                "Référence \(reference)", SchoolInvitationListPresentation.statusLabel(invitation, now: now), deadline]
                .compactMap { $0 }.joined(separator: ", "))
    }
}

private struct InvitationDetailView: View {
    @Bindable var model: SchoolInvitationWorkspace
    let invitation: SchoolInvitation
    let now: Date
    @State private var confirmsResend = false
    @State private var showsRevocation = false

    private var status: SchoolInvitationStatus { SchoolInvitationListPresentation.status(invitation, now: now) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Text(InvitationPresentation.title(invitation, training: model.trainingLabel(invitation)))
                        .font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    // Une invitation en attente est l’état ordinaire, qu’elle utilise un code ou un lien.
                    Text("Réf. \(model.reference(invitation))")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .accessibilityLabel("Référence \(model.reference(invitation))")
                    if status != .pending {
                        DrivyStatusBadge(title: SchoolInvitationListPresentation.statusLabel(invitation, now: now),
                            symbol: InvitationPresentation.symbol(status), tone: InvitationPresentation.tone(status))
                    }
                }
                DrivyRowGroup {
                    if !invitation.isCode {
                        DrivyContactRow(title: "Rôles", value: invitation.roleLabel, symbol: "person.crop.circle")
                    }
                    DrivyContactRow(title: invitation.isCode ? "Échéance du code" : "Échéance du lien",
                        value: SchoolInvitationListPresentation.deadline(invitation, timeZone: model.school?.timeZone), symbol: "calendar")
                    DrivyContactRow(title: "Référence complète", value: invitation.id.uuidString, symbol: "number")
                        .textSelection(.enabled)
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
                    .frame(maxWidth: DrivyLayout.compactColumn)
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
            Text("Réf. \(model.reference(invitation))\n\n"
                + (invitation.isCode ? "L’ancien code cessera de fonctionner." : "L’ancien lien cessera de fonctionner."))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            // Le code remplace le formulaire en fondu : même feuille, même contexte.
            Group {
                if let issued = model.issuedCode {
                    InvitationCodeResultView(issued: issued, schoolName: model.school?.name)
                        .transition(.opacity)
                } else {
                    form
                        .transition(.opacity)
                }
            }
            .animation(DrivyMotion.context(reduceMotion), value: model.issuedCode != nil)
            .navigationTitle(model.issuedCode == nil ? "Inviter un élève" : "Code élève")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.issuedCode == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(model.isBusy) }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { model.dismissIssuedCode(); dismiss() }
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
        // Le code n’est montré qu’une fois : seul « Fermer » le referme, jamais un glissement involontaire.
        .tint(DrivyTheme.accent).interactiveDismissDisabled(model.isBusy || model.issuedCode != nil)
    }

    private var form: some View {
        Form {
            // Lignes sur la surface du thème, comme la liste des invitations (le gris système du sombre ne s’accorde pas).
            Group {
                if !model.hasLoaded && model.errorMessage == nil {
                    Section { DrivySkeletonRows(count: 3, lines: 1).drivySkeleton("Chargement des formations et des moniteurs…") }
                        .drivyFormRows()
                }
                if model.lacksOpenTraining {
                    Section {
                        DrivyEmptyState(title: "Aucune formation ouverte", message: "Ouvre-la sur le web pour inviter un élève.",
                            symbol: "steeringwheel")
                    }
                        .drivyFormRows()
                }
                if model.lacksInstructor {
                    Section {
                        DrivyEmptyState(title: "Aucun moniteur actif", message: "Ajoute un moniteur sur le web pour inviter un élève.",
                            symbol: "person.crop.circle")
                    }
                        .drivyFormRows()
                }
                if model.carriesTraining && !model.offerings.isEmpty {
                    Section {
                        ForEach(model.offerings) { offering in
                            let isOn = model.selectedOfferingIDs.contains(offering.id)
                            let isFull = !isOn && model.selectedOfferingIDs.count >= 16
                            Toggle(isOn: Binding(
                                get: { model.selectedOfferingIDs.contains(offering.id) },
                                set: { selected in
                                    if selected { model.selectedOfferingIDs.insert(offering.id) }
                                    else { model.selectedOfferingIDs.remove(offering.id) }
                                })) {
                                HStack(spacing: DrivySpacing.s) {
                                    DrivingLicenseIcon(code: offering.categoryCode,
                                                       emphasis: isFull ? .disabled : isOn ? .selected : .normal)
                                    Text(offeringLabel(offering))
                                }
                            }
                                .disabled(isFull)
                                .drivyControlTint()
                                .accessibilityIdentifier("invitation-training-\(offering.id.uuidString)")
                        }
                    } header: { Text("Permis").drivyFormSectionHeader() }
                        .drivyFormRows()
                    .disabled(!model.mayEdit || model.creationOptionsError != nil)
                }
                if model.roles.contains("ADMIN"), !model.instructors.isEmpty {
                    Section {
                        Picker("Moniteur", selection: $model.selectedInstructorID) {
                            if model.selectedInstructorID == nil { Text("Choisir").tag(nil as UUID?) }
                            ForEach(model.instructors) { instructor in
                                Text(model.instructorLabel(instructor)).tag(Optional(instructor.id))
                            }
                        }
                        .accessibilityIdentifier("invitation-instructor")
                    }
                        .drivyFormRows()
                    .disabled(!model.mayEdit || model.creationOptionsError != nil)
                }
                if let error = model.creationOptionsError {
                    Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                        .drivyFormRows()
                }
                if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) }
                    .drivyFormRows() }
                if let pending = model.pending {
                    InvitationPendingSection(model: model, pending: pending)
                } else if model.codeRecovery != nil {
                    Section { InvitationCodeRecovery(model: model) }
                        .drivyFormRows()
                } else if model.needsReload && !model.isLoading {
                    Section { Button("Actualiser") { Task { await model.load() } } }
                        .drivyFormRows()
                }
            }
            .drivyFormRows()
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            if model.codeRecovery == nil {
                DrivyFormActionBar(hint: hint) {
                    Button { Task { await model.createCode() } } label: {
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
        guard model.mayEdit, model.creationOptionsError == nil else { return nil }
        if !model.offerings.isEmpty && model.selectedOfferingIDs.isEmpty { return "Choisis au moins un permis." }
        if !model.instructors.isEmpty && model.selectedInstructorID == nil { return "Choisis le moniteur." }
        return nil
    }

    private func offeringLabel(_ offering: SchoolOffering) -> String {
        let shared = model.offerings.filter { $0.categoryCode == offering.categoryCode }.count > 1
        return shared ? "Permis \(offering.categoryCode) · \(offering.offeringKey)" : "Permis \(offering.categoryCode)"
    }
}

/// Code lisible en entier, sur deux groupes si la taille de texte ne tient plus en une ligne.
struct InvitationCodeResultView: View {
    let issued: SchoolIssuedInvitationCode
    let schoolName: String?
    var now = Date()
    @State private var copied = false
    @ScaledMetric(relativeTo: .title) private var codeSize: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: DrivySpacing.l) {
                VStack(spacing: DrivySpacing.m) {
                    ViewThatFits(in: .horizontal) {
                        codeText(issued.code)
                        VStack(spacing: DrivySpacing.xxs) {
                            ForEach(Array(issued.code.split(separator: "-").enumerated()), id: \.offset) { _, group in
                                codeText(String(group))
                            }
                        }
                    }
                        .foregroundStyle(DrivyTheme.text)
                        .textSelection(.enabled)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Code")
                        .accessibilityValue(Text(issued.code.replacingOccurrences(of: "-", with: " ")).speechSpellsOutCharacters())
                        .accessibilityIdentifier("invitation-code-value")
                    Label(Self.validity(until: issued.expiresAt, now: now), systemImage: "clock")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(DrivyTheme.muted)
                }
                .padding(.vertical, DrivySpacing.l)
                .padding(.horizontal, DrivySpacing.m)
                .frame(maxWidth: .infinity)
                .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content))
                VStack(spacing: DrivySpacing.s) {
                    // Un verbe et son objet ; l’aperçu du partage nomme ce qui part.
                    ShareLink(item: Self.message(code: issued.code, schoolName: schoolName),
                              subject: Text("Code élève"),
                              preview: SharePreview("Code élève")) {
                        Label("Partager le code", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("invitation-code-share")
                    Button(action: copy) {
                        // Le symbole bascule en fondu, sans mouvement sous « Réduire les animations ».
                        HStack(spacing: DrivySpacing.xs) {
                            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                                .accessibilityHidden(true)
                            Text(copied ? "Code copié" : "Copier le code")
                        }
                    }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .animation(DrivyMotion.feedback(reduceMotion), value: copied)
                    .accessibilityIdentifier("invitation-code-copy")
                }
            }
            .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
        }
        .background(DrivyTheme.surface)
        // La copie est locale et immédiate : retour haptique puis retour au libellé d’action.
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in isCopied }
        .task(id: copied) {
            guard copied, (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            copied = false
        }
    }

    private func codeText(_ value: String) -> some View {
        Text(value)
            .font(typeSize.isAccessibilitySize
                ? .system(.body, design: .monospaced).weight(.bold)
                : .system(size: codeSize, weight: .bold, design: .monospaced))
            .tracking(typeSize.isAccessibilitySize ? 0 : codeSize * 0.06)
            .fixedSize()
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
        return "Rejoins \(school) sur Drivy : ouvre l’app, touche « J’ai un code », connecte-toi puis saisis \(code)."
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

    private var context: String {
        InvitationPresentation.title(invitation, training: model.trainingLabel(invitation)) + " · Réf. \(model.reference(invitation))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DrivyFormIntro(context: context,
                        message: invitation.isCode ? "Le code ne permettra plus de rejoindre l’école."
                            : "La personne ne pourra plus rejoindre l’école avec ce lien.")
                }
                .listRowBackground(DrivyTheme.canvas)
                .listRowSeparator(.hidden)
                Section {
                    TextField(invitation.isCode ? "Pourquoi révoquer ce code ?" : "Explique pourquoi ce lien doit être révoqué",
                        text: $reason, axis: .vertical).lineLimit(3...8)
                        .accessibilityLabel("Motif de révocation").accessibilityIdentifier("invitation-revoke-reason")
                    if reason.unicodeScalars.count > 800 {
                        Text("\(reason.unicodeScalars.count)/1 000 caractères").font(.caption)
                            .foregroundStyle(reason.unicodeScalars.count > 1000 ? DrivyTheme.danger : DrivyTheme.muted)
                    }
                } header: { Text("Motif").drivyFormSectionHeader() }
                .disabled(!model.mayEdit)
                .drivyFormRows()
                Group {
                    if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) }
                        .drivyFormRows() }
                    if let pending = model.pending {
                        InvitationPendingSection(model: model, pending: pending)
                    } else if model.needsReload {
                        Section { Button("Actualiser avant de confirmer") { Task { await model.load() } } }
                            .drivyFormRows()
                    }
                }
                .drivyFormRows()
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                DrivyFormActionBar(hint: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Indique le motif de la révocation." : nil) {
                    Button(role: .destructive) { confirms = true } label: {
                        DrivyBusyLabel(title: invitation.isCode ? "Révoquer le code" : "Révoquer l’invitation", isBusy: model.isBusy)
                    }
                    .buttonStyle(DrivyDestructiveButtonStyle())
                    .disabled(!model.canManage(invitation) || !SchoolInvitationWorkspace.reasonIsValid(reason))
                    .accessibilityIdentifier("invitation-confirm-revoke")
                }
            }
            .navigationTitle(invitation.isCode ? "Révoquer le code" : "Révoquer le lien").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(model.isBusy) } }
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
        // Un motif déjà saisi ne se perd pas sur un glissement involontaire ; « Annuler » reste la sortie.
        .interactiveDismissDisabled(model.isBusy || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
