import SwiftUI

/// The dossier opens on one card for the learner (who, which permits, how to reach them, and the personal
/// details folded inside), then shows lessons or progression in place, in the same scroll, behind one
/// segmented control: nothing is pushed. However many formations the learner follows, one permit filter
/// serves both sections.
struct SchoolLearnerDossierView: View {
    @Bindable var workspace: SchoolWorkspace
    let openProfile: ((SchoolLearner) -> Void)?
    let makeLearnerProfile: ((SchoolLearner) -> SchoolProfileWorkspace?)?
    let openPlanning: ((SchoolLearner) -> Void)?
    let trainingClient: SchoolTrainingClient?
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    /// Présent quand le dossier s’ouvre en feuille (depuis une leçon) : un bouton Fermer rend la leçon.
    var close: (() -> Void)? = nil
    /// Lessons or progression: the choice survives a reread and a change of permit.
    @State private var section: SchoolTrainingSection = .lessons
    @State private var profileModel: SchoolProfileWorkspace?
    @State private var editingProfile: SchoolProfileWorkspace?
    /// Le champ que le formulaire ouvre et met au clavier quand on vient d’une information manquante.
    @State private var editingFocus: SchoolProfileField?
    @State private var profileScopeKey = ""
    @State private var profileCreationFailed = false
    @State private var showsInformation = false
    /// Informations requises qui manquent au profil, telles que l’école les nomme ; vide tant que rien n’est lu.
    @State private var missingFields: [String] = []
    /// Vrai une fois les champs manquants lus pour ce dossier : une panne ne se lit jamais « rien ne manque ».
    @State private var missingFieldsRead = false
    /// The permit filtered in Lessons and Progression; `nil` shows them all. Held here so the choice
    /// is shared by the two sections of the same learner.
    @State private var permit: UUID?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(workspace.selectedLearnerID?.uuidString ?? "")"
    }

    /// The profile read for the learner and rights on screen, never the one of a previous scope.
    private var currentProfile: SchoolProfileWorkspace? {
        profileScopeKey == scopeKey ? profileModel : nil
    }

    /// The learner's formations, the current one first: the order of the permit filter.
    private var trainings: [SchoolTraining] { SchoolPermitName.ordered(workspace.trainings) }

    var body: some View {
        NavigationStack {
            dossier
                .navigationTitle("Dossier")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if let close {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer", action: close).accessibilityIdentifier("dossier-close")
                        }
                    }
                }
        }
        .task(id: scopeKey) { await reload() }
        .sheet(item: $editingProfile, onDismiss: { editingFocus = nil; Task { await reload() } }) { model in
            let missing = Set(missingFields.compactMap(SchoolProfileField.init(rawValue:)))
            // Son propre dossier (administration qui est aussi élève) s’ouvre dans « Mon profil », avec son compte Drivy.
            if model.isOwnProfile {
                SchoolMyProfileView(workspace: workspace, dossier: model, loadsDossierOnAppear: false,
                    focus: editingFocus, missingFields: missing)
            } else {
                SchoolProfileView(model: model, loadsOnAppear: false, focus: editingFocus, missingFields: missing)
            }
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
            // Changing tabs keeps the profile. Changing account,
            // rights or selected learner invalidates its in-flight reads and draft.
            if profileScopeKey != scopeKey { profileModel?.invalidate(); editingProfile = nil }
        }
    }

    private var dossier: some View {
        // The page is refreshable and now often shorter than the screen: it keeps the
        // system bounce, without which the pull gesture has nothing to pull.
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                // Rien de lu pour cet élève : l’attente, aussi après une lecture interrompue que la prochaine reprend.
                if workspace.learner?.id != workspace.selectedLearnerID && workspace.learnerError == nil {
                    DrivySkeletonRows(count: 3, leading: .avatar).drivySkeleton("Chargement du dossier…")
                }
                if let error = workspace.learnerError {
                    SchoolErrorNotice(message: error, retry: { Task { await reload() } })
                }
                if let learner = workspace.learner, learner.id == workspace.selectedLearnerID {
                    header(learner)
                    pages(learner)
                }
            }
            .drivyGroupedPageContent()
        }
        // Sur le fond des listes groupées, comme Profil et l’historique des leçons : l’identité est posée
        // sur le fond, le reste se lit en blocs.
        .background(DrivyTheme.canvas)
        .refreshable { await refresh() }
        .accessibilityIdentifier("learner-dossier")
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
    }

    // MARK: - Learner card

    /// One card for the person. Folded: who, which permits and their state, and a menu to reach them.
    /// Unfolded: the personal details, in the same surface. Everything shown folded comes with the dossier
    /// itself, so nothing moves when the profile arrives.
    private func header(_ learner: SchoolLearner) -> some View {
        let links = SchoolLearnerContactLink.links(for: contact(of: learner))
        let unfolds = canUnfold(learner)
        return VStack(alignment: .leading, spacing: 0) {
            // Rien à déplier : la carte reste lisible, l’appui ne fait rien (un bouton désactivé griserait le nom).
            Button { if unfolds { toggleInformation() } } label: {
                identity(learner, reservesMenu: !links.isEmpty, unfolds: unfolds)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([learner.displayName, permitLine, learner.archivedAt == nil ? nil : "Archivé"]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityValue(unfolds ? (showsInformation ? "Informations personnelles dépliées" : "Informations personnelles repliées") : "")
            .accessibilityHint(unfolds ? "Affiche ou masque les informations personnelles" : "")
            // Historic UI-test identifier: it designates the full name that heads the dossier.
            .accessibilityIdentifier("learner-profile-first-name")
            // The menu sits over the header, outside the button: opening it never unfolds the card.
            .overlay(alignment: .topTrailing) {
                if !links.isEmpty { contactMenu(links, learner: learner).padding(.top, DrivySpacing.m) }
            }
            attention(learner)
            if showsInformation && unfolds {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    Divider().overlay(DrivyTheme.border)
                    details(learner)
                }
                .padding(.bottom, DrivySpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .offset(y: -DrivySpacing.xs)))
                .accessibilityIdentifier("learner-profile-details")
            }
        }
        .drivyGroupedBlock(verticalPadding: 0)
        // The details appear inside the card as it grows, never over what follows.
        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.groupedBlock, style: .continuous))
    }

    private func identity(_ learner: SchoolLearner, reservesMenu: Bool, unfolds: Bool) -> some View {
        let stacked = typeSize.isAccessibilitySize
        return HStack(alignment: .center, spacing: DrivySpacing.s) {
            // At the largest text sizes the name takes the whole width.
            if !stacked {
                DrivyAvatar(name: learner.displayName, size: DrivyAvatar.pageSize, photo: workspace.photo(for: learner.personId))
                    .task(id: learner.personId) { await workspace.loadPhoto(for: learner.personId) }
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(learner.displayName)
                    .font(.drivyTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .lineLimit(stacked ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let permitLine {
                    Text(permitLine)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if learner.archivedAt != nil { DrivyStatusBadge(title: "Archivé", symbol: "archivebox") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The trailing column: room for the menu laid over it, then the chevron of the card.
            VStack(spacing: 0) {
                if reservesMenu { Color.clear.frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget) }
                if unfolds {
                    Image(systemName: reduceMotion && showsInformation ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .rotationEffect(.degrees(!reduceMotion && showsInformation ? 180 : 0))
                        .frame(width: DrivyLayout.tapTarget, height: reservesMenu ? 16 : DrivyLayout.tapTarget)
                }
            }
        }
        .padding(.vertical, DrivySpacing.m)
        .contentShape(Rectangle())
    }

    /// Every permit with its state, the current one first: « Cat. B (En cours) · Cat. A (En pause) ».
    /// One line of text that wraps, so several permits never turn into a row of badges.
    private var permitLine: String? {
        let names = SchoolPermitName.categories(trainings)
        let parts = trainings.map { "\(names[$0.id] ?? "Cat. \($0.categoryCode)") (\(SchoolPresentation.trainingStatus($0.status)))" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The same three gestures as before, behind one button: call, message, e-mail. Only those a
    /// recorded contact makes possible are listed.
    private func contactMenu(_ links: [SchoolLearnerContactLink], learner: SchoolLearner) -> some View {
        Menu {
            ForEach(links) { link in
                Button { openURL(link.url) } label: { Label(link.title, systemImage: link.symbol) }
                    .accessibilityValue(link.value)
                    .accessibilityIdentifier("learner-profile-\(link.kind.rawValue)")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .frame(width: 32, height: 32)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                .drivyMenuLabelShape(Circle())
        }
        .accessibilityLabel("Contacter \(learner.displayName)")
        .accessibilityIdentifier("learner-profile-actions")
    }

    private func toggleInformation() {
        withAnimation(DrivyMotion.unfold(reduceMotion)) { showsInformation.toggle() }
    }

    /// Once read, the administrative profile is the reference for contacts; before, the dossier's own copy.
    private func contact(of learner: SchoolLearner) -> SchoolLearnerContact {
        if let profile = currentProfile?.profile {
            return SchoolLearnerContact(email: profile.contactEmail, phone: profile.contactPhone)
        }
        return SchoolLearnerContact(email: learner.contactEmail, phone: learner.contactPhone)
    }

    // MARK: - Personal details

    /// There is something to unfold: a profile read or being read, or recorded contacts in an isolated shell.
    private func canUnfold(_ learner: SchoolLearner) -> Bool {
        guard makeLearnerProfile != nil else {
            return learner.contactEmail != nil || learner.contactPhone != nil || openProfile != nil
        }
        let model = currentProfile
        return model?.profile != nil || model?.isLoading == true || (model == nil && !profileCreationFailed)
    }

    /// Les champs lus manquent, ou le dossier se dit incomplet sans qu’aucun champ visible par ce compte ne manque
    /// (un moniteur ne lit pas les champs protégés). Tant que la lecture n’a pas abouti, rien n’est affirmé.
    private func showsMissingInformation(_ learner: SchoolLearner, model: SchoolProfileWorkspace) -> Bool {
        guard missingFieldsRead else { return false }
        return !missingFields.isEmpty || (!model.hasFullAccess && SchoolRequiredActionRules.profileIsIncomplete(learner))
    }

    /// A request to check and an error are unusual: they stay visible, folded or not.
    @ViewBuilder private func attention(_ learner: SchoolLearner) -> some View {
        if makeLearnerProfile != nil {
            let model = currentProfile
            if let model, model.pending == nil, showsMissingInformation(learner, model: model) {
                missingInformation(model)
            }
            if let model, model.pending != nil {
                verifyButton(model).padding(.bottom, DrivySpacing.xs)
            }
            if let error = model?.errorMessage {
                SchoolErrorNotice(message: error, retry: { Task { await loadProfile() } })
                    .padding(.bottom, DrivySpacing.m)
            } else if model == nil && profileCreationFailed {
                SchoolErrorNotice(message: "Les informations de l’élève ne peuvent pas être chargées.",
                    retry: { Task { await loadProfile() } })
                    .padding(.bottom, DrivySpacing.m)
            }
        }
    }

    /// Ce qui manque, champ par champ, chaque ligne ouvrant le formulaire sur ce champ. Un champ que ce compte ne
    /// peut pas modifier est nommé sans geste, avec qui le renseigne. Un moniteur à qui l’école ne montre pas les
    /// champs protégés lit seulement qu’il revient à l’administration de compléter le dossier.
    @ViewBuilder private func missingInformation(_ model: SchoolProfileWorkspace) -> some View {
        let fields = missingFields.compactMap(SchoolProfileField.init(rawValue:))
        let editable = model.editableFields
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(DrivyTheme.border)
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                if fields.contains(where: { editable.contains($0) }) { DrivyActionDot() }
                Text("Profil à compléter")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                Spacer(minLength: DrivySpacing.xs)
                Text(fields.isEmpty ? "Par l’administration" : SchoolRequiredActionRules.missingCount(fields.count))
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .multilineTextAlignment(.trailing)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DrivySpacing.m)
            .padding(.bottom, DrivySpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(fields) { field in
                if editable.contains(field) {
                    Button { complete(field, model: model) } label: {
                        HStack(spacing: DrivySpacing.s) {
                            Text(field.label).foregroundStyle(DrivyTheme.text)
                            Spacer(minLength: DrivySpacing.xs)
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DrivyTheme.muted)
                                .accessibilityHidden(true)
                        }
                        .font(.body)
                        .frame(minHeight: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Ouvre le champ à renseigner")
                    .accessibilityIdentifier("learner-missing-\(field.rawValue)")
                } else {
                    HStack(spacing: DrivySpacing.s) {
                        Text(field.label).foregroundStyle(DrivyTheme.text)
                        Spacer(minLength: DrivySpacing.xs)
                        Text(field.isName && !model.hasFullAccess ? "Élève ou administration" : "Administration")
                            .foregroundStyle(DrivyTheme.muted)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: DrivyLayout.tapTarget)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.bottom, DrivySpacing.xs)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learner-missing-information")
    }

    private func complete(_ field: SchoolProfileField, model: SchoolProfileWorkspace) {
        editingFocus = field
        editingProfile = model
    }

    @ViewBuilder private func details(_ learner: SchoolLearner) -> some View {
        Text("Informations personnelles")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.muted)
            .accessibilityAddTraits(.isHeader)
        if makeLearnerProfile == nil {
            // Isolated shells without a profile client still show only recorded contacts.
            VStack(alignment: .leading, spacing: 0) {
                if let email = learner.contactEmail { DrivyContactRow(title: "E-mail", value: email) }
                if let phone = learner.contactPhone { DrivyContactRow(title: "Téléphone", value: phone) }
                if let openProfile {
                    Button("Modifier les informations") { openProfile(learner) }
                        .buttonStyle(.drivyText)
                }
            }
        } else if let model = currentProfile, model.profile != nil {
            SchoolLearnerProfileSummary(model: model, displayedName: learner.displayName)
            if model.pending == nil { editButton(model) }
        } else {
            DrivySkeletonRows(count: 2, lines: 1).drivySkeleton("Chargement des informations…")
        }
    }

    /// Never dimmed during a silent reread: the form keeps its own fields locked until the answer.
    private func editButton(_ model: SchoolProfileWorkspace) -> some View {
        Button("Modifier les informations") { editingProfile = model }
            .buttonStyle(.drivyText)
            .accessibilityIdentifier("learner-edit-profile")
    }

    private func verifyButton(_ model: SchoolProfileWorkspace) -> some View {
        Button { editingProfile = model } label: {
            Label("Vérifier la demande", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
        }
        .buttonStyle(.drivyText)
        .accessibilityIdentifier("learner-edit-profile")
    }

    // MARK: - Lessons and progression

    private func pages(_ learner: SchoolLearner) -> some View {
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
            if let trainingClient, !workspace.trainings.isEmpty {
                // The section control, the permit filter and the content live in this page's own scroll.
                SchoolTrainingScreen(embeddedIn: workspace, client: trainingClient, learner: learner,
                    trainingIDs: trainings.map(\.id), permit: $permit, section: $section)
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

    // MARK: - Actions

    @ViewBuilder private var actions: some View {
        if let learner = workspace.learner, let openPlanning, learner.archivedAt == nil {
            DrivyStickyActionBar(grouped: true) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: DrivySpacing.s))
                    : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
                layout {
                    if agendaClient != nil {
                        // La leçon créée depuis le dossier apparaît dans sa liste : comme après « Planifier », les
                        // leçons se relisent à la fermeture de la chaîne, pas seulement les formations.
                        SchoolStartNowButton(workspace: workspace, agendaClient: agendaClient, captureController: captureController,
                            learnerID: learner.id, onFinished: {
                                Task { await workspace.loadTrainings() }
                                NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil)
                            }) {
                            Label("Démarrer", systemImage: "location.fill")
                        }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityLabel("Démarrer une leçon").accessibilityIdentifier("learner-start-now")
                    }
                    let plan = Button { openPlanning(learner) } label: { Text("Planifier") }
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
        await workspace.loadRemainingTrainings()
        guard !Task.isCancelled, requestedScope == scopeKey else { return }
        await loadProfile()
    }

    /// Tirer pour actualiser relit le dossier puis ce que montre la section embarquée (modèles partagés : les listes
    /// restent à l’écran jusqu’à chaque réponse). Le geste attend la relecture sans la porter : SwiftUI annule la
    /// tâche de `.refreshable` dès que la page se redessine sous le doigt (dossier relu, formations remplacées),
    /// et cette annulation, transmise aux requêtes, revenait en « Le chargement a été interrompu ». La relecture
    /// court donc dans sa propre tâche ; un changement d’élève ou de droits l’arrête toujours (`reload` compare
    /// la portée, le dossier ignore les réponses d’un autre élève).
    private func refresh() async {
        let reading = Task { @MainActor in
            await reload()
            await reloadLessons()
        }
        await reading.value
    }

    private func reloadLessons() async {
        await SchoolLessonFeed(models: SchoolTrainingModelCache.current(trainings.map(\.id))).reload()
    }

    private func loadProfile() async {
        guard editingProfile == nil, let learner = workspace.learner, learner.id == workspace.selectedLearnerID else { return }
        if let model = profileModel, profileScopeKey == scopeKey {
            await model.load(preserveDraft: false)
            await readMissingFields(model, learner: learner)
            return
        }
        profileModel?.invalidate()
        missingFields = []
        missingFieldsRead = false
        profileScopeKey = scopeKey
        profileModel = makeLearnerProfile?(learner)
        profileCreationFailed = profileModel == nil
        if let profileModel {
            await profileModel.load(preserveDraft: false)
            await readMissingFields(profileModel, learner: learner)
        }
    }

    /// Relu avec le profil, donc après chaque modification. La ligne de la liste et le point de l’onglet suivent le
    /// dossier relu (`loadSelectedLearner` remplace sa ligne) : l’école calcule les deux avec la même règle.
    private func readMissingFields(_ model: SchoolProfileWorkspace, learner: SchoolLearner) async {
        let requested = scopeKey
        guard let fields = await model.missingRequiredFields(), requested == scopeKey, !Task.isCancelled else { return }
        withAnimation(DrivyMotion.unfold(reduceMotion)) {
            missingFields = fields
            missingFieldsRead = true
        }
    }
}
