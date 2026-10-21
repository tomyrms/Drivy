import PhotosUI
import SwiftUI

/// Ce que le compte permet de faire, partagé entre la feuille « Compte » (élève, compte sans école)
/// et l’onglet Profil (moniteur, administration). Une action absente n’est pas affichée.
struct SchoolAccountActions {
    let manageURL: URL?
    let openProfile: (() -> Void)?
    let openInvitations: (() -> Void)?
    let openJoinSchool: (() -> Void)?
    let signOut: () -> Void
    var resumeOnboarding: (() -> Void)? = nil
    /// Un trajet GPS est en cours : quitter le compte ou l’école l’arrêterait, ces gestes demandent alors un accord.
    var tripInProgress = false

    /// Les lignes du compte, dans l’ordre de la feuille. `afterChangingSchool` ferme la feuille qui les porte, s’il y en a une.
    @MainActor @ViewBuilder
    func rows(workspace: SchoolWorkspace?, openURL: OpenURLAction, afterChangingSchool: @escaping () -> Void = {}) -> some View {
        accountRows(workspace: workspace, openURL: openURL, afterChangingSchool: afterChangingSchool)
        lockRow()
        signOutRow()
    }

    /// Le compte et l’école, sans le verrou ni la déconnexion : les Paramètres de l’élève les rangent par sujet.
    @MainActor @ViewBuilder
    func accountRows(workspace: SchoolWorkspace?, openURL: OpenURLAction, afterChangingSchool: @escaping () -> Void = {}) -> some View {
        // Aucun symbole de tête : chaque ligne se lit par son titre, une icône par ligne ne dit rien de plus.
        if let workspace, workspace.person != nil {
            SchoolRenameSelfRow(workspace: workspace)
        }
        if let openProfile {
            DrivyNavigationRow(title: "Mes informations", action: openProfile)
                .accessibilityIdentifier("open-my-profile")
        }
        if let workspace, let error = workspace.ownLearnerError {
            SchoolErrorNotice(message: error, retry: { Task { await workspace.refreshOwnLearner(minimumInterval: 0) } })
        }
        if let resumeOnboarding {
            // Ce qui attend le compte se lit sur sa ligne, en bleu : le point de l’onglet y mène.
            DrivyNavigationRow(title: "Reprendre l’accueil", badge: DrivyStatusBadge(title: "À terminer", tone: .accent), action: resumeOnboarding)
                .accessibilityIdentifier("resume-school-onboarding")
        }
        if let openInvitations {
            DrivyNavigationRow(title: "Invitations", action: openInvitations)
                .accessibilityIdentifier("open-school-invitations")
        }
        if let manageURL {
            DrivyNavigationRow(title: workspace?.school?.status == "DRAFT" ? "Préparer l’école" : "Gérer l’école", detail: "Sur le web", action: {
                workspace?.willOpenManagement()
                openURL(manageURL)
            })
                .accessibilityIdentifier("open-school-management")
        }
        if let workspace, (workspace.person?.memberships.count ?? 0) > 1, !tripInProgress {
            DrivyNavigationRow(title: "Changer d’école", detail: workspace.membership?.schoolName, action: {
                workspace.leaveSchool()
                afterChangingSchool()
            })
            .accessibilityIdentifier("school-change-school")
        }
        if let openJoinSchool {
            DrivyNavigationRow(title: "Rejoindre une école", action: openJoinSchool)
                .accessibilityIdentifier("open-join-school")
        }
    }

    /// « Ouvrir avec Face ID » ; rien sans verrou biométrique sur l’appareil.
    @MainActor func lockRow() -> some View { SchoolAppLockRow() }

    @MainActor func signOutRow() -> some View {
        SchoolSignOutRow(action: signOut, confirms: tripInProgress)
            .accessibilityIdentifier("school-sign-out")
    }
}

/// « Se déconnecter » : la dernière ligne du compte, en danger, au rythme des lignes voisines (titre de ligne et
/// 52 pt sur une page, corps de texte et cellule native dans une liste groupée).
private struct SchoolSignOutRow: View {
    let action: () -> Void
    var confirms = false
    @State private var asksConfirmation = false
    @Environment(\.drivyRowContext) private var context

    var body: some View {
        Group {
            if context == .grouped {
                Button(role: .destructive, action: tap) { label }
            } else {
                Button(role: .destructive, action: tap) { label }
                    .buttonStyle(DrivyRowButtonStyle())
            }
        }
        .confirmationDialog("Un trajet est en cours", isPresented: $asksConfirmation, titleVisibility: .visible) {
            Button("Arrêter le trajet et se déconnecter", role: .destructive, action: action)
            Button("Continuer le trajet", role: .cancel) { }
        }
    }

    private func tap() {
        if confirms { asksConfirmation = true } else { action() }
    }

    private var label: some View {
        Text("Se déconnecter")
            .font(context == .grouped ? .body : .headline)
            .foregroundStyle(DrivyTheme.danger)
            .padding(.vertical, context == .grouped ? DrivySpacing.xs : 0)
            .frame(maxWidth: .infinity, minHeight: context == .grouped ? DrivyLayout.tapTarget : 52, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// Avatar, nom, école puis rôles : l’en-tête du compte.
struct SchoolAccountHeading: View {
    let workspace: SchoolWorkspace?
    let isAuthenticated: Bool
    /// Remplace la ligne des rôles (l’élève lit ses permis : « Permis B »).
    var detail: String? = nil
    /// Faux pour l’élève : son rôle ne lui apprend rien, seule l’école est dite (et `detail`, s’il y en a un).
    var showsRoles = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Même anatomie que l’en-tête du dossier d’un élève (DrivyLearnerIdentity, variante page).
        HStack(spacing: DrivySpacing.s) {
            if !typeSize.isAccessibilitySize {
                DrivyAvatar(name: workspace?.person?.displayName ?? "Compte", size: DrivyAvatar.pageSize, photo: workspace?.selfPhoto?.data)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(workspace?.person?.displayName ?? (isAuthenticated ? "Compte connecté" : "Aucun compte connecté"))
                    .font(.drivyTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let membership = workspace?.membership {
                    // École puis rôles, chacun sur sa ligne : jamais un « · » orphelin en début de ligne.
                    Text(membership.schoolName)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let line = detail ?? (showsRoles ? SchoolPresentation.roles(membership.roles) : nil) {
                        Text(line)
                            .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account-heading")
        .task(id: workspace?.person?.personId) {
            // La photo du compte se lit dès l’en-tête, sans attendre l’ouverture de « Mon profil ».
            if let workspace, workspace.person != nil, workspace.selfProfile == nil { _ = try? await workspace.loadSelfProfile() }
        }
    }
}

/// « Mon profil » : chaque compte (moniteur, administration, élève) tient le sien, sans passer par le web (#64).
/// Le dossier d’élève reste dans « Mes informations » ; ceci est le compte Drivy de la personne.
private struct SchoolRenameSelfRow: View {
    let workspace: SchoolWorkspace
    @State private var editing = false

    var body: some View {
        DrivyNavigationRow(title: "Mon profil", detail: workspace.person?.displayName, action: { editing = true })
            .accessibilityIdentifier("rename-self")
            .sheet(isPresented: $editing) { SchoolSelfProfileSheet(workspace: workspace) }
    }
}

private struct SchoolSelfProfileSheet: View {
    let workspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var edit = SchoolSelfProfileEdit(displayName: "", firstName: "", lastName: "", contactPhone: "")
    @State private var loaded: SchoolSelfProfileEdit?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isSavingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var confirmsRemoval = false
    @State private var error: String?

    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmed: SchoolSelfProfileEdit {
        SchoolSelfProfileEdit(displayName: clean(edit.displayName), firstName: clean(edit.firstName),
            lastName: clean(edit.lastName), contactPhone: clean(edit.contactPhone))
    }
    private var phoneValid: Bool {
        let phone = trimmed.contactPhone
        return phone.isEmpty || (phone.count >= 3 && phone.count <= 32 && phone.allSatisfy { "+0123456789 ().-/".contains($0) })
    }
    private var valid: Bool {
        !trimmed.displayName.isEmpty && trimmed.displayName.count <= 200 && trimmed.firstName.count <= 150
            && trimmed.lastName.count <= 150 && phoneValid
    }
    private var unchanged: Bool { trimmed == loaded }
    private var busy: Bool { isSaving || isSavingPhoto || isLoading }

    var body: some View {
        NavigationStack {
            Form {
                Section { photoRow }
                Section {
                    TextField("Prénom", text: $edit.firstName)
                        .textContentType(.givenName).textInputAutocapitalization(.words).autocorrectionDisabled()
                        .accessibilityIdentifier("self-first-name")
                    TextField("Nom", text: $edit.lastName)
                        .textContentType(.familyName).textInputAutocapitalization(.words).autocorrectionDisabled()
                        .accessibilityIdentifier("self-last-name")
                }
                Section("Nom affiché") {
                    TextField("Nom affiché", text: $edit.displayName)
                        .textContentType(.name).textInputAutocapitalization(.words).autocorrectionDisabled()
                        .accessibilityIdentifier("rename-self-field")
                }
                Section {
                    TextField("Téléphone", text: $edit.contactPhone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                        .accessibilityIdentifier("self-phone")
                } footer: {
                    if let error { DrivyFormMessage(text: error, tone: .danger) }
                    else if !phoneValid { DrivyFormMessage(text: "Ce numéro contient un caractère inattendu.", tone: .danger) }
                    else if trimmed.displayName.count > 200 { DrivyFormMessage(text: "Raccourcis le nom affiché à 200 caractères.", tone: .danger) }
                }
            }
            .disabled(busy)
            .overlay { if isLoading { ProgressView().accessibilityLabel("Chargement du profil") } }
            .navigationTitle("Mon profil").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().accessibilityLabel("Enregistrement…") }
                    else { Button("Enregistrer") { save() }.disabled(!valid || unchanged || busy) }
                }
            }
            .interactiveDismissDisabled(isSaving || isSavingPhoto)
            .confirmationDialog("Retirer la photo ?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Retirer la photo", role: .destructive) { upload(nil) }
            }
        }
        .tint(DrivyTheme.accent)
        .task { await load() }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await prepare(item) }
        }
    }

    private var photoRow: some View {
        HStack(spacing: DrivySpacing.m) {
            ZStack {
                DrivyAvatar(name: trimmed.displayName.isEmpty ? (workspace.person?.displayName ?? "") : trimmed.displayName,
                    size: 72, photo: workspace.selfPhoto?.data)
                if isSavingPhoto { ProgressView().accessibilityLabel("Envoi de la photo…") }
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                    Text(workspace.selfPhoto == nil ? "Ajouter une photo" : "Changer la photo")
                }
                .accessibilityIdentifier("self-photo-pick")
                if workspace.selfProfile?.photoVersion != nil {
                    Button("Retirer la photo", role: .destructive) { confirmsRemoval = true }
                        .accessibilityIdentifier("self-photo-remove")
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, DrivySpacing.xxs)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await workspace.loadSelfProfile()
            fill(from: profile)
        } catch {
            // Le nom du compte reste modifiable même si le profil complet ne se lit pas.
            if let person = workspace.person {
                fill(from: SchoolSelfProfile(personId: person.personId, displayName: person.displayName, version: person.version))
            }
            self.error = (error as? LocalizedError)?.errorDescription ?? SchoolAPIError.unavailable.localizedDescription
        }
    }

    private func fill(from profile: SchoolSelfProfile) {
        let value = SchoolSelfProfileEdit(displayName: profile.displayName, firstName: profile.firstName ?? "",
            lastName: profile.lastName ?? "", contactPhone: profile.contactPhone ?? "")
        edit = value; loaded = value
    }

    private func save() {
        guard valid, !unchanged, !busy else { return }
        isSaving = true; error = nil
        let value = trimmed
        Task {
            do {
                try await workspace.saveSelfProfile(value)
                isSaving = false
                UIAccessibility.post(notification: .announcement, argument: "Profil enregistré")
                dismiss()
            } catch {
                isSaving = false
                if case SchoolSelfProfileFailure.changed = error, let profile = workspace.selfProfile { loaded = SchoolSelfProfileEdit(
                    displayName: profile.displayName, firstName: profile.firstName ?? "", lastName: profile.lastName ?? "",
                    contactPhone: profile.contactPhone ?? "") }
                // La saisie reste en place : elle se corrige ou se renvoie telle quelle.
                self.error = (error as? LocalizedError)?.errorDescription ?? SchoolAPIError.unavailable.localizedDescription
            }
        }
    }

    private func prepare(_ item: PhotosPickerItem) async {
        error = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = await Task.detached(priority: .userInitiated, operation: { SchoolProfilePhotoEncoder.squareJPEG(from: data) }).value
        else { error = SchoolSelfProfileFailure.invalidPhoto.localizedDescription; return }
        upload(jpeg)
    }

    private func upload(_ jpeg: Data?) {
        guard !isSavingPhoto else { return }
        isSavingPhoto = true; error = nil
        Task {
            do {
                try await workspace.setSelfPhoto(jpeg)
                UIAccessibility.post(notification: .announcement, argument: jpeg == nil ? "Photo retirée" : "Photo enregistrée")
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? SchoolAPIError.unavailable.localizedDescription
            }
            isSavingPhoto = false
        }
    }
}

/// Recadre au centre en carré, réduit à 512 px au plus et réencode en JPEG : aucune métadonnée de la photo
/// d’origine (position, appareil) ne part, et l’envoi reste sous la limite de l’école.
enum SchoolProfilePhotoEncoder {
    static let side: CGFloat = 512
    static let maxBytes = 250_000

    static func squareJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let crop = min(width, height)
        guard crop >= 64 else { return nil }
        // L’orientation EXIF est appliquée par le dessin ; le carré se prend dans l’image redressée.
        let upright = image.size
        let edge = min(upright.width, upright.height)
        let target = min(side, edge * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let factor = target / edge
            let drawn = CGSize(width: upright.width * factor, height: upright.height * factor)
            image.draw(in: CGRect(x: (target - drawn.width) / 2, y: (target - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        for quality in [0.82, 0.7, 0.55, 0.4] as [CGFloat] {
            if let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count <= maxBytes { return jpeg }
        }
        return nil
    }
}

/// « Ouvrir avec Face ID » : même hauteur que les lignes de navigation voisines. Le titre nomme déjà
/// la biométrie, le symbole le redisait. Sans verrou biométrique sur l’appareil, la ligne n’existe pas.
private struct SchoolAppLockRow: View {
    @Environment(AppLock.self) private var appLock: AppLock?
    @Environment(\.drivyRowContext) private var context

    var body: some View {
        if let appLock, let biometry = appLock.biometryName {
            Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { appLock.setEnabled($0) })) {
                Text("Ouvrir avec \(biometry)")
                    .font(context == .grouped ? .body : .headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .drivyControlTint()
            .padding(.vertical, context == .grouped ? DrivySpacing.xs : DrivySpacing.s)
            .frame(minHeight: context == .grouped ? DrivyLayout.tapTarget : 52)
            .accessibilityIdentifier("app-lock-toggle")
        }
    }
}
