import SwiftUI

/// Ce que le compte permet de faire, partagé entre la feuille « Compte » (élève, compte sans école)
/// et l’onglet Profil (moniteur, administration). Une action absente n’est pas affichée.
struct SchoolAccountActions {
    let manageURL: URL?
    let openProfile: (() -> Void)?
    let openInvitations: (() -> Void)?
    let openJoinSchool: (() -> Void)?
    let signOut: () -> Void

    /// Les lignes du compte, dans l’ordre de la feuille. `afterChangingSchool` ferme la feuille qui les porte, s’il y en a une.
    @MainActor @ViewBuilder
    func rows(workspace: SchoolWorkspace?, openURL: OpenURLAction, afterChangingSchool: @escaping () -> Void = {}) -> some View {
        if let openProfile {
            DrivyNavigationRow(title: "Mon profil", symbol: "person.text.rectangle", action: openProfile)
                .accessibilityIdentifier("open-my-profile")
        }
        if let openInvitations {
            DrivyNavigationRow(title: "Invitations", symbol: "envelope", action: openInvitations)
                .accessibilityIdentifier("open-school-invitations")
        }
        if let manageURL {
            DrivyNavigationRow(title: "Gérer l’école", detail: "Sur le web", symbol: "globe",
                action: { openURL(manageURL) })
                .accessibilityIdentifier("open-school-management")
        }
        if let workspace, (workspace.person?.memberships.count ?? 0) > 1 {
            DrivyNavigationRow(title: "Changer d’école", detail: workspace.membership?.schoolName,
                symbol: "arrow.left.arrow.right", action: {
                    workspace.leaveSchool()
                    afterChangingSchool()
                })
                .accessibilityIdentifier("school-change-school")
        }
        if let openJoinSchool {
            DrivyNavigationRow(title: "Rejoindre une école", symbol: "number", action: openJoinSchool)
                .accessibilityIdentifier("open-join-school")
        }
        SchoolAppLockRow()
        DrivyDestructiveRow(title: "Se déconnecter", symbol: "rectangle.portrait.and.arrow.right", action: signOut)
            .accessibilityIdentifier("school-sign-out")
    }
}

/// Avatar, nom, école puis rôles : l’en-tête du compte.
struct SchoolAccountHeading: View {
    let workspace: SchoolWorkspace?
    let isAuthenticated: Bool

    var body: some View {
        HStack(spacing: DrivySpacing.m) {
            DrivyAvatar(name: workspace?.person?.displayName ?? "Compte", size: 72)
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

/// « Ouvrir avec Face ID » : même colonne de symbole et même hauteur que les lignes de navigation voisines.
/// Sans verrou biométrique sur l’appareil, la ligne n’existe pas.
private struct SchoolAppLockRow: View {
    @Environment(AppLock.self) private var appLock: AppLock?
    @ScaledMetric(relativeTo: .title3) private var symbolWidth: CGFloat = 28

    var body: some View {
        if let appLock, let biometry = appLock.biometryName {
            Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { appLock.setEnabled($0) })) {
                HStack(spacing: DrivySpacing.m) {
                    Image(systemName: biometry == "Touch ID" ? "touchid" : "faceid")
                        .font(.title3)
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: symbolWidth)
                        .accessibilityHidden(true)
                    Text("Ouvrir avec \(biometry)")
                        .font(.headline)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, DrivySpacing.s)
            .frame(minHeight: 64)
            .accessibilityIdentifier("app-lock-toggle")
        }
    }
}
