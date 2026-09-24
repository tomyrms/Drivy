import SwiftUI

struct SchoolBrowserView: View {
    @Bindable var workspace: SchoolWorkspace
    let openAccount: () -> Void
    var openInvitations: (() -> Void)? = nil
    var openProfile: ((SchoolLearner) -> Void)? = nil
    var openSchool: (() -> Void)? = nil
    var openTrainingAdministration: ((SchoolLearner) -> Void)? = nil
    var openPlanning: ((SchoolLearner) -> Void)? = nil
    @State private var choosesSchool = false

    var body: some View {
        NavigationSplitView {
            searchableMaster
            .background(DrivyTheme.canvas)
            .navigationTitle(workspace.isLearnerOnly ? "Mon dossier" : "Élèves")
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
                if let openInvitations {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: openInvitations) { Label("Invitations", systemImage: "envelope") }
                            .accessibilityIdentifier("open-school-invitations")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            if workspace.selectedLearnerID != nil {
                SchoolLearnerDetailView(workspace: workspace, openProfile: openProfile, openTrainingAdministration: openTrainingAdministration, openPlanning: openPlanning)
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

    @ViewBuilder private var searchableMaster: some View {
        if workspace.school?.status == "ACTIVE", !workspace.isLearnerOnly {
            masterColumn.searchable(text: Binding(get: { workspace.searchText }, set: { workspace.setSearchText($0) }),
                placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher un élève")
        } else {
            masterColumn
        }
    }

    private var masterColumn: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(workspace.school?.name ?? workspace.membership?.schoolName ?? "École")
                    .font(.subheadline.weight(.semibold))
                if let membership = workspace.membership {
                    Text(SchoolPresentation.roles(membership.roles))
                        .font(.caption).foregroundStyle(DrivyTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            learnerList
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
            if let school = workspace.school, school.status != "ACTIVE" {
                VStack(alignment: .leading, spacing: 14) {
                    Label(school.status == "ARCHIVED" ? "École archivée" : "L’école se prépare", systemImage: "building.2")
                        .font(.headline)
                    Text(school.status == "ARCHIVED"
                        ? "Cette école n’ouvre plus de nouvelles opérations. La carte reste disponible depuis Séance."
                        : "Les dossiers seront accessibles lorsque l’école sera active. Vous pouvez déjà ouvrir la carte depuis Séance.")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    if let openSchool {
                        Button("Ouvrir l’espace École", action: openSchool).frame(minHeight: 44)
                    }
                }
                .padding(.vertical, 16)
            } else if !workspace.isSearching && !workspace.isLoadingSchool && workspace.school != nil && workspace.learners.isEmpty && workspace.learnersError == nil {
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
                .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 20))
                .listRowBackground(workspace.selectedLearnerID == learner.id ? DrivyTheme.accentSoft : DrivyTheme.surface)
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
        .refreshable {
            guard workspace.school?.status == "ACTIVE" else { return }
            await workspace.searchLearners(workspace.searchText)
        }
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
                .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.text)
                .frame(width: 44, height: 44)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(learner.displayName).font(.headline)
                    .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.text)
                if let email = learner.contactEmail, !email.isEmpty {
                    Text(email).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                if learner.archivedAt != nil {
                    Label("Dossier archivé", systemImage: "archivebox")
                        .font(.caption).foregroundStyle(DrivyTheme.muted)
                } else if learner.profileReadiness == "MINIMAL" || learner.profileReadiness == "ACTION_REQUIRED" {
                    Text(learner.profileReadiness == "MINIMAL" ? "Profil à compléter" : "Informations à vérifier")
                        .font(.caption).foregroundStyle(DrivyTheme.muted)
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
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(DrivyTheme.muted)
                        .padding(24)
                        .background(DrivyTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 28))
                        .accessibilityHidden(true)
                    Text(workspace.isLearnerOnly ? "Votre dossier scolaire" : "Les dossiers de votre école")
                        .font(.largeTitle.weight(.bold))
                    Text(school.name).font(.headline).foregroundStyle(DrivyTheme.muted)
                    Text(workspace.isLearnerOnly
                        ? "Ouvrez votre dossier pour retrouver votre profil et vos formations."
                        : "Sélectionnez un élève dans la liste pour retrouver son profil, ses coordonnées et ses formations.")
                        .font(.title3).foregroundStyle(DrivyTheme.muted)
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
        .navigationTitle("Dossiers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SchoolLearnerDetailView: View {
    @Bindable var workspace: SchoolWorkspace
    let openProfile: ((SchoolLearner) -> Void)?
    let openTrainingAdministration: ((SchoolLearner) -> Void)?
    let openPlanning: ((SchoolLearner) -> Void)?
    @State private var showsTraining = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if workspace.isLoadingLearner {
                    ProgressView("Ouverture du dossier…").frame(maxWidth: .infinity, minHeight: 120)
                } else if let error = workspace.learnerError {
                    SchoolErrorNotice(message: error, retry: { Task { await workspace.loadSelectedLearner() } })
                } else if let learner = workspace.learner {
                    learnerHeading(learner)
                    if let openProfile {
                        Button { openProfile(learner) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "person.text.rectangle")
                                    .font(.title2).foregroundStyle(DrivyTheme.accent).frame(width: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Profil scolaire").font(.headline).foregroundStyle(DrivyTheme.text)
                                    Text(learner.profileReadiness == "MINIMAL" ? "Compléter les informations utiles" : "Consulter et mettre à jour")
                                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                            .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("open-learner-profile")
                    }
                    trainings
                    if learner.contactEmail != nil || learner.contactPhone != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Coordonnées").font(.title3.weight(.semibold))
                            DrivyPanel {
                                VStack(alignment: .leading, spacing: 20) {
                                    if let email = learner.contactEmail { SchoolInfoRow(title: "E-mail", value: email) }
                                    if learner.contactEmail != nil && learner.contactPhone != nil { Divider() }
                                    if let phone = learner.contactPhone { SchoolInfoRow(title: "Téléphone", value: phone) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
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

    private func learnerHeading(_ learner: SchoolLearner) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Text(SchoolPresentation.initials(learner.displayName))
                    .font(.title3.weight(.semibold))
                    .frame(width: 60, height: 60)
                    .background(DrivyTheme.surfaceMuted, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(learner.displayName).font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(workspace.school?.name ?? "Dossier scolaire")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
            }
            if learner.archivedAt != nil {
                Label("Dossier archivé", systemImage: "archivebox")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            } else if learner.profileReadiness == "MINIMAL" {
                Label("Profil à compléter", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var trainings: some View {
        DrivyPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Formations").font(.title3.weight(.semibold))
                if let learner = workspace.learner, let openPlanning, learner.archivedAt == nil {
                    Button { openPlanning(learner) } label: { Label("Planifier une leçon", systemImage: "calendar.badge.plus") }
                        .frame(minHeight: 48).accessibilityIdentifier("learner-plan-lesson")
                }
                if let learner = workspace.learner, let openTrainingAdministration, learner.archivedAt == nil {
                    Button { openTrainingAdministration(learner) } label: {
                        Label("Gérer les formations", systemImage: "person.badge.plus")
                    }
                    .frame(minHeight: 48)
                    .accessibilityIdentifier("manage-learner-trainings")
                }
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
                            Image(systemName: "steeringwheel")
                                .font(.title2).foregroundStyle(DrivyTheme.muted)
                                .frame(width: 40, height: 44)
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
        parser.locale = Locale(identifier: "fr_CH")
        parser.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return parser.string(from: date)
    }
}
