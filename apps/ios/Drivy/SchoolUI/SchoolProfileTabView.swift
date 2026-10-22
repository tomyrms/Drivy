import SwiftUI

/// Le compte du moniteur ou de l’administration : qui il est, ses leçons et son compte (informations, invitations,
/// école). Les réglages (préférences, signalements, apparence, verrou, déconnexion) sont dans Paramètres, poussés
/// dans la même pile par l’engrenage. Le serveur décide de ce que ce compte lit dans l’historique des leçons.
struct SchoolProfileTabView: View {
    @Bindable var workspace: SchoolWorkspace
    let account: SchoolAccountActions?
    var agendaClient: SchoolAgendaClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
    var chooseSchool: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var planningSettings: PlanningSettingsPresentation?
    @State private var showsSettings = false

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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Paramètres")
                            .accessibilityIdentifier("profile-settings")
                    }
                }
                .navigationDestination(isPresented: $showsSettings) {
                    SchoolStaffSettingsView(workspace: workspace, account: account, agendaClient: agendaClient) { scope, client in
                        planningSettings = PlanningSettingsPresentation(scope: scope, client: client)
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
        .onChange(of: scopeKey) { _, _ in planningSettings = nil; showsSettings = false }
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

    /// L’en-tête posé sur le fond, comme le Profil de l’élève ; puis les leçons et le compte. Les réglages sont
    /// dans Paramètres, rangés dans le même ordre que ceux de l’élève.
    @ViewBuilder private var accountSections: some View {
        Section {
            SchoolAccountHeading(workspace: workspace, isAuthenticated: true, edit: account?.openProfile)
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
            }
            .drivyFormRows()
        }
        if let account, account.hasSchoolRows(workspace: workspace) {
            // « Mon profil » vit dans Paramètres ; le crayon de l’en-tête y mène aussi.
            Section {
                account.accountRows(workspace: workspace, openURL: openURL, includesProfile: false)
                    .listRowInsets(rowInsets)
            } header: {
                Text("Compte").drivyFormSectionHeader()
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
