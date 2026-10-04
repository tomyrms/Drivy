import MapKit
import Observation
import SwiftUI
import UIKit

/// Aujourd’hui : la carte et la leçon qui compte maintenant. Une leçon passée sans résultat passe en premier
/// (« À terminer ») ; sinon la prochaine, avec son départ. Un trajet se lance toujours depuis une leçon et son élève ;
/// tant qu’aucune leçon n’est en cours ou imminente, « Démarrer une leçon » en crée une qui commence maintenant
/// (le serveur contrôle le planning) puis enchaîne sur le départ du trajet.
struct SchoolTodayView: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var lessons: [SchoolLesson] = []
    @State private var loadedKey: String?
    @State private var isLoading = false
    @State private var requestID = UUID()
    @State private var error: String?
    @State private var preparation: SchoolCapturePreparationWorkspace?
    @State private var opened: OpenedLesson?
    @State private var showsDay = false
    @State private var cardHeight: CGFloat = 0
    @State private var location = SchoolTodayLocationPermission()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @Namespace private var mapScope

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
                if typeSize.isAccessibilitySize {
                    accessibleDay(now: context.date, availableHeight: geometry.size.height)
                } else if geometry.size.width >= TodayLayout.sidebarBreakpoint {
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
            .task(id: dayKey(context.date)) { await load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.refresh(); Task { await load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            if let change = notification.object as? SchoolLessonChange, change.schoolID != workspace.membership?.schoolId { return }
            if preparation == nil && opened == nil { Task { await load() } }
        }
        .onChange(of: scopeKey) { _, _ in
            preparation?.invalidate(); preparation = nil; opened = nil
        }
        .sheet(item: $preparation, onDismiss: { Task { await load() } }) { model in
            SchoolCapturePreparationView(model: model, schoolWorkspace: workspace)
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

    private func dayKey(_ date: Date) -> String {
        "\(scopeKey):\(SchoolDateFormat.template("yyyyMMdd", date, zone: workspace.school?.timeZone ?? "Europe/Zurich"))"
    }

    /// Le grand texte garde toute sa hauteur : une seule lecture verticale, sans panneau borné au-dessus des onglets.
    private func accessibleDay(now: Date, availableHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: DrivySpacing.l) {
                card(now: now, floating: false)
                if location.permitted {
                    map
                        .frame(height: min(max(availableHeight * 0.45, 240), 420))
                        .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                } else {
                    locationPlaceholder
                }
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: TodayLayout.bottomPanelMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaPadding(.bottom, DrivySpacing.l)
        .background(DrivyTheme.canvas)
    }

    /// Sans position autorisée, un état honnête plutôt qu’une vue du pays entier.
    @ViewBuilder private var map: some View {
        if location.permitted {
            Map(position: $camera, scope: mapScope) { UserAnnotation() }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls { }
                // Avant les insets du panneau : le contrôle suit la carte visible sans déplacer ses mentions.
                .overlay(alignment: .bottomTrailing) {
                    MapUserLocationButton(scope: mapScope)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.trailing, DrivySpacing.m)
                        .padding(.bottom, DrivySpacing.l)
                }
        } else {
            locationPlaceholder
                .frame(maxHeight: .infinity)
                .background(DrivyTheme.canvas)
        }
    }

    private var locationPlaceholder: some View {
        VStack(spacing: DrivySpacing.s) {
            Image(systemName: "location.slash").font(.title).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
            Text("Position indisponible").font(.headline).foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            if location.status == .notDetermined {
                Button { location.request() } label: {
                    Text("Autoriser la localisation").fixedSize(horizontal: false, vertical: true)
                }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .accessibilityIdentifier("today-location-authorize")
            } else if location.status == .denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Text("Ouvrir Réglages").fixedSize(horizontal: false, vertical: true)
                }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .accessibilityIdentifier("today-location-settings")
            } else if location.status == .restricted {
                Text("La localisation est limitée sur cet appareil.").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .padding(DrivySpacing.l)
        .frame(maxWidth: .infinity)
    }

    /// Panneau de la journée : la leçon qui compte maintenant et son action dominante, puis le reste du jour.
    @ViewBuilder private func card(now: Date, floating: Bool) -> some View {
        let toFinish = planned.filter { ($0.endsAt ?? .distantFuture) <= now }
        let next = planned.first { ($0.endsAt ?? .distantPast) > now }
        DrivyMapDock(floating: floating) {
            Text(SchoolDateFormat.template("EEEEdMMMM", now, zone: workspace.school?.timeZone ?? "Europe/Zurich").capitalizedFirst)
                .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let lesson = toFinish.first {
                lessonSummary(lesson, badge: lesson.drivyState(now: now).badge, moment: nil)
                if instructs && lesson.instructorMembershipId == workspace.membership?.membershipId {
                    Button { opened = OpenedLesson(lesson: lesson, completing: true) } label: {
                        Label("Terminer la leçon", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                    .accessibilityIdentifier("today-finish-lesson")
                }
                if let next {
                    Divider().overlay(DrivyTheme.border)
                    upcomingLesson(next, now: now)
                }
            } else if let next {
                lessonSummary(next, badge: nil, moment: SchoolTodayPresentation.moment(for: next, now: now))
                if mayStart(next, now: now) {
                    Button { start(next) } label: { Label("Démarrer le trajet", systemImage: "location.fill") }
                        .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                        .accessibilityIdentifier("today-start")
                } else {
                    if let opening = startOpening(next, now: now) {
                        Label("Démarrer dès \(opening)", systemImage: "clock")
                            .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(DrivyTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("today-start-later")
                    }
                    // Ni en cours ni imminente : le moniteur peut lancer une autre leçon sans la planifier.
                    if instructs, (next.startsAt ?? .distantPast) > now { startNowButton(prominent: false) }
                }
            } else if loadedKey != dayKey(now) && error == nil {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    DrivySkeletonBlock(width: 180, height: 32)
                    DrivySkeletonRow(leading: .avatar)
                    DrivySkeletonBlock(height: 52, radius: DrivyRadius.content)
                }.drivySkeleton("Chargement de la journée…")
            } else if error == nil {
                Text(lessons.isEmpty ? "Aucune leçon aujourd’hui" : "Aucune autre leçon aujourd’hui")
                    .font(.headline).foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if instructs { startNowButton(prominent: true) }
            }
            if let error { SchoolErrorNotice(message: error, retry: { Task { await load() } }) }
            dayList(now: now, excluding: Set([toFinish.first?.id, next?.id].compactMap { $0 }))
        }
    }

    /// Point focal du panneau : l’heure de départ en grand chiffre tabulaire, puis l’élève (avatar, nom, lieu).
    private func lessonSummary(_ lesson: SchoolLesson, badge: DrivyStatusBadge?, moment: String?) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.xs))
        return Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                if let moment {
                    Text(moment).font(.headline).foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                        if !lesson.meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(lesson.meetingPoint).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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

    /// La prochaine leçon reste visible sous une leçon passée à terminer.
    private func upcomingLesson(_ lesson: SchoolLesson, now: Date) -> some View {
        Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(SchoolTodayPresentation.moment(for: lesson, now: now))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                DrivyLessonRow(start: startTime(lesson), end: endTime(lesson), title: name(lesson), details: [])
            }
        }
        .buttonStyle(DrivyRowButtonStyle())
        .accessibilityIdentifier("today-next-lesson")
        .accessibilityHint("Ouvre la prochaine leçon")
    }

    @ViewBuilder private func dayList(now: Date, excluding: Set<UUID>) -> some View {
        let others = SchoolTodayPresentation.upcomingLessons(lessons, now: now, excluding: excluding)
        if !others.isEmpty {
          VStack(spacing: 0) {
            // La liste complète reste dans l’agenda ; ce groupe ne montre que la suite de la journée.
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
                Text(others.count == 1 ? "Prochaine leçon" : "\(others.count) prochaines leçons")
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
    /// « Démarrer une leçon » : élève, leçon créée maintenant par le serveur, puis départ du trajet (voir SchoolStartNowButton).
    @ViewBuilder private func startNowButton(prominent: Bool) -> some View {
        let button = SchoolStartNowButton(workspace: workspace, agendaClient: agendaClient, captureController: captureController,
            onFinished: { Task { await load() } }) {
            Label("Démarrer une leçon", systemImage: "location.fill")
        }
        if prominent {
            button.buttonStyle(DrivyPrimaryButtonStyle(size: .field)).accessibilityIdentifier("today-start-now")
        } else {
            button.buttonStyle(DrivySecondaryButtonStyle(size: .field)).accessibilityIdentifier("today-start-now")
        }
    }

    /// Relit la journée sans effacer ce qui est affiché.
    @MainActor private func load() async {
        guard let agendaClient, let membership = workspace.membership else {
            lessons = []; loadedKey = nil; error = "L’agenda n’est pas disponible. Actualise ton école."
            return
        }
        let key = dayKey(Date()), request = UUID()
        requestID = request
        if loadedKey != key { lessons = [] }
        isLoading = true; error = nil
        defer { if requestID == request { isLoading = false } }
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
                if let cursor, !seen.insert(cursor).inserted { throw SchoolAgendaFailure.invalidResponse }
                if all.count > 10_000 || (pages >= 100 && cursor != nil) { throw SchoolAgendaFailure.invalidResponse }
            } while cursor != nil
            guard key == dayKey(Date()), requestID == request, !Task.isCancelled else { return }
            var unique: [UUID: SchoolLesson] = [:]
            for lesson in all { unique[lesson.id] = lesson }
            lessons = Array(unique.values); loadedKey = key
        } catch {
            guard key == dayKey(Date()), requestID == request, !Task.isCancelled, !(error is CancellationError) else { return }
            switch error as? SchoolAgendaFailure {
            case .authentication, .forbidden:
                lessons = []; loadedKey = nil; opened = nil
                preparation?.invalidate(); preparation = nil
            default: break
            }
            self.error = (error as? LocalizedError)?.errorDescription ?? "Les leçons du jour n’ont pas pu être chargées."
        }
    }
}

enum SchoolTodayPresentation {
    /// Une leçon planifiée reste présente pendant son créneau, jusqu’à sa fin exclue.
    /// Les leçons passées sans constat gardent leur mise en avant « À terminer » dans la carte.
    static func upcomingLessons(_ lessons: [SchoolLesson], now: Date, excluding: Set<UUID> = []) -> [SchoolLesson] {
        lessons.filter { lesson in
            lesson.status == "PLANNED" && (lesson.endsAt ?? .distantPast) > now && !excluding.contains(lesson.id)
        }.sorted { $0.plannedStart < $1.plannedStart }
    }

    /// Un horaire écoulé ne prouve pas que la conduite a démarré.
    static func moment(for lesson: SchoolLesson, now: Date) -> String {
        guard let start = lesson.startsAt else { return "Prochaine leçon" }
        let minutes = Int(ceil(start.timeIntervalSince(now) / 60))
        if minutes <= 0 { return "Horaire commencé" }
        if minutes < 60 { return "Dans \(minutes) min" }
        let hours = minutes / 60, remainder = minutes % 60
        return remainder == 0 ? "Dans \(hours) h" : "Dans \(hours) h \(remainder) min"
    }
}

/// Observe seulement l’autorisation : aucune collecte ni position conservée par cet écran.
@MainActor @Observable private final class SchoolTodayLocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private let manager = CLLocationManager()
    var permitted: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    override init() {
        super.init()
        status = manager.authorizationStatus
        manager.delegate = self
    }
    func refresh() { status = manager.authorizationStatus }
    func request() { if status == .notDetermined { manager.requestWhenInUseAuthorization() } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { status = manager.authorizationStatus }
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
