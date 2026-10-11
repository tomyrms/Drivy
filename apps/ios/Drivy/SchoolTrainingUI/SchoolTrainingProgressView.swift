import SwiftUI

/// La progression d’une formation : la prochaine étape du dernier bilan, ce qu’il reste à travailler, puis, repliés,
/// ce qui est acquis et ce qui n’a pas encore été vu. Une ligne dit une compétence et son niveau, rien d’autre :
/// la situation et le détail sont dans la leçon qu’elle ouvre.
/// Ni score, ni pourcentage, ni barre, ni tendance : le serveur ne garde que le dernier niveau publié.
struct SchoolTrainingProgressSection: View {
    let model: SchoolTrainingWorkspace
    /// Une évaluation est datée sans sa leçon : elle se lit dans le fuseau de l’école.
    let schoolTimeZone: String
    /// L’équipe lit de quand date chaque niveau (une compétence pas revue depuis longtemps) ; l’élève non.
    var showsDates = false
    let open: (UUID) -> Void
    /// `nil` tant que le lecteur n’a rien choisi : l’acquis ne s’ouvre seul que s’il n’y a rien à travailler.
    @State private var showsIndependent: Bool?
    @State private var showsUnseen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ce que la page montre : clé du fondu entre le squelette, la progression, le vide et la panne.
    private enum Stage: Equatable { case loading, failed, empty, content }

    private var stage: Stage {
        guard let value = model.progress else { return model.progressError == nil ? .loading : .failed }
        return value.items.isEmpty && value.unobservedCompetencyIds.isEmpty ? .empty : .content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let value = model.progress {
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
                DrivySkeletonRows(count: 5)
                    .drivySkeleton("Chargement de la progression…")
            }
        }
        // Le squelette cède la place à la progression (ou à sa panne) par un fondu ; la panne d’une relecture s’ajoute
        // de même ; les replis s’ouvrent et se ferment avec la même douceur.
        .animation(DrivyMotion.reveal(reduceMotion), value: stage)
        .animation(DrivyMotion.reveal(reduceMotion), value: model.progressError)
        .animation(DrivyMotion.reveal(reduceMotion), value: showsIndependent)
        .animation(DrivyMotion.reveal(reduceMotion), value: showsUnseen)
    }

    private var order: [UUID] { model.competencies.map(\.id) }

    /// Le libellé du référentiel fait foi ; celui de l’évaluation sert tant qu’il n’est pas lu.
    private func label(_ item: SchoolReportProgressItem) -> String {
        model.competencies.first { $0.id == item.id }?.displayLabel ?? item.displayLabel
    }

    private func notice(_ message: String) -> some View {
        SchoolErrorNotice(message: message, retry: { Task { await model.loadProgress() } })
    }

    @ViewBuilder private func content(_ value: SchoolReportProgress) -> some View {
        let toWorkOn = SchoolProgressRules.toWorkOn(value.items)
        let independent = SchoolProgressRules.independent(value.items, order: order)
        lastLesson
        if !toWorkOn.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SchoolProgressGroupTitle(title: "À travailler")
                rows(toWorkOn, showsMeter: true)
            }
        }
        if !independent.isEmpty {
            // Replié quand il reste à travailler : la page tient alors sur un écran.
            fold("En autonomie", count: independent.count,
                 isExpanded: Binding(get: { showsIndependent ?? toWorkOn.isEmpty }, set: { showsIndependent = $0 })) {
                rows(independent, showsMeter: false)
            }
        }
        unseen(count: value.unobservedCompetencyIds.count)
    }

    // MARK: - Prochaine étape et dernière leçon

    /// Le conseil du dernier bilan en tête, puis la leçon d’où il vient. Rien tant que le bilan n’est pas lu ou si sa
    /// lecture est refusée ; aucune étape n’est déduite des compétences.
    @ViewBuilder private var lastLesson: some View {
        if let last = model.lastEvaluated {
            let nextStep = last.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
            let day = SchoolTrainingFormatting.day(last.date, zone: last.timeZone ?? schoolTimeZone)
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

    // MARK: - Compétences

    private func rows(_ items: [SchoolReportProgressItem], showsMeter: Bool) -> some View {
        DrivyRowGroup {
            ForEach(items) { item in
                Button { open(item.sourceLessonId) } label: {
                    SchoolProgressRow(label: label(item), level: item.level, showsMeter: showsMeter,
                        date: showsDates ? SchoolTrainingFormatting.day(item.observedAt, zone: schoolTimeZone) : nil)
                }
                .buttonStyle(DrivyRowButtonStyle())
                .accessibilityHint("Ouvre la leçon")
            }
        }
    }

    /// Ce qui n’a pas encore été vu n’appelle aucun geste : replié, et ses lignes n’ouvrent rien.
    @ViewBuilder private func unseen(count: Int) -> some View {
        let competencies = model.unobservedCompetencies
        if !competencies.isEmpty {
            fold("Pas encore vues", count: max(count, competencies.count), isExpanded: $showsUnseen) {
                DrivyRowGroup {
                    ForEach(competencies) { competency in
                        SchoolProgressRow(label: competency.displayLabel, level: "", showsMeter: false, opensLesson: false)
                    }
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
                .frame(minHeight: 44, alignment: .leading)
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
    /// Inutile sous un titre qui dit déjà le niveau de tout le groupe.
    var showsMeter = true
    var date: String? = nil
    var opensLesson = true
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let date {
                    Text(date).font(.caption).monospacedDigit().foregroundStyle(DrivyTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DrivySpacing.s) {
                if showsMeter && !level.isEmpty { DrivyCompetencyMeter(level: level) }
                if opensLesson {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([levelWords, date].compactMap { $0 }.joined(separator: ", "))
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
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
