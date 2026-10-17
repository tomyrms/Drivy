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
    /// Le bouton d’école de la barre, quand le compte en a plusieurs : il flotte avec le titre.
    var schoolName: String? = nil
    var chooseSchool: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SchoolRequiredActionStore.self) private var requiredActions: SchoolRequiredActionStore?
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
    /// La feuille « Démarrer une leçon » appartient à l’écran : la carte qui porte son bouton change avec l’heure.
    @State private var startNow = SchoolStartNowPresentation()
    @State private var cardHeight: CGFloat = 0
    @State private var location = SchoolTodayLocationPermission()
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

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
    /// La carte occupe tout l’écran : titre flottant, sans barre système.
    private var floatsTitle: Bool { !typeSize.isAccessibilitySize }
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
                            // Le panneau commence sous le titre flottant, comme il commençait sous la barre.
                            .safeAreaPadding(.top, DrivyLayout.tapTarget)
                            .frame(width: DrivyMapLayout.sidebarWidth)
                            .scrollEdgeEffectHidden(true, for: .top)
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
                        // Le panneau défile seul : son effet de bord ne remonte pas sous la barre du haut.
                        .scrollEdgeEffectHidden(true, for: .top)
                        .frame(maxWidth: TodayLayout.bottomPanelMaxWidth)
                        .frame(height: min(cardHeight > 0 ? cardHeight : maxHeight, maxHeight))
                    }
                }
            }
            .onAppear { restoreRememberedDay() }
            .task(id: dayKey(context.date)) { restoreRememberedDay(); await load() }
        }
        // Sous iOS 26, une barre de navigation posée sur une carte MapKit floute la carte sur toute sa hauteur et
        // s’arrête net sous le titre : un bandeau. Ni son fond, ni les effets de bord, ni la zone sûre ne le retirent
        // (mesuré sur simulateur, une barre sur un contenu ordinaire reste nette). Au-dessus de la carte, l’écran n’a
        // donc pas de barre système : le titre et le bouton d’école flottent à leur place, sans fond. En très grand
        // texte, la page défile et garde sa barre.
        .toolbar(floatsTitle ? .hidden : .automatic, for: .navigationBar)
        .overlay(alignment: .top) {
            if floatsTitle { DrivyFloatingTitleBar(title: "Aujourd’hui", schoolName: schoolName, chooseSchool: chooseSchool) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { location.refresh(); Task { await load() } }
        }
        // Les leçons à terminer que cet écran lit déjà (le jour et le rappel des jours passés) sont l’action
        // de l’onglet : aucune lecture de plus, et le point part dès que la liste se vide. Une leçon commencée
        // devient « à terminer » à sa fin prévue : le point s’allume à cette heure-là, comme sa ligne.
        .task(id: (lessons + unfinished).map { "\($0.id):\($0.version)" }) {
            while !Task.isCancelled {
                let all = lessons + unfinished, now = Date()
                requiredActions?.replace(.finishLesson, with: SchoolRequiredActionRules.lessonsToFinish(all,
                    instructorMembershipID: instructorFilter, now: now))
                guard let next = SchoolRequiredActionRules.nextFinishDeadline(all, instructorMembershipID: instructorFilter, now: now)
                else { return }
                try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSince(now))))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            if let change = notification.object as? SchoolLessonChange, change.schoolID != workspace.membership?.schoolId { return }
            if opened == nil { Task { await load() } }
        }
        .onChange(of: scopeKey) { _, _ in
            opened = nil; presentsStartNow = false
        }
        .modifier(SchoolStartNowSheets(presentation: startNow, workspace: workspace, agendaClient: agendaClient))
        .sheet(item: $opened, onDismiss: {
            // Une demande abandonnée ou vérifiée depuis la fiche ne reste pas affichée par l'enregistreur du trajet.
            captureController?.liveObservations?.refreshPending()
            Task { await load() }
        }) { item in
            if let agendaClient {
                NavigationStack {
                    SchoolLessonReportView(client: agendaClient.reportClient, schoolWorkspace: workspace, lessonID: item.lesson.id,
                        learnerName: name(item.lesson), opensCompletion: item.completing, opensStart: item.starting,
                        knownLesson: item.lesson, startIssue: item.issue)
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
            // Ni rotation ni boussole : la carte du jour reste nord en haut, sans commande système hors de la DA.
            Map(position: $camera, interactionModes: [.pan, .zoom]) { UserAnnotation() }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControls { }
                // Le point de position garde le bleu du système : teinté du bleu pastel du thème sombre, il se lisait
                // comme une position périmée.
                .tint(.blue)
                // Avant les insets du panneau : le contrôle suit la carte visible sans déplacer ses mentions.
                .overlay(alignment: .bottomTrailing) { recenterButton }
        } else {
            locationPlaceholder
                .frame(maxHeight: .infinity)
                .background(DrivyTheme.canvas)
        }
    }

    /// Même bouton rond que sur la carte du trajet : verre lisible, glyphe de la DA, plein quand la carte suit.
    private var recenterButton: some View {
        let following = camera.followsUserLocation
        return Button {
            withAnimation(DrivyMotion.context(reduceMotion)) { camera = .userLocation(fallback: .automatic) }
        } label: {
            Image(systemName: following ? "location.fill" : "location")
                .font(DrivyMapGlyph.primaryControl)
                .foregroundStyle(following ? DrivyTheme.accent : DrivyTheme.text)
                .frame(width: 48, height: 48)
                .drivyLegibleMapControl(in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, DrivySpacing.m)
        .padding(.bottom, DrivySpacing.m)
        .accessibilityLabel("Recentrer sur ma position")
        .accessibilityAddTraits(following ? [.isSelected] : [])
        .accessibilityIdentifier("today-recenter")
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
        let next = planned.first { !$0.hasStarted && !SchoolLessonHubRules.isMissed($0, now: now) }
        // Un rendez-vous manqué ne passe devant un autre qu’à défaut : il reste à l’écran, « En attente », tant que
        // rien d’autre n’est prévu, comme dans l’agenda.
        let featured = SchoolTodayPresentation.featured(in: planned, now: now)
        DrivyMapDock(floating: floating) {
            if let lesson = featured {
                // Une leçon commencée se lit « En cours » sur sa ligne, pas seulement dans le libellé du bouton.
                lessonSummary(lesson, note: lesson.drivyState(now: now).rowNote
                    ?? (lesson.hasStarted ? DrivyRowNote(text: "En cours", tone: .accent) : nil))
                if instructs && lesson.instructorMembershipId == workspace.membership?.membershipId
                    && (lesson.hasStarted || SchoolLessonHubRules.mayBegin(lesson, now: now)) {
                    Button { Task { await commence(lesson) } } label: {
                        DrivyBusyLabel(title: lesson.hasStarted ? "Continuer la leçon" : "Commencer la leçon",
                            busyTitle: "Commencer la leçon", isBusy: checkingStart || startingPlanned)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle(size: .field))
                    .accessibilityIdentifier(lesson.hasStarted ? "today-continue-lesson" : "today-start")
                    if !lesson.hasStarted { startNowButton(prominent: false) }
                }
                following(now: now, featured: lesson, next: active == nil ? nil : next)
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
            unfinishedList(now: now, excluding: featured?.id)
        }
    }

    /// Les leçons restées à terminer depuis un autre jour, sous la journée : la ligne dit le jour, son mot
    /// « À terminer » dit quoi faire, et la fiche s’ouvre pour la finir.
    /// La leçon déjà en tête du panneau n’y est pas répétée.
    @ViewBuilder private func unfinishedList(now: Date, excluding featuredID: UUID?) -> some View {
        let unfinished = unfinished.filter { $0.id != featuredID }
        if !unfinished.isEmpty {
            VStack(spacing: 0) {
                Divider().overlay(DrivyTheme.border)
                ForEach(unfinished) { lesson in
                    Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
                        DrivyLessonRow(start: startTime(lesson), end: endTime(lesson), title: name(lesson),
                            details: [day(lesson)], state: lesson.drivyState(now: now))
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

    /// Après la leçon en tête : la suivante en une ligne, le reste de la journée en une pastille « +2 ».
    /// La liste complète se lit dans l’agenda ; le panneau laisse la carte respirer.
    @ViewBuilder private func following(now: Date, featured: SchoolLesson, next: SchoolLesson?) -> some View {
        let rest = SchoolTodayPresentation.upcomingLessons(lessons, now: now,
            excluding: Set([featured.id, next?.id].compactMap { $0 }))
        // Une leçon manquée reste lisible ici (« En attente ») quand aucune autre n’est prévue après elle.
        let upcoming = next ?? rest.first { !$0.hasStarted && !SchoolLessonHubRules.isMissed($0, now: now) }
            ?? rest.first { !$0.hasStarted }
        if let upcoming {
            Divider().overlay(DrivyTheme.border)
            nextLine(upcoming, extra: rest.filter { $0.id != upcoming.id }.count, now: now)
        }
    }

    /// Même colonne d’heure que la leçon du dessus : les noms s’alignent. Sans heure de fin ni lieu, que la fiche donne.
    private func nextLine(_ lesson: SchoolLesson, extra: Int, now: Date) -> some View {
        let moment = SchoolTodayPresentation.moment(for: lesson, now: now)
        return Button { opened = OpenedLesson(lesson: lesson, completing: false) } label: {
            // Heure, nom, pastille et chevron sur la première ligne, comme la leçon du dessus.
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.m) {
                Text(startTime(lesson))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(DrivyTheme.text)
                    .frame(minWidth: 52, alignment: .leading)
                    .fixedSize()
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(name(lesson))
                        .font(.headline)
                        .foregroundStyle(DrivyTheme.text)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    Text(moment)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if extra > 0 {
                    Text("+\(extra)")
                        .font(.footnote.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(DrivyTheme.muted)
                        .padding(.horizontal, DrivySpacing.xs)
                        .frame(minWidth: 32, minHeight: 24)
                        .background(DrivyTheme.surfaceMuted, in: Capsule())
                }
                DrivyRowChevron()
            }
            .padding(.vertical, DrivySpacing.s)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ensuite, \(startTime(lesson)), \(name(lesson)), \(moment)"
                + (extra == 0 ? "" : extra == 1 ? ", et une autre leçon aujourd’hui" : ", et \(extra) autres leçons aujourd’hui"))
        }
        .buttonStyle(DrivyRowButtonStyle())
        .accessibilityHint("Ouvre la prochaine leçon")
        .accessibilityIdentifier("today-next-lesson")
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
            }, presentation: startNow) {
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
            opened = OpenedLesson(lesson: lesson, completing: false,
                starting: SchoolLessonHubRules.mayBegin(lesson, now: Date()))
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
        if case .lesson(let issue) = outcome {
            // Autre compte ou autre école entre-temps : la fiche ne s’ouvre pas, mais le rideau se lève toujours.
            if scopeKey == startKey { opened = OpenedLesson(lesson: lesson, completing: false, issue: issue) }
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

    /// La leçon en tête de la carte : celle qui se déroule, sinon la prochaine, sinon la première manquée restée
    /// sans départ. `planned` est trié par heure de début ; `nil` seulement quand il est vide.
    static func featured(in planned: [SchoolLesson], now: Date) -> SchoolLesson? {
        planned.first { $0.hasStarted }
            ?? planned.first { !$0.hasStarted && !SchoolLessonHubRules.isMissed($0, now: now) }
            ?? planned.first { !$0.hasStarted }
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
