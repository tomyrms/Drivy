import SwiftUI

@main
struct DrivyApp: App {
    @State private var controller = SessionController()
    @State private var identity: IdentitySession
    @State private var workspace: SchoolWorkspace?
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
            SchoolRootView(configuration: configuration, identity: identity,
                           workspace: workspace, localController: controller)
                .task { await identity.restore() }
                .onOpenURL { _ = identity.handleRedirect($0) }
                .onChange(of: scenePhase) { previous, current in
                    if previous != .active, current == .active, identity.isAuthenticated,
                       let workspace, workspace.person != nil, !workspace.isLoadingAccount {
                        Task { await workspace.loadAccount() }
                    }
                }
                .overlay {
                    if scenePhase != .active {
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
}
