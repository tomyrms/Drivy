import SwiftUI

struct SchoolBrowserView: View {
    @Bindable var workspace: SchoolWorkspace
    let openAccount: () -> Void
    @State private var choosesSchool = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workspace.school?.name ?? workspace.membership?.schoolName ?? "École")
                        .font(.headline)
                    if let membership = workspace.membership {
                        Text(SchoolPresentation.roles(membership.roles))
                            .font(.subheadline)
                            .foregroundStyle(DrivyTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                learnerList
            }
            .background(DrivyTheme.canvas)
            .navigationTitle(workspace.isLearnerOnly ? "Mon dossier" : "Élèves")
            .searchable(text: Binding(get: { workspace.searchText }, set: { workspace.setSearchText($0) }), prompt: "Rechercher un nom")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { choosesSchool = true } label: {
                        Label("Écoles", systemImage: "building.2")
                    }
                    .accessibilityIdentifier("choose-school")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openAccount) { Label("Compte", systemImage: "person.crop.circle") }
                        .accessibilityIdentifier("school-account")
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            if workspace.selectedLearnerID != nil {
                SchoolLearnerDetailView(workspace: workspace)
            } else {
                SchoolOverviewView(workspace: workspace)
            }
        }
        .sheet(isPresented: $choosesSchool) {
            NavigationStack {
                SchoolChooserView(workspace: workspace, onSelect: { choosesSchool = false })
                    .navigationTitle("Mes écoles")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fermer") { choosesSchool = false }
                        }
                    }
            }
        }
    }

    private var learnerList: some View {
        List(selection: Binding(get: { workspace.selectedLearnerID }, set: { workspace.selectLearner($0) })) {
            if workspace.isLoadingSchool || workspace.isSearching {
                ProgressView(workspace.isLoadingSchool ? "Ouverture de l’école…" : "Recherche en cours…")
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            if let error = workspace.schoolError {
                SchoolErrorNotice(message: error, retry: {
                    if let membership = workspace.membership { Task { await workspace.selectSchool(membership) } }
                })
            } else if let error = workspace.learnersError {
                SchoolErrorNotice(message: error, retry: { Task { await workspace.searchLearners(workspace.searchText) } })
            }
            if !workspace.isSearching && !workspace.isLoadingSchool && workspace.school != nil && workspace.learners.isEmpty && workspace.learnersError == nil {
                ContentUnavailableView(
                    workspace.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Aucun dossier accessible" : "Aucun résultat",
                    systemImage: "person.crop.rectangle.stack",
                    description: Text(workspace.searchText.isEmpty ? "Les dossiers autorisés par votre école apparaîtront ici." : "Essayez un autre nom ou effacez la recherche.")
                )
            }
            ForEach(workspace.learners) { learner in
                NavigationLink(value: learner.id) {
                    SchoolLearnerRow(learner: learner, isSelected: workspace.selectedLearnerID == learner.id)
                }
                .accessibilityIdentifier("school-learner-\(learner.id.uuidString)")
            }
            if workspace.nextLearnersCursor != nil {
                Button { Task { await workspace.loadMoreLearners() } } label: {
                    if workspace.isLoadingMoreLearners { ProgressView("Chargement…") }
                    else { Text("Afficher la suite") }
                }
                .frame(minHeight: 48)
                .disabled(workspace.isLoadingMoreLearners || workspace.isSearching)
                .accessibilityIdentifier("more-learners")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await workspace.searchLearners(workspace.searchText) }
    }
}

struct SchoolChooserView: View {
    @Bindable var workspace: SchoolWorkspace
    var onSelect: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                ForEach(workspace.person?.memberships ?? []) { membership in
                    Button {
                        workspace.leaveSchool()
                        onSelect?()
                        Task { await workspace.selectSchool(membership) }
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "building.2")
                                .foregroundStyle(DrivyTheme.accent)
                                .frame(width: 44, height: 44)
                                .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(membership.schoolName).font(.headline).foregroundStyle(DrivyTheme.text)
                                Text(SchoolPresentation.roles(membership.roles))
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").foregroundStyle(DrivyTheme.muted)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("school-choice-\(membership.schoolId.uuidString)")
                }
            } header: {
                Text("Choisissez votre école")
            }
        }
        .scrollContentBackground(.hidden)
        .background(DrivyTheme.canvas)
    }
}

private struct SchoolLearnerRow: View {
    let learner: SchoolLearner
    let isSelected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(SchoolPresentation.initials(learner.displayName))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? DrivyTheme.onAccent : DrivyTheme.text)
                .frame(width: 44, height: 44)
                .background(isSelected ? DrivyTheme.onAccent.opacity(0.16) : DrivyTheme.surfaceMuted, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(learner.displayName).font(.headline)
                    .foregroundStyle(isSelected ? DrivyTheme.onAccent : DrivyTheme.text)
                if let email = learner.contactEmail, !email.isEmpty {
                    Text(email).font(.subheadline).foregroundStyle(isSelected ? DrivyTheme.onAccent : DrivyTheme.muted)
                }
                if learner.archivedAt != nil {
                    Label("Dossier archivé", systemImage: "archivebox")
                        .font(.caption).foregroundStyle(isSelected ? DrivyTheme.onAccent : DrivyTheme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct SchoolOverviewView: View {
    @Bindable var workspace: SchoolWorkspace
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let school = workspace.school {
                    Image(systemName: "building.2")
                        .font(.largeTitle).foregroundStyle(DrivyTheme.accent).accessibilityHidden(true)
                    Text(school.name).font(.largeTitle.weight(.bold))
                    Text("Choisissez un dossier pour consulter ses informations et ses formations.")
                        .foregroundStyle(DrivyTheme.muted)
                    DrivyPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Contacter l’école").font(.headline)
                            SchoolInfoRow(title: "E-mail", value: school.contactEmail)
                            if let phone = school.contactPhone { SchoolInfoRow(title: "Téléphone", value: phone) }
                        }
                    }
                } else if workspace.isLoadingSchool {
                    ProgressView("Ouverture de l’école…")
                } else if let error = workspace.schoolError {
                    SchoolErrorNotice(message: error, retry: {
                        if let membership = workspace.membership { Task { await workspace.selectSchool(membership) } }
                    })
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Mon école")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SchoolLearnerDetailView: View {
    @Bindable var workspace: SchoolWorkspace
    @State private var showsTraining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if workspace.isLoadingLearner {
                    ProgressView("Ouverture du dossier…").frame(maxWidth: .infinity, minHeight: 120)
                } else if let error = workspace.learnerError {
                    SchoolErrorNotice(message: error, retry: { Task { await workspace.loadSelectedLearner() } })
                } else if let learner = workspace.learner {
                    Text(learner.displayName).font(.largeTitle.weight(.bold))
                    if learner.archivedAt != nil {
                        Label("Dossier archivé", systemImage: "archivebox").foregroundStyle(DrivyTheme.muted)
                    }
                    if learner.contactEmail != nil || learner.contactPhone != nil {
                        DrivyPanel {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Coordonnées").font(.headline)
                                if let email = learner.contactEmail { SchoolInfoRow(title: "E-mail", value: email) }
                                if let phone = learner.contactPhone { SchoolInfoRow(title: "Téléphone", value: phone) }
                            }
                        }
                    }
                    trainings
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(DrivyTheme.canvas)
        .navigationTitle("Dossier")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workspace.selectedLearnerID) { await workspace.loadSelectedLearner() }
        .sheet(isPresented: $showsTraining, onDismiss: { workspace.selectTraining(nil) }) {
            SchoolTrainingDetailView(workspace: workspace)
        }
    }

    private var trainings: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Formations").font(.title3.weight(.semibold))
                if workspace.isLoadingTrainings { ProgressView("Chargement des formations…") }
                if let error = workspace.trainingsError {
                    SchoolErrorNotice(message: error, retry: { Task { await workspace.loadTrainings() } })
                }
                if !workspace.isLoadingTrainings && workspace.trainings.isEmpty && workspace.trainingsError == nil {
                    Text("Aucune formation accessible dans ce dossier.")
                        .foregroundStyle(DrivyTheme.muted)
                }
                ForEach(workspace.trainings) { training in
                    Button {
                        workspace.selectTraining(training.id)
                        showsTraining = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "steeringwheel").foregroundStyle(DrivyTheme.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Catégorie \(training.categoryCode)").font(.headline)
                                Text(SchoolPresentation.trainingStatus(training.status))
                                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").foregroundStyle(DrivyTheme.muted)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("school-training-\(training.id.uuidString)")
                    if training.id != workspace.trainings.last?.id { Divider() }
                }
                if workspace.nextTrainingsCursor != nil {
                    Button { Task { await workspace.loadMoreTrainings() } } label: {
                        if workspace.isLoadingMoreTrainings { ProgressView("Chargement…") }
                        else { Text("Afficher les autres formations") }
                    }
                    .frame(minHeight: 48)
                    .disabled(workspace.isLoadingMoreTrainings)
                }
            }
        }
    }
}

private struct SchoolTrainingDetailView: View {
    @Bindable var workspace: SchoolWorkspace
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if workspace.isLoadingTraining {
                        ProgressView("Ouverture de la formation…")
                    } else if let error = workspace.trainingError {
                        SchoolErrorNotice(message: error, retry: { Task { await workspace.loadSelectedTraining() } })
                    } else if let training = workspace.training {
                        Text("Catégorie \(training.categoryCode)").font(.largeTitle.weight(.bold))
                        if let learner = workspace.learner { Text(learner.displayName).font(.title3) }
                        DrivyPanel {
                            VStack(alignment: .leading, spacing: 16) {
                                SchoolInfoRow(title: "État", value: SchoolPresentation.trainingStatus(training.status))
                                if let date = training.startedOn { SchoolInfoRow(title: "Début", value: SchoolPresentation.civilDate(date)) }
                                if let date = training.closedOn { SchoolInfoRow(title: "Fin", value: SchoolPresentation.civilDate(date)) }
                            }
                        }
                    } else {
                        ContentUnavailableView("Formation indisponible", systemImage: "doc.questionmark")
                    }
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(DrivyTheme.canvas)
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
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(DrivyTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Réessayer", action: retry)
                    .buttonStyle(.bordered)
                    .tint(DrivyTheme.danger)
                    .frame(minHeight: 48)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.dangerSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SchoolInfoRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        parser.locale = .autoupdatingCurrent
        parser.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return parser.string(from: date)
    }
}
