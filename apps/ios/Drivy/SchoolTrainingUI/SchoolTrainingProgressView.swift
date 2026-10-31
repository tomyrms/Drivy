import SwiftUI

/// La progression d’une formation : où l’élève en est, en une phrase et une toile (une branche par compétence), la
/// prochaine étape du dernier bilan, ce qu’il reste à travailler, puis, repliés, ce qui est acquis et ce qui n’a pas
/// encore été vu. La recherche traverse ces groupes ; chaque détail s’ouvre indépendamment sur place.
/// Ni score, ni pourcentage, ni tendance : le serveur ne garde que le dernier niveau publié, la toile le trace tel quel.
struct SchoolTrainingProgressSection: View {
    let model: SchoolTrainingWorkspace
    let trainingName: String
    /// Une évaluation est datée sans sa leçon : elle se lit dans le fuseau de l’école.
    let schoolTimeZone: String
    /// Vrai sur la page de l’élève : chaque bloc est une carte posée sur le fond de page, comme dans son Profil.
    /// Faux dans le dossier du moniteur, où la progression se lit à plat sous les leçons.
    var grouped = false
    let open: (UUID) -> Void
    /// Plusieurs détails restent lisibles ensemble, y compris après l’effacement d’une recherche.
    @State private var expanded: Set<UUID> = []
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    /// `nil` tant que le lecteur n’a rien choisi : l’acquis ne s’ouvre seul que s’il n’y a rien à travailler.
    @State private var showsIndependent: Bool?
    @State private var showsUnseen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Ce que la page montre : clé du fondu entre le squelette, la progression, le vide et la panne.
    private enum Stage: Equatable { case loading, failed, empty, content }

    private var stage: Stage {
        guard let value = model.progress else { return model.progressError == nil ? .loading : .failed }
        return value.items.isEmpty && value.unobservedCompetencyIds.isEmpty ? .empty : .content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if model.invalidated || model.accessRevoked || !model.hasPedagogicalRole {
                EmptyView()
            } else if let value = model.progress {
                // Une relecture en panne garde la dernière lecture sous son erreur.
                if let error = model.progressError { notice(error) }
                if value.items.isEmpty && value.unobservedCompetencyIds.isEmpty {
                    DrivyEmptyState(title: "Aucune compétence", symbol: "list.bullet")
                } else {
                    content(value)
                }
            } else if let error = model.progressError {
                notice(error)
            } else {
                block {
                    DrivySkeletonRows(count: 5)
                        .drivySkeleton("Chargement de la progression…")
                }
            }
        }
        // Le squelette cède la place à la progression (ou à sa panne) par un fondu ; la panne d’une relecture s’ajoute
        // de même ; les replis s’ouvrent et se ferment avec la même douceur.
        .animation(DrivyMotion.reveal(reduceMotion), value: stage)
        .animation(DrivyMotion.reveal(reduceMotion), value: model.progressError)
        .animation(DrivyMotion.reveal(reduceMotion), value: showsIndependent)
        .animation(DrivyMotion.reveal(reduceMotion), value: showsUnseen)
        .animation(DrivyMotion.reveal(reduceMotion), value: expanded)
        .onChange(of: availableIDs) { _, ids in expanded.formIntersection(ids) }
        .onChange(of: model.progress?.trainingId) { _, _ in resetReading() }
        .onChange(of: model.invalidated) { _, invalidated in if invalidated { resetReading() } }
        .onChange(of: model.accessRevoked) { _, revoked in if revoked { resetReading() } }
        .onChange(of: model.hasPedagogicalRole) { _, allowed in if !allowed { resetReading() } }
        .onChange(of: search) { previous, current in
            if !previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { revealExpandedGroups() }
        }
    }

    private var availableIDs: Set<UUID> {
        guard let value = model.progress else { return [] }
        return Set(value.items.map(\.id)).union(value.unobservedCompetencyIds)
    }

    private func resetReading() {
        expanded = []; search = ""; searchFocused = false
        showsIndependent = nil; showsUnseen = false
    }

    private func toggle(_ id: UUID) {
        if !expanded.insert(id).inserted { expanded.remove(id) }
    }

    /// Un détail choisi dans les résultats reste visible en revenant aux groupes ordinaires.
    private func revealExpandedGroups() {
        guard let value = model.progress else { return }
        if value.items.contains(where: { $0.level == "INDEPENDENT" && expanded.contains($0.id) }) { showsIndependent = true }
        if !expanded.isDisjoint(with: value.unobservedCompetencyIds) { showsUnseen = true }
    }

    private func notice(_ message: String) -> some View {
        SchoolErrorNotice(message: message, retry: { Task { await model.loadProgress() } })
    }

    @ViewBuilder private func content(_ value: SchoolReportProgress) -> some View {
        let reading = SchoolProgressReading(progress: value, curriculum: model.competencies, query: search)
        overview(value)
        lastLesson
        DrivySearchField(text: $search, prompt: "Rechercher une compétence", focus: $searchFocused)
            .onSubmit { searchFocused = false }
            .accessibilityIdentifier("progress-search")
        if reading.isSearching {
            searchResults(reading)
        } else {
            if !reading.toWorkOn.isEmpty {
                block("À travailler") { rows(reading.toWorkOn, reading: reading, showsMeter: true) }
            }
            if !reading.independent.isEmpty {
                // La recherche ne modifie pas le choix de repli du lecteur.
                block {
                    fold("En autonomie", count: reading.independent.count,
                         isExpanded: Binding(get: { showsIndependent ?? reading.toWorkOn.isEmpty }, set: { showsIndependent = $0 })) {
                        rows(reading.independent, reading: reading, showsMeter: false)
                    }
                }
            }
            if !reading.unseen.isEmpty {
                block {
                    fold("Pas encore vues", count: value.unobservedCompetencyIds.count, isExpanded: $showsUnseen) {
                        unseenRows(reading.unseen)
                    }
                }
            }
        }
    }

    @ViewBuilder private func searchResults(_ reading: SchoolProgressReading) -> some View {
        Text("\(trainingName) · \(reading.resultCount == 1 ? "1 compétence trouvée" : "\(reading.resultCount) compétences trouvées")")
            .font(.subheadline)
            .foregroundStyle(DrivyTheme.muted)
            .accessibilityIdentifier("progress-search-count")
        if reading.missingReferenceCount > 0 {
            Text("Référentiel incomplet : recherche limitée aux libellés disponibles.")
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("progress-search-partial")
        }
        if reading.resultCount == 0 {
            DrivyEmptyState(title: reading.missingReferenceCount > 0
                ? "Aucun résultat parmi les compétences disponibles" : "Aucune compétence trouvée", symbol: "magnifyingglass")
        }
        // Les résultats restent séparés par niveau, mais tous les groupes sont ouverts pendant la recherche.
        if !reading.toWorkOn.isEmpty {
            block("À travailler") { rows(reading.toWorkOn, reading: reading, showsMeter: true) }
        }
        if !reading.independent.isEmpty {
            block("En autonomie") { rows(reading.independent, reading: reading, showsMeter: false) }
        }
        if !reading.unseen.isEmpty {
            block("Pas encore vues") { unseenRows(reading.unseen) }
        }
    }

    /// Un bloc de la page : une carte sous son titre sur la page de l’élève, sinon le contenu à plat sous son titre.
    @ViewBuilder private func block<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        if grouped {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                if let title {
                    SchoolProgressGroupTitle(title: title).padding(.horizontal, DrivySpacing.m)
                }
                VStack(alignment: .leading, spacing: 0) { content() }
                    .drivyGroupedBlock()
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let title { SchoolProgressGroupTitle(title: title) }
                content()
            }
        }
    }

    /// La vue d’ensemble : le décompte en mots, puis la toile quand le référentiel est lu et tient en branches lisibles.
    private func overview(_ value: SchoolReportProgress) -> some View {
        let axes = SchoolProgressRules.radarAxes(curriculum: model.competencies.sorted { $0.sortOrder < $1.sortOrder }
            .map { (id: $0.id, label: $0.displayLabel) }, items: value.items, unobserved: value.unobservedCompetencyIds.count)
        return block {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                standing(value)
                // Aux très grandes tailles de texte, les libellés ne tiennent plus autour de la toile : les listes suffisent.
                if !axes.isEmpty && !typeSize.isAccessibilitySize {
                    SchoolProgressRadar(axes: axes)
                        .frame(maxWidth: 420)
                        .frame(maxWidth: .infinity)
                    Text("Du centre au bord : pas encore vue, en découverte, avec accompagnement, en autonomie.")
                        .font(.caption)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, grouped ? DrivySpacing.xs : 0)
        }
    }

    // MARK: - Où j’en suis

    /// La vue d’ensemble : un décompte en mots, jamais un score. L’acquis d’abord, le reste en une ligne.
    @ViewBuilder private func standing(_ value: SchoolReportProgress) -> some View {
        if let headline = SchoolProgressRules.autonomyLine(items: value.items, unobserved: value.unobservedCompetencyIds.count) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DrivyTheme.text)
                if let rest = SchoolProgressRules.countLine(items: value.items.filter { $0.level != "INDEPENDENT" },
                                                            unobserved: value.unobservedCompetencyIds.count) {
                    Text(rest)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("progress-standing")
        }
    }

    // MARK: - Prochaine étape et dernière leçon

    /// Le conseil du dernier bilan en tête, puis la leçon d’où il vient. Rien tant que le bilan n’est pas lu ou si sa
    /// lecture est refusée ; aucune étape n’est déduite des compétences.
    @ViewBuilder private var lastLesson: some View {
        if let last = model.lastEvaluated {
            let nextStep = last.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
            let day = SchoolTrainingFormatting.day(last.date, zone: last.timeZone ?? schoolTimeZone)
            if grouped {
                block(nextStep.isEmpty ? nil : "Prochaine étape") {
                    if !nextStep.isEmpty {
                        Text(nextStep)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DrivyTheme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, DrivySpacing.s)
                        Divider().overlay(DrivyTheme.border)
                    }
                    Button { open(last.lessonID) } label: { SchoolLastLessonLine(day: day) }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint("Ouvre la leçon")
                        .accessibilityIdentifier("progress-last-lesson")
                }
            } else {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                if !nextStep.isEmpty {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("Prochaine étape")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DrivyTheme.muted)
                            .accessibilityAddTraits(.isHeader)
                        Text(nextStep)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(DrivyTheme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button { open(last.lessonID) } label: { SchoolLastLessonLine(day: day) }
                    .buttonStyle(DrivyRowButtonStyle())
                    .accessibilityHint("Ouvre la leçon")
                    .accessibilityIdentifier("progress-last-lesson")
            }
            }
        }
    }

    // MARK: - Compétences

    private func rows(_ items: [SchoolReportProgressItem], reading: SchoolProgressReading, showsMeter: Bool) -> some View {
        DrivyRowGroup {
            ForEach(items) { item in
                let isExpanded = expanded.contains(item.id)
                VStack(alignment: .leading, spacing: 0) {
                    Button { toggle(item.id) } label: {
                        SchoolProgressRow(label: reading.label(item), level: item.level,
                            observedDay: SchoolTrainingFormatting.day(item.observedAt, zone: schoolTimeZone),
                            showsMeter: showsMeter, isExpanded: isExpanded)
                    }
                    .buttonStyle(DrivyRowButtonStyle())
                    .accessibilityHint(isExpanded ? "Masque le détail" : "Affiche le détail")
                    .accessibilityIdentifier("progress-competency-\(item.id.uuidString)")
                    if isExpanded { detail(item).transition(.opacity) }
                }
            }
        }
    }

    /// Le détail d’une compétence, sur place : son niveau en mots et sa date, la situation notée par le moniteur,
    /// puis la leçon d’où vient ce niveau.
    private func detail(_ item: SchoolReportProgressItem) -> some View {
        let context = item.context.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = SchoolTrainingFormatting.day(item.observedAt, zone: schoolTimeZone)
        return VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text("\(SchoolTrainingFormatting.level(item.level)) · \(day)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(DrivyTheme.muted)
            if !context.isEmpty {
                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.text)
            }
            Button("Voir la leçon") { open(item.sourceLessonId) }
                .buttonStyle(.drivyText)
                .accessibilityHint("Leçon source, \(trainingName)")
                .accessibilityIdentifier("progress-open-lesson")
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Une compétence non vue peut expliquer le référentiel, sans créer d’observation ni de niveau.
    private func unseenRows(_ competencies: [SchoolCatalogCompetency]) -> some View {
        DrivyRowGroup {
            ForEach(competencies) { competency in
                if let definition = SchoolProgressReading.definition(competency) {
                    let isExpanded = expanded.contains(competency.id)
                    VStack(alignment: .leading, spacing: 0) {
                        Button { toggle(competency.id) } label: {
                            SchoolProgressRow(label: competency.displayLabel, level: "", showsMeter: false, isExpanded: isExpanded)
                        }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint(isExpanded ? "Masque la définition" : "Affiche la définition du référentiel")
                        .accessibilityIdentifier("progress-competency-\(competency.id.uuidString)")
                        if isExpanded {
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text("Référentiel · \(trainingName)").font(.caption).foregroundStyle(DrivyTheme.muted)
                                Text(definition).font(.subheadline).foregroundStyle(DrivyTheme.text)
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("progress-definition-\(competency.id.uuidString)")
                            .transition(.opacity)
                        }
                    }
                } else {
                    SchoolProgressRow(label: competency.displayLabel, level: "", showsMeter: false, isExpanded: nil)
                }
            }
        }
    }

    /// Un groupe replié : son nom et son nombre suffisent tant qu’on ne l’ouvre pas.
    private func fold<Content: View>(_ title: String, count: Int, isExpanded: Binding<Bool>,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
        } label: {
            Text("\(title) (\(count))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.accent)
                .multilineTextAlignment(.leading)
                .frame(minHeight: DrivyLayout.tapTarget, alignment: .leading)
        }
    }
}

/// Titre d’un groupe de compétences : discret, sous le nom du permis quand la page en montre plusieurs.
private struct SchoolProgressGroupTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Une compétence : son libellé et sa jauge. Le niveau en mots reste dit à VoiceOver, que la jauge soit montrée ou non.
private struct SchoolProgressRow: View {
    let label: String
    let level: String
    /// Absente pour une compétence pas encore vue ; jamais remplacée par la date du chargement.
    var observedDay: String? = nil
    /// Inutile sous un titre qui dit déjà le niveau de tout le groupe.
    var showsMeter = true
    /// `nil` : la ligne n’a aucun détail à déplier (définition absente du référentiel).
    let isExpanded: Bool?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var levelWords: String { level.isEmpty ? "Pas encore vue" : SchoolTrainingFormatting.level(level) }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DrivySpacing.m))
        layout {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                if let observedDay {
                    Text(observedDay)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(DrivyTheme.muted)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DrivySpacing.s) {
                if showsMeter && !level.isEmpty { DrivyCompetencyMeter(level: level) }
                if let isExpanded {
                    // Vers le bas : la ligne se déplie ici, elle ne mène pas ailleurs.
                    // Réduire les animations : le symbole change en fondu au lieu de tourner.
                    Image(systemName: reduceMotion && isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .rotationEffect(.degrees(!reduceMotion && isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        // L’état déplié se dit aussi quand les indications de VoiceOver sont coupées.
        .accessibilityValue([levelWords, observedDay.map { "Évaluation : \($0)" },
            isExpanded.map { $0 ? "Détail affiché" : "Détail masqué" }].compactMap { $0 }.joined(separator: ", "))
    }
}

/// La leçon du dernier bilan, en une ligne qui l’ouvre.
private struct SchoolLastLessonLine: View {
    let day: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            Text("Leçon du \(day)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(DrivyTheme.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            DrivyRowChevron()
        }
        .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
