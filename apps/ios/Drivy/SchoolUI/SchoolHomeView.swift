import SwiftUI

/// The map is an entry point, including while a school is being prepared.
/// School data always remains the projection authorized by SchoolWorkspace.
struct SchoolHomeView: View {
    @Bindable var workspace: SchoolWorkspace
    let localController: SessionController
    let openAccount: () -> Void
    let signOut: () -> Void
    var configureSchool: (() -> Void)? = nil
    var openInvitations: (() -> Void)? = nil
    var openProfile: ((SchoolLearner) -> Void)? = nil
    var openProfilePolicy: (() -> Void)? = nil
    var openOnboarding: (() -> Void)? = nil
    var openCatalog: (() -> Void)? = nil
    var openTrainingAdministration: ((SchoolLearner) -> Void)? = nil
    var agendaClient: SchoolAgendaClient? = nil
    @State private var selectedTab: HomeTab = .session
    @State private var choosesSchool = false
    @State private var dossierPlanningModel: SchoolPlanningWorkspace?

    private enum HomeTab: Hashable { case session, agenda, learners, school }

    var body: some View {
        TabView(selection: $selectedTab) {
            sessionTab
                .tabItem { Label("Séance", systemImage: "map") }
                .tag(HomeTab.session)
            if let agendaClient {
                NavigationStack {
                    SchoolAgendaView(client: agendaClient, workspace: workspace)
                        .toolbar { contextToolbar }
                }
                    .tabItem { Label("Agenda", systemImage: "calendar") }
                    .tag(HomeTab.agenda)
            }
            learnersTab
                .tabItem { Label(workspace.isLearnerOnly ? "Mon dossier" : "Élèves", systemImage: "person.2") }
                .tag(HomeTab.learners)
            schoolTab
                .tabItem { Label("École", systemImage: "building.2") }
                .tag(HomeTab.school)
        }
        .tint(DrivyTheme.accent)
        .sheet(isPresented: $choosesSchool) { schoolChooser }
        .sheet(item: $dossierPlanningModel) { model in SchoolPlanningView(model: model) }
        .onChange(of: workspace.membership?.membershipId) { _, _ in
            dossierPlanningModel?.invalidate(); dossierPlanningModel = nil
        }
        .onChange(of: workspace.membership?.accessEpoch) { _, _ in
            dossierPlanningModel?.invalidate(); dossierPlanningModel = nil
        }
        .task { await localController.load() }
    }

    private var sessionTab: some View {
        NavigationStack {
            DrivingMapHomeView(controller: localController, schoolName: workspace.school?.name,
                openLearners: { selectedTab = .learners }, agendaClient: agendaClient,
                workspace: workspace, openAgenda: { selectedTab = .agenda })
                .navigationTitle("Séance")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { contextToolbar }
        }
    }

    @ViewBuilder private var learnersTab: some View {
        if workspace.membership != nil {
            SchoolBrowserView(workspace: workspace, openAccount: openAccount,
                openInvitations: openInvitations, openProfile: openProfile,
                openSchool: { selectedTab = .school }, openTrainingAdministration: openTrainingAdministration,
                openPlanning: planningAction)
        } else {
            NavigationStack {
                schoolSelection
                    .navigationTitle("Élèves")
                    .toolbar { contextToolbar }
            }
        }
    }

    private var schoolTab: some View {
        NavigationStack {
            Group {
                if workspace.membership != nil { schoolDetails }
                else { schoolSelection }
            }
            .navigationTitle("École")
            .toolbar { contextToolbar }
        }
    }
    private var planningAction: ((SchoolLearner) -> Void)? {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership,
              workspace.school?.status == "ACTIVE", membership.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) else { return nil }
        return { learner in
            let model = SchoolPlanningWorkspace(scope: agendaClient.scope(person: person, membership: membership),
                client: agendaClient.planningClient, date: Date().addingTimeInterval(3600))
            model.learnerID = learner.id
            dossierPlanningModel = model
        }
    }

    private var schoolDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                schoolHeading
                if workspace.isLoadingSchool {
                    ProgressView("Ouverture de l’école…")
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                if let error = workspace.schoolError {
                    SchoolErrorNotice(message: error, retry: { refreshSchool() })
                }
                if let school = workspace.school {
                    if school.status != "ACTIVE" { schoolStatus(school.status) }
                    schoolActions
                    contactSection(school)
                }
                accountSection
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
    }

    private var schoolHeading: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "building.2")
                .font(.title2.weight(.medium))
                .foregroundStyle(DrivyTheme.accent)
                .frame(width: 60, height: 60)
                .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(workspace.school?.name ?? workspace.membership?.schoolName ?? "Mon école")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if let membership = workspace.membership {
                Label(SchoolPresentation.roles(membership.roles), systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DrivyTheme.muted)
            }
        }
    }

    private func schoolStatus(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(status == "ARCHIVED" ? "École archivée" : "Votre école se prépare", systemImage: "info.circle")
                .font(.headline)
            Text(status == "ARCHIVED"
                ? "Les nouvelles opérations scolaires sont fermées. Vos séances sur cet appareil restent accessibles."
                : "La carte est disponible. L’administration peut terminer la configuration depuis cet espace.")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 20))
    }

    private var schoolActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dans votre école").font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                actionRow(workspace.isLearnerOnly ? "Mon dossier scolaire" : "Dossiers élèves",
                    detail: workspace.isLearnerOnly ? "Profil et formations" : "Retrouver les élèves autorisés",
                    symbol: "person.2", action: { selectedTab = .learners })
                if let openCatalog {
                    Divider().padding(.leading, 64)
                    actionRow("Formations", detail: "Offres, référentiels et procédures", symbol: "steeringwheel", action: openCatalog)
                }
                if let openInvitations {
                    Divider().padding(.leading, 64)
                    actionRow("Invitations", detail: "Inviter et suivre les accès", symbol: "envelope", action: openInvitations)
                }
                if let configureSchool {
                    Divider().padding(.leading, 64)
                    actionRow("Configuration de l’école", detail: "Coordonnées, données et activation", symbol: "slider.horizontal.3", action: configureSchool)
                }
                if let openProfilePolicy {
                    Divider().padding(.leading, 64)
                    actionRow("Champs du profil", detail: "Informations demandées aux élèves", symbol: "list.bullet.rectangle", action: openProfilePolicy)
                }
            }
            .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func contactSection(_ school: SchoolDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contacter l’école").font(.title3.weight(.semibold))
            DrivyPanel {
                VStack(alignment: .leading, spacing: 18) {
                    contactValue(school.contactEmail, title: "E-mail", symbol: "envelope")
                    if let phone = school.contactPhone, !phone.isEmpty {
                        Divider()
                        contactValue(phone, title: "Téléphone", symbol: "phone")
                    }
                }
            }
        }
    }

    private func contactValue(_ value: String, title: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(DrivyTheme.muted).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(DrivyTheme.muted)
                Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Votre compte").font(.title3.weight(.semibold))
            DrivyPanel {
                VStack(alignment: .leading, spacing: 18) {
                    Text(workspace.person?.displayName ?? "Compte connecté").font(.headline)
                    Text(roleExplanation).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let openOnboarding {
                        Button("Mon arrivée dans l’école", action: openOnboarding).frame(minHeight: 44)
                    }
                    Button { choosesSchool = true } label: { Label("Changer d’école", systemImage: "building.2") }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("school-change-school")
                    Divider()
                    Button("Se déconnecter", role: .destructive, action: signOut)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("school-sign-out")
                }
            }
        }
    }

    private var roleExplanation: String {
        let roles = workspace.membership?.roles ?? []
        if roles.contains("ADMIN") { return "Votre accès Administration permet de gérer cette école et les dossiers qui vous sont autorisés." }
        if roles.contains("INSTRUCTOR") { return "Votre accès Moniteur donne accès aux élèves qui vous sont affectés par cette école." }
        return "Votre accès Élève donne accès à votre dossier personnel dans cette école."
    }

    private func actionRow(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title3).foregroundStyle(DrivyTheme.muted).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
                    Text(detail).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var schoolSelection: some View {
        if workspace.person?.memberships.isEmpty == true {
            ContentUnavailableView("Votre école vous attend", systemImage: "building.2",
                description: Text("Demandez à votre école de vous donner accès à votre dossier. La carte reste accessible dans Séance."))
                .background(DrivyTheme.canvas)
        } else {
            SchoolChooserView(workspace: workspace)
        }
    }

    private var schoolChooser: some View {
        NavigationStack {
            SchoolChooserView(workspace: workspace, onSelect: { choosesSchool = false })
                .navigationTitle("Mes écoles")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { choosesSchool = false } } }
        }
    }

    @ToolbarContentBuilder private var contextToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { choosesSchool = true } label: { Label("Écoles", systemImage: "building.2") }
                .accessibilityIdentifier("choose-school")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: openAccount) { Label("Compte", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("school-account")
        }
    }

    private func refreshSchool() {
        guard let membership = workspace.membership else { return }
        Task { await workspace.selectSchool(membership) }
    }
}
