import SwiftUI

/// Le compte et ses réglages. L’historique des leçons a sa propre destination ;
/// le serveur décide de ce que ce compte y lit.
struct SchoolProfileTabView: View {
    @Bindable var workspace: SchoolWorkspace
    let account: SchoolAccountActions?
    var agendaClient: SchoolAgendaClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
    var chooseSchool: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppLock.self) private var appLock: AppLock?
    @State private var planningSettings: PlanningSettingsPresentation?

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.schoolId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? "")"
    }

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
        .id(scopeKey)
        .sheet(item: $planningSettings) { presentation in
            NavigationStack {
                SchoolPlanningSettingsView(scope: presentation.scope, client: presentation.client)
            }
            .tint(DrivyTheme.accent)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationSizing(.form)
        }
        .onChange(of: scopeKey) { _, _ in planningSettings = nil }
    }

    private var content: some View {
        List { accountSections }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DrivyLayout.formColumn)
            .frame(maxWidth: .infinity)
            .background(DrivyTheme.canvas)
            .accessibilityIdentifier("profile-list")
    }

    /// Les rangées portent déjà leur espacement vertical : sans cela, la liste le double.
    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m) }

    /// L’en-tête posé sur le fond, comme le Profil de l’élève ; puis les leçons, et le compte rangé par sujet dans
    /// le même ordre que les Paramètres de l’élève (Compte, Sécurité, déconnexion).
    @ViewBuilder private var accountSections: some View {
        Section {
            SchoolAccountHeading(workspace: workspace, isAuthenticated: true)
        }
        .listRowInsets(EdgeInsets(top: DrivySpacing.s, leading: DrivySpacing.m, bottom: DrivySpacing.s, trailing: DrivySpacing.m))
        .drivyClearRow()
        if let agendaClient {
            Section {
                NavigationLink {
                    SchoolLessonHistoryView(workspace: workspace, agendaClient: agendaClient, captureController: captureController)
                } label: {
                    // La cellule native assure déjà ses 44 pt : une hauteur de plus la rendait plus haute que ses voisines.
                    Text("Leçons")
                        .foregroundStyle(DrivyTheme.text)
                }
                .accessibilityIdentifier("profile-open-lessons")
                if let person = workspace.person, let membership = workspace.membership,
                   membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") {
                    // Une feuille s’ouvre : même ligne et même chevron que les autres destinations du Profil.
                    DrivyNavigationRow(title: "Préférences de leçon") {
                        planningSettings = PlanningSettingsPresentation(scope: agendaClient.scope(person: person, membership: membership),
                            client: agendaClient.planningClient)
                    }
                    .listRowInsets(rowInsets)
                    .accessibilityIdentifier("profile-planning-settings")
                }
                // Seulement quand l’école a dit que ce compte peut les gérer (administration, ou moniteur
                // portant le droit) ; un moniteur sans ce droit utilise simplement « Signaler ».
                if let themes = agendaClient.observationThemeStore(person: workspace.person, membership: workspace.membership),
                   themes.canManage {
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
        if let account {
            Section {
                account.accountRows(workspace: workspace, openURL: openURL)
                    .listRowInsets(rowInsets)
            } header: {
                Text("Compte").drivyFormSectionHeader()
            }
            .drivyFormRows()
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
}

private struct PlanningSettingsPresentation: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolPlanningClient
}
