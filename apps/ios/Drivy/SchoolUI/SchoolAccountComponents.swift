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
        if let openProfile {
            DrivyNavigationRow(title: "Mes informations", action: openProfile)
                .accessibilityIdentifier("open-my-profile")
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
                DrivyAvatar(name: workspace?.person?.displayName ?? "Compte", size: DrivyAvatar.pageSize)
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
            .padding(.vertical, context == .grouped ? DrivySpacing.xs : DrivySpacing.s)
            .frame(minHeight: context == .grouped ? DrivyLayout.tapTarget : 52)
            .accessibilityIdentifier("app-lock-toggle")
        }
    }
}
