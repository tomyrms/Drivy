import SwiftUI

struct SchoolAgendaView: View {
    let client: SchoolAgendaClient
    @Bindable var workspace: SchoolWorkspace
    var captureController: SchoolCaptureSessionController? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate = Date()
    @State private var lessons: [SchoolLesson] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedScope: String?
    @State private var selectedLesson: SchoolLesson?
    @State private var planningModel: SchoolPlanningWorkspace?
    /// Leçons de la semaine rangées par jour, calculées une fois par lecture.
    @State private var dayIndex: [Date: [SchoolLesson]] = [:]
    /// Administration qui enseigne aussi : ses leçons par défaut, toute l’école sur demande.
    @State private var wholeSchool = false

    private var identityScope: String { "\(workspace.person?.id.uuidString ?? ""):\(workspace.membership?.id.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0)" }
    private var mayPlan: Bool { workspace.membership?.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) == true && workspace.school?.status == "ACTIVE" }
    private var isAdmin: Bool { workspace.membership?.roles.contains("ADMIN") == true }
    private var isInstructor: Bool { workspace.membership?.roles.contains("INSTRUCTOR") == true }
    /// Un moniteur voit ses leçons ; l’école entière seulement pour l’administration (filtre relu par le serveur).
    private var instructorFilter: UUID? { isInstructor && !(isAdmin && wholeSchool) ? workspace.membership?.membershipId : nil }
    private var showsInstructor: Bool { instructorFilter == nil && isAdmin }

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "fr_CH")
        result.firstWeekday = 2
        result.timeZone = TimeZone(identifier: workspace.school?.timeZone ?? "Europe/Zurich") ?? .current
        return result
    }
    private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? calendar.startOfDay(for: selectedDate) }
    private var weekDays: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    private var dailyLessons: [SchoolLesson] {
        guard loadedScope == scopeKey else { return [] }
        return dayIndex[calendar.startOfDay(for: selectedDate)] ?? []
    }
    private var scopeKey: String { "\(identityScope):\(workspace.membership?.schoolId.uuidString ?? ""):\(weekStart.timeIntervalSince1970):\(instructorFilter?.uuidString ?? "all")" }
    private var dateTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Aujourd’hui" }
        return SchoolDateFormat.template("EEEEdMMMM", selectedDate, zone: calendar.timeZone.identifier).capitalizedFirst
    }

    var body: some View {
        GeometryReader { geometry in
            // La semaine garde ses commandes pendant que la liste défile. Les deux
            // colonnes ne sont proposées qu’avec 340 pt de calendrier et 520 pt de liste.
            if geometry.size.width >= AgendaLayout.twoColumnBreakpoint && !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: DrivySpacing.xl) {
                    ScrollView {
                        weekGroup
                            .padding(DrivySpacing.l)
                    }
                    .frame(width: AgendaLayout.weekColumnWidth)
                    .background(DrivyTheme.canvas)
                    ScrollView {
                        dayGroup
                        .padding(.vertical, DrivySpacing.l)
                        .padding(.trailing, DrivySpacing.xl)
                    }
                    .frame(maxWidth: AgendaLayout.dayColumnMaxWidth)
                    .refreshable { await loadWeek(keepingCurrent: true) }
                }
                .frame(maxWidth: AgendaLayout.weekColumnWidth + DrivySpacing.xl + AgendaLayout.dayColumnMaxWidth,
                    maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    // Le filtre agit sur toute la semaine : il reste avec elle, pas entre le jour et ses leçons.
                    VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                        weekGroup
                        dayGroup
                    }
                    .drivyPageContent(maxWidth: AgendaLayout.singleColumnMaxWidth)
                }
                .refreshable { await loadWeek(keepingCurrent: true) }
            }
        }
        .background(DrivyTheme.surface)
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.large)
        // Réapparition de l’onglet : la semaine affichée reste en place pendant la relecture, et une feuille
        // ouverte n’est jamais refermée par elle. Un changement de semaine ou de filtre repart de zéro (loadedScope).
        .task(id: scopeKey) { await loadWeek(keepingCurrent: true) }
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            if let change = notification.object as? SchoolLessonChange, change.schoolID != workspace.membership?.schoolId { return }
            // La fermeture de la feuille relira déjà la semaine ; ne pas ajouter de requête concurrente.
            if selectedLesson == nil && planningModel == nil { Task { await loadWeek(keepingCurrent: true) } }
        }
        // Une ligne ouvre directement l’écran de la leçon ; l’agenda se relit sans s’effacer à la fermeture
        // (leçon terminée, déplacée ou annulée).
        .sheet(item: $selectedLesson, onDismiss: { Task { await loadWeek(keepingCurrent: true) } }) { lesson in
            NavigationStack {
                SchoolLessonReportView(client: client.reportClient, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learnerName(lesson))
            }
            .tint(DrivyTheme.accent)
            .environment(captureController)
        }
        .sheet(item: $planningModel, onDismiss: { Task { await loadWeek(keepingCurrent: true) } }) { model in SchoolPlanningView(model: model) }
        .onChange(of: identityScope) { _, _ in
            planningModel?.invalidate(); planningModel = nil; selectedLesson = nil
        }
        // Retour au premier plan : la semaine se relit sans s’effacer, comme Aujourd’hui. Une feuille ouverte
        // relira déjà l’agenda à sa fermeture.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && selectedLesson == nil && planningModel == nil { Task { await loadWeek(keepingCurrent: true) } }
        }
    }

    /// La semaine : mois, jours et filtre serrés ensemble, pour se distinguer nettement de la liste du jour.
    private var weekGroup: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            weekHeader
            dayPicker
            schoolFilter
        }
    }

    /// Le jour : son titre colle à ses leçons.
    private var dayGroup: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            dayHeading
            dayContent
        }
    }

    @ViewBuilder private var schoolFilter: some View {
        if isAdmin && isInstructor {
            Toggle("Toute l’école", isOn: $wholeSchool)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("agenda-whole-school")
        }
    }

    @ViewBuilder private var dayContent: some View {
        if workspace.membership == nil {
            ContentUnavailableView("Choisis ton école", systemImage: "building.2")
        } else {
            if let error {
                SchoolErrorNotice(message: error, retry: { Task { await loadWeek(keepingCurrent: true) } })
            }
            if loadedScope != scopeKey && error == nil {
                DrivySkeletonRows(count: 3, leading: .time).drivySkeleton("Chargement de l’agenda…")
            } else if loadedScope == scopeKey && dailyLessons.isEmpty {
                // Qui planifie a déjà « Planifier une leçon » dans l’en-tête du jour : pas de second bouton identique.
                DrivyEmptyState(title: "Aucune leçon ce jour", message: "",
                    symbol: "calendar", actionTitle: mayPlan ? nil : "Voir le jour suivant") {
                    if let next = calendar.date(byAdding: .day, value: 1, to: selectedDate) { selectedDate = next }
                }
            } else if loadedScope == scopeKey {
                LazyVStack(spacing: 0) {
                    ForEach(Array(dailyLessons.enumerated()), id: \.element.id) { index, lesson in
                        Button { selectedLesson = lesson } label: {
                            lessonRow(lesson, position: .at(index, count: dailyLessons.count))
                        }
                            .buttonStyle(DrivyRowButtonStyle())
                            .accessibilityHint("Ouvre la leçon")
                    }
                }
            }
        }
    }

    /// Month context and week navigation, as in the mockup: quiet month, 44 pt arrows.
    private var weekHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DrivySpacing.xs) {
                monthTitle.fixedSize()
                Spacer(minLength: DrivySpacing.xs)
                weekControls.fixedSize()
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                monthTitle
                weekControls
            }
        }
    }
    private var monthTitle: some View {
        Text(formattedDay(selectedDate, template: "MMMM yyyy").capitalizedFirst)
            .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
    private var weekControls: some View {
        HStack(spacing: DrivySpacing.xxs) {
            if !calendar.isDateInToday(selectedDate) {
                Button("Aujourd’hui") { selectedDate = Date() }
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 44, minHeight: 44)
            }
            Button { moveWeek(-1) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Semaine précédente")
            Button { moveWeek(1) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Semaine suivante")
        }
    }

    private var dayHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.m) {
                Text(dateTitle).font(.drivySection).foregroundStyle(DrivyTheme.text).fixedSize()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DrivySpacing.s)
                if mayPlan { planButton }
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(dateTitle).font(.drivySection).foregroundStyle(DrivyTheme.text).accessibilityAddTraits(.isHeader)
                if mayPlan { planButton }
            }
        }
    }
    private var planButton: some View {
        Button { planningModel = newPlanningModel() } label: {
            Label("Planifier une leçon", systemImage: "plus").font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.accent)
                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("agenda-plan-lesson")
    }
    @ViewBuilder private var dayPicker: some View {
        if typeSize.isAccessibilitySize { compactDayPicker }
        else {
            ViewThatFits(in: .horizontal) {
                weekStrip
                compactDayPicker
            }
        }
    }
    private var compactDayPicker: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text("Choisir un jour").accessibilityHidden(true)
                    DatePicker("Choisir un jour", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("Choisir un jour")
                }
            } else {
                DatePicker("Choisir un jour", selection: $selectedDate, displayedComponents: .date)
            }
        }
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.calendar, calendar)
            .environment(\.locale, Locale(identifier: "fr_CH"))
    }
    /// La semaine d’un coup d’œil : le jour choisi plein, aujourd’hui en bleu, un point par leçon (trois au plus).
    private var weekStrip: some View {
        HStack(spacing: DrivySpacing.xxs) {
            ForEach(weekDays, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                let today = calendar.isDateInToday(day)
                let count = lessonCount(on: day)
                Button { selectedDate = day } label: {
                    VStack(spacing: DrivySpacing.xs) {
                        Text(formattedDay(day, template: "EEEEE").uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? DrivyTheme.onAccent : DrivyTheme.muted)
                        Text(String(calendar.component(.day, from: day)))
                            .font(.title3.weight(selected || today ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(selected ? DrivyTheme.onAccent : today ? DrivyTheme.accent : DrivyTheme.text)
                        HStack(spacing: DrivySpacing.xxs) {
                            ForEach(0..<max(min(count, 3), 1), id: \.self) { _ in
                                Circle().fill(count > 0 ? (selected ? DrivyTheme.onAccent : DrivyTheme.accent) : .clear)
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 80)
                    .background(selected ? DrivyTheme.accent : .clear, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                }
                .buttonStyle(AgendaDayButtonStyle())
                // « Aujourd’hui » ne se lit pas qu’à la couleur du chiffre.
                .accessibilityLabel(today ? "Aujourd’hui, \(formattedDay(day, template: "EEEE d MMMM"))" : formattedDay(day, template: "EEEE d MMMM"))
                .accessibilityValue(count == 0 ? "" : count == 1 ? "1 leçon" : "\(count) leçons")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(DrivySpacing.xxs)
        .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.xxs))
    }

    /// Same row anatomy as the training dossier and the report lists: the time column already
    /// gives start and end, so the meta lines keep only who and where. An unusual state
    /// (à terminer, annulée, absence) is one word at the head of the detail line, no capsule.
    private func lessonRow(_ lesson: SchoolLesson, position: DrivyThreadPosition) -> some View {
        var details = [lesson.meetingPoint]
        if showsInstructor, let instructor = lesson.providedInstructorName { details.insert(instructor, at: 0) }
        return DrivyLessonRow(start: time(lesson.startsAt), end: time(lesson.endsAt), title: learnerName(lesson),
            details: details, state: lesson.drivyState, railPosition: position)
    }

    /// Nom fourni avec la leçon, sinon celui d’un dossier déjà chargé ; jamais deviné.
    private func learnerName(_ lesson: SchoolLesson) -> String {
        lesson.providedLearnerName ?? workspace.learners.first { $0.id == lesson.learnerId }?.displayName ?? "Leçon de conduite"
    }
    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return SchoolDateFormat.time(date, zone: calendar.timeZone.identifier)
    }
    private func formattedDay(_ date: Date, template: String) -> String {
        SchoolDateFormat.template(template, date, zone: calendar.timeZone.identifier)
    }
    private func lessonCount(on day: Date) -> Int {
        loadedScope == scopeKey ? (dayIndex[calendar.startOfDay(for: day)] ?? []).count : 0
    }
    private func moveWeek(_ offset: Int) { if let date = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) { selectedDate = date } }
    private func newPlanningModel() -> SchoolPlanningWorkspace? {
        guard let person = workspace.person, let membership = workspace.membership, mayPlan else { return nil }
        let day = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let proposed = max(day, Date().addingTimeInterval(3600))
        return SchoolPlanningWorkspace(scope: client.scope(person: person, membership: membership), client: client.planningClient, date: proposed)
    }
    /// `keepingCurrent` : relecture sans effacer la semaine affichée (retour d’une leçon, tirer pour actualiser).
    @MainActor private func loadWeek(keepingCurrent: Bool = false) async {
        let id = UUID(); requestID = id
        let keeps = keepingCurrent && loadedScope == scopeKey
        if !keeps { lessons = []; dayIndex = [:]; error = nil; loadedScope = nil }
        guard let schoolID = workspace.membership?.schoolId, let end = calendar.date(byAdding: .day, value: 7, to: weekStart) else { isLoading = false; return }
        let start = weekStart, scope = scopeKey
        if !keeps { isLoading = true }
        defer { if requestID == id { isLoading = false } }
        do {
            var all: [SchoolLesson] = [], cursor: String?, seen = Set<String>()
            repeat {
                let page = try await client.lessons(schoolID: schoolID, from: start, to: end, cursor: cursor, instructorMembershipID: instructorFilter)
                guard !Task.isCancelled, requestID == id, scopeKey == scope else { return }
                all.append(contentsOf: page.items); cursor = page.nextCursor
                if let cursor, !seen.insert(cursor).inserted { throw SchoolAgendaFailure.invalidResponse }
                if all.count > 10_000 { throw SchoolAgendaFailure.invalidResponse }
            } while cursor != nil
            guard Set(all.map(\.id)).count == all.count else { throw SchoolAgendaFailure.invalidResponse }
            let calendar = self.calendar
            lessons = all; loadedScope = scope; error = nil
            dayIndex = Dictionary(grouping: all.filter { $0.startsAt != nil }) { calendar.startOfDay(for: $0.startsAt!) }
                .mapValues { $0.sorted { $0.plannedStart < $1.plannedStart } }
        } catch {
            guard !Task.isCancelled, requestID == id, scopeKey == scope else { return }
            switch error as? SchoolAgendaFailure {
            case .authentication, .forbidden:
                lessons = []; dayIndex = [:]; loadedScope = nil; selectedLesson = nil
                self.error = (error as? LocalizedError)?.errorDescription ?? "L’agenda n’a pas pu être chargé."
                // « Réessayer » seul ne sortirait jamais d’une session expirée ou d’un accès retiré : le compte est
                // relu. Refusé, il ouvre la reconnexion ; modifié, il recharge l’école ; inchangé, rien ne bouge.
                await workspace.refreshAccount(minimumInterval: 0)
                return
            default: break
            }
            self.error = (error as? LocalizedError)?.errorDescription ?? "L’agenda n’a pas pu être chargé."
        }
    }
}

/// Retour d’appui d’un jour de la semaine : le même que partout, nul sous Réduire les animations.
private struct AgendaDayButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? DrivyPress.scale : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

/// Colonnes de l’agenda : semaine et liste du jour côte à côte dès 1000 pt
/// (340 pt de calendrier utile et 520 pt de liste), sinon un seul flux.
private enum AgendaLayout {
    static let twoColumnBreakpoint: CGFloat = 1000
    static let weekColumnWidth: CGFloat = 388
    static let dayColumnMaxWidth = DrivyLayout.formColumn
    static let singleColumnMaxWidth = DrivyLayout.formColumn
}

extension SchoolAgendaClient {
    /// Préparation du trajet d’une leçon : l’agenda et « Aujourd’hui » partagent exactement ce chemin.
    func capturePreparation(scope: SchoolCommandScope, lessonID: UUID, controller: SchoolCaptureSessionController?) -> SchoolCapturePreparationWorkspace {
        guard let controller else {
            return SchoolCapturePreparationWorkspace(scope: scope, lessonID: lessonID, client: captureClient, reader: reader, agenda: self)
        }
        let handler: SchoolCaptureStartHandler = { transfer, source, session, lease, authorization, receivedAt in
            try await controller.adoptAndStart(transfer: transfer, source: source, session: session,
                lease: lease, authorization: authorization, receivedAt: receivedAt)
        }
        return SchoolCapturePreparationWorkspace(scope: scope, lessonID: lessonID,
            client: captureClient, reader: reader, agenda: self,
            journalProvider: { try await controller.journal() }, onCaptureAuthorized: handler,
            onRefusalConfirmed: { learnerID, lessonID in controller.learnerRefused(learnerID: learnerID, lessonID: lessonID) },
            canUseDiagnostic: { controller.canPrepareCapture })
    }
}
