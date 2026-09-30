import SwiftUI

enum SchoolTrainingSection: String, CaseIterable { case lessons = "Leçons", progress = "Progression" }

/// Le calendrier de la leçon fait foi, même près de minuit ou d'un changement d'année UTC.
struct SchoolLessonPeriod: Equatable {
    var month = 0
    var year = 0
    var isActive: Bool { month != 0 || year != 0 }
    func includes(_ lesson: SchoolLesson) -> Bool {
        guard let parts = Self.parts(lesson) else { return !isActive }
        return (month == 0 || parts.month == month) && (year == 0 || parts.year == year)
    }
    static func parts(_ lesson: SchoolLesson) -> DateComponents? {
        guard let date = lesson.startsAt, let zone = TimeZone(identifier: lesson.timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.dateComponents([.year, .month], from: date)
    }
    var title: String {
        var values: [String] = []
        if (1...12).contains(month) { values.append(Self.monthName(month)) }
        if year != 0 { values.append(String(year)) }
        return values.joined(separator: " ")
    }
    static func monthName(_ month: Int) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH")
        return formatter.standaloneMonthSymbols[month - 1].capitalizedFirst
    }
}

/// La formation ouverte depuis le dossier d’un élève (moniteur).
struct SchoolTrainingView: View {
    let client: SchoolTrainingClient
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let trainingID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SchoolTrainingScreen(client: client, workspace: workspace, learner: learner, trainingID: trainingID)
                .navigationTitle("Formation")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
        .tint(DrivyTheme.accent)
        .presentationSizing(.page)
    }
}

/// Leçons et progression d’une formation. Les onglets de l’élève fixent la section ;
/// sans section fixée, un sélecteur passe de l’une à l’autre.
struct SchoolTrainingScreen: View {
    let client: SchoolTrainingClient
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let trainingID: UUID
    var section: SchoolTrainingSection? = nil
    @State private var model: SchoolTrainingWorkspace?
    /// La leçon ouverte vit ici, hors du contenu conditionnel et de `.id` : une relecture ou un changement
    /// de portée recrée le contenu, jamais la feuille qui le surplombe.
    @State private var opened: OpenedLesson?
    @Environment(\.scenePhase) private var scenePhase

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(trainingID)"
    }
    var body: some View {
        Group {
            if let model, matches(model) {
                SchoolTrainingContent(model: model, workspace: workspace, learner: learner, fixedSection: section, opened: $opened)
            } else {
                ProgressView("Chargement de la formation…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DrivyTheme.surface)
            }
        }
        .id(scopeKey)
        .task(id: scopeKey) {
            if let model, matches(model), model.trainingID == trainingID {
                // Retour sur l’écran ou changement d’onglet : toujours relire, sans effacer ce qui est affiché.
                await model.refreshOnAppear()
                return
            }
            model = nil
            guard let person = workspace.person, let membership = workspace.membership else { return }
            let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
                membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
            let shared = SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner.id,
                trainingID: trainingID, client: client)
            model = shared.model
            // Le modèle partagé peut dater d’avant un bilan enregistré ailleurs : relecture à chaque affichage.
            await shared.model.load(keepingCurrent: !shared.isNew)
        }
        .onChange(of: model?.accessRevoked) { _, revoked in
            // Relecture silencieuse : `loadAccount` vide le compte et fait disparaître tout l’écran (feuille ouverte comprise).
            if revoked == true { Task { await workspace.refreshAccount(minimumInterval: 0) } }
        }
        // Une leçon planifiée ailleurs (feuille de planification du dossier) : la liste se relit sans être recréée.
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            if let change = notification.object as? SchoolLessonChange,
               change.schoolID != workspace.membership?.schoolId || change.trainingID != trainingID { return }
            if let model, matches(model) { Task { await model.refreshOnAppear() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let model, matches(model) { Task { await model.refreshOnAppear() } }
        }
        .sheet(item: $opened, onDismiss: { if let model { Task { await model.load(keepingCurrent: true) } } }) { lesson in
            NavigationStack {
                SchoolLessonReportView(client: client.reports, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learner.displayName,
                    isNextPlanned: lesson.id == model?.upcomingLessons.first?.id)
            }
            .tint(DrivyTheme.accent)
        }
    }
    private func matches(_ model: SchoolTrainingWorkspace) -> Bool {
        model.learnerID == learner.id && model.trainingID == trainingID
            && model.scope.personID == workspace.person?.personId && model.scope.membershipID == workspace.membership?.membershipId
            && model.scope.accessEpoch == workspace.membership?.accessEpoch && model.membership.roles == workspace.membership?.roles
            && model.membership.grants == workspace.membership?.grants
    }
}

private struct OpenedLesson: Identifiable { let id: UUID }

extension Notification.Name {
    /// Une leçon vient d’être créée, déplacée ou annulée hors de l’écran qui la montre.
    static let drivyLessonsDidChange = Notification.Name("drivy.lessonsDidChange")
}

/// Émis seulement après confirmation durable d'une commande, sans contenu pédagogique ni position.
struct SchoolLessonChange: Sendable {
    let schoolID: UUID
    let trainingID: UUID
    let lessonID: UUID
}

/// Filtre de statut des leçons du dossier. Deux ensembles disjoints (à venir, passées) ; « À terminer »
/// est le sous-ensemble des passées restées sans issue.
private enum TrainingLessonFilter: String, CaseIterable, Identifiable {
    case all, upcoming, past, toFinish
    var id: String { rawValue }
    var title: String {
        switch self { case .all: "Toutes"; case .upcoming: "À venir"; case .past: "Passées"; case .toFinish: "À terminer" }
    }
    var emptyTitle: String {
        switch self {
        case .all: "Aucune leçon"
        case .upcoming: "Aucune leçon à venir"
        case .past: "Aucune leçon passée"
        case .toFinish: "Aucune leçon à terminer"
        }
    }
    func includes(_ lesson: SchoolLesson) -> Bool {
        let state = lesson.drivyState
        let isUpcoming = lesson.status == "PLANNED" && state != .toFinish
        switch self {
        case .all: return true
        case .upcoming: return isUpcoming
        case .past: return !isUpcoming
        case .toFinish: return state == .toFinish
        }
    }
}

/// Ordre des leçons. « Chronologique » garde la prochaine leçon en tête : à venir (croissant), à terminer,
/// puis passées (la plus récente d’abord). Les deux autres sont strictement croissant ou décroissant.
private enum TrainingLessonOrder: String, CaseIterable, Identifiable {
    case chronological, newestFirst, oldestFirst
    var id: String { rawValue }
    var title: String {
        switch self { case .chronological: "Chronologique"; case .newestFirst: "Plus récentes d’abord"; case .oldestFirst: "Plus anciennes d’abord" }
    }
    var symbol: String {
        switch self { case .chronological: "arrow.up.arrow.down"; case .newestFirst: "arrow.down"; case .oldestFirst: "arrow.up" }
    }
}

private struct TrainingLessonMonth: Identifiable {
    let id: String
    let title: String
    let lessons: [SchoolLesson]
}

private struct SchoolTrainingContent: View {
    @Bindable var model: SchoolTrainingWorkspace
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let fixedSection: SchoolTrainingSection?
    @Binding var opened: OpenedLesson?
    @State private var chosenSection: SchoolTrainingSection = .lessons
    /// Le tri et le filtre survivent aux changements d’onglet et de dossier pendant la session de la scène.
    @SceneStorage("training.lessons.filter") private var filter: TrainingLessonFilter = .all
    @SceneStorage("training.lessons.order") private var order: TrainingLessonOrder = .chronological
    @SceneStorage("training.lessons.month") private var selectedMonth = 0
    @SceneStorage("training.lessons.year") private var selectedYear = 0
    @State private var showsPeriod = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var section: SchoolTrainingSection { fixedSection ?? chosenSection }
    private var period: SchoolLessonPeriod { SchoolLessonPeriod(month: selectedMonth, year: selectedYear) }

    var body: some View {
        GeometryReader { geometry in
            // Dans un grand détail, les leçons et leur progression restent visibles ensemble.
            // Le sélecteur est conservé quand chaque colonne n’aurait plus 460 pt de lecture.
            if geometry.size.width >= TrainingLayout.twoColumnBreakpoint && fixedSection == nil && model.hasPedagogicalRole
                && model.training != nil && !dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    heading
                    if let error = model.errorMessage { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                    HStack(alignment: .top, spacing: DrivySpacing.xl) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                                DrivySectionHeader(title: "Leçons")
                                lessons
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .refreshable { await model.load(keepingCurrent: true) }
                        ScrollView {
                            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                                DrivySectionHeader(title: "Progression")
                                progress
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .refreshable { await model.loadProgress() }
                    }
                }
                .drivyPageContent(maxWidth: TrainingLayout.twoColumnMaxWidth)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DrivySpacing.l) {
                        if fixedSection == nil { heading }
                        if model.isLoading && model.training == nil { DrivyLoadingState(title: "Chargement de la formation…") }
                        if let error = model.errorMessage { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }
                        if model.training != nil {
                            if fixedSection == nil && model.hasPedagogicalRole { sectionPicker }
                            switch section {
                            case .lessons: lessons
                            case .progress: progress
                            }
                        }
                    }
                    .drivyPageContent()
                }
                .refreshable { await model.load(keepingCurrent: true) }
            }
        }
        .background(DrivyTheme.surface)
        .accessibilityIdentifier("training-dossier")
        .sheet(isPresented: $showsPeriod) { periodPicker }
        .task(id: "\(selectedMonth):\(selectedYear)") {
            if period.isActive { await model.loadHistory() }
        }
    }
    private var heading: some View {
        // Le dossier est celui d’une personne : son nom est le titre, la formation la précise.
        HStack(spacing: DrivySpacing.m) {
            if !dynamicTypeSize.isAccessibilitySize {
                DrivyAvatar(name: learner.displayName, size: 60)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(learner.displayName)
                    .font(.drivyTitle).foregroundStyle(DrivyTheme.text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Label(model.training.map { "Permis \($0.categoryCode)" } ?? "Formation", systemImage: "steeringwheel")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }
            Spacer(minLength: 0)
            if let training = model.training, training.status != "ACTIVE" {
                DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status))
            }
        }
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            sections.pickerStyle(.menu).frame(minHeight: 48)
        } else {
            sections.pickerStyle(.segmented)
                .frame(maxWidth: TrainingLayout.pickerMaxWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var sections: some View {
        Picker("Afficher", selection: $chosenSection) {
            ForEach(SchoolTrainingSection.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item).accessibilityIdentifier("training-tab-\(item.rawValue)")
            }
        }
    }
    private var lessons: some View {
        let visible = model.lessons.filter { filter.includes($0) && period.includes($0) }
        return VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if model.lessonsLoaded && model.lessons.isEmpty && !model.isLoading {
                DrivyEmptyState(title: "Aucune leçon", symbol: "calendar")
            }
            if !model.lessons.isEmpty { lessonsMenu }
            if model.isLoadingHistory { DrivyLoadingState(title: "Chargement de l’historique…") }
            if visible.isEmpty && !model.lessons.isEmpty && !model.isLoadingHistory && (!period.isActive || model.nextCursor == nil) {
                DrivyEmptyState(title: period.isActive ? "Aucune leçon sur cette période" : filter.emptyTitle, symbol: "calendar",
                    actionTitle: "Tout afficher", action: { filter = .all; selectedMonth = 0; selectedYear = 0 })
            }
            ForEach(months(of: visible)) { month in monthGroup(month) }
            moreLessons
        }
    }
    /// Un seul contrôle natif : le libellé dit le filtre, la flèche dit le sens ; le menu range les deux choix.
    private var lessonsMenu: some View {
        Menu {
            Section("Afficher") {
                Picker("Afficher", selection: $filter) {
                    ForEach(TrainingLessonFilter.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.inline)
            }
            Section("Trier") {
                Picker("Trier", selection: $order) {
                    ForEach(TrainingLessonOrder.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.inline)
            }
            Section {
                Button("Période…", systemImage: "calendar") { showsPeriod = true }
                if period.isActive { Button("Toutes les périodes") { selectedMonth = 0; selectedYear = 0 } }
            }
        } label: {
            HStack(spacing: DrivySpacing.xs) {
                Image(systemName: order.symbol).font(.caption.weight(.bold))
                Text(filter.title)
                if period.isActive { Text(period.title) }
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Afficher : \(filter.title), \(period.title), \(order.title)")
        .accessibilityIdentifier("training-lessons-menu")
    }
    private var periodPicker: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mois", selection: $selectedMonth) {
                        Text("Tous les mois").tag(0)
                        ForEach(1...12, id: \.self) { month in Text(SchoolLessonPeriod.monthName(month)).tag(month) }
                    }
                    Picker("Année", selection: $selectedYear) {
                        Text("Toutes les années").tag(0)
                        ForEach(periodYears, id: \.self) { year in Text(String(year)).tag(year) }
                    }
                    .disabled(model.isLoadingHistory)
                }
                if model.isLoadingHistory { ProgressView("Chargement de l’historique…") }
                if let error = model.errorMessage {
                    SchoolErrorNotice(message: error, retry: { Task { await model.loadHistory() } })
                }
                if period.isActive { Button("Toutes les périodes") { selectedMonth = 0; selectedYear = 0 } }
            }
            .navigationTitle("Période").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Afficher") { showsPeriod = false } } }
            .task { await model.loadHistory() }
        }
        .presentationDetents([.medium, .large])
    }
    private var periodYears: [Int] {
        var years = Set(model.lessons.compactMap { SchoolLessonPeriod.parts($0)?.year })
        if selectedYear != 0 { years.insert(selectedYear) }
        return years.sorted(by: >)
    }
    private func months(of values: [SchoolLesson]) -> [TrainingLessonMonth] {
        switch order {
        case .newestFirst: return monthGroups(values, newestFirst: true)
        case .oldestFirst: return monthGroups(values, newestFirst: false)
        case .chronological:
            let toFinish = values.filter { $0.drivyState == .toFinish }
            let upcoming = values.filter { $0.status == "PLANNED" && $0.drivyState != .toFinish }
            let past = values.filter { $0.status != "PLANNED" }
            var result = monthGroups(upcoming, newestFirst: false)
            if !toFinish.isEmpty {
                result.append(TrainingLessonMonth(id: "to-finish", title: "À terminer", lessons: sortedByDate(toFinish, newestFirst: false)))
            }
            return result + monthGroups(past, newestFirst: true)
        }
    }
    private func sortedByDate(_ values: [SchoolLesson], newestFirst: Bool) -> [SchoolLesson] {
        values.sorted { first, second in
            let a = first.startsAt ?? .distantPast, b = second.startsAt ?? .distantPast
            if a == b { return first.id.uuidString < second.id.uuidString }
            return newestFirst ? a > b : a < b
        }
    }
    private func monthGroups(_ values: [SchoolLesson], newestFirst: Bool) -> [TrainingLessonMonth] {
        var result: [TrainingLessonMonth] = []
        for lesson in sortedByDate(values, newestFirst: newestFirst) {
            let key = SchoolTrainingFormatting.monthKey(lesson.plannedStart, zone: lesson.timeZone)
            if let last = result.last, last.id == key {
                result[result.count - 1] = TrainingLessonMonth(id: key, title: last.title, lessons: last.lessons + [lesson])
            } else {
                result.append(TrainingLessonMonth(id: key,
                    title: SchoolTrainingFormatting.monthTitle(lesson.plannedStart, zone: lesson.timeZone), lessons: [lesson]))
            }
        }
        return result
    }
    private func monthGroup(_ month: TrainingLessonMonth) -> some View {
        let count = month.lessons.count
        return VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                Text(month.title)
                    .font(.drivySection).foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(month.title), \(count == 1 ? "1 leçon" : "\(count) leçons")")
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("training-month-\(month.id)")
            DrivyRowGroup {
                ForEach(month.lessons) { lesson in
                    Button { opened = OpenedLesson(id: lesson.id) } label: { SchoolTrainingLessonRow(lesson: lesson) }
                        .buttonStyle(DrivyRowButtonStyle())
                        .disabled(!model.canOpenPedagogicalContent)
                        .accessibilityIdentifier("training-lesson-\(lesson.id.uuidString)")
                }
            }
        }
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if let value = model.progress {
                if let error = model.progressError { SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } }) }
                DrivyRowGroup {
                    ForEach(orderedProgress(value.items)) { item in
                        Button { opened = OpenedLesson(id: item.sourceLessonId) } label: { progressRow(item) }
                            .buttonStyle(DrivyRowButtonStyle())
                            .accessibilityHint("Ouvre la leçon")
                    }
                    ForEach(model.unobservedCompetencies) { competency in
                        HStack(spacing: DrivySpacing.m) {
                            DrivyCompetencyNote(label: competency.displayLabel, level: "Pas encore vu", tone: .neutral)
                            DrivyCompetencyMeter(level: "")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, DrivySpacing.s)
                    }
                }
                if value.items.isEmpty && value.unobservedCompetencyIds.isEmpty {
                    DrivyEmptyState(title: "Aucune compétence", symbol: "list.bullet")
                }
            } else if let error = model.progressError {
                SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } })
            } else {
                DrivyLoadingState(title: "Chargement de la progression…")
            }
        }
    }
    private func progressRow(_ item: SchoolReportProgressItem) -> some View {
        HStack(alignment: .top, spacing: DrivySpacing.m) {
            DrivyCompetencyNote(label: model.competencies.first(where: { $0.id == item.id })?.displayLabel ?? item.displayLabel,
                level: SchoolTrainingFormatting.level(item.level), context: item.context,
                date: SchoolTrainingFormatting.day(item.observedAt, zone: workspace.school?.timeZone ?? "Europe/Zurich"))
            DrivyCompetencyMeter(level: item.level).padding(.top, DrivySpacing.xs)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                .padding(.top, DrivySpacing.xxs)
                .accessibilityHidden(true)
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private func orderedProgress(_ items: [SchoolReportProgressItem]) -> [SchoolReportProgressItem] {
        let ranks = Dictionary(model.competencies.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.sorted {
            let a = ranks[$0.id] ?? Int.max, b = ranks[$1.id] ?? Int.max
            return a == b ? $0.displayLabel.localizedStandardCompare($1.displayLabel) == .orderedAscending : a < b
        }
    }
    @ViewBuilder private var moreLessons: some View {
        if model.nextCursor != nil {
            Button { Task { await model.loadMore() } } label: {
                DrivyBusyLabel(title: "Afficher d’autres leçons", busyTitle: "Chargement…", isBusy: model.isLoadingMore)
            }
            .buttonStyle(DrivySecondaryButtonStyle()).disabled(model.isLoadingMore)
        }
    }
}

/// Même anatomie que la ligne d’agenda : heure, jour, lieu ; un badge seulement pour l’inhabituel.
private struct SchoolTrainingLessonRow: View {
    let lesson: SchoolLesson
    var body: some View {
        DrivyLessonRow(start: SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone),
            end: SchoolTrainingFormatting.time(lesson.plannedEnd, zone: lesson.timeZone),
            title: SchoolTrainingFormatting.rowDay(lesson.plannedStart, zone: lesson.timeZone),
            details: [lesson.meetingPoint],
            badge: lesson.drivyState.isUnusual ? lesson.drivyState.badge : nil)
    }
}

/// Leçons et progression côte à côte dès 1040 pt de détail (460 pt de lecture par colonne).
private enum TrainingLayout {
    static let twoColumnBreakpoint: CGFloat = 1040
    static let twoColumnMaxWidth: CGFloat = 1200
    /// Le sélecteur Leçons / Progression ne s’étire pas sur toute la largeur d’un grand détail.
    static let pickerMaxWidth: CGFloat = 360
}

enum SchoolTrainingFormatting {
    static func level(_ code: String) -> String {
        switch code { case "DISCOVERING": "En découverte"; case "GUIDED": "Avec accompagnement"; case "INDEPENDENT": "En autonomie"; default: "À vérifier" }
    }
    static func instant(_ value: String, zone: String) -> String { format(value, zone: zone, template: "d MMMM yyyy HHmm") }
    static func day(_ value: String, zone: String) -> String { format(value, zone: zone, template: "d MMMM yyyy") }
    static func time(_ value: String, zone: String) -> String { format(value, zone: zone, template: "HHmm") }
    /// Titre d’une ligne de leçon : l’année seulement quand ce n’est pas l’année en cours,
    /// pour que la date tienne sur une ligne à côté d’un badge.
    static func rowDay(_ value: String, zone: String) -> String {
        guard let date = SchoolLesson.date(value), let timeZone = TimeZone(identifier: zone) else { return "Date indisponible" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return format(value, zone: zone, template: sameYear ? "EEE d MMMM" : "d MMMM yyyy").capitalizedFirst
    }
    /// Clé de regroupement par mois, dans le fuseau de la leçon.
    static func monthKey(_ value: String, zone: String) -> String {
        guard let date = SchoolLesson.date(value), let timeZone = TimeZone(identifier: zone) else { return "unknown" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }
    /// « Septembre 2026 ».
    static func monthTitle(_ value: String, zone: String) -> String {
        format(value, zone: zone, template: "LLLL yyyy").capitalizedFirst
    }
    private static func format(_ value: String, zone: String, template: String) -> String {
        guard let date = SchoolLesson.date(value), let timeZone = TimeZone(identifier: zone) else { return "Date indisponible" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "fr_CH"); formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template); return formatter.string(from: date)
    }
}
