import SwiftUI

/// Onglet Profil du moniteur et de l’administration : le compte en tête (avatar, école, rôle, réglages),
/// puis les trajets que le serveur laisse lire à ce compte. L’administration voit ceux de toute l’école
/// et peut les filtrer ; le moniteur voit les siens.
struct SchoolProfileTabView: View {
    @Bindable var workspace: SchoolWorkspace
    let account: SchoolAccountActions?
    var agendaClient: SchoolAgendaClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
    var chooseSchool: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Profil")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if let chooseSchool {
                        DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName,
                            chooseSchool: chooseSchool)
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        if let agendaClient {
            SchoolTripsView(workspace: workspace, agendaClient: agendaClient, captureController: captureController) {
                accountSections
            }
        } else {
            List { accountSections }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: DrivyLayout.formColumn)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.canvas)
        }
    }

    /// Deux sections en tête de la liste : l’en-tête du compte, puis ses lignes.
    @ViewBuilder private var accountSections: some View {
        Section {
            SchoolAccountHeading(workspace: workspace, isAuthenticated: true)
        }
        .listRowInsets(EdgeInsets(top: DrivySpacing.s, leading: DrivySpacing.m, bottom: DrivySpacing.s, trailing: DrivySpacing.m))
        .listRowBackground(Color.clear)
        if let account {
            Section {
                account.rows(workspace: workspace, openURL: openURL)
                    // Les rangées portent déjà leur espacement vertical : sans cela, la liste le double.
                    .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
            }
            .drivyFormRows()
        }
        if let agendaClient, let person = workspace.person, let membership = workspace.membership,
           membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") {
            Section {
                NavigationLink("Préférences de leçon") {
                    SchoolPlanningSettingsView(scope: agendaClient.scope(person: person, membership: membership), client: agendaClient.planningClient)
                }
            }.drivyFormRows()
        }
    }
}
