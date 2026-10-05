import SwiftUI

private struct SchoolLearnerPage: Hashable {
    let trainingID: UUID
    let section: SchoolTrainingSection
}

/// The dossier's home says who the learner is and how to reach them, then opens lessons and
/// progression as distinct pushed pages, so the native back action always returns here.
/// Personal details stay folded until someone asks for them.
struct SchoolLearnerDossierView: View {
    @Bindable var workspace: SchoolWorkspace
    let openProfile: ((SchoolLearner) -> Void)?
    let makeLearnerProfile: ((SchoolLearner) -> SchoolProfileWorkspace?)?
    let openPlanning: ((SchoolLearner) -> Void)?
    let trainingClient: SchoolTrainingClient?
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    @State private var path: [SchoolLearnerPage] = []
    @State private var profileModel: SchoolProfileWorkspace?
    @State private var editingProfile: SchoolProfileWorkspace?
    @State private var profileScopeKey = ""
    @State private var profileCreationFailed = false
    @State private var showsInformation = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(workspace.selectedLearnerID?.uuidString ?? "")"
    }

    /// The profile read for the learner and rights on screen, never the one of a previous scope.
    private var currentProfile: SchoolProfileWorkspace? {
        profileScopeKey == scopeKey ? profileModel : nil
    }

    /// With a single formation, its name and unusual status sit under the learner's name.
    /// With several, each group of rows carries its own.
    private var soleTraining: SchoolTraining? {
        workspace.trainings.count == 1 && workspace.nextTrainingsCursor == nil ? workspace.trainings.first : nil
    }

    private var unusualSoleTraining: SchoolTraining? {
        guard let training = soleTraining, training.status != "ACTIVE" else { return nil }
        return training
    }

    var body: some View {
        NavigationStack(path: $path) {
            dossier
                .navigationTitle("Dossier")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: SchoolLearnerPage.self) { page in
                    if let learner = workspace.learner, learner.id == workspace.selectedLearnerID, let trainingClient {
                        SchoolTrainingScreen(client: trainingClient, workspace: workspace, learner: learner,
                            trainingID: page.trainingID, section: page.section, showsHeading: true)
                            .navigationTitle(page.section.rawValue)
                            .navigationBarTitleDisplayMode(.inline)
                    } else {
                        ContentUnavailableView("Dossier indisponible", systemImage: "person.crop.circle.badge.exclamationmark")
                    }
                }
        }
        .task(id: scopeKey) { await reload() }
        .sheet(item: $editingProfile, onDismiss: { Task { await reload() } }) { model in
            SchoolProfileView(model: model, loadsOnAppear: false)
        }
        .onChange(of: profileModel?.accessFailure) { _, failure in
            guard let failure else { return }
            editingProfile = nil
            if failure == .unauthorized || failure == .forbidden {
                workspace.rejectCurrentAccess(requiresAuthentication: failure == .unauthorized)
            } else {
                Task { await workspace.loadSelectedLearner() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && editingProfile == nil { Task { await reload() } }
        }
        .onDisappear {
            // Pushing a page or changing tabs keeps the profile. Changing account,
            // rights or selected learner invalidates its in-flight reads and draft.
            if profileScopeKey != scopeKey { profileModel?.invalidate(); editingProfile = nil }
        }
    }

    private var dossier: some View {
        // The page is refreshable and now often shorter than the screen: it keeps the
        // system bounce, without which the pull gesture has nothing to pull.
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                if workspace.isLoadingLearner && workspace.learner == nil {
                    DrivySkeletonRows(count: 3, leading: .avatar).drivySkeleton("Chargement du dossier…")
                }
                if let error = workspace.learnerError {
                    SchoolErrorNotice(message: error, retry: { Task { await reload() } })
                }
                if let learner = workspace.learner, learner.id == workspace.selectedLearnerID {
                    header(learner)
                    pages
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .refreshable { await reload() }
        .accessibilityIdentifier("learner-dossier")
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
    }

    // MARK: - Identity

    /// Visible at once: who, which formation, what is unusual, and the frequent gestures.
    /// Everything shown here comes with the dossier itself, so nothing moves when the profile arrives.
    private func header(_ learner: SchoolLearner) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            // Historic UI-test identifier: it now designates the full name that heads the dossier.
            DrivyLearnerIdentity(name: learner.displayName,
                                 detail: soleTraining.map { "Permis \($0.categoryCode)" }, variant: .page)
                .accessibilityIdentifier("learner-profile-first-name")
            statusBadges(learner)
            SchoolLearnerActions(learner: learner, contact: contact(of: learner), identifierPrefix: "learner-profile")
            information(learner)
        }
    }

    @ViewBuilder private func statusBadges(_ learner: SchoolLearner) -> some View {
        if learner.archivedAt != nil || unusualSoleTraining != nil {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
                : AnyLayout(HStackLayout(spacing: DrivySpacing.xs))
            layout {
                if learner.archivedAt != nil { DrivyStatusBadge(title: "Archivé", symbol: "archivebox") }
                if let training = unusualSoleTraining {
                    DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status))
                }
            }
        }
    }

    /// Once read, the administrative profile is the reference for contacts; before, the dossier's own copy.
    private func contact(of learner: SchoolLearner) -> SchoolLearnerContact {
        if let profile = currentProfile?.profile {
            return SchoolLearnerContact(email: profile.contactEmail, phone: profile.contactPhone)
        }
        return SchoolLearnerContact(email: learner.contactEmail, phone: learner.contactPhone)
    }

    // MARK: - Personal details

    /// A request to check and an error are unusual: they stay visible. The details themselves wait folded.
    @ViewBuilder private func information(_ learner: SchoolLearner) -> some View {
        if makeLearnerProfile == nil {
            recordedContacts(learner)
        } else {
            let model = currentProfile
            if let model, model.pending != nil { verifyButton(model) }
            if let error = model?.errorMessage {
                SchoolErrorNotice(message: error, retry: { Task { await loadProfile() } })
            } else if model == nil && profileCreationFailed {
                SchoolErrorNotice(message: "Les informations de l’élève ne peuvent pas être chargées.",
                    retry: { Task { await loadProfile() } })
            }
            if model?.profile != nil || model?.isLoading == true || (model == nil && !profileCreationFailed) {
                informationDisclosure(model, learner: learner)
            }
        }
    }

    private func informationDisclosure(_ model: SchoolProfileWorkspace?, learner: SchoolLearner) -> some View {
        DisclosureGroup(isExpanded: $showsInformation) {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                if let model, model.profile != nil {
                    SchoolLearnerProfileSummary(model: model, displayedName: learner.displayName)
                    if model.pending == nil { editButton(model) }
                } else {
                    DrivySkeletonRows(count: 2, lines: 1).drivySkeleton("Chargement des informations…")
                }
            }
            .padding(.top, DrivySpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            informationLabel
        }
        .accessibilityIdentifier("learner-profile-details")
    }

    private var informationLabel: some View {
        Text("Informations personnelles")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44, alignment: .leading)
    }

    /// Never dimmed during a silent reread: the form keeps its own fields locked until the answer.
    private func editButton(_ model: SchoolProfileWorkspace) -> some View {
        Button { editingProfile = model } label: {
            Text("Modifier les informations")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("learner-edit-profile")
    }

    private func verifyButton(_ model: SchoolProfileWorkspace) -> some View {
        Button { editingProfile = model } label: {
            Label("Vérifier la demande", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("learner-edit-profile")
    }

    /// Isolated shells without a profile client still show only recorded contacts.
    @ViewBuilder private func recordedContacts(_ learner: SchoolLearner) -> some View {
        if learner.contactEmail != nil || learner.contactPhone != nil || openProfile != nil {
            DisclosureGroup(isExpanded: $showsInformation) {
                VStack(alignment: .leading, spacing: 0) {
                    if let email = learner.contactEmail { DrivyContactRow(title: "E-mail", value: email) }
                    if let phone = learner.contactPhone { DrivyContactRow(title: "Téléphone", value: phone) }
                    if let openProfile {
                        Button("Modifier les informations") { openProfile(learner) }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                informationLabel
            }
        }
    }

    // MARK: - Lessons and progression

    private var pages: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if workspace.isLoadingTrainings && workspace.trainings.isEmpty {
                DrivySkeletonRows(count: 2).drivySkeleton("Chargement des formations…")
            }
            if let error = workspace.trainingsError {
                SchoolErrorNotice(message: error, retry: { Task { await workspace.loadTrainings() } })
            }
            if !workspace.isLoadingTrainings && workspace.trainings.isEmpty && workspace.trainingsError == nil {
                DrivyEmptyState(title: "Aucune formation", message: "Ouvre-la sur le web.", symbol: "steeringwheel")
            }
            ForEach(workspace.trainings) { training in trainingPages(training) }
            if workspace.nextTrainingsCursor != nil {
                Button { Task { await workspace.loadMoreTrainings() } } label: {
                    DrivyBusyLabel(title: "Afficher les autres formations", busyTitle: "Chargement…", isBusy: workspace.isLoadingMoreTrainings)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(workspace.isLoadingMoreTrainings || workspace.isLoadingTrainings)
            }
        }
    }

    private func trainingPages(_ training: SchoolTraining) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            if soleTraining == nil { trainingTitle(training) }
            DrivyRowGroup {
                DrivyNavigationRow(title: "Leçons") {
                    path.append(SchoolLearnerPage(trainingID: training.id, section: .lessons))
                }
                .accessibilityIdentifier("learner-lessons-\(training.id.uuidString)")
                DrivyNavigationRow(title: "Progression") {
                    path.append(SchoolLearnerPage(trainingID: training.id, section: .progress))
                }
                .accessibilityIdentifier("learner-progress-\(training.id.uuidString)")
            }
            .disabled(trainingClient == nil)
        }
    }

    /// Several formations: each group is named, and an unusual status follows its own name.
    private func trainingTitle(_ training: SchoolTraining) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.s))
        return layout {
            DrivySectionHeader(title: "Permis \(training.categoryCode)")
            if training.status != "ACTIVE" {
                DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status))
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder private var actions: some View {
        if let learner = workspace.learner, let openPlanning, learner.archivedAt == nil {
            DrivyStickyActionBar {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: DrivySpacing.s))
                    : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
                layout {
                    if agendaClient != nil {
                        SchoolStartNowButton(workspace: workspace, agendaClient: agendaClient, captureController: captureController,
                            learnerID: learner.id, onFinished: { Task { await workspace.loadTrainings() } }) {
                            Label("Démarrer", systemImage: "location.fill")
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityLabel("Démarrer une leçon").accessibilityIdentifier("learner-start-now")
                    }
                    let plan = Button { openPlanning(learner) } label: { Label("Planifier", systemImage: "calendar.badge.plus") }
                        .accessibilityLabel("Planifier une leçon").accessibilityIdentifier("learner-plan-lesson")
                    if agendaClient != nil { plan.buttonStyle(DrivySecondaryButtonStyle()) }
                    else { plan.buttonStyle(DrivyPrimaryButtonStyle()) }
                }
            }
        }
    }

    private func reload() async {
        let requestedScope = scopeKey
        await workspace.loadSelectedLearner()
        guard !Task.isCancelled, requestedScope == scopeKey else { return }
        await loadProfile()
    }

    private func loadProfile() async {
        guard editingProfile == nil, let learner = workspace.learner, learner.id == workspace.selectedLearnerID else { return }
        if let model = profileModel, profileScopeKey == scopeKey {
            await model.load(preserveDraft: false)
            return
        }
        profileModel?.invalidate()
        profileScopeKey = scopeKey
        profileModel = makeLearnerProfile?(learner)
        profileCreationFailed = profileModel == nil
        if let profileModel { await profileModel.load(preserveDraft: false) }
    }
}
