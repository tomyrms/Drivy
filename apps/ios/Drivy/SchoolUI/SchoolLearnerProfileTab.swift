import SwiftUI

/// Ce que l’onglet Profil de l’élève ouvre dans sa propre pile.
enum SchoolLearnerProfileRoute: Hashable {
    case settings
    case permit(UUID)
    case trips
}

/// L’onglet Profil de l’élève : qui il est et dans quelle école, ses permis en une liste, et l’accès à
/// « Mon profil » et aux paramètres. Le détail vit ailleurs : les séances dans Leçons, les compétences dans
/// Progression, le compte dans Paramètres. Les formations sont celles des onglets Leçons et Progression (mêmes
/// modèles partagés, toutes leçons lues) : rien n’est relu en double, et aucun chiffre n’est donné tant que
/// l’historique n’est pas complet.
struct SchoolLearnerProfileTab: View {
    @Bindable var workspace: SchoolWorkspace
    /// Le dossier de l’élève ; `nil` tant que l’école ne l’a pas ouvert (le compte reste accessible).
    let learner: SchoolLearner?
    /// Ses formations, celle en cours d’abord.
    let trainings: [SchoolTraining]
    let account: SchoolAccountActions?
    let agendaClient: SchoolAgendaClient?
    let trainingClient: SchoolTrainingClient?
    var chooseSchool: (() -> Void)? = nil
    /// Ouvre l’onglet Leçons ou Progression sur ce permis.
    var openTraining: ((UUID, SchoolHomeTab) -> Void)? = nil
    /// Relit le dossier quand il n’a pas pu être lu.
    var retryDossier: (() -> Void)? = nil
    /// L’accord GPS général de l’élève, tenu par les onglets : le point de Profil s’allume avant que la page soit
    /// ouverte, et la page relit le même modèle. Le Profil n’en dit que ce qui attend une réponse.
    @Binding var consent: SchoolRecordingChoiceWorkspace?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SchoolCaptureSessionController.self) private var capture: SchoolCaptureSessionController?
    @State private var models: [SchoolTrainingWorkspace] = []
    /// Affectations de chaque formation ; une lecture refusée ou en panne n’affiche simplement pas de moniteur.
    @State private var assignments: [UUID: [SchoolAssignment]] = [:]
    @State private var path: [SchoolLearnerProfileRoute] = []

    private var accountKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)"
    }
    private var scopeKey: String {
        "\(accountKey):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(learner?.id.uuidString ?? ""):\(trainings.map { $0.id.uuidString }.joined(separator: ",")):\(recordsTrips)"
    }
    private var scope: SchoolCommandScope? {
        guard let person = workspace.person, let membership = workspace.membership, let trainingClient else { return nil }
        return SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId, membershipID: membership.membershipId,
            accessEpoch: membership.accessEpoch, apiBaseURL: trainingClient.baseURL.absoluteString)
    }
    /// Trajets et accord GPS n’ont de sens que dans une école qui enregistre des trajets.
    private var recordsTrips: Bool { workspace.school?.status == "ACTIVE" && workspace.school?.modules.gpsEnabled == true }
    /// Ce qui fait apparaître la synthèse d’un permis : elle arrive en fondu, à la place de son attente.
    private var readyKey: String { models.map { "\($0.trainingID):\(Self.isComplete($0))" }.joined(separator: ",") }

    var body: some View {
        NavigationStack(path: $path) {
            List { content }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: DrivyLayout.formColumn)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.canvas)
                .animation(DrivyMotion.reveal(reduceMotion), value: readyKey)
                .animation(DrivyMotion.reveal(reduceMotion), value: consentAttention)
                .refreshable { await refresh(olderThan: 0) }
                .navigationTitle("Profil")
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbar }
                .navigationDestination(for: SchoolLearnerProfileRoute.self) { destination($0) }
                .accessibilityIdentifier("learner-profile-list")
        }
        .id(accountKey)
        .task(id: scopeKey) { await prepare() }
        .onChange(of: accountKey) { _, _ in path = [] }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh(olderThan: 30) } }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let chooseSchool {
            DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName,
                chooseSchool: chooseSchool)
        }
        if account != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button { path.append(.settings) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Paramètres")
                    .accessibilityIdentifier("profile-open-settings")
            }
        }
    }

    // MARK: Page

    /// Identité, permis, puis seulement ce qui attend une réponse.
    @ViewBuilder private var content: some View {
        // Le même en-tête que le Profil du moniteur : posé sur le fond, pas dans une cellule.
        Section {
            SchoolAccountHeading(workspace: workspace, isAuthenticated: true, detail: schoolNote, showsRoles: false)
        }
        .listRowInsets(EdgeInsets(top: DrivySpacing.s, leading: DrivySpacing.m, bottom: DrivySpacing.s, trailing: DrivySpacing.m))
        .drivyClearRow()
        if let openProfile = account?.openProfile {
            // « Mon profil » : la même page que dans Paramètres, compte Drivy et dossier de l’école réunis.
            Section {
                DrivyNavigationRow(title: "Mon profil", action: openProfile)
                    .listRowInsets(rowInsets)
                    .accessibilityIdentifier("profile-open-my-profile")
            }
            .drivyFormRows()
        }
        Section {
            permits
        } header: {
            Text(trainings.count == 1 ? "Mon permis" : "Mes permis").drivyFormSectionHeader()
        }
        .drivyFormRows()
        if let resumeOnboarding = account?.resumeOnboarding {
            // L’accueil laissé en route : la ligne que le point de l’onglet désigne, avant tout le reste à faire.
            Section {
                DrivyNavigationRow(title: "Reprendre l’accueil", badge: DrivyStatusBadge(title: "À terminer", tone: .accent),
                                   action: resumeOnboarding)
                    .listRowInsets(rowInsets)
                    .accessibilityIdentifier("profile-resume-onboarding")
            }
            .drivyFormRows()
        }
        if let attention = consentAttention {
            // Ce qui attend une réponse se lit comme partout : un badge d’alerte sur la ligne qui y mène.
            Section {
                // Ce qui attend l’élève se lit en bleu : c’est une action, pas une alerte.
                DrivyNavigationRow(title: "Accord GPS", badge: DrivyStatusBadge(title: attention, tone: .accent)) {
                    path.append(.settings)
                }
                .listRowInsets(rowInsets)
                .accessibilityIdentifier("profile-gps-consent-attention")
            }
            .drivyFormRows()
        }
    }

    /// Les rangées partagées portent leur espacement vertical : la liste ne le double pas.
    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m) }

    /// Sous le nom de l’école, seulement quand elle n’est pas en activité.
    private var schoolNote: String? {
        guard let status = workspace.school?.status, status != "ACTIVE" else { return nil }
        return status == "ARCHIVED" ? "École archivée" : "École en préparation"
    }

    /// Une ligne par permis ; sans permis, une phrase dit pourquoi, sans prendre la page.
    @ViewBuilder private var permits: some View {
        if !trainings.isEmpty {
            let names = SchoolPermitName.names(trainings)
            ForEach(trainings) { training in
                let model = models.first { $0.trainingID == training.id }
                NavigationLink(value: SchoolLearnerProfileRoute.permit(training.id)) {
                    SchoolLearnerPermitRow(title: names[training.id] ?? "Permis \(training.categoryCode)",
                        code: training.categoryCode, summary: Self.summary(training: training, model: model))
                }
                .accessibilityIdentifier("profile-permit-\(training.id.uuidString)")
            }
            // Une lecture en panne se dit une fois pour la section ; les permis lus restent consultables.
            let failed = models.filter { $0.errorMessage != nil }
            if let message = failed.first?.errorMessage {
                SchoolErrorNotice(message: message, retry: {
                    Task { await SchoolLessonFeed.together(failed) { await $0.load(keepingCurrent: true) } }
                })
            }
        } else if let error = workspace.learnersError ?? workspace.learnerError ?? workspace.trainingsError {
            SchoolErrorNotice(message: error, retry: retryDossier)
        } else if workspace.isSearching || workspace.isLoadingLearner || workspace.isLoadingTrainings
                    || (learner != nil && workspace.learner == nil) {
            DrivySkeletonRow(lines: 2).drivySkeleton("Chargement de tes permis…")
        } else {
            Text(learner == nil ? "Ton école n’a pas encore ouvert ton dossier." : "Aucune formation pour l’instant.")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
                .accessibilityIdentifier("profile-no-permit")
        }
    }

    /// Ce que le Profil dit de l’accord GPS : rien tant qu’il est donné ou simplement pas encore lu.
    private var consentAttention: String? {
        guard recordsTrips, let consent else { return nil }
        return consent.learnerAttention
    }

    // MARK: Destinations

    @ViewBuilder private func destination(_ route: SchoolLearnerProfileRoute) -> some View {
        switch route {
        case .settings:
            if let account {
                SchoolLearnerSettingsView(workspace: workspace, account: account, recording: recording)
            }
        case .permit(let id):
            if let model = models.first(where: { $0.trainingID == id }) {
                let training = model.training ?? trainings.first(where: { $0.id == id })
                SchoolLearnerPermitDetail(title: permitTitle(id, training: training), training: training, model: model,
                    assignments: assignments[id], open: opener(id))
            } else {
                ContentUnavailableView("Formation indisponible", systemImage: "steeringwheel")
            }
        case .trips:
            if let agendaClient {
                SchoolLearnerTripsView(workspace: workspace, agendaClient: agendaClient)
            }
        }
    }

    private func permitTitle(_ id: UUID, training: SchoolTraining?) -> String {
        if let name = SchoolPermitName.names(trainings)[id] { return name }
        return training.map { "Permis \($0.categoryCode)" } ?? "Formation"
    }

    /// Leçons ou Progression, sur ce permis.
    private func opener(_ id: UUID) -> ((SchoolHomeTab) -> Void)? {
        guard let openTraining else { return nil }
        return { tab in openTraining(id, tab) }
    }

    private var recording: SchoolLearnerSettingsView.Recording? {
        guard recordsTrips, let agendaClient else { return nil }
        return .init(agenda: agendaClient, scope: scope, learnerID: learner?.id, consent: consent)
    }

    // MARK: Lecture

    private static func isComplete(_ model: SchoolTrainingWorkspace) -> Bool {
        model.lessonsLoaded && model.nextCursor == nil && model.training != nil
    }

    /// La ligne de synthèse d’un permis : son état s’il est inhabituel, puis ses leçons une fois toutes lues.
    private static func summary(training: SchoolTraining, model: SchoolTrainingWorkspace?) -> SchoolLearnerPermitRow.Summary {
        let status = training.status == "ACTIVE" ? nil : SchoolPresentation.trainingStatus(training.status)
        guard let model else { return .loading }
        if isComplete(model) {
            let lessons = SchoolTrainingOverview.make(lessons: model.lessons, progress: model.progress).summary
            return .ready([status, lessons].compactMap { $0 }.joined(separator: " · "))
        }
        return model.errorMessage == nil ? .loading : .ready(status ?? "Leçons non lues")
    }

    /// Les modèles partagés avec Leçons et Progression : un nouveau se lit, un modèle connu ne se relit que s’il date.
    private func prepare() async {
        guard let learner, let membership = workspace.membership, let trainingClient, let scope else {
            models = []; assignments = [:]; consent?.invalidate(); consent = nil; return
        }
        let shared = trainings.map {
            SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner.id, trainingID: $0.id, client: trainingClient)
        }
        models = shared.map { $0.model }
        models.forEach { $0.requestWholeHistory() }
        let fresh = Set(shared.filter { $0.isNew }.map { $0.model.trainingID })
        let ids = trainings.map { $0.id }
        let schoolID = membership.schoolId
        let reading = Task { await loadAssignments(ids, schoolID: schoolID) }
        let asking = Task { await prepareConsent(scope: scope, learnerID: learner.id) }
        await SchoolLessonFeed.together(models) { model in
            if fresh.contains(model.trainingID) { await model.load() } else { await model.refresh(ifOlderThan: 30) }
        }
        // Annulées avec l’écran : une lecture d’un autre compte ou d’une autre école n’écrit rien ici.
        await withTaskCancellationHandler { await reading.value; await asking.value } onCancel: { reading.cancel(); asking.cancel() }
    }

    /// Le choix général de l’élève : celui qui vaut pour ses prochaines leçons, même sans leçon planifiée.
    private func prepareConsent(scope: SchoolCommandScope, learnerID: UUID) async {
        guard recordsTrips, let agendaClient else { consent?.invalidate(); consent = nil; return }
        if let consent, consent.scope == scope, consent.learnerID == learnerID, !consent.accessRevoked {
            if consent.needsReload, !consent.isLoading, !consent.isBusy { await consent.load() }
            return
        }
        consent?.invalidate()
        let model = SchoolOwnRecordingChoice.makeModel(scope: scope, lessonID: nil, learnerID: learnerID,
            agenda: agendaClient, capture: capture)
        consent = model
        await model.load()
    }

    private func refresh(olderThan interval: TimeInterval) async {
        await SchoolLessonFeed(models: models).reload(ifOlderThan: interval)
    }

    /// Le moniteur affecté se lit sur la formation ; son nom vient de ses leçons, jamais d’un annuaire de l’équipe.
    private func loadAssignments(_ ids: [UUID], schoolID: UUID) async {
        guard let agendaClient else { return }
        let client = agendaClient.planningClient
        var result: [UUID: [SchoolAssignment]] = [:]
        for id in ids {
            do {
                let records: [SchoolAssignment] = try await client.records(schoolID, path: ["trainings", id.uuidString, "assignments"])
                result[id] = records.filter { $0.trainingId == id }
            } catch { continue }
        }
        guard !Task.isCancelled else { return }
        assignments = result
    }
}

/// Ce que le Profil signale de l’accord GPS, hors de la vue : la règle se teste telle quelle.
enum SchoolRecordingChoiceAttention {
    /// `nil` : rien à traiter (accord donné, pas encore lu, ou accès retiré). Une lecture en panne ne se montre
    /// pas ici : elle se lit dans Paramètres, à côté de l’accord, avec « Réessayer ».
    static func label(notice: Bool, revoked: Bool, pending: Bool, answered: Bool) -> String? {
        guard notice, !revoked else { return nil }
        if pending { return "À vérifier" }
        return answered ? nil : "À donner"
    }
}

/// Un permis dans la liste du Profil : son nom, puis une ligne de synthèse. L’attente garde la hauteur de la
/// ligne, la synthèse la remplace sans pousser la page.
struct SchoolLearnerPermitRow: View {
    enum Summary: Equatable { case loading, ready(String) }

    let title: String
    var code: String? = nil
    let summary: Summary
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.s) {
            // Le véhicule du permis, comme la pastille d’une DrivyEntityRow ; en très grand texte, le nom suffit.
            if let code, !typeSize.isAccessibilitySize { DrivyLicenseTile(code: code) }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                switch summary {
                case .loading:
                    Text("0 leçon terminée · 0 h 00")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .redacted(reason: .placeholder)
                case .ready(let text):
                    Text(text)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(DrivyTheme.muted)
                        .transition(.opacity)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, DrivySpacing.xxs)
        .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenSummary)
    }

    private var spokenSummary: String {
        switch summary {
        case .loading: "Chargement"
        case .ready(let text): text
        }
    }
}

/// Ce que le profil dit d’une formation, calculé sur toutes ses leçons lues. Aucun score : un nombre de leçons, le
/// temps passé en leçon (horaires réels déclarés par le moniteur, jamais déduits du GPS), un décompte de compétences.
struct SchoolTrainingOverview: Equatable {
    let completedLessons: Int
    let lessonMinutes: Int
    let lastCompleted: SchoolLesson?
    /// Compétences en autonomie et nombre de compétences du référentiel ; `nil` tant que la progression n’est pas lue.
    let independent: Int?
    let competencies: Int?

    static func make(lessons: [SchoolLesson], progress: SchoolReportProgress?) -> SchoolTrainingOverview {
        let completed = lessons.filter { $0.status == "COMPLETED" }
        var minutes = 0
        for lesson in completed {
            // Une leçon dont l’horaire réel a été retiré (correction de l’école) ne compte pas dans le temps.
            guard let start = lesson.actualStart.flatMap({ SchoolLesson.date($0) }),
                  let end = lesson.actualEnd.flatMap({ SchoolLesson.date($0) }), end > start else { continue }
            minutes += Int((end.timeIntervalSince(start) / 60).rounded())
        }
        let last = completed.max { endOf($0) < endOf($1) }
        return SchoolTrainingOverview(completedLessons: completed.count, lessonMinutes: minutes, lastCompleted: last,
            independent: progress.map { value in value.items.filter { $0.level == "INDEPENDENT" }.count },
            competencies: progress.map { $0.items.count + $0.unobservedCompetencyIds.count })
    }

    private static func endOf(_ lesson: SchoolLesson) -> Date {
        lesson.actualEnd.flatMap { SchoolLesson.date($0) } ?? lesson.endsAt ?? .distantPast
    }

    /// « 45 min », « 12 h », « 35 h 10 ».
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, rest)
    }

    /// Leçons et temps en une ligne : « 12 leçons terminées · 14 h 30 ». Le temps manque quand aucun horaire réel
    /// n’est connu ; il n’est jamais remplacé par l’horaire prévu.
    var summary: String {
        guard completedLessons > 0 else { return "Aucune leçon terminée" }
        let lessons = completedLessons == 1 ? "1 leçon terminée" : "\(completedLessons) leçons terminées"
        return lessonMinutes > 0 ? "\(lessons) · \(Self.duration(lessonMinutes))" : lessons
    }

    /// « 8 sur 31 compétences en autonomie » : un décompte du référentiel, ni un score ni un permis obtenu.
    /// `nil` tant que la progression n’est pas lue ou que le référentiel est vide.
    var autonomySummary: String? {
        guard let independent, let competencies, competencies > 0 else { return nil }
        return "\(independent) sur \(competencies) compétences en autonomie"
    }

    /// Moniteurs que l’école affecte aujourd’hui à la formation, nommés par la plus récente de leurs leçons, dans
    /// l’ordre alphabétique. Un moniteur sans leçon lue n’est pas nommé : l’élève ne lit pas l’équipe de l’école, et
    /// rien n’est deviné. Ce n’est pas un moniteur référent : d’autres peuvent donner des leçons.
    static func assignedInstructors(assignments: [SchoolAssignment], lessons: [SchoolLesson], now: Date) -> [String] {
        let current = assignments.filter { assignment in
            guard let from = SchoolLesson.date(assignment.validFrom), from <= now else { return false }
            guard let until = assignment.validUntil else { return true }
            return SchoolLesson.date(until).map { $0 > now } ?? false
        }
        var names: [String] = []
        for id in Set(current.map { $0.instructorMembershipId }) {
            let latest = lessons.filter { $0.instructorMembershipId == id && $0.providedInstructorName != nil }
                .max { ($0.startsAt ?? .distantPast) < ($1.startsAt ?? .distantPast) }
            if let name = latest?.providedInstructorName, !names.contains(name) { names.append(name) }
        }
        return names.sorted { $0.localizedCompare($1) == .orderedAscending }
    }
}

extension SchoolRecordingChoiceWorkspace {
    /// Ce qui attend la réponse de l’élève à la notice d’enregistrement de l’école ; `nil` quand rien n’attend.
    var learnerAttention: String? {
        SchoolRecordingChoiceAttention.label(notice: notice != nil, revoked: accessRevoked,
            pending: !relatedPending.isEmpty || hasOldScope, answered: validAnswer != nil)
    }
}
