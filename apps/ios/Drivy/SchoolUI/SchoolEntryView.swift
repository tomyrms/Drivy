import SwiftUI

/// L'accueil scolaire attend l'activation web ; aucun onglet terrain vide ne masque la prochaine action.
struct SchoolEntryView: View {
    @Bindable var workspace: SchoolWorkspace
    let portalURL: URL?
    let openAccount: () -> Void
    var chooseSchool: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.schoolMessagingEntry) private var messagingEntry
    @State private var portalError: String?

    private var destination: SchoolEntryDestination { workspace.entryDestination }
    private var isWorking: Bool { workspace.isLoadingSchool || workspace.isLoadingAccount || workspace.isRefreshingEntry }
    private var opensPortal: Bool { destination == .prepareSchool || destination == .management }
    private var title: String {
        switch destination {
        case .prepareSchool: "Préparer votre école"
        case .waitingForActivation: "L’école se prépare"
        case .management: "Gestion de votre école"
        case .archived: "École archivée"
        case .loading: "Ouverture de l’école"
        default: "École indisponible"
        }
    }
    private var symbol: String {
        switch destination {
        case .prepareSchool: "list.bullet.rectangle"
        case .waitingForActivation, .loading: "building.2"
        case .management: "desktopcomputer"
        case .archived: "archivebox"
        default: "exclamationmark.triangle"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if destination == .loading && workspace.schoolError == nil {
                        DrivySkeletonRows(count: 3).drivySkeleton("Ouverture de l’école…")
                    } else {
                        ContentUnavailableView {
                            Label(title, systemImage: symbol)
                                .accessibilityIdentifier("school-entry-status")
                        } description: {
                            EmptyView()
                        } actions: {
                            if opensPortal, let portalURL {
                                Button(destination == .prepareSchool ? "Continuer la préparation sur le web" : "Ouvrir le portail web") {
                                    portalError = nil
                                    workspace.willOpenManagement()
                                    openURL(portalURL) { accepted in
                                        if !accepted { portalError = "Le portail n’a pas pu s’ouvrir. Réessayez." }
                                    }
                                }
                                .buttonStyle(DrivyPrimaryButtonStyle())
                                .accessibilityIdentifier("school-open-portal")
                            }
                            Button("Actualiser") { Task { await workspace.refreshEntry() } }
                                .buttonStyle(DrivySecondaryButtonStyle())
                                .disabled(isWorking)
                                .accessibilityIdentifier("school-entry-refresh")
                        }
                    }
                    if let error = portalError ?? workspace.schoolError {
                        SchoolErrorNotice(message: error)
                    } else if opensPortal && portalURL == nil {
                        SchoolErrorNotice(message: "Le portail de l’école n’est pas configuré.")
                    }
                    if isWorking && destination != .loading { ProgressView("Vérification de l’école…") }
                }
                .drivyPageContent(maxWidth: DrivyLayout.narrowColumn)
            }
            .refreshable { await workspace.refreshEntry() }
            .background(DrivyTheme.surface)
            .navigationTitle(workspace.school?.name ?? workspace.membership?.schoolName ?? "Drivy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if destination == .management, messagingEntry != nil {
                    ToolbarItem(placement: .primaryAction) { SchoolMessagingEntryButton() }
                }
                DrivyAccountToolbarItem(openAccount: openAccount)
                if let chooseSchool {
                    DrivySchoolToolbarItem(schoolName: workspace.membership?.schoolName, chooseSchool: chooseSchool)
                }
            }
        }
    }
}
