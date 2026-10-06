import SwiftUI

/// Dimensions du récapitulatif d’une leçon.
enum SchoolLessonSummaryLayout {
    /// Deux colonnes de lecture : le bilan à gauche, le trajet et ses observations à droite.
    static let wideMaxWidth: CGFloat = 1248
    static let evidenceColumnWidth: CGFloat = 420
    /// Carte du trajet quand elle a sa propre colonne.
    static let wideMapHeight: CGFloat = 320
}

/// Ce qu’une leçon qui n’est plus à venir donne à lire, pour ce lecteur. Tout ce qui est vide est absent :
/// le récapitulatif ne montre jamais une section sans contenu.
@MainActor struct SchoolLessonSummaryContent {
    enum Mark: Equatable { case unsaved, forMe }

    struct Report {
        let nextStep: String
        let workedOn: String
        let observationText: String
        let levels: [SchoolReportObservation]
        let mark: Mark?

        var hasTexts: Bool {
            !(nextStep + workedOn + observationText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    let report: Report?
    /// Bilan absent, dit en une ligne à qui aurait pu le lire.
    let missingReport: String?
    let goals: [SchoolLessonGoal]
    /// Note que le moniteur garde pour lui ; l’école ne la rend qu’à lui.
    let privateNote: String
    let showsTrip: Bool
    let observations: [SchoolObservation]
    let hasPrices: Bool

    init(model: SchoolLessonReportWorkspace) {
        let lesson = model.lesson
        let isCompleted = lesson?.status == "COMPLETED"
        let isPlanned = lesson?.status == "PLANNED"
        var report: Report?
        var missing: String?
        if isCompleted {
            if model.isAuthor {
                // Le moniteur relit ce qu’il a saisi, envoyé ou non. Sans brouillon lu, rien n’est affirmé.
                if model.draft != nil {
                    if model.reportIsEmpty {
                        missing = SchoolReportFlowRules.missingReportLine(isAuthor: true, isOwnLearner: false, canReadSharedReport: true)
                    } else {
                        let mark: Mark? = model.draftChanged ? .unsaved : (model.sharing != nil && !model.reportShared ? .forMe : nil)
                        report = Report(nextStep: model.nextStep, workedOn: model.workedOn, observationText: model.observationText,
                            levels: model.observations, mark: mark)
                    }
                }
            } else if model.canReadSharedReport {
                if let revision = model.revisions.first {
                    report = Report(nextStep: revision.nextStep, workedOn: revision.workedOn, observationText: revision.observationText,
                        levels: revision.observations, mark: nil)
                } else if model.sharedReportWasRead {
                    missing = SchoolReportFlowRules.missingReportLine(isAuthor: false, isOwnLearner: model.isOwnLearner,
                        canReadSharedReport: true)
                }
            }
        }
        self.report = report
        missingReport = missing
        goals = isPlanned ? [] : (model.preparation?.goals ?? [])
        privateNote = isPlanned || !model.isAuthor
            ? "" : (model.preparation?.administrativeCheckNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        showsTrip = SchoolReportFlowRules.showsTrip(readsLesson: model.canReadLessonContent, hasTrack: !model.track.isEmpty,
            replayableCount: model.replayableCaptures.count, noteCount: SchoolReportFlowRules.tripNotes(model.captures).count,
            isPlanned: isPlanned)
        observations = model.lessonObservations
        hasPrices = lesson.map { !SchoolLessonHubRules.priceLines(lesson: $0, account: model.account).isEmpty } ?? false
    }

    var hasGoals: Bool { !goals.isEmpty || !privateNote.isEmpty }
    var hasEvidence: Bool { showsTrip || !observations.isEmpty }
    var hasMainColumn: Bool { report != nil || missingReport != nil || hasGoals }
    /// Seule chose à lire sous l’en-tête (leçon annulée ou manquée, bilan pas encore écrit) : les objectifs s’ouvrent d’eux-mêmes.
    var goalsStandAlone: Bool { report == nil && !hasEvidence }
}

/// Récapitulatif d’une leçon terminée, annulée ou manquée : une lecture, jamais un formulaire. En-tête compact,
/// bilan, compétences évaluées, trajet, observations, objectifs prévus, prix ; chaque partie n’existe que si elle a
/// un contenu. Aucune commande d’édition ici : la rédaction s’ouvre depuis la barre ou le menu de la fiche.
struct SchoolLessonSummaryView: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    let learnerName: String
    var finishError: String? = nil
    /// Fenêtre large : le trajet et ses observations prennent leur propre colonne.
    var isWide = false

    var body: some View {
        let content = SchoolLessonSummaryContent(model: model)
        let twoColumns = isWide && content.hasEvidence && content.hasMainColumn
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                SchoolLessonHeaderView(model: model, learnerName: learnerName, finishError: finishError, showsPrices: false)
                SchoolReportNotices(model: model)
                if twoColumns {
                    HStack(alignment: .top, spacing: DrivySpacing.xl) {
                        VStack(alignment: .leading, spacing: DrivySpacing.l) {
                            reading(content)
                            closing(content)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: DrivySpacing.l) {
                            evidence(content, mapHeight: SchoolLessonSummaryLayout.wideMapHeight)
                        }
                        .frame(width: SchoolLessonSummaryLayout.evidenceColumnWidth, alignment: .leading)
                    }
                } else {
                    reading(content)
                    evidence(content, mapHeight: DrivyMapLayout.previewHeight)
                    closing(content)
                }
            }
            .drivyPageContent(maxWidth: twoColumns ? SchoolLessonSummaryLayout.wideMaxWidth : DrivyLayout.readingColumn)
        }
        .background(DrivyTheme.surface)
        .accessibilityIdentifier("lesson-summary")
    }

    /// Le bilan du moniteur et les compétences qu’il a évaluées.
    @ViewBuilder private func reading(_ content: SchoolLessonSummaryContent) -> some View {
        if let report = content.report {
            SchoolLessonSummaryReport(report: report, competencies: model.competencies)
        }
        if let missing = content.missingReport {
            Text(missing)
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lesson-report-missing")
        }
    }

    /// Le trajet est une composante de la leçon : son aperçu, sa lecture, puis ce qui a été noté en route.
    @ViewBuilder private func evidence(_ content: SchoolLessonSummaryContent, mapHeight: CGFloat) -> some View {
        if content.showsTrip {
            SchoolLessonSummaryTrip(model: model, router: router, context: context, mapHeight: mapHeight)
        }
        if !content.observations.isEmpty {
            SchoolLessonSummaryObservations(model: model, router: router, observations: content.observations)
        }
    }

    /// Ce qui se consulte après coup : les objectifs prévus, puis le prix.
    @ViewBuilder private func closing(_ content: SchoolLessonSummaryContent) -> some View {
        if content.hasGoals {
            SchoolLessonSummaryGoals(goals: content.goals, privateNote: content.privateNote, startsExpanded: content.goalsStandAlone)
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
}

// MARK: Bilan

/// Les textes du bilan, puis les compétences évaluées ; le même corps pour le moniteur et pour l’élève.
private struct SchoolLessonSummaryReport: View {
    let report: SchoolLessonSummaryContent.Report
    let competencies: [SchoolCatalogCompetency]

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if report.hasTexts {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    DrivySectionHeader(title: "Bilan")
                    DrivyReportBody(nextStep: report.nextStep, workedOn: report.workedOn,
                        observationText: report.observationText, compact: true)
                }
            }
            if !report.levels.isEmpty {
                SchoolLessonSummaryCompetencies(levels: report.levels, competencies: competencies)
            }
            // L’inhabituel seulement : une saisie pas encore envoyée, un bilan gardé pour soi.
            switch report.mark {
            case .unsaved:
                markText("Non enregistré").accessibilityIdentifier("lesson-report-unsaved")
            case .forMe:
                markText("Pour moi").accessibilityIdentifier("lesson-report-private")
            case nil:
                EmptyView()
            }
        }
    }

    private func markText(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(DrivyTheme.muted)
    }
}

/// Une ligne par compétence évaluée : son nom, le niveau en mots, la situation, et la jauge commune à la progression.
private struct SchoolLessonSummaryCompetencies: View {
    let levels: [SchoolReportObservation]
    let competencies: [SchoolCatalogCompetency]
    @State private var showsAll = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let fold = SchoolReportFlowRules.fold(levels, limit: SchoolReportFlowRules.competencyFoldLimit)
        let visible = showsAll ? levels : fold.shown
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivySectionHeader(title: "Compétences évaluées")
            DrivyRowGroup {
                ForEach(visible) { level in row(level) }
            }
            if !showsAll && !fold.hidden.isEmpty {
                SchoolLessonSummaryMoreButton(
                    title: SchoolReportFlowRules.foldTitle(hidden: fold.hidden.count, noun: "compétences"),
                    identifier: "lesson-summary-more-competencies") { showsAll = true }
            }
        }
    }

    private func row(_ level: SchoolReportObservation) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.m))
        return layout {
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

// MARK: Trajet et observations

/// Aperçu du trajet avec sa lecture. Sans tracé lisible, une ligne de texte ouvre le replay.
private struct SchoolLessonSummaryTrip: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let context: SchoolReportContext
    let mapHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            DrivySectionHeader(title: "Trajet")
            if !model.track.isEmpty {
                SchoolLessonTripMap(model: model, router: router, context: context, height: mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            } else {
                SchoolLessonReplayLinks(model: model, router: router, context: context)
            }
            SchoolLessonTripNotes(captures: model.captures)
            // Le réglage se fait dans la rédaction ; ici, seul l’inhabituel se lit.
            if model.isAuthor, model.sharing != nil, !model.captureShared {
                Text("Pour moi").font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .accessibilityLabel("Trajet gardé pour toi")
            }
        }
    }
}

/// Ce qui a été noté pendant la leçon. Une observation placée sur le trajet se retrouve sur la carte : la toucher
/// fait grossir son épingle. Aucune commande : modifier, retirer ou garder pour soi se fait dans la rédaction.
private struct SchoolLessonSummaryObservations: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let observations: [SchoolObservation]
    @State private var showsAll = false

    var body: some View {
        let fold = SchoolReportFlowRules.fold(observations, limit: SchoolReportFlowRules.observationFoldLimit)
        let visible = showsAll ? observations : fold.shown
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            DrivySectionHeader(title: "Observations")
            DrivyRowGroup {
                ForEach(visible) { observation in
                    SchoolLessonSummaryObservationRow(model: model, router: router, observation: observation)
                }
            }
            if !showsAll && !fold.hidden.isEmpty {
                SchoolLessonSummaryMoreButton(
                    title: SchoolReportFlowRules.foldTitle(hidden: fold.hidden.count, noun: "observations"),
                    identifier: "lesson-summary-more-observations") { showsAll = true }
            }
        }
    }
}

private struct SchoolLessonSummaryObservationRow: View {
    let model: SchoolLessonReportWorkspace
    let router: SchoolReportRouter
    let observation: SchoolObservation

    private var competency: String? {
        guard let id = observation.competencyId else { return nil }
        return model.competencies.first(where: { $0.id == id })?.displayLabel
    }
    private var isAnchored: Bool { model.anchor(of: observation) != nil }
    private var isKept: Bool { model.isAuthor && model.isPrivate(observation) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            summary
            if isKept {
                Text("Pour moi").font(.caption).foregroundStyle(DrivyTheme.muted)
            }
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    @ViewBuilder private var summary: some View {
        let content = DrivyObservationSummary(observation: observation, competency: competency,
            detail: SchoolReportFlowRules.observationDetail(observation, zone: model.lesson?.timeZone))
        if isAnchored {
            content
                .contentShape(Rectangle())
                .onTapGesture { router.selectedObservation = router.selectedObservation == observation.id ? nil : observation.id }
                .accessibilityAction(named: "Montrer sur la carte") { router.selectedObservation = observation.id }
        } else {
            content
        }
    }
}

// MARK: Objectifs prévus

/// Les objectifs de la leçon, repliés : ils se consultent après coup. Seuls sous l’en-tête, ils s’ouvrent d’eux-mêmes.
private struct SchoolLessonSummaryGoals: View {
    let goals: [SchoolLessonGoal]
    let privateNote: String
    let startsExpanded: Bool
    @State private var expanded: Bool?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { expanded ?? startsExpanded }, set: { expanded = $0 })) {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                ForEach(goals) { goal in
                    Text(goal.label)
                        .font(.body)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DrivySpacing.xs)
        } label: {
            Text("Objectifs prévus")
                .font(.drivySection)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityIdentifier("lesson-goals")
    }
}

// MARK: Repli

/// « Afficher les 3 autres compétences » : la suite d’une liste repliée, à un geste.
private struct SchoolLessonSummaryMoreButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DrivyTheme.accent)
        .accessibilityIdentifier(identifier)
    }
}
