import MapKit
import SwiftUI

/// Aujourd’hui : la carte et la leçon qui compte maintenant. Une leçon passée sans résultat passe en premier
/// (« À terminer ») ; sinon la prochaine, avec son départ. Un trajet se lance toujours depuis une leçon et son élève ;
/// sans leçon prévue, « Démarrer une leçon » en crée une qui commence maintenant.
struct SchoolTodayView: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    @State private var lessons: [SchoolLesson] = []
    @State private var loadedKey: String?
    @State private var isLoading = false
    @State private var error: String?
    @State private var preparation: SchoolCapturePreparationWorkspace?
    @State private var planning: SchoolPlanningWorkspace?
    @State private var startNow: SchoolStartNowWorkspace?
    @State private var lastStartNow: SchoolStartNowWorkspace?
    @State private var opened: OpenedLesson?
    @State private var showsDay = false
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(JourneyMapRegion.overview))

    private struct OpenedLesson: Identifiable {
        let lesson: SchoolLesson
        let completing: Bool
        var id: UUID { lesson.id }
    }

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)"
    }
    private var instructs: Bool {
        workspace.membership?.roles.contains("INSTRUCTOR") == true && workspace.school?.status == "ACTIVE"
    }
    /// Un moniteur voit ses propres leçons, même s’il administre l’école (filtre relu par le serveur).
    private var instructorFilter: UUID? {
        workspace.membership?.roles.contains("INSTRUCTOR") == true ? workspace.membership?.membershipId : nil
    }
    private var planned: [SchoolLesson] {
        lessons.filter { $0.status == "PLANNED" }.sorted { $0.plannedStart < $1.plannedStart }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            Map(position: $camera) { UserAnnotation() }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls { MapUserLocationButton() }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    card(now: context.date).padding(DrivySpacing.m).frame(maxWidth: 600)
                }
        }
        .task(id: scopeKey) { await load() }
        .sheet(item: $preparation, onDismiss: { Task { await load() } }) { model in
            SchoolCapturePreparationView(model: model, schoolWorkspace: workspace)
        }
        .sheet(item: $planning, onDismiss: { Task { await load() } }) { model in
            SchoolPlanningView(model: model)
        }
        .sheet(item: $startNow, onDismiss: { startNowClosed() }) { model in
            SchoolStartNowView(model: model)
        }
        .sheet(item: $opened, onDismiss: { Task { await load() } }) { item in
            if let agendaClient {
                NavigationStack {
                    SchoolLessonReportView(client: agendaClient.reportClient, schoolWorkspace: workspace, lessonID: item.lesson.id,
                        learnerName: name(item.lesson), opensCompletion: item.completing)
                }
                .tint(DrivyTheme.accent)
                .environment(captureController)
            }
        }
    }

    @ViewBuilder private func card(now: Date) -> some View {
        let toFinish = planned.filter { ($0.endsAt ?? .distantFuture) <= now }
        let next = planned.first { ($0.endsAt ?? .distantPast) > now }
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            if let lesson = toFinish.first {
                lessonSummary(lesson, badge: lesson.drivyState(now: now).badge)
                Button { opened = OpenedLesson(lesson: lesson, completing: true) } label: {
                    Label("Terminer la leçon", systemImage: "checkmark.circle")
                }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .accessibilityIdentifier("today-finish-lesson")
            } else if let next {
                lessonSummary(next, badge: nil)
                if mayStart(next, now: now) {
                    Button { start(next) } label: { Label("Démarrer", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("today-start")
                } else if let opening = startOpening(next, now: now) {
                    Label("Démarrer dès \(opening)", systemImage: "clock")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("today-start-later")
                }
            } else if isLoading && loadedKey != scopeKey {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Aucune autre leçon aujourd’hui").font(.headline).foregroundStyle(DrivyTheme.text)
                if instructs {
                    Button { openStartNow() } label: { Label("Démarrer une leçon", systemImage: "plus") }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("today-start-now")
                }
            }
            if let error { SchoolErrorNotice(message: error, retry: { Task { await load() } }) }
            dayList(now: now, focus: toFinish.first?.id ?? next?.id)
        }
        .padding(DrivySpacing.m)
        .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func lessonSummary(_ lesson: SchoolLesson, badge: DrivyStatusBadge?) -> some View {
        Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(time(lesson)).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(DrivyTheme.text)
                    Spacer(minLength: DrivySpacing.xs)
                    if let badge { badge }
                }
                Text(name(lesson)).font(.headline).foregroundStyle(DrivyTheme.text)
                Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvrir la leçon")
    }

    /// Les autres leçons du jour, repliées : une ligne par leçon, un badge seulement pour l’inhabituel.
    @ViewBuilder private func dayList(now: Date, focus: UUID?) -> some View {
        let others = lessons.filter { $0.id != focus }.sorted { $0.plannedStart < $1.plannedStart }
        if !others.isEmpty {
            DisclosureGroup(isExpanded: $showsDay) {
                VStack(spacing: 0) {
                    ForEach(others) { lesson in
                        Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
                            HStack(spacing: DrivySpacing.s) {
                                Text(startTime(lesson)).font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                                Text(name(lesson)).font(.subheadline).foregroundStyle(DrivyTheme.text).lineLimit(1)
                                Spacer(minLength: DrivySpacing.xs)
                                if let badge = lesson.drivyState(now: now).rowBadge { badge }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } label: {
                Text("Leçons du jour (\(lessons.count))").font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("today-day-list")
        }
    }

    /// Nom fourni avec la leçon, sinon celui d’un dossier déjà chargé ; jamais deviné.
    private func name(_ lesson: SchoolLesson) -> String {
        lesson.providedLearnerName
            ?? workspace.learners.first { $0.id == lesson.learnerId }?.displayName
            ?? (workspace.learner?.id == lesson.learnerId ? workspace.learner?.displayName : nil) ?? "Leçon de conduite"
    }
    private func time(_ lesson: SchoolLesson) -> String {
        guard let start = lesson.startsAt, let end = lesson.endsAt else { return "—" }
        return "\(SchoolDateFormat.time(start, zone: lesson.timeZone)) – \(SchoolDateFormat.time(end, zone: lesson.timeZone))"
    }
    private func startTime(_ lesson: SchoolLesson) -> String {
        lesson.startsAt.map { SchoolDateFormat.time($0, zone: lesson.timeZone) } ?? "—"
    }

    /// Même règle que l’écran de la leçon : moniteur de la leçon, GPS de l’école actif, aucun autre trajet,
    /// dans la fenêtre acceptée par le serveur.
    private func mayStart(_ lesson: SchoolLesson, now: Date = Date()) -> Bool {
        guard instructs, let captureController else { return false }
        let isAuthor = lesson.instructorMembershipId == workspace.membership?.membershipId
        return SchoolLessonHubRules.mayStartCapture(lesson: lesson, isAuthor: isAuthor, school: workspace.school,
            capture: SchoolLessonCaptureStatus(controller: captureController, lessonID: lesson.id),
            controllerCanPrepare: captureController.canPrepareCapture, now: now)
    }
    private func startOpening(_ lesson: SchoolLesson, now: Date) -> String? {
        guard instructs, let captureController else { return nil }
        let isAuthor = lesson.instructorMembershipId == workspace.membership?.membershipId
        guard let opening = SchoolLessonHubRules.captureOpening(lesson: lesson, isAuthor: isAuthor, school: workspace.school,
            capture: SchoolLessonCaptureStatus(controller: captureController, lessonID: lesson.id),
            controllerCanPrepare: captureController.canPrepareCapture, now: now) else { return nil }
        return SchoolLessonHubRules.openingLabel(opening, zone: lesson.timeZone, now: now)
    }
    private func start(_ lesson: SchoolLesson) {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership,
              lesson.instructorMembershipId == membership.membershipId, mayStart(lesson) else { return }
        preparation = agendaClient.capturePreparation(scope: agendaClient.scope(person: person, membership: membership),
            lessonID: lesson.id, controller: captureController)
    }
    private func openStartNow() {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership, instructs else { return }
        let model = SchoolStartNowWorkspace(scope: agendaClient.scope(person: person, membership: membership), client: agendaClient.planningClient)
        lastStartNow = model; startNow = model
    }
    /// Leçon créée : le trajet démarre aussitôt si possible, sinon la leçon s’ouvre. Sans la route côté serveur,
    /// la planification classique s’ouvre avec l’élève déjà choisi.
    private func startNowClosed() {
        guard let model = lastStartNow else { return }
        lastStartNow = nil
        if let lesson = model.started {
            lessons.removeAll { $0.id == lesson.id }; lessons.append(lesson)
            if mayStart(lesson) { start(lesson) } else { opened = OpenedLesson(lesson: lesson, completing: false) }
        } else if model.unsupported {
            planNow(learnerID: model.learnerID)
        }
        Task { await load() }
    }
    private func planNow(learnerID: UUID?) {
        guard let agendaClient, let person = workspace.person, let membership = workspace.membership, instructs else { return }
        let model = SchoolPlanningWorkspace(scope: agendaClient.scope(person: person, membership: membership),
            client: agendaClient.planningClient, date: Date().addingTimeInterval(120))
        model.learnerID = learnerID
        planning = model
    }

    /// Relit la journée sans effacer ce qui est affiché.
    @MainActor private func load() async {
        guard let agendaClient, let membership = workspace.membership else { lessons = []; loadedKey = nil; return }
        let key = scopeKey
        if loadedKey != key { lessons = [] }
        isLoading = true; error = nil
        defer { if key == scopeKey { isLoading = false } }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: workspace.school?.timeZone ?? "") ?? .current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        do {
            var all: [SchoolLesson] = [], cursor: String?, seen = Set<String>(), pages = 0
            repeat {
                pages += 1
                let page = try await agendaClient.lessons(schoolID: membership.schoolId, from: dayStart, to: dayEnd, cursor: cursor,
                    instructorMembershipID: instructorFilter)
                all.append(contentsOf: page.items); cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { break }
            } while cursor != nil && pages < 10
            guard key == scopeKey, !Task.isCancelled else { return }
            var unique: [UUID: SchoolLesson] = [:]
            for lesson in all { unique[lesson.id] = lesson }
            lessons = Array(unique.values); loadedKey = key
        } catch {
            guard key == scopeKey, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = (error as? LocalizedError)?.errorDescription ?? "Les leçons du jour n’ont pas pu être chargées."
        }
    }
}

extension SchoolLesson {
    /// État affiché à un instant donné (l’état par défaut suit l’horloge au moment du rendu).
    func drivyState(now: Date) -> DrivyLessonState { DrivyLessonState(status: status, start: startsAt, end: endsAt, now: now) }
}
