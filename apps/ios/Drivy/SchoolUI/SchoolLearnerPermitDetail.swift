import SwiftUI

/// Profil → un permis : la formation d’abord (où elle en est, ce qui est acquis, ce qui vient), puis Leçons et
/// Progression, qui ouvrent leur onglet sur ce permis. Les séances et les compétences ne sont pas recopiées ici.
struct SchoolLearnerPermitDetail: View {
    let title: String
    let training: SchoolTraining?
    let model: SchoolTrainingWorkspace
    /// Affectations lues pour cette formation ; `nil` : pas lues, aucun moniteur n’est alors nommé.
    let assignments: [SchoolAssignment]?
    /// Ouvre Leçons ou Progression sur ce permis.
    let open: ((SchoolHomeTab) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Les chiffres ne se donnent qu’une fois toutes les leçons lues.
    private var overview: SchoolTrainingOverview? {
        guard model.lessonsLoaded, model.nextCursor == nil, model.training != nil else { return nil }
        return SchoolTrainingOverview.make(lessons: model.lessons, progress: model.progress)
    }

    private var instructors: [String] {
        guard let assignments else { return [] }
        return SchoolTrainingOverview.assignedInstructors(assignments: assignments, lessons: model.lessons, now: Date())
    }

    var body: some View {
        let figures = overview
        List {
            if figures == nil, let error = model.errorMessage {
                Section {
                    SchoolErrorNotice(message: error, retry: { Task { await model.load(keepingCurrent: true) } })
                }
                .drivyFormRows()
            }
            Section {
                formation(figures)
            } header: {
                Text("Formation").drivyFormSectionHeader()
            }
            .drivyFormRows()
            if let open {
                // Les chiffres sont dans la formation, juste au-dessus : ces lignes ne les redisent pas.
                Section {
                    DrivyNavigationRow(title: "Leçons") { open(.lessons) }
                        .accessibilityIdentifier("profile-permit-lessons")
                    DrivyNavigationRow(title: "Progression") { open(.progress) }
                        .accessibilityIdentifier("profile-permit-progress")
                }
                .listRowInsets(EdgeInsets(top: 0, leading: DrivySpacing.m, bottom: 0, trailing: DrivySpacing.m))
                .drivyFormRows()
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .animation(DrivyMotion.reveal(reduceMotion), value: figures)
        .animation(DrivyMotion.reveal(reduceMotion), value: model.progress)
        .refreshable { await model.load(keepingCurrent: true) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("learner-permit-detail")
    }

    /// Un seul bloc : l’état de la formation avec son permis, l’acquis du référentiel quand la progression est lue,
    /// les repères de leçons, puis les moniteurs affectés. Tant que les leçons ne sont pas toutes lues, leurs repères
    /// attendent sous un squelette plutôt que d’afficher un compte partiel.
    @ViewBuilder private func formation(_ overview: SchoolTrainingOverview?) -> some View {
        if let training {
            SchoolPermitFormationHeader(training: training)
        }
        if let levels = SchoolPermitLevels(progress: model.progress), levels.total > 0 {
            SchoolPermitLevelsRow(levels: levels)
        }
        if let overview {
            let items = Self.figures(overview, lessons: model.lessons, now: Date())
            if !items.isEmpty {
                DrivyFigureStrip(items: items)
                    .padding(.vertical, DrivySpacing.xs)
                    .accessibilityIdentifier("permit-figures")
            }
        } else if model.errorMessage == nil {
            DrivySkeletonRow(lines: 1).drivySkeleton("Chargement des leçons…")
        }
        let names = instructors
        if !names.isEmpty {
            // Un nom par ligne : ce sont les moniteurs que l’école affecte à cette formation, pas un référent.
            DrivyKeyValueRow(title: names.count == 1 ? "Moniteur affecté" : "Moniteurs affectés",
                value: names.joined(separator: "\n"))
        }
    }

    /// Leçons terminées (et leur temps réel), la dernière, la prochaine. Ce qui n’existe pas n’est pas dit.
    static func figures(_ overview: SchoolTrainingOverview, lessons: [SchoolLesson], now: Date) -> [DrivyFigureStrip.Item] {
        var items: [DrivyFigureStrip.Item] = [
            .init(id: "lessons", value: "\(overview.completedLessons)",
                label: overview.completedLessons == 1 ? "Leçon terminée" : "Leçons terminées")
        ]
        if overview.lessonMinutes > 0 {
            items.append(.init(id: "time", value: SchoolTrainingOverview.duration(overview.lessonMinutes), label: "De conduite"))
        }
        if let last = overview.lastCompleted {
            items.append(.init(id: "last", value: shortDay(last),
                label: "Dernière leçon"))
        }
        if let next = nextLesson(lessons, now: now) {
            items.append(.init(id: "next", value: shortDay(next),
                label: "Prochaine leçon"))
        }
        return items
    }

    /// « 21 sept. » : la rangée de chiffres tient sur une ligne ; l’année n’est dite que si elle n’est pas celle d’aujourd’hui.
    private static func shortDay(_ lesson: SchoolLesson) -> String {
        guard let date = lesson.startsAt else { return "" }
        let zone = TimeZone(identifier: lesson.timeZone) ?? .current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        return SchoolDateCache.shared.string(from: date, zone: zone, template: sameYear ? "dMMM" : "dMMMy")
    }

    /// La prochaine leçon planifiée qui n’a pas encore commencé.
    static func nextLesson(_ lessons: [SchoolLesson], now: Date) -> SchoolLesson? {
        lessons.filter { $0.status == "PLANNED" && !$0.hasStarted && ($0.startsAt ?? .distantPast) > now }
            .min { ($0.startsAt ?? .distantFuture) < ($1.startsAt ?? .distantFuture) }
    }
}

/// L’en-tête du bloc : le véhicule du permis, l’état de la formation, et depuis quand (ou jusqu’à quand).
/// Le nom du permis est déjà le titre de la page : il n’est pas redit.
private struct SchoolPermitFormationHeader: View {
    let training: SchoolTraining

    /// « Formation en cours », « Formation terminée » ; un état inconnu n’est pas qualifié.
    private var state: String {
        ["ACTIVE", "PAUSED", "COMPLETED", "CANCELLED"].contains(training.status)
            ? "Formation \(SchoolPresentation.trainingStatus(training.status).lowercased())" : "Formation"
    }

    private var dates: String? {
        if let closed = training.closedOn, training.status != "ACTIVE" {
            return "Jusqu’au \(SchoolPresentation.civilDate(closed))"
        }
        return training.startedOn.map { "Depuis le \(SchoolPresentation.civilDate($0))" }
    }

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.s) {
            DrivingLicenseIcon(code: training.categoryCode, size: 32, relativeTo: .title3, emphasis: .selected)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(state)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let dates {
                    Text(dates)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DrivySpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("permit-formation-state")
    }
}

/// Le référentiel du permis réparti en trois états : acquis (en autonomie), en cours (découverte ou
/// accompagnement), à voir (jamais évalué). Des décomptes du dernier niveau publié : ni score ni pourcentage.
struct SchoolPermitLevels: Equatable {
    let independent: Int
    let inProgress: Int
    let unseen: Int
    var total: Int { independent + inProgress + unseen }

    init(independent: Int, inProgress: Int, unseen: Int) {
        self.independent = independent; self.inProgress = inProgress; self.unseen = unseen
    }

    /// `nil` tant que la progression n’est pas lue : aucun décompte n’est alors affirmé.
    init?(progress: SchoolReportProgress?) {
        guard let progress else { return nil }
        let independent = progress.items.filter { $0.level == "INDEPENDENT" }.count
        let inProgress = progress.items.filter { $0.level == "DISCOVERING" || $0.level == "GUIDED" }.count
        // Un niveau inconnu n’est pas un acquis : il reste à voir.
        let unknown = progress.items.count - independent - inProgress
        self.init(independent: independent, inProgress: inProgress, unseen: progress.unobservedCompetencyIds.count + unknown)
    }
}

/// Une barre fine en trois tons et sa légende sur une ligne : ce que l’élève maîtrise, travaille, n’a pas encore vu.
private struct SchoolPermitLevelsRow: View {
    let levels: SchoolPermitLevels

    private var parts: [(count: Int, label: String, color: Color)] {
        [(levels.independent, "acquises", DrivyTheme.accentFill),
         (levels.inProgress, "en cours", DrivyTheme.accentFill.opacity(0.4)),
         (levels.unseen, "à voir", DrivyTheme.rail)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Compétences")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                Spacer(minLength: DrivySpacing.xs)
                Text("\(levels.independent) sur \(levels.total)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(DrivyTheme.muted)
            }
            GeometryReader { geometry in
                let gap: CGFloat = 2
                let shown = parts.filter { $0.count > 0 }
                let width = max(0, geometry.size.width - gap * CGFloat(max(0, shown.count - 1)))
                HStack(spacing: gap) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(part.color)
                            .frame(width: width * CGFloat(part.count) / CGFloat(max(1, levels.total)))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            legend
        }
        .padding(.vertical, DrivySpacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compétences")
        .accessibilityValue("\(levels.independent) acquises, \(levels.inProgress) en cours, \(levels.unseen) à voir, sur \(levels.total)")
        .accessibilityIdentifier("permit-levels")
    }

    /// Légende en ligne ; en grand texte, une entrée par ligne.
    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DrivySpacing.m) { legendItems }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) { legendItems }
        }
    }

    @ViewBuilder private var legendItems: some View {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
            HStack(spacing: DrivySpacing.xxs) {
                Circle().fill(part.color).frame(width: 8, height: 8)
                Text("\(part.count) \(part.label)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize()
            }
        }
    }
}
