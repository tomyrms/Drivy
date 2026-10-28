import PhotosUI
import SwiftUI

/// « Mon profil » : la seule page où une personne consulte et modifie ses informations. Une seule identité (#94) :
/// photo, prénom, nom, nom affiché, e-mail, téléphone, date de naissance et adresse vivent sur son compte Drivy
/// (`/v1/me/profile`) ; toutes ses écoles lisent ces mêmes valeurs. Un seul formulaire, un seul enregistrement.
/// Pour un élève, l’école ouverte ajoute seulement ce qui lui appartient : pourquoi elle demande ces informations,
/// sa notice, ce qui manque encore et l’accueil à reprendre (`SchoolProfileWorkspace`, en lecture).
struct SchoolMyProfileView: View {
    let workspace: SchoolWorkspace
    /// Le contexte de l’école ouverte pour un élève ; `nil` sans dossier (moniteur, administration, compte sans école).
    let dossier: SchoolProfileWorkspace?
    var loadsDossierOnAppear = true
    /// Information manquante à ouvrir : la page défile jusqu’à elle et la met au clavier.
    var focus: SchoolProfileField? = nil
    /// Informations requises qui manquaient à l’ouverture ; chacune garde son point tant qu’elle reste vide.
    var missingFields: Set<SchoolProfileField> = []
    @State private var editor: SchoolSelfProfileEditor
    @FocusState private var focusedField: SchoolProfileField?
    @State private var focusApplied = false
    @State private var pickedPhoto: PhotosPickerItem?
    /// La photo choisie, en attente de son cadrage : rien n’est envoyé avant « Utiliser ».
    @State private var cropping: PhotoCropRequest?
    @State private var confirmsPhotoRemoval = false
    @State private var confirmsDiscard = false
    @State private var showsGuidedWelcome = false
    @State private var savedOnce = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(workspace: SchoolWorkspace, dossier: SchoolProfileWorkspace?, loadsDossierOnAppear: Bool = true,
         focus: SchoolProfileField? = nil, missingFields: Set<SchoolProfileField> = []) {
        self.workspace = workspace; self.dossier = dossier; self.loadsDossierOnAppear = loadsDossierOnAppear
        self.focus = focus; self.missingFields = missingFields
        _editor = State(initialValue: SchoolSelfProfileEditor(workspace: workspace))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                form
                    .task(id: editor.isLoading) { await openFocus(proxy) }
            }
            .navigationTitle("Mon profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { if editor.hasEdits { confirmsDiscard = true } else { dismiss() } }
                        .disabled(editor.isBusy || editor.photoIntent != nil)
                        .accessibilityIdentifier("my-profile-close")
                }
            }
            .alert("Quitter sans enregistrer tes changements ?", isPresented: $confirmsDiscard) {
                Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) { }
            } message: {
                // La photo part seule, dès qu’elle est cadrée : la fermeture n’abandonne que le reste (#155).
                if editor.photoChanged { Text("Ta photo est déjà enregistrée. Seuls les autres changements seront perdus.") }
            }
            .confirmationDialog("Retirer la photo ?", isPresented: $confirmsPhotoRemoval, titleVisibility: .visible) {
                Button("Retirer la photo", role: .destructive) { upload(nil) }
            }
            .sheet(isPresented: $showsGuidedWelcome) {
                if let dossier { SchoolOnboardingView(model: dossier, trainings: workspace.trainings) }
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(editor.hasEdits || editor.isBusy || editor.photoIntent != nil)
        .onChange(of: editor.photoResult) { _, result in
            if let result { UIAccessibility.post(notification: .announcement, argument: result) }
        }
        .onChange(of: editor.photoErrorMessage) { _, error in
            if let error { UIAccessibility.post(notification: .announcement, argument: error) }
        }
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
            messages
            identitySection
            contactSection
            birthSection
            addressSection
            if let dossier { SchoolProfileContextSections(model: dossier, resumeOnboarding: { showsGuidedWelcome = true }) }
        }
        .disabled(editor.isLoading)
        .sheet(item: $cropping) { request in
            SchoolProfilePhotoCropView(image: request.image, confirm: { rect in
                cropping = nil
                finishCrop(request.preview, crop: rect)
            }, cancel: { cropping = nil })
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            // Une saisie en cours n’est jamais remplacée par la relecture.
            if !editor.hasEdits { await editor.load() }
            if let dossier, !dossier.isBusy { await dossier.load() }
        }
        .safeAreaInset(edge: .bottom) {
            if editor.hasEdits || editor.isSaving {
                DrivyFormActionBar(hint: editor.hasEdits && !editor.valid ? "Vérifie les champs signalés." : nil) {
                    Button(action: save) { DrivyBusyLabel(title: "Enregistrer", isBusy: editor.isSaving) }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .disabled(!editor.canSave)
                        .accessibilityIdentifier("my-profile-save")
                }
            }
        }
    }

    // MARK: Sections

    /// Le nom affiché saisi, ou celui du compte tant qu’il est vide : l’aperçu de la photo le montre tel quel.
    private var previewName: String {
        editor.trimmed.displayName.isEmpty ? (workspace.person?.displayName ?? "") : editor.trimmed.displayName
    }

    private var photoSection: some View {
        Section {
            HStack(spacing: DrivySpacing.m) {
                ZStack {
                    // Le dernier choix s’affiche aussitôt ; les autres membres ne le voient qu’après l’école (#118).
                    DrivyAvatar(name: previewName, size: 72, photo: editor.displayedPhoto(confirmed: workspace.selfPhoto?.data))
                        .opacity(editor.photoIntent == nil ? 1 : 0.6)
                    if editor.photoIntent != nil { ProgressView().accessibilityLabel("Envoi de la photo…") }
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    // L’aperçu : la photo et le nom affiché, comme les membres de l’école les voient (#157).
                    Text(previewName)
                        .font(.headline)
                        .foregroundStyle(DrivyTheme.text)
                        .lineLimit(2)
                        .accessibilityLabel("Aperçu : \(previewName)")
                        .accessibilityIdentifier("self-display-name-preview")
                    PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                        Text(editor.showsPhoto(confirmedVersion: workspace.selfProfile?.photoVersion) ? "Changer la photo" : "Ajouter une photo")
                    }
                    .accessibilityIdentifier("self-photo-pick")
                    if editor.showsPhoto(confirmedVersion: workspace.selfProfile?.photoVersion) {
                        Button("Retirer la photo", role: .destructive) { confirmsPhotoRemoval = true }
                            .accessibilityIdentifier("self-photo-remove")
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, DrivySpacing.xxs)
            // Le résultat de la photo, près d’elle : elle s’enregistre sans le bouton « Enregistrer » (#155).
            if let error = editor.photoErrorMessage {
                DrivyFormMessage(text: error, tone: .danger)
                    .accessibilityIdentifier("my-profile-photo-error")
                if editor.failedPhoto != nil {
                    Button("Réessayer") { editor.retryPhoto() }
                        .accessibilityHint("Renvoie la dernière photo choisie")
                        .accessibilityIdentifier("my-profile-photo-retry")
                }
            } else if editor.photoIntent != nil {
                Text(editor.photoIntent == .remove ? "Retrait de la photo en cours" : "Envoi de la photo en cours")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .accessibilityIdentifier("my-profile-photo-pending")
            } else if let result = editor.photoResult {
                DrivyFormMessage(text: result)
                    .accessibilityIdentifier("my-profile-photo-result")
            }
        }
        .drivyFormRows()
    }

    /// Le résultat du dernier geste : échec de lecture, d’envoi ou de photo, ou enregistrement confirmé par l’école.
    @ViewBuilder private var messages: some View {
        if let error = editor.errorMessage {
            Section { DrivyFormMessage(text: error, tone: .danger) }
                .drivyFormRows()
                .accessibilityIdentifier("my-profile-error")
        } else if savedOnce, !editor.hasEdits {
            Section { DrivyFormMessage(text: "Profil enregistré.") }
                .drivyFormRows()
        }
    }

    private var identitySection: some View {
        Section {
            field("Prénom", text: $editor.edit.firstName, identifier: "self-first-name", field: .firstName)
                .textContentType(.givenName).textInputAutocapitalization(.words).autocorrectionDisabled()
            field("Nom", text: $editor.edit.lastName, identifier: "self-last-name", field: .lastName)
                .textContentType(.familyName).textInputAutocapitalization(.words).autocorrectionDisabled()
            DrivyFormField(label: "Nom affiché", text: $editor.edit.displayName, identifier: "self-display-name",
                info: "Le nom que voient les membres de ton école, dans les listes et Messages. Ton prénom et ton nom ne changent pas.")
                .textContentType(.name).textInputAutocapitalization(.words).autocorrectionDisabled()
            if editor.hasEdits, !editor.displayNameValid {
                DrivyFormMessage(text: editor.trimmed.displayName.isEmpty ? "Renseigne le nom affiché."
                    : "Raccourcis le nom affiché à 200 caractères.", tone: .danger)
            }
        } header: { Text("Identité").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    private var contactSection: some View {
        Section {
            // L’adresse où l’école peut écrire, distincte de celle de la connexion (#158).
            field("E-mail de contact", text: $editor.edit.contactEmail, prompt: "nom@exemple.ch", identifier: "self-email",
                  field: .contactEmail, info: "L’adresse où ton école peut t’écrire. L’adresse de connexion ne change pas.")
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !editor.emailValid { DrivyFormMessage(text: "Vérifie le format de l’e-mail de contact.", tone: .danger) }
            field("Téléphone", text: $editor.edit.contactPhone, identifier: "self-phone", field: .contactPhone)
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
            if !editor.phoneValid { DrivyFormMessage(text: "Ce numéro contient un caractère inattendu.", tone: .danger) }
        } header: { Text("Contact").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    private var birthSection: some View {
        Section { birthRow } header: { header("Date de naissance", field: .birthDate) }
            .drivyFormRows()
            .id(SchoolProfileField.birthDate)
    }

    private var addressSection: some View {
        Section {
            Toggle("Renseigner une adresse", isOn: $editor.hasAddress.animation(DrivyMotion.feedback(reduceMotion)))
                .drivyControlTint()
                .accessibilityIdentifier("self-address-toggle")
                .id(SchoolProfileField.postalAddress)
            if editor.hasAddress {
                SchoolPostalAddressFields(address: $editor.address, focus: $focusedField, countryIdentifier: "self-country")
                if !editor.addressValid, !editor.address.line1.trimmingCharacters(in: .whitespaces).isEmpty || !editor.address.countryCode.isEmpty {
                    DrivyFormMessage(text: "Complète la rue, le code postal, la localité et le pays.", tone: .danger)
                }
            }
        } header: { header("Adresse", field: .postalAddress) }
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

    // MARK: Champs requis par l’école

    /// Une information que l’école demande et qui manque encore : son point la précède jusqu’à la saisie.
    private func isMissing(_ field: SchoolProfileField) -> Bool {
        guard missingFields.contains(field) else { return false }
        switch field {
        case .firstName: return editor.trimmed.firstName.isEmpty
        case .lastName: return editor.trimmed.lastName.isEmpty
        case .contactEmail: return editor.trimmed.contactEmail.isEmpty
        case .contactPhone: return editor.trimmed.contactPhone.isEmpty
        case .birthDate: return editor.edit.birthDate.isEmpty
        case .postalAddress: return !editor.addressValid || !editor.hasAddress
        case .profilePhotoDocumentId: return false
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String? = nil, identifier: String, field: SchoolProfileField,
                       info: String? = nil) -> some View {
        DrivyFormField(label: title, text: text, prompt: prompt, identifier: identifier, isMissing: isMissing(field),
                       focus: $focusedField, focusValue: field, info: info)
            .id(field)
    }

    private func header(_ title: String, field: SchoolProfileField) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
            if isMissing(field) { DrivyActionDot().transition(.opacity) }
            Text(title).drivyFormSectionHeader()
        }
        .animation(DrivyMotion.feedback(reduceMotion), value: isMissing(field))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMissing(field) ? "À renseigner" : "")
    }

    /// Une fois le compte lu : défilement jusqu’à l’information demandée, puis le clavier. Une seule fois par ouverture.
    private func openFocus(_ proxy: ScrollViewProxy) async {
        guard let focus, !focusApplied, !editor.isLoading else { return }
        focusApplied = true
        if focus == .postalAddress && !editor.hasAddress { editor.hasAddress = true }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        withAnimation(DrivyMotion.context(reduceMotion)) { proxy.scrollTo(focus, anchor: .center) }
        if focus != .birthDate { focusedField = focus == .postalAddress ? .postalAddress : focus }
    }

    // MARK: Enregistrement

    /// Une seule requête : le compte. L’école relit ensuite ce qui lui manque encore.
    private func save() {
        guard editor.canSave else { return }
        Task {
            let ok = await editor.save()
            savedOnce = ok
            UIAccessibility.post(notification: .announcement, argument: ok ? "Profil enregistré" : (editor.errorMessage ?? "Le profil n’a pas été enregistré."))
            if ok, let dossier, !dossier.isBusy { await dossier.load() }
        }
    }

    /// Le fichier choisi est redressé et réduit hors du fil principal, puis proposé au cadrage.
    private func prepare(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let preview = await Task.detached(priority: .userInitiated, operation: { SchoolProfilePhotoEncoder.uprightPreview(from: data) }).value,
              let image = UIImage(data: preview)
        else { editor.failPhoto(); return }
        cropping = PhotoCropRequest(preview: preview, image: image)
    }

    /// Seul le carré cadré part, réencodé sans métadonnées.
    private func finishCrop(_ preview: Data, crop: CGRect) {
        Task {
            guard let jpeg = await Task.detached(priority: .userInitiated, operation: {
                SchoolProfilePhotoEncoder.squareJPEG(fromPreview: preview, crop: crop)
            }).value else { editor.failPhoto(); return }
            upload(jpeg)
        }
    }

    private func upload(_ jpeg: Data?) {
        editor.choosePhoto(jpeg)
    }
}

/// Une photo choisie, réduite, en attente de son cadrage.
private struct PhotoCropRequest: Identifiable {
    let id = UUID()
    let preview: Data
    let image: UIImage
}
