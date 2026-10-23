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

/// La feuille de profil : l’accueil guidé, « Mon profil » (compte Drivy et, pour un élève, son dossier) ou le dossier
/// d’un autre élève. Le modèle du dossier voyage avec la feuille ; « Mon profil » sans dossier n’en a pas.
private struct ProfileSheet: Identifiable {
    let id = UUID()
    let model: SchoolProfileWorkspace?
}

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
    @State private var profileRoute: ProfileSheet?
    @State private var joinWorkspace: SchoolJoinWorkspace?
    @State private var joinRoute: SchoolWorkspaceSheet<SchoolJoinWorkspace>?
    @State private var codeJoinWorkspace: SchoolCodeJoinWorkspace?
    @State private var codeJoinRoute: SchoolWorkspaceSheet<SchoolCodeJoinWorkspace>?
    /// « J’ai un lien d’invitation » closes the code sheet, then opens the link one.
    @State private var opensLinkAfterCode = false
    @State private var joinMembershipToOpen: SchoolMembership?
    @State private var pendingJoinLink: String?
    @State private var joinsByCodeAfterSignIn = false
    /// « J’ai un code » avant connexion, puis ce qu’il reste à faire une fois connecté.
    @State private var accessWorkspace: SchoolAccessWorkspace?
    @State private var accessRoute: SchoolWorkspaceSheet<SchoolAccessWorkspace>?
    /// La connexion conserve la priorité de son code jusqu’à l’ouverture de l’écran suivant.
    @State private var isContinuingAccess = false
    @State private var openingWorkspace: SchoolOpeningWorkspace?
    @State private var openingRoute: SchoolWorkspaceSheet<SchoolOpeningWorkspace>?
    @State private var selectedHomeTab: SchoolHomeTab = .session
    @State private var captureController = SchoolCaptureSessionController()
    @Environment(\.scenePhase) private var scenePhase
    /// The profile sheet shows the guided welcome only when it was opened for it.
    @State private var onboardingWorkspaceID: UUID?
    /// Memberships already offered the welcome during this launch: « Plus tard » never loops.
    /// Across launches, SchoolOnboardingDeferral keeps the offer away for seven days.
    @State private var offeredOnboarding: Set<UUID> = []
    /// Confirmé par la lecture serveur, même si l’offre automatique a été reportée.
    @State private var onboardingToResume: UUID?

    private var presentsSheet: Bool {
        joinRoute != nil || codeJoinRoute != nil || invitationsRoute != nil || inviteRoute != nil || profileRoute != nil
            || accessRoute != nil || openingRoute != nil
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
                    account: accountActions, inviteLearner: inviteAction, openProfile: profileAction,
                    makeLearnerProfile: { makeProfileWorkspace(learner: $0) }, agendaClient: homeAgendaClient,
                    trainingClient: homeTrainingClient, captureController: captureController,
                    messagingEntry: homeMessagingEntry,
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
            } else if pendingJoinLink != nil || joinsByCodeAfterSignIn {
                let byCode = joinsByCodeAfterSignIn
                joinsByCodeAfterSignIn = false
                openJoinWhenIdle(byCode: byCode)
            }
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
        .onChange(of: workspace?.person?.displayName) { _, name in
            openingWorkspace?.prefillAccountDisplayName(name)
        }
        .onChange(of: identity.suggestedDisplayName) { _, name in
            openingWorkspace?.prefillAccountDisplayName(workspace?.person?.displayName ?? name)
        }
        .onChange(of: workspace?.isLoadingAccount) { _, loading in
            if loading == false { verifyPresentedScopes() }
        }
        .onChange(of: workspace?.isLoadingSchool) { _, loading in
            if loading == false && workspace?.isLoadingAccount != true { verifyPresentedScopes() }
        }
        .onChange(of: workspace?.school?.status) { _, status in
            if let status, status != "ACTIVE" {
                captureController.setScope(nil)
                onboardingToResume = nil
                closeProfile(); closeInvitations()
            }
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
                    .frame(minHeight: DrivyLayout.tapTarget)
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
                openProfile: followUp(.profile, when: canOpenMyProfile),
                openInvitations: followUp(.invitations, when: canManageInvitations),
                openJoinSchool: followUp(.join, when: canJoinSchool),
                signOut: signOut, resumeOnboarding: followUp(.onboarding, when: canResumeOnboarding))
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
                }, useLink: { opensLinkAfterCode = true; codeJoinRoute = nil },
                openSchoolWithCode: { _ in codeJoinRoute = nil })
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
            profileContent(route)
                .disabled(isCheckingSchoolAccess)
                .overlay { accessCheckOverlay }
                .onChange(of: route.model?.accessFailure) { _, failure in
                    // Seul un retrait d’accès ferme la feuille. Un dossier introuvable (archivé entre-temps, service
                    // de l’école plus ancien que l’app) n’en est pas un : la feuille reste sur son message, avec « Fermer ».
                    if failure == .unauthorized || failure == .forbidden {
                        closeProfile(); Task { await workspace?.loadAccount() }
                    }
                }
        }
    }

    private var accessLayer: some View {
        profileLayer
            .sheet(item: $accessRoute, onDismiss: accessDismissed) { route in
                SchoolAccessCodeView(model: route.model)
                    .onChange(of: route.model.isFinished) { _, finished in if finished { accessRoute = nil } }
            }
            .sheet(item: $openingRoute, onDismiss: openingDismissed) { route in
                SchoolOpeningView(model: route.model, openSchool: { _ in openingRoute = nil })
            }
    }

    private var presentations: some View { accessLayer }

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

    @ViewBuilder private func profileContent(_ route: ProfileSheet) -> some View {
        if let model = route.model, model.id == onboardingWorkspaceID {
            SchoolOnboardingView(model: model, trainings: workspace?.trainings ?? [])
        } else if let model = route.model, !model.isOwnProfile {
            SchoolProfileView(model: model)
        } else if let workspace {
            SchoolMyProfileView(workspace: workspace, dossier: route.model)
        }
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
        case .profile: openMyProfile()
        case .onboarding: if canResumeOnboarding && !presentsSheet { openOnboarding() }
        }
    }

    /// Les actions du compte, pour l’onglet Profil du moniteur et de l’administration.
    private var accountActions: SchoolAccountActions {
        SchoolAccountActions(manageURL: manageURL,
            openProfile: followUp(.profile, when: canOpenMyProfile),
            openInvitations: followUp(.invitations, when: canManageInvitations),
            openJoinSchool: followUp(.join, when: canJoinSchool),
            signOut: signOut, resumeOnboarding: followUp(.onboarding, when: canResumeOnboarding),
            tripInProgress: tripInProgress)
    }

    /// Un trajet GPS tourne (ou attend encore la confirmation de l’école) : changer d’école fermerait sa portée.
    private var tripInProgress: Bool { captureController.captureID != nil && captureController.state != .saved }

    /// Rejoindre une école ouvre l’école rejointe : comme « Changer d’école », le geste se retire pendant un trajet.
    private var canJoinSchool: Bool { configuration != nil && identity.isAuthenticated && !tripInProgress }

    private var canResumeOnboarding: Bool {
        guard configuration != nil, identity.isAuthenticated, workspace?.school?.status == "ACTIVE",
              let membership = workspace?.membership else { return false }
        // L’élève comme le moniteur : un accueil laissé en route se reprend depuis Profil, sans attendre sept jours.
        return SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: workspace?.school?.status, roles: membership.roles)
            && onboardingToResume == membership.membershipId
    }

    /// La gestion de l’école est réservée à l’administration, sur le portail web.
    private var manageURL: URL? {
        guard let configuration, let membership = workspace?.membership, membership.roles.contains("ADMIN") else { return nil }
        guard workspace?.school?.status != "ARCHIVED" else { return nil }
        return configuration.managementURL(schoolID: membership.schoolId, preparation: workspace?.school?.status == "DRAFT")
    }

    /// « Mon profil » existe pour tout compte Drivy connecté, élève, moniteur, administration ou sans école.
    private var canOpenMyProfile: Bool { identity.isAuthenticated && workspace?.person != nil }

    private var ownProfileLearner: SchoolLearner? {
        guard workspace?.school?.status == "ACTIVE", let person = workspace?.person,
              workspace?.membership?.roles.contains("LEARNER") == true else { return nil }
        guard let own = workspace?.ownLearner, own.personId == person.personId else { return nil }
        return own
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
            if showsAccount { follow(.join) } else { openJoinWhenIdle(byCode: false) }
        }
    }
    /// Connexion ou lien reçu : une présentation déjà à l’écran (page du fournisseur d’identité qui se referme,
    /// leçon, planification, choix d’école) ferait perdre cette feuille sans un mot. Elle attend sa fermeture ;
    /// au-delà de l’attente, le lien reste retenu pour « Rejoindre une école ».
    private func openJoinWhenIdle(byCode: Bool) {
        Task {
            guard await SchoolPresentationIdle.wait(isPresenting: { uikitIsPresenting }),
                  identity.isAuthenticated, !presentsSheet else { return }
            if pendingJoinLink != nil { openJoin() } else if byCode { openCodeJoin() }
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

    // MARK: J’ai un code (avant connexion)

    private func openAccessCode(link: String? = nil) {
        guard let configuration, !identity.isAuthenticated, accessRoute == nil else { return }
        identity.clearError()
        let model = SchoolAccessWorkspace(client: SchoolAccountClient(configuration: configuration), identity: identity, link: link)
        accessWorkspace = model; accessRoute = SchoolWorkspaceSheet(model: model)
    }
    private func accessDismissed() {
        let outcome = accessWorkspace?.outcome
        accessWorkspace?.invalidate(); accessWorkspace = nil
        if let outcome { continueAccess(outcome) }
    }
    /// Connecté avec le code gardé : rejoindre l’école (élève), ouvrir l’école (code d’ouverture), ou relire l’invitation reçue.
    private func continueAccess(_ outcome: SchoolAccessOutcome) {
        isContinuingAccess = true
        Task {
            defer { isContinuingAccess = false }
            guard await SchoolPresentationIdle.wait(isPresenting: { uikitIsPresenting }),
                  identity.isAuthenticated, !presentsSheet, let configuration else { return }
            switch (outcome.kind, outcome.input) {
            case (.schoolOpening, _):
                let model = SchoolOpeningWorkspace(client: SchoolOpeningClient(configuration: configuration, tokenSource: identity),
                    code: outcome.input.secret,
                    displayName: SchoolOpeningWorkspace.prefilledDisplayName(accountCreationName: outcome.displayName,
                        knownPersonName: workspace?.person?.displayName, identityDisplayName: identity.suggestedDisplayName), email: outcome.email)
                openingWorkspace = model; openingRoute = SchoolWorkspaceSheet(model: model)
            case (.learnerInvitation, .code(let code)):
                openCodeJoin(code: code)
            case (.emailInvitation, .invitationLink(let token)):
                var parts = URLComponents()
                parts.scheme = configuration.apiBaseURL.scheme; parts.host = configuration.apiBaseURL.host; parts.port = configuration.apiBaseURL.port
                parts.path = "/app/invitation"; parts.percentEncodedFragment = "token=\(token)"
                pendingJoinLink = parts.string; openJoin()
            default:
                break
            }
        }
    }
    private func closeOpening() { openingRoute = nil }
    private func openingDismissed() {
        let created = openingWorkspace?.receipt != nil
        openingWorkspace = nil
        if created { Task { await workspace?.loadAccount() } }
    }

    // MARK: Rejoindre avec un code

    private var joinByCodeAction: (() -> Void)? {
        configuration != nil && identity.isAuthenticated ? { openCodeJoin() } : nil
    }
    private func openCodeJoin(code: String? = nil) {
        guard identity.isAuthenticated, let configuration else { return }
        if presentsSheet {
            // Une route restée posée sans feuille à l’écran (présentation écartée par une autre) ne condamne pas
            // le bouton : la même demande est présentée de nouveau.
            if codeJoinRoute != nil, !uikitIsPresenting, let model = codeJoinWorkspace {
                codeJoinRoute = SchoolWorkspaceSheet(model: model)
            }
            return
        }
        codeJoinWorkspace?.invalidate()
        let model = SchoolCodeJoinWorkspace(client: SchoolJoinClient(configuration: configuration, tokenSource: identity),
                                            accessClient: SchoolAccountClient(configuration: configuration))
        // Code saisi avant la connexion : la feuille le lit aussitôt, sans le redemander.
        if let code { model.code = code }
        codeJoinWorkspace = model; codeJoinRoute = SchoolWorkspaceSheet(model: model)
    }
    private func closeCodeJoin() { codeJoinWorkspace?.invalidate(); codeJoinRoute = nil; opensLinkAfterCode = false }
    private func codeJoinDismissed() {
        let membership = joinMembershipToOpen ?? codeJoinWorkspace?.member
        let principal = codeJoinWorkspace?.record?.principal
        let client = codeJoinWorkspace?.client
        let openingCode = codeJoinWorkspace?.openingCode
        joinMembershipToOpen = nil; codeJoinWorkspace?.invalidate(); codeJoinWorkspace = nil
        if opensLinkAfterCode { opensLinkAfterCode = false; openJoin(); return }
        if let openingCode {
            // Connecté, avec un code d’ouverture : le formulaire de l’école suit, au nom du compte.
            continueAccess(SchoolAccessOutcome(input: .code(openingCode), kind: .schoolOpening,
                                               displayName: workspace?.person?.displayName, email: nil))
            return
        }
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
            // Adhésion arrivée pendant un trajet (lien ouvert, demande restée en attente) : l’école du trajet reste
            // ouverte, l’école rejointe se choisit ensuite par « Changer d’école ».
            guard !tripInProgress else { return }
            // Compte neuf : la lecture du compte a déjà ouvert son unique école, elle n’est pas lue une seconde fois.
            if workspace.membership != current || workspace.school == nil { await workspace.selectSchool(current) }
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
        // Un code créé ne laisse aucun message de succès : c’est l’écriture confirmée qui compte.
        let invited = invitations?.didConfirmWrite == true
        invitations?.invalidate(); invitations = nil
        // L’élève invité apparaît dans la liste après son acceptation ; la liste est relue sans rien effacer.
        if invited, identity.isAuthenticated, workspace?.school?.status == "ACTIVE" {
            Task { await workspace?.refreshLearners(minimumInterval: 0) }
        }
    }

    // MARK: Profil et accueil

    private var onboardingOfferKey: String {
        // La liste d’élèves ne compte que pour un compte élève (son dossier) : une recherche du moniteur qui la vide
        // ne relance pas la lecture de son accueil.
        let kind = SchoolEntryDestination.personalOnboardingKind(schoolStatus: workspace?.school?.status,
            roles: workspace?.membership?.roles ?? [])
        let ownDossier = kind == .student ? "\(ownProfileLearner?.id.uuidString ?? "")" : ""
        return "\(workspace?.membership?.membershipId.uuidString ?? ""):\(workspace?.membership?.accessEpoch ?? 0):\(workspace?.membership?.roles.joined(separator: ",") ?? ""):\(workspace?.school?.status ?? ""):\(ownDossier):\(isContinuingAccess)"
    }

    /// First access: open the guided welcome once when the school says it is not finished.
    /// Staff with the ADMIN role only are not forced into it.
    private func offerOnboardingIfNeeded() async {
        // « Reprendre l’accueil » reste affiché pendant la relecture : il ne s’éteint que pour une autre adhésion,
        // ou quand l’école ne le dit plus à terminer.
        if onboardingToResume != workspace?.membership?.membershipId { onboardingToResume = nil }
        guard !isContinuingAccess, identity.isAuthenticated, let configuration, let person = workspace?.person,
              let membership = workspace?.membership,
              let kind = SchoolEntryDestination.personalOnboardingKind(schoolStatus: workspace?.school?.status, roles: membership.roles) else {
            onboardingToResume = nil
            return
        }
        if kind == .student && ownProfileLearner == nil { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: configuration.apiBaseURL.absoluteString)
        let api = SchoolProfileClient(baseURL: configuration.apiBaseURL, tokenSource: identity)
        let state = await SchoolOnboardingPrompt.pendingState(api: api, scope: scope, kind: kind)
        guard !Task.isCancelled, !isContinuingAccess, identity.isAuthenticated,
              SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: workspace?.school?.status, roles: membership.roles),
              workspace?.person?.personId == person.personId,
              workspace?.membership?.membershipId == membership.membershipId,
              workspace?.membership?.accessEpoch == membership.accessEpoch else { return }
        // Une panne ne dit rien : « Reprendre l’accueil » déjà affiché reste, rien ne s’ouvre.
        guard let pending = state else { return }
        guard pending else {
            onboardingToResume = nil
            return
        }
        onboardingToResume = membership.membershipId
        guard !offeredOnboarding.contains(membership.membershipId),
              !SchoolOnboardingDeferral.isDeferred(membership.membershipId), !presentsSheet else { return }
        offeredOnboarding.insert(membership.membershipId)
        // Une feuille ouverte ailleurs (leçon, démarrage) ferait perdre celle-ci sans un mot : on attend qu’elle se ferme.
        guard await SchoolPresentationIdle.wait(isPresenting: { uikitIsPresenting }),
              !Task.isCancelled, !isContinuingAccess, identity.isAuthenticated,
              SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: workspace?.school?.status, roles: membership.roles),
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
        let welcomeKind = SchoolEntryDestination.personalOnboardingKind(schoolStatus: workspace?.school?.status, roles: membership.roles)
        if targetLearner == nil, onboardingOnly, welcomeKind == .student {
            targetLearner = ownProfileLearner
        }
        let isOwn = targetLearner?.personId == person.personId && membership.roles.contains("LEARNER")
        let kind: SchoolOnboardingKind?
        if isOwn { kind = .student }
        else if onboardingOnly { kind = welcomeKind }
        else { kind = nil }
        return SchoolProfileWorkspace(scope: scope, roles: membership.roles, learnerID: targetLearner?.id,
            isOwnProfile: isOwn, onboardingKind: kind,
            api: SchoolProfileClient(baseURL: configuration.apiBaseURL, tokenSource: identity))
    }
    private func openProfile(_ learner: SchoolLearner) {
        guard let model = makeProfileWorkspace(learner: learner) else { return }
        onboardingWorkspaceID = nil
        profileWorkspace = model; profileRoute = ProfileSheet(model: model)
    }
    /// Le compte Drivy, et le dossier de l’élève dans l’école ouverte quand l’école l’a ouvert. Aucun dossier n’est
    /// créé ni lu pour un compte qui n’en a pas : la page ne montre alors que le compte.
    private func openMyProfile() {
        guard canOpenMyProfile, !presentsSheet else { return }
        let model = ownProfileLearner.flatMap { makeProfileWorkspace(learner: $0) }
        onboardingWorkspaceID = nil
        profileWorkspace = model; profileRoute = ProfileSheet(model: model)
    }
    private func openOnboarding() {
        guard SchoolEntryDestination.allowsPersonalOnboarding(schoolStatus: workspace?.school?.status,
            roles: workspace?.membership?.roles ?? []) else { return }
        guard let model = makeProfileWorkspace(onboardingOnly: true) else { return }
        onboardingWorkspaceID = model.id
        profileWorkspace = model; profileRoute = ProfileSheet(model: model)
    }
    private func closeProfile() { profileWorkspace?.invalidate(); profileRoute = nil }
    private func profileDismissed() {
        if onboardingWorkspaceID != nil, profileWorkspace?.onboarding?.status == "COMPLETED" {
            onboardingToResume = nil
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

    private var homeMessagingEntry: SchoolMessagingEntry? {
        guard SchoolMessagingDevelopment.permitted(arguments: ProcessInfo.processInfo.arguments,
                  schoolIsActive: workspace?.school?.status == "ACTIVE"),
              let configuration, let clients, let workspace, let person = workspace.person,
              let membership = workspace.membership else { return nil }
        let baseURL = configuration.apiBaseURL
        let identity = identity
        let scope = MessagingScope(accountID: person.personId, schoolID: membership.schoolId,
            accessEpoch: membership.accessEpoch, apiBaseURL: baseURL.absoluteString)
        return MessagingDevelopmentEntry.make(scope: scope, baseURL: baseURL,
            tokenSource: identity, transport: clients.messagingTransport,
            photoLoader: { [weak workspace] id in
                await workspace?.loadPhoto(for: id)
                return await workspace?.photo(for: id)
            }, currentScope: {
                guard identity.isAuthenticated, workspace.school?.status == "ACTIVE",
                      let person = workspace.person, let membership = workspace.membership else { return nil }
                return MessagingScope(accountID: person.personId, schoolID: membership.schoolId,
                    accessEpoch: membership.accessEpoch, apiBaseURL: baseURL.absoluteString)
            })
    }

    private var homeAgendaClient: SchoolAgendaClient? { configuration == nil ? nil : clients?.agenda }
    private var homeTrainingClient: SchoolTrainingClient? { configuration == nil ? nil : clients?.training }


    // MARK: Connexion

    private var signInLanding: some View {
        SchoolSignInLanding(isConfigured: configuration != nil, isWorking: identity.isWorking && accessRoute == nil,
            errorMessage: accessRoute == nil ? identity.errorMessage : nil,
            signIn: { email, password in
                joinsByCodeAfterSignIn = false
                Task { await identity.signIn(email: email, password: password) }
            },
            joinWithCode: { openAccessCode() },
            clearError: { identity.clearError() })
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
                                // La page de connexion de l’app reprend la main.
                                await identity.signOut()
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
        onboardingToResume = nil
        closeJoin(); closeCodeJoin(); closeInvitations(); closeProfile(); closeOpening()
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
        guard identity.isAuthenticated, workspace?.school?.status != "ARCHIVED", workspace?.school?.status != "DRAFT", let configuration, let workspace else {
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
        // La recharge conserve la même portée. Changer d'école ou de compte, ou perdre le rôle moniteur,
        // ferme immédiatement la source de l'ancienne séance. Une époque plus récente de la même adhésion
        // active, rôle moniteur conservé, laisse le trajet en cours finir sous sa portée (A5-01).
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch,
            apiBaseURL: configuration.apiBaseURL.absoluteString)
        captureController.setScope(scope, retainsInstructorRole: membership.roles.contains("INSTRUCTOR"))
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
                ToolbarItem(placement: .cancellationAction) {
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
