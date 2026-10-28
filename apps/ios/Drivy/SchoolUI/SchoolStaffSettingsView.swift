import SwiftUI

/// Profil → Paramètres (moniteur, administration) : « Mon profil », notifications, préférences de leçon, signalements
/// et leur classement, apparence, verrou de l’app et déconnexion. Mêmes lignes et même rangement que les Paramètres de
/// l’élève (`SchoolLearnerSettingsView`) : rien n’est copié, chaque ligne vient de son écran ou de `SchoolAccountActions`.
/// Invitations et école restent sur le Profil.
///
/// Une seule règle d’ouverture (#136) : un formulaire qui s’enregistre par un bouton, avec sa saisie protégée à la
/// fermeture (Mon profil, Préférences de leçon), s’ouvre en feuille ; une page dont chaque choix s’applique aussitôt
/// (Notifications, Signalements) est poussée dans la pile, avec le retour.
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

    /// Pour tout moniteur ou compte de l’administration : chacun y règle son propre classement. L’ordre et
    /// l’affichage de l’école ne s’y modifient que si elle a dit que ce compte peut les gérer.
    private var observationThemes: SchoolObservationThemeStore? {
        agendaClient?.observationThemeStore(person: workspace.person, membership: workspace.membership)
    }

    private var observationRanking: SchoolObservationRankingStore? {
        agendaClient?.observationRankingStore(person: workspace.person, membership: workspace.membership)
    }

    var body: some View {
        List {
            if let account, let openProfile = account.openProfile, workspace.person != nil {
                // « Mon profil » en tête des Paramètres, comme chez l’élève ; le crayon de l’en-tête du Profil y mène aussi.
                Section {
                    DrivyNavigationRow(title: "Mon profil", detail: workspace.person?.displayName, action: openProfile)
                        .listRowInsets(rowInsets)
                        .accessibilityIdentifier("open-my-profile")
                } header: {
                    Text("Compte").drivyFormSectionHeader()
                }
                .drivyFormRows()
            }
            if SchoolNotificationSettingsDestination.isAvailable(workspace) {
                Section {
                    NavigationLink {
                        SchoolNotificationSettingsDestination(workspace: workspace)
                    } label: {
                        Text("Notifications")
                            .foregroundStyle(DrivyTheme.text)
                    }
                    .accessibilityIdentifier("settings-notifications")
                }
                .drivyFormRows()
            }
            let planning = self.planning
            let themes = self.observationThemes
            if planning != nil || themes != nil {
                // Chaque ligne se lit par son titre : un en-tête de section le redirait.
                Section {
                    if let planning {
                        // Un formulaire à enregistrer : il s’ouvre en feuille, avec « Fermer » protégé.
                        DrivyNavigationRow(title: "Préférences de leçon") {
                            openPlanningSettings(planning.scope, planning.client)
                        }
                        .listRowInsets(rowInsets)
                        .accessibilityIdentifier("profile-planning-settings")
                    }
                    if let themes {
                        NavigationLink {
                            SchoolObservationThemeSettingsView(store: themes, ranking: observationRanking)
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
            Section {
                NavigationLink {
                    SchoolHelpView(workspace: workspace)
                } label: {
                    Text("Aide").foregroundStyle(DrivyTheme.text)
                }
                .accessibilityIdentifier("settings-help")
            }
            .drivyFormRows()
            SchoolMapAttributionSection()
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
