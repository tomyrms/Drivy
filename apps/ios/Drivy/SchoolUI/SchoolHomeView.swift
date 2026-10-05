import SwiftUI

enum SchoolHomeTab: Hashable { case session, agenda, learners, profile, lessons, progress }

/// Onglets par rôle : le moniteur et l’administration conduisent (Aujourd’hui, Agenda, Élèves) et trouvent
/// leur compte et leurs trajets dans Profil ; l’élève suit (Leçons, Progression), son compte derrière l’avatar.
/// La gestion de l’école vit sur le web.
struct SchoolHomeView: View {
    @Bindable var workspace: SchoolWorkspace
    let openAccount: () -> Void
    /// Les actions du compte, affichées dans l’onglet Profil du moniteur et de l’administration.
    var account: SchoolAccountActions? = nil
    var inviteLearner: (() -> Void)? = nil
    var openProfile: ((SchoolLearner) -> Void)? = nil
    var makeLearnerProfile: ((SchoolLearner) -> SchoolProfileWorkspace?)? = nil
    var agendaClient: SchoolAgendaClient? = nil
    var trainingClient: SchoolTrainingClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
    /// Rejoindre une école avec un code, quand le compte n’en a encore aucune.
    var joinSchool: (() -> Void)? = nil
    @Binding var selectedTab: SchoolHomeTab
    @State private var choosesSchool = false
    @State private var dossierPlanningModel: SchoolPlanningWorkspace?
    @State private var chosenTrainingID: UUID?
    @State private var captureLesson: CaptureLessonRoute?

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
        // La leçon planifiée depuis le dossier apparaît dans sa liste : le dossier se relit à la fermeture.
        .sheet(item: $dossierPlanningModel, onDismiss: { NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil) }) { model in
            SchoolPlanningView(model: model)
        }
        .sheet(item: $captureLesson) { route in
            if let agendaClient {
                NavigationStack {
                    SchoolLessonReportView(client: agendaClient.reportClient, schoolWorkspace: workspace,
                        lessonID: route.id, learnerName: route.learnerName, opensCompletion: route.completing,
                        completionConfirmed: route.completing)
                }
                .tint(DrivyTheme.accent)
                .environment(captureController)
            }
        }
        .onChange(of: workspace.membership?.membershipId) { _, _ in resetScope() }
        .onChange(of: workspace.membership?.accessEpoch) { _, _ in resetScope() }
        // Seul le départ d’un trajet ramène sur « Aujourd’hui ». L’identifiant du trajet reste le même pendant
        // la pause et la reprise ; l’état « en collecte », lui, repasse à vrai à chaque reprise.
        .onChange(of: captureController?.captureID) { previous, current in
            if current != nil && current != previous { selectedTab = .session }
        }
        .onChange(of: selectedTab) { previous, _ in
            // A trip the school has confirmed (complete or partial) is over: leaving the live
            // view closes it, so « Aujourd’hui » shows the day again instead of the ended trip.
            if previous == .session, let captureController, captureController.state == .saved,
               let result = captureController.finalizedSyncState, result == .synced || result == .partial {
                captureController.closeSaved()
            }
        }
    }

    private func resetScope() {
        dossierPlanningModel?.invalidate(); dossierPlanningModel = nil; chosenTrainingID = nil; captureLesson = nil
    }

    // MARK: Moniteur

    private var staffSelection: Binding<SchoolHomeTab> {
        Binding(get: { [.session, .agenda, .learners, .profile].contains(selectedTab) ? selectedTab : .session }, set: { selectedTab = $0 })
    }

    private var staffTabs: some View {
        TabView(selection: staffSelection) {
            sessionTab
                .tabItem {
                    Label("Aujourd’hui", systemImage: captureController?.captureID != nil ? "location.fill" : "map")
                        .accessibilityValue(captureController?.captureID != nil ? "Leçon en cours" : "")
                }
                .tag(SchoolHomeTab.session)
            if let agendaClient {
                NavigationStack {
                    SchoolAgendaView(client: agendaClient, workspace: workspace, captureController: captureController)
                        .toolbar { staffToolbar }
                }
                .tabItem { Label("Agenda", systemImage: "calendar") }
                .tag(SchoolHomeTab.agenda)
            }
            SchoolBrowserView(workspace: workspace, openAccount: nil, chooseSchool: chooseSchoolAction,
                inviteLearner: inviteLearner, openProfile: openProfile, makeLearnerProfile: makeLearnerProfile,
                openPlanning: planningAction, trainingClient: trainingClient,
                agendaClient: agendaClient, captureController: captureController)
                .tabItem { Label("Élèves", systemImage: "person.2") }
                .tag(SchoolHomeTab.learners)
            SchoolProfileTabView(workspace: workspace, account: account, agendaClient: agendaClient,
                captureController: captureController, chooseSchool: chooseSchoolAction)
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(SchoolHomeTab.profile)
        }
    }

    private var sessionTab: some View {
        NavigationStack {
            Group {
                if let captureController, captureController.captureID != nil {
                    SchoolCaptureLiveView(controller: captureController, learnerName: captureLearnerName,
                        closeSaved: { captureController.closeSaved() },
                        openLesson: { lessonID, completing in
                            captureLesson = CaptureLessonRoute(id: lessonID, learnerName: captureLearnerName, completing: completing)
                        }, observationClient: agendaClient?.observationClient, isTabRoot: true)
                } else {
                    SchoolTodayView(workspace: workspace, agendaClient: agendaClient, captureController: captureController)
                        .navigationTitle("Aujourd’hui")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .toolbar { staffToolbar }
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
            DrivySkeletonRows(count: 3)
                .drivySkeleton("Chargement de ton dossier…")
                .drivyPageContent()
                .frame(maxHeight: .infinity, alignment: .top).background(DrivyTheme.surface)
        } else if workspace.school?.status != "ACTIVE" {
            ContentUnavailableView("L’école se prépare", systemImage: "building.2")
        } else if ownLearner == nil {
            ContentUnavailableView("Dossier pas encore ouvert", systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Ton école l’ouvrira bientôt."))
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

    /// Moniteur et administration : l’école seulement, le compte vit dans l’onglet Profil.
    @ToolbarContentBuilder private var staffToolbar: some ToolbarContent {
        if let chooseSchoolAction {
            DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName, chooseSchool: chooseSchoolAction)
        }
    }

    @ToolbarContentBuilder private var contextToolbar: some ToolbarContent {
        if let chooseSchoolAction {
            DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName, chooseSchool: chooseSchoolAction)
        }
        DrivyAccountToolbarItem(openAccount: openAccount)
    }
}

private struct CaptureLessonRoute: Identifiable {
    let id: UUID
    let learnerName: String
    let completing: Bool
}
