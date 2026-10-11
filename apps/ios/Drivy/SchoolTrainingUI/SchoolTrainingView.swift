import SwiftUI

enum SchoolTrainingSection: String, CaseIterable, Hashable { case lessons = "Leçons", progress = "Progression" }

/// Le calendrier de la leçon fait foi, même près de minuit ou d'un changement d'année UTC.
struct SchoolLessonPeriod: Equatable {
    var month = 0
    var year = 0
    var isActive: Bool { month != 0 || year != 0 }
    func includes(_ lesson: SchoolLesson) -> Bool {
        guard isActive else { return true }
        guard let parts = Self.parts(lesson) else { return false }
        return (month == 0 || parts.month == month) && (year == 0 || parts.year == year)
    }
    static func parts(_ lesson: SchoolLesson) -> DateComponents? {
        guard let date = lesson.startsAt, let zone = TimeZone(identifier: lesson.timeZone) else { return nil }
        return SchoolDateCache.shared.calendar(zone: zone).dateComponents([.year, .month], from: date)
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

/// La formation ouverte depuis les écrans de revue visuelle. Le dossier produit
/// utilise SchoolTrainingScreen directement, dans son propre défilement.
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

/// Leçons et progression d’un élève, pour une ou plusieurs de ses formations. Les onglets de l’élève
/// fixent la section ; sans section fixée, un sélecteur passe de l’une à l’autre, en place.
/// Avec plusieurs formations, un filtre par permis apparaît ; avec une seule, rien ne s’ajoute.
/// `showsHeading` ajoute à une section fixée un rappel d’une ligne (élève, formation).
/// Le dossier embarque cet écran dans son propre défilement (`init(embeddedIn:)`) : ni défilement
/// ni fond ici, et c’est le dossier qui tient la section choisie.
struct SchoolTrainingScreen: View {
    let client: SchoolTrainingClient
    @Bindable var workspace: SchoolWorkspace
    let learner: SchoolLearner
    /// Les formations montrées, dans l’ordre du filtre.
    let trainingIDs: [UUID]
    let section: SchoolTrainingSection?
    let showsHeading: Bool
    let openProfile: (() -> Void)?
    /// Les onglets de l’élève : toutes ses leçons lues, la prochaine en tête, aucun vocabulaire de moniteur.
    let ownLessons: Bool
    private let isEmbedded: Bool
    /// La section tenue par l’écran hôte ; sinon celle de cet écran.
    private let hostSection: Binding<SchoolTrainingSection>?
    /// Le permis choisi ; `nil` les montre tous. Tenu par l’appelant : le choix survit au retour sur la page.
    @Binding private var permit: UUID?
    @State private var ownSection: SchoolTrainingSection = .lessons
    @State private var models: [SchoolTrainingWorkspace] = []
    /// La leçon ouverte vit ici, hors du contenu conditionnel et de `.id` : une relecture ou un changement
    /// de portée recrée le contenu, jamais la feuille qui le surplombe.
    @State private var opened: OpenedLesson?
    /// La carte « Prochaine leçon » s’ouvre en zoom vers sa fiche.
    @Namespace private var lessonZoom
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(client: SchoolTrainingClient, workspace: SchoolWorkspace, learner: SchoolLearner, trainingIDs: [UUID],
         permit: Binding<UUID?>, section: SchoolTrainingSection? = nil, showsHeading: Bool = false,
         openProfile: (() -> Void)? = nil, ownLessons: Bool = false) {
        self.client = client
        _workspace = Bindable(wrappedValue: workspace)
        self.learner = learner
        self.trainingIDs = trainingIDs
        self.section = section
        self.showsHeading = showsHeading
        self.openProfile = openProfile
        self.ownLessons = ownLessons
        isEmbedded = false
        hostSection = nil
        _permit = permit
        // Un autre onglet a déjà lu ces formations : elles s’affichent dès la première image, sans squelette.
        let cached = SchoolTrainingModelCache.current(trainingIDs)
        if cached.count == trainingIDs.count { _models = State(initialValue: cached) }
    }

    /// Dans le dossier : sélecteur Leçons / Progression, filtre et contenu, posés dans le défilement de l’hôte.
    init(embeddedIn workspace: SchoolWorkspace, client: SchoolTrainingClient, learner: SchoolLearner, trainingIDs: [UUID],
         permit: Binding<UUID?>, section: Binding<SchoolTrainingSection>) {
        self.client = client
        _workspace = Bindable(wrappedValue: workspace)
        self.learner = learner
        self.trainingIDs = trainingIDs
        self.section = nil
        showsHeading = false
        openProfile = nil
        ownLessons = false
        isEmbedded = true
        hostSection = section
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
                    openProfile: openProfile, isEmbedded: isEmbedded, ownLessons: ownLessons, zoom: lessonZoom, permit: $permit,
                    chosenSection: hostSection ?? $ownSection, opened: $opened)
            } else if isEmbedded {
                DrivySkeletonRows(count: 4, leading: .time)
                    .drivySkeleton("Chargement de la formation…")
            } else {
                DrivySkeletonRows(count: 4, leading: .time)
                    .drivySkeleton("Chargement de la formation…")
                    .drivyPageContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(DrivyTheme.surface)
            }
        }
        .id(scopeKey)
        // Le squelette laisse place aux leçons en fondu, sans remplacement sec.
        .animation(DrivyMotion.reveal(reduceMotion), value: isCurrent)
        .task(id: scopeKey) { await open() }
        .onChange(of: models.contains { $0.accessRevoked }) { _, revoked in
            // Relecture silencieuse : `loadAccount` vide le compte et fait disparaître tout l’écran (feuille ouverte comprise).
            if revoked { Task { await workspace.refreshAccount(minimumInterval: 0) } }
        }
        // Une leçon planifiée ailleurs (feuille de planification du dossier) : la liste se relit sans être recréée.
        .onReceive(NotificationCenter.default.publisher(for: .drivyLessonsDidChange)) { notification in
            guard isCurrent else { return }
            guard let change = notification.object as? SchoolLessonChange else {
                Task { await SchoolLessonFeed(models: models).reload(ifOlderThan: 0) }; return
            }
            guard change.schoolID == workspace.membership?.schoolId,
                  let model = models.first(where: { $0.trainingID == change.trainingID }) else { return }
            Task { await model.refreshOnAppear() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Les onglets de l’élève partagent leurs formations : un seul relit, et pas plus d’une fois par demi-minute.
            if phase == .active, isCurrent { Task { await SchoolLessonFeed(models: models).reload(ifOlderThan: 30) } }
        }
        .sheet(item: $opened, onDismiss: { Task { await refresh() } }) { lesson in lessonSheet(lesson) }
    }

    @ViewBuilder private func lessonSheet(_ lesson: OpenedLesson) -> some View {
        let sheet = NavigationStack {
            // Le souhait de l’élève suit la prochaine leçon de sa formation, pas celle du dossier entier.
            SchoolLessonReportView(client: client.reports, schoolWorkspace: workspace, lessonID: lesson.id, learnerName: learner.displayName,
                isNextPlanned: models.contains { $0.upcomingLessons.first?.id == lesson.id },
                knownLesson: models.lazy.flatMap(\.lessons).first { $0.id == lesson.id })
        }
        .tint(DrivyTheme.accent)
        if lesson.zooms {
            sheet.navigationTransition(.zoom(sourceID: lesson.id, in: lessonZoom))
        } else {
            sheet
        }
    }
    private func open() async {
        // Retour sur l’écran ou changement d’onglet : relire sans effacer ce qui est affiché, sauf lecture toute
        // récente ou déjà en cours (les onglets de l’élève partagent leurs formations).
        if isCurrent {
            if ownLessons { models.forEach { $0.requestWholeHistory() } }
            await SchoolLessonFeed(models: models).reload(ifOlderThan: 30); return
        }
        models = []
        guard let person = workspace.person, let membership = workspace.membership else { return }
        let scope = SchoolCommandScope(personID: person.personId, schoolID: membership.schoolId,
            membershipID: membership.membershipId, accessEpoch: membership.accessEpoch, apiBaseURL: client.baseURL.absoluteString)
        let shared = trainingIDs.map {
            SchoolTrainingModelCache.model(scope: scope, membership: membership, learnerID: learner.id, trainingID: $0, client: client)
        }
        models = shared.map { $0.model }
        if ownLessons { models.forEach { $0.requestWholeHistory() } }
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

private struct OpenedLesson: Identifiable {
    let id: UUID
    /// Ouverte depuis la carte « Prochaine leçon » : la fiche s’ouvre en zoom depuis elle.
    var zooms = false
}

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

/// Filtre de statut des leçons du dossier. Une leçon dont l’horaire est passé
/// reste en attente sans démarrage ; « À terminer » exige un démarrage enregistré.
enum TrainingLessonFilter: String, CaseIterable, Identifiable {
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
    func includes(_ lesson: SchoolLesson, now: Date = Date()) -> Bool {
        let state = lesson.drivyState(now: now)
        let isUpcoming = state == .planned || state == .inProgress
        switch self {
        case .all: return true
        case .upcoming: return isUpcoming
        case .past: return !isUpcoming
        case .toFinish: return state == .toFinish
        }
    }
}

/// Ordre des leçons. « Chronologique » garde la prochaine leçon en tête : à venir (croissant),
/// en attente, à terminer, puis passées (la plus récente d’abord).
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
    /// Posé dans le défilement d’un autre écran (le dossier) : ni défilement, ni fond, ni rappel de l’élève.
    let isEmbedded: Bool
    let ownLessons: Bool
    let zoom: Namespace.ID
    @Binding var permit: UUID?
    @Binding var chosenSection: SchoolTrainingSection
    @Binding var opened: OpenedLesson?
    /// Le tri et le filtre survivent aux changements d’onglet et de dossier pendant la session de la scène.
    @SceneStorage("training.lessons.filter") private var filter: TrainingLessonFilter = .all
    @SceneStorage("training.lessons.order") private var order: TrainingLessonOrder = .chronological
    @SceneStorage("training.lessons.month") private var selectedMonth = 0
    @SceneStorage("training.lessons.year") private var selectedYear = 0
    @State private var showsPeriod = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// L’élève ne termine pas de leçon : « À terminer » n’est pas un filtre pour lui.
    private var filters: [TrainingLessonFilter] { ownLessons ? [.all, .upcoming, .past] : TrainingLessonFilter.allCases }
    /// Le filtre retenu, ramené à « Toutes » quand il n’a pas cours ici.
    private var activeFilter: TrainingLessonFilter { filters.contains(filter) ? filter : .all }

    /// Sans lecture pédagogique, il n’y a pas de sélecteur : seules les leçons sont montrées.
    private var section: SchoolTrainingSection { fixedSection ?? (hasPedagogicalRole ? chosenSection : .lessons) }
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
    private var needsHistory: Bool { period.isActive || activeFilter != .all }

    var body: some View {
        Group {
            if isEmbedded {
                // Un conteneur d’accessibilité : l’identifiant ne remplace pas ceux des lignes.
                page.accessibilityElement(children: .contain)
            } else {
                standalone
            }
        }
        .accessibilityIdentifier("training-dossier")
        .sheet(isPresented: $showsPeriod) { periodPicker }
        .task(id: "\(selectedMonth):\(selectedYear):\(filter.rawValue):\(selected?.trainingID.uuidString ?? "")") {
            if needsHistory { await feed.loadHistory() }
        }
    }

    private var standalone: some View {
        GeometryReader { geometry in
            // Dans un grand détail, les leçons et leur progression restent visibles ensemble.
            // Le sélecteur est conservé quand chaque colonne n’aurait plus 460 pt de lecture.
            if geometry.size.width >= TrainingLayout.twoColumnBreakpoint && fixedSection == nil && hasPedagogicalRole
                && hasTraining && !dynamicTypeSize.isAccessibilitySize {
                columns
            } else {
                ScrollView { page.drivyPageContent() }
                    .refreshable { await feed.reload() }
            }
        }
        .background(DrivyTheme.surface)
    }

    /// Le flux unique : sélecteur, rangée de filtres, puis la section choisie. Le dossier le pose tel quel sous l’identité.
    private var page: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if !isEmbedded && (fixedSection == nil || showsHeading) { heading }
            if fixedSection == nil && hasPedagogicalRole { sectionPicker }
            filterRow(withLessonsMenu: section == .lessons)
            if !hasTraining && feed.isLoading {
                DrivySkeletonRows(count: 4, leading: .time)
                    .drivySkeleton("Chargement de la formation…")
            }
            failures
            if hasTraining {
                switch section {
                case .lessons: lessons
                case .progress: progress
                }
            }
        }
    }

    private var columns: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            heading
            filterRow(withLessonsMenu: false)
            failures
            HStack(alignment: .top, spacing: DrivySpacing.xl) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DrivySpacing.m) {
                        DrivySectionHeader(title: "Leçons")
                        if showsLessonsMenu { lessonsMenu.frame(maxWidth: .infinity, alignment: .trailing) }
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

    /// Une section fixée rappelle l’élève en une ligne. Ouverte seule, la formation nomme l’élève
    /// en tête, sans le poids d’un titre d’écran. Dans le dossier, l’identité est déjà au-dessus.
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

    /// Le tri des leçons n’a de sens qu’une fois des leçons lues.
    private var showsLessonsMenu: Bool { hasTraining && feed.hasLessons && !feed.isLoadingFirstPage }

    /// Une seule rangée : le permis à gauche, « Filtrer et trier » à droite (Leçons seulement).
    /// Avec un seul permis et rien à trier, la rangée n’existe pas. En très grand texte, les deux menus s’empilent.
    @ViewBuilder private func filterRow(withLessonsMenu: Bool) -> some View {
        let showsMenu = withLessonsMenu && showsLessonsMenu
        if hasSeveralPermits || showsMenu {
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .center, spacing: DrivySpacing.m))
            layout {
                if hasSeveralPermits { permitFilter }
                if !stacked { Spacer(minLength: 0) }
                if showsMenu { lessonsMenu }
            }
        }
    }

    /// Toujours un menu qui affiche le choix en cours, quel que soit le nombre de permis :
    /// jamais un second contrôle segmenté sous celui des sections.
    private var permitFilter: some View {
        let names = permitNames
        let current = selected.map { permitName($0, in: names) } ?? "Tous les permis"
        return Menu {
            Picker("Permis", selection: Binding(get: { selected?.trainingID }, set: { permit = $0 })) {
                Text("Tous les permis").tag(UUID?.none)
                ForEach(models, id: \.trainingID) { model in
                    Text(permitName(model, in: names)).tag(UUID?.some(model.trainingID))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: DrivySpacing.xs) {
                Text(current).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Permis")
        .accessibilityValue(current)
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
    /// Segmenté ; en très grand texte, un menu qui affiche la section en cours.
    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            sections.pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        } else {
            sections.pickerStyle(.segmented)
                .frame(maxWidth: TrainingLayout.pickerMaxWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var sections: some View {
        Picker("Afficher", selection: $chosenSection) {
            ForEach(SchoolTrainingSection.allCases, id: \.self) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .accessibilityIdentifier("dossier-section")
    }
    private var lessons: some View {
        let feed = self.feed
        let names = mixesPermits ? permitNames : [:]
        let featured = featuredLesson(in: feed.lessons)
        // La prochaine leçon de l’élève est en tête, dans sa carte : la liste ne la redit pas.
        let visible = feed.lessons.filter { activeFilter.includes($0) && period.includes($0) && $0.id != featured?.id }
        // Le permis d’une leçon n’est nommé que lorsque la liste en mêle plusieurs.
        return VStack(alignment: .leading, spacing: DrivySpacing.m) {
            if feed.isLoadingFirstPage {
                DrivySkeletonRows(count: 4, leading: .time)
                    .drivySkeleton("Chargement des leçons…")
                    .transition(.opacity)
            } else {
                if let featured { nextLessonCard(featured, permitNames: names) }
                if feed.allRead && !feed.hasLessons && !feed.isLoading {
                    DrivyEmptyState(title: "Aucune leçon", symbol: "calendar")
                }
                if feed.isLoadingHistory { DrivyLoadingState(title: "Chargement de l’historique…").transition(.opacity) }
                // Tant qu’il reste des pages à lire, « aucune leçon » ne peut pas être affirmé.
                if visible.isEmpty && featured == nil && feed.hasLessons && !feed.isLoadingHistory && !feed.hasMore {
                    DrivyEmptyState(title: period.isActive ? "Aucune leçon sur cette période" : activeFilter.emptyTitle, symbol: "calendar",
                        actionTitle: "Tout afficher", action: { showAll() })
                }
                // Des centaines de leçons possibles : seuls les mois visibles sont construits.
                LazyVStack(alignment: .leading, spacing: DrivySpacing.m) {
                    ForEach(months(of: visible)) { month in monthGroup(month, feed: feed, permitNames: names) }
                }
                moreLessons
            }
        }
        // Filtre, tri, période ou permis : la liste se recompose en fondu, sans saut.
        .animation(DrivyMotion.reveal(reduceMotion), value: listKey)
        .animation(DrivyMotion.reveal(reduceMotion), value: feed.isLoadingFirstPage)
    }

    /// Ce qui recompose la liste : un changement de l’un de ces choix se fait en fondu.
    private var listKey: String {
        "\(activeFilter.rawValue):\(order.rawValue):\(selectedMonth):\(selectedYear):\(selected?.trainingID.uuidString ?? "all")"
    }

    private func showAll() {
        withAnimation(DrivyMotion.reveal(reduceMotion)) { filter = .all; selectedMonth = 0; selectedYear = 0 }
    }

    /// L’élève : la leçon qui compte, en tête de ses leçons — celle qui se déroule, sinon la prochaine. Rien quand
    /// la liste montre les leçons passées ou une période choisie.
    private func featuredLesson(in lessons: [SchoolLesson]) -> SchoolLesson? {
        guard ownLessons, section == .lessons, activeFilter != .past, !period.isActive else { return nil }
        return SchoolLearnerLessonMoment.featured(lessons, now: Date())
    }

    /// La même lecture que la leçon qui compte d’Aujourd’hui chez le moniteur : quand, horaire, jour, lieu et moniteur.
    /// Toute la carte ouvre la fiche, en zoom depuis elle.
    private func nextLessonCard(_ lesson: SchoolLesson, permitNames: [UUID: String]) -> some View {
        Button { opened = OpenedLesson(id: lesson.id, zooms: true) } label: {
            DrivyCard {
                VStack(alignment: .leading, spacing: 0) {
                    TimelineView(.everyMinute) { context in
                        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                            Text(lesson.hasStarted ? "Leçon en cours" : "Prochaine leçon")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DrivyTheme.muted)
                            Spacer(minLength: DrivySpacing.xs)
                            if let moment = SchoolLearnerLessonMoment.text(for: lesson, now: context.date) {
                                Text(moment)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DrivyTheme.accent)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    DrivyLessonRow(start: SchoolTrainingFormatting.time(lesson.plannedStart, zone: lesson.timeZone),
                        end: SchoolTrainingFormatting.time(lesson.plannedEnd, zone: lesson.timeZone),
                        title: SchoolTrainingFormatting.rowDay(lesson.plannedStart, zone: lesson.timeZone),
                        details: [nextLessonDetail(lesson, permitNames: permitNames)])
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content + DrivySpacing.m, style: .continuous))
        }
        .buttonStyle(DrivyTileButtonStyle())
        .disabled(feed.model(for: lesson)?.canOpenPedagogicalContent != true)
        .matchedTransitionSource(id: lesson.id, in: zoom)
        .accessibilityHint("Ouvre la leçon")
        .accessibilityIdentifier("training-next-lesson")
        .transition(.opacity)
    }

    /// Lieu de rendez-vous, permis quand la liste en mêle plusieurs, puis moniteur.
    private func nextLessonDetail(_ lesson: SchoolLesson, permitNames: [UUID: String]) -> String {
        [lesson.meetingPoint, permitNames[lesson.trainingId], instructorName(of: lesson)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
    /// Un seul contrôle natif : le libellé dit le filtre, la flèche dit le sens ; le menu range les deux choix.
    private var lessonsMenu: some View {
        Menu {
            Section("Afficher") {
                Picker("Afficher", selection: Binding(get: { activeFilter }, set: { value in
                    withAnimation(DrivyMotion.reveal(reduceMotion)) { filter = value }
                })) {
                    ForEach(filters) { item in Text(item.title).tag(item) }
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
                Text(period.isActive ? "\(activeFilter.title) · \(period.title)" : activeFilter.title)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Filtrer et trier les leçons")
        .accessibilityValue([activeFilter.title, period.isActive ? period.title : "Toutes les périodes", order.title].joined(separator: ", "))
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
                    if feed.isLoadingHistory { DrivyLoadingState(title: "Chargement de l’historique…") }
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
            if ownLessons {
                // L’élève : ce qui vient, puis le passé par mois. Une leçon restée sans résultat est du passé pour lui,
                // pas une tâche ; un mois n’a jamais deux titres identiques.
                let now = Date()
                let coming = values.filter { SchoolLearnerLessonMoment.isComing($0, now: now) }
                let past = values.filter { !SchoolLearnerLessonMoment.isComing($0, now: now) }
                let upcoming = coming.isEmpty ? [] : [TrainingLessonMonth(id: "upcoming", title: "À venir",
                    lessons: sortedByDate(coming, newestFirst: false))]
                return upcoming + monthGroups(past, newestFirst: true, prefix: "past")
            }
            let toFinish = values.filter { $0.drivyState == .toFinish }
            let waiting = values.filter { $0.drivyState == .waiting }
            let upcoming = values.filter { $0.drivyState == .planned || $0.drivyState == .inProgress }
            let past = values.filter { $0.status != "PLANNED" }
            var result = monthGroups(upcoming, newestFirst: false, prefix: "upcoming")
            if !waiting.isEmpty {
                result.append(TrainingLessonMonth(id: "waiting", title: "En attente", lessons: sortedByDate(waiting, newestFirst: false)))
            }
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
                        // Sous un titre d’état, la ligne ne redit pas la même information.
                        SchoolLessonHistoryRow(lesson: lesson, permit: permitNames[lesson.trainingId],
                            instructor: instructorName(of: lesson), showsState: month.id != "to-finish" && month.id != "waiting",
                            note: learnerNote(lesson))
                    }
                        .buttonStyle(DrivyRowButtonStyle())
                        .disabled(feed.model(for: lesson)?.canOpenPedagogicalContent != true)
                        .accessibilityIdentifier("training-lesson-\(lesson.id.uuidString)")
                }
            }
        }
    }
    /// L’élève ne termine pas de leçon : une leçon restée sans résultat se lit « En attente », sans encre d’alerte.
    private func learnerNote(_ lesson: SchoolLesson) -> DrivyRowNote? {
        guard ownLessons, [.waiting, .toFinish].contains(lesson.drivyState) else { return nil }
        return DrivyRowNote(text: DrivyLessonState.waiting.title, tone: .neutral)
    }
    /// Le moniteur n’est nommé que s’il n’est pas le lecteur : un collègue pour l’équipe, toujours pour l’élève.
    private func instructorName(of lesson: SchoolLesson) -> String? {
        lesson.instructorMembershipId == workspace.membership?.membershipId ? nil : lesson.providedInstructorName
    }
    /// Une compétence relève du référentiel de sa catégorie : « Tous » montre la progression de chaque permis
    /// sous son nom, l’une après l’autre, sans rien additionner d’un permis à l’autre.
    private var progress: some View {
        let names = permitNames
        let zone = workspace.school?.timeZone ?? "Europe/Zurich"
        return VStack(alignment: .leading, spacing: DrivySpacing.xl) {
            // Une formation illisible est dite par son erreur, pas par une section vide.
            ForEach(shown.filter { $0.training != nil || $0.isLoading }, id: \.trainingID) { model in
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    if mixesPermits { permitTitle(model, name: permitName(model, in: names)) }
                    SchoolTrainingProgressSection(model: model, schoolTimeZone: zone) { opened = OpenedLesson(id: $0) }
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

/// Quand a lieu la prochaine leçon de l’élève, en un mot : « Dans 25 min », « Aujourd’hui », « Demain »,
/// « Dans 3 jours ». Au-delà d’une semaine, la date de la ligne suffit. Calendrier du fuseau de la leçon.
enum SchoolLearnerLessonMoment {
    /// Ce qui vient pour l’élève : une leçon qui se déroule, ou une leçon planifiée dont le créneau n’est pas fini.
    /// Même règle que son souhait (`upcomingLessons`) : à l’heure du rendez-vous, tant que le moniteur n’a pas
    /// commencé, la leçon du jour reste la prochaine.
    static func isComing(_ lesson: SchoolLesson, now: Date) -> Bool {
        guard lesson.status == "PLANNED", let end = lesson.endsAt else { return false }
        return end > now
    }
    /// La leçon en tête : celle qui se déroule, sinon la plus proche de celles qui viennent.
    static func featured(_ lessons: [SchoolLesson], now: Date) -> SchoolLesson? {
        let coming = lessons.filter { isComing($0, now: now) }
        return coming.first { $0.hasStarted }
            ?? coming.min { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }
    static func text(for lesson: SchoolLesson, now: Date) -> String? {
        if lesson.hasStarted { return nil }
        guard let start = lesson.startsAt, let zone = TimeZone(identifier: lesson.timeZone) else { return nil }
        let minutes = Int(ceil(start.timeIntervalSince(now) / 60))
        guard minutes > 0 else { return "Maintenant" }
        if minutes < 60 { return "Dans \(minutes) min" }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        switch days {
        case 0: return "Aujourd’hui"
        case 1: return "Demain"
        case 2...6: return "Dans \(days) jours"
        default: return nil
        }
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
        let calendar = SchoolDateCache.shared.calendar(zone: timeZone)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return format(value, zone: zone, template: sameYear ? "EEE d MMMM" : "d MMMM yyyy").capitalizedFirst
    }
    /// Clé de regroupement par mois, dans le fuseau de la leçon.
    static func monthKey(_ value: String, zone: String) -> String {
        guard let date = SchoolLesson.date(value), let timeZone = TimeZone(identifier: zone) else { return "unknown" }
        let parts = SchoolDateCache.shared.calendar(zone: timeZone).dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }
    /// « Septembre 2026 ».
    static func monthTitle(_ value: String, zone: String) -> String {
        format(value, zone: zone, template: "LLLL yyyy").capitalizedFirst
    }
    private static func format(_ value: String, zone: String, template: String) -> String {
        guard let date = SchoolLesson.date(value), let timeZone = TimeZone(identifier: zone) else { return "Date indisponible" }
        return SchoolDateCache.shared.string(from: date, zone: timeZone, template: template)
    }
}
