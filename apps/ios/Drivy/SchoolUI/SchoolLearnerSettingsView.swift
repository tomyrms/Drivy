import SwiftUI

/// Profil → Paramètres (élève) : le compte, l’enregistrement GPS, le verrou de l’app et la déconnexion. Les lignes
/// sont celles de `SchoolAccountActions`, partagées avec la feuille « Compte » et le Profil du moniteur : un seul
/// jeu de réglages, rangé ici par sujet.
struct SchoolLearnerSettingsView: View {
    /// L’accord GPS général de l’élève et ses trajets, dans une école qui en enregistre.
    struct Recording {
        let agenda: SchoolAgendaClient
        /// `nil` avec `learnerID` tant que l’école n’a pas ouvert le dossier : seuls les trajets se lisent.
        let scope: SchoolCommandScope?
        let learnerID: UUID?
        /// Le choix déjà lu par le Profil ; la ligne ne le relit pas.
        let consent: SchoolRecordingChoiceWorkspace?
    }

    let workspace: SchoolWorkspace
    let account: SchoolAccountActions
    let recording: Recording?
    @Environment(\.openURL) private var openURL
    @Environment(AppLock.self) private var appLock: AppLock?

    /// Les rangées du compte portent déjà leur espacement vertical : sans cela, la liste le double.
    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m) }

    var body: some View {
        List {
            Section {
                account.accountRows(workspace: workspace, openURL: openURL)
                    .listRowInsets(rowInsets)
            } header: {
                Text("Compte").drivyFormSectionHeader()
            }
            .drivyFormRows()
            if let recording {
                Section {
                    if let scope = recording.scope, let learnerID = recording.learnerID {
                        SchoolOwnRecordingChoice(scope: scope, lessonID: nil, learnerID: learnerID, agenda: recording.agenda,
                            shared: recording.consent)
                    }
                    NavigationLink(value: SchoolLearnerProfileRoute.trips) {
                        Text("Trajets")
                            .foregroundStyle(DrivyTheme.text)
                    }
                    .accessibilityIdentifier("profile-open-trips")
                } header: {
                    Text("Enregistrement GPS").drivyFormSectionHeader()
                }
                .drivyFormRows()
            }
            DrivyAppearanceSection()
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("learner-settings-list")
    }
}
