import SwiftUI
import UIKit

/// La donnée qui ouvre la feuille est aussi celle que reçoit son contenu.
/// Une intention ne peut donc pas présenter une feuille sans son modèle initial.
private struct SchoolWorkspaceSheet<Model: AnyObject>: Identifiable {
    let id = UUID()
    let model: Model
}

/// Ce que le compte ouvre une fois sa feuille fermée : une seule feuille à la fois.
private enum AccountFollowUp { case join, invitations, profile, onboarding }

struct SchoolRootView: View {
    let configuration: AppConfiguration?
    @Bindable var identity: IdentitySession
    let workspace: SchoolWorkspace?
    /// Created once by the app; nil only without configuration.
    var clients: SchoolHomeClients? = nil
    @State private var showsAccount = false
    @State private var afterAccount: AccountFollowUp?
    @State private var presenter: UIViewController?
    // Les modèles restent disponibles jusqu’à onDismiss pour la réconciliation ;
    // la présentation, elle, est pilotée par un item complet.
    @State private var invitations: SchoolInvitationWorkspace?
    @State private var invitationsRoute: SchoolWorkspaceSheet<SchoolInvitationWorkspace>?
    @State private var inviteRoute: SchoolWorkspaceSheet<SchoolInvitationWorkspace>?
    @State private var profileWorkspace: SchoolProfileWorkspace?
    @State private var profileRoute: SchoolWorkspaceSheet<SchoolProfileWorkspace>?
    @State private var joinWorkspace: SchoolJoinWorkspace?
    @State private var joinRoute: SchoolWorkspaceSheet<SchoolJoinWorkspace>?
    @State private var codeJoinWorkspace: SchoolCodeJoinWorkspace?
    @State private var codeJoinRoute: SchoolWorkspaceSheet<SchoolCodeJoinWorkspace>?
    /// « J’ai un lien d’invitation » closes the code sheet, then opens the link one.
    @State private var opensLinkAfterCode = false
    @State private var joinMembershipToOpen: SchoolMembership?
    @State private var pendingJoinLink: String?
    @State private var joinsByCodeAfterSignIn = false
    @State private var selectedHomeTab: SchoolHomeTab = .session
    @State private var captureController = SchoolCaptureSessionController()
    @Environment(\.scenePhase) private var scenePhase
    /// The profile sheet shows the guided welcome only when it was opened for it.
    @State private var onboardingWorkspaceID: UUID?
    /// Memberships already offered the welcome during this launch: « Plus tard » never loops.
    /// Across launches, SchoolOnboardingDeferral keeps the offer away for seven days.
    @State private var offeredOnboarding: Set<UUID> = []
    /// Confirmé par la lecture serveur, même si l’offre automatique a été reportée.
    @State private var staffOnboardingToResume: UUID?

    private var presentsSheet: Bool {
        joinRoute != nil || codeJoinRoute != nil || invitationsRoute != nil || inviteRoute != nil || profileRoute != nil
    }

    var body: some View {
        presentations
            .task(id: onboardingOfferKey) { await offerOnboardingIfNeeded() }
    }

    // MARK: Contenu

    @ViewBuilder
    private var rootContent: some View {
        if identity.isAuthenticated, let workspace {
            if workspace.person != nil {
                SchoolHomeView(workspace: workspace, openAccount: { showsAccount = true },
                    account: accountActions, inviteLearner: inviteAction, openProfile: profileAction, agendaClient: homeAgendaClient,
                    trainingClient: homeTrainingClient, captureController: captureController,
                    joinSchool: joinByCodeAction, selectedTab: $selectedHomeTab)
            } else {
                NavigationStack {
                    accountLanding(workspace)
                        .navigationTitle("Drivy")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { DrivyAccountToolbarItem(openAccount: { showsAccount = true }) }
                }
            }
        } else {
            NavigationStack {
                signInLanding
                    .navigationTitle("Drivy")
            }
        }
    }

    private var observedContent: some View {
        rootContent
        // The session controller is shared with every screen of the signed-in content:
        // read it with `@Environment(SchoolCaptureSessionController.self)` (optional).
        .environment(captureController)
        .environment(\.drivyAccountName, workspace?.person?.displayName)
        .tint(DrivyTheme.accent)
        .foregroundStyle(DrivyTheme.text)
        .background(SignInPresenter { presenter = $0 }.frame(width: 0, height: 0))
        .task(id: identity.isAuthenticated) {
            if identity.isAuthenticated { await workspace?.loadAccount() }
            else { captureController.setScope(nil); workspace?.reset() }
            updateCaptureScope()
        }
        .onChange(of: identity.isAuthenticated) { _, authenticated in
            if !authenticated {
                captureController.setScope(nil)
                closeAll(); selectedHomeTab = .session; workspace?.reset()
            } else if pendingJoinLink != nil { openJoin() }
            else if joinsByCodeAfterSignIn { joinsByCodeAfterSignIn = false; openCodeJoin() }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateCaptureScope() }
        }
        .safeAreaInset(edge: .top) {
            if identity.isAuthenticated, let error = captureController.pendingSynchronizationError {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Button("Réessayer la synchronisation") {
                        Task { await captureController.retryPendingSynchronizations() }
                    }
                    .frame(minHeight: 44)
                }
                .drivyPageContent()
                .background(DrivyTheme.surface)
            }
        }
        .onOpenURL { receiveInvitation($0) }
    }

    // MARK: Feuilles

    private var accountLayer: some View {
        observedContent.sheet(isPresented: $showsAccount, onDismiss: accountDismissed) {
            SchoolAccountView(isAuthenticated: identity.isAuthenticated, workspace: workspace, manageURL: manageURL,
                openProfile: followUp(.profile, when: ownProfileLearner != nil),
                openInvitations: followUp(.invitations, when: canManageInvitations),
                openJoinSchool: followUp(.join, when: configuration != nil && identity.isAuthenticated),
                signOut: signOut, resumeOnboarding: followUp(.onboarding, when: canResumeStaffOnboarding))
        }
    }

    private var joinLayer: some View {
        accountLayer
            .sheet(item: $joinRoute, onDismiss: joinDismissed) { route in
                SchoolJoinView(model: route.model, openSchool: { membership in
                    joinMembershipToOpen = membership; joinRoute = nil
                })
            }
            .sheet(item: $codeJoinRoute, onDismiss: codeJoinDismissed) { route in
                SchoolCodeJoinView(model: route.model, openSchool: { membership in
                    joinMembershipToOpen = membership; codeJoinRoute = nil
                }, useLink: { opensLinkAfterCode = true; codeJoinRoute = nil })
            }
    }

    private var invitationLayer: some View {
        joinLayer
            .sheet(item: $invitationsRoute, onDismiss: invitationsDismissed) { route in
                invitationSheet(SchoolInvitationsView(model: route.model), model: route.model)
            }
            .sheet(item: $inviteRoute, onDismiss: invitationsDismissed) { route in
                invitationSheet(InvitationCreationView(model: route.model, learnerOnly: true), model: route.model)
            }
    }

    private var profileLayer: some View {
        invitationLayer.sheet(item: $profileRoute, onDismiss: profileDismissed) { route in
            profileContent(route.model)
                .disabled(isCheckingSchoolAccess)
                .overlay { accessCheckOverlay }
                .onChange(of: route.model.accessFailure) { _, failure in
                    if failure != nil { closeProfile(); Task { await workspace?.loadAccount() } }
                }
        }
    }

    private var presentations: some View { profileLayer }

    private func invitationSheet<Content: View>(_ content: Content, model: SchoolInvitationWorkspace) -> some View {
        content
            .disabled(isCheckingSchoolAccess)
            .overlay { accessCheckOverlay }
            .onChange(of: model.accessFailure) { _, failure in
                if let failure {
                    closeInvitations()
                    workspace?.rejectCurrentAccess(requiresAuthentication: failure == .unauthorized)
                }
            }
    }

    @ViewBuilder private func profileContent(_ model: SchoolProfileWorkspace) -> some View {
        if model.id == onboardingWorkspaceID { SchoolOnboardingView(model: model, trainings: workspace?.trainings ?? []) }
        else { SchoolProfileView(model: model) }
    }

    @ViewBuilder
    private var accessCheckOverlay: some View {
        if isCheckingSchoolAccess {
            DrivyTheme.canvas.ignoresSafeArea().overlay {
                ProgressView("Vérification de tes accès…").foregroundStyle(DrivyTheme.muted)
            }
        }
    }

    // MARK: Compte

    /// From the account sheet, the action waits for the sheet to close; from the Profil tab, it runs at once.
    private func follow(_ action: AccountFollowUp) {
        if showsAccount { afterAccount = action; showsAccount = false } else { perform(action) }
    }
    private func followUp(_ action: AccountFollowUp, when enabled: Bool) -> (() -> Void)? {
        guard enabled else { return nil }
        return { follow(action) }
    }

    private func accountDismissed() {
        guard let action = afterAccount else { return }
        afterAccount = nil
        perform(action)
    }

    private func perform(_ action: AccountFollowUp) {
        switch action {
        case .join:
            if pendingJoinLink != nil { openJoin() } else { openCodeJoin() }
        case .invitations: openInvitations(creation: false)
        case .profile: if let learner = ownProfileLearner { openProfile(learner) }
        case .onboarding: if canResumeStaffOnboarding && !presentsSheet { openOnboarding() }
        }
    }

    /// Les actions du compte, pour l’onglet Profil du moniteur et de l’administration.
    private var accountActions: SchoolAccountActions {
        SchoolAccountActions(manageURL: manageURL,
            openProfile: followUp(.profile, when: ownProfileLearner != nil),
            openInvitations: followUp(.invitations, when: canManageInvitations),
            openJoinSchool: followUp(.join, when: configuration != nil && identity.isAuthenticated),
            signOut: signOut, resumeOnboarding: followUp(.onboarding, when: canResumeStaffOnboarding))
    }

    private var canResumeStaffOnboarding: Bool {
        guard configuration != nil, identity.isAuthenticated, workspace?.school?.status == "ACTIVE",
              let membership = workspace?.membership else { return false }
        return membership.roles.contains("INSTRUCTOR") && !membership.roles.contains("LEARNER")
            && staffOnboardingToResume == membership.membershipId
    }

    /// La gestion de l’école est réservée à l’administration, sur le portail web.
    private var manageURL: URL? {
        guard let configuration, let membership = workspace?.membership, membership.roles.contains("ADMIN") else { return nil }
        return configuration.managementURL(schoolID: membership.schoolId)
    }

    private var ownProfileLearner: SchoolLearner? {
        guard let person = workspace?.person, workspace?.membership?.roles.contains("LEARNER") == true else { return nil }
        return workspace?.learners.first { $0.personId == person.personId }
    }

    // MARK: Rejoindre une école

    private func openJoin() {
        guard identity.isAuthenticated, let configuration else { return }
        joinWorkspace?.invalidate()
        let model = SchoolJoinWorkspace(client: SchoolJoinClient(configuration: configuration, tokenSource: identity), link: pendingJoinLink)
        joinWorkspace = model
        pendingJoinLink = nil; joinRoute = SchoolWorkspaceSheet(model: model)
    }
    private func closeJoin() { joinWorkspace?.invalidate(); joinRoute = nil; joinMembershipToOpen = nil }
    private func receiveInvitation(_ url: URL) {
        guard let configuration,
              (try? SchoolJoinClient.token(from: url.absoluteString, configuration: configuration)) != nil else { return }
        // An open sheet may already contain an uncertain intention. A new link never replaces it.
        guard joinRoute == nil else { return }
        pendingJoinLink = url.absoluteString
        if identity.isAuthenticated {
            guard !presentsSheet else { return }
            if showsAccount { follow(.join) } else { openJoin() }
        }
    }
    private func joinDismissed() {
        // Fermer (ou glisser) après « Tu as rejoint l’école » ouvre aussi l’école rejointe : le compte est relu dans tous les cas.
        let membership = joinMembershipToOpen ?? joinWorkspace?.member
        let principal = joinWorkspace?.record?.principal
        let client = joinWorkspace?.client
        joinMembershipToOpen = nil; joinWorkspace?.invalidate(); joinWorkspace = nil
        openJoinedSchool(membership, principal: principal, client: client)
    }

    // MARK: Rejoindre avec un code

    private var joinByCodeAction: (() -> Void)? {
        configuration != nil && identity.isAuthenticated ? { openCodeJoin() } : nil
    }
    private func openCodeJoin() {
        guard identity.isAuthenticated, let configuration, !presentsSheet else { return }
        codeJoinWorkspace?.invalidate()
        let model = SchoolCodeJoinWorkspace(client: SchoolJoinClient(configuration: configuration, tokenSource: identity))
        codeJoinWorkspace = model; codeJoinRoute = SchoolWorkspaceSheet(model: model)
    }
    private func closeCodeJoin() { codeJoinWorkspace?.invalidate(); codeJoinRoute = nil; opensLinkAfterCode = false }
    private func codeJoinDismissed() {
        let membership = joinMembershipToOpen ?? codeJoinWorkspace?.member
        let principal = codeJoinWorkspace?.record?.principal
        let client = codeJoinWorkspace?.client
        joinMembershipToOpen = nil; codeJoinWorkspace?.invalidate(); codeJoinWorkspace = nil
        if opensLinkAfterCode { opensLinkAfterCode = false; openJoin(); return }
        openJoinedSchool(membership, principal: principal, client: client)
    }

    /// After joining: reload the account with the same identity, then open the school joined.
    private func openJoinedSchool(_ membership: SchoolMembership?, principal: SchoolJoinPrincipal?, client: SchoolJoinClient?) {
        guard let membership, let principal, let client, identity.isAuthenticated, let workspace else { return }
        Task {
            guard (try? await client.principal()) == principal, identity.isAuthenticated else { return }
            await workspace.loadAccount()
            guard (try? await client.principal()) == principal, identity.isAuthenticated,
                  let current = workspace.person?.memberships.first(where: {
                      $0.schoolId == membership.schoolId && $0.membershipId == membership.membershipId
                  }) else { return }
            await workspace.selectSchool(current)
            if workspace.membership?.membershipId == current.membershipId { selectedHomeTab = .session }
        }
    }

    // MARK: Invitations

    private var canManageInvitations: Bool {
        configuration != nil && workspace?.school?.status == "ACTIVE"
            && (workspace?.membership?.roles.contains("ADMIN") == true || workspace?.membership?.roles.contains("INSTRUCTOR") == true)
    }

    private var inviteAction: (() -> Void)? {
        canManageInvitations ? { openInvitations(creation: true) } : nil
    }

    private func openInvitations(creation: Bool) {
        guard canManageInvitations, let configuration, let person = workspace?.person,
              let membership = workspace?.membership else { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch,
            apiBaseURL: configuration.apiBaseURL.absoluteString)
        let model = SchoolInvitationWorkspace(scope: scope, roles: membership.roles,
            api: SchoolInvitationClient(baseURL: configuration.apiBaseURL, tokenSource: identity))
        invitations = model
        if creation { inviteRoute = SchoolWorkspaceSheet(model: model) }
        else { invitationsRoute = SchoolWorkspaceSheet(model: model) }
    }

    private func closeInvitations() {
        invitations?.invalidate()
        invitationsRoute = nil; inviteRoute = nil
    }

    private func invitationsDismissed() {
        let invited = invitations?.successMessage != nil
        invitations?.invalidate(); invitations = nil
        // L’élève invité apparaît dans la liste après son acceptation ; on relit la liste.
        if invited, identity.isAuthenticated, workspace?.school?.status == "ACTIVE" {
            Task { await workspace?.searchLearners(workspace?.searchText ?? "") }
        }
    }

    // MARK: Profil et accueil

    private var onboardingOfferKey: String {
        "\(workspace?.membership?.membershipId.uuidString ?? ""):\(workspace?.membership?.accessEpoch ?? 0):\(workspace?.membership?.roles.joined(separator: ",") ?? ""):\(workspace?.school?.status ?? ""):\(workspace?.learners.isEmpty == false)"
    }

    /// First access: open the guided welcome once when the school says it is not finished.
    /// Staff with the ADMIN role only are not forced into it.
    private func offerOnboardingIfNeeded() async {
        staffOnboardingToResume = nil
        guard identity.isAuthenticated, let configuration, let person = workspace?.person,
              let membership = workspace?.membership,
              membership.roles.contains("LEARNER") || membership.roles.contains("INSTRUCTOR") else { return }
        let isLearner = membership.roles.contains("LEARNER")
        if isLearner && workspace?.learners.isEmpty != false { return }
        let kind: SchoolOnboardingKind = isLearner ? .student : .staff
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: configuration.apiBaseURL.absoluteString)
        let api = SchoolProfileClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
        guard await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: kind),
              !Task.isCancelled, identity.isAuthenticated,
              workspace?.person?.personId == person.personId,
              workspace?.membership?.membershipId == membership.membershipId,
              workspace?.membership?.accessEpoch == membership.accessEpoch else { return }
        if !isLearner { staffOnboardingToResume = membership.membershipId }
        guard !offeredOnboarding.contains(membership.membershipId),
              !SchoolOnboardingDeferral.isDeferred(membership.membershipId), !presentsSheet else { return }
        offeredOnboarding.insert(membership.membershipId)
        // Une feuille ouverte ailleurs (leçon, démarrage) ferait perdre celle-ci sans un mot : on attend qu’elle se ferme.
        guard await SchoolPresentationIdle.wait(isPresenting: { uikitIsPresenting }),
              !Task.isCancelled, identity.isAuthenticated,
              workspace?.person?.personId == person.personId,
              workspace?.membership?.membershipId == membership.membershipId,
              workspace?.membership?.accessEpoch == membership.accessEpoch,
              workspace?.membership?.roles == membership.roles, !presentsSheet else {
            offeredOnboarding.remove(membership.membershipId)
            return
        }
        // Offered once: whatever the answer (« Plus tard », closing), not again for seven days.
        SchoolOnboardingDeferral.record(membership.membershipId)
        openOnboarding()
    }

    /// Vrai quand un contrôleur modal (feuille SwiftUI, dialogue) est déjà présenté depuis la racine de la scène.
    private var uikitIsPresenting: Bool {
        presenter?.view.window?.rootViewController?.presentedViewController != nil
    }

    private var profileAction: ((SchoolLearner) -> Void)? {
        guard configuration != nil, workspace?.membership != nil else { return nil }
        return { learner in openProfile(learner) }
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
        profileWorkspace = model; profileRoute = SchoolWorkspaceSheet(model: model)
    }
    private func openOnboarding() {
        guard let model = makeProfileWorkspace(onboardingOnly: true) else { return }
        onboardingWorkspaceID = model.id
        profileWorkspace = model; profileRoute = SchoolWorkspaceSheet(model: model)
    }
    private func closeProfile() { profileWorkspace?.invalidate(); profileRoute = nil }
    private func profileDismissed() {
        if onboardingWorkspaceID != nil, profileWorkspace?.onboarding?.status == "COMPLETED" {
            staffOnboardingToResume = nil
        }
        // Le dossier ne se relit que si le profil a changé : la relecture vide un instant la liste des formations
        // et fait disparaître l’écran de formation ouvert derrière.
        let changed = profileWorkspace?.successMessage != nil || onboardingWorkspaceID != nil
        profileWorkspace?.invalidate(); profileWorkspace = nil; onboardingWorkspaceID = nil
        if changed, identity.isAuthenticated, workspace?.selectedLearnerID != nil {
            Task { await workspace?.loadSelectedLearner() }
        }
    }

    // MARK: Clients de l’accueil

    private var homeAgendaClient: SchoolAgendaClient? { configuration == nil ? nil : clients?.agenda }
    private var homeTrainingClient: SchoolTrainingClient? { configuration == nil ? nil : clients?.training }


    // MARK: Connexion

    private var signInLanding: some View {
        SchoolSignInLanding(isConfigured: configuration != nil, isWorking: identity.isWorking,
            errorMessage: identity.errorMessage, canPresent: presenter != nil,
            signIn: { joinsByCodeAfterSignIn = false; signIn() },
            joinWithCode: { joinsByCodeAfterSignIn = true; signIn() })
    }

    @ViewBuilder
    private func accountLanding(_ workspace: SchoolWorkspace) -> some View {
        if workspace.identityNotLinked, let joinByCodeAction {
            // A new account belongs to no school yet: the code received from the instructor is the way in.
            SchoolWithoutSchoolView(joinSchool: joinByCodeAction)
        } else if let error = workspace.accountError {
            // Same error anatomy as every screen: the notice carries « Réessayer »;
            // an expired session needs a new sign-in, which is the one dominant action.
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if workspace.requiresAuthentication {
                        SchoolErrorNotice(message: error)
                        Button("Se reconnecter") {
                            workspace.reset()
                            Task {
                                await identity.signOut()
                                signIn()
                            }
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                    } else {
                        SchoolErrorNotice(message: error, retry: { Task { await workspace.loadAccount() } })
                    }
                }
                .drivyPageContent(maxWidth: DrivyLayout.narrowColumn)
            }
            .background(DrivyTheme.surface)
        } else {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                DrivySkeletonRow(leading: .avatar, lines: 3)
                DrivySkeletonRows(count: 3)
            }
                .drivySkeleton("Chargement du compte…")
                .drivyPageContent(maxWidth: DrivyLayout.formColumn)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(DrivyTheme.canvas)
        }
    }

    private func signIn() {
        guard let presenter else { return }
        Task { await identity.signIn(presenting: presenter) }
    }

    private func signOut() {
        captureController.setScope(nil)
        pendingJoinLink = nil
        joinsByCodeAfterSignIn = false
        closeAll()
        workspace?.reset()
        showsAccount = false
        Task { await identity.signOut() }
    }

    private func closeAll() {
        staffOnboardingToResume = nil
        closeJoin(); closeCodeJoin(); closeInvitations(); closeProfile()
    }

    // MARK: Portée

    private var isCheckingSchoolAccess: Bool {
        workspace?.isLoadingAccount == true || workspace?.isLoadingSchool == true
    }

    private func verifyPresentedScopes() {
        updateCaptureScope()
        let person = workspace?.person, membership = workspace?.membership
        func current(_ scope: SchoolCommandScope) -> Bool {
            scope.personID == person?.personId && scope.schoolID == membership?.schoolId
                && scope.membershipID == membership?.membershipId && scope.accessEpoch == membership?.accessEpoch
        }
        if let model = profileWorkspace, !current(model.scope) { closeProfile() }
        if let model = invitations, !canManageInvitations || !current(model.scope) { closeInvitations() }
    }

    private func updateCaptureScope() {
        guard identity.isAuthenticated, workspace?.school?.status != "ARCHIVED", let configuration, let workspace else {
            captureController.setScope(nil)
            return
        }
        guard let person = workspace.person, let membership = workspace.membership else {
            // Reloading, offline or choosing a school: an ongoing trip keeps recording. Only a
            // refusal from the school (expired session, withdrawn access) closes its scope;
            // another account or school replaces it as soon as it is known.
            if workspace.accessRevoked { captureController.setScope(nil) }
            return
        }
        // La recharge conserve la même portée. Changer d'école, de compte ou
        // d'epoch ferme immédiatement la source de l'ancienne séance.
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch,
            apiBaseURL: configuration.apiBaseURL.absoluteString)
        captureController.setScope(scope)
        if let client = homeAgendaClient?.captureClient {
            Task { await captureController.resumePendingSynchronizations(client: client, scope: scope) }
        }
    }
}

/// Attend qu’aucune présentation ne soit à l’écran avant d’en ouvrir une autre depuis la racine.
enum SchoolPresentationIdle {
    /// `true` dès que rien n’est présenté ; `false` si l’attente est annulée ou dépasse `attempts` pauses.
    @MainActor
    static func wait(isPresenting: () -> Bool, attempts: Int = 30, pause: Duration = .seconds(1)) async -> Bool {
        var remaining = attempts
        while isPresenting() {
            guard remaining > 0, !Task.isCancelled else { return false }
            remaining -= 1
            do { try await Task.sleep(for: pause) } catch { return false }
        }
        return !Task.isCancelled
    }
}

/// The guided welcome is offered at most once a week per membership, across launches.
/// Only the membership identifier and a date are kept, in the app's own defaults.
enum SchoolOnboardingDeferral {
    static let interval: TimeInterval = 7 * 86_400
    private static func key(_ membershipID: UUID) -> String { "drivy.onboarding.offered.\(membershipID.uuidString.lowercased())" }

    static func isDeferred(_ membershipID: UUID, now: Date = Date(), defaults: UserDefaults = .standard) -> Bool {
        guard let offered = defaults.object(forKey: key(membershipID)) as? Date else { return false }
        return now.timeIntervalSince(offered) < interval && offered <= now
    }

    static func record(_ membershipID: UUID, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: key(membershipID))
    }
}

/// Le compte, en feuille : celui de l’élève, ou d’un compte sans école. Le moniteur et l’administration
/// le trouvent dans l’onglet Profil. Peu de lignes, chacune une action ; la gestion de l’école ouvre le portail web.
struct SchoolAccountView: View {
    let isAuthenticated: Bool
    let workspace: SchoolWorkspace?
    let manageURL: URL?
    let openProfile: (() -> Void)?
    let openInvitations: (() -> Void)?
    let openJoinSchool: (() -> Void)?
    let signOut: () -> Void
    var resumeOnboarding: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var actions: SchoolAccountActions {
        SchoolAccountActions(manageURL: manageURL, openProfile: openProfile, openInvitations: openInvitations,
            openJoinSchool: openJoinSchool, signOut: signOut, resumeOnboarding: resumeOnboarding)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    SchoolAccountHeading(workspace: workspace, isAuthenticated: isAuthenticated)
                    if isAuthenticated {
                        // Une seule liste : les séparateurs suivent le même rythme d’un bout à l’autre.
                        DrivyRowGroup {
                            actions.rows(workspace: workspace, openURL: openURL, afterChangingSchool: { dismiss() })
                        }
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
