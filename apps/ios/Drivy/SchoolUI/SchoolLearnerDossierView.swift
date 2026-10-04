import SwiftUI

private struct SchoolLearnerPage: Hashable {
    let trainingID: UUID
    let section: SchoolTrainingSection
}

/// The learner's profile is the dossier's home. Lessons and progression are distinct
/// pushed pages, so the native back action always returns to this profile.
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(workspace.selectedLearnerID?.uuidString ?? "")"
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
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                if workspace.isLoadingLearner && workspace.learner == nil {
                    DrivySkeletonRows(count: 3, leading: .avatar).drivySkeleton("Chargement du dossier…")
                }
                if let error = workspace.learnerError {
                    SchoolErrorNotice(message: error, retry: { Task { await reload() } })
                }
                if let learner = workspace.learner, learner.id == workspace.selectedLearnerID {
                    profileCard(learner)
                    pages
                }
            }
            .drivyPageContent()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DrivyTheme.surface)
        .refreshable { await reload() }
        .accessibilityIdentifier("learner-dossier")
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
    }

    private func profileCard(_ learner: SchoolLearner) -> some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                HStack(alignment: .top, spacing: DrivySpacing.m) {
                    if !typeSize.isAccessibilitySize { DrivyAvatar(name: learner.displayName, size: 56) }
                    VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                        Text(learner.displayName)
                            .font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if learner.archivedAt != nil { DrivyStatusBadge(title: "Archivé", symbol: "archivebox") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let model = profileModel, profileScopeKey == scopeKey {
                    if model.profile != nil {
                        SchoolLearnerProfileSummary(model: model)
                    } else if model.isLoading {
                        DrivySkeletonRows(count: 3).drivySkeleton("Chargement des informations…")
                    }
                    if let error = model.errorMessage {
                        SchoolErrorNotice(message: error, retry: { Task { await loadProfile() } })
                    }
                    if model.profile != nil || model.pending != nil {
                        Button { editingProfile = model } label: {
                            Label(model.pending == nil ? "Modifier les informations" : "Vérifier la demande",
                                  systemImage: model.pending == nil ? "pencil" : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                                .frame(minHeight: 44)
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("learner-edit-profile")
                    }
                } else if makeLearnerProfile != nil {
                    if profileCreationFailed {
                        SchoolErrorNotice(message: "Les informations de l’élève ne peuvent pas être chargées.",
                            retry: { Task { await loadProfile() } })
                    } else {
                        DrivySkeletonRows(count: 3).drivySkeleton("Chargement des informations…")
                    }
                } else {
                    // Isolated shells without a profile client still show only recorded contacts.
                    if let email = learner.contactEmail { DrivyContactRow(title: "E-mail", value: email, symbol: "envelope") }
                    if let phone = learner.contactPhone { DrivyContactRow(title: "Téléphone", value: phone, symbol: "phone") }
                    if let openProfile {
                        Button("Modifier les informations") { openProfile(learner) }.frame(minHeight: 44)
                    }
                }
                if !workspace.trainings.isEmpty {
                    Divider()
                    ForEach(workspace.trainings) { training in
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
                            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.s))
                        layout {
                            Label("Permis \(training.categoryCode)", systemImage: "steeringwheel")
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            if training.status != "ACTIVE" {
                                DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status))
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

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
            ForEach(workspace.trainings) { training in
                DrivyRowGroup(title: workspace.trainings.count > 1 ? "Permis \(training.categoryCode)" : nil) {
                    DrivyNavigationRow(title: "Leçons", symbol: "calendar") {
                        path.append(SchoolLearnerPage(trainingID: training.id, section: .lessons))
                    }
                    .accessibilityIdentifier("learner-lessons-\(training.id.uuidString)")
                    DrivyNavigationRow(title: "Progression", symbol: "chart.line.uptrend.xyaxis") {
                        path.append(SchoolLearnerPage(trainingID: training.id, section: .progress))
                    }
                    .accessibilityIdentifier("learner-progress-\(training.id.uuidString)")
                }
                .disabled(trainingClient == nil)
            }
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
