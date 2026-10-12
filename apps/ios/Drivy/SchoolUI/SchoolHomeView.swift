import SwiftUI

enum SchoolHomeTab: Hashable { case session, agenda, learners, profile, lessons, progress }

/// Onglets par rôle : le moniteur et l’administration conduisent (Aujourd’hui, Agenda, Élèves) et trouvent
/// leur compte et leurs trajets dans Profil ; l’élève suit (Leçons, Progression) et trouve dans Profil son
/// identité, son école, ses permis, puis ses informations et ses paramètres.
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
    /// Le permis que l’élève filtre dans ses onglets Leçons et Progression ; `nil` les montre tous.
    @State private var chosenPermit: UUID?
    @State private var captureLesson: CaptureLessonRoute?
    /// Ce que le compte doit faire dans cette école : les points des onglets et les lignes s’y lisent.
    @State private var requiredActions = SchoolRequiredActionStore()
    /// Élève du trajet en cours, lu à part quand il n’est pas dans la page d’élèves affichée.
    @State private var captureLearner: (id: UUID, name: String)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

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
        .environment(requiredActions)
        .sheet(isPresented: $choosesSchool) {
            SchoolChooserSheet(workspace: workspace, close: { choosesSchool = false })
        }
        // La leçon planifiée depuis le dossier apparaît dans sa liste : le dossier se relit à la fermeture.
        .sheet(item: $dossierPlanningModel, onDismiss: { NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil) }) { model in
            SchoolPlanningView(model: model)
        }
        // Une demande abandonnée ou vérifiée depuis la fiche ne reste pas affichée par l'enregistreur du trajet.
        .sheet(item: $captureLesson, onDismiss: {
            captureController?.liveObservations?.refreshPending()
            // Leçon terminée depuis cette fiche : son trajet arrêté ne reste pas à l’écran avec « Terminer la leçon ».
            // L’envoi du trajet continue de lui-même.
            if let captureController, let lessonID = captureController.lessonID, captureController.state == .saved,
               captureController.completedLessonID == lessonID {
                captureController.closeLessonFlow(lessonID: lessonID)
            }
        }) { route in
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
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { _ in
            SchoolTodayMemory.forget(); SchoolAgendaMemory.forget()
        }
        .onChange(of: workspace.membership?.membershipId) { _, _ in resetScope() }
        .onChange(of: workspace.membership?.accessEpoch) { _, _ in resetScope() }
        // Seul le départ d’un trajet ramène sur « Aujourd’hui ». L’identifiant du trajet reste le même pendant
        // la pause et la reprise ; l’état « en collecte », lui, repasse à vrai à chaque reprise.
        .onChange(of: captureController?.captureID) { previous, current in
            if current != nil && current != previous { selectedTab = .session; SchoolTodayMemory.forget() }
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

    /// Icône d’un onglet : le symbole du système, ou, quand une action y attend, le même symbole mordu par le
    /// point bleu de Drivy, dessiné pour l’état choisi et l’état au repos.
    @ViewBuilder private func tabLabel(_ title: String, systemImage: String, tab: SchoolHomeTab) -> some View {
        if requiredActions.needsAttention(tab) {
            Label {
                Text(title)
            } icon: {
                DrivyTabIcon.image(systemName: systemImage, selected: selectedTab == tab, scheme: colorScheme)
            }
            .accessibilityValue("Action requise")
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    /// Ce que cette vue sait déjà sans rien lire de plus : les profils incomplets de la page d’élèves affichée
    /// (administration seulement) et l’accueil laissé en route.
    private func refreshStaffActions() {
        let roles = workspace.membership?.roles ?? []
        requiredActions.replace(.completeLearnerProfile, with: SchoolRequiredActionRules.incompleteProfiles(workspace.learners, roles: roles))
        requiredActions.replace(.resumeOnboarding, with: SchoolRequiredActionRules.onboarding(canResume: account?.resumeOnboarding != nil, isLearner: false))
    }

    private func resetScope() {
        dossierPlanningModel?.invalidate(); dossierPlanningModel = nil; chosenPermit = nil; captureLesson = nil
        requiredActions.reset()
    }

    // MARK: Moniteur

    private var staffSelection: Binding<SchoolHomeTab> {
        Binding(get: { [.session, .agenda, .learners, .profile].contains(selectedTab) ? selectedTab : .session }, set: { selectedTab = $0 })
    }

    private var staffTabs: some View {
        TabView(selection: staffSelection) {
            sessionTab
                .tabItem {
                    tabLabel("Aujourd’hui", systemImage: captureController?.captureID != nil ? "location.fill" : "map", tab: .session)
                        .accessibilityValue(captureController?.captureID != nil ? "Leçon en cours" : (requiredActions.needsAttention(.session) ? "Action requise" : ""))
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
                .tabItem { tabLabel("Élèves", systemImage: "person.2", tab: .learners) }
                .tag(SchoolHomeTab.learners)
            SchoolProfileTabView(workspace: workspace, account: account, agendaClient: agendaClient,
                captureController: captureController, chooseSchool: chooseSchoolAction)
                .tabItem { tabLabel("Profil", systemImage: "person.crop.circle", tab: .profile) }
                .tag(SchoolHomeTab.profile)
        }
        // Ce que les onglets savent déjà : relu quand la page d’élèves, les droits ou l’accueil changent.
        .onChange(of: workspace.learners.map { "\($0.id):\($0.profileReadiness ?? "")\($0.archivedAt == nil)" }, initial: true) { _, _ in refreshStaffActions() }
        .onChange(of: workspace.membership?.roles) { _, _ in refreshStaffActions() }
        .onChange(of: account?.resumeOnboarding != nil) { _, _ in refreshStaffActions() }
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
            .task(id: captureController?.learnerID) {
                guard let id = captureController?.learnerID, captureLearner?.id != id,
                      let name = await workspace.learnerName(id) else { return }
                captureLearner = (id, name)
            }
        }
    }

    private var captureLearnerName: String {
        let learnerID = captureController?.learnerID
        if let learner = workspace.learner, learner.id == learnerID { return learner.displayName }
        if let listed = workspace.learners.first(where: { $0.id == learnerID }) { return listed.displayName }
        return captureLearner?.id == learnerID ? captureLearner?.name ?? "Leçon en cours" : "Leçon en cours"
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
        Binding(get: { [.lessons, .progress, .profile].contains(selectedTab) ? selectedTab : .lessons }, set: { selectedTab = $0 })
    }

    private var ownLearner: SchoolLearner? {
        workspace.learners.first { $0.personId == workspace.person?.personId }
    }

    /// Toutes les formations de l’élève, celle en cours d’abord ; la page les filtre par permis.
    private var learnerTrainings: [SchoolTraining] {
        guard workspace.learner?.id == ownLearner?.id else { return [] }
        return SchoolPermitName.ordered(workspace.trainings)
    }

    private var learnerTabs: some View {
        TabView(selection: learnerSelection) {
            learnerTab(.lessons, title: "Leçons")
                .tabItem { Label("Leçons", systemImage: "calendar") }
                .tag(SchoolHomeTab.lessons)
            // Ni score ni tendance : des compétences et leur niveau. L’icône dessinée pour Drivy (« volant-anneau ») :
            // la jante du volant se remplit comme un anneau, pleine sur la partie parcourue.
            learnerTab(.progress, title: "Progression")
                .tabItem { Label("Progression", image: "Tab-progress") }
                .tag(SchoolHomeTab.progress)
            SchoolLearnerProfileTab(workspace: workspace, learner: ownLearner, trainings: learnerTrainings, account: account,
                agendaClient: agendaClient, trainingClient: trainingClient, chooseSchool: chooseSchoolAction,
                openTraining: { training, tab in chosenPermit = training; selectedTab = tab },
                retryDossier: { retryLearner() }, makeLearnerProfile: makeLearnerProfile)
                .tabItem { tabLabel("Profil", systemImage: "person.crop.circle", tab: .profile) }
                .tag(SchoolHomeTab.profile)
        }
        .task(id: ownLearner?.id) {
            guard let id = ownLearner?.id else { return }
            if workspace.selectedLearnerID != id { workspace.selectLearner(id) }
            if workspace.learner?.id != id { await workspace.loadSelectedLearner() }
            await workspace.loadRemainingTrainings()
        }
        .onChange(of: scenePhase) { _, phase in
            // Une formation ouverte, mise en pause ou terminée par l’école apparaît au retour dans l’app ; les
            // formations déjà affichées restent à l’écran jusqu’à la réponse.
            guard phase == .active, let id = ownLearner?.id, workspace.learner?.id == id, !workspace.isLoadingTrainings else { return }
            Task { await workspace.loadTrainings(); await workspace.loadRemainingTrainings() }
        }
    }

    private func learnerTab(_ section: SchoolTrainingSection, title: String) -> some View {
        NavigationStack {
            Group {
                let trainings = learnerTrainings
                if let learner = ownLearner, !trainings.isEmpty, let trainingClient {
                    SchoolTrainingScreen(client: trainingClient, workspace: workspace, learner: learner,
                        trainingIDs: trainings.map(\.id), permit: $chosenPermit, section: section, ownLessons: true)
                } else {
                    learnerStatus
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            // Le compte vit dans l’onglet Profil, comme pour le moniteur : seule l’école reste dans la barre.
            .toolbar { staffToolbar }
        }
    }

    /// Un seul fond pour chaque état : erreur, attente et vide se remplacent sans saut de couleur.
    private var learnerStatus: some View {
        learnerStatusContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DrivyTheme.surface)
    }

    @ViewBuilder private var learnerStatusContent: some View {
        if let error = workspace.schoolError ?? workspace.learnersError ?? workspace.learnerError ?? workspace.trainingsError {
            SchoolErrorNotice(message: error, retry: { retryLearner() }).drivyPageContent()
        } else if workspace.isLoadingSchool || workspace.isSearching || workspace.isLoadingLearner || workspace.isLoadingTrainings
                    || (ownLearner != nil && workspace.learner == nil) {
            DrivySkeletonRows(count: 3)
                .drivySkeleton("Chargement de ton dossier…")
                .drivyPageContent()
        } else if workspace.school?.status != "ACTIVE" {
            // Même lecture que chez le moniteur : une école archivée ne « se prépare » pas.
            let archived = workspace.school?.status == "ARCHIVED"
            ContentUnavailableView(archived ? "École archivée" : "L’école se prépare", systemImage: archived ? "archivebox" : "building.2")
                .frame(maxHeight: .infinity)
        } else if ownLearner == nil {
            ContentUnavailableView("Dossier pas encore ouvert", systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Ton école l’ouvrira bientôt."))
                .frame(maxHeight: .infinity)
        } else {
            ContentUnavailableView("Aucune formation", systemImage: "steeringwheel")
                .frame(maxHeight: .infinity)
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

    /// Un trajet GPS tourne (ou attend encore la confirmation de l’école) : changer d’école fermerait sa portée.
    private var tripInProgress: Bool {
        guard let captureController else { return false }
        return captureController.captureID != nil && captureController.state != .saved
    }

    /// Le bouton d’école n’apparaît que si le compte en a plusieurs. Pendant un trajet, il se retire comme la ligne
    /// « Changer d’école » du compte : choisir une autre école arrêterait le trajet sans rien demander.
    private var chooseSchoolAction: (() -> Void)? {
        (workspace.person?.memberships.count ?? 0) > 1 && !tripInProgress ? { choosesSchool = true } : nil
    }

    /// Moniteur et administration : l’école seulement, le compte vit dans l’onglet Profil.
    @ToolbarContentBuilder private var staffToolbar: some ToolbarContent {
        if let chooseSchoolAction {
            DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName, chooseSchool: chooseSchoolAction)
        }
    }

}

private struct CaptureLessonRoute: Identifiable {
    let id: UUID
    let learnerName: String
    let completing: Bool
}
