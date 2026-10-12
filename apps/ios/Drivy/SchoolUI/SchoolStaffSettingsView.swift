import SwiftUI

/// Profil → Paramètres (moniteur, administration) : préférences de leçon, signalements de l’école, apparence,
/// verrou de l’app et déconnexion. Mêmes lignes et même rangement que les Paramètres de l’élève
/// (`SchoolLearnerSettingsView`) : rien n’est copié, chaque ligne vient de son écran ou de `SchoolAccountActions`.
/// Le compte (informations, invitations, école) reste sur le Profil.
struct SchoolStaffSettingsView: View {
    let workspace: SchoolWorkspace
    let account: SchoolAccountActions?
    let agendaClient: SchoolAgendaClient?
    /// Ouvre la feuille « Préférences de leçon », portée par l’onglet Profil (fermée quand le compte change).
    let openPlanningSettings: (SchoolCommandScope, SchoolPlanningClient) -> Void
    @Environment(AppLock.self) private var appLock: AppLock?

    /// Les rangées du compte portent déjà leur espacement vertical : sans cela, la liste le double.
    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m) }

    /// La feuille des préférences, pour un compte de l’administration ou un moniteur seulement.
    private var planning: (scope: SchoolCommandScope, client: SchoolPlanningClient)? {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership,
              membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") else { return nil }
        return (agendaClient.scope(person: person, membership: membership), agendaClient.planningClient)
    }

    /// Seulement quand l’école a dit que ce compte peut les gérer (administration, ou moniteur portant le droit) ;
    /// un moniteur sans ce droit utilise simplement « Signaler ».
    private var observationThemes: SchoolObservationThemeStore? {
        guard let themes = agendaClient?.observationThemeStore(person: workspace.person, membership: workspace.membership),
              themes.canManage else { return nil }
        return themes
    }

    var body: some View {
        List {
            let planning = self.planning
            let themes = self.observationThemes
            if planning != nil || themes != nil {
                // Chaque ligne se lit par son titre : un en-tête de section le redirait.
                Section {
                    if let planning {
                        // Une feuille s’ouvre : même ligne et même chevron que les autres destinations.
                        DrivyNavigationRow(title: "Préférences de leçon") {
                            openPlanningSettings(planning.scope, planning.client)
                        }
                        .listRowInsets(rowInsets)
                        .accessibilityIdentifier("profile-planning-settings")
                    }
                    if let themes {
                        NavigationLink {
                            SchoolObservationThemeSettingsView(store: themes)
                        } label: {
                            Text("Signalements")
                                .foregroundStyle(DrivyTheme.text)
                        }
                        .accessibilityIdentifier("profile-observation-themes")
                    }
                }
                .drivyFormRows()
            }
            DrivyAppearanceSection()
            if let account {
                if appLock?.biometryName != nil {
                    Section {
                        account.lockRow()
                            .listRowInsets(rowInsets)
                    } header: {
                        Text("Sécurité").drivyFormSectionHeader()
                    }
                    .drivyFormRows()
                }
                Section {
                    account.signOutRow()
                        .listRowInsets(rowInsets)
                }
                .drivyFormRows()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("staff-settings-list")
    }
}
