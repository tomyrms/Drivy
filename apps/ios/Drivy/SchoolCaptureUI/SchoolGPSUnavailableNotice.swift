import SwiftUI

/// Le réglage se corrige au bureau ; la relecture ne démarre jamais une capture et conserve la leçon ouverte.
struct SchoolGPSUnavailableNotice: View {
    let reason: SchoolGPSUnavailableReason
    @Bindable var workspace: SchoolWorkspace
    var managementURL: URL? = nil
    var openCapture: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    private var isAdministrator: Bool { workspace.membership?.roles.contains("ADMIN") == true }
    private var isRefreshing: Bool { workspace.isRefreshingEntry || workspace.isLoadingSchool || workspace.isLoadingAccount }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            DrivyInlineMessage(text: reason.message(isAdministrator: isAdministrator), tone: .warning)
            if reason == .moduleDisabled, isAdministrator, let managementURL {
                Button("Gérer le GPS de l’école") {
                    workspace.willOpenManagement()
                    openURL(managementURL)
                }
                .buttonStyle(.drivyText)
                .accessibilityIdentifier("gps-open-school-management")
            }
            if reason.canRefreshSchool {
                Button { Task { await workspace.refreshEntry() } } label: {
                    DrivyBusyLabel(title: "Actualiser les accès", busyTitle: "Vérification…", isBusy: isRefreshing)
                }
                .buttonStyle(.drivyText)
                .disabled(isRefreshing)
                .accessibilityIdentifier("gps-refresh-school")
                if let error = workspace.schoolError {
                    DrivyInlineMessage(text: error, tone: .warning)
                }
            }
            if reason == .captureStopped, let openCapture {
                Button("Revoir le trajet", action: openCapture)
                    .buttonStyle(.drivyText)
                    .accessibilityIdentifier("gps-open-stopped-capture")
            }
        }
        .accessibilityIdentifier("gps-unavailable-notice")
    }
}
