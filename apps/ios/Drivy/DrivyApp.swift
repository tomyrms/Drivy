import SwiftUI

@main
struct DrivyApp: App {
    @State private var controller = SessionController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            QualificationRootView(controller: controller)
                .task { await controller.load() }
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
