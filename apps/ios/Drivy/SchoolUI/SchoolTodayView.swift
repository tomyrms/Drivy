import MapKit
import SwiftUI

/// Aujourd’hui : la carte et la leçon qui compte maintenant. Une leçon passée sans résultat passe en premier
/// (« À terminer ») ; sinon la prochaine, avec son départ. Un trajet se lance toujours depuis une leçon et son élève ;
/// sans leçon prévue, « Démarrer une leçon » en crée une qui commence maintenant.
struct SchoolTodayView: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    @Environment(\.dynamicTypeSize) private var typeSize
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
    @State private var cardHeight: CGFloat = 0
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
            GeometryReader { geometry in
                // 380 pt pour la leçon et au moins 580 pt de carte ; une fenêtre étroite
                // conserve le panneau du bas, indépendamment du modèle d’iPad.
                if geometry.size.width >= TodayLayout.sidebarBreakpoint && !typeSize.isAccessibilitySize {
                    // Hors de la carte, le panneau latéral est posé sur le fond : filet, pas d’ombre.
                    map
                        .safeAreaInset(edge: .leading, spacing: 0) {
                            ScrollView {
                                card(now: context.date, floating: false).padding(DrivySpacing.m)
                            }
                            .frame(width: DrivyMapLayout.sidebarWidth)
                            .background(DrivyTheme.canvas)
                            // La colonne a la place : la journée s’y ouvre d’emblée au lieu de laisser un fond vide.
                            .onAppear { showsDay = true }
                        }
                } else {
                    let maxHeight = geometry.size.height * TodayLayout.bottomPanelMaxRatio
                    map.safeAreaInset(edge: .bottom, spacing: 0) {
                        ScrollView {
                            card(now: context.date, floating: true).padding(DrivySpacing.m)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxWidth: TodayLayout.bottomPanelMaxWidth)
                        .frame(height: min(cardHeight > 0 ? cardHeight : maxHeight, maxHeight))
                    }
                }
            }
        }
        .task(id: scopeKey) { await load() }
        .onChange(of: scopeKey) { _, _ in
            lastStartNow?.invalidate(); lastStartNow = nil; startNow = nil
            preparation?.invalidate(); preparation = nil
            planning?.invalidate(); planning = nil; opened = nil
        }
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

    private var map: some View {
        Map(position: $camera) { UserAnnotation() }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton() }
    }

    /// Panneau de la journée : la leçon qui compte maintenant et son action dominante, puis le reste du jour.
    @ViewBuilder private func card(now: Date, floating: Bool) -> some View {
        let toFinish = planned.filter { ($0.endsAt ?? .distantFuture) <= now }
        let next = planned.first { ($0.endsAt ?? .distantPast) > now }
        DrivyMapDock(floating: floating) {
            if let lesson = toFinish.first {
                lessonSummary(lesson, badge: lesson.drivyState(now: now).badge)
                Button { opened = OpenedLesson(lesson: lesson, completing: true) } label: {
                    Label("Terminer la leçon", systemImage: "checkmark.circle")
                }
                .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                .accessibilityIdentifier("today-finish-lesson")
            } else if let next {
                lessonSummary(next, badge: nil)
                if mayStart(next, now: now) {
                    Button { start(next) } label: { Label("Démarrer le trajet", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                        .accessibilityIdentifier("today-start")
                } else if let opening = startOpening(next, now: now) {
                    Label("Démarrer dès \(opening)", systemImage: "clock")
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("today-start-later")
                }
            } else if isLoading && loadedKey != scopeKey {
                DrivyLoadingState(title: "Chargement de la journée…")
            } else {
                Text(lessons.isEmpty ? "Aucune leçon aujourd’hui" : "Aucune autre leçon aujourd’hui")
                    .font(.headline).foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if instructs {
                    Button { openStartNow() } label: { Label("Démarrer une leçon", systemImage: "plus") }
                        .buttonStyle(DrivyPrimaryButtonStyle())
                        .accessibilityIdentifier("today-start-now")
                }
            }
            if let error { SchoolErrorNotice(message: error, retry: { Task { await load() } }) }
            dayList(now: now, focus: toFinish.first?.id ?? next?.id)
        }
    }

    /// Point focal du panneau : l’heure de départ en grand chiffre tabulaire, puis l’élève (avatar, nom, lieu).
    private func lessonSummary(_ lesson: SchoolLesson, badge: DrivyStatusBadge?) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.xs))
        return Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                layout {
                    Text(startTime(lesson)).font(.drivyScreenTitle.monospacedDigit()).foregroundStyle(DrivyTheme.text)
                    Text("– \(endTime(lesson))").font(.title3.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
                    if !stacked { Spacer(minLength: DrivySpacing.xs) }
                    if let badge { badge }
                }
                HStack(spacing: DrivySpacing.s) {
                    if !stacked { DrivyAvatar(name: name(lesson), size: 44) }
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text(name(lesson)).font(.headline).foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !stacked {
                        Spacer(minLength: DrivySpacing.xs)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DrivyRowButtonStyle())
        .accessibilityHint("Ouvre la leçon")
    }

    /// Les autres leçons du jour, repliées : une ligne par leçon, un badge seulement pour l’inhabituel.
    @ViewBuilder private func dayList(now: Date, focus: UUID?) -> some View {
        let others = lessons.filter { $0.id != focus }.sorted { $0.plannedStart < $1.plannedStart }
        if !others.isEmpty {
          VStack(spacing: 0) {
            // Filet entre la leçon qui compte et le reste du jour : deux groupes, pas une pile.
            Divider().overlay(DrivyTheme.border)
            DisclosureGroup(isExpanded: $showsDay) {
                VStack(spacing: 0) {
                    ForEach(others) { lesson in
                        Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
                            DrivyLessonRow(start: startTime(lesson), end: endTime(lesson), title: name(lesson),
                                details: [lesson.meetingPoint], badge: lesson.drivyState(now: now).rowBadge, showsChevron: false)
                        }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint("Ouvre la leçon")
                        Divider().overlay(DrivyTheme.border)
                    }
                }
            } label: {
                (Text("Leçons du jour ") + Text("\(lessons.count)").foregroundStyle(DrivyTheme.muted))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("today-day-list")
          }
        }
    }

    /// Nom fourni avec la leçon, sinon celui d’un dossier déjà chargé ; jamais deviné.
    private func name(_ lesson: SchoolLesson) -> String {
        lesson.providedLearnerName
            ?? workspace.learners.first { $0.id == lesson.learnerId }?.displayName
            ?? (workspace.learner?.id == lesson.learnerId ? workspace.learner?.displayName : nil) ?? "Leçon de conduite"
    }
    private func startTime(_ lesson: SchoolLesson) -> String {
        lesson.startsAt.map { SchoolDateFormat.time($0, zone: lesson.timeZone) } ?? "—"
    }
    private func endTime(_ lesson: SchoolLesson) -> String {
        lesson.endsAt.map { SchoolDateFormat.time($0, zone: lesson.timeZone) } ?? "—"
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

/// Seuils d’Aujourd’hui : panneau latéral dès 960 pt (380 pt de leçon, au moins 580 pt de carte),
/// sinon panneau bas borné en largeur et en hauteur.
private enum TodayLayout {
    static let sidebarBreakpoint: CGFloat = 960
    static let bottomPanelMaxWidth = DrivyLayout.narrowColumn
    static let bottomPanelMaxRatio: CGFloat = 0.66
}

extension SchoolLesson {
    /// État affiché à un instant donné (l’état par défaut suit l’horloge au moment du rendu).
    func drivyState(now: Date) -> DrivyLessonState { DrivyLessonState(status: status, start: startsAt, end: endsAt, now: now) }
}
