import MapKit
import Observation
import SwiftUI
import UIKit

/// Aujourd’hui : la carte et la leçon qui compte maintenant. Une leçon passée sans résultat passe en premier
/// si elle a été démarrée ; sinon la prochaine, avec son départ. Un trajet se lance toujours depuis une leçon et son élève ;
/// tant qu’aucune leçon n’est en cours ou imminente, « Démarrer une leçon » en crée une qui commence maintenant
/// (le serveur contrôle le planning) puis enchaîne sur le départ du trajet.
struct SchoolTodayView: View {
    @Bindable var workspace: SchoolWorkspace
    let agendaClient: SchoolAgendaClient?
    let captureController: SchoolCaptureSessionController?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var lessons: [SchoolLesson] = []
    /// Leçons du moniteur commencées un jour précédent et jamais terminées : aucune fin n’est automatique, et
    /// sans ce rappel elles ne se retrouvaient que dans l’historique du profil.
    @State private var unfinished: [SchoolLesson] = []
    @State private var loadedKey: String?
    @State private var isLoading = false
    @State private var requestID = UUID()
    @State private var error: String?
    @State private var opened: OpenedLesson?
    @State private var presentsStartNow = false
    @State private var showsDay = false
    @State private var cardHeight: CGFloat = 0
    @State private var location = SchoolTodayLocationPermission()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @Namespace private var mapScope

    /// « Commencer la leçon » direct en cours (accord lu, puis rideau) : un second appui ne lance rien.
    @State private var startingPlanned = false
    @State private var checkingStart = false

    private struct OpenedLesson: Identifiable {
        let lesson: SchoolLesson
        let completing: Bool
        var starting = false
        /// Départ direct qui n’a pas abouti : la fiche s’ouvre avec sa raison.
        var issue: String? = nil
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
            .onAppear { restoreRememberedDay() }
            .task(id: dayKey(context.date)) { restoreRememberedDay(); await load() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.refresh(); Task { await load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            if let change = notification.object as? SchoolLessonChange, change.schoolID != workspace.membership?.schoolId { return }
            if opened == nil { Task { await load() } }
        }
        .onChange(of: scopeKey) { _, _ in
            opened = nil; presentsStartNow = false
        }
        .sheet(item: $opened, onDismiss: {
            // Une demande abandonnée ou vérifiée depuis la fiche ne reste pas affichée par l'enregistreur du trajet.
            captureController?.liveObservations?.refreshPending()
            Task { await load() }
        }) { item in
            if let agendaClient {
                NavigationStack {
                    SchoolLessonReportView(client: agendaClient.reportClient, schoolWorkspace: workspace, lessonID: item.lesson.id,
                        learnerName: name(item.lesson), opensCompletion: item.completing, opensStart: item.starting,
                        startIssue: item.issue)
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
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
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
        let active = planned.first { $0.hasStarted }
        let next = planned.first { !$0.hasStarted }
        let featured = active ?? next
        DrivyMapDock(floating: floating) {
            if let lesson = featured {
                lessonSummary(lesson, note: lesson.drivyState(now: now).rowNote)
                if instructs && lesson.instructorMembershipId == workspace.membership?.membershipId {
                    Button { Task { await commence(lesson) } } label: {
                        DrivyBusyLabel(title: lesson.hasStarted ? "Continuer la leçon" : "Commencer la leçon",
                            busyTitle: "Commencer la leçon", isBusy: checkingStart || startingPlanned)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                    .accessibilityIdentifier(lesson.hasStarted ? "today-continue-lesson" : "today-start")
                    if !lesson.hasStarted { startNowButton(prominent: false) }
                }
                if active != nil, let next {
                    Divider().overlay(DrivyTheme.border)
                    upcomingLesson(next, now: now)
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
            dayList(now: now, excluding: Set([featured?.id, active == nil ? nil : next?.id].compactMap { $0 }))
            unfinishedList(now: now)
        }
    }

    /// Les leçons restées à terminer depuis un autre jour, sous la journée : la ligne dit le jour, son mot
    /// « À terminer » dit quoi faire, et la fiche s’ouvre pour la finir.
    @ViewBuilder private func unfinishedList(now: Date) -> some View {
        if !unfinished.isEmpty {
            VStack(spacing: 0) {
                Divider().overlay(DrivyTheme.border)
                ForEach(unfinished) { lesson in
                    Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
                        DrivyLessonRow(start: startTime(lesson), end: endTime(lesson), title: name(lesson),
                            details: [day(lesson)], state: lesson.drivyState(now: now), showsChevron: false)
                    }
                    .buttonStyle(DrivyRowButtonStyle())
                    .accessibilityHint("Ouvre la leçon à terminer")
                    .accessibilityIdentifier("today-unfinished-\(lesson.id.uuidString)")
                }
            }
        }
    }

    /// Même lecture compacte que l’agenda : horaire, élève, lieu et éventuel état inhabituel.
    /// La fiche de leçon reste accessible depuis toute la ligne.
    private func lessonSummary(_ lesson: SchoolLesson, note: DrivyRowNote?) -> some View {
        Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
            DrivyLessonRow(start: startTime(lesson), end: endTime(lesson), title: name(lesson),
                details: [lesson.meetingPoint], note: note)
        }
        .buttonStyle(DrivyRowButtonStyle())
        .accessibilityIdentifier("today-focus-lesson")
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
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, lesson in
                        Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
                            DrivyLessonRow(start: startTime(lesson), end: endTime(lesson), title: name(lesson),
                                details: [lesson.meetingPoint], state: lesson.drivyState(now: now), showsChevron: false,
                                railPosition: .at(index, count: others.count))
                        }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint("Ouvre la leçon")
                    }
                }
            } label: {
                Text(others.count == 1 ? "Autre leçon" : "\(others.count) autres leçons")
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
    /// « Jeudi 8 octobre », dans le fuseau de la leçon.
    private func day(_ lesson: SchoolLesson) -> String {
        lesson.startsAt.map { SchoolDateFormat.template("EEEEdMMMM", $0, zone: lesson.timeZone).capitalizedFirst } ?? ""
    }

    /// « Démarrer une leçon » : élève, leçon créée maintenant par le serveur, puis départ du trajet (voir SchoolStartNowButton).
    @ViewBuilder private func startNowButton(prominent: Bool) -> some View {
        let button = SchoolStartNowButton(workspace: workspace, agendaClient: agendaClient, captureController: captureController,
            onFinished: { Task { await load() } }, onPresentationChanged: { presented in
                presentsStartNow = presented
                if presented { requestID = UUID(); isLoading = false }
            }) {
            Label(prominent ? "Démarrer une leçon" : "Leçon sans rendez-vous", systemImage: "location.fill")
        }
        if prominent {
            button.buttonStyle(DrivyPrimaryButtonStyle(size: .field)).accessibilityIdentifier("today-start-now")
        } else {
            button.buttonStyle(DrivySecondaryButtonStyle(size: .field)).accessibilityIdentifier("today-start-now")
        }
    }

    /// « Commencer la leçon » : quand l’accord de l’élève vaut déjà et que la localisation est accordée, la leçon
    /// commence et le trajet part sous le rideau, sans ouvrir la fiche ; sinon la fiche s’ouvre et commence comme
    /// avant (la question d’accord s’y pose). « Continuer » ouvre toujours la fiche.
    private func commence(_ lesson: SchoolLesson) async {
        guard !checkingStart, !startingPlanned, opened == nil else { return }
        guard !lesson.hasStarted, mayStartDirectly(lesson), let agendaClient, let captureController,
              let person = workspace.person, let membership = workspace.membership else {
            opened = OpenedLesson(lesson: lesson, completing: false, starting: !lesson.hasStarted)
            return
        }
        let scope = agendaClient.scope(person: person, membership: membership), startKey = scopeKey
        // Lecture seule de l’accord, l’attente se lit dans le bouton : le rideau ne se montre jamais pour une question.
        checkingStart = true
        let allowed = await SchoolPlannedStart.consentAllows(lesson, scope: scope, client: agendaClient.captureClient)
        checkingStart = false
        // Une autre fiche ouverte entre-temps, ou un autre compte : rien n’est remplacé.
        guard opened == nil, scopeKey == startKey else { return }
        guard allowed, mayStartDirectly(lesson) else {
            opened = OpenedLesson(lesson: lesson, completing: false, starting: true)
            return
        }
        startingPlanned = true
        let outcome = await SchoolPlannedStart.run(lesson: lesson, membership: membership, scope: scope,
            agenda: agendaClient, controller: captureController)
        startingPlanned = false
        // Trajet parti : la carte remplace déjà cet écran. Sinon la fiche s’ouvre sous le rideau, puis il se lève.
        if case .lesson(let issue) = outcome, scopeKey == startKey {
            opened = OpenedLesson(lesson: lesson, completing: false, issue: issue)
            await DrivyLaunchCurtain.shared.hide(afterSequence: true)
        }
    }

    /// Rien à demander côté appareil et école : moniteur de la leçon, GPS de l’école, localisation exacte accordée.
    private func mayStartDirectly(_ lesson: SchoolLesson) -> Bool {
        guard instructs, let captureController, location.permitted, location.precise else { return false }
        return SchoolLessonHubRules.mayStartCapture(lesson: lesson,
            isAuthor: lesson.instructorMembershipId == workspace.membership?.membershipId, school: workspace.school,
            capture: SchoolLessonCaptureStatus(controller: captureController, lessonID: lesson.id),
            controllerCanPrepare: captureController.canPrepareCapture, now: Date())
    }

    /// Un nouvel « Aujourd’hui » (retour d’un trajet, changement d’onglet) reprend la journée déjà lue pour ce compte
    /// et ce jour : pas de squelette, la relecture suit sans rien effacer.
    private func restoreRememberedDay() {
        let key = dayKey(Date())
        guard loadedKey == nil, let day = SchoolTodayMemory.day(for: key) else { return }
        lessons = day.lessons; unfinished = day.unfinished; loadedKey = key
    }

    /// Relit la journée sans effacer ce qui est affiché.
    @MainActor private func load() async {
        // Ce bouton porte plusieurs feuilles successives. Un refresh le remplaçant ne doit pas fermer la chaîne.
        guard !presentsStartNow, !startingPlanned else { return }
        guard let agendaClient, let membership = workspace.membership else {
            lessons = []; unfinished = []; loadedKey = nil; error = "L’agenda n’est pas disponible. Actualise ton école."
            return
        }
        let key = dayKey(Date()), request = UUID()
        requestID = request
        if loadedKey != key { lessons = []; unfinished = [] }
        isLoading = true; error = nil
        defer { if requestID == request { isLoading = false } }
        // Même fuseau que la clé du jour (`dayKey`) : la journée lue est celle qui est affichée.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: workspace.school?.timeZone ?? "Europe/Zurich") ?? .current
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
            SchoolTodayMemory.remember(key: key, lessons: lessons, unfinished: unfinished)
            // Lecture discrète : la page la plus récente des leçons passées du moniteur suffit à retrouver celles
            // restées sans fin. Une panne garde le rappel déjà affiché et ne dit rien : la journée reste lisible.
            guard let instructor = instructorFilter else { unfinished = []; return }
            guard let earlier = try? await agendaClient.lessonHistory(schoolID: membership.schoolId, before: dayStart,
                instructorMembershipID: instructor, cursor: nil) else { return }
            guard key == dayKey(Date()), requestID == request, !Task.isCancelled else { return }
            unfinished = SchoolTodayPresentation.unfinishedLessons(earlier.items, before: dayStart)
            SchoolTodayMemory.remember(key: key, lessons: lessons, unfinished: unfinished)
        } catch {
            guard key == dayKey(Date()), requestID == request, !Task.isCancelled, !(error is CancellationError) else { return }
            switch error as? SchoolAgendaFailure {
            case .authentication, .forbidden:
                SchoolTodayMemory.forget()
                lessons = []; unfinished = []; loadedKey = nil; opened = nil
                self.error = (error as? LocalizedError)?.errorDescription ?? "Les leçons du jour n’ont pas pu être chargées."
                // « Réessayer » seul ne sortirait jamais d’une session expirée ou d’un accès retiré : le compte est
                // relu. Refusé, il ouvre la reconnexion ; modifié, il recharge l’école ; inchangé, rien ne bouge.
                await workspace.refreshAccount(minimumInterval: 0)
                return
            default: break
            }
            self.error = (error as? LocalizedError)?.errorDescription ?? "Les leçons du jour n’ont pas pu être chargées."
        }
    }
}

enum SchoolTodayPresentation {
    /// Tous les rendez-vous encore ouverts restent accessibles, y compris ceux en attente après leur horaire.
    static func upcomingLessons(_ lessons: [SchoolLesson], now: Date, excluding: Set<UUID> = []) -> [SchoolLesson] {
        lessons.filter { lesson in
            lesson.status == "PLANNED" && !excluding.contains(lesson.id)
        }.sorted { $0.plannedStart < $1.plannedStart }
    }

    /// Leçons commencées avant aujourd’hui et restées sans résultat, la plus ancienne d’abord. Seul un départ
    /// confirmé par l’école compte : un rendez-vous passé jamais commencé n’est pas « à terminer ».
    static func unfinishedLessons(_ lessons: [SchoolLesson], before dayStart: Date) -> [SchoolLesson] {
        lessons.filter { lesson in
            lesson.status == "PLANNED" && lesson.hasStarted && (lesson.startsAt.map { $0 < dayStart } ?? false)
        }.sorted { $0.plannedStart < $1.plannedStart }
    }

    /// Un horaire écoulé ne prouve pas que la conduite a démarré.
    static func moment(for lesson: SchoolLesson, now: Date) -> String {
        if lesson.hasStarted { return "En cours" }
        guard let start = lesson.startsAt else { return "Prochaine leçon" }
        let minutes = Int(ceil(start.timeIntervalSince(now) / 60))
        if minutes <= 0 { return "En attente" }
        if minutes < 60 { return "Dans \(minutes) min" }
        let hours = minutes / 60, remainder = minutes % 60
        return remainder == 0 ? "Dans \(hours) h" : "Dans \(hours) h \(remainder) min"
    }
}

/// Observe seulement l’autorisation : aucune collecte ni position conservée par cet écran.
@MainActor @Observable private final class SchoolTodayLocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus = .notDetermined
    /// Position exacte accordée (sinon le trajet ne pourrait pas partir).
    private(set) var precise = false
    @ObservationIgnored private let manager = CLLocationManager()
    var permitted: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    override init() {
        super.init()
        refresh()
        manager.delegate = self
    }
    func refresh() { status = manager.authorizationStatus; precise = manager.accuracyAuthorization == .fullAccuracy }
    func request() { if status == .notDetermined { manager.requestWhenInUseAuthorization() } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refresh() }
}

/// Dernière journée lue, en mémoire seulement, par compte, école, droits et jour (la clé `dayKey`) : aucun autre
/// compte ni aucun autre jour ne la retrouve, et rien n’est écrit sur l’appareil.
@MainActor enum SchoolTodayMemory {
    private static var key: String?
    private static var lessons: [SchoolLesson] = []
    private static var unfinished: [SchoolLesson] = []

    static func remember(key: String, lessons: [SchoolLesson], unfinished: [SchoolLesson]) {
        self.key = key; self.lessons = lessons; self.unfinished = unfinished
    }

    static func day(for key: String) -> (lessons: [SchoolLesson], unfinished: [SchoolLesson])? {
        self.key == key ? (lessons, unfinished) : nil
    }

    /// Une leçon a changé (début, fin, annulation) ou l’accès a été refusé : la journée retenue n’est plus sûre.
    static func forget() {
        key = nil; lessons = []; unfinished = []
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
    func drivyState(now: Date) -> DrivyLessonState { DrivyLessonState(status: status, start: startsAt, end: endsAt, actualStart: startedAt, now: now) }
}
