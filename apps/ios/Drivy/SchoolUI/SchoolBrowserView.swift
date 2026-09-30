import SwiftUI

/// Les élèves du moniteur : rechercher, inviter, ouvrir un dossier. La gestion administrative vit sur le web.
struct SchoolBrowserView: View {
    @Bindable var workspace: SchoolWorkspace
    let openAccount: () -> Void
    var chooseSchool: (() -> Void)? = nil
    var inviteLearner: (() -> Void)? = nil
    var openProfile: ((SchoolLearner) -> Void)? = nil
    var openPlanning: ((SchoolLearner) -> Void)? = nil
    var trainingClient: SchoolTrainingClient? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            searchableMaster
            .background(DrivyTheme.canvas)
            .navigationTitle("Élèves")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let chooseSchool {
                    DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName, chooseSchool: chooseSchool)
                }
                if let inviteLearner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: inviteLearner) { Label("Inviter un élève", systemImage: "person.badge.plus") }
                            .accessibilityIdentifier("add-school-learner")
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                DrivyAccountToolbarItem(openAccount: openAccount)
            }
            .navigationSplitViewColumnWidth(min: DrivyLayout.splitListMinWidth, ideal: DrivyLayout.splitListIdealWidth,
                max: DrivyLayout.splitListMaxWidth)
        } detail: {
            if workspace.selectedLearnerID != nil {
                SchoolLearnerDetailView(workspace: workspace, openProfile: openProfile, openPlanning: openPlanning, trainingClient: trainingClient)
            } else {
                SchoolOverviewView(workspace: workspace)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(DrivyTheme.accent)
    }

    @ViewBuilder private var searchableMaster: some View {
        if workspace.school?.status == "ACTIVE" {
            learnerList.searchable(text: Binding(get: { workspace.searchText }, set: { workspace.setSearchText($0) }),
                placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher un élève")
        } else {
            learnerList
        }
    }

    private var trimmedSearch: String { workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var learnerList: some View {
        List(selection: Binding(get: { workspace.selectedLearnerID }, set: { workspace.selectLearner($0) })) {
            if workspace.isLoadingSchool || workspace.isSearching {
                DrivyLoadingState(title: workspace.isSearching ? "Recherche des élèves…" : "Chargement des élèves…")
                    .listRowSeparator(.hidden)
                    .drivyFormRows()
            }
            if let error = workspace.schoolError {
                SchoolErrorNotice(message: error, retry: {
                    if let membership = workspace.membership { Task { await workspace.selectSchool(membership) } }
                })
                .listRowSeparator(.hidden)
                .drivyFormRows()
            } else if let error = workspace.learnersError {
                SchoolErrorNotice(message: error, retry: { Task { await workspace.searchLearners(workspace.searchText) } })
                    .listRowSeparator(.hidden)
                    .drivyFormRows()
            }
            if let school = workspace.school, school.status != "ACTIVE" {
                DrivyEmptyState(title: school.status == "ARCHIVED" ? "École archivée" : "L’école se prépare",
                    message: school.status == "ARCHIVED" ? "" : "Termine sa préparation sur le web.",
                    symbol: school.status == "ARCHIVED" ? "archivebox" : "building.2")
                    .listRowSeparator(.hidden)
                    .drivyFormRows()
            } else if !workspace.isSearching && !workspace.isLoadingSchool && workspace.school != nil && workspace.learners.isEmpty && workspace.learnersError == nil {
                emptyLearners
                    .buttonStyle(.borderless)
                    .listRowSeparator(.hidden)
                    .drivyFormRows()
            }
            ForEach(workspace.learners) { learner in
                NavigationLink(value: learner.id) {
                    SchoolLearnerRow(learner: learner, isSelected: workspace.selectedLearnerID == learner.id)
                }
                .accessibilityIdentifier("school-learner-\(learner.id.uuidString)")
                .listRowInsets(EdgeInsets(top: DrivySpacing.xxs, leading: DrivySpacing.m, bottom: DrivySpacing.xxs, trailing: DrivySpacing.m))
                .listRowSeparatorTint(DrivyTheme.border)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .drivyFormRows(isSelected: workspace.selectedLearnerID == learner.id)
            }
            if workspace.nextLearnersCursor != nil {
                Button { Task { await workspace.loadMoreLearners() } } label: {
                    DrivyBusyLabel(title: "Afficher d’autres élèves", busyTitle: "Chargement…", isBusy: workspace.isLoadingMoreLearners)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .disabled(workspace.isLoadingMoreLearners || workspace.isSearching)
                .accessibilityIdentifier("more-learners")
                .listRowSeparator(.hidden)
                .drivyFormRows()
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

    @ViewBuilder private var emptyLearners: some View {
        if !trimmedSearch.isEmpty {
            DrivyEmptyState(title: "Aucun résultat", symbol: "magnifyingglass",
                actionTitle: "Effacer la recherche", action: { workspace.setSearchText("") })
        } else if let inviteLearner {
            DrivyEmptyState(title: "Aucun élève", symbol: "person.2", actionTitle: "Inviter un élève", action: inviteLearner)
        } else {
            DrivyEmptyState(title: "Aucun élève", symbol: "person.2")
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
        DrivyEntityRow(title: learner.displayName, leading: .avatar(learner.displayName), badge: badge, isSelected: isSelected)
    }

    /// Seul ce qui demande une action reste en badge.
    private var badge: DrivyStatusBadge? {
        if learner.archivedAt != nil { return DrivyStatusBadge(title: "Archivé", symbol: "archivebox") }
        if learner.profileReadiness == "ACTION_REQUIRED" { return DrivyStatusBadge(title: "À vérifier", symbol: "exclamationmark.triangle", tone: .warning) }
        return nil
    }
}

/// Colonne de détail de l’iPad avant une sélection.
private struct SchoolOverviewView: View {
    @Bindable var workspace: SchoolWorkspace
    var body: some View {
        Group {
            if workspace.school != nil {
                ContentUnavailableView("Sélectionne un élève", systemImage: "person.text.rectangle")
            } else if workspace.isLoadingSchool {
                ProgressView("Chargement de l’école…")
            } else if let error = workspace.schoolError {
                SchoolErrorNotice(message: error, retry: {
                    if let membership = workspace.membership { Task { await workspace.selectSchool(membership) } }
                })
                .drivyPageContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.surface)
        .navigationTitle("Élèves")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SchoolLearnerDetailView: View {
    @Bindable var workspace: SchoolWorkspace
    let openProfile: ((SchoolLearner) -> Void)?
    let openPlanning: ((SchoolLearner) -> Void)?
    let trainingClient: SchoolTrainingClient?
    @State private var presentedTraining: TrainingPresentation?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A learner with one training: its lessons and progression are the dossier itself.
    private var singleTraining: SchoolTraining? {
        guard trainingClient != nil, !workspace.isLoadingTrainings, workspace.trainingsError == nil,
              workspace.nextTrainingsCursor == nil, workspace.trainings.count == 1,
              let training = workspace.trainings.first, training.learnerId == workspace.learner?.id else { return nil }
        return training
    }

    var body: some View {
        Group {
            if let learner = workspace.learner, let training = singleTraining, let trainingClient {
                SchoolTrainingScreen(client: trainingClient, workspace: workspace, learner: learner, trainingID: training.id)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let openPlanning, learner.archivedAt == nil {
                            DrivyStickyActionBar { planButton(learner, openPlanning: openPlanning) }
                        }
                    }
                    .toolbar {
                        if openProfile != nil || learner.contactEmail != nil || learner.contactPhone != nil {
                            ToolbarItem(placement: .topBarTrailing) { dossierMenu(learner) }
                        }
                    }
            } else {
                dossier
            }
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

    private func planButton(_ learner: SchoolLearner, openPlanning: @escaping (SchoolLearner) -> Void) -> some View {
        Button { openPlanning(learner) } label: { Label("Planifier une leçon", systemImage: "calendar.badge.plus") }
            .buttonStyle(DrivyPrimaryButtonStyle()).accessibilityIdentifier("learner-plan-lesson")
    }

    /// Profile and contacts of a single-training dossier, whose page is the training itself.
    private func dossierMenu(_ learner: SchoolLearner) -> some View {
        Menu {
            if let openProfile {
                Button { openProfile(learner) } label: {
                    Label(learner.profileReadiness == "ACTION_REQUIRED" ? "Profil · à vérifier" : "Profil", systemImage: "person.text.rectangle")
                }
            }
            if let phone = learner.contactPhone {
                if let url = SchoolContactLinks.call(phone) { Link(destination: url) { Label("Appeler", systemImage: "phone") } }
                if let url = SchoolContactLinks.message(phone) { Link(destination: url) { Label("Envoyer un message", systemImage: "message") } }
            }
            if let email = learner.contactEmail, let url = SchoolContactLinks.mail(email) {
                Link(destination: url) { Label("Envoyer un e-mail", systemImage: "envelope") }
            }
        } label: {
            Label("Profil et coordonnées", systemImage: learner.profileReadiness == "ACTION_REQUIRED" ? "exclamationmark.circle" : "ellipsis.circle")
        }
        .accessibilityIdentifier("learner-dossier-menu")
    }

    private var dossier: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                if workspace.isLoadingLearner {
                    DrivyLoadingState(title: "Chargement du dossier…")
                } else if let error = workspace.learnerError {
                    SchoolErrorNotice(message: error, retry: { Task { await workspace.loadSelectedLearner() } })
                } else if let learner = workspace.learner {
                    VStack(alignment: .leading, spacing: DrivySpacing.l) {
                        learnerHeading(learner)
                        if let openPlanning, learner.archivedAt == nil { planButton(learner, openPlanning: openPlanning) }
                    }
                    trainings
                    if let openProfile {
                        DrivyRowGroup {
                            DrivyNavigationRow(title: "Profil", symbol: "person.text.rectangle",
                                badge: learner.profileReadiness == "ACTION_REQUIRED"
                                    ? DrivyStatusBadge(title: "À vérifier", symbol: "exclamationmark.triangle", tone: .warning) : nil,
                                action: { openProfile(learner) })
                                .accessibilityIdentifier("open-learner-profile")
                        }
                    }
                    if learner.contactEmail != nil || learner.contactPhone != nil {
                        DrivyRowGroup(title: "Coordonnées") {
                            if let email = learner.contactEmail {
                                SchoolContactActionRow(title: "E-mail", value: email, symbol: "envelope",
                                    actions: SchoolContactActionRow.actions(email: email, name: learner.displayName))
                            }
                            if let phone = learner.contactPhone {
                                SchoolContactActionRow(title: "Téléphone", value: phone, symbol: "phone",
                                    actions: SchoolContactActionRow.actions(phone: phone, name: learner.displayName))
                            }
                        }
                    }
                }
            }
            .drivyPageContent()
        }
    }

    private func learnerHeading(_ learner: SchoolLearner) -> some View {
        HStack(alignment: .center, spacing: DrivySpacing.m) {
            if !dynamicTypeSize.isAccessibilitySize {
                DrivyAvatar(name: learner.displayName, size: 60)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(learner.displayName)
                    .font(.drivyScreenTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if learner.archivedAt != nil {
                    DrivyStatusBadge(title: "Archivé", symbol: "archivebox")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var trainings: some View {
        VStack(alignment: .leading, spacing: 0) {
            if workspace.isLoadingTrainings {
                DrivyLoadingState(title: "Chargement des formations…")
            }
            if let error = workspace.trainingsError {
                SchoolErrorNotice(message: error, retry: { Task { await workspace.loadTrainings() } })
                    .padding(.vertical, DrivySpacing.xs)
            }
            if !workspace.isLoadingTrainings && workspace.trainings.isEmpty && workspace.trainingsError == nil {
                DrivyEmptyState(title: "Aucune formation", message: "Ouvre-la sur le web.", symbol: "steeringwheel")
            }
            DrivyRowGroup(title: workspace.trainings.isEmpty ? nil : "Formation") {
                ForEach(workspace.trainings) { training in
                    DrivyNavigationRow(title: "Permis \(training.categoryCode)", symbol: "steeringwheel",
                        badge: training.status == "ACTIVE" ? nil : DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status)),
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
                    DrivyBusyLabel(title: "Afficher les autres formations", busyTitle: "Chargement…", isBusy: workspace.isLoadingMoreTrainings)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .disabled(workspace.isLoadingMoreTrainings)
            }
        }
    }
}

/// Contact value with its actions (call, message, e-mail) as 44 pt round buttons.
private struct SchoolContactActionRow: View {
    struct Action: Identifiable {
        let label: String
        let symbol: String
        let url: URL
        var id: String { url.absoluteString }
    }
    let title: String
    let value: String
    let symbol: String
    let actions: [Action]

    static func actions(email: String, name: String) -> [Action] {
        guard let url = SchoolContactLinks.mail(email) else { return [] }
        return [Action(label: "Envoyer un e-mail à \(name)", symbol: "envelope.fill", url: url)]
    }
    static func actions(phone: String, name: String) -> [Action] {
        var result: [Action] = []
        if let url = SchoolContactLinks.message(phone) { result.append(Action(label: "Envoyer un message à \(name)", symbol: "message.fill", url: url)) }
        if let url = SchoolContactLinks.call(phone) { result.append(Action(label: "Appeler \(name)", symbol: "phone.fill", url: url)) }
        return result
    }

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.s) {
            DrivyContactRow(title: title, value: value, symbol: symbol)
            ForEach(actions) { action in
                Link(destination: action.url) {
                    Image(systemName: action.symbol)
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(DrivyTheme.accentSoft, in: Circle())
                        .contentShape(Circle())
                }
                .foregroundStyle(DrivyTheme.accent)
                .accessibilityLabel(action.label)
            }
        }
    }
}

/// `tel:`, `sms:` and `mailto:` links built from what the school recorded, never guessed.
enum SchoolContactLinks {
    private static func dialable(_ phone: String) -> String? {
        let characters = phone.filter { ($0.isASCII && $0.isNumber) || $0 == "+" }
        let value = String(characters.prefix(1)) + characters.dropFirst().filter { $0 != "+" }
        return value.filter(\.isNumber).count >= 3 ? value : nil
    }
    static func call(_ phone: String) -> URL? { dialable(phone).flatMap { URL(string: "tel:\($0)") } }
    static func message(_ phone: String) -> URL? { dialable(phone).flatMap { URL(string: "sms:\($0)") } }
    static func mail(_ address: String) -> URL? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), !value.contains(where: \.isWhitespace) else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = value
        return components.url
    }
}

private struct TrainingPresentation: Identifiable {
    let client: SchoolTrainingClient
    let learner: SchoolLearner
    let trainingID: UUID
    var id: UUID { trainingID }
}

struct SchoolErrorNotice: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if let retry { DrivyRetryButton(action: retry) }
        }
        .foregroundStyle(DrivyTheme.danger)
        .padding(DrivySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.dangerSurface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .accessibilityElement(children: .contain)
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
