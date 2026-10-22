import SwiftUI

/// Le dossier d’un élève vu par l’école : le moniteur affecté (coordonnées) ou l’administration (toutes les informations).
/// Une seule identité (#94) : ces champs sont ceux du compte Drivy de l’élève ; l’élève les modifie dans « Mon profil ».
struct SchoolProfileView: View {
    @Bindable var model: SchoolProfileWorkspace
    var loadsOnAppear = true
    /// Le champ à ouvrir : la page défile jusqu’à lui et le met au clavier (venu d’une information manquante).
    var focus: SchoolProfileField? = nil
    /// Informations requises qui manquaient à l’ouverture ; chacune garde son point tant qu’elle reste vide.
    var missingFields: Set<SchoolProfileField> = []
    @FocusState private var focusedField: SchoolProfileField?
    @State private var focusApplied = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsGuidedWelcome = false
    @State private var confirmsDiscard = false
    @State private var attemptedSave = false
    /// Une seule identité (#94) : l’administration qui modifie l’élève modifie son compte, lu par toutes ses écoles.
    @State private var confirmsSave = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profil de l’élève")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") {
                            if model.hasEdits { confirmsDiscard = true } else { dismiss() }
                        }.disabled(model.isBusy)
                    }
                }
                .task { if loadsOnAppear { await model.load() } }
                .sheet(isPresented: $showsGuidedWelcome) { SchoolOnboardingView(model: model) }
                .alert("Quitter sans enregistrer tes changements ?", isPresented: $confirmsDiscard) {
                    Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                } message: {
                    Text("Une demande déjà envoyée reste conservée sur cet appareil jusqu’à confirmation.")
                }
                .alert("Modifier le profil de l’élève ?", isPresented: $confirmsSave) {
                    Button("Enregistrer pour l’élève") { send() }
                    Button("Annuler", role: .cancel) {}
                } message: {
                    Text("Ces informations sont celles du compte Drivy de l’élève. Il les retrouvera dans Mon profil, et toute autre école qui le suit lira les mêmes.")
                }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.hasEdits || model.isBusy)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            form
                .task(id: model.profile != nil) { await openFocus(proxy) }
        }
    }

    /// Une fois le dossier à l’écran : défilement jusqu’au champ demandé, puis le clavier, après la montée de la
    /// feuille. Une adresse à renseigner s’ouvre d’elle-même. Une seule fois par ouverture.
    private func openFocus(_ proxy: ScrollViewProxy) async {
        guard let focus, !focusApplied, model.profile != nil, model.editableFields.contains(focus) else { return }
        focusApplied = true
        if focus == .postalAddress && !model.draft.hasAddress { model.draft.hasAddress = true }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        withAnimation(DrivyMotion.context(reduceMotion)) { proxy.scrollTo(focus, anchor: .center) }
        focusedField = focus
    }

    private var form: some View {
        Form {
            SchoolProfileStatusSections(model: model)
            if let profile = model.profile { heading(profile) }
            SchoolProfileFieldSections(model: model, focusedField: $focusedField, missingFields: missingFields)
            SchoolProfileContextSections(model: model, resumeOnboarding: { showsGuidedWelcome = true })
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            if model.profile != nil, !model.editableFields.isEmpty, model.hasEdits || model.isBusy {
                DrivyFormActionBar(hint: saveHint.text, hintTone: saveHint.tone) {
                    Button {
                        attemptedSave = true
                        // Le moniteur n’écrit que les coordonnées de contact ; tout changement d’identité se confirme.
                        if model.isOwnProfile { send() } else { confirmsSave = true }
                    } label: {
                        // Même indicateur de l’envoi jusqu’à la relecture qui en applique la réponse.
                        DrivyBusyLabel(title: "Enregistrer les modifications", isBusy: model.isSavingProfile)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canSaveProfile)
                    .accessibilityIdentifier("profile-save")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func send() { Task { _ = await model.saveProfileAfterConfirmation() } }

    private var saveHint: (text: String?, tone: DrivyTone) {
        if attemptedSave, let error = model.errorMessage { return (error, .danger) }
        guard model.hasEdits else { return (nil, .neutral) }
        return (model.invalidFields.isEmpty ? nil : "Vérifie les champs signalés.", .neutral)
    }

    /// Même tête que l’écran Compte : avatar, nom, école. Elle ne redit pas les champs, elle nomme la personne.
    @ViewBuilder private func heading(_ profile: SchoolAdministrativeProfile) -> some View {
        let name = [profile.firstName, profile.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !name.isEmpty {
            Section {
                HStack(spacing: DrivySpacing.m) {
                    if !typeSize.isAccessibilitySize { DrivyAvatar(name: name, size: 52) }
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(name)
                            .font(.drivyTitle)
                            .foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let school = model.school?.name {
                            Text(school)
                                .font(.subheadline)
                                .foregroundStyle(DrivyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .drivyClearRow()
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: DrivySpacing.xs, leading: 0, bottom: DrivySpacing.xs, trailing: 0))
            }
        }
    }
}

struct SchoolProfileStatusSections: View {
    @Bindable var model: SchoolProfileWorkspace
    var body: some View {
        Group {
            if model.profile == nil && model.onboarding == nil && model.errorMessage == nil
                && (model.isLoading || model.school == nil) {
                Section { DrivySkeletonRows(count: 4).drivySkeleton("Chargement du dossier…") }
                    .drivyFormRows()
            }
            if model.hasProfileConflict {
                Section { SchoolProfileConflictNotice(model: model) }
                    .drivyFormRows()
            } else if let error = model.errorMessage {
                // The notice is the whole row: no white card around the red one.
                Section {
                    SchoolErrorNotice(message: error,
                        retry: model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(DrivyTheme.dangerSurface)
                }
            }
            if let success = model.successMessage, !model.hasEdits {
                Section { DrivyFormMessage(text: success) }
                    .drivyFormRows()
            }
            // Réservée à une demande restée en attente : un enregistrement normal, en cours, ne la montre pas.
            if let pending = model.pending, model.pendingAwaitsReview {
                Section {
                    DrivyPendingRequest(
                        message: pending.waitingMessage(absent: model.pendingAbsent),
                        notes: model.pendingAbsent ? [] : pendingNotes(pending),
                        reference: pending.id,
                        verify: model.pendingAbsent ? nil : { Task { await model.verifyPending() } }, canVerify: model.canVerifyPending,
                        retry: model.canRetryPending ? { Task { await model.retryPending() } } : nil,
                        abandon: model.pendingAbsent ? { Task { await model.abandonPending() } } : nil, canAbandon: model.canVerifyPending)
                }
                    .drivyFormRows()
            }
        }
    }
}

/// Shared by the profile form and its guided welcome: a re-read must not silently
/// put local edits on top of someone else's newer version.
struct SchoolProfileConflictNotice: View {
    @Bindable var model: SchoolProfileWorkspace
    @State private var confirmsReload = false

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            SchoolErrorNotice(message: model.errorMessage ?? "Ces informations ont changé dans l’école.")
            Button("Recharger les informations") { confirmsReload = true }
                .frame(minHeight: DrivyLayout.tapTarget)
                .disabled(model.isLoading || model.isBusy)
                .accessibilityIdentifier("profile-reload-conflict")
        }
        .alert("Recharger les informations de l’école ?", isPresented: $confirmsReload) {
            Button("Recharger", role: .destructive) { Task { await model.load(preserveDraft: false) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ton brouillon sera remplacé par les informations enregistrées dans l’école.")
        }
    }
}

extension SchoolProfileStatusSections {
    fileprivate func pendingNotes(_ pending: PendingSchoolCommand) -> [String] {
        var notes: [String] = []
        if pending.observationUndoOperationID != nil {
            notes.append("L’annulation du signalement doit être vérifiée depuis la leçon.")
        } else if !pending.kind.isProfile {
            notes.append("Cette demande vient d’un autre écran de l’école.")
        }
        if pending.scope != model.scope { notes.append("Tes accès ont changé depuis l’envoi. Le renvoi reste désactivé.") }
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
