import PhotosUI
import SwiftUI

/// « Mon profil » : la seule page où une personne consulte et modifie ce qui la concerne. Deux sources y restent
/// distinctes. Le compte Drivy (`/v1/me/profile`) lui appartient, quel que soit son rôle ou son école. Le dossier
/// d’élève (`SchoolProfileWorkspace`) appartient à l’école ouverte et n’existe que pour un élève dont l’école l’a
/// ouvert ; il garde ses droits, sa politique, sa file d’envoi chiffrée et ses conflits. Chaque source s’enregistre
/// par sa propre requête et dit son propre résultat : rien n’est présenté comme une transaction commune.
struct SchoolMyProfileView: View {
    let workspace: SchoolWorkspace
    /// Le dossier de la personne dans l’école ouverte ; `nil` sans dossier (moniteur, administration, compte sans école).
    let dossier: SchoolProfileWorkspace?
    var loadsDossierOnAppear = true
    /// Le champ du dossier à ouvrir : la page défile jusqu’à lui et le met au clavier (venu d’une information manquante).
    var focus: SchoolProfileField? = nil
    /// Informations requises qui manquaient à l’ouverture ; chacune garde son point tant qu’elle reste vide.
    var missingFields: Set<SchoolProfileField> = []
    @State private var editor: SchoolSelfProfileEditor
    @FocusState private var focusedField: SchoolProfileField?
    @State private var focusApplied = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var confirmsPhotoRemoval = false
    @State private var confirmsDiscard = false
    @State private var showsGuidedWelcome = false
    @State private var showsAllDossierFields = false
    @State private var outcome: SchoolMyProfileOutcome?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(workspace: SchoolWorkspace, dossier: SchoolProfileWorkspace?, loadsDossierOnAppear: Bool = true,
         focus: SchoolProfileField? = nil, missingFields: Set<SchoolProfileField> = []) {
        self.workspace = workspace; self.dossier = dossier; self.loadsDossierOnAppear = loadsDossierOnAppear
        self.focus = focus; self.missingFields = missingFields
        _editor = State(initialValue: SchoolSelfProfileEditor(workspace: workspace))
    }

    private var dossierHasEdits: Bool { dossier?.hasEdits == true }
    private var hasEdits: Bool { editor.hasEdits || dossierHasEdits }
    private var isBusy: Bool { editor.isBusy || dossier?.isBusy == true || dossier?.isSavingProfile == true }
    /// Chaque source modifiée doit être valable : un enregistrement ne part jamais à moitié par surprise.
    private var canSave: Bool {
        hasEdits && !isBusy && (!editor.hasEdits || editor.canSave) && (!dossierHasEdits || dossier?.canSaveProfile == true)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                form
                    .task(id: dossier?.profile != nil) { await openFocus(proxy) }
            }
            .navigationTitle("Mon profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { if hasEdits { confirmsDiscard = true } else { dismiss() } }
                        .disabled(isBusy)
                        .accessibilityIdentifier("my-profile-close")
                }
            }
            .alert("Quitter sans enregistrer tes changements ?", isPresented: $confirmsDiscard) {
                Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
            } message: {
                Text("Une demande déjà envoyée à l’école reste conservée sur cet appareil jusqu’à confirmation.")
            }
            .confirmationDialog("Retirer la photo ?", isPresented: $confirmsPhotoRemoval, titleVisibility: .visible) {
                Button("Retirer la photo", role: .destructive) { upload(nil) }
            }
            .sheet(isPresented: $showsGuidedWelcome) {
                if let dossier { SchoolOnboardingView(model: dossier, trainings: workspace.trainings) }
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(hasEdits || isBusy)
        .task {
            await editor.load()
            if loadsDossierOnAppear, let dossier { await dossier.load() }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await prepare(item) }
        }
    }

    private var form: some View {
        Form {
            photoSection
            accountMessages
            accountSections
            if let dossier { dossierSections(dossier) }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            // Une saisie en cours n’est jamais remplacée par la relecture : le compte attend, le dossier garde son brouillon.
            if !editor.hasEdits { await editor.load() }
            if let dossier, !dossier.isBusy { await dossier.load() }
        }
        .animation(DrivyMotion.feedback(reduceMotion), value: showsAllDossierFields)
        .safeAreaInset(edge: .bottom) {
            if hasEdits || isBusy {
                DrivyFormActionBar(hint: saveHint.text, hintTone: saveHint.tone) {
                    Button(action: save) {
                        DrivyBusyLabel(title: "Enregistrer", isBusy: editor.isSaving || dossier?.isSavingProfile == true)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(!canSave)
                    .accessibilityIdentifier("my-profile-save")
                }
            }
        }
    }

    // MARK: Compte Drivy

    private var photoSection: some View {
        Section {
            HStack(spacing: DrivySpacing.m) {
                ZStack {
                    DrivyAvatar(name: editor.trimmed.displayName.isEmpty ? (workspace.person?.displayName ?? "") : editor.trimmed.displayName,
                        size: 72, photo: workspace.selfPhoto?.data)
                    if editor.isSavingPhoto { ProgressView().accessibilityLabel("Envoi de la photo…") }
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                        Text(workspace.selfPhoto == nil ? "Ajouter une photo" : "Changer la photo")
                    }
                    .accessibilityIdentifier("self-photo-pick")
                    if workspace.selfProfile?.photoVersion != nil {
                        Button("Retirer la photo", role: .destructive) { confirmsPhotoRemoval = true }
                            .accessibilityIdentifier("self-photo-remove")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(editor.isBusy || editor.isLoading)
            }
            .padding(.vertical, DrivySpacing.xxs)
        }
        .drivyFormRows()
    }

    /// Ce que le compte Drivy a dit de son dernier geste : échec de lecture, d’envoi ou de photo, ou enregistrement confirmé.
    @ViewBuilder private var accountMessages: some View {
        if let error = editor.errorMessage {
            Section { DrivyFormMessage(text: error, tone: .danger) }
                .drivyFormRows()
                .accessibilityIdentifier("my-profile-account-error")
        } else if outcome?.account == true, !editor.hasEdits {
            Section { DrivyFormMessage(text: "Compte Drivy enregistré.") }
                .drivyFormRows()
        }
    }

    @ViewBuilder private var accountSections: some View {
        Section {
            DrivyFormField(label: "Prénom", text: $editor.edit.firstName, identifier: "self-first-name")
                .textContentType(.givenName).textInputAutocapitalization(.words).autocorrectionDisabled()
            DrivyFormField(label: "Nom", text: $editor.edit.lastName, identifier: "self-last-name")
                .textContentType(.familyName).textInputAutocapitalization(.words).autocorrectionDisabled()
            DrivyFormField(label: "Nom affiché", text: $editor.edit.displayName, identifier: "self-display-name")
                .textContentType(.name).textInputAutocapitalization(.words).autocorrectionDisabled()
            if !editor.displayNameValid, editor.hasEdits {
                DrivyFormMessage(text: editor.trimmed.displayName.isEmpty ? "Renseigne le nom affiché."
                    : "Raccourcis le nom affiché à 200 caractères.", tone: .danger)
            }
        } header: { Text("Identité").drivyFormSectionHeader() }
            .drivyFormRows()
        Section {
            DrivyFormField(label: "E-mail", text: $editor.edit.contactEmail, prompt: "nom@exemple.ch", identifier: "self-email")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !editor.emailValid { DrivyFormMessage(text: "Vérifie le format de l’adresse e-mail.", tone: .danger) }
            DrivyFormField(label: "Téléphone", text: $editor.edit.contactPhone, identifier: "self-phone")
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
            if !editor.phoneValid { DrivyFormMessage(text: "Ce numéro contient un caractère inattendu.", tone: .danger) }
        } header: { Text("Contact").drivyFormSectionHeader() }
            .drivyFormRows()
        Section { birthRow } header: { Text("Date de naissance").drivyFormSectionHeader() }
            .drivyFormRows()
        Section {
            Toggle("Renseigner une adresse", isOn: $editor.hasAddress.animation(DrivyMotion.feedback(reduceMotion)))
                .drivyControlTint()
                .accessibilityIdentifier("self-address-toggle")
            if editor.hasAddress {
                SchoolPostalAddressFields(address: $editor.address, countryIdentifier: "self-country")
                if !editor.addressValid, !editor.address.line1.trimmingCharacters(in: .whitespaces).isEmpty || !editor.address.countryCode.isEmpty {
                    DrivyFormMessage(text: "Complète la rue, le code postal, la localité et le pays.", tone: .danger)
                }
            }
        } header: { Text("Adresse").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    /// Date civile choisie avec le sélecteur natif ; aucune date n’est posée tant que la personne n’en choisit pas.
    @ViewBuilder private var birthRow: some View {
        if let date = Self.civil.date(from: editor.edit.birthDate) {
            DatePicker("Date de naissance", selection: Binding(get: { date }, set: { editor.edit.birthDate = Self.civil.string(from: $0) }),
                in: Self.earliest...Date(), displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "fr_CH"))
                .accessibilityIdentifier("self-birth-date")
            Button("Retirer la date", role: .destructive) { editor.edit.birthDate = "" }
                .accessibilityIdentifier("self-birth-date-clear")
        } else {
            Button("Ajouter la date de naissance") {
                editor.edit.birthDate = Self.civil.string(from: Calendar(identifier: .gregorian).date(byAdding: .year, value: -18, to: Date()) ?? Date())
            }
            .accessibilityIdentifier("self-birth-date-add")
        }
    }
    private static let civil: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Europe/Zurich"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f
    }()
    private static let earliest = civil.date(from: "1900-01-01") ?? .distantPast

    // MARK: Dossier scolaire

    @ViewBuilder private func dossierSections(_ dossier: SchoolProfileWorkspace) -> some View {
        Section {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text("Dossier scolaire")
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                if let school = dossier.school?.name ?? workspace.membership?.schoolName {
                    Text(school)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .drivyClearRow()
            .listRowInsets(EdgeInsets(top: DrivySpacing.m, leading: 0, bottom: 0, trailing: 0))
        }
        .accessibilityIdentifier("my-profile-dossier")
        SchoolProfileStatusSections(model: dossier)
        let hidden = duplicatedFields(dossier)
        SchoolProfileFieldSections(model: dossier, focusedField: $focusedField, missingFields: missingFields,
            dossierTitle: "Identité dans le dossier", hiddenFields: hidden)
        if !hidden.isEmpty {
            Section {
                Button(hidden.count == 1 ? "Afficher le champ identique au compte" : "Afficher les \(hidden.count) champs identiques au compte") {
                    showsAllDossierFields = true
                }
                .frame(minHeight: DrivyLayout.tapTarget)
                .accessibilityIdentifier("my-profile-show-dossier-fields")
            }
            .drivyFormRows()
        }
        SchoolProfileContextSections(model: dossier, resumeOnboarding: { showsGuidedWelcome = true })
    }

    /// Champs du dossier dont la valeur enregistrée redit celle du compte : ils ne s’affichent pas deux fois. Un champ
    /// modifié, demandé, manquant ou signalé par l’école reste toujours visible ; sans compte lu, rien n’est masqué.
    private func duplicatedFields(_ dossier: SchoolProfileWorkspace) -> Set<SchoolProfileField> {
        guard !showsAllDossierFields, let profile = dossier.profile, let account = workspace.selfProfile else { return [] }
        func same(_ a: String?, _ b: String?) -> Bool {
            let left = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Une valeur vide des deux côtés n’est pas un doublon : elle reste à renseigner dans le dossier.
            return !left.isEmpty && left == (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var fields: Set<SchoolProfileField> = []
        if same(profile.firstName, account.firstName) { fields.insert(.firstName) }
        if same(profile.lastName, account.lastName) { fields.insert(.lastName) }
        if same(profile.contactEmail, account.contactEmail) { fields.insert(.contactEmail) }
        if same(profile.contactPhone, account.contactPhone) { fields.insert(.contactPhone) }
        if same(profile.birthDate, account.birthDate) { fields.insert(.birthDate) }
        if let address = profile.postalAddress, address == account.postalAddress { fields.insert(.postalAddress) }
        let edited = dossier.draft.changes(from: profile, allowed: dossier.editableFields).keys.compactMap(SchoolProfileField.init(rawValue:))
        let flagged = (dossier.readiness?.blockers ?? []).compactMap { $0.field.flatMap(SchoolProfileField.init(rawValue:)) }
        fields.subtract(edited); fields.subtract(flagged); fields.subtract(missingFields)
        fields.subtract(dossier.invalidFields)
        if let focus { fields.remove(focus) }
        return fields
    }

    /// Une fois le dossier à l’écran : défilement jusqu’au champ demandé, puis le clavier, après la montée de la
    /// feuille. Une adresse à renseigner s’ouvre d’elle-même. Une seule fois par ouverture.
    private func openFocus(_ proxy: ScrollViewProxy) async {
        guard let focus, let dossier, !focusApplied, dossier.profile != nil, dossier.editableFields.contains(focus) else { return }
        focusApplied = true
        if focus == .postalAddress && !dossier.draft.hasAddress { dossier.draft.hasAddress = true }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        withAnimation(DrivyMotion.context(reduceMotion)) { proxy.scrollTo(focus, anchor: .center) }
        focusedField = focus
    }

    // MARK: Enregistrement

    private var saveHint: (text: String?, tone: DrivyTone) {
        if let outcome, let text = outcome.partialFailure { return (text, .danger) }
        guard hasEdits, !canSave, !isBusy else { return (nil, .neutral) }
        if dossier?.pending != nil && dossierHasEdits { return ("Vérifie d’abord la demande en attente du dossier.", .neutral) }
        return ("Vérifie les champs signalés.", .neutral)
    }

    /// Le compte puis le dossier, chacun par sa requête. Le résultat de chacun est dit à sa place ; un échec garde sa saisie.
    private func save() {
        guard canSave else { return }
        let savesAccount = editor.hasEdits, savesDossier = dossierHasEdits
        outcome = nil
        Task {
            var account: Bool?
            if savesAccount { account = await editor.save() }
            var saved: Bool?
            if savesDossier, let dossier { saved = await dossier.saveProfileAfterConfirmation() }
            let result = SchoolMyProfileOutcome(account: account, dossier: saved)
            outcome = result
            UIAccessibility.post(notification: .announcement, argument: result.announcement)
        }
    }

    private func prepare(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = await Task.detached(priority: .userInitiated, operation: { SchoolProfilePhotoEncoder.squareJPEG(from: data) }).value
        else { editor.failPhoto(); return }
        upload(jpeg)
    }

    private func upload(_ jpeg: Data?) {
        Task {
            if await editor.setPhoto(jpeg) {
                UIAccessibility.post(notification: .announcement, argument: jpeg == nil ? "Photo retirée" : "Photo enregistrée")
            }
        }
    }
}

/// Ce que le dernier « Enregistrer » a obtenu de chaque source : `nil` quand elle n’avait rien à envoyer.
/// Hors de la vue : la règle se teste telle quelle. Aucun succès n’est annoncé pour l’ensemble si une partie échoue.
struct SchoolMyProfileOutcome: Equatable {
    let account: Bool?
    let dossier: Bool?

    /// La phrase de la barre d’action quand une source a échoué ; `nil` quand rien n’a échoué.
    var partialFailure: String? {
        switch (account, dossier) {
        case (.some(true), .some(false)): "Compte Drivy enregistré. Le dossier de l’école n’a pas été enregistré."
        case (.some(false), .some(true)): "Dossier de l’école enregistré. Le compte Drivy n’a pas été enregistré."
        case (.some(false), .some(false)): "Ni le compte Drivy ni le dossier de l’école n’ont été enregistrés."
        case (.some(false), .none): "Le compte Drivy n’a pas été enregistré."
        case (.none, .some(false)): "Le dossier de l’école n’a pas été enregistré."
        default: nil
        }
    }

    var announcement: String {
        if let partialFailure { return partialFailure }
        switch (account, dossier) {
        case (.some(true), .some(true)): return "Compte Drivy et dossier de l’école enregistrés"
        case (.some(true), _): return "Compte Drivy enregistré"
        case (_, .some(true)): return "Dossier de l’école enregistré"
        default: return ""
        }
    }
}
