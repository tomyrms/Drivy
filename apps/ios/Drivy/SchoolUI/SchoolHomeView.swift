import SwiftUI

enum SchoolHomeTab: Hashable { case session, agenda, learners, school }

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
    var openMembers: (() -> Void)? = nil
    var openAddLearner: (() -> Void)? = nil
    var trainingClient: SchoolTrainingClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
    @Binding var selectedTab: SchoolHomeTab
    @State private var choosesSchool = false
    @State private var dossierPlanningModel: SchoolPlanningWorkspace?
    @State private var trainingCreationModel: SchoolTrainingCreationWorkspace?
    @State private var captureHistoryModel: SchoolCaptureHistoryWorkspace?

    var body: some View {
        TabView(selection: $selectedTab) {
            sessionTab
                .tabItem { Label("Séance", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(SchoolHomeTab.session)
            if let agendaClient {
                NavigationStack {
                    SchoolAgendaView(client: agendaClient, workspace: workspace, captureController: captureController)
                        .toolbar { contextToolbar }
                }
                    .tabItem { Label("Agenda", systemImage: "calendar") }
                    .tag(SchoolHomeTab.agenda)
            }
            learnersTab
                .tabItem { Label(workspace.isLearnerOnly ? "Mon dossier" : "Élèves", systemImage: "person.2") }
                .tag(SchoolHomeTab.learners)
            schoolTab
                .tabItem { Label("École", systemImage: "building.2") }
                .tag(SchoolHomeTab.school)
        }
        .tint(DrivyTheme.accent)
        .sheet(isPresented: $choosesSchool) {
            SchoolChooserSheet(workspace: workspace, close: { choosesSchool = false })
        }
        .sheet(item: $dossierPlanningModel) { model in SchoolPlanningView(model: model) }
        .sheet(item: historyPresentation) { model in
            SchoolCaptureHistoryView(model: model, workspace: workspace)
        }
        .sheet(item: $trainingCreationModel, onDismiss: trainingCreationDismissed) { model in
            SchoolTrainingCreationView(model: model)
                .onChange(of: model.accessRevoked) { _, revoked in
                    if revoked {
                        model.invalidate(); trainingCreationModel = nil
                        Task { await workspace.loadAccount() }
                    }
                }
        }
        .onChange(of: workspace.membership?.membershipId) { _, _ in
            dossierPlanningModel?.invalidate(); dossierPlanningModel = nil
            trainingCreationModel?.invalidate(); trainingCreationModel = nil
            captureHistoryModel?.invalidate(); captureHistoryModel = nil
        }
        .onChange(of: workspace.membership?.accessEpoch) { _, _ in
            dossierPlanningModel?.invalidate(); dossierPlanningModel = nil
            trainingCreationModel?.invalidate(); trainingCreationModel = nil
            captureHistoryModel?.invalidate(); captureHistoryModel = nil
        }
        .task { await localController.load() }
        .onChange(of: captureController?.isCollecting) { wasCollecting, isCollecting in
            if wasCollecting != true && isCollecting == true { selectedTab = .session }
        }
    }

    private var historyPresentation: Binding<SchoolCaptureHistoryWorkspace?> {
        Binding(get: { captureHistoryModel }, set: { value in
            if let value { captureHistoryModel = value }
            else { captureHistoryModel?.invalidate(); captureHistoryModel = nil }
        })
    }

    private var sessionTab: some View {
        NavigationStack {
            Group {
                if let captureController, captureController.captureID != nil {
                    SchoolCaptureLiveView(controller: captureController, learnerName: captureLearnerName,
                        returnToLesson: { selectedTab = .agenda })
                } else {
                    DrivingMapHomeView(controller: localController, schoolName: workspace.school?.name,
                        openLearners: { selectedTab = .learners }, agendaClient: agendaClient,
                        workspace: workspace, openAgenda: { selectedTab = .agenda })
                        .navigationTitle("Séance")
                        .navigationBarTitleDisplayMode(.large)
                }
            }
            .toolbar { contextToolbar }
        }
    }

    private var captureLearnerName: String {
        let learnerID = captureController?.learnerID
        if let learner = workspace.learner, learner.id == learnerID { return learner.displayName }
        return workspace.learners.first(where: { $0.id == learnerID })?.displayName ?? "Leçon en cours"
    }

    @ViewBuilder private var learnersTab: some View {
        if workspace.membership != nil {
            SchoolBrowserView(workspace: workspace, openAccount: openAccount,
                openInvitations: openInvitations, openProfile: openProfile,
                openSchool: { selectedTab = .school }, openTrainingAdministration: openTrainingAdministration,
                openPlanning: planningAction, openAddLearner: openAddLearner,
                trainingClient: trainingClient, openCreateTraining: createTrainingAction)
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
            .navigationBarTitleDisplayMode(.large)
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

    private var createTrainingAction: ((SchoolLearner) -> Void)? {
        guard let trainingClient, let person = workspace.person, let membership = workspace.membership,
              workspace.school?.status == "ACTIVE", membership.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) else { return nil }
        return { learner in
            let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
                membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: trainingClient.baseURL.absoluteString)
            trainingCreationModel = SchoolTrainingCreationWorkspace(scope: scope, membership: membership, learner: learner, client: trainingClient)
        }
    }
    private func trainingCreationDismissed() {
        trainingCreationModel?.invalidate(); trainingCreationModel = nil
        Task { await workspace.loadTrainings() }
    }

    private var schoolDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
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
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
    }

    /// The school name is the toolbar title; the viewer's role is the first fact.
    private var schoolHeading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if let membership = workspace.membership {
                HStack(spacing: DrivySpacing.m) {
                    Image(systemName: "checkmark.shield")
                        .font(.title3)
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("Votre rôle").font(.headline).foregroundStyle(DrivyTheme.text)
                        Text(SchoolPresentation.roles(membership.roles))
                            .font(.subheadline)
                            .foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DrivySpacing.s)
                .frame(minHeight: 64)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func schoolStatus(_ status: String) -> some View {
        let archived = status == "ARCHIVED"
        return DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                DrivyStatusBadge(title: archived ? "École archivée" : "En préparation",
                    symbol: archived ? "archivebox" : "hammer", tone: archived ? .neutral : .warning)
                Text(archived
                    ? "Les nouvelles opérations scolaires sont fermées. Vos séances sur cet appareil restent accessibles."
                    : "La carte est disponible. L’administration peut terminer la configuration depuis cet espace.")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !archived, let configureSchool {
                    Button("Préparer mon école", action: configureSchool)
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .padding(.top, DrivySpacing.xs)
                }
            }
        }
    }

    private var schoolActions: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xl) {
            if captureController != nil, agendaClient != nil, workspace.membership?.roles.contains("INSTRUCTOR") == true {
                DrivyRowGroup(title: "Mes trajets") {
                    DrivyNavigationRow(title: "Trajets de l’école", detail: "Retrouver et envoyer les trajets de cet appareil",
                        symbol: "point.topleft.down.to.point.bottomright.curvepath", action: openCaptureHistory)
                }
            }
            if openMembers != nil || openInvitations != nil {
                DrivyRowGroup(title: "Équipe") {
                    if let openMembers {
                        DrivyNavigationRow(title: "Équipe et accès", detail: "Membres, rôles et autorisations", symbol: "person.2.badge.key", action: openMembers)
                    }
                    if let openInvitations {
                        DrivyNavigationRow(title: "Invitations", detail: "Inviter une personne et suivre les liens", symbol: "envelope", action: openInvitations)
                    }
                }
            }
            if openCatalog != nil || configureSchool != nil || openProfilePolicy != nil {
                DrivyRowGroup(title: "Organisation") {
                    if let openCatalog {
                        DrivyNavigationRow(title: "Formations", detail: "Offres, référentiels et procédures", symbol: "steeringwheel", action: openCatalog)
                    }
                    if let configureSchool {
                        DrivyNavigationRow(title: "Configuration", detail: "Coordonnées, textes et activation de l’école", symbol: "slider.horizontal.3", action: configureSchool)
                    }
                    if let openProfilePolicy {
                        DrivyNavigationRow(title: "Champs du profil", detail: "Informations demandées aux élèves", symbol: "list.bullet.rectangle", action: openProfilePolicy)
                    }
                }
            }
        }
    }

    private func openCaptureHistory() {
        guard let captureController, let agendaClient, let person = workspace.person,
              let membership = workspace.membership, membership.roles.contains("INSTRUCTOR") else { return }
        captureHistoryModel = SchoolCaptureHistoryWorkspace(scope: agendaClient.scope(person: person, membership: membership),
            client: agendaClient.captureClient, owner: captureController)
    }

    private func contactSection(_ school: SchoolDetails) -> some View {
        DrivyRowGroup(title: "Contacter l’école") {
            DrivyContactRow(title: "E-mail", value: school.contactEmail, symbol: "envelope")
            if let phone = school.contactPhone, !phone.isEmpty {
                DrivyContactRow(title: "Téléphone", value: phone, symbol: "phone")
            }
        }
    }

    private var accountSection: some View {
        DrivyRowGroup(title: "Votre compte") {
            DrivyEntityRow(title: workspace.person?.displayName ?? "Compte connecté",
                meta: workspace.membership.map { SchoolPresentation.roles($0.roles) },
                leading: .avatar(workspace.person?.displayName ?? "Compte"))
            if let openOnboarding {
                DrivyNavigationRow(title: "Mon arrivée dans l’école", detail: "Profil et étapes d’accueil",
                    symbol: "figure.wave", action: openOnboarding)
            }
            DrivyNavigationRow(title: "Changer d’école", detail: workspace.person.map { $0.memberships.count > 1 ? "\($0.memberships.count) écoles sur ce compte" : "Une école sur ce compte" },
                symbol: "arrow.left.arrow.right", action: { choosesSchool = true })
                .accessibilityIdentifier("school-change-school")
            DrivyDestructiveRow(title: "Se déconnecter", symbol: "rectangle.portrait.and.arrow.right", action: signOut)
                .accessibilityIdentifier("school-sign-out")
        }
    }

    @ViewBuilder private var schoolSelection: some View {
        if workspace.person?.memberships.isEmpty == true {
            ContentUnavailableView("Aucune école associée", systemImage: "building.2",
                description: Text("Demandez à votre école de vous donner accès à votre dossier. La carte reste accessible dans Séance."))
                .background(DrivyTheme.canvas)
        } else {
            SchoolChooserView(workspace: workspace)
        }
    }

    /// Same leading school button and trailing account button on every tab.
    @ToolbarContentBuilder private var contextToolbar: some ToolbarContent {
        DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName,
            chooseSchool: { choosesSchool = true })
        DrivyAccountToolbarItem(openAccount: openAccount)
    }

    private func refreshSchool() {
        guard let membership = workspace.membership else { return }
        Task { await workspace.selectSchool(membership) }
    }
}
