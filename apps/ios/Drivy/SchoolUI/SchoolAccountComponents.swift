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
        // Aucun symbole de tête : chaque ligne se lit par son titre, une icône par ligne ne dit rien de plus.
        if let openProfile {
            DrivyNavigationRow(title: "Mon profil", action: openProfile)
                .accessibilityIdentifier("open-my-profile")
        }
        if let resumeOnboarding {
            DrivyNavigationRow(title: "Reprendre l’accueil", action: resumeOnboarding)
                .accessibilityIdentifier("resume-school-onboarding")
        }
        if let openInvitations {
            DrivyNavigationRow(title: "Invitations", action: openInvitations)
                .accessibilityIdentifier("open-school-invitations")
        }
        if let manageURL {
            DrivyNavigationRow(title: "Gérer l’école", detail: "Sur le web", action: { openURL(manageURL) })
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
        SchoolAppLockRow()
        SchoolSignOutRow(action: signOut, confirms: tripInProgress)
            .accessibilityIdentifier("school-sign-out")
    }
}

/// « Se déconnecter » : même ligne que `DrivyDestructiveRow` (danger, 52 pt, retour d’appui de ligne),
/// sans symbole puisque les lignes voisines n’en portent plus.
private struct SchoolSignOutRow: View {
    let action: () -> Void
    var confirms = false
    @State private var asksConfirmation = false

    var body: some View {
        Button(role: .destructive) {
            if confirms { asksConfirmation = true } else { action() }
        } label: {
            Text("Se déconnecter")
                .font(.headline)
                .foregroundStyle(DrivyTheme.danger)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(DrivyRowButtonStyle())
        .confirmationDialog("Un trajet est en cours", isPresented: $asksConfirmation, titleVisibility: .visible) {
            Button("Arrêter le trajet et se déconnecter", role: .destructive, action: action)
            Button("Continuer le trajet", role: .cancel) { }
        }
    }
}

/// Avatar, nom, école puis rôles : l’en-tête du compte.
struct SchoolAccountHeading: View {
    let workspace: SchoolWorkspace?
    let isAuthenticated: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: DrivySpacing.m) {
            if !typeSize.isAccessibilitySize {
                DrivyAvatar(name: workspace?.person?.displayName ?? "Compte", size: 52)
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
                    Text(SchoolPresentation.roles(membership.roles))
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("account-heading")
    }
}

/// « Ouvrir avec Face ID » : même hauteur que les lignes de navigation voisines. Le titre nomme déjà
/// la biométrie, le symbole le redisait. Sans verrou biométrique sur l’appareil, la ligne n’existe pas.
private struct SchoolAppLockRow: View {
    @Environment(AppLock.self) private var appLock: AppLock?

    var body: some View {
        if let appLock, let biometry = appLock.biometryName {
            Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { appLock.setEnabled($0) })) {
                Text("Ouvrir avec \(biometry)")
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DrivySpacing.s)
            .frame(minHeight: 52)
            .accessibilityIdentifier("app-lock-toggle")
        }
    }
}
