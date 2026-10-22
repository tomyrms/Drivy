import SwiftUI

enum SchoolHomeTab: Hashable { case session, agenda, learners, profile, lessons, progress }

/// Onglets par rôle : le moniteur conduit (Aujourd’hui, Agenda, Élèves) et trouve
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
    /// L’accord GPS général de l’élève connecté, lu dès ses onglets : le point de Profil ne dépend pas d’une
    /// première visite de la page, qui relit ce même modèle.
    @State private var learnerConsent: SchoolRecordingChoiceWorkspace?
    /// Élève du trajet en cours, lu à part quand il n’est pas dans la page d’élèves affichée.
    @State private var captureLearner: (id: UUID, name: String)?
    /// L’écran du trajet a été quitté par le moniteur : la capture continue, l’app retrouve ses onglets.
    /// « Une capture existe » et « son écran est présenté » restent deux faits distincts.
    @State private var captureMinimized = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch workspace.entryDestination {
            case .chooseSchool:
                NavigationStack {
                    schoolSelection.navigationTitle("Drivy").toolbar { DrivyAccountToolbarItem(openAccount: openAccount) }
                }
            case .learner:
                learnerTabs
            case .instructor:
                staffTabs
            default:
                SchoolEntryView(workspace: workspace, portalURL: account?.manageURL,
                    openAccount: openAccount, chooseSchool: chooseSchoolAction)
            }
        }
        .tint(DrivyTheme.accent)
        .environment(requiredActions)
        .environment(\.schoolLearnerDossier, learnerDossierOpener)
        .sheet(isPresented: $choosesSchool) {
            SchoolChooserSheet(workspace: workspace, close: { choosesSchool = false })
        }
        // La leçon planifiée depuis le dossier apparaît dans sa liste : la planification annonce elle-même son
        // écriture confirmée (`drivyLessonsDidChange`), une fois. Une feuille refermée sans écriture ne relit rien.
        .sheet(item: $dossierPlanningModel) { model in
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
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            SchoolTodayMemory.forget(); SchoolAgendaMemory.forget()
            // Leçon terminée (ou absence) confirmée par l’école, depuis n’importe quel écran : le point d’Aujourd’hui
            // part tout de suite, même si la relecture de la journée échoue ensuite.
            if let change = notification.object as? SchoolLessonChange, change.schoolID == workspace.membership?.schoolId,
               change.kind == .completeLesson || change.kind == .markNoShow {
                requiredActions.resolve(.finishLesson, entityID: change.lessonID)
            }
        }
        .onChange(of: workspace.membership?.membershipId) { _, _ in resetScope() }
        .onChange(of: workspace.membership?.accessEpoch) { _, _ in resetScope() }
        .onChange(of: workspace.school?.status) { _, status in
            if let status, status != "ACTIVE" { resetScope() }
        }
        // Seul le départ d’un trajet ramène sur « Aujourd’hui ». L’identifiant du trajet reste le même pendant
        // la pause et la reprise ; l’état « en collecte », lui, repasse à vrai à chaque reprise.
        .onChange(of: captureController?.captureID) { previous, current in
            if current != previous { captureMinimized = false }
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

    /// Ce que cette vue sait déjà sans rien lire de plus : les profils incomplets de toute l’école (administration
    /// seulement ; la page d’élèves affichée tant que l’école ne les a pas rendus) et l’accueil laissé en route.
    private func refreshStaffActions() {
        let roles = workspace.membership?.roles ?? []
        requiredActions.replace(.completeLearnerProfile, with: SchoolRequiredActionRules.incompleteProfiles(workspace.learners,
            schoolWide: workspace.learnersToComplete, roles: roles))
        requiredActions.replace(.resumeOnboarding, with: SchoolRequiredActionRules.onboarding(canResume: account?.resumeOnboarding != nil, isLearner: false))
    }

    private func resetScope() {
        dossierPlanningModel?.invalidate(); dossierPlanningModel = nil; chosenPermit = nil; captureLesson = nil
        captureMinimized = false
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
        .modifier(CaptureReturnAccessory(isEnabled: showsCaptureReturn, button: { captureReturnButton }))
        // Ce que les onglets savent déjà : relu quand la page d’élèves, les droits ou l’accueil changent.
        .onChange(of: workspace.learners.map { "\($0.id):\($0.profileReadiness ?? "")\($0.archivedAt == nil)" }, initial: true) { _, _ in refreshStaffActions() }
        .onChange(of: workspace.learnersToComplete) { _, _ in refreshStaffActions() }
        .onChange(of: workspace.membership?.roles) { _, _ in refreshStaffActions() }
        // Un dossier complété sur le web ou sur un autre appareil se lit au retour dans l’app.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await workspace.refreshLearnersToComplete() } }
        }
        .onChange(of: account?.resumeOnboarding != nil) { _, _ in refreshStaffActions() }
        // Signalements de l’école : lus à l’ouverture de son espace, et relus quand les droits du compte changent.
        // « Signaler » et le Profil partagent ce qui en revient.
        .task(id: observationThemeScope) {
            guard let themes = agendaClient?.observationThemeStore(person: workspace.person, membership: workspace.membership) else { return }
            await themes.refresh()
            // Classement du moniteur : relu au même moment, pour que la prochaine leçon parte du dernier ordre.
            if let ranking = agendaClient?.observationRankingStore(person: workspace.person, membership: workspace.membership) {
                await ranking.refresh()
            }
        }
    }

    private var observationThemeScope: String {
        guard let membership = workspace.membership else { return "" }
        return "\(membership.membershipId.uuidString):\(membership.accessEpoch):\(membership.roles.joined(separator: ",")):\(membership.grants.joined(separator: ","))"
    }

    /// Le trajet est présenté en plein écran, sans barre d’onglets ; quitté, il laisse place à la journée.
    private var presentsCapture: Bool {
        captureController?.captureID != nil && !captureMinimized
    }

    /// Retour au trajet proposé partout dans l’app tant que la capture existe et que son écran est quitté.
    private var showsCaptureReturn: Bool {
        captureController?.captureID != nil && captureMinimized
    }

    private func minimizeCapture() {
        guard let captureController else { return }
        // Trajet déjà confirmé par l’école : le quitter le ferme, comme le retour habituel.
        if captureController.state == .saved, let result = captureController.finalizedSyncState,
           result == .synced || result == .partial {
            captureController.closeSaved()
            return
        }
        captureMinimized = true
    }

    private func returnToCapture() {
        guard captureController?.captureID != nil else { captureMinimized = false; return }
        selectedTab = .session
        captureMinimized = false
    }

    private var captureReturnButton: some View {
        let paused = captureController?.state == .paused
        let saved = captureController?.state == .saved
        return Button(action: returnToCapture) {
            HStack(spacing: DrivySpacing.s) {
                Image(systemName: saved ? "checkmark.circle.fill" : paused ? "pause.circle.fill" : "location.fill")
                    .foregroundStyle(DrivyTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(saved ? "Trajet arrêté" : paused ? "Trajet en pause" : "Trajet en cours")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DrivyTheme.text)
                    Text(captureLearnerName)
                        .font(.caption)
                        .foregroundStyle(DrivyTheme.muted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DrivySpacing.m)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(saved ? "Revenir au trajet" : "Revenir au trajet en cours")
        .accessibilityValue("\(captureLearnerName)\(saved ? ", arrêté" : paused ? ", en pause" : "")")
        .accessibilityIdentifier("capture-return")
    }

    private var sessionTab: some View {
        NavigationStack {
            Group {
                if let captureController, presentsCapture {
                    SchoolCaptureLiveView(controller: captureController, learnerName: captureLearnerName,
                        closeSaved: { captureController.closeSaved() },
                        openLesson: { lessonID, completing in
                            captureLesson = CaptureLessonRoute(id: lessonID, learnerName: captureLearnerName, completing: completing)
                        }, observationClient: agendaClient?.observationClient, isTabRoot: true,
                        minimize: { minimizeCapture() })
                        // Plein écran : la carte prend la place des onglets, rendus dès que l’écran est quitté.
                        .toolbar(.hidden, for: .tabBar)
                } else {
                    SchoolTodayView(workspace: workspace, agendaClient: agendaClient, captureController: captureController,
                        schoolName: workspace.school?.name ?? workspace.membership?.schoolName, chooseSchool: chooseSchoolAction)
                        .navigationTitle("Aujourd’hui")
                        .navigationBarTitleDisplayMode(.inline)
                        // La carte va jusqu’en haut : aucun fond ni flou de barre ne la coupe en rectangle.
                        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            // Avant iOS 26.1, pas d’accessoire d’onglets masquable : le retour vit dans Aujourd’hui.
                            if showsCaptureReturn, !CaptureReturnSupport.usesTabAccessory {
                                captureReturnButton
                                    .padding(.vertical, DrivySpacing.xs)
                                    .background(DrivyTheme.surfaceRaised, in: Capsule())
                                    .drivyShadow(radius: 12, y: 4)
                                    .padding(.horizontal, DrivySpacing.m).padding(.bottom, DrivySpacing.s)
                            }
                        }
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
                client: agendaClient.planningClient, date: Date().addingTimeInterval(3600), suggestingNextSlotFrom: Date())
            model.learnerID = learner.id
            dossierPlanningModel = model
        }
    }

    // MARK: Élève

    /// Dossier ouvert depuis le nom d’une fiche leçon : le même dossier que l’onglet Élèves, sans commande de
    /// départ ni de planification, en feuille au-dessus de la leçon qui reste en place.
    private var learnerDossierOpener: SchoolLearnerDossierOpener? {
        guard workspace.entryDestination == .instructor, let membership = workspace.membership,
              membership.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) else { return nil }
        return SchoolLearnerDossierOpener(schoolID: membership.schoolId, select: { workspace.selectLearner($0) }) { learnerID in
            AnyView(SchoolLessonDossierSheet(workspace: workspace, learnerID: learnerID, openProfile: openProfile,
                makeLearnerProfile: makeLearnerProfile, trainingClient: trainingClient)
                .environment(requiredActions))
        }
    }

    // MARK: Élève (onglets)

    private var learnerSelection: Binding<SchoolHomeTab> {
        Binding(get: { [.lessons, .progress, .profile].contains(selectedTab) ? selectedTab : .lessons }, set: { selectedTab = $0 })
    }

    private var ownLearner: SchoolLearner? {
        workspace.ownLearner
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
            // Ni score ni tendance : des compétences et leur niveau. L’icône dessinée pour Drivy : une courbe
            // montante, segments à 45°, bouts ronds, pointe ouverte.
            learnerTab(.progress, title: "Progression")
                .tabItem { Label("Progression", image: "Tab-progress") }
                .tag(SchoolHomeTab.progress)
            SchoolLearnerProfileTab(workspace: workspace, learner: ownLearner, trainings: learnerTrainings, account: account,
                agendaClient: agendaClient, trainingClient: trainingClient, chooseSchool: chooseSchoolAction,
                openTraining: { training, tab in chosenPermit = training; selectedTab = tab },
                retryDossier: { retryLearner() }, consent: $learnerConsent)
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
            // Un accord donné depuis un autre appareil ou une leçon se relit au retour dans l’app.
            if phase == .active, let consent = learnerConsent, !consent.isLoading, !consent.isBusy { Task { await consent.load() } }
            // Une formation ouverte, mise en pause ou terminée par l’école apparaît au retour dans l’app ; les
            // formations déjà affichées restent à l’écran jusqu’à la réponse.
            guard phase == .active, let id = ownLearner?.id, workspace.learner?.id == id, !workspace.isLoadingTrainings else { return }
            Task { await workspace.loadTrainings(); await workspace.loadRemainingTrainings() }
        }
        .task(id: learnerConsentKey) { await prepareLearnerConsent() }
        // L’accueil de l’élève laissé en route allume Profil, où « Reprendre l’accueil » le rouvre.
        .onChange(of: account?.resumeOnboarding != nil, initial: true) { _, canResume in
            requiredActions.replace(.resumeOnboarding, with: SchoolRequiredActionRules.onboarding(canResume: canResume, isLearner: true))
        }
        // Ce que la ligne « Accord GPS » du Profil dit, le point de l’onglet le dit : réponse donnée, il part aussitôt.
        // Tant que rien n’a été lu, rien n’est affirmé.
        .onChange(of: "\(learnerConsent?.isLoading ?? true):\(learnerConsentAttention ?? "")", initial: true) { _, _ in
            guard let learnerConsent, !learnerConsent.isLoading else { return }
            requiredActions.replace(.giveRecordingConsent, with: SchoolRequiredActionRules.recordingConsent(attention: learnerConsentAttention))
        }
    }

    /// Trajets et accord GPS n’ont de sens que dans une école qui enregistre des trajets.
    private var learnerRecordsTrips: Bool { workspace.school?.status == "ACTIVE" && workspace.school?.modules.gpsEnabled == true }

    private var learnerConsentAttention: String? { learnerRecordsTrips ? learnerConsent?.learnerAttention : nil }

    private var learnerConsentKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(ownLearner?.id.uuidString ?? ""):\(learnerRecordsTrips)"
    }

    /// Le même modèle que la page Profil réutilise : relu s’il vaut pour ce compte et cet élève, sinon remplacé.
    private func prepareLearnerConsent() async {
        guard learnerRecordsTrips, let agendaClient, let trainingClient, let person = workspace.person,
              let membership = workspace.membership, let learnerID = ownLearner?.id else {
            learnerConsent?.invalidate(); learnerConsent = nil
            requiredActions.replace(.giveRecordingConsent, with: [])
            return
        }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId, membershipID: membership.membershipId,
            accessEpoch: membership.accessEpoch, apiBaseURL: trainingClient.baseURL.absoluteString)
        if let current = learnerConsent, current.scope == scope, current.learnerID == learnerID, !current.accessRevoked {
            if current.needsReload, !current.isLoading, !current.isBusy { await current.load() }
            return
        }
        learnerConsent?.invalidate()
        let model = SchoolOwnRecordingChoice.makeModel(scope: scope, lessonID: nil, learnerID: learnerID,
            agenda: agendaClient, capture: captureController)
        learnerConsent = model
        await model.load()
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
        // Défilement pour pouvoir tirer : un dossier que l’école vient d’ouvrir se lit sans relancer l’app.
        GeometryReader { proxy in
            ScrollView {
                learnerStatusContent(height: proxy.size.height)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .refreshable {
                await workspace.refreshLearners(minimumInterval: 0)
                if workspace.learner != nil {
                    await workspace.loadTrainings()
                    await workspace.loadRemainingTrainings()
                }
            }
        }
        .background(DrivyTheme.surface)
    }

    /// `height` : la hauteur visible. Dans le défilement, un état vide se centre sur elle comme hors défilement.
    @ViewBuilder private func learnerStatusContent(height: CGFloat) -> some View {
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
                .frame(minHeight: height)
        } else if ownLearner == nil {
            ContentUnavailableView("Dossier pas encore ouvert", systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Ton école l’ouvrira bientôt."))
                .frame(minHeight: height)
        } else {
            ContentUnavailableView("Aucune formation", systemImage: "steeringwheel")
                .frame(minHeight: height)
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

/// Le dossier d’un élève en feuille, ouvert depuis une leçon. La sélection de l’onglet Élèves suit cet élève :
/// c’est le même dossier, lu avec les droits de l’école ouverte.
private struct SchoolLessonDossierSheet: View {
    @Bindable var workspace: SchoolWorkspace
    let learnerID: UUID
    let openProfile: ((SchoolLearner) -> Void)?
    let makeLearnerProfile: ((SchoolLearner) -> SchoolProfileWorkspace?)?
    let trainingClient: SchoolTrainingClient?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SchoolLearnerDossierView(workspace: workspace, openProfile: openProfile, makeLearnerProfile: makeLearnerProfile,
            openPlanning: nil, trainingClient: trainingClient, agendaClient: nil, captureController: nil,
            close: { dismiss() })
            .onAppear { if workspace.selectedLearnerID != learnerID { workspace.selectLearner(learnerID) } }
            .tint(DrivyTheme.accent)
    }
}

/// « Revenir au trajet en cours » au-dessus des onglets, depuis n’importe quel onglet (iOS 26.1 et ensuite).
private struct CaptureReturnAccessory<Accessory: View>: ViewModifier {
    let isEnabled: Bool
    @ViewBuilder let button: () -> Accessory

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isEnabled) { button() }
        } else {
            content
        }
    }
}

private enum CaptureReturnSupport {
    static var usesTabAccessory: Bool {
        if #available(iOS 26.1, *) { true } else { false }
    }
}
