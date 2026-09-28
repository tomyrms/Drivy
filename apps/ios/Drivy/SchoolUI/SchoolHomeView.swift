import SwiftUI

enum SchoolHomeTab: Hashable { case session, agenda, learners, trips, lessons, progress }

/// Onglets par rôle : le moniteur conduit (Aujourd’hui, Agenda, Élèves, Trajets), l’élève suit (Leçons, Progression).
/// La gestion de l’école vit sur le web ; le compte reste derrière l’avatar.
struct SchoolHomeView: View {
    @Bindable var workspace: SchoolWorkspace
    let openAccount: () -> Void
    var inviteLearner: (() -> Void)? = nil
    var openProfile: ((SchoolLearner) -> Void)? = nil
    var agendaClient: SchoolAgendaClient? = nil
    var trainingClient: SchoolTrainingClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
    /// Rejoindre une école avec un code, quand le compte n’en a encore aucune.
    var joinSchool: (() -> Void)? = nil
    @Binding var selectedTab: SchoolHomeTab
    @State private var choosesSchool = false
    @State private var dossierPlanningModel: SchoolPlanningWorkspace?
    @State private var chosenTrainingID: UUID?

    var body: some View {
        Group {
            if workspace.membership == nil {
                NavigationStack {
                    schoolSelection.navigationTitle("Drivy").toolbar { DrivyAccountToolbarItem(openAccount: openAccount) }
                }
            } else if workspace.isLearnerOnly {
                learnerTabs
            } else {
                staffTabs
            }
        }
        .tint(DrivyTheme.accent)
        .sheet(isPresented: $choosesSchool) {
            SchoolChooserSheet(workspace: workspace, close: { choosesSchool = false })
        }
        .sheet(item: $dossierPlanningModel) { model in SchoolPlanningView(model: model) }
        .onChange(of: workspace.membership?.membershipId) { _, _ in resetScope() }
        .onChange(of: workspace.membership?.accessEpoch) { _, _ in resetScope() }
        .onChange(of: captureController?.isCollecting) { wasCollecting, isCollecting in
            if wasCollecting != true && isCollecting == true { selectedTab = .session }
        }
    }

    private func resetScope() {
        dossierPlanningModel?.invalidate(); dossierPlanningModel = nil; chosenTrainingID = nil
    }

    // MARK: Moniteur

    private var staffSelection: Binding<SchoolHomeTab> {
        Binding(get: { [.session, .agenda, .learners, .trips].contains(selectedTab) ? selectedTab : .session }, set: { selectedTab = $0 })
    }

    private var staffTabs: some View {
        TabView(selection: staffSelection) {
            sessionTab
                .tabItem { Label("Aujourd’hui", systemImage: "map") }
                .tag(SchoolHomeTab.session)
            if let agendaClient {
                NavigationStack {
                    SchoolAgendaView(client: agendaClient, workspace: workspace, captureController: captureController)
                        .toolbar { contextToolbar }
                }
                .tabItem { Label("Agenda", systemImage: "calendar") }
                .tag(SchoolHomeTab.agenda)
            }
            SchoolBrowserView(workspace: workspace, openAccount: openAccount, chooseSchool: chooseSchoolAction,
                inviteLearner: inviteLearner, openProfile: openProfile, openPlanning: planningAction, trainingClient: trainingClient)
                .tabItem { Label("Élèves", systemImage: "person.2") }
                .tag(SchoolHomeTab.learners)
            if let agendaClient {
                NavigationStack {
                    SchoolTripsView(workspace: workspace, agendaClient: agendaClient, captureController: captureController)
                        .toolbar { contextToolbar }
                }
                .tabItem { Label("Trajets", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(SchoolHomeTab.trips)
            }
        }
    }

    private var sessionTab: some View {
        NavigationStack {
            Group {
                if let captureController, captureController.captureID != nil {
                    SchoolCaptureLiveView(controller: captureController, learnerName: captureLearnerName,
                        returnToLesson: { selectedTab = .agenda })
                } else {
                    SchoolTodayView(workspace: workspace, agendaClient: agendaClient, captureController: captureController)
                        .navigationTitle("Aujourd’hui")
                        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: Élève

    private var learnerSelection: Binding<SchoolHomeTab> {
        Binding(get: { selectedTab == .progress ? .progress : .lessons }, set: { selectedTab = $0 })
    }

    private var ownLearner: SchoolLearner? {
        workspace.learners.first { $0.personId == workspace.person?.personId }
    }

    /// La formation en cours d’abord ; un menu permet d’en choisir une autre.
    private var learnerTraining: SchoolTraining? {
        guard workspace.learner?.id == ownLearner?.id else { return nil }
        return workspace.trainings.first { $0.id == chosenTrainingID }
            ?? workspace.trainings.first { $0.status == "ACTIVE" } ?? workspace.trainings.first
    }

    private var learnerTabs: some View {
        TabView(selection: learnerSelection) {
            learnerTab(.lessons, title: "Leçons")
                .tabItem { Label("Leçons", systemImage: "calendar") }
                .tag(SchoolHomeTab.lessons)
            learnerTab(.progress, title: "Progression")
                .tabItem { Label("Progression", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(SchoolHomeTab.progress)
        }
        .task(id: ownLearner?.id) {
            guard let id = ownLearner?.id else { return }
            if workspace.selectedLearnerID != id { workspace.selectLearner(id) }
            if workspace.learner?.id != id { await workspace.loadSelectedLearner() }
        }
    }

    private func learnerTab(_ section: SchoolTrainingSection, title: String) -> some View {
        NavigationStack {
            Group {
                if let learner = ownLearner, let training = learnerTraining, let trainingClient {
                    SchoolTrainingScreen(client: trainingClient, workspace: workspace, learner: learner,
                        trainingID: training.id, section: section)
                } else {
                    learnerStatus
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if workspace.trainings.count > 1, let current = learnerTraining {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Formation", selection: Binding(get: { current.id }, set: { chosenTrainingID = $0 })) {
                                ForEach(workspace.trainings) { training in Text("Permis \(training.categoryCode)").tag(training.id) }
                            }
                        } label: { Label("Permis \(current.categoryCode)", systemImage: "steeringwheel") }
                    }
                }
                contextToolbar
            }
        }
    }

    @ViewBuilder private var learnerStatus: some View {
        if let error = workspace.schoolError ?? workspace.learnersError ?? workspace.learnerError ?? workspace.trainingsError {
            SchoolErrorNotice(message: error, retry: { retryLearner() }).drivyPageContent()
                .frame(maxHeight: .infinity, alignment: .top).background(DrivyTheme.surface)
        } else if workspace.isLoadingSchool || workspace.isSearching || workspace.isLoadingLearner || workspace.isLoadingTrainings
                    || (ownLearner != nil && workspace.learner == nil) {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(DrivyTheme.surface)
        } else if workspace.school?.status != "ACTIVE" {
            ContentUnavailableView("L’école se prépare", systemImage: "building.2")
        } else if ownLearner == nil {
            ContentUnavailableView("Dossier pas encore ouvert", systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Votre école l’ouvrira bientôt."))
        } else {
            ContentUnavailableView("Aucune formation", systemImage: "steeringwheel")
        }
    }

    private func retryLearner() {
        guard let membership = workspace.membership else { return }
        Task {
            if workspace.schoolError != nil || workspace.learnersError != nil { await workspace.selectSchool(membership) }
            else { await workspace.loadSelectedLearner() }
        }
    }

    // MARK: Commun

    @ViewBuilder private var schoolSelection: some View {
        if workspace.person?.memberships.isEmpty == true {
            SchoolWithoutSchoolView(joinSchool: joinSchool)
        } else {
            SchoolChooserView(workspace: workspace)
        }
    }

    /// Le bouton d’école n’apparaît que si le compte en a plusieurs.
    private var chooseSchoolAction: (() -> Void)? {
        (workspace.person?.memberships.count ?? 0) > 1 ? { choosesSchool = true } : nil
    }

    @ToolbarContentBuilder private var contextToolbar: some ToolbarContent {
        if let chooseSchoolAction {
            DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName, chooseSchool: chooseSchoolAction)
        }
        DrivyAccountToolbarItem(openAccount: openAccount)
    }
}
