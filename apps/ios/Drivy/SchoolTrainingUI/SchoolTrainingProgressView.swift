import SwiftUI

/// La progression d’une formation : la dernière leçon évaluée, un décompte en mots, puis les
/// compétences rangées par ce qu’il reste à faire. Chaque ligne ouvre la leçon d’où vient son niveau.
/// Ni score, ni pourcentage, ni barre, ni tendance : le serveur ne garde que le dernier niveau publié.
struct SchoolTrainingProgressSection: View {
    let model: SchoolTrainingWorkspace
    /// Une évaluation est datée sans sa leçon : elle se lit dans le fuseau de l’école.
    let schoolTimeZone: String
    let open: (UUID) -> Void
    @State private var showsUnseen = false

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let value = model.progress {
                // Une relecture en panne garde la dernière lecture sous son erreur.
                if let error = model.progressError { notice(error) }
                if value.items.isEmpty && value.unobservedCompetencyIds.isEmpty {
                    DrivyEmptyState(title: "Aucune compétence", symbol: "list.bullet")
                } else {
                    overview(value)
                    group("À travailler", SchoolProgressRules.toWorkOn(value.items))
                    group("En autonomie", SchoolProgressRules.independent(value.items, order: order))
                    unseen(count: value.unobservedCompetencyIds.count)
                }
            } else if let error = model.progressError {
                notice(error)
            } else {
                DrivySkeletonRows(count: 5)
                    .drivySkeleton("Chargement de la progression…")
            }
        }
    }

    private var order: [UUID] { model.competencies.map(\.id) }

    /// Le libellé du référentiel fait foi ; celui de l’évaluation sert tant qu’il n’est pas lu.
    private func label(_ item: SchoolReportProgressItem) -> String {
        model.competencies.first { $0.id == item.id }?.displayLabel ?? item.displayLabel
    }

    private func notice(_ message: String) -> some View {
        SchoolErrorNotice(message: message, retry: { Task { await model.loadProgress() } })
    }

    // MARK: - Dernière leçon et décompte

    @ViewBuilder private func overview(_ value: SchoolReportProgress) -> some View {
        let summary = lastLesson(value)
        let counts = SchoolProgressRules.countLine(items: value.items, unobserved: value.unobservedCompetencyIds.count)
        if summary != nil || counts != nil {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                if let summary {
                    Button { open(summary.lessonID) } label: { summary }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint("Ouvre la leçon")
                }
                if let counts {
                    Text(counts)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Omis tant que le bilan n’est pas lu, si sa lecture est refusée, ou s’il n’a rien à dire.
    private func lastLesson(_ value: SchoolReportProgress) -> SchoolLastLessonSummary? {
        guard let last = model.lastEvaluated else { return nil }
        let nextStep = last.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        let worked = SchoolProgressRules.worked(in: last.lessonID, items: value.items, order: order).map { label($0) }
        guard !nextStep.isEmpty || !worked.isEmpty else { return nil }
        return SchoolLastLessonSummary(lessonID: last.lessonID,
            day: SchoolTrainingFormatting.day(last.date, zone: last.timeZone ?? schoolTimeZone),
            nextStep: nextStep, worked: worked)
    }

    // MARK: - Compétences

    @ViewBuilder private func group(_ title: String, _ items: [SchoolReportProgressItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SchoolProgressGroupTitle(title: title)
                DrivyRowGroup {
                    ForEach(items) { item in
                        Button { open(item.sourceLessonId) } label: {
                            SchoolProgressRow(label: label(item), level: item.level, context: item.context,
                                date: SchoolTrainingFormatting.day(item.observedAt, zone: schoolTimeZone))
                        }
                        .buttonStyle(DrivyRowButtonStyle())
                        .accessibilityHint("Ouvre la leçon")
                    }
                }
            }
        }
    }

    /// Replié : ce qui n’a pas encore été vu n’appelle aucun geste.
    @ViewBuilder private func unseen(count: Int) -> some View {
        let competencies = model.unobservedCompetencies
        if !competencies.isEmpty {
            DisclosureGroup(isExpanded: $showsUnseen) {
                DrivyRowGroup {
                    ForEach(competencies) { competency in
                        SchoolProgressRow(label: competency.displayLabel, level: "", opensLesson: false)
                    }
                }
            } label: {
                Text("Pas encore vues (\(max(count, competencies.count)))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 44, alignment: .leading)
            }
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

/// Une compétence : libellé, niveau en mots, situation, date, et le parcours partagé avec le bilan.
private struct SchoolProgressRow: View {
    let label: String
    let level: String
    /// La situation notée par le moniteur (« Slalom sur le plateau »), si elle existe.
    var context: String? = nil
    var date: String? = nil
    var opensLesson = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.m))
        layout {
            DrivyCompetencyNote(label: label, level: level.isEmpty ? "Pas encore vue" : SchoolTrainingFormatting.level(level),
                context: context, date: date)
            HStack(spacing: DrivySpacing.s) {
                DrivyCompetencyMeter(level: level)
                if opensLesson {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, DrivySpacing.xs)
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// La dernière leçon et la prochaine étape du même bilan suivent un seul fil.
/// Une étape absente ne produit ni station vide ni texte déduit des compétences.
private struct SchoolLastLessonSummary: View {
    let lessonID: UUID
    let day: String
    let nextStep: String
    let worked: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DrivyThreadItem(position: nextStep.isEmpty ? .only : .first) {
                HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("Dernière leçon évaluée")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DrivyTheme.muted)
                        Text(day)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(DrivyTheme.text)
                        if !worked.isEmpty {
                            Text("Travaillé : \(worked.joined(separator: ", "))")
                                .font(.subheadline)
                                .foregroundStyle(DrivyTheme.muted)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DrivyTheme.muted)
                        .accessibilityHidden(true)
                }
            }
            if !nextStep.isEmpty {
                DrivyThreadItem(position: .last, isCurrent: true, isPast: false) {
                    VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                        Text("Prochaine étape")
                            .font(.headline)
                            .foregroundStyle(DrivyTheme.text)
                        Text(nextStep)
                            .font(.body)
                            .foregroundStyle(DrivyTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
