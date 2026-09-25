import SwiftUI
import UIKit

/// La donnée qui ouvre la feuille est aussi celle que reçoit son contenu.
/// Une intention ne peut donc pas présenter une feuille sans son modèle initial.
private struct SchoolWorkspaceSheet<Model: AnyObject>: Identifiable {
    let id = UUID()
    let model: Model
}

private struct SchoolMemberSheet: Identifiable {
    let id = UUID()
    let model: SchoolMemberWorkspace
    let mode: SchoolMemberEntryMode
}

struct SchoolRootView: View {
    let configuration: AppConfiguration?
    @Bindable var identity: IdentitySession
    let workspace: SchoolWorkspace?
    let localController: SessionController
    @State private var showsAccount = false
    @State private var showsLocalTrials = false
    @State private var opensTrialsAfterAccount = false
    @State private var opensConfigurationAfterAccount = false
    @State private var configurationRoute: SchoolWorkspaceSheet<SchoolConfigurationWorkspace>?
    @State private var schoolConfiguration: SchoolConfigurationWorkspace?
    @State private var opensInvitationsAfterAccount = false
    @State private var invitationsRoute: SchoolWorkspaceSheet<SchoolInvitationWorkspace>?
    @State private var invitations: SchoolInvitationWorkspace?
    @State private var presenter: UIViewController?
    @State private var profileWorkspace: SchoolProfileWorkspace?
    @State private var profileRoute: SchoolWorkspaceSheet<SchoolProfileWorkspace>?
    @State private var opensProfilePolicyAfterAccount = false
    @State private var opensOnboardingAfterAccount = false
    @State private var opensProfilePolicyAfterConfiguration = false
    @State private var catalogWorkspace: SchoolCatalogWorkspace?
    @State private var catalogRoute: SchoolWorkspaceSheet<SchoolCatalogWorkspace>?
    @State private var memberWorkspace: SchoolMemberWorkspace?
    @State private var membersRoute: SchoolMemberSheet?
    @State private var memberEntryMode: SchoolMemberEntryMode = .team
    @State private var opensInvitationsAfterMembers = false
    @State private var memberLearnerToOpen: SchoolLearner?
    @State private var joinWorkspace: SchoolJoinWorkspace?
    @State private var joinRoute: SchoolWorkspaceSheet<SchoolJoinWorkspace>?
    @State private var opensJoinAfterAccount = false
    @State private var joinMembershipToOpen: SchoolMembership?
    @State private var pendingJoinLink: String?
    @State private var selectedHomeTab: SchoolHomeTab = .session
    @State private var captureController = SchoolCaptureSessionController()
    /// The profile sheet shows the guided welcome only when it was opened for it.
    @State private var onboardingWorkspaceID: UUID?
    /// Memberships already offered the welcome during this launch: « Plus tard » never loops.
    @State private var offeredOnboarding: Set<UUID> = []

    // Les workspaces restent disponibles jusqu’à onDismiss pour la réconciliation.
    // La présentation, elle, est exclusivement pilotée par un item complet.
    private var showsSchoolConfiguration: Bool {
        get { configurationRoute != nil }
        nonmutating set { configurationRoute = newValue ? schoolConfiguration.map { SchoolWorkspaceSheet(model: $0) } : nil }
    }
    private var showsInvitations: Bool {
        get { invitationsRoute != nil }
        nonmutating set { invitationsRoute = newValue ? invitations.map { SchoolWorkspaceSheet(model: $0) } : nil }
    }
    private var showsProfile: Bool {
        get { profileRoute != nil }
        nonmutating set { profileRoute = newValue ? profileWorkspace.map { SchoolWorkspaceSheet(model: $0) } : nil }
    }
    private var showsCatalog: Bool {
        get { catalogRoute != nil }
        nonmutating set { catalogRoute = newValue ? catalogWorkspace.map { SchoolWorkspaceSheet(model: $0) } : nil }
    }
    private var showsMembers: Bool {
        get { membersRoute != nil }
        nonmutating set { membersRoute = newValue ? memberWorkspace.map { SchoolMemberSheet(model: $0, mode: memberEntryMode) } : nil }
    }
    private var showsJoinSchool: Bool {
        get { joinRoute != nil }
        nonmutating set { joinRoute = newValue ? joinWorkspace.map { SchoolWorkspaceSheet(model: $0) } : nil }
    }

    var body: some View {
        joinPresentation
            .sheet(item: $invitationsRoute, onDismiss: invitationsDismissed) { route in
                invitationsSheet(route.model)
            }
            .sheet(item: $configurationRoute, onDismiss: configurationDismissed) { route in
                configurationSheet(route.model)
            }
            .fullScreenCover(isPresented: $showsLocalTrials) {
                localTrialsCover
            }
            .sheet(item: $profileRoute, onDismiss: profileDismissed) { route in
                profileSheet(route.model)
            }
            .task(id: onboardingOfferKey) { await offerOnboardingIfNeeded() }
    }

    private var onboardingOfferKey: String {
        "\(workspace?.membership?.membershipId.uuidString ?? ""):\(workspace?.learners.isEmpty == false)"
    }

    /// First access: open the guided welcome once when the school says it is not finished.
    /// Staff with the ADMIN role only are not forced into it; it stays reachable from the account.
    private func offerOnboardingIfNeeded() async {
        guard identity.isAuthenticated, let configuration, let person = workspace?.person,
              let membership = workspace?.membership, !offeredOnboarding.contains(membership.membershipId),
              membership.roles.contains("LEARNER") || membership.roles.contains("INSTRUCTOR"),
              profileRoute == nil, joinRoute == nil, configurationRoute == nil else { return }
        let isLearner = membership.roles.contains("LEARNER")
        if isLearner && workspace?.learners.isEmpty != false { return }
        offeredOnboarding.insert(membership.membershipId)
        let kind: SchoolOnboardingKind = isLearner ? .student : .staff
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: configuration.apiBaseURL.absoluteString)
        let api = SchoolProfileClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
        guard await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: kind),
              workspace?.membership?.membershipId == membership.membershipId, profileRoute == nil else { return }
        openOnboarding()
    }

    @ViewBuilder
    private var rootContent: some View {
        if identity.isAuthenticated, let workspace {
            authenticatedContent(workspace)
        } else {
            NavigationStack {
                signInLanding
                    .navigationTitle("Drivy")
                    .toolbar { accountToolbar }
            }
        }
    }

    @ViewBuilder
    private func authenticatedContent(_ workspace: SchoolWorkspace) -> some View {
        if workspace.person != nil {
            SchoolHomeView(workspace: workspace, localController: localController,
                openAccount: { showAccount() }, signOut: { signOut() },
                configureSchool: homeConfigurationAction, openInvitations: invitationsAction,
                openProfile: profileAction, openProfilePolicy: homeProfilePolicyAction,
                openOnboarding: homeOnboardingAction, openCatalog: homeCatalogAction,
                openTrainingAdministration: trainingAdministrationAction, agendaClient: homeAgendaClient,
                openMembers: membersAction, openAddLearner: addLearnerAction,
                trainingClient: homeTrainingClient, captureController: captureController,
                selectedTab: $selectedHomeTab)
        } else {
            NavigationStack {
                accountLanding(workspace)
                    .navigationTitle("Mon école")
                    .toolbar { accountToolbar }
            }
        }
    }

    private var observedContent: some View {
        rootContent
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
        .background(SignInPresenter { presenter = $0 }.frame(width: 0, height: 0))
        .task(id: identity.isAuthenticated) {
            captureController.setPersonalCaptureActive(localController.isCapturing)
            if identity.isAuthenticated { await workspace?.loadAccount() }
            else { captureController.setScope(nil); workspace?.reset() }
            updateCaptureScope()
        }
        .onChange(of: identity.isAuthenticated) { _, authenticated in
            if !authenticated {
                captureController.setScope(nil)
                closeJoin(); closeConfiguration(); closeInvitations(); closeProfile(); closeCatalog(); closeMembers()
                selectedHomeTab = .session; workspace?.reset()
            } else if pendingJoinLink != nil { openJoin() }
        }
        .onChange(of: workspace?.membership?.membershipId) { _, _ in
            if workspace?.isLoadingAccount != true { verifyPresentedScopes() }
        }
        .onChange(of: workspace?.membership?.accessEpoch) { _, _ in
            if workspace?.isLoadingAccount != true { verifyPresentedScopes() }
        }
        .onChange(of: workspace?.person?.personId) { _, _ in
            if workspace?.isLoadingAccount != true { updateCaptureScope() }
        }
        .onChange(of: workspace?.isLoadingAccount) { _, loading in
            if loading == false { verifyPresentedScopes() }
        }
        .onChange(of: workspace?.isLoadingSchool) { _, loading in
            if loading == false && workspace?.isLoadingAccount != true { verifyPresentedScopes() }
        }
        .onChange(of: workspace?.school?.status) { _, status in
            if status == "ARCHIVED" { captureController.setScope(nil) }
        }
        .onChange(of: localController.isCapturing) { _, capturing in
            captureController.setPersonalCaptureActive(capturing)
        }
        .onOpenURL { receiveInvitation($0) }
    }

    private var accountPresentation: some View {
        observedContent.sheet(isPresented: $showsAccount, onDismiss: accountDismissed) {
            SchoolAccountView(identity: identity, workspace: workspace, localController: localController,
                openLocalTrials: openTrialsFromAccount,
                localTrialsAvailable: captureController.captureID == nil || captureController.state == .saved,
                configureSchool: accountConfigurationAction,
                openInvitations: accountInvitationsAction, openProfilePolicy: accountProfilePolicyAction,
                openOnboarding: accountOnboardingAction, openJoinSchool: accountJoinAction, signOut: signOut)
        }
    }

    private var catalogPresentation: some View {
        accountPresentation.sheet(item: $catalogRoute, onDismiss: catalogDismissed) { route in
            let catalogWorkspace = route.model
            SchoolCatalogView(model: catalogWorkspace)
                .disabled(isCheckingSchoolAccess)
                .overlay { accessCheckOverlay }
                .onChange(of: catalogWorkspace.accessFailure) { _, failure in
                    if failure != nil { closeCatalog(); Task { await workspace?.loadAccount() } }
                }
        }
    }

    private var homeAgendaClient: SchoolAgendaClient? {
        guard let configuration else { return nil }
        return SchoolAgendaClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
    }

    private var homeTrainingClient: SchoolTrainingClient? {
        guard let configuration else { return nil }
        return SchoolTrainingClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
    }

    private var joinPresentation: some View {
        memberPresentation.sheet(item: $joinRoute, onDismiss: joinDismissed) { route in
            SchoolJoinView(model: route.model, openSchool: { membership in
                joinMembershipToOpen = membership; showsJoinSchool = false
            })
        }
    }
    private var accountJoinAction: (() -> Void)? {
        guard configuration != nil, identity.isAuthenticated else { return nil }
        return { opensJoinAfterAccount = true; showsAccount = false }
    }
    private func openJoin() {
        guard identity.isAuthenticated, let configuration else { return }
        joinWorkspace?.invalidate()
        joinWorkspace = SchoolJoinWorkspace(client: SchoolJoinClient(configuration: configuration, tokenSource: identity), link: pendingJoinLink)
        pendingJoinLink = nil; showsJoinSchool = true
    }
    private func closeJoin() { joinWorkspace?.invalidate(); showsJoinSchool = false; joinMembershipToOpen = nil }
    private func receiveInvitation(_ url: URL) {
        guard let configuration,
              (try? SchoolJoinClient.token(from: url.absoluteString, configuration: configuration)) != nil else { return }
        // An open sheet may already contain an uncertain intention. A new link never replaces it.
        guard !showsJoinSchool else { return }
        pendingJoinLink = url.absoluteString
        if identity.isAuthenticated {
            guard !showsLocalTrials, !showsSchoolConfiguration, !showsInvitations, !showsProfile, !showsCatalog, !showsMembers else { return }
            if showsAccount { opensJoinAfterAccount = true; showsAccount = false }
            else { openJoin() }
        }
    }
    private func joinDismissed() {
        let membership = joinMembershipToOpen
        let principal = joinWorkspace?.record?.principal
        let client = joinWorkspace?.client
        joinMembershipToOpen = nil; joinWorkspace?.invalidate(); joinWorkspace = nil
        guard let membership, let principal, let client, identity.isAuthenticated, let workspace else { return }
        Task {
            guard (try? await client.principal()) == principal, identity.isAuthenticated else { return }
            await workspace.loadAccount()
            guard (try? await client.principal()) == principal, identity.isAuthenticated,
                  let current = workspace.person?.memberships.first(where: {
                      $0.schoolId == membership.schoolId && $0.membershipId == membership.membershipId
                  }) else { return }
            await workspace.selectSchool(current)
            if workspace.membership?.membershipId == current.membershipId { selectedHomeTab = .school }
        }
    }

    private var memberPresentation: some View {
        catalogPresentation.sheet(item: $membersRoute, onDismiss: membersDismissed) { route in
            let memberWorkspace = route.model
            SchoolMemberView(model: memberWorkspace, identity: identity, mode: route.mode,
                openInvitations: {
                    opensInvitationsAfterMembers = true
                    showsMembers = false
                }, openLearner: { learner in
                    memberLearnerToOpen = learner
                    showsMembers = false
                })
                .disabled(isCheckingSchoolAccess)
                .overlay { accessCheckOverlay }
                .onChange(of: memberWorkspace.accessRevoked) { _, revoked in if revoked { closeMembers() } }
                .onChange(of: memberWorkspace.ownAccessChanged) { _, changed in if changed { showsMembers = false } }
        }
    }
    private var membersAction: (() -> Void)? {
        guard canConfigureSchool, workspace?.school?.status == "ACTIVE" else { return nil }
        return { openMembers(mode: .team) }
    }
    private var addLearnerAction: (() -> Void)? {
        guard canConfigureSchool, workspace?.school?.status == "ACTIVE" else { return nil }
        return { openMembers(mode: .addLearner) }
    }
    private func openMembers(mode: SchoolMemberEntryMode) {
        guard canConfigureSchool, workspace?.school?.status == "ACTIVE", let configuration,
              let person = workspace?.person, let membership = workspace?.membership else { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: configuration.apiBaseURL.absoluteString)
        memberWorkspace = SchoolMemberWorkspace(scope: scope, client: SchoolMemberClient(baseURL: configuration.apiBaseURL, tokenSource: identity))
        memberEntryMode = mode; showsMembers = true
    }
    private func closeMembers() { memberWorkspace?.invalidate(); showsMembers = false }
    private func membersDismissed() {
        let learner = memberLearnerToOpen
        let invite = opensInvitationsAfterMembers
        let personID = memberWorkspace?.scope.personID
        let schoolID = memberWorkspace?.scope.schoolID
        let accessChanged = memberWorkspace?.ownAccessChanged == true || memberWorkspace?.accessRevoked == true
        memberLearnerToOpen = nil; opensInvitationsAfterMembers = false
        memberWorkspace?.invalidate(); memberWorkspace = nil
        guard identity.isAuthenticated, accessChanged || learner != nil || invite else { return }
        Task {
            if accessChanged { await workspace?.loadAccount() }
            guard workspace?.person?.personId == personID, workspace?.membership?.schoolId == schoolID else { return }
            if let learner, learner.schoolId == schoolID {
                workspace?.selectLearner(learner.id)
                selectedHomeTab = .learners
                await workspace?.loadSelectedLearner()
            }
            if invite { openInvitations() }
        }
    }

    private var homeCatalogAction: (() -> Void)? {
        guard canConfigureSchool else { return nil }
        return { openCatalog() }
    }

    private var trainingAdministrationAction: ((SchoolLearner) -> Void)? {
        guard canConfigureSchool, workspace?.school?.status == "ACTIVE" else { return nil }
        return { learner in openCatalog(learner: learner) }
    }

    private func openCatalog(learner: SchoolLearner? = nil) {
        guard canConfigureSchool, let configuration, let person = workspace?.person, let membership = workspace?.membership else { return }
        if let learner, learner.schoolId != membership.schoolId { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: configuration.apiBaseURL.absoluteString)
        catalogWorkspace = SchoolCatalogWorkspace(scope: scope, learner: learner,
            api: SchoolCatalogClient(baseURL: configuration.apiBaseURL, tokenSource: identity))
        showsCatalog = true
    }

    private func closeCatalog() { catalogWorkspace?.invalidate(); showsCatalog = false }
    private func catalogDismissed() {
        catalogWorkspace?.invalidate(); catalogWorkspace = nil
        if identity.isAuthenticated, workspace?.selectedLearnerID != nil { Task { await workspace?.loadSelectedLearner() } }
    }

    private func invitationsSheet(_ invitations: SchoolInvitationWorkspace) -> some View {
        SchoolInvitationsView(model: invitations)
            .disabled(isCheckingSchoolAccess)
            .overlay { accessCheckOverlay }
            .onChange(of: invitations.accessFailure) { _, failure in
                if let failure {
                    closeInvitations()
                    workspace?.rejectCurrentAccess(requiresAuthentication: failure == .unauthorized)
                }
            }
    }

    private func configurationSheet(_ schoolConfiguration: SchoolConfigurationWorkspace) -> some View {
        SchoolConfigurationView(model: schoolConfiguration, openSchool: { showsSchoolConfiguration = false },
            openProfilePolicy: openPolicyFromConfiguration)
            .disabled(isCheckingSchoolAccess)
            .overlay { accessCheckOverlay }
            .onChange(of: schoolConfiguration.accessFailure) { _, failure in
                if let failure {
                    closeConfiguration()
                    workspace?.rejectCurrentAccess(requiresAuthentication: failure == .unauthorized)
                }
            }
    }

    @ViewBuilder
    private var accessCheckOverlay: some View {
        if isCheckingSchoolAccess {
            DrivyTheme.canvas.ignoresSafeArea().overlay { ProgressView("Vérification de vos accès…") }
        }
    }

    private func profileSheet(_ profileWorkspace: SchoolProfileWorkspace) -> some View {
        profileContent(profileWorkspace)
            .disabled(isCheckingSchoolAccess)
            .overlay { accessCheckOverlay }
            .onChange(of: profileWorkspace.accessFailure) { _, failure in
                if failure != nil {
                    closeProfile()
                    Task { await workspace?.loadAccount() }
                }
            }
    }
    @ViewBuilder private func profileContent(_ model: SchoolProfileWorkspace) -> some View {
        if model.isPolicyManagement { SchoolProfilePolicyView(model: model) }
        else if model.id == onboardingWorkspaceID { SchoolOnboardingView(model: model, trainings: workspace?.trainings ?? []) }
        else { SchoolProfileView(model: model) }
    }
    private var profileAction: ((SchoolLearner) -> Void)? {
        guard configuration != nil, workspace?.membership != nil else { return nil }
        return { learner in openProfile(learner) }
    }
    private var accountProfilePolicyAction: (() -> Void)? {
        guard canConfigureSchool else { return nil }
        return { opensProfilePolicyAfterAccount = true; showsAccount = false }
    }
    private var accountOnboardingAction: (() -> Void)? {
        guard configuration != nil, workspace?.membership != nil else { return nil }
        return { opensOnboardingAfterAccount = true; showsAccount = false }
    }
    private func openPolicyFromConfiguration() {
        opensProfilePolicyAfterConfiguration = true
        showsSchoolConfiguration = false
    }
    private func makeProfileWorkspace(learner: SchoolLearner? = nil, onboardingOnly: Bool = false) -> SchoolProfileWorkspace? {
        guard let configuration, let person = workspace?.person, let membership = workspace?.membership else { return nil }
        if let learner, learner.schoolId != membership.schoolId { return nil }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: configuration.apiBaseURL.absoluteString)
        var targetLearner = learner
        if targetLearner == nil, onboardingOnly, membership.roles.contains("LEARNER") {
            targetLearner = workspace?.learners.first { $0.personId == person.personId }
        }
        let isOwn = targetLearner?.personId == person.personId && membership.roles.contains("LEARNER")
        let kind: SchoolOnboardingKind?
        if isOwn { kind = .student }
        else if onboardingOnly { kind = membership.roles.contains("LEARNER") ? .student : .staff }
        else { kind = nil }
        return SchoolProfileWorkspace(scope: scope, roles: membership.roles, learnerID: targetLearner?.id,
            isOwnProfile: isOwn, onboardingKind: kind,
            api: SchoolProfileClient(baseURL: configuration.apiBaseURL, tokenSource: identity))
    }
    private func openProfile(_ learner: SchoolLearner) {
        guard let model = makeProfileWorkspace(learner: learner) else { return }
        onboardingWorkspaceID = nil
        profileWorkspace = model; showsProfile = true
    }
    private func openProfilePolicy() {
        guard canConfigureSchool, let model = makeProfileWorkspace() else { return }
        onboardingWorkspaceID = nil
        profileWorkspace = model; showsProfile = true
    }
    private func openOnboarding() {
        guard let model = makeProfileWorkspace(onboardingOnly: true) else { return }
        onboardingWorkspaceID = model.id
        profileWorkspace = model; showsProfile = true
    }
    private func closeProfile() { profileWorkspace?.invalidate(); showsProfile = false }
    private func profileDismissed() {
        profileWorkspace?.invalidate(); profileWorkspace = nil; onboardingWorkspaceID = nil
        if identity.isAuthenticated, workspace?.selectedLearnerID != nil {
            Task { await workspace?.loadSelectedLearner() }
        }
    }

    private var localTrialsCover: some View {
        VStack(spacing: 0) {
            HStack {
                Button { showsLocalTrials = false } label: {
                    Label("Retour à Drivy", systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                Spacer()
                Text("Essais locaux")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
            }
            .padding(.horizontal, DrivySpacing.m)
            .background(DrivyTheme.surface)
            .overlay(alignment: .bottom) { Divider().overlay(DrivyTheme.border) }
            QualificationRootView(controller: localController)
                .task { await localController.load() }
        }
        .tint(DrivyTheme.accent)
        .background(DrivyTheme.surface)
    }

    private var invitationsAction: (() -> Void)? {
        guard canManageInvitations else { return nil }
        let action: () -> Void = { openInvitations() }
        return action
    }

    private var homeConfigurationAction: (() -> Void)? {
        guard canConfigureSchool else { return nil }
        return { openConfiguration() }
    }

    private var homeProfilePolicyAction: (() -> Void)? {
        guard canConfigureSchool else { return nil }
        return { openProfilePolicy() }
    }

    private var homeOnboardingAction: (() -> Void)? {
        guard configuration != nil, workspace?.membership != nil else { return nil }
        return { openOnboarding() }
    }

    private var accountConfigurationAction: (() -> Void)? {
        guard canConfigureSchool else { return nil }
        let action: () -> Void = { openConfigurationFromAccount() }
        return action
    }

    private var accountInvitationsAction: (() -> Void)? {
        guard canManageInvitations else { return nil }
        let action: () -> Void = { openInvitationsFromAccount() }
        return action
    }

    private func showAccount() { showsAccount = true }

    private func openTrialsFromAccount() {
        guard captureController.captureID == nil || captureController.state == .saved else { return }
        opensTrialsAfterAccount = true
        showsAccount = false
    }

    private func openConfigurationFromAccount() {
        opensConfigurationAfterAccount = true
        showsAccount = false
    }

    private func openInvitationsFromAccount() {
        opensInvitationsAfterAccount = true
        showsAccount = false
    }

    private func accountDismissed() {
        if opensJoinAfterAccount {
            opensJoinAfterAccount = false; openJoin()
            return
        }
        if opensTrialsAfterAccount {
            opensTrialsAfterAccount = false
            showsLocalTrials = true
        }
        if opensConfigurationAfterAccount {
            opensConfigurationAfterAccount = false
            openConfiguration()
        }
        if opensInvitationsAfterAccount {
            opensInvitationsAfterAccount = false
            openInvitations()
        }
        if opensProfilePolicyAfterAccount {
            opensProfilePolicyAfterAccount = false; openProfilePolicy()
        }
        if opensOnboardingAfterAccount {
            opensOnboardingAfterAccount = false; openOnboarding()
        }
    }

    private func invitationsDismissed() {
        invitations?.invalidate()
        invitations = nil
    }

    private func configurationDismissed() {
        let scope = schoolConfiguration?.scope
        let updatedSchool = schoolConfiguration?.school
        let schoolChanged = updatedSchool != nil && updatedSchool != workspace?.school
        let opensPolicy = opensProfilePolicyAfterConfiguration
        opensProfilePolicyAfterConfiguration = false
        schoolConfiguration?.invalidate()
        schoolConfiguration = nil
        guard identity.isAuthenticated, let scope,
              workspace?.person?.personId == scope.personID,
              let membership = workspace?.membership,
              membership.membershipId == scope.membershipID,
              membership.accessEpoch == scope.accessEpoch else { return }
        if schoolChanged {
            Task {
                await workspace?.loadAccount()
                guard identity.isAuthenticated,
                      workspace?.person?.personId == scope.personID,
                      workspace?.membership?.schoolId == scope.schoolID,
                      workspace?.membership?.membershipId == scope.membershipID,
                      workspace?.membership?.accessEpoch == scope.accessEpoch else { return }
                if opensPolicy { openProfilePolicy() }
            }
        } else if opensPolicy {
            openProfilePolicy()
        }
    }

    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        if identity.isAuthenticated, configuration != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button { openJoin() } label: { Label("Rejoindre une école", systemImage: "envelope.open") }
                    .accessibilityIdentifier("open-join-school")
            }
        }
        DrivyAccountToolbarItem(openAccount: { showsAccount = true })
    }

    private var signInLanding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                DrivyRouteGlyph()
                    .frame(height: 120)
                    .padding(DrivySpacing.l)
                    .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous)
                            .strokeBorder(DrivyTheme.border, lineWidth: 0.5)
                    }
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Text("Vos leçons, vos trajets, votre école.")
                        .font(.drivyScreenTitle)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Connectez-vous pour retrouver votre école, vos dossiers et vos formations autorisés.")
                        .font(.body)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if configuration == nil {
                    DrivyInlineMessage(text: "La connexion scolaire n’est pas encore activée dans cette version.", tone: .neutral)
                        .accessibilityIdentifier("school-not-configured")
                } else if let error = identity.errorMessage {
                    SchoolErrorNotice(message: error)
                }
                DrivyRowGroup(title: "Sans compte") {
                    localTrialsEntry
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if configuration != nil {
                Button(action: signIn) {
                    if identity.isWorking {
                        DrivyBusyLabel(title: "Se connecter", busyTitle: "Connexion en cours…", isBusy: true)
                    } else {
                        Label("Se connecter", systemImage: "person.crop.circle")
                    }
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(identity.isWorking || presenter == nil)
                .accessibilityIdentifier("school-sign-in")
                .padding(.horizontal, DrivySpacing.l)
                .padding(.vertical, DrivySpacing.s)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.surface)
                .overlay(alignment: .top) { Divider().overlay(DrivyTheme.border) }
            }
        }
    }

    @ViewBuilder
    private func accountLanding(_ workspace: SchoolWorkspace) -> some View {
        if workspace.isLoadingAccount {
            ProgressView("Chargement de vos écoles…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DrivyTheme.canvas)
        } else if let error = workspace.accountError {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    SchoolErrorNotice(message: error)
                    if workspace.requiresAuthentication {
                        Button("Se reconnecter") {
                            workspace.reset()
                            Task {
                                await identity.signOut()
                                signIn()
                            }
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                    } else {
                        Button("Actualiser mes écoles") { Task { await workspace.loadAccount() } }
                            .buttonStyle(DrivyPrimaryButtonStyle())
                    }
                    if identity.isAuthenticated, !workspace.requiresAuthentication {
                        Button { openJoin() } label: { Label("J’ai une invitation", systemImage: "envelope.open") }
                            .buttonStyle(DrivySecondaryButtonStyle())
                    }
                    DrivyRowGroup(title: "Sans école") {
                        localTrialsEntry
                    }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
        } else if let person = workspace.person, person.memberships.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    ContentUnavailableView("Aucune école pour le moment", systemImage: "building.2", description: Text("Votre compte est connecté. Demandez à votre école de vous donner accès à votre dossier, ou ouvrez le lien d’invitation reçu."))
                    Button("Actualiser mes écoles") { Task { await workspace.loadAccount() } }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                    if identity.isAuthenticated, configuration != nil {
                        Button { openJoin() } label: { Label("J’ai une invitation", systemImage: "envelope.open") }
                            .buttonStyle(DrivySecondaryButtonStyle())
                    }
                    DrivyRowGroup(title: "Sans école") {
                        localTrialsEntry
                    }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
        } else {
            SchoolChooserView(workspace: workspace)
        }
    }

    private var localTrialsEntry: some View {
        DrivyNavigationRow(title: localController.isCapturing ? "Revenir à l’essai en cours" : "Essais locaux",
            detail: "Essayer la carte et les observations, séparément des dossiers de l’école.",
            symbol: "map", action: { showsLocalTrials = true })
            .accessibilityIdentifier("open-local-trials")
    }

    private func signIn() {
        guard let presenter else { return }
        Task { await identity.signIn(presenting: presenter) }
    }

    private func signOut() {
        captureController.setScope(nil)
        pendingJoinLink = nil
        closeJoin()
        closeMembers()
        closeCatalog()
        closeProfile()
        closeConfiguration()
        closeInvitations()
        workspace?.reset()
        showsAccount = false
        Task { await identity.signOut() }
    }

    private var canConfigureSchool: Bool {
        configuration != nil && workspace?.membership?.roles.contains("ADMIN") == true
            && workspace?.school != nil && workspace?.school?.status != "ARCHIVED"
    }

    private var isCheckingSchoolAccess: Bool {
        workspace?.isLoadingAccount == true || workspace?.isLoadingSchool == true
    }

    private var canManageInvitations: Bool {
        configuration != nil && workspace?.school?.status == "ACTIVE"
            && (workspace?.membership?.roles.contains("ADMIN") == true || workspace?.membership?.roles.contains("INSTRUCTOR") == true)
    }

    private func openInvitations() {
        guard canManageInvitations, let configuration, let person = workspace?.person,
              let membership = workspace?.membership else { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch,
            apiBaseURL: configuration.apiBaseURL.absoluteString)
        invitations = SchoolInvitationWorkspace(scope: scope, roles: membership.roles,
            api: SchoolInvitationClient(baseURL: configuration.apiBaseURL, tokenSource: identity))
        showsInvitations = true
    }

    private func closeInvitations() {
        invitations?.invalidate()
        showsInvitations = false
    }

    private func verifyPresentedScopes() {
        updateCaptureScope()
        if let model = memberWorkspace {
            if !canConfigureSchool || model.scope.personID != workspace?.person?.personId
                || model.scope.membershipID != workspace?.membership?.membershipId
                || model.scope.accessEpoch != workspace?.membership?.accessEpoch { closeMembers() }
        }
        if let model = catalogWorkspace {
            if !canConfigureSchool || model.scope.personID != workspace?.person?.personId
                || model.scope.membershipID != workspace?.membership?.membershipId
                || model.scope.accessEpoch != workspace?.membership?.accessEpoch { closeCatalog() }
        }
        verifyConfigurationScope()
        verifyProfileScope()
        guard let model = invitations else { return }
        guard canManageInvitations, let person = workspace?.person, let membership = workspace?.membership,
              model.scope.personID == person.personId, model.scope.schoolID == membership.schoolId,
              model.scope.membershipID == membership.membershipId, model.scope.accessEpoch == membership.accessEpoch else {
            closeInvitations()
            return
        }
    }

    private func updateCaptureScope() {
        guard identity.isAuthenticated, workspace?.school?.status != "ARCHIVED", let configuration,
              let person = workspace?.person, let membership = workspace?.membership else {
            captureController.setScope(nil)
            return
        }
        // La recharge conserve la même portée. Changer d'école, de compte ou
        // d'epoch ferme immédiatement la source de l'ancienne séance.
        captureController.setScope(SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch,
            apiBaseURL: configuration.apiBaseURL.absoluteString))
    }

    private func verifyProfileScope() {
        guard let model = profileWorkspace else { return }
        guard let person = workspace?.person, let membership = workspace?.membership,
              model.scope.personID == person.personId, model.scope.schoolID == membership.schoolId,
              model.scope.membershipID == membership.membershipId, model.scope.accessEpoch == membership.accessEpoch else {
            closeProfile(); return
        }
        if model.isPolicyManagement && !canConfigureSchool { closeProfile() }
    }

    private func openConfiguration() {
        guard canConfigureSchool, let configuration, let person = workspace?.person,
              let membership = workspace?.membership else { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch,
            apiBaseURL: configuration.apiBaseURL.absoluteString)
        schoolConfiguration = SchoolConfigurationWorkspace(scope: scope,
            api: SchoolConfigurationClient(baseURL: configuration.apiBaseURL, tokenSource: identity))
        showsSchoolConfiguration = true
    }

    private func verifyConfigurationScope() {
        guard let model = schoolConfiguration else { return }
        guard configuration != nil, let person = workspace?.person, let membership = workspace?.membership,
              membership.roles.contains("ADMIN"), workspace?.school?.status != "ARCHIVED",
              model.scope.personID == person.personId, model.scope.schoolID == membership.schoolId,
              model.scope.membershipID == membership.membershipId, model.scope.accessEpoch == membership.accessEpoch else {
            closeConfiguration()
            return
        }
    }

    private func closeConfiguration() {
        schoolConfiguration?.invalidate()
        showsSchoolConfiguration = false
    }
}

private struct SchoolAccountView: View {
    @Bindable var identity: IdentitySession
    let workspace: SchoolWorkspace?
    let localController: SessionController
    let openLocalTrials: () -> Void
    let localTrialsAvailable: Bool
    let configureSchool: (() -> Void)?
    let openInvitations: (() -> Void)?
    let openProfilePolicy: (() -> Void)?
    let openOnboarding: (() -> Void)?
    let openJoinSchool: (() -> Void)?
    let signOut: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Mockup 11: one reading page, grouped action rows with the same anatomy
    /// as the École tab, sign-out closing the page.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                    accountHeading
                    if identity.isAuthenticated { schoolGroup }
                    if identity.isAuthenticated, openProfilePolicy != nil || openInvitations != nil || configureSchool != nil {
                        DrivyRowGroup(title: "Administration de l’école") {
                            if let configureSchool {
                                DrivyNavigationRow(title: "Préparer mon école", detail: "Coordonnées, textes et activation",
                                    symbol: "slider.horizontal.3", action: configureSchool)
                                    .accessibilityIdentifier("open-school-configuration")
                            }
                            if let openInvitations {
                                DrivyNavigationRow(title: "Invitations", detail: "Inviter une personne et suivre les liens",
                                    symbol: "envelope", action: openInvitations)
                                    .accessibilityIdentifier("open-school-invitations")
                            }
                            if let openProfilePolicy {
                                DrivyNavigationRow(title: "Champs du profil", detail: "Informations demandées aux élèves",
                                    symbol: "list.bullet.rectangle", action: openProfilePolicy)
                                    .accessibilityIdentifier("open-profile-policies")
                            }
                        }
                    }
                    localTrialsGroup
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        DrivySectionHeader(title: "Confidentialité")
                        StorageCaption(message: "Cet espace affiche les données autorisées par votre école. Elles sont retirées de l’appareil à la déconnexion ou au changement d’école.")
                    }
                    if identity.isAuthenticated {
                        DrivyDestructiveRow(title: "Se déconnecter", symbol: "rectangle.portrait.and.arrow.right", action: signOut)
                            .accessibilityIdentifier("school-sign-out")
                    }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .tint(DrivyTheme.accent)
    }

    private var accountHeading: some View {
        HStack(spacing: DrivySpacing.m) {
            DrivyAvatar(name: workspace?.person?.displayName ?? "Compte", size: 60)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Group {
                    if let person = workspace?.person {
                        Text(person.displayName)
                    } else {
                        Text(identity.isAuthenticated ? "Compte connecté" : "Aucun compte connecté")
                    }
                }
                .font(.drivyTitle)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                if let membership = workspace?.membership {
                    Text("\(membership.schoolName) · \(SchoolPresentation.roles(membership.roles))")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var schoolGroup: some View {
        DrivyRowGroup(title: "Mon école") {
            if let workspace, workspace.membership != nil, (workspace.person?.memberships.count ?? 0) > 1 {
                DrivyNavigationRow(title: "Changer d’école", detail: workspace.membership?.schoolName,
                    symbol: "arrow.left.arrow.right", action: {
                        workspace.leaveSchool()
                        dismiss()
                    })
                    .accessibilityIdentifier("school-change-school")
            }
            if let openJoinSchool {
                DrivyNavigationRow(title: "Rejoindre une école", detail: "Avec le lien d’invitation reçu",
                    symbol: "envelope.open", action: openJoinSchool)
                    .accessibilityIdentifier("open-join-school")
            }
            if let openOnboarding {
                DrivyNavigationRow(title: "Accueil dans l’école", detail: "Vos informations, votre formation, le GPS",
                    symbol: "figure.wave", action: openOnboarding)
                    .accessibilityIdentifier("open-my-onboarding")
            }
            DrivyNavigationRow(title: "Actualiser mes accès", detail: "Relire vos écoles et vos rôles",
                symbol: "arrow.clockwise", action: {
                    dismiss()
                    Task { await workspace?.loadAccount() }
                })
        }
    }

    /// Local trials stay on this device and are not lessons of the school.
    /// While a school session runs, the row stays visible and says why it waits.
    private var localTrialsGroup: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivyRowGroup(title: "Essais locaux") {
                DrivyNavigationRow(title: localController.isCapturing ? "Revenir à l’essai en cours" : "Essais locaux",
                    detail: localTrialsAvailable ? "Carte et observations, séparées des dossiers de l’école"
                        : "Terminez la séance de l’école avant d’ouvrir un trajet personnel.",
                    symbol: "map",
                    badge: localTrialsAvailable ? nil : DrivyStatusBadge(title: "Indisponible", symbol: "lock"),
                    action: openLocalTrials)
                    .accessibilityIdentifier("open-local-trials")
                    .disabled(!localTrialsAvailable)
            }
            Text("Les essais locaux restent sur cet appareil. Ils ne sont pas des leçons de votre école.")
                .font(.footnote)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Resolve the presenting controller in this scene, never an arbitrary window.
private struct SignInPresenter: UIViewControllerRepresentable {
    let resolve: @MainActor (UIViewController) -> Void

    func makeUIViewController(context: Context) -> AnchorController {
        let controller = AnchorController()
        controller.resolve = resolve
        return controller
    }

    func updateUIViewController(_ controller: AnchorController, context: Context) {
        controller.resolve = resolve
    }

    final class AnchorController: UIViewController {
        var resolve: (@MainActor (UIViewController) -> Void)?
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            resolve?(self)
        }
    }
}
