import SwiftUI

/// Les champs du dossier scolaire, tels que les droits relus par le serveur les ouvrent : partagés par le formulaire
/// du dossier vu par l’école (`SchoolProfileView`) et par la page « Mon profil » de l’élève.
struct SchoolProfileFieldSections: View {
    @Bindable var model: SchoolProfileWorkspace
    var focusedField: FocusState<SchoolProfileField?>.Binding
    /// Informations requises qui manquaient à l’ouverture ; chacune garde son point tant qu’elle reste vide.
    var missingFields: Set<SchoolProfileField> = []
    /// Sur « Mon profil », les sections du dossier se nomment par l’école : elles suivent celles du compte Drivy.
    var dossierTitle: String? = nil
    /// Champs dont la valeur enregistrée redit celle du compte Drivy : « Mon profil » ne les répète pas.
    var hiddenFields: Set<SchoolProfileField> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let profile = model.profile {
            if shows(.firstName) || shows(.lastName) { identitySection(profile) }
            contactSection
            if model.editableFields.contains(.birthDate), shows(.birthDate) { birthSection }
            if model.editableFields.contains(.postalAddress), shows(.postalAddress) { addressSection }
        }
    }

    private func shows(_ field: SchoolProfileField) -> Bool { !hiddenFields.contains(field) }

    private func isMissing(_ field: SchoolProfileField) -> Bool {
        missingFields.contains(field) && model.draft.isEmpty(field)
    }

    private func identitySection(_ profile: SchoolAdministrativeProfile) -> some View {
        Section {
            if shows(.firstName) {
                if model.editableFields.contains(.firstName) {
                profileField("Prénom", text: $model.draft.firstName, identifier: "profile-first-name", field: .firstName).textContentType(.givenName)
                    .id(SchoolProfileField.firstName)
                fieldExplanation(.firstName)
            } else { LabeledContent("Prénom", value: profile.firstName ?? "À compléter") }
            }
            if shows(.lastName) {
                if model.editableFields.contains(.lastName) {
                profileField("Nom", text: $model.draft.lastName, identifier: "profile-last-name", field: .lastName).textContentType(.familyName)
                    .id(SchoolProfileField.lastName)
                fieldExplanation(.lastName)
            } else { LabeledContent("Nom", value: profile.lastName ?? "À compléter") }
            }
        } header: { Text(dossierTitle ?? "Identité scolaire").drivyFormSectionHeader() }
            .drivyFormRows()
        .disabled(!model.acceptsInput)
    }

    @ViewBuilder private var contactSection: some View {
        let email = model.editableFields.contains(.contactEmail) && shows(.contactEmail)
        let phone = model.editableFields.contains(.contactPhone) && shows(.contactPhone)
        if email || phone {
            Section {
                if email {
                    profileField("E-mail", text: $model.draft.contactEmail, prompt: "nom@exemple.ch", identifier: "profile-email", field: .contactEmail)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .id(SchoolProfileField.contactEmail)
                    fieldExplanation(.contactEmail)
                }
                if phone {
                    profileField("Téléphone", text: $model.draft.contactPhone, identifier: "profile-phone", field: .contactPhone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                        .id(SchoolProfileField.contactPhone)
                    fieldExplanation(.contactPhone)
                }
            } header: { Text(dossierTitle == nil ? "Contacts" : "Coordonnées du dossier").drivyFormSectionHeader() }
                .drivyFormRows()
            .disabled(!model.acceptsInput)
        }
    }

    private var birthSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                TextField("JJ.MM.AAAA", text: $model.draft.birthDate).keyboardType(.numbersAndPunctuation)
                    .focused(focusedField, equals: .birthDate)
                    .accessibilityLabel("Date de naissance, jour point mois point année")
                    .accessibilityValue(isMissing(.birthDate) ? "À renseigner" : "")
                    .accessibilityIdentifier("profile-birth-date")
            }
            .padding(.vertical, DrivySpacing.xxs)
            .id(SchoolProfileField.birthDate)
            fieldExplanation(.birthDate)
        } header: { sectionHeader(dossierTitle == nil ? "Date de naissance" : "Date de naissance du dossier", field: .birthDate) }
            .drivyFormRows()
        .disabled(!model.acceptsInput)
    }

    private var addressSection: some View {
        Section {
            Toggle("Renseigner une adresse", isOn: $model.draft.hasAddress)
                .drivyControlTint()
                .id(SchoolProfileField.postalAddress)
            if model.draft.hasAddress {
                SchoolPostalAddressFields(address: $model.draft.address, focus: focusedField, countryIdentifier: "profile-country")
            }
            fieldExplanation(.postalAddress)
        } header: { sectionHeader(dossierTitle == nil ? "Adresse postale" : "Adresse du dossier", field: .postalAddress) }
            .drivyFormRows()
        .disabled(!model.acceptsInput)
    }

    @ViewBuilder private func fieldExplanation(_ field: SchoolProfileField) -> some View {
        if model.hasEdits, model.invalidFields.contains(field) {
            Label(fieldError(field), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(DrivyTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldError(_ field: SchoolProfileField) -> String {
        switch field {
        case .firstName: "Renseigne le prénom, limité à 150 caractères."
        case .lastName: "Renseigne le nom, limité à 150 caractères."
        case .contactEmail: "Vérifie le format de l’adresse e-mail."
        case .contactPhone: "Le téléphone est limité à 32 caractères."
        case .birthDate: "Utilise JJ.MM.AAAA pour une date réelle, non future."
        case .postalAddress: "Renseigne la rue, le code postal, la localité et le pays."
        case .profilePhotoDocumentId: "Vérifie la photo du profil."
        }
    }

    /// `field` : l’information que la saisie renseigne, pour son point et pour l’ouverture au clavier.
    private func profileField(_ title: String, text: Binding<String>, prompt: String? = nil, identifier: String? = nil,
                              field: SchoolProfileField) -> some View {
        DrivyFormField(label: title, text: text, prompt: prompt, identifier: identifier,
                       isMissing: isMissing(field), focus: focusedField, focusValue: field)
    }

    /// En-tête d’une section d’une seule information : le point la précède tant qu’elle manque.
    private func sectionHeader(_ title: String, field: SchoolProfileField) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
            if isMissing(field) { DrivyActionDot().transition(.opacity) }
            Text(title).drivyFormSectionHeader()
        }
        .animation(DrivyMotion.feedback(reduceMotion), value: isMissing(field))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isMissing(field) ? "À renseigner" : "")
    }
}

/// Ce que le dossier dit autour de ses champs : photo associée, prochaine étape, accueil, explications et notice.
struct SchoolProfileContextSections: View {
    @Bindable var model: SchoolProfileWorkspace
    /// Rouvre l’accueil guidé ; la feuille appartient à l’écran qui porte ces sections.
    let resumeOnboarding: () -> Void

    var body: some View {
        if let profile = model.profile {
            if profile.profilePhotoDocumentId != nil {
                Section {
                    Label("Une photo est associée au dossier", systemImage: "person.crop.circle")
                        .foregroundStyle(DrivyTheme.muted)
                } header: { Text("Photo du dossier").drivyFormSectionHeader() }
                    .drivyFormRows()
            }
            readinessSection
        }
        if let status = model.onboarding?.status, status != "COMPLETED" { onboardingSection }
        explanationsSection
    }

    @ViewBuilder private var readinessSection: some View {
        if let readiness = model.readiness, !readiness.ready {
            Section {
                Label("Accès à l’espace scolaire à préparer", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                SchoolProfileBlockers(blockers: readiness.blockers)
            } header: { Text("Prochaine étape").drivyFormSectionHeader() }
                .drivyFormRows()
        }
    }

    /// The welcome itself is the guided flow (SchoolOnboardingView); this screen
    /// only says where it stands and reopens it. No step is chosen from a list here.
    private var onboardingSection: some View {
        Section {
            Label("Accueil à terminer", systemImage: "figure.wave")
                .font(.headline)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reprendre l’accueil", action: resumeOnboarding)
                .frame(minHeight: DrivyLayout.tapTarget)
                .disabled(model.isBusy || model.hasEdits)
                .accessibilityIdentifier("onboarding-resume")
            if model.hasEdits {
                Text("Enregistre d’abord tes modifications.")
                    .font(.footnote).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: { Text("Accueil dans l’école").drivyFormSectionHeader() }
            .drivyFormRows()
    }

    /// Les deux explications (champs demandés, usage des données) forment un seul groupe :
    /// deux lignes séparées d’un filet plutôt que deux pastilles isolées.
    @ViewBuilder private var explanationsSection: some View {
        let policy = model.applicablePolicy
        let notice = model.notice.flatMap { $0.status == "APPROVED" ? $0 : nil }
        if policy != nil || notice != nil {
            Section {
                if let policy {
                    DisclosureGroup("Pourquoi ces informations ?") {
                        ForEach(policy.fields) { rule in
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text(rule.field.label).font(.subheadline.weight(.semibold))
                                Text(rule.requirement == .optional ? "Facultatif" : "\(rule.requirement.label) · \(rule.stage.label)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                                Text(rule.explanation).font(.footnote).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let notice {
                    // Same wording and content as the notice sheet of the guided welcome.
                    SchoolPrivacyLink(text: .init(notice: notice.noticeText, retention: notice.retentionText, contact: notice.contactEmail),
                        addressesLearner: model.isOwnProfile, identifier: "profile-privacy-link")
                }
            }
            .drivyFormRows()
        }
    }
}

/// Rue, complément, code postal, localité et pays : la même saisie pour le compte Drivy et pour le dossier.
struct SchoolPostalAddressFields: View {
    @Binding var address: SchoolPostalAddress
    /// Le point d’une adresse requise se lit sur l’en-tête de sa section, pas sur la rue.
    var focus: FocusState<SchoolProfileField?>.Binding? = nil
    let countryIdentifier: String

    var body: some View {
        DrivyFormField(label: "Rue et numéro", text: $address.line1,
                       focus: focus, focusValue: focus == nil ? nil : .postalAddress)
            .textContentType(.streetAddressLine1)
        DrivyFormField(label: "Complément · facultatif",
                       text: Binding(get: { address.line2 ?? "" }, set: { address.line2 = $0.isEmpty ? nil : $0 }))
            .textContentType(.streetAddressLine2)
        DrivyFormField(label: "Code postal", text: $address.postalCode).textContentType(.postalCode)
        DrivyFormField(label: "Localité", text: $address.locality).textContentType(.addressCity)
        SchoolCountryPicker(code: $address.countryCode, identifier: countryIdentifier)
    }
}

/// Le serveur attend un code à deux lettres : la personne choisit un pays, elle ne tape pas un code.
/// Le pays de la région de l’appareil vient en tête ; rien n’est présélectionné. Un code déjà enregistré
/// mais absent de la liste garde sa ligne, pour ne jamais afficher une sélection vide.
struct SchoolCountryPicker: View {
    @Binding var code: String
    let identifier: String

    var body: some View {
        let current = code, local = SchoolProfileCountry.local
        Picker("Pays", selection: $code) {
            if !SchoolProfileCountry.all.contains(where: { $0.code == current }) {
                Text(current.isEmpty ? "Choisir" : current).tag(current)
            }
            if let local {
                Text(local.name).tag(local.code)
                Divider()
            }
            ForEach(SchoolProfileCountry.all.filter { $0.code != local?.code }) { country in
                Text(country.name).tag(country.code)
            }
        }
        .frame(minHeight: DrivyLayout.tapTarget)
        .accessibilityIdentifier(identifier)
    }
}
