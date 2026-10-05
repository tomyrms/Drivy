import SwiftUI

/// Le compte et ses réglages. L’historique des trajets a sa propre destination,
/// sans déplacer les filtres ni élargir les données autorisées par le serveur.
struct SchoolProfileTabView: View {
    @Bindable var workspace: SchoolWorkspace
    let account: SchoolAccountActions?
    var agendaClient: SchoolAgendaClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
    var chooseSchool: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    /// Identité, accès aux leçons, puis actions du compte.
    @ViewBuilder private var accountSections: some View {
        Section {
            SchoolAccountHeading(workspace: workspace, isAuthenticated: true)
        }
        .listRowInsets(EdgeInsets(top: DrivySpacing.s, leading: DrivySpacing.m, bottom: DrivySpacing.s, trailing: DrivySpacing.m))
        .listRowBackground(Color.clear)
        if let agendaClient {
            Section {
                NavigationLink {
                    SchoolTripsView(workspace: workspace, agendaClient: agendaClient, captureController: captureController, showsHeading: false) { EmptyView() }
                        .navigationTitle("Trajets")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text("Trajets")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile-open-trips")
                if let person = workspace.person, let membership = workspace.membership,
                   membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") {
                    Button {
                        planningSettings = PlanningSettingsPresentation(scope: agendaClient.scope(person: person, membership: membership),
                            client: agendaClient.planningClient)
                    } label: {
                        Text("Préférences de leçon")
                            .foregroundStyle(DrivyTheme.text)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("profile-planning-settings")
                }
            } header: { Text("Leçons").drivyFormSectionHeader() }
            .drivyFormRows()
        }
        if let account {
            Section {
                account.rows(workspace: workspace, openURL: openURL)
                    // Les rangées portent déjà leur espacement vertical : sans cela, la liste le double.
                    .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
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
