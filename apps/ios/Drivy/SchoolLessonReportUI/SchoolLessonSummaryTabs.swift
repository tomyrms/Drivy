import SwiftUI

/// Les trois lectures d’une leçon terminée, sous l’en-tête de l’élève. Mêmes onglets pour le moniteur et pour
/// l’élève : ce que chacun y lit vient de `SchoolLessonSummaryContent`, qui ne garde que ce que l’école lui rend.
enum SchoolLessonSummaryTab: String, CaseIterable, Identifiable, Hashable {
    case report, competencies, route

    var id: String { rawValue }
    var title: String {
        switch self {
        case .report: "Bilan"
        case .competencies: "Compétences"
        case .route: "Trajet & notes"
        }
    }
    /// VoiceOver lit l’intitulé entier, sans esperluette.
    var spokenTitle: String { self == .route ? "Trajet et observations" : title }
}

/// Une observation se range selon son appréciation : ce qui va bien, ce qui demande de l’attention, le reste
/// (repère posé en route, note sans appréciation).
enum SchoolLessonObservationGroup: Int, CaseIterable, Identifiable, Comparable {
    case positive, attention, general

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .positive: "Points positifs"
        case .attention: "Points d’attention"
        case .general: "Autres observations"
        }
    }

    init(status: SchoolObservationStatus?) {
        switch status {
        case .positive: self = .positive
        case .attention, .toWorkOn: self = .attention
        case nil: self = .general
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Règles de lecture du récapitulatif à onglets, sans vue : ce qu’elles décident se teste sans écran.
enum SchoolLessonSummaryRules {
    struct Duration: Equatable {
        let minutes: Int
        /// Mesurée entre le départ et la fin confirmés par l’école ; sinon, la durée réservée.
        let isActual: Bool
    }

    struct ObservationSection<Item>: Identifiable {
        let group: SchoolLessonObservationGroup
        let items: [Item]
        var id: Int { group.rawValue }
    }

    /// La durée réelle quand l’école connaît le départ et la fin ; à défaut la durée réservée, dite comme telle.
    /// Jamais un horaire deviné.
    static func duration(_ lesson: SchoolLesson) -> Duration? {
        if let start = lesson.startedAt, let end = lesson.actualEnd.flatMap(SchoolLesson.date), end > start {
            return Duration(minutes: Int((end.timeIntervalSince(start) / 60).rounded()), isActual: true)
        }
        let planned = lesson.durationMinutes
        return planned > 0 ? Duration(minutes: planned, isActual: false) : nil
    }

    /// Les observations par appréciation, chaque groupe dans l’ordre reçu (celui du trajet). Un groupe vide est absent.
    static func sections<Item>(_ items: [Item], status: (Item) -> SchoolObservationStatus?) -> [ObservationSection<Item>] {
        let grouped = Dictionary(grouping: items) { SchoolLessonObservationGroup(status: status($0)) }
        return SchoolLessonObservationGroup.allCases.compactMap { group in
            guard let values = grouped[group], !values.isEmpty else { return nil }
            return ObservationSection(group: group, items: values)
        }
    }

    /// « 2 en autonomie · 1 avec accompagnement » : du niveau le plus avancé au premier, un niveau absent n’est pas dit.
    static func levelBreakdown(_ levels: [String]) -> String? {
        let parts: [String] = [("INDEPENDENT", "en autonomie"), ("GUIDED", "avec accompagnement"), ("DISCOVERING", "en découverte")]
            .compactMap { key, label in
                let count = levels.filter { $0 == key }.count
                return count > 0 ? "\(count) \(label)" : nil
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Le sélecteur segmenté garde ses trois intitulés lisibles jusqu’à cette taille ; au-delà, un menu.
    static func usesMenu(_ size: DynamicTypeSize) -> Bool { size > .xLarge }
}

/// Récapitulatif d’une leçon terminée : l’en-tête de l’élève, puis Bilan, Compétences, Trajet & notes.
/// Le sélecteur reste en haut pendant la lecture ; changer d’onglet remonte au début de l’onglet sans saut de page.
struct SchoolLessonSummaryTabs: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    let learnerName: String
    let finishError: String?
    let content: SchoolLessonSummaryContent
    let isWide: Bool
    @State private var tab: SchoolLessonSummaryTab = .report
    /// Défilement et hauteurs relevés à l’affichage : ils décident seulement s’il faut remonter au sélecteur.
    @State private var offset: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    @State private var mapIsVisible = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barID = "lesson-summary-tabs"
    private static let mapID = "lesson-summary-map"

    /// Position du sélecteur dans la page : au-delà, il est épinglé et l’onglet suivant doit commencer sous lui.
    private var barTop: CGFloat { DrivySpacing.m + headerHeight + DrivySpacing.l }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DrivySpacing.l, pinnedViews: .sectionHeaders) {
                    VStack(alignment: .leading, spacing: DrivySpacing.l) {
                        SchoolLessonHeaderView(model: model, learnerName: learnerName, finishError: finishError, showsPrices: false)
                        SchoolReportNotices(model: model)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    Section {
                        // Les deux onglets se superposent pendant le fondu : la page ne s’allonge jamais de leur somme.
                        ZStack(alignment: .topLeading) {
                            page(tab)
                                .id(tab)
                                .transition(.opacity)
                        }
                        // Un onglet court garde la hauteur de l’écran : le sélecteur épinglé ne redescend pas d’un coup.
                        .frame(maxWidth: .infinity, minHeight: max(0, viewport - barHeight - DrivySpacing.l), alignment: .topLeading)
                    } header: {
                        bar
                            .id(Self.barID)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                    }
                }
                .drivyPageContent()
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, value in
                offset = value
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height - $0.contentInsets.top - $0.contentInsets.bottom } action: { _, value in
                viewport = value
            }
            .onChange(of: tab) { _, _ in
                // Lu plus bas que le sélecteur : l’onglet suivant s’ouvre sur son début, sélecteur en place.
                if offset > barTop + 1 { proxy.scrollTo(Self.barID, anchor: .top) }
            }
            .onChange(of: router.selectedObservation) { _, selected in
                // Une observation touchée sous la carte : la carte revient à l’écran pour montrer son épingle.
                guard selected != nil, tab == .route, !mapIsVisible else { return }
                withAnimation(DrivyMotion.reveal(reduceMotion)) { proxy.scrollTo(Self.mapID, anchor: .center) }
            }
        }
        .background(DrivyTheme.surface)
        .accessibilityIdentifier("lesson-summary")
    }

    // MARK: Sélecteur

    private var selection: Binding<SchoolLessonSummaryTab> {
        Binding(get: { tab }, set: { open($0) })
    }

    private func open(_ next: SchoolLessonSummaryTab) {
        guard next != tab else { return }
        withAnimation(DrivyMotion.reveal(reduceMotion)) { tab = next }
    }

    /// Segmenté, comme les sections du dossier ; en très grand texte, un menu qui nomme l’onglet ouvert.
    @ViewBuilder private var bar: some View {
        let picker = Picker("Afficher", selection: selection) {
            ForEach(SchoolLessonSummaryTab.allCases) { item in
                Text(item.title).accessibilityLabel(item.spokenTitle).tag(item)
            }
        }
        Group {
            if SchoolLessonSummaryRules.usesMenu(typeSize) {
                picker.pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
            } else {
                picker.pickerStyle(.segmented)
                    .labelsHidden()
            }
        }
        .drivyControlTint()
        .padding(.vertical, DrivySpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Épinglé, le sélecteur garde le fond de la page sur toute la largeur : le texte passe dessous, pas à travers.
        .background { DrivyTheme.surface.padding(.horizontal, -DrivySpacing.xl) }
        .accessibilityIdentifier(Self.barID)
    }

    // MARK: Onglets

    private func page(_ tab: SchoolLessonSummaryTab) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            switch tab {
            case .report: reportPage
            case .competencies: competenciesPage
            case .route: routePage
            }
        }
        .padding(.top, DrivySpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Bilan

    @ViewBuilder private var reportPage: some View {
        let items = glanceItems
        if !items.isEmpty {
            DrivyFigureStrip(items: items)
                .accessibilityIdentifier("lesson-summary-glance")
        }
        if let report = content.report {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                if report.hasTexts {
                    DrivyReportBody(nextStep: report.nextStep, workedOn: report.workedOn,
                        observationText: report.observationText, compact: true)
                } else {
                    Text("Aucun texte ajouté.")
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                }
                SchoolLessonSummaryMarkText(mark: report.mark)
            }
            .accessibilityIdentifier("lesson-summary-report")
        }
        missingReportLine
        if content.hasGoals {
            SchoolLessonSummaryGoalList(goals: content.goals, privateNote: content.privateNote)
        }
        if content.hasPrices, let lesson = model.lesson {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Divider().overlay(DrivyTheme.border)
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    SchoolLessonPriceLines(model: model, lesson: lesson)
                }
            }
        }
    }

    @ViewBuilder private var missingReportLine: some View {
        if let missing = content.missingReport {
            Text(missing)
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lesson-report-missing")
        }
    }

    /// Les faits de la séance en une rangée : permis, durée, et ce que les deux autres onglets contiennent.
    /// Une valeur inconnue est absente, jamais remplacée par un zéro.
    private var glanceItems: [DrivyFigureStrip.Item] {
        var items: [DrivyFigureStrip.Item] = []
        if let code = model.training?.categoryCode, !code.isEmpty {
            items.append(.init(id: "permit", value: DrivingLicenseCategory(code: code)?.code ?? code, label: "Permis", licenseCode: code))
        }
        if let lesson = model.lesson, let duration = SchoolLessonSummaryRules.duration(lesson) {
            items.append(.init(id: "duration", value: SchoolTrainingOverview.duration(duration.minutes),
                label: duration.isActual ? "Durée" : "Durée prévue"))
        }
        if let levels = content.report?.levels, !levels.isEmpty {
            items.append(.init(id: "competencies", value: "\(levels.count)",
                label: levels.count == 1 ? "Compétence" : "Compétences", action: { open(.competencies) },
                actionHint: "Ouvre l’onglet Compétences"))
        }
        if !content.observations.isEmpty {
            items.append(.init(id: "observations", value: "\(content.observations.count)",
                label: content.observations.count == 1 ? "Observation" : "Observations", action: { open(.route) },
                actionHint: "Ouvre l’onglet Trajet et observations"))
        }
        return items
    }

    // Compétences

    @ViewBuilder private var competenciesPage: some View {
        let levels = content.report?.levels ?? []
        if levels.isEmpty {
            if content.report == nil, content.missingReport != nil {
                missingReportLine
            } else {
                DrivyEmptyState(title: "Aucune compétence évaluée", symbol: "checklist")
                    .accessibilityIdentifier("lesson-competencies-empty")
            }
        } else {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                if let breakdown = SchoolLessonSummaryRules.levelBreakdown(levels.map(\.level)) {
                    Text(breakdown)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DrivyRowGroup {
                    ForEach(levels) { level in
                        SchoolLessonCompetencyRow(level: level, competencies: model.competencies)
                    }
                }
            }
            .accessibilityIdentifier("lesson-competencies")
        }
    }

    // Trajet & notes

    @ViewBuilder private var routePage: some View {
        if !content.showsTrip && content.observations.isEmpty {
            DrivyEmptyState(title: "Aucun trajet ni observation", symbol: "map")
                .accessibilityIdentifier("lesson-route-empty")
        } else {
            if content.showsTrip {
                SchoolLessonSummaryTrip(model: model, router: router, context: context,
                    mapHeight: isWide ? SchoolLessonSummaryLayout.wideMapHeight : DrivyMapLayout.previewHeight, showsTitle: false)
                    .id(Self.mapID)
                    .onScrollVisibilityChange(threshold: 0.6) { mapIsVisible = $0 }
            }
            ForEach(SchoolLessonSummaryRules.sections(content.observations) { SchoolLessonHubRules.status(of: $0) }) { section in
                SchoolLessonSummaryObservationGroup(model: model, router: router, title: section.group.title,
                    observations: section.items)
            }
        }
    }
}

// MARK: Bilan

/// L’inhabituel seulement : une saisie pas encore envoyée, un bilan gardé pour soi.
struct SchoolLessonSummaryMarkText: View {
    let mark: SchoolLessonSummaryContent.Mark?

    var body: some View {
        switch mark {
        case .unsaved:
            Text("Non enregistré").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                .accessibilityIdentifier("lesson-report-unsaved")
        case .forMe:
            Text("Pour moi").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                .accessibilityIdentifier("lesson-report-private")
        case nil:
            EmptyView()
        }
    }
}

/// Les objectifs prévus, ouverts : dans le bilan, ils disent ce que la séance devait travailler.
private struct SchoolLessonSummaryGoalList: View {
    let goals: [SchoolLessonGoal]
    let privateNote: String

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivySectionHeader(title: "Objectifs prévus")
            ForEach(goals) { goal in
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    Circle().fill(DrivyTheme.muted).frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        .accessibilityHidden(true)
                    Text(goal.label)
                        .font(.body)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !privateNote.isEmpty {
                // Même cadenas que dans la préparation : cette ligne reste au moniteur, l’élève ne la reçoit pas.
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    DrivyPrivacyMark(isPrivate: true)
                    Text(privateNote).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("lesson-private-note")
            }
        }
        .accessibilityIdentifier("lesson-goals")
    }
}

// MARK: Compétences

/// Une compétence évaluée : son nom, le niveau en mots, la situation notée, et le parcours en trois étapes commun
/// à la progression. Le même rang dans le récapitulatif et dans l’onglet.
struct SchoolLessonCompetencyRow: View {
    let level: SchoolReportObservation
    let competencies: [SchoolCatalogCompetency]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.m))
        layout {
            DrivyCompetencyNote(label: competencies.first(where: { $0.id == level.id })?.displayLabel ?? "Compétence",
                level: level.levelLabel, context: level.context)
            DrivyCompetencyMeter(level: level.level)
                .padding(.top, DrivySpacing.xs)
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Observations

/// Un groupe d’observations (positives, d’attention, autres) en fil : la couleur du repère est celle de l’épingle
/// sur la carte. Toucher une observation placée sur le trajet montre son épingle.
private struct SchoolLessonSummaryObservationGroup: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let title: String
    let observations: [SchoolObservation]

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                Text(title)
                    .font(.drivySection)
                    .foregroundStyle(DrivyTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("\(observations.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(observations.enumerated()), id: \.element.id) { index, observation in
                    DrivyThreadItem(position: .at(index, count: observations.count),
                        isCurrent: router.selectedObservation == observation.id,
                        markerColor: SchoolReportObservationsSection.color(observation),
                        markerGlyph: observation.glyph(competencies: model.competencies)) {
                        SchoolLessonSummaryObservationRow(model: model, router: router, observation: observation)
                    }
                }
            }
        }
    }
}
