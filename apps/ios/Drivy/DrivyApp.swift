import SwiftUI
import UIKit

@main
struct DrivyApp: App {
    @State private var identity: IdentitySession
    @State private var workspace: SchoolWorkspace?
    @State private var clients: SchoolHomeClients?
    @State private var appLock: AppLock
    /// Fenêtre du verrou et du masque de confidentialité, au-dessus de toute feuille.
    @State private var cover: AppCoverPresenter
    @State private var offersAppLock = false
    private let configuration: AppConfiguration?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = AppConfiguration.fromBundle()
        self.configuration = configuration
        let identity = IdentitySession(configuration: configuration)
        _identity = State(initialValue: identity)
        let appLock = AppLock()
        _appLock = State(initialValue: appLock)
        _cover = State(initialValue: AppCoverPresenter(lock: appLock))
        // One transport (one URLSession) for the account reads and the shell's clients.
        let transport = SchoolURLSessionTransport()
        _workspace = State(initialValue: configuration.map {
            SchoolWorkspace(api: DrivyAPIClient(baseURL: $0.apiBaseURL, tokenSource: identity, transport: transport))
        })
        _clients = State(initialValue: configuration.map {
            SchoolHomeClients(configuration: $0, tokenSource: identity, transport: transport)
        })
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if let screen = ProcessInfo.processInfo.environment["DRIVY_VISUAL_SCREEN"] {
                if screen == "design-system" || screen == "skeletons" {
                    DrivyDesignSystemGallery(loadingOnly: screen == "skeletons")
                        .environment(\.locale, Locale(identifier: "fr_CH"))
                        .dynamicTypeSize(ProcessInfo.processInfo.environment["DRIVY_VISUAL_LARGE_TEXT"] == "1" ? .accessibility3 : .large)
                        .tint(DrivyTheme.accent)
                } else {
                    SchoolVisualReview(screen: screen)
                }
            } else {
                application
            }
            #else
            application
            #endif
        }
    }

    /// L’offre du verrou cède le pas aux feuilles ouvertes par la connexion (« J’ai un code », lien d’invitation,
    /// accueil guidé) : deux présentations lancées au même instant, une seule arrive à l’écran. Elle attend qu’aucune
    /// ne soit présentée ; au-delà de l’attente, elle sera proposée à la prochaine ouverture de session.
    private func offerAppLockWhenIdle() {
        Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard await SchoolPresentationIdle.wait(isPresenting: { Self.isPresenting }, attempts: 120),
                  identity.isAuthenticated, appLock.shouldOffer else { return }
            offersAppLock = true
        }
    }

    /// Vrai quand une feuille ou un dialogue est présenté depuis la fenêtre de l’app.
    private static var isPresenting: Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            .contains { $0.windowLevel == .normal && $0.rootViewController?.presentedViewController != nil }
    }

    private var application: some View {
            SchoolRootView(configuration: configuration, identity: identity, workspace: workspace, clients: clients)
                .environment(appLock)
                .task {
                    await identity.restore()
                    if !identity.isAuthenticated { appLock.sessionEnded() }
                }
                .onOpenURL { _ = identity.handleRedirect($0) }
                // `initial` : la fenêtre de protection connaît l’état de la scène dès le premier rendu.
                .onChange(of: scenePhase, initial: true) { previous, current in
                    if current == .background { appLock.didEnterBackground() }
                    if previous != .active, current == .active {
                        appLock.didBecomeActive(authenticated: identity.isAuthenticated)
                    }
                    // Coming back never tears the screen down: the account is re-read silently,
                    // at most every five minutes, and only a change of rights reloads the school.
                    if previous != .active, current == .active, identity.isAuthenticated,
                       let workspace, workspace.person != nil, !workspace.isLoadingAccount {
                        // Puis la liste des élèves (ou le dossier de l’élève), au plus une fois par minute.
                        Task { await workspace.refreshAccount(); await workspace.refreshLearners() }
                    }
                    // Après le verrouillage éventuel : au retour, le verrou remplace le masque sans montrer l’app.
                    cover.update(sceneIsActive: current == .active, hasSession: identity.isAuthenticated)
                }
                .onChange(of: appLock.isLocked, initial: true) { _, _ in cover.update() }
                .onChange(of: identity.isAuthenticated) { wasAuthenticated, isAuthenticated in
                    if !isAuthenticated { appLock.sessionEnded() }
                    if !wasAuthenticated, isAuthenticated, appLock.shouldOffer { offerAppLockWhenIdle() }
                    cover.update(hasSession: isAuthenticated)
                }
                .confirmationDialog("Ouvrir Drivy avec \(appLock.biometryName ?? "Face ID") ?",
                                    isPresented: $offersAppLock, titleVisibility: .visible) {
                    Button("Utiliser \(appLock.biometryName ?? "Face ID")") { appLock.answerOffer(enable: true) }
                    Button("Plus tard", role: .cancel) { appLock.answerOffer(enable: false) }
                } message: {
                    Text("Tu restes connecté 30 jours sur cet appareil.")
                }
                // Le verrou et le masque sont dans leur propre fenêtre (`AppCoverPresenter`), au-dessus des feuilles.
                .accessibilityHidden(appLock.isLocked || scenePhase != .active)
    }
}
