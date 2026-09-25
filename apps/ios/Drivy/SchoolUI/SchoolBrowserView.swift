import SwiftUI

struct SchoolBrowserView: View {
    @Bindable var workspace: SchoolWorkspace
    let openAccount: () -> Void
    var openInvitations: (() -> Void)? = nil
    var openProfile: ((SchoolLearner) -> Void)? = nil
    var openSchool: (() -> Void)? = nil
    var openTrainingAdministration: ((SchoolLearner) -> Void)? = nil
    var openPlanning: ((SchoolLearner) -> Void)? = nil
    var openAddLearner: (() -> Void)? = nil
    var trainingClient: SchoolTrainingClient? = nil
    var openCreateTraining: ((SchoolLearner) -> Void)? = nil
    @State private var choosesSchool = false

    var body: some View {
        NavigationSplitView {
            searchableMaster
            .background(DrivyTheme.canvas)
            .navigationTitle(workspace.isLearnerOnly ? "Mon dossier" : "Élèves")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                // Same shell as the other tabs; the contextual action sits
                // before the account button, which always closes the bar.
                DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName,
                    chooseSchool: { choosesSchool = true })
                if let openAddLearner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: openAddLearner) { Label("Ajouter un élève", systemImage: "person.badge.plus") }
                            .accessibilityIdentifier("add-school-learner")
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                DrivyAccountToolbarItem(openAccount: openAccount)
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        } detail: {
            if workspace.selectedLearnerID != nil {
                SchoolLearnerDetailView(workspace: workspace, openProfile: openProfile, openTrainingAdministration: openTrainingAdministration,
                    openPlanning: openPlanning, trainingClient: trainingClient, openCreateTraining: openCreateTraining)
            } else {
                SchoolOverviewView(workspace: workspace)
            }
        }
        .tint(DrivyTheme.accent)
        .sheet(isPresented: $choosesSchool) {
            SchoolChooserSheet(workspace: workspace, close: { choosesSchool = false })
        }
    }

    @ViewBuilder private var searchableMaster: some View {
        if workspace.school?.status == "ACTIVE", !workspace.isLearnerOnly {
            masterColumn.searchable(text: Binding(get: { workspace.searchText }, set: { workspace.setSearchText($0) }),
                placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher un élève")
        } else {
            masterColumn
        }
    }

    private var masterColumn: some View {
        learnerList
    }

    private var trimmedSearch: String { workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var learnerList: some View {
        List(selection: Binding(get: { workspace.selectedLearnerID }, set: { workspace.selectLearner($0) })) {
            if workspace.isLoadingSchool || workspace.isSearching {
                ProgressView(workspace.isLoadingSchool ? "Ouverture de l’école…" : "Recherche en cours…")
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .listRowSeparator(.hidden)
                    .listRowBackground(DrivyTheme.surface)
            }
            if let error = workspace.schoolError {
                SchoolErrorNotice(message: error, retry: {
                    if let membership = workspace.membership { Task { await workspace.selectSchool(membership) } }
                })
                .listRowSeparator(.hidden)
                .listRowBackground(DrivyTheme.surface)
            } else if let error = workspace.learnersError {
                SchoolErrorNotice(message: error, retry: { Task { await workspace.searchLearners(workspace.searchText) } })
                    .listRowSeparator(.hidden)
                    .listRowBackground(DrivyTheme.surface)
            }
            if let school = workspace.school, school.status != "ACTIVE" {
                DrivyEmptyState(title: school.status == "ARCHIVED" ? "École archivée" : "L’école se prépare",
                    message: school.status == "ARCHIVED"
                        ? "Cette école n’ouvre plus de nouvelles opérations. La carte reste disponible depuis Séance."
                        : "Les dossiers seront accessibles lorsque l’école sera active. Vous pouvez déjà ouvrir la carte depuis Séance.",
                    symbol: school.status == "ARCHIVED" ? "archivebox" : "building.2",
                    actionTitle: openSchool == nil ? nil : "Ouvrir l’espace École", action: openSchool)
                    .buttonStyle(.borderless)
                    .listRowSeparator(.hidden)
                    .listRowBackground(DrivyTheme.surface)
            } else if !workspace.isSearching && !workspace.isLoadingSchool && workspace.school != nil && workspace.learners.isEmpty && workspace.learnersError == nil {
                emptyLearners
                    .buttonStyle(.borderless)
                    .listRowSeparator(.hidden)
                    .listRowBackground(DrivyTheme.surface)
            }
            ForEach(workspace.learners) { learner in
                NavigationLink(value: learner.id) {
                    SchoolLearnerRow(learner: learner, isSelected: workspace.selectedLearnerID == learner.id)
                }
                .accessibilityIdentifier("school-learner-\(learner.id.uuidString)")
                .listRowInsets(EdgeInsets(top: DrivySpacing.xxs, leading: DrivySpacing.l, bottom: DrivySpacing.xxs, trailing: DrivySpacing.m))
                .listRowSeparatorTint(DrivyTheme.border)
                .listRowBackground(workspace.selectedLearnerID == learner.id ? DrivyTheme.accentSoft : DrivyTheme.surface)
            }
            if workspace.nextLearnersCursor != nil {
                Button { Task { await workspace.loadMoreLearners() } } label: {
                    if workspace.isLoadingMoreLearners { ProgressView("Chargement des élèves suivants…") }
                    else { Text("Afficher la suite").font(.subheadline.weight(.semibold)) }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .disabled(workspace.isLoadingMoreLearners || workspace.isSearching)
                .accessibilityIdentifier("more-learners")
                .listRowSeparator(.hidden)
                .listRowBackground(DrivyTheme.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.surface)
        .refreshable {
            guard workspace.school?.status == "ACTIVE" else { return }
            await workspace.searchLearners(workspace.searchText)
        }
    }

    /// First use, no result and no access are three different situations,
    /// each with its own next step.
    @ViewBuilder private var emptyLearners: some View {
        if !trimmedSearch.isEmpty {
            DrivyEmptyState(title: "Aucun résultat", message: "Aucun élève ne correspond à « \(trimmedSearch) ». Essayez un autre nom.",
                symbol: "magnifyingglass", actionTitle: "Effacer la recherche", action: { workspace.setSearchText("") })
        } else if let openAddLearner {
            VStack(alignment: .leading, spacing: 0) {
                DrivyEmptyState(title: "Aucun élève pour le moment",
                    message: "Ajoutez le rôle Élève à un membre de l’école, ou invitez une nouvelle personne.",
                    symbol: "person.2", actionTitle: "Ajouter un élève", action: openAddLearner)
                invitationsLink
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                DrivyEmptyState(title: "Aucun dossier accessible",
                    message: workspace.isLearnerOnly ? "Votre école doit vous donner accès à votre dossier." : "Ce compte n’a accès à aucun dossier dans cette école.",
                    symbol: "person.crop.circle.badge.questionmark")
                invitationsLink
            }
        }
    }

    @ViewBuilder private var invitationsLink: some View {
        if workspace.searchText.isEmpty, let openInvitations {
            Button("Ouvrir les invitations", action: openInvitations)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
                .frame(minHeight: 44)
                .padding(.leading, DrivySpacing.xl + DrivySpacing.m)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("open-school-invitations")
        }
    }
}

/// School chooser presented from the leading toolbar button of every tab.
struct SchoolChooserSheet: View {
    @Bindable var workspace: SchoolWorkspace
    let close: () -> Void

    var body: some View {
        NavigationStack {
            SchoolChooserView(workspace: workspace, onSelect: close)
                .navigationTitle("Changer d’école")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Fermer", action: close) }
                }
        }
        .tint(DrivyTheme.accent)
        .presentationDetents([.medium, .large])
    }
}

struct SchoolChooserView: View {
    @Bindable var workspace: SchoolWorkspace
    var onSelect: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    DrivySectionHeader(title: "Choisissez votre école")
                    Text("Drivy affiche les dossiers et les formations autorisés par l’école choisie.")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, DrivySpacing.xs)
                ForEach(workspace.person?.memberships ?? []) { membership in
                    let isCurrent = workspace.membership?.membershipId == membership.membershipId
                    Button {
                        workspace.leaveSchool()
                        onSelect?()
                        Task { await workspace.selectSchool(membership) }
                    } label: {
                        HStack(spacing: DrivySpacing.m) {
                            Image(systemName: "building.2")
                                .font(.title3)
                                .foregroundStyle(isCurrent ? DrivyTheme.accent : DrivyTheme.muted)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text(membership.schoolName).font(.headline).foregroundStyle(DrivyTheme.text)
                                Text(SchoolPresentation.roles(membership.roles))
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            DrivySelectionMark(isSelected: isCurrent)
                        }
                    }
                    .buttonStyle(DrivySelectionCardStyle(isSelected: isCurrent))
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .accessibilityIdentifier("school-choice-\(membership.schoolId.uuidString)")
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
    }
}

private struct SchoolLearnerRow: View {
    let learner: SchoolLearner
    let isSelected: Bool

    var body: some View {
        DrivyEntityRow(title: learner.displayName, meta: learner.contactEmail,
            leading: .avatar(learner.displayName), badge: badge, isSelected: isSelected)
    }

    private var badge: DrivyStatusBadge? {
        if learner.archivedAt != nil { return DrivyStatusBadge(title: "Dossier archivé", symbol: "archivebox") }
        switch learner.profileReadiness {
        case "MINIMAL": return DrivyStatusBadge(title: "Profil à compléter", symbol: "person.text.rectangle")
        case "ACTION_REQUIRED": return DrivyStatusBadge(title: "Informations à vérifier", symbol: "exclamationmark.triangle", tone: .warning)
        default: return nil
        }
    }
}

/// iPad detail column before a selection: a whole empty screen, so the system
/// ContentUnavailableView carries it.
private struct SchoolOverviewView: View {
    @Bindable var workspace: SchoolWorkspace
    var body: some View {
        Group {
            if workspace.school != nil {
                ContentUnavailableView {
                    Label(workspace.isLearnerOnly ? "Ouvrir mon dossier" : "Sélectionnez un élève", systemImage: "person.text.rectangle")
                } description: {
                    Text(workspace.isLearnerOnly
                        ? "Ouvrez votre dossier pour retrouver votre profil et vos formations."
                        : "Son profil et ses formations s’afficheront ici.")
                }
            } else if workspace.isLoadingSchool {
                ProgressView("Ouverture de l’école…")
            } else if let error = workspace.schoolError {
                SchoolErrorNotice(message: error, retry: {
                    if let membership = workspace.membership { Task { await workspace.selectSchool(membership) } }
                })
                .drivyPageContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.surface)
        .navigationTitle("Dossiers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SchoolLearnerDetailView: View {
    @Bindable var workspace: SchoolWorkspace
    let openProfile: ((SchoolLearner) -> Void)?
    let openTrainingAdministration: ((SchoolLearner) -> Void)?
    let openPlanning: ((SchoolLearner) -> Void)?
    let trainingClient: SchoolTrainingClient?
    let openCreateTraining: ((SchoolLearner) -> Void)?
    @State private var presentedTraining: TrainingPresentation?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                if workspace.isLoadingLearner {
                    ProgressView("Ouverture du dossier…").frame(maxWidth: .infinity, minHeight: 120)
                } else if let error = workspace.learnerError {
                    SchoolErrorNotice(message: error, retry: { Task { await workspace.loadSelectedLearner() } })
                } else if let learner = workspace.learner {
                    VStack(alignment: .leading, spacing: DrivySpacing.l) {
                        learnerHeading(learner)
                        if let openPlanning, learner.archivedAt == nil {
                            Button { openPlanning(learner) } label: { Label("Planifier une leçon", systemImage: "calendar.badge.plus") }
                                .buttonStyle(DrivyPrimaryButtonStyle()).accessibilityIdentifier("learner-plan-lesson")
                        }
                    }
                    if let openProfile {
                        DrivyRowGroup(title: "Dossier") {
                            DrivyNavigationRow(title: "Profil scolaire",
                                detail: learner.profileReadiness == "MINIMAL" ? "Compléter les informations utiles" : "Consulter et mettre à jour",
                                symbol: "person.text.rectangle",
                                badge: profileBadge(learner),
                                action: { openProfile(learner) })
                                .accessibilityIdentifier("open-learner-profile")
                        }
                    }
                    trainings
                    if learner.contactEmail != nil || learner.contactPhone != nil {
                        DrivyRowGroup(title: "Coordonnées") {
                            if let email = learner.contactEmail { DrivyContactRow(title: "E-mail", value: email, symbol: "envelope") }
                            if let phone = learner.contactPhone { DrivyContactRow(title: "Téléphone", value: phone, symbol: "phone") }
                        }
                    }
                }
            }
            .drivyPageContent()
        }
        .background(DrivyTheme.surface)
        .navigationTitle("Dossier")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workspace.selectedLearnerID) { await workspace.loadSelectedLearner() }
        .sheet(item: $presentedTraining, onDismiss: { workspace.selectTraining(nil) }) { presentation in
            SchoolTrainingView(client: presentation.client, workspace: workspace,
                learner: presentation.learner, trainingID: presentation.trainingID)
        }
    }

    private func profileBadge(_ learner: SchoolLearner) -> DrivyStatusBadge? {
        switch learner.profileReadiness {
        case "MINIMAL": DrivyStatusBadge(title: "À compléter", symbol: "person.text.rectangle")
        case "ACTION_REQUIRED": DrivyStatusBadge(title: "À vérifier", symbol: "exclamationmark.triangle", tone: .warning)
        default: nil
        }
    }

    /// Mockup 04: initials, the learner's name as the screen title, then the
    /// school context. The avatar steps aside under accessibility text sizes.
    private func learnerHeading(_ learner: SchoolLearner) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(alignment: .center, spacing: DrivySpacing.m) {
                if !dynamicTypeSize.isAccessibilitySize {
                    DrivyAvatar(name: learner.displayName, size: 60)
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(learner.displayName)
                        .font(.drivyScreenTitle)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(workspace.school.map { "Élève · \($0.name)" } ?? "Dossier scolaire")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if learner.archivedAt != nil {
                DrivyStatusBadge(title: "Dossier archivé", symbol: "archivebox")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var trainings: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Formations").font(.drivySection).foregroundStyle(DrivyTheme.text).accessibilityAddTraits(.isHeader)
                Spacer(minLength: DrivySpacing.xs)
                if let learner = workspace.learner, learner.archivedAt == nil,
                   openCreateTraining != nil || openTrainingAdministration != nil {
                    Menu {
                        if let openCreateTraining {
                            Button { openCreateTraining(learner) } label: { Label("Ouvrir une formation", systemImage: "plus") }
                                .accessibilityIdentifier("create-learner-training")
                        }
                        if let openTrainingAdministration {
                            Button { openTrainingAdministration(learner) } label: { Label("Affecter un moniteur", systemImage: "person.badge.plus") }
                                .accessibilityIdentifier("manage-learner-trainings")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(DrivyTheme.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Gérer les formations")
                }
            }
            .padding(.bottom, DrivySpacing.xxs)
            if workspace.isLoadingTrainings {
                ProgressView("Chargement des formations…")
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            if let error = workspace.trainingsError {
                SchoolErrorNotice(message: error, retry: { Task { await workspace.loadTrainings() } })
                    .padding(.vertical, DrivySpacing.xs)
            }
            if !workspace.isLoadingTrainings && workspace.trainings.isEmpty && workspace.trainingsError == nil {
                if let learner = workspace.learner, let openCreateTraining, learner.archivedAt == nil {
                    DrivyEmptyState(title: "Aucune formation", message: "Ouvrez une formation pour ce dossier à partir d’une offre de l’école.",
                        symbol: "steeringwheel", actionTitle: "Ouvrir une formation", action: { openCreateTraining(learner) })
                } else {
                    DrivyEmptyState(title: "Aucune formation", message: "Aucune formation accessible dans ce dossier.", symbol: "steeringwheel")
                }
            }
            DrivyRowGroup {
                ForEach(workspace.trainings) { training in
                    DrivyNavigationRow(title: "Permis \(training.categoryCode)", symbol: "steeringwheel",
                        badge: DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status),
                            tone: training.status == "ACTIVE" ? .accent : .neutral),
                        action: {
                            guard let trainingClient, let learner = workspace.learner else { return }
                            workspace.selectTraining(training.id)
                            presentedTraining = TrainingPresentation(client: trainingClient, learner: learner, trainingID: training.id)
                        })
                        .disabled(trainingClient == nil || workspace.learner == nil)
                        .accessibilityIdentifier("school-training-\(training.id.uuidString)")
                }
            }
            if workspace.nextTrainingsCursor != nil {
                Button { Task { await workspace.loadMoreTrainings() } } label: {
                    if workspace.isLoadingMoreTrainings { ProgressView("Chargement des formations suivantes…") }
                    else { Text("Afficher les autres formations").font(.subheadline.weight(.semibold)) }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .disabled(workspace.isLoadingMoreTrainings)
            }
        }
    }
}

private struct TrainingPresentation: Identifiable {
    let client: SchoolTrainingClient
    let learner: SchoolLearner
    let trainingID: UUID
    var id: UUID { trainingID }
}

private struct SchoolTrainingDetailView: View {
    @Bindable var workspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    if workspace.isLoadingTraining {
                        ProgressView("Ouverture de la formation…")
                    } else if let error = workspace.trainingError {
                        SchoolErrorNotice(message: error, retry: { Task { await workspace.loadSelectedTraining() } })
                    } else if let training = workspace.training {
                        Text("Permis \(training.categoryCode)").font(.drivyScreenTitle)
                        if let learner = workspace.learner { Text(learner.displayName).font(.title3) }
                        DrivyPanel {
                            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                                SchoolInfoRow(title: "État", value: SchoolPresentation.trainingStatus(training.status))
                                if let date = training.startedOn { SchoolInfoRow(title: "Début", value: SchoolPresentation.civilDate(date)) }
                                if let date = training.closedOn { SchoolInfoRow(title: "Fin", value: SchoolPresentation.civilDate(date)) }
                            }
                        }
                    } else {
                        ContentUnavailableView("Formation indisponible", systemImage: "doc.questionmark")
                    }
                }
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Formation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } }
            }
            .task(id: workspace.selectedTrainingID) { await workspace.loadSelectedTraining() }
        }
        .tint(DrivyTheme.accent)
    }
}

struct SchoolErrorNotice: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let retry { DrivyRetryButton(action: retry) }
        }
        .foregroundStyle(DrivyTheme.danger)
        .padding(DrivySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.dangerSurface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct SchoolInfoRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

enum SchoolPresentation {
    static func roles(_ codes: [String]) -> String {
        codes.map {
            switch $0 {
            case "ADMIN": "Administration"
            case "INSTRUCTOR": "Moniteur"
            case "LEARNER": "Élève"
            default: "Rôle à préciser"
            }
        }.joined(separator: " · ")
    }

    static func initials(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    static func trainingStatus(_ code: String) -> String {
        switch code {
        case "ACTIVE": "En cours"
        case "PAUSED": "En pause"
        case "COMPLETED": "Terminée"
        case "CANCELLED": "Annulée"
        default: "État à préciser"
        }
    }

    static func civilDate(_ value: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return "Date indisponible" }
        parser.locale = Locale(identifier: "fr_CH")
        parser.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return parser.string(from: date)
    }
}
