import SwiftUI

struct SchoolAgendaView: View {
    let client: SchoolAgendaClient
    @Bindable var workspace: SchoolWorkspace
    var captureController: SchoolCaptureSessionController? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDate = Date()
    /// Semaine ou mois : relu au lancement, retenu à chaque choix. Le jour choisi est le même dans les deux.
    @State private var displayMode = SchoolAgendaDisplayMode.stored
    /// Sens du dernier changement de mois : la grille suivante arrive de ce côté.
    @State private var monthStep = 1
    @State private var lessons: [SchoolLesson] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var requestID = UUID()
    /// Compte, filtre et fenêtre des leçons affichées ; `nil` tant que rien de sûr n’est lu.
    @State private var loaded: SchoolAgendaScope?
    @State private var freshness = SchoolAgendaFreshness()
    @State private var selectedLesson: SchoolLesson?
    @State private var planningModel: SchoolPlanningWorkspace?
    /// Résultat durable de la feuille de planification, ouvert seulement après la fermeture de celle-ci.
    @State private var planningReturn = SchoolAgendaPlanningReturn()
    /// Leçons de la fenêtre lue (semaine ou grille du mois) rangées par jour, calculées une fois par lecture.
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

    /// Lu des dizaines de fois par rendu (bande de la semaine, grille du mois) : un calendrier par fuseau, gardé.
    private var calendar: Calendar {
        let zone = workspace.school?.timeZone ?? "Europe/Zurich"
        if let known = Self.calendars[zone] { return known }
        var result = Calendar(identifier: .gregorian)
        result.locale = Locale(identifier: "fr_CH")
        result.firstWeekday = 2
        result.timeZone = TimeZone(identifier: zone) ?? .current
        Self.calendars[zone] = result
        return result
    }
    @MainActor private static var calendars: [String: Calendar] = [:]
    private var weekStart: Date { SchoolAgendaMonth.startOfWeek(for: selectedDate, calendar: calendar) }
    private var weekDays: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    /// Compte, droits, école et filtre : ce qui change ici efface l’agenda au lieu de le garder.
    private var scopePrefix: String {
        "\(identityScope):\(workspace.membership?.schoolId.uuidString ?? ""):\(instructorFilter?.uuidString ?? "all")"
    }
    /// La fenêtre à lire : la semaine du jour choisi, ou les six semaines de la grille de son mois.
    private var currentScope: SchoolAgendaScope { scope(for: selectedDate, mode: displayMode) }
    private func scope(for date: Date, mode: SchoolAgendaDisplayMode) -> SchoolAgendaScope {
        SchoolAgendaScope(prefix: scopePrefix, range: SchoolAgendaMonth.range(for: date, mode: mode, calendar: calendar))
    }
    /// Un jour est lu quand la fenêtre affichée, pour ce compte et ce filtre, le contient : une semaine tirée
    /// de son mois, ou la semaine déjà là pendant que le mois arrive, n’a pas à repasser par un squelette.
    private func isLoaded(_ day: Date) -> Bool {
        guard let loaded, loaded.prefix == scopePrefix else { return false }
        return loaded.range.contains(calendar.startOfDay(for: day))
    }
    private var dailyLessons: [SchoolLesson] {
        guard isLoaded(selectedDate) else { return [] }
        return dayIndex[calendar.startOfDay(for: selectedDate)] ?? []
    }
    private var dateTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Aujourd’hui" }
        return SchoolDateFormat.template("EEEEdMMMM", selectedDate, zone: calendar.timeZone.identifier).capitalizedFirst
    }
    private var emptyPresentation: SchoolAgendaEmptyPresentation { SchoolAgendaEmptyPresentation(mayPlan: mayPlan) }

    var body: some View {
        GeometryReader { geometry in
            // Le calendrier garde ses commandes pendant que la liste défile. Les deux
            // colonnes ne sont proposées qu’avec 340 pt de calendrier et 520 pt de liste.
            if geometry.size.width >= AgendaLayout.twoColumnBreakpoint && !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: DrivySpacing.xl) {
                    ScrollView {
                        calendarGroup
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
                    .refreshable { await loadAgenda(keepingCurrent: true) }
                }
                .frame(maxWidth: AgendaLayout.weekColumnWidth + DrivySpacing.xl + AgendaLayout.dayColumnMaxWidth,
                    maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    // Le filtre agit sur toute la période : il reste avec elle, pas entre le jour et ses leçons.
                    VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                        calendarGroup
                        dayGroup
                    }
                    .drivyPageContent(maxWidth: AgendaLayout.singleColumnMaxWidth)
                }
                .refreshable { await loadAgenda(keepingCurrent: true) }
            }
        }
        .background(DrivyTheme.surface)
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.large)
        // Réapparition de l’onglet : la période affichée reste en place pendant la relecture, et une feuille
        // ouverte n’est jamais refermée par elle. Un changement de compte ou de filtre repart de zéro (`loaded`).
        .task(id: currentScope) { await loadAgenda(keepingCurrent: true, navigating: true) }
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            if let change = notification.object as? SchoolLessonChange, change.schoolID != workspace.membership?.schoolId { return }
            // La fermeture de la feuille relira déjà l’agenda ; ne pas ajouter de requête concurrente.
            if selectedLesson == nil && planningModel == nil { Task { await loadAgenda(keepingCurrent: true) } }
        }
        // Une ligne ouvre directement l’écran de la leçon ; l’agenda se relit sans s’effacer à la fermeture
        // (leçon terminée, déplacée ou annulée).
        .sheet(item: $selectedLesson, onDismiss: { Task { await loadAgenda(keepingCurrent: true) } }) { lesson in
            NavigationStack {
                SchoolLessonReportView(client: client.reportClient, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learnerName(lesson), knownLesson: lesson)
            }
            .tint(DrivyTheme.accent)
            .environment(captureController)
        }
        .sheet(item: $planningModel, onDismiss: {
            // La fiche confirmée s'ouvre, et l'agenda derrière elle est relu pour afficher la nouvelle leçon.
            if let lesson = planningReturn.takeConfirmedLesson() { selectedLesson = lesson }
            Task { await loadAgenda(keepingCurrent: true) }
        }) { model in
            SchoolPlanningView(model: model, onConfirmedLesson: { planningReturn.receive($0) })
        }
        .onChange(of: identityScope) { _, _ in
            planningModel?.invalidate(); planningModel = nil; selectedLesson = nil
            planningReturn = SchoolAgendaPlanningReturn(); freshness.reset()
        }
        // Retour au premier plan : la période se relit sans s’effacer, comme Aujourd’hui. Une feuille ouverte
        // relira déjà l’agenda à sa fermeture.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && selectedLesson == nil && planningModel == nil { Task { await loadAgenda(keepingCurrent: true) } }
        }
    }

    /// Le calendrier : affichage, période, jours et filtre serrés ensemble, pour se distinguer nettement de la liste du jour.
    private var calendarGroup: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            modeBar
            periodHeader
            calendarBody
            schoolFilter
        }
    }

    /// Le jour : son titre colle à ses leçons.
    private var dayGroup: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            dayHeading
            // L’état d’une leçon suit l’heure (« En attente » une fois l’horaire passé) sans attendre un autre rendu.
            TimelineView(.everyMinute) { _ in dayContent }
        }
    }

    @ViewBuilder private var schoolFilter: some View {
        if isAdmin && isInstructor {
            Toggle("Toute l’école", isOn: $wholeSchool)
                .drivyControlTint()
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: DrivyLayout.tapTarget)
                .accessibilityIdentifier("agenda-whole-school")
        }
    }

    @ViewBuilder private var dayContent: some View {
        if workspace.membership == nil {
            ContentUnavailableView("Choisis ton école", systemImage: "building.2")
        } else {
            if let error {
                SchoolErrorNotice(message: error, retry: { Task { await loadAgenda(keepingCurrent: true) } })
                if let message = freshness.retainedSuccessMessage(hasError: true, displayedScope: currentScope,
                                                                  timeZone: calendar.timeZone.identifier) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(DrivyTheme.muted)
                        .accessibilityIdentifier("agenda-retained-read-date")
                }
            }
            if !isLoaded(selectedDate) && error == nil {
                DrivySkeletonRows(count: 3, leading: .time).drivySkeleton("Chargement de l’agenda…")
            } else if isLoaded(selectedDate) && dailyLessons.isEmpty {
                // Qui planifie a déjà « Planifier une leçon » dans l’en-tête du jour : pas de second bouton identique.
                DrivyEmptyState(title: "Aucune leçon ce jour", message: "",
                    symbol: "calendar", actionTitle: emptyPresentation.nextDayActionTitle) {
                    if let next = calendar.date(byAdding: .day, value: 1, to: selectedDate) { select(next) }
                }
            } else if isLoaded(selectedDate) {
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

    /// Semaine ou mois, et le retour à aujourd’hui : une ligne de hauteur fixe, que le bouton paraisse ou non.
    private var modeBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DrivySpacing.s) {
                modePicker
                Spacer(minLength: 0)
                todayButton
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                modePicker
                todayButton
            }
        }
        .frame(minHeight: DrivyLayout.tapTarget)
    }
    private var modePicker: some View {
        Picker("Affichage", selection: Binding(get: { displayMode }, set: { setMode($0) })) {
            ForEach(SchoolAgendaDisplayMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .drivyControlTint()
        .accessibilityIdentifier("agenda-display-mode")
    }
    @ViewBuilder private var todayButton: some View {
        if !calendar.isDateInToday(selectedDate) {
            Button("Aujourd’hui") { select(Date()) }
                .buttonStyle(.drivyText)
                .frame(minWidth: DrivyLayout.tapTarget)
                .transition(.opacity)
        }
    }

    /// Le mois et sa navigation : discret au-dessus de la semaine, affirmé au-dessus du mois. 44 pt de flèches.
    private var periodHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DrivySpacing.xs) {
                periodTitle.fixedSize()
                Spacer(minLength: DrivySpacing.xs)
                periodControls.fixedSize()
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                periodTitle
                periodControls
            }
        }
    }
    private var periodTitle: some View {
        let month = displayMode == .month
        return Text(formattedDay(selectedDate, template: "MMMM yyyy").capitalizedFirst)
            .font(month ? Font.headline : Font.subheadline.weight(.semibold))
            .foregroundStyle(month ? DrivyTheme.text : DrivyTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
    private var periodControls: some View {
        let month = displayMode == .month
        return HStack(spacing: DrivySpacing.xxs) {
            arrow("chevron.left", label: month ? "Mois précédent" : "Semaine précédente") { movePeriod(-1) }
            arrow("chevron.right", label: month ? "Mois suivant" : "Semaine suivante") { movePeriod(1) }
        }
    }
    private func arrow(_ symbol: String, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// Semaine ou mois au même endroit : le nouvel affichage se pose en fondu, l’ancien s’efface aussitôt
    /// (une pile ne garde pas deux hauteurs), et la liste du jour suit la hauteur sans saut.
    private var calendarBody: some View {
        ZStack(alignment: .top) {
            if displayMode == .month {
                monthGrid.transition(modeTransition)
            } else {
                dayPicker.transition(modeTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var modeTransition: AnyTransition {
        let insertion: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
        return .asymmetric(insertion: insertion, removal: .identity)
    }
    private var monthGrid: some View {
        SchoolAgendaMonthGrid(calendar: calendar, selectedDate: selectedDate, step: monthStep,
            summary: { daySummary(on: $0) }, select: { select($0) }, moveMonth: { moveMonth($0) })
    }

    private var dayHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.m) {
                Text(dateTitle).font(.drivySection).foregroundStyle(DrivyTheme.text).fixedSize()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DrivySpacing.s)
                if emptyPresentation.showsPlanInHeading { planButton }
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(dateTitle).font(.drivySection).foregroundStyle(DrivyTheme.text).accessibilityAddTraits(.isHeader)
                if emptyPresentation.showsPlanInHeading { planButton }
            }
        }
    }
    private var planButton: some View {
        Button { planningModel = newPlanningModel() } label: { Label("Planifier une leçon", systemImage: "plus") }
            .buttonStyle(.drivyText)
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
            .drivyControlTint()
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.calendar, calendar)
            .environment(\.locale, Locale(identifier: "fr_CH"))
    }
    /// La semaine d’un coup d’œil : le jour choisi plein, aujourd’hui en bleu, une marque par leçon (trois au plus).
    private var weekStrip: some View {
        HStack(spacing: DrivySpacing.xxs) {
            ForEach(weekDays, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                let today = calendar.isDateInToday(day)
                let summary = daySummary(on: day)
                Button { select(day) } label: {
                    VStack(spacing: DrivySpacing.xs) {
                        Text(formattedDay(day, template: "EEEEE").uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? DrivyTheme.onAccent : DrivyTheme.muted)
                        Text(String(calendar.component(.day, from: day)))
                            .font(.title3.weight(selected || today ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(selected ? DrivyTheme.onAccent : today ? DrivyTheme.accent : DrivyTheme.text)
                        SchoolAgendaDayDots(marks: summary.marks, onFill: selected)
                    }
                    .frame(minWidth: DrivyLayout.tapTarget, maxWidth: .infinity, minHeight: 80)
                    .background(selected ? DrivyTheme.accentFill : .clear, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
                }
                .buttonStyle(AgendaDayButtonStyle())
                // « Aujourd’hui » ne se lit pas qu’à la couleur du chiffre.
                .accessibilityLabel(today ? "Aujourd’hui, \(formattedDay(day, template: "EEEE d MMMM"))" : formattedDay(day, template: "EEEE d MMMM"))
                .accessibilityValue(summary.spokenCount)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(DrivySpacing.xxs)
        .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.xxs))
        // La bande de la semaine est un sélecteur : un léger retour de sélection, comme les roues du système.
        .sensoryFeedback(.selection, trigger: selectedDate)
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
    /// Mêmes leçons, même comptage dans la semaine et dans le mois ; rien tant que le jour n’est pas lu.
    private func daySummary(on day: Date) -> SchoolAgendaDaySummary {
        guard isLoaded(day) else { return .empty }
        let lessons = dayIndex[calendar.startOfDay(for: day)] ?? []
        let closed = lessons.filter { $0.drivyState.isClosed }.count
        return SchoolAgendaDaySummary(active: lessons.count - closed, closed: closed)
    }
    private func moveWeek(_ offset: Int) { if let date = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) { select(date) } }
    /// Même jour du mois voisin, ramené au dernier jour s’il n’existe pas (31 janvier → février).
    private func moveMonth(_ offset: Int) { select(SchoolAgendaMonth.shiftingMonth(selectedDate, by: offset, calendar: calendar)) }
    private func movePeriod(_ offset: Int) {
        if displayMode == .month { moveMonth(offset) } else { moveWeek(offset) }
    }
    /// Changer de jour, de semaine ou de mois : la liste passe en fondu, sans remplacement sec.
    private func select(_ date: Date) {
        let from = SchoolAgendaMonth.startOfMonth(for: selectedDate, calendar: calendar)
        let to = SchoolAgendaMonth.startOfMonth(for: date, calendar: calendar)
        if from != to { monthStep = to > from ? 1 : -1 }
        withAnimation(DrivyMotion.reveal(reduceMotion)) {
            selectedDate = date
            recall(scope(for: date, mode: displayMode))
        }
    }
    /// Semaine ↔ mois : même jour, mêmes leçons ; la fenêtre déjà lue arrive dans le même fondu.
    private func setMode(_ mode: SchoolAgendaDisplayMode) {
        guard mode != displayMode else { return }
        SchoolAgendaDisplayMode.stored = mode
        withAnimation(DrivyMotion.reveal(reduceMotion)) {
            displayMode = mode
            recall(scope(for: selectedDate, mode: mode))
        }
    }
    /// Fenêtre déjà lue (ou contenue dans un mois lu) : elle s’affiche aussitôt, sans passer par un squelette.
    private func recall(_ wanted: SchoolAgendaScope) {
        guard loaded != wanted, let remembered = SchoolAgendaMemory.lessons(prefix: wanted.prefix, range: wanted.range) else { return }
        show(remembered.lessons, scope: wanted)
        freshness.recordSuccess(scope: wanted, at: remembered.readAt)
    }
    private func newPlanningModel() -> SchoolPlanningWorkspace? {
        guard let person = workspace.person, let membership = workspace.membership, mayPlan else { return nil }
        let day = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let proposed = max(day, Date().addingTimeInterval(3600))
        // Le prochain créneau libre se cherche à partir du jour affiché (ou de maintenant, s’il est passé) ;
        // l’horaire proposé ne sert que si l’école ne connaît pas encore cette recherche.
        let from = max(calendar.startOfDay(for: selectedDate), Date())
        return SchoolPlanningWorkspace(scope: client.scope(person: person, membership: membership), client: client.planningClient,
            date: proposed, suggestingNextSlotFrom: from)
    }
    /// `keepingCurrent` : relecture sans effacer ce qui est affiché (retour d’une leçon, tirer pour actualiser).
    /// `navigating` : changement de jour, de période ou d’affichage. Une fenêtre lue il y a quelques secondes
    /// n’est pas relue, et le mois affiché fait lire d’avance ses deux voisins.
    @MainActor private func loadAgenda(keepingCurrent: Bool = false, navigating: Bool = false) async {
        let id = UUID(); requestID = id
        let wanted = currentScope, filter = instructorFilter, anchor = selectedDate, mode = displayMode
        var keeps = keepingCurrent && loaded == wanted
        var fresh = false
        if let remembered = SchoolAgendaMemory.lessons(prefix: wanted.prefix, range: wanted.range) {
            // Fenêtre déjà lue pour ce compte, ce filtre et ces dates : elle s’affiche aussitôt, sans squelette,
            // et la relecture qui suit la remplace sans rien effacer.
            if !keeps {
                show(remembered.lessons, scope: wanted); freshness.recordSuccess(scope: wanted, at: remembered.readAt)
                error = nil; keeps = true
            }
            fresh = remembered.isFresh
        } else if !keeps {
            // Même compte, même filtre : ce qui est déjà lu reste juste pour ses propres jours (la semaine pendant
            // que son mois arrive). Un autre compte, une autre école ou un autre filtre repart de zéro.
            if loaded?.prefix != wanted.prefix { lessons = []; dayIndex = [:]; loaded = nil; freshness.reset() }
            error = nil
        }
        guard let schoolID = workspace.membership?.schoolId else { isLoading = false; return }
        if navigating && fresh && error == nil {
            isLoading = false
            if mode == .month { await prefetchNeighbours(of: anchor, prefix: wanted.prefix, schoolID: schoolID, filter: filter, id: id) }
            return
        }
        if !keeps { isLoading = true }
        defer { if requestID == id { isLoading = false } }
        do {
            guard let all = try await fetchLessons(schoolID: schoolID, range: wanted.range, filter: filter,
                stillWanted: { requestID == id && currentScope == wanted }) else { return }
            let readAt = Date()
            show(all, scope: wanted); freshness.recordSuccess(scope: wanted, at: readAt); error = nil
            SchoolAgendaMemory.remember(all, prefix: wanted.prefix, range: wanted.range, now: readAt)
            if navigating && mode == .month { await prefetchNeighbours(of: anchor, prefix: wanted.prefix, schoolID: schoolID, filter: filter, id: id) }
        } catch {
            guard !Task.isCancelled, requestID == id, currentScope == wanted else { return }
            switch error as? SchoolAgendaFailure {
            case .authentication, .forbidden:
                SchoolAgendaMemory.forget()
                lessons = []; dayIndex = [:]; loaded = nil; selectedLesson = nil; freshness.reset()
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

    /// Toutes les pages d’une fenêtre (une seule requête par page, quelle que soit sa longueur) ;
    /// `nil` dès qu’une lecture plus récente ou un autre compte l’a remplacée.
    @MainActor private func fetchLessons(schoolID: UUID, range: SchoolAgendaRange, filter: UUID?,
                                         stillWanted: () -> Bool) async throws -> [SchoolLesson]? {
        var all: [SchoolLesson] = [], cursor: String?, seen = Set<String>()
        repeat {
            let page = try await client.lessons(schoolID: schoolID, from: range.start, to: range.end, cursor: cursor, instructorMembershipID: filter)
            guard !Task.isCancelled, stillWanted() else { return nil }
            all.append(contentsOf: page.items); cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw SchoolAgendaFailure.invalidResponse }
            if all.count > 10_000 { throw SchoolAgendaFailure.invalidResponse }
        } while cursor != nil
        guard Set(all.map(\.id)).count == all.count else { throw SchoolAgendaFailure.invalidResponse }
        return all
    }

    /// Mois voisins lus d’avance, en mémoire seulement : passer au mois suivant ou précédent ne montre pas
    /// de squelette. Abandonné dès qu’une autre lecture commence ; un échec ici ne s’affiche pas, la
    /// navigation relira normalement.
    @MainActor private func prefetchNeighbours(of anchor: Date, prefix: String, schoolID: UUID, filter: UUID?, id: UUID) async {
        for offset in [1, -1] {
            guard !Task.isCancelled, requestID == id else { return }
            let month = SchoolAgendaMonth.shiftingMonth(anchor, by: offset, calendar: calendar)
            let range = SchoolAgendaMonth.gridRange(for: month, calendar: calendar)
            if SchoolAgendaMemory.lessons(prefix: prefix, range: range) != nil { continue }
            guard let all = try? await fetchLessons(schoolID: schoolID, range: range, filter: filter,
                stillWanted: { requestID == id && scopePrefix == prefix }) else { return }
            SchoolAgendaMemory.remember(all, prefix: prefix, range: range)
        }
    }
}

extension SchoolAgendaView {
    @MainActor fileprivate func show(_ all: [SchoolLesson], scope: SchoolAgendaScope) {
        lessons = all; loaded = scope
        dayIndex = SchoolAgendaMonth.index(all, calendar: calendar, start: { $0.startsAt },
            order: { $0.plannedStart < $1.plannedStart })
    }
}

/// Ce que montre l’agenda : pour quel compte, école et filtre (`prefix`), sur quelle fenêtre.
struct SchoolAgendaScope: Hashable, Sendable {
    let prefix: String
    let range: SchoolAgendaRange
}

/// Fenêtres de l’agenda déjà lues (semaines, grilles de mois), en mémoire seulement, par compte, droits, école
/// et filtre (`prefix`) : aucun autre compte ni filtre ne les retrouve, rien n’est écrit sur l’appareil.
/// Oubliées à chaque leçon modifiée. Une semaine contenue dans un mois lu en est tirée sans nouvelle lecture.
@MainActor enum SchoolAgendaMemory {
    private struct Entry {
        let prefix: String
        let range: SchoolAgendaRange
        let lessons: [SchoolLesson]
        let readAt: Date
    }
    private static var entries: [Entry] = []
    /// Lue depuis moins longtemps, une fenêtre n’est pas relue en changeant de jour, de période ou d’affichage.
    /// Tirer pour actualiser, revenir au premier plan ou modifier une leçon relisent toujours.
    static let freshness: TimeInterval = 30

    static func lessons(prefix: String, range: SchoolAgendaRange, now: Date = Date()) -> (lessons: [SchoolLesson], isFresh: Bool, readAt: Date)? {
        // La plus récente d’abord : la même fenêtre, ou une qui la contient (la semaine dans son mois).
        guard let entry = entries.last(where: { $0.prefix == prefix && $0.range.contains(range) }) else { return nil }
        let lessons = entry.range == range ? entry.lessons : entry.lessons.filter { lesson in
            guard let start = lesson.startsAt, let end = lesson.endsAt else { return false }
            return range.overlaps(start: start, end: end)
        }
        return (lessons, now.timeIntervalSince(entry.readAt) < freshness, entry.readAt)
    }

    static func remember(_ lessons: [SchoolLesson], prefix: String, range: SchoolAgendaRange, now: Date = Date()) {
        entries.removeAll { $0.prefix == prefix && $0.range == range }
        entries.append(Entry(prefix: prefix, range: range, lessons: lessons, readAt: now))
        // Quelques semaines et mois suffisent pour aller et venir ; les plus anciens sont oubliés.
        while entries.count > 12 { entries.removeFirst() }
    }

    static func forget() { entries = [] }
}

/// Retour d’appui d’un jour de la semaine ou du mois : le même que partout, nul sous Réduire les animations.
struct AgendaDayButtonStyle: ButtonStyle {
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
    /// `source` : récepteur déjà réveillé par le démarrage immédiat, repris tel quel au lieu d’en créer un autre.
    func capturePreparation(scope: SchoolCommandScope, lessonID: UUID, controller: SchoolCaptureSessionController?,
                            source warmSource: (any SchoolCaptureLocationProviding)? = nil) -> SchoolCapturePreparationWorkspace {
        guard let controller else {
            return SchoolCapturePreparationWorkspace(scope: scope, lessonID: lessonID, client: captureClient, reader: reader, agenda: self)
        }
        let makeSource: @MainActor () -> any SchoolCaptureLocationProviding = {
            if let warmSource { return warmSource }
            return SchoolCaptureLocationSource()
        }
        let handler: SchoolCaptureStartHandler = { transfer, source, session, lease, authorization, receivedAt in
            try await controller.adoptAndStart(transfer: transfer, source: source, session: session,
                lease: lease, authorization: authorization, receivedAt: receivedAt)
        }
        return SchoolCapturePreparationWorkspace(scope: scope, lessonID: lessonID,
            client: captureClient, reader: reader, agenda: self,
            journalProvider: { try await controller.journal() }, onCaptureAuthorized: handler,
            onRefusalConfirmed: { learnerID, lessonID in controller.learnerRefused(learnerID: learnerID, lessonID: lessonID) },
            canUseDiagnostic: { controller.canPrepareCapture },
            settleInterruptedCaptures: { lessonID in await controller.settleInterruptedCaptures(lessonID: lessonID) },
            makeLocationSource: makeSource)
    }
}
