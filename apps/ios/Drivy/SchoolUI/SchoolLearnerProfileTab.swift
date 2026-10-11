import SwiftUI

/// L’onglet Profil de l’élève : qui il est, où il en est dans chacune de ses formations, ses trajets, son accord
/// GPS et son compte. Les formations sont celles des onglets Leçons et Progression (mêmes modèles partagés, toutes
/// leçons lues) : rien n’est relu en double, et aucun chiffre n’est donné tant que l’historique n’est pas complet.
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
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var models: [SchoolTrainingWorkspace] = []
    /// Affectations de chaque formation ; une lecture refusée ou en panne n’affiche simplement pas de moniteur.
    @State private var assignments: [UUID: [SchoolAssignment]] = [:]
    @State private var opened: ProfileLesson?

    private var accountKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)"
    }
    private var scopeKey: String {
        "\(accountKey):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(learner?.id.uuidString ?? ""):\(trainings.map { $0.id.uuidString }.joined(separator: ","))"
    }
    private var scope: SchoolCommandScope? {
        guard let person = workspace.person, let membership = workspace.membership, let trainingClient else { return nil }
        return SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId, membershipID: membership.membershipId,
            accessEpoch: membership.accessEpoch, apiBaseURL: trainingClient.baseURL.absoluteString)
    }
    /// Trajets et accord GPS n’ont de sens que dans une école qui enregistre des trajets.
    private var recordsTrips: Bool { workspace.school?.status == "ACTIVE" && workspace.school?.modules.gpsEnabled == true }
    /// Ce qui fait apparaître les chiffres d’une formation : ils arrivent en fondu, sans pousser la page.
    private var readyKey: String { models.map { "\($0.trainingID):\(Self.isComplete($0))" }.joined(separator: ",") }

    var body: some View {
        NavigationStack {
            List { content }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: DrivyLayout.formColumn)
                .frame(maxWidth: .infinity)
                .background(DrivyTheme.canvas)
                .animation(DrivyMotion.reveal(reduceMotion), value: readyKey)
                .refreshable { await refresh(olderThan: 0) }
                .navigationTitle("Profil")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if let chooseSchool {
                        DrivySchoolToolbarItem(schoolName: workspace.school?.name ?? workspace.membership?.schoolName,
                            chooseSchool: chooseSchool)
                    }
                }
                .accessibilityIdentifier("learner-profile-list")
        }
        .id(accountKey)
        .task(id: scopeKey) { await prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh(olderThan: 30) } }
        }
        .sheet(item: $opened, onDismiss: { Task { await refresh(olderThan: 0) } }) { lesson in
            if let trainingClient {
                NavigationStack {
                    SchoolLessonReportView(client: trainingClient.reports, schoolWorkspace: workspace, lessonID: lesson.id,
                        learnerName: learner?.displayName ?? "", knownLesson: lesson.lesson)
                }
                .tint(DrivyTheme.accent)
            }
        }
    }

    /// Identité, chaque formation, trajets et accord GPS, puis le compte.
    @ViewBuilder private var content: some View {
        Section {
            SchoolAccountHeading(workspace: workspace, isAuthenticated: true, detail: SchoolPermitName.summary(trainings))
        }
        .listRowInsets(EdgeInsets(top: DrivySpacing.s, leading: DrivySpacing.m, bottom: DrivySpacing.s, trailing: DrivySpacing.m))
        .listRowBackground(Color.clear)
        ForEach(models, id: \.trainingID) { model in trainingSection(model) }
        if recordsTrips, let agendaClient {
            Section {
                NavigationLink {
                    SchoolLearnerTripsView(workspace: workspace, agendaClient: agendaClient)
                } label: {
                    Text("Trajets")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile-open-trips")
            }
            .drivyFormRows()
            if let learner, let scope {
                // Le choix général de l’élève : celui qui vaut pour ses prochaines leçons, même sans leçon planifiée.
                Section {
                    SchoolOwnRecordingChoice(scope: scope, lessonID: nil, learnerID: learner.id, agenda: agendaClient)
                }
                .drivyFormRows()
            }
        }
        if let account {
            Section {
                account.rows(workspace: workspace, openURL: openURL)
                    // Les rangées portent déjà leur espacement vertical : sans cela, la liste le double.
                    .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
            }
            .drivyFormRows()
        }
    }

    /// Une formation : ses chiffres une fois toutes ses leçons lues, sinon une attente, ou la panne et « Réessayer ».
    @ViewBuilder private func trainingSection(_ model: SchoolTrainingWorkspace) -> some View {
        let training = model.training ?? trainings.first { $0.id == model.trainingID }
        Section {
            if Self.isComplete(model) {
                // Une relecture en panne garde les chiffres déjà lus, mais le dit : rien ne passe pour à jour.
                if let error = model.errorMessage {
                    SchoolErrorNotice(message: error, retry: { Task { await model.load(keepingCurrent: true) } })
                }
                overviewRows(SchoolTrainingOverview.make(lessons: model.lessons, progress: model.progress), model: model, training: training)
            } else if let error = model.errorMessage {
                SchoolErrorNotice(message: error, retry: { Task { await model.load(keepingCurrent: true) } })
            } else {
                DrivySkeletonRows(count: 3)
                    .drivySkeleton("Chargement de la formation…")
            }
        } header: {
            trainingHeader(training, model: model)
        }
        .drivyFormRows()
    }

    /// « Permis B », suivi de l’état seulement s’il est inhabituel (en pause, terminée, annulée).
    private func trainingHeader(_ training: SchoolTraining?, model: SchoolTrainingWorkspace) -> some View {
        let names = SchoolPermitName.names(trainings)
        var title = names[model.trainingID] ?? training.map { "Permis \($0.categoryCode)" } ?? "Formation"
        if let training, training.status != "ACTIVE" { title += " · " + SchoolPresentation.trainingStatus(training.status) }
        return Text(title).drivyFormSectionHeader()
    }

    @ViewBuilder private func overviewRows(_ overview: SchoolTrainingOverview, model: SchoolTrainingWorkspace,
                                           training: SchoolTraining?) -> some View {
        DrivyKeyValueRow(title: "Leçons terminées", value: "\(overview.completedLessons)", numeric: true)
        if overview.lessonMinutes > 0 {
            DrivyKeyValueRow(title: "Temps en leçon", value: SchoolTrainingOverview.duration(overview.lessonMinutes), numeric: true)
        }
        if let independent = overview.independent, let total = overview.competencies, total > 0 {
            DrivyKeyValueRow(title: "En autonomie", value: "\(independent) sur \(total)", numeric: true)
        }
        if let records = assignments[model.trainingID],
           let name = SchoolTrainingOverview.instructorNames(assignments: records, lessons: model.lessons, now: Date()) {
            DrivyKeyValueRow(title: "Moniteur", value: name)
        }
        if let started = training?.startedOn {
            DrivyKeyValueRow(title: "Début", value: SchoolPresentation.civilDate(started))
        }
        if let last = overview.lastCompleted {
            DrivyNavigationRow(title: "Dernière leçon", detail: SchoolTrainingFormatting.day(last.plannedStart, zone: last.timeZone)) {
                opened = ProfileLesson(lesson: last)
            }
            .accessibilityIdentifier("profile-last-lesson-\(model.trainingID.uuidString)")
        }
    }

    private static func isComplete(_ model: SchoolTrainingWorkspace) -> Bool {
        model.lessonsLoaded && model.nextCursor == nil && model.training != nil
    }

    /// Les modèles partagés avec Leçons et Progression : un nouveau se lit, un modèle connu ne se relit que s’il date.
    private func prepare() async {
        guard let learner, let membership = workspace.membership, let trainingClient, let scope else {
            models = []; assignments = [:]; return
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
        await SchoolLessonFeed.together(models) { model in
            if fresh.contains(model.trainingID) { await model.load() } else { await model.refresh(ifOlderThan: 30) }
        }
        // Annulée avec l’écran : une lecture d’un autre compte ou d’une autre école n’écrit rien ici.
        await withTaskCancellationHandler { await reading.value } onCancel: { reading.cancel() }
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

private struct ProfileLesson: Identifiable {
    let lesson: SchoolLesson
    var id: UUID { lesson.id }
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

    /// Moniteurs affectés aujourd’hui à la formation, nommés par la plus récente de leurs leçons. Un moniteur sans
    /// leçon lue n’est pas nommé : l’élève ne lit pas l’équipe de l’école, et rien n’est deviné.
    static func instructorNames(assignments: [SchoolAssignment], lessons: [SchoolLesson], now: Date) -> String? {
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
        return names.isEmpty ? nil : names.sorted { $0.localizedCompare($1) == .orderedAscending }.joined(separator: ", ")
    }
}
