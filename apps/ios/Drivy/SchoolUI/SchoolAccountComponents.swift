import ImageIO
import SwiftUI
import UIKit

/// Ce que le compte permet de faire, partagé entre la feuille « Compte » (élève, compte sans école)
/// et l’onglet Profil (moniteur, administration). Une action absente n’est pas affichée.
struct SchoolAccountActions {
    let manageURL: URL?
    /// Ouvre « Mon profil », la seule page du compte Drivy et, pour un élève, de son dossier dans l’école ouverte.
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
    /// `includesProfile` : faux sur le Profil du moniteur, où « Mon profil » s’ouvre par le crayon de l’en-tête
    /// et vit dans Paramètres. `chooseSchool` : la feuille d’école des onglets, la même que le bouton de la barre.
    @MainActor @ViewBuilder
    func accountRows(workspace: SchoolWorkspace?, openURL: OpenURLAction, includesProfile: Bool = true,
                     chooseSchool: (() -> Void)? = nil,
                     afterChangingSchool: @escaping () -> Void = {}) -> some View {
        // Aucun symbole de tête : chaque ligne se lit par son titre, une icône par ligne ne dit rien de plus.
        if includesProfile, let openProfile, let person = workspace?.person {
            DrivyNavigationRow(title: "Mon profil", detail: person.displayName, action: openProfile)
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
            SchoolChangeSchoolRow(workspace: workspace, chooseSchool: chooseSchool, afterChangingSchool: afterChangingSchool)
        }
        if let openJoinSchool {
            DrivyNavigationRow(title: "Rejoindre une école", action: openJoinSchool)
                .accessibilityIdentifier("open-join-school")
        }
    }

    /// Ce que montre la section Compte sans « Mon profil » (passé dans Paramètres) : vide, elle n’est pas posée.
    @MainActor func hasSchoolRows(workspace: SchoolWorkspace?) -> Bool {
        workspace?.ownLearnerError != nil || resumeOnboarding != nil || openInvitations != nil || manageURL != nil
            || ((workspace?.person?.memberships.count ?? 0) > 1 && !tripInProgress) || openJoinSchool != nil
    }

    /// « Ouvrir avec Face ID » ; rien sans verrou biométrique sur l’appareil.
    @MainActor func lockRow() -> some View { SchoolAppLockRow() }

    @MainActor func signOutRow() -> some View {
        SchoolSignOutRow(action: signOut, confirms: tripInProgress)
            .accessibilityIdentifier("school-sign-out")
    }
}

/// « Changer d’école » ouvre le même choix que le bouton d’école de la barre, l’école ouverte cochée. Fermer ou
/// reprendre l’école ouverte ne quitte rien ; seule une autre école vide l’ancienne portée. Dans les onglets, c’est
/// la feuille de l’accueil (`chooseSchool`) : elle survit au changement, qui reconstruit les onglets. Ailleurs (feuille
/// « Compte »), la ligne présente la même feuille et ne ferme la sienne qu’après un vrai changement.
private struct SchoolChangeSchoolRow: View {
    @Bindable var workspace: SchoolWorkspace
    let chooseSchool: (() -> Void)?
    let afterChangingSchool: () -> Void
    @State private var choosesSchool = false
    @State private var changedSchool = false

    var body: some View {
        DrivyNavigationRow(title: "Changer d’école", detail: workspace.membership?.schoolName, action: {
            if let chooseSchool { chooseSchool() } else { changedSchool = false; choosesSchool = true }
        })
        .accessibilityIdentifier("school-change-school")
        .sheet(isPresented: $choosesSchool, onDismiss: { if changedSchool { afterChangingSchool() } }) {
            SchoolChooserSheet(workspace: workspace, close: { choosesSchool = false },
                didChangeSchool: { changedSchool = true })
        }
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

/// Avatar, nom, école puis rôles : l’en-tête du compte. `edit` pose à droite le crayon qui ouvre « Mon profil ».
struct SchoolAccountHeading: View {
    let workspace: SchoolWorkspace?
    let isAuthenticated: Bool
    /// Remplace la ligne des rôles (l’élève lit ses permis : « Permis B »).
    var detail: String? = nil
    /// Faux pour l’élève : son rôle ne lui apprend rien, seule l’école est dite (et `detail`, s’il y en a un).
    var showsRoles = true
    /// Ouvre « Mon profil » ; absent, aucun crayon n’est montré.
    var edit: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.s) {
            identity
            if let edit, workspace?.person != nil {
                Spacer(minLength: DrivySpacing.xs)
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DrivyTheme.accent)
                        .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                        .background(DrivyTheme.surfaceRaised, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modifier mon profil")
                .accessibilityIdentifier("profile-edit")
            }
        }
        .task(id: workspace?.person?.personId) {
            // La photo du compte se lit dès l’en-tête, sans attendre l’ouverture de « Mon profil ».
            if let workspace, workspace.person != nil, workspace.selfProfile == nil { _ = try? await workspace.loadSelfProfile() }
        }
    }

    /// Même anatomie que l’en-tête du dossier d’un élève (DrivyLearnerIdentity, variante page), lue d’un seul tenant.
    private var identity: some View {
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
    }
}


/// Recadre au centre en carré, réduit à 512 px au plus et réencode en JPEG : aucune métadonnée de la photo
/// d’origine (position, appareil) ne part, et l’envoi reste sous la limite de l’école.
/// La photo de profil, du fichier choisi à l’avatar envoyé (#156). L’original n’est jamais envoyé ni gardé : il est
/// redressé et réduit en mémoire pour le cadrage, puis seul le carré choisi est réencodé, sans métadonnées.
enum SchoolProfilePhotoEncoder {
    static let side: CGFloat = 512
    static let maxBytes = 250_000
    /// Plus grand côté de l’aperçu de cadrage : assez pour un avatar net, sans décoder une photo de 48 Mpx en entier.
    static let previewMaxPixel = 2048
    static let maxZoom: CGFloat = 4

    /// L’image redressée (orientation EXIF appliquée) et réduite par ImageIO, réencodée sans ses métadonnées.
    static func uprightPreview(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: previewMaxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              min(image.width, image.height) >= 64 else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.9)
    }

    /// Points d’écran par pixel de l’image : au zoom 1, le petit côté remplit le cadre.
    static func displayScale(imageSize: CGSize, frameSide: CGFloat, zoom: CGFloat) -> CGFloat {
        let short = min(imageSize.width, imageSize.height)
        guard short > 0, frameSide > 0 else { return 1 }
        return frameSide / short * min(maxZoom, max(1, zoom))
    }

    /// Déplacement du centre de l’image, borné pour qu’elle couvre toujours le cadre.
    static func clampedOffset(_ offset: CGSize, imageSize: CGSize, frameSide: CGFloat, zoom: CGFloat) -> CGSize {
        let scale = displayScale(imageSize: imageSize, frameSide: frameSide, zoom: zoom)
        let maxX = max(0, (imageSize.width * scale - frameSide) / 2)
        let maxY = max(0, (imageSize.height * scale - frameSide) / 2)
        return CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }

    /// Le carré de l’image, en pixels, vu dans le cadre.
    static func cropRect(imageSize: CGSize, frameSide: CGFloat, zoom: CGFloat, offset: CGSize) -> CGRect {
        let scale = displayScale(imageSize: imageSize, frameSide: frameSide, zoom: zoom)
        let shown = clampedOffset(offset, imageSize: imageSize, frameSide: frameSide, zoom: zoom)
        let edge = frameSide / scale
        return CGRect(x: imageSize.width / 2 - (frameSide / 2 + shown.width) / scale,
                      y: imageSize.height / 2 - (frameSide / 2 + shown.height) / scale,
                      width: edge, height: edge)
    }

    /// Le carré choisi dans l’aperçu, en JPEG de 512 px au plus et 250 ko au plus.
    static func squareJPEG(fromPreview data: Data, crop: CGRect) -> Data? {
        guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        let square = crop.integral.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let edge = min(square.width, square.height)
        guard edge >= 64, let cropped = cg.cropping(to: CGRect(x: square.minX, y: square.minY, width: edge, height: edge)) else {
            return nil
        }
        let target = min(side, edge)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: target, height: target))
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
