import SwiftUI

@main
struct DrivyApp: App {
    @State private var identity: IdentitySession
    @State private var workspace: SchoolWorkspace?
    @State private var appLock = AppLock()
    @State private var offersAppLock = false
    private let configuration: AppConfiguration?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let configuration = AppConfiguration.fromBundle()
        self.configuration = configuration
        let identity = IdentitySession(configuration: configuration)
        _identity = State(initialValue: identity)
        _workspace = State(initialValue: configuration.map {
            SchoolWorkspace(api: DrivyAPIClient(baseURL: $0.apiBaseURL, tokenSource: identity))
        })
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if let screen = ProcessInfo.processInfo.environment["DRIVY_VISUAL_SCREEN"] {
                if screen == "design-system" {
                    DrivyDesignSystemGallery()
                        .environment(\.locale, Locale(identifier: "fr_CH"))
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

    private var application: some View {
            SchoolRootView(configuration: configuration, identity: identity, workspace: workspace)
                .environment(appLock)
                .task {
                    await identity.restore()
                    if !identity.isAuthenticated { appLock.sessionEnded() }
                }
                .onOpenURL { _ = identity.handleRedirect($0) }
                .onChange(of: scenePhase) { previous, current in
                    if current == .background { appLock.didEnterBackground() }
                    if previous != .active, current == .active {
                        appLock.didBecomeActive(authenticated: identity.isAuthenticated)
                    }
                    if previous != .active, current == .active, identity.isAuthenticated,
                       let workspace, workspace.person != nil, !workspace.isLoadingAccount {
                        Task { await workspace.loadAccount() }
                    }
                }
                .onChange(of: identity.isAuthenticated) { wasAuthenticated, isAuthenticated in
                    if !isAuthenticated { appLock.sessionEnded() }
                    if !wasAuthenticated, isAuthenticated, appLock.shouldOffer { offersAppLock = true }
                }
                .confirmationDialog("Ouvrir Drivy avec \(appLock.biometryName ?? "Face ID") ?",
                                    isPresented: $offersAppLock, titleVisibility: .visible) {
                    Button("Utiliser \(appLock.biometryName ?? "Face ID")") { appLock.answerOffer(enable: true) }
                    Button("Plus tard", role: .cancel) { appLock.answerOffer(enable: false) }
                } message: {
                    Text("Vous restez connecté 30 jours sur cet appareil.")
                }
                .overlay {
                    if appLock.isLocked {
                        AppLockView(lock: appLock)
                    } else if scenePhase != .active {
                        Color(.systemBackground)
                            .ignoresSafeArea()
                            .overlay {
                                Image(systemName: "map.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
    }
}
