import SwiftUI
import UIKit

struct SchoolRootView: View {
    let configuration: AppConfiguration?
    @Bindable var identity: IdentitySession
    let workspace: SchoolWorkspace?
    let localController: SessionController
    @State private var showsAccount = false
    @State private var showsLocalTrials = false
    @State private var opensTrialsAfterAccount = false
    @State private var presenter: UIViewController?

    var body: some View {
        Group {
            if identity.isAuthenticated, let workspace {
                if workspace.person != nil, workspace.membership != nil {
                    SchoolBrowserView(workspace: workspace, openAccount: { showsAccount = true })
                } else {
                    NavigationStack {
                        accountLanding(workspace)
                            .navigationTitle("Mon école")
                            .toolbar { accountToolbar }
                    }
                }
            } else {
                NavigationStack {
                    signInLanding
                        .navigationTitle("Drivy")
                        .toolbar { accountToolbar }
                }
            }
        }
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
        .background(SignInPresenter { presenter = $0 }.frame(width: 0, height: 0))
        .task(id: identity.isAuthenticated) {
            if identity.isAuthenticated { await workspace?.loadAccount() }
            else { workspace?.reset() }
        }
        .onChange(of: identity.isAuthenticated) { _, authenticated in
            if !authenticated { workspace?.reset() }
        }
        .sheet(isPresented: $showsAccount, onDismiss: {
            if opensTrialsAfterAccount {
                opensTrialsAfterAccount = false
                showsLocalTrials = true
            }
        }) {
            SchoolAccountView(identity: identity, workspace: workspace, localController: localController,
                openLocalTrials: {
                    opensTrialsAfterAccount = true
                    showsAccount = false
                }, signOut: signOut)
        }
        .fullScreenCover(isPresented: $showsLocalTrials) {
            QualificationRootView(controller: localController)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Button { showsLocalTrials = false } label: {
                            Label("Retour à Drivy", systemImage: "chevron.left")
                                .frame(minHeight: 44)
                        }
                        Spacer()
                        Text("Essais locaux")
                            .font(.footnote)
                            .foregroundStyle(DrivyTheme.muted)
                    }
                    .padding(.horizontal, 16)
                    .background(DrivyTheme.surface)
                }
                .task { await localController.load() }
        }
    }

    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsAccount = true } label: {
                Label("Compte", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("school-account")
        }
    }

    private var signInLanding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Image(systemName: "steeringwheel")
                    .font(.largeTitle)
                    .foregroundStyle(DrivyTheme.accent)
                    .padding(20)
                    .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Retrouvez votre école.")
                        .font(.largeTitle.weight(.bold))
                    Text("Connectez-vous pour accéder aux dossiers et aux formations qui vous sont autorisés.")
                        .font(.title3)
                        .foregroundStyle(DrivyTheme.muted)
                }
                if configuration == nil {
                    Label("La connexion scolaire n’est pas encore activée dans cette version.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .accessibilityIdentifier("school-not-configured")
                } else {
                    Button(action: signIn) {
                        Label(identity.isWorking ? "Connexion en cours…" : "Se connecter", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .disabled(identity.isWorking || presenter == nil)
                    .accessibilityIdentifier("school-sign-in")
                    if let error = identity.errorMessage {
                        SchoolErrorNotice(message: error)
                    }
                }
                Divider()
                localTrialsEntry
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
    }

    @ViewBuilder
    private func accountLanding(_ workspace: SchoolWorkspace) -> some View {
        if workspace.isLoadingAccount {
            ProgressView("Chargement de vos écoles…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DrivyTheme.canvas)
        } else if let error = workspace.accountError {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SchoolErrorNotice(message: error)
                    if workspace.requiresAuthentication {
                        Button("Se reconnecter") {
                            workspace.reset()
                            Task {
                                await identity.signOut()
                                signIn()
                            }
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                    } else {
                        Button("Actualiser mes écoles") { Task { await workspace.loadAccount() } }
                            .buttonStyle(DrivyPrimaryButtonStyle())
                    }
                    localTrialsEntry
                }
                .padding(24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
        } else if let person = workspace.person, person.memberships.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ContentUnavailableView("Aucune école pour le moment", systemImage: "building.2", description: Text("Votre compte est connecté. Demandez à votre école de vous donner accès à votre dossier."))
                    Button("Actualiser mes écoles") { Task { await workspace.loadAccount() } }
                        .buttonStyle(DrivySecondaryButtonStyle())
                    localTrialsEntry
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
        } else {
            SchoolChooserView(workspace: workspace)
        }
    }

    private var localTrialsEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showsLocalTrials = true } label: {
                Label(localController.isCapturing ? "Revenir à l’essai en cours" : "Essais locaux", systemImage: "map")
                    .frame(minHeight: 48)
            }
            .accessibilityIdentifier("open-local-trials")
            Text("Un espace personnel pour essayer la carte et les observations, séparé des dossiers de l’école.")
                .font(.footnote)
                .foregroundStyle(DrivyTheme.muted)
        }
    }

    private func signIn() {
        guard let presenter else { return }
        Task { await identity.signIn(presenting: presenter) }
    }

    private func signOut() {
        workspace?.reset()
        showsAccount = false
        Task { await identity.signOut() }
    }
}

private struct SchoolAccountView: View {
    @Bindable var identity: IdentitySession
    let workspace: SchoolWorkspace?
    let localController: SessionController
    let openLocalTrials: () -> Void
    let signOut: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Votre compte") {
                    if let person = workspace?.person {
                        Text(person.displayName).font(.headline)
                    } else {
                        Text(identity.isAuthenticated ? "Compte connecté" : "Aucun compte connecté")
                    }
                    if let membership = workspace?.membership {
                        LabeledContent("École", value: membership.schoolName)
                        Text(SchoolPresentation.roles(membership.roles))
                            .foregroundStyle(DrivyTheme.muted)
                    }
                    if identity.isAuthenticated {
                        Button("Actualiser mes accès") {
                            dismiss()
                            Task { await workspace?.loadAccount() }
                        }
                        Button("Se déconnecter", role: .destructive, action: signOut)
                            .accessibilityIdentifier("school-sign-out")
                    }
                }
                Section {
                    Button(action: openLocalTrials) {
                        Label(localController.isCapturing ? "Revenir à l’essai en cours" : "Essais locaux", systemImage: "map")
                    }
                    .accessibilityIdentifier("open-local-trials")
                } footer: {
                    Text("Les essais locaux restent sur cet appareil. Ils ne sont pas des leçons de votre école.")
                }
                Section("Confidentialité") {
                    Text("Cet espace affiche les données autorisées par votre école. Les données scolaires affichées sont retirées à la déconnexion ou au changement d’école.")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .tint(DrivyTheme.accent)
    }
}

/// Resolve the presenting controller in this scene, never an arbitrary window.
private struct SignInPresenter: UIViewControllerRepresentable {
    let resolve: @MainActor (UIViewController) -> Void

    func makeUIViewController(context: Context) -> AnchorController {
        let controller = AnchorController()
        controller.resolve = resolve
        return controller
    }

    func updateUIViewController(_ controller: AnchorController, context: Context) {
        controller.resolve = resolve
    }

    final class AnchorController: UIViewController {
        var resolve: (@MainActor (UIViewController) -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            resolve?(self)
        }
    }
}
