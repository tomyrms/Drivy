import SwiftUI

/// Les élèves du moniteur : rechercher, inviter, ouvrir un dossier. La gestion administrative vit sur le web.
struct SchoolBrowserView: View {
    @Bindable var workspace: SchoolWorkspace
    /// Nil pour le moniteur et l’administration : leur compte vit dans l’onglet Profil.
    var openAccount: (() -> Void)? = nil
    var chooseSchool: (() -> Void)? = nil
    var inviteLearner: (() -> Void)? = nil
    var openProfile: ((SchoolLearner) -> Void)? = nil
    var makeLearnerProfile: ((SchoolLearner) -> SchoolProfileWorkspace?)? = nil
    var openPlanning: ((SchoolLearner) -> Void)? = nil
    var trainingClient: SchoolTrainingClient? = nil
    var agendaClient: SchoolAgendaClient? = nil
    var captureController: SchoolCaptureSessionController? = nil
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
                if let openAccount { DrivyAccountToolbarItem(openAccount: openAccount) }
            }
            .navigationSplitViewColumnWidth(min: DrivyLayout.splitListMinWidth, ideal: DrivyLayout.splitListIdealWidth,
                max: DrivyLayout.splitListMaxWidth)
        } detail: {
            if workspace.selectedLearnerID != nil {
                SchoolLearnerDossierView(workspace: workspace, openProfile: openProfile, makeLearnerProfile: makeLearnerProfile,
                    openPlanning: openPlanning, trainingClient: trainingClient,
                    agendaClient: agendaClient, captureController: captureController)
                    .id(detailScopeKey)
            } else {
                SchoolOverviewView(workspace: workspace)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(DrivyTheme.accent)
    }

    /// A pushed page always belongs to the selected learner and the current school rights.
    private var detailScopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(workspace.selectedLearnerID?.uuidString ?? "")"
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
            if (workspace.isLoadingSchool || workspace.isSearching) && workspace.learners.isEmpty {
                DrivySkeletonRows(count: 5, leading: .avatar)
                    .drivySkeleton(workspace.isSearching ? "Recherche des élèves…" : "Chargement des élèves…")
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
                .onAppear { Task { await workspace.loadMoreLearners() } }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
    }
}

struct SchoolChooserView: View {
    @Bindable var workspace: SchoolWorkspace
    var onSelect: (() -> Void)? = nil

    var body: some View {
        ScrollView { choices }
            .scrollBounceBehavior(.basedOnSize)
            .background(DrivyTheme.surface)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            ForEach(workspace.person?.memberships ?? []) { membership in
                let isCurrent = workspace.membership?.membershipId == membership.membershipId
                Button {
                    // L’école déjà ouverte : on ferme sans tout reconstruire.
                    guard !isCurrent else { onSelect?(); return }
                    workspace.leaveSchool()
                    onSelect?()
                    Task { await workspace.selectSchool(membership) }
                } label: {
                    // Pas de symbole d’école sur chaque choix : la coche porte l’école ouverte.
                    HStack(spacing: DrivySpacing.m) {
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
}

private struct SchoolLearnerRow: View {
    let learner: SchoolLearner
    let isSelected: Bool

    var body: some View {
        DrivyEntityRow(title: learner.displayName, leading: .avatar(learner.displayName), badge: badge, isSelected: isSelected)
    }

    /// Seul ce qui demande une action reste en badge.
    private var badge: DrivyStatusBadge? {
        if learner.archivedAt != nil { return DrivyStatusBadge(title: "Archivé") }
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
                DrivySkeletonRows(count: 3, leading: .avatar)
                    .drivySkeleton("Chargement de l’école…")
                    .drivyPageContent()
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

/// `tel:`, `sms:` and `mailto:` links built from what the school recorded, never guessed.
enum SchoolContactLinks {
    private static func dialable(_ phone: String) -> String? {
        // Remove formatting only. A note, extension or misplaced + is not a new
        // number: keep the recorded contact readable without offering a wrong call.
        guard phone.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "+" || $0.isWhitespace || "().-".contains($0) }) else { return nil }
        let value = phone.filter { !$0.isWhitespace && !"().-".contains($0) }
        guard !value.dropFirst().contains("+") else { return nil }
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
