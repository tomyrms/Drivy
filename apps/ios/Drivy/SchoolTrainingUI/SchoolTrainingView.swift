import SwiftUI

enum SchoolTrainingSection: String, CaseIterable, Hashable { case lessons = "Leçons", progress = "Progression" }

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

/// Leçons et progression d’un élève, pour une ou plusieurs de ses formations. Les pages du dossier et les
/// onglets de l’élève fixent la section ; sans section fixée, un sélecteur passe de l’une à l’autre.
/// Avec plusieurs formations, un filtre par permis apparaît ; avec une seule, rien ne s’ajoute.
/// `showsHeading` ajoute à une section fixée un rappel d’une ligne (élève, formation) : la page
/// poussée depuis le dossier en a besoin, les onglets de l’élève qui lit son propre dossier non.
struct SchoolTrainingScreen: View {
    let client: SchoolTrainingClient
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    /// Les formations montrées, dans l’ordre du filtre.
    let trainingIDs: [UUID]
    let section: SchoolTrainingSection?
    let showsHeading: Bool
    let openProfile: (() -> Void)?
    /// Le permis choisi ; `nil` les montre tous. Tenu par l’appelant : le choix survit au retour sur la page.
    @Binding private var permit: UUID?
    @State private var models: [SchoolTrainingWorkspace] = []
    /// La leçon ouverte vit ici, hors du contenu conditionnel et de `.id` : une relecture ou un changement
    /// de portée recrée le contenu, jamais la feuille qui le surplombe.
    @State private var opened: OpenedLesson?
    @Environment(\.scenePhase) private var scenePhase

    init(client: SchoolTrainingClient, workspace: SchoolWorkspace, learner: SchoolLearner, trainingIDs: [UUID],
         permit: Binding<UUID?>, section: SchoolTrainingSection? = nil, showsHeading: Bool = false,
         openProfile: (() -> Void)? = nil) {
        self.client = client
        _workspace = Bindable(wrappedValue: workspace)
        self.learner = learner
        self.trainingIDs = trainingIDs
        self.section = section
        self.showsHeading = showsHeading
        self.openProfile = openProfile
        _permit = permit
    }

    /// Une seule formation : aucun filtre.
    init(client: SchoolTrainingClient, workspace: SchoolWorkspace, learner: SchoolLearner, trainingID: UUID,
         section: SchoolTrainingSection? = nil, showsHeading: Bool = false, openProfile: (() -> Void)? = nil) {
        self.init(client: client, workspace: workspace, learner: learner, trainingIDs: [trainingID], permit: .constant(nil),
            section: section, showsHeading: showsHeading, openProfile: openProfile)
    }

    private var scopeKey: String {
        "\(workspace.person?.personId.uuidString ?? ""):\(workspace.membership?.membershipId.uuidString ?? ""):\(workspace.membership?.accessEpoch ?? 0):\(workspace.membership?.roles.joined(separator: ",") ?? ""):\(workspace.membership?.grants.joined(separator: ",") ?? ""):\(trainingIDs.map(\.uuidString).joined(separator: ","))"
    }
    /// Les modèles affichés sont ceux des formations demandées, pour l’élève et les droits en cours.
    private var isCurrent: Bool {
        !models.isEmpty && models.map(\.trainingID) == trainingIDs && models.allSatisfy { matches($0) }
    }
    var body: some View {
        Group {
            if isCurrent {
                SchoolTrainingContent(models: models, workspace: workspace, learner: learner, fixedSection: section, showsHeading: showsHeading,
                    openProfile: openProfile, permit: $permit, opened: $opened)
            } else {
                DrivySkeletonRows(count: 4, leading: .time)
                    .drivySkeleton("Chargement de la formation…")
                    .drivyPageContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(DrivyTheme.surface)
            }
        }
        .id(scopeKey)
        .task(id: scopeKey) { await open() }
        .onChange(of: models.contains { $0.accessRevoked }) { _, revoked in
            // Relecture silencieuse : `loadAccount` vide le compte et fait disparaître tout l’écran (feuille ouverte comprise).
            if revoked { Task { await workspace.refreshAccount(minimumInterval: 0) } }
        }
        // Une leçon planifiée ailleurs (feuille de planification du dossier) : la liste se relit sans être recréée.
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            guard isCurrent else { return }
            guard let change = notification.object as? SchoolLessonChange else { Task { await refresh() }; return }
            guard change.schoolID == workspace.membership?.schoolId,
                  let model = models.first(where: { $0.trainingID == change.trainingID }) else { return }
            Task { await model.refreshOnAppear() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isCurrent { Task { await refresh() } }
        }
        .sheet(item: $opened, onDismiss: { Task { await refresh() } }) { lesson in
            NavigationStack {
                // Le souhait de l’élève suit la prochaine leçon de sa formation, pas celle du dossier entier.
                SchoolLessonReportView(client: client.reports, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learner.displayName,
                    isNextPlanned: models.contains { $0.upcomingLessons.first?.id == lesson.id })
            }
            .tint(DrivyTheme.accent)
        }
    }
    private func open() async {
        // Retour sur l’écran ou changement d’onglet : toujours relire, sans effacer ce qui est affiché.
        if isCurrent { await refresh(); return }
        models = []
        guard let person = workspace.person, let membership = workspace.membership else { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
        let shared = trainingIDs.map {
            SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner.id, trainingID: $0, client: client)
        }
        models = shared.map { $0.model }
        // Un modèle partagé peut dater d’avant un bilan enregistré ailleurs : relecture à chaque affichage.
        let kept = Set(shared.filter { !$0.isNew }.map { $0.model.trainingID })
        await SchoolLessonFeed.together(models) { await $0.load(keepingCurrent: kept.contains($0.trainingID)) }
    }
    private func refresh() async { await SchoolLessonFeed(models: models).reload() }
    private func matches(_ model: SchoolTrainingWorkspace) -> Bool {
        model.learnerID == learner.id
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
    /// Un modèle par formation de l’élève, dans l’ordre du filtre.
    let models: [SchoolTrainingWorkspace]
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    let fixedSection: SchoolTrainingSection?
    let showsHeading: Bool
    let openProfile: (() -> Void)?
    @Binding var permit: UUID?
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

    /// Le permis montré seul : l’unique formation de l’élève, ou celle que le filtre désigne.
    /// Un choix qui ne correspond plus à aucune formation revient à « Tous ».
    private var selected: SchoolTrainingWorkspace? {
        models.count == 1 ? models.first : models.first { $0.trainingID == permit }
    }
    private var shown: [SchoolTrainingWorkspace] { selected.map { [$0] } ?? models }
    private var feed: SchoolLessonFeed { SchoolLessonFeed(models: shown) }
    private var hasSeveralPermits: Bool { models.count > 1 }
    /// « Tous » avec plusieurs permis : chaque leçon et chaque section de progression nomme le sien.
    private var mixesPermits: Bool { shown.count > 1 }
    private var hasPedagogicalRole: Bool { models.first?.hasPedagogicalRole ?? false }
    private var hasTraining: Bool { shown.contains { $0.training != nil } }
    /// Les filtres de statut et de période portent sur l’historique complet, jamais sur les seules pages lues.
    private var needsHistory: Bool { period.isActive || filter != .all }

    var body: some View {
        GeometryReader { geometry in
            // Dans un grand détail, les leçons et leur progression restent visibles ensemble.
            // Le sélecteur est conservé quand chaque colonne n’aurait plus 460 pt de lecture.
            if geometry.size.width >= TrainingLayout.twoColumnBreakpoint && fixedSection == nil && hasPedagogicalRole
                && hasTraining && !dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    heading
                    if hasSeveralPermits { permitFilter }
                    failures
                    HStack(alignment: .top, spacing: DrivySpacing.xl) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                                DrivySectionHeader(title: "Leçons")
                                lessons
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .refreshable { await feed.reload() }
                        ScrollView {
                            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                                DrivySectionHeader(title: "Progression")
                                progress
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .refreshable { await SchoolLessonFeed.together(shown) { await $0.loadProgress() } }
                    }
                }
                .drivyPageContent(maxWidth: TrainingLayout.twoColumnMaxWidth)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DrivySpacing.m) {
                        if fixedSection == nil || showsHeading { heading }
                        if hasSeveralPermits { permitFilter }
                        if !hasTraining && feed.isLoading {
                            DrivySkeletonRows(count: 4, leading: .time)
                                .drivySkeleton("Chargement de la formation…")
                        }
                        failures
                        if hasTraining {
                            if fixedSection == nil && hasPedagogicalRole { sectionPicker }
                            switch section {
                            case .lessons: lessons
                            case .progress: progress
                            }
                        }
                    }
                    .drivyPageContent()
                }
                .refreshable { await feed.reload() }
            }
        }
        .background(DrivyTheme.surface)
        .accessibilityIdentifier("training-dossier")
        .sheet(isPresented: $showsPeriod) { periodPicker }
        .task(id: "\(selectedMonth):\(selectedYear):\(filter.rawValue):\(selected?.trainingID.uuidString ?? "")") {
            if needsHistory { await feed.loadHistory() }
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            identity
            // Sans coordonnée exploitable ni profil à ouvrir, la rangée ne prend aucune place.
            if fixedSection == nil { SchoolLearnerActions(learner: learner, openProfile: openProfile) }
        }
    }

    /// La formation d’un modèle : celle que cet écran a relue, sinon celle que le dossier connaît déjà,
    /// pour que son nom ne change pas pendant le chargement.
    private func training(of model: SchoolTrainingWorkspace) -> SchoolTraining? {
        model.training ?? workspace.trainings.first { $0.id == model.trainingID }
    }
    private var permitNames: [UUID: String] { SchoolPermitName.names(models.compactMap { training(of: $0) }) }
    private func permitName(_ model: SchoolTrainingWorkspace, in names: [UUID: String]) -> String {
        names[model.trainingID] ?? "Permis"
    }

    /// Le permis montré seul. Avec « Tous », aucun n’est à nommer en tête.
    private var shownTraining: SchoolTraining? { selected.flatMap { training(of: $0) } }
    /// Avec plusieurs permis, le filtre dit déjà lequel est affiché : le rappel ne le répète pas.
    private var formationName: String? {
        hasSeveralPermits ? nil : shownTraining.map { "Permis \($0.categoryCode)" }
    }

    /// Poussée depuis le dossier, la page rappelle l’élève en une ligne : on vient de le quitter.
    /// Ouverte seule, la formation nomme l’élève en tête, sans le poids d’un titre d’écran.
    @ViewBuilder private var identity: some View {
        if fixedSection == nil {
            DrivyLearnerIdentity(name: learner.displayName, detail: formationName ?? "Formation", variant: .compact) {
                statusBadge
            }
        } else {
            DrivyLearnerIdentity(name: learner.displayName, detail: formationName, variant: .inline) {
                statusBadge
            }
        }
    }

    /// Un mot de texte seulement pour l’inhabituel : en pause, terminée, annulée.
    @ViewBuilder private var statusBadge: some View {
        if let training = shownTraining, training.status != "ACTIVE" {
            Text(SchoolPresentation.trainingStatus(training.status))
                .font(.subheadline).foregroundStyle(DrivyTheme.muted)
        }
    }

    /// Deux permis : trois choix courts tiennent dans un contrôle segmenté. Au-delà, ou en très grand texte,
    /// un menu qui affiche le choix en cours ; jamais une rangée de boutons à faire défiler.
    @ViewBuilder private var permitFilter: some View {
        if models.count == 2 && !dynamicTypeSize.isAccessibilitySize {
            permitPicker(allTitle: "Tous").pickerStyle(.segmented)
                .frame(maxWidth: TrainingLayout.pickerMaxWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Même libellé-menu que le tri des leçons, aligné sur la marge du contenu.
            let current = selected.map { permitName($0, in: permitNames) } ?? "Tous les permis"
            Menu {
                permitPicker(allTitle: "Tous les permis").pickerStyle(.inline)
            } label: {
                HStack(spacing: DrivySpacing.xs) {
                    Text(current).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Permis")
            .accessibilityValue(current)
            .accessibilityIdentifier("training-permit-filter")
        }
    }
    private func permitPicker(allTitle: String) -> some View {
        let names = permitNames
        return Picker("Permis", selection: Binding(get: { selected?.trainingID }, set: { permit = $0 })) {
            Text(allTitle).tag(UUID?.none)
            ForEach(models, id: \.trainingID) { model in
                Text(permitName(model, in: names)).tag(UUID?.some(model.trainingID))
            }
        }
        .labelsHidden()
        .accessibilityLabel("Permis")
        .accessibilityIdentifier("training-permit-filter")
    }

    /// Une panne commune à tout ce qui est montré se dit une fois ; sinon chaque permis porte la sienne,
    /// et les autres restent lisibles.
    @ViewBuilder private var failures: some View {
        let failed = shown.filter { $0.errorMessage != nil }
        if let message = failed.first?.errorMessage, failed.count == shown.count,
           failed.allSatisfy({ $0.errorMessage == message }) {
            SchoolErrorNotice(message: message, retry: { retry(failed) })
        } else {
            let names = permitNames
            ForEach(failed, id: \.trainingID) { model in
                SchoolErrorNotice(message: "\(permitName(model, in: names)) : \(model.errorMessage ?? "")", retry: { retry([model]) })
            }
        }
    }
    private func retry(_ models: [SchoolTrainingWorkspace]) {
        Task { await SchoolLessonFeed.together(models) { await $0.load() } }
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
        let feed = self.feed
        let visible = feed.lessons.filter { filter.includes($0) && period.includes($0) }
        // Le permis d’une leçon n’est nommé que lorsque la liste en mêle plusieurs.
        let names = mixesPermits ? permitNames : [:]
        return VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if feed.isLoadingFirstPage {
                DrivySkeletonRows(count: 4, leading: .time)
                    .drivySkeleton("Chargement des leçons…")
            } else {
                if feed.allRead && !feed.hasLessons && !feed.isLoading {
                    DrivyEmptyState(title: "Aucune leçon", symbol: "calendar")
                }
                if feed.hasLessons { lessonsMenu }
                if feed.isLoadingHistory { DrivyLoadingState(title: "Chargement de l’historique…") }
                // Tant qu’il reste des pages à lire, « aucune leçon » ne peut pas être affirmé.
                if visible.isEmpty && feed.hasLessons && !feed.isLoadingHistory && !feed.hasMore {
                    DrivyEmptyState(title: period.isActive ? "Aucune leçon sur cette période" : filter.emptyTitle, symbol: "calendar",
                        actionTitle: "Tout afficher", action: { filter = .all; selectedMonth = 0; selectedYear = 0 })
                }
                ForEach(months(of: visible)) { month in monthGroup(month, feed: feed, permitNames: names) }
                moreLessons
            }
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
                Text(period.isActive ? "\(filter.title) · \(period.title)" : filter.title)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Filtrer et trier les leçons")
        .accessibilityValue([filter.title, period.isActive ? period.title : "Toutes les périodes", order.title].joined(separator: ", "))
        .accessibilityIdentifier("training-lessons-menu")
    }
    private var periodPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    DrivyRowGroup {
                        periodField("Mois") {
                            Picker("Mois", selection: $selectedMonth) {
                                Text("Tous les mois").tag(0)
                                ForEach(1...12, id: \.self) { month in Text(SchoolLessonPeriod.monthName(month)).tag(month) }
                            }
                        }
                        periodField("Année") {
                            Picker("Année", selection: $selectedYear) {
                                Text("Toutes les années").tag(0)
                                ForEach(periodYears, id: \.self) { year in Text(String(year)).tag(year) }
                            }
                            .disabled(feed.isLoadingHistory)
                        }
                    }
                    if feed.isLoadingHistory { ProgressView("Chargement de l’historique…") }
                    if let error = shown.compactMap(\.errorMessage).first {
                        SchoolErrorNotice(message: error, retry: { Task { await feed.loadHistory() } })
                    }
                    if period.isActive {
                        Button("Toutes les périodes") { selectedMonth = 0; selectedYear = 0 }
                            .frame(minHeight: 44)
                    }
                }
                .drivyPageContent(maxWidth: DrivyLayout.formColumn)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(DrivyTheme.surface)
            .navigationTitle("Période").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Afficher") { showsPeriod = false } } }
            .task { await feed.loadHistory() }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
    }
    private func periodField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            content().labelsHidden().pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DrivySpacing.xs)
    }
    private var periodYears: [Int] {
        var years = Set(shown.flatMap(\.lessons).compactMap { SchoolLessonPeriod.parts($0)?.year })
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
            var result = monthGroups(upcoming, newestFirst: false, prefix: "upcoming")
            if !toFinish.isEmpty {
                result.append(TrainingLessonMonth(id: "to-finish", title: "À terminer", lessons: sortedByDate(toFinish, newestFirst: false)))
            }
            return result + monthGroups(past, newestFirst: true, prefix: "past")
        }
    }
    private func sortedByDate(_ values: [SchoolLesson], newestFirst: Bool) -> [SchoolLesson] {
        values.sorted { first, second in
            let a = first.startsAt ?? .distantPast, b = second.startsAt ?? .distantPast
            if a == b { return first.id.uuidString < second.id.uuidString }
            return newestFirst ? a > b : a < b
        }
    }
    private func monthGroups(_ values: [SchoolLesson], newestFirst: Bool, prefix: String = "all") -> [TrainingLessonMonth] {
        var result: [TrainingLessonMonth] = []
        for lesson in sortedByDate(values, newestFirst: newestFirst) {
            let key = "\(prefix)-\(SchoolTrainingFormatting.monthKey(lesson.plannedStart, zone: lesson.timeZone))"
            if let last = result.last, last.id == key {
                result[result.count - 1] = TrainingLessonMonth(id: key, title: last.title, lessons: last.lessons + [lesson])
            } else {
                result.append(TrainingLessonMonth(id: key,
                    title: SchoolTrainingFormatting.monthTitle(lesson.plannedStart, zone: lesson.timeZone), lessons: [lesson]))
            }
        }
        return result
    }
    private func monthGroup(_ month: TrainingLessonMonth, feed: SchoolLessonFeed, permitNames: [UUID: String]) -> some View {
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
                    Button { opened = OpenedLesson(id: lesson.id) } label: {
                        // Sous le titre « À terminer », la ligne ne redit pas son état.
                        SchoolTrainingLessonRow(lesson: lesson, permit: permitNames[lesson.trainingId],
                            showsState: month.id != "to-finish")
                    }
                        .buttonStyle(DrivyRowButtonStyle())
                        .disabled(feed.model(for: lesson)?.canOpenPedagogicalContent != true)
                        .accessibilityIdentifier("training-lesson-\(lesson.id.uuidString)")
                }
            }
        }
    }
    /// Une compétence relève du référentiel de sa catégorie : « Tous » montre la progression de chaque permis
    /// sous son nom, l’une après l’autre, sans rien additionner d’un permis à l’autre.
    private var progress: some View {
        let names = permitNames
        return VStack(alignment: .leading, spacing: DrivySpacing.l) {
            // Une formation illisible est dite par son erreur, pas par une section vide.
            ForEach(shown.filter { $0.training != nil || $0.isLoading }, id: \.trainingID) { model in
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    if mixesPermits { permitTitle(model, name: permitName(model, in: names)) }
                    competencies(of: model)
                }
            }
        }
    }
    /// Le titre d’un permis dans « Tous » ; un état inhabituel suit son nom.
    private func permitTitle(_ model: SchoolTrainingWorkspace, name: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.s))
        return layout {
            DrivySectionHeader(title: name)
            if let training = training(of: model), training.status != "ACTIVE" {
                Text(SchoolPresentation.trainingStatus(training.status))
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
        }
    }
    private func competencies(of model: SchoolTrainingWorkspace) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if let value = model.progress {
                if let error = model.progressError { SchoolErrorNotice(message: error, retry: { Task { await model.loadProgress() } }) }
                DrivyRowGroup {
                    ForEach(orderedProgress(value.items, of: model)) { item in
                        Button { opened = OpenedLesson(id: item.sourceLessonId) } label: { progressRow(item, of: model) }
                            .buttonStyle(DrivyRowButtonStyle())
                            .accessibilityHint("Ouvre la leçon")
                    }
                    ForEach(model.unobservedCompetencies) { competency in
                        progressLayout {
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
                DrivySkeletonRows(count: 5)
                    .drivySkeleton("Chargement de la progression…")
            }
        }
    }
    private func progressRow(_ item: SchoolReportProgressItem, of model: SchoolTrainingWorkspace) -> some View {
        progressLayout {
            DrivyCompetencyNote(label: model.competencies.first(where: { $0.id == item.id })?.displayLabel ?? item.displayLabel,
                level: SchoolTrainingFormatting.level(item.level), context: item.context,
                date: SchoolTrainingFormatting.day(item.observedAt, zone: workspace.school?.timeZone ?? "Europe/Zurich"))
            HStack(spacing: DrivySpacing.s) {
                DrivyCompetencyMeter(level: item.level)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.top, DrivySpacing.xs)
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private var progressLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.m))
    }
    private func orderedProgress(_ items: [SchoolReportProgressItem], of model: SchoolTrainingWorkspace) -> [SchoolReportProgressItem] {
        let ranks = Dictionary(model.competencies.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items.sorted {
            let a = ranks[$0.id] ?? Int.max, b = ranks[$1.id] ?? Int.max
            return a == b ? $0.displayLabel.localizedStandardCompare($1.displayLabel) == .orderedAscending : a < b
        }
    }
    @ViewBuilder private var moreLessons: some View {
        let feed = self.feed
        if feed.hasMore {
            Button { Task { await feed.loadMore() } } label: {
                DrivyBusyLabel(title: "Afficher d’autres leçons", busyTitle: "Chargement…", isBusy: feed.isLoadingMore)
            }
            .buttonStyle(DrivySecondaryButtonStyle()).disabled(feed.isLoadingMore)
        }
    }
}

/// Même anatomie que la ligne d’agenda : heure, jour, lieu ; un mot de texte seulement pour l’inhabituel.
private struct SchoolTrainingLessonRow: View {
    let lesson: SchoolLesson
    /// Nommé seulement quand la liste mêle plusieurs permis : du texte parmi les détails, pas un badge.
    var permit: String? = nil
    var showsState = true
    var body: some View {
        DrivyLessonRow(start: SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone),
            end: SchoolTrainingFormatting.time(lesson.plannedEnd, zone: lesson.timeZone),
            title: SchoolTrainingFormatting.rowDay(lesson.plannedStart, zone: lesson.timeZone),
            details: [[permit, lesson.meetingPoint].compactMap { $0 }.joined(separator: " · ")],
            state: showsState ? lesson.drivyState : nil)
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
