import SwiftUI
import UIKit

/// La donnée qui ouvre la feuille est aussi celle que reçoit son contenu.
/// Une intention ne peut donc pas présenter une feuille sans son modèle initial.
private struct SchoolWorkspaceSheet<Model: AnyObject>: Identifiable {
    let id = UUID()
    let model: Model
}

/// Ce que le compte ouvre une fois sa feuille fermée : une seule feuille à la fois.
private enum AccountFollowUp { case join, invitations, profile }

struct SchoolRootView: View {
    let configuration: AppConfiguration?
    @Bindable var identity: IdentitySession
    let workspace: SchoolWorkspace?
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
    @State private var selectedHomeTab: SchoolHomeTab = .session
    @State private var captureController = SchoolCaptureSessionController()
    /// The profile sheet shows the guided welcome only when it was opened for it.
    @State private var onboardingWorkspaceID: UUID?
    /// Memberships already offered the welcome during this launch: « Plus tard » never loops.
    @State private var offeredOnboarding: Set<UUID> = []

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
                    inviteLearner: inviteAction, openProfile: profileAction, agendaClient: homeAgendaClient,
                    trainingClient: homeTrainingClient, captureController: captureController,
                    joinSchool: joinByCodeAction, selectedTab: $selectedHomeTab)
            } else {
                NavigationStack {
                    accountLanding(workspace)
                        .navigationTitle("Drivy")
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
        .onOpenURL { receiveInvitation($0) }
    }

    // MARK: Feuilles

    private var accountLayer: some View {
        observedContent.sheet(isPresented: $showsAccount, onDismiss: accountDismissed) {
            SchoolAccountView(identity: identity, workspace: workspace, manageURL: manageURL,
                openProfile: followUp(.profile, when: ownProfileLearner != nil),
                openInvitations: followUp(.invitations, when: canManageInvitations),
                openJoinSchool: followUp(.join, when: configuration != nil && identity.isAuthenticated),
                signOut: signOut)
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
            DrivyTheme.canvas.ignoresSafeArea().overlay { ProgressView() }
        }
    }

    // MARK: Compte

    private func follow(_ action: AccountFollowUp) { afterAccount = action; showsAccount = false }
    private func followUp(_ action: AccountFollowUp, when enabled: Bool) -> (() -> Void)? {
        guard enabled else { return nil }
        return { follow(action) }
    }

    private func accountDismissed() {
        guard let action = afterAccount else { return }
        afterAccount = nil
        switch action {
        case .join: openCodeJoin()
        case .invitations: openInvitations(creation: false)
        case .profile: if let learner = ownProfileLearner { openProfile(learner) }
        }
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
        let membership = joinMembershipToOpen
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
        let membership = joinMembershipToOpen
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
        "\(workspace?.membership?.membershipId.uuidString ?? ""):\(workspace?.learners.isEmpty == false)"
    }

    /// First access: open the guided welcome once when the school says it is not finished.
    /// Staff with the ADMIN role only are not forced into it.
    private func offerOnboardingIfNeeded() async {
        guard identity.isAuthenticated, let configuration, let person = workspace?.person,
              let membership = workspace?.membership, !offeredOnboarding.contains(membership.membershipId),
              membership.roles.contains("LEARNER") || membership.roles.contains("INSTRUCTOR"),
              !presentsSheet else { return }
        let isLearner = membership.roles.contains("LEARNER")
        if isLearner && workspace?.learners.isEmpty != false { return }
        offeredOnboarding.insert(membership.membershipId)
        let kind: SchoolOnboardingKind = isLearner ? .student : .staff
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: configuration.apiBaseURL.absoluteString)
        let api = SchoolProfileClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
        guard await SchoolOnboardingPrompt.isPending(api: api, scope: scope, kind: kind),
              workspace?.membership?.membershipId == membership.membershipId, !presentsSheet else { return }
        openOnboarding()
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
        profileWorkspace?.invalidate(); profileWorkspace = nil; onboardingWorkspaceID = nil
        if identity.isAuthenticated, workspace?.selectedLearnerID != nil {
            Task { await workspace?.loadSelectedLearner() }
        }
    }

    // MARK: Clients de l’accueil

    private var homeAgendaClient: SchoolAgendaClient? {
        guard let configuration else { return nil }
        return SchoolAgendaClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
    }

    private var homeTrainingClient: SchoolTrainingClient? {
        guard let configuration else { return nil }
        return SchoolTrainingClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
    }


    // MARK: Connexion

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
                Text("Vos leçons, vos trajets, votre école.")
                    .font(.drivyScreenTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if configuration == nil {
                    DrivyInlineMessage(text: "La connexion n’est pas activée dans cette version.", tone: .neutral)
                        .accessibilityIdentifier("school-not-configured")
                } else if let error = identity.errorMessage {
                    SchoolErrorNotice(message: error)
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if configuration != nil {
                Button(action: signIn) {
                    if identity.isWorking {
                        DrivyBusyLabel(title: "Se connecter", busyTitle: "Connexion…", isBusy: true)
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
        if workspace.identityNotLinked, let joinByCodeAction {
            // A new account belongs to no school yet: the code received from the instructor is the way in.
            SchoolWithoutSchoolView(joinSchool: joinByCodeAction)
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
                        Button("Réessayer") { Task { await workspace.loadAccount() } }
                            .buttonStyle(DrivyPrimaryButtonStyle())
                    }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        closeAll()
        workspace?.reset()
        showsAccount = false
        Task { await identity.signOut() }
    }

    private func closeAll() {
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
}

/// Le compte : peu de lignes, chacune une action. La gestion de l’école ouvre le portail web.
private struct SchoolAccountView: View {
    @Bindable var identity: IdentitySession
    let workspace: SchoolWorkspace?
    let manageURL: URL?
    let openProfile: (() -> Void)?
    let openInvitations: (() -> Void)?
    let openJoinSchool: (() -> Void)?
    let signOut: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppLock.self) private var appLock: AppLock?

    private var hasSeveralSchools: Bool { (workspace?.person?.memberships.count ?? 0) > 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                    accountHeading
                    if identity.isAuthenticated {
                        if openProfile != nil || openInvitations != nil || manageURL != nil {
                            DrivyRowGroup {
                                if let openProfile {
                                    DrivyNavigationRow(title: "Mon profil", symbol: "person.text.rectangle", action: openProfile)
                                        .accessibilityIdentifier("open-my-profile")
                                }
                                if let openInvitations {
                                    DrivyNavigationRow(title: "Invitations", symbol: "envelope", action: openInvitations)
                                        .accessibilityIdentifier("open-school-invitations")
                                }
                                if let manageURL {
                                    DrivyNavigationRow(title: "Gérer l’école", detail: "Sur le web", symbol: "globe",
                                        action: { openURL(manageURL) })
                                        .accessibilityIdentifier("open-school-management")
                                }
                            }
                        }
                        DrivyRowGroup {
                            if let workspace, hasSeveralSchools {
                                DrivyNavigationRow(title: "Changer d’école", detail: workspace.membership?.schoolName,
                                    symbol: "arrow.left.arrow.right", action: {
                                        workspace.leaveSchool()
                                        dismiss()
                                    })
                                    .accessibilityIdentifier("school-change-school")
                            }
                            if let openJoinSchool {
                                DrivyNavigationRow(title: "Rejoindre une école", symbol: "number", action: openJoinSchool)
                                    .accessibilityIdentifier("open-join-school")
                            }
                            if let appLock, let biometry = appLock.biometryName {
                                Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { appLock.setEnabled($0) })) {
                                    Label("Ouvrir avec \(biometry)", systemImage: biometry == "Touch ID" ? "touchid" : "faceid")
                                }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("app-lock-toggle")
                            }
                        }
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
                Text(workspace?.person?.displayName ?? (identity.isAuthenticated ? "Compte connecté" : "Aucun compte connecté"))
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
