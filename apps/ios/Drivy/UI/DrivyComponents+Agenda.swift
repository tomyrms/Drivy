import SwiftUI

// Shared anatomy of the agenda, the training dossier and the lesson report:
// one lesson row, one wording per lesson or report state, one report body.
// Presentation only: states are derived from values the server already returned.

/// Lesson state as shown to people. Same title, symbol and tone everywhere.
enum DrivyLessonState {
    case planned, inProgress, toFinish, completed, cancelled, noShow, unknown

    init(status: String, start: Date?, end: Date?, now: Date = Date()) {
        switch status {
        case "PLANNED":
            if let start, let end, start <= now, now < end { self = .inProgress }
            else if let end, end <= now { self = .toFinish }
            else { self = .planned }
        case "COMPLETED": self = .completed
        case "CANCELLED": self = .cancelled
        case "NO_SHOW": self = .noShow
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .planned: "Planifiée"
        case .inProgress: "En cours"
        case .toFinish: "À terminer"
        case .completed: "Terminée"
        case .cancelled: "Annulée"
        case .noShow: "Absence"
        case .unknown: "À vérifier"
        }
    }

    var symbol: String {
        switch self {
        case .planned: "calendar"
        case .inProgress: "clock"
        case .toFinish: "clock.badge.exclamationmark"
        case .completed: "checkmark"
        case .cancelled: "xmark"
        case .noShow: "person.crop.circle.badge.xmark"
        case .unknown: "questionmark.circle"
        }
    }

    var tone: DrivyTone {
        switch self {
        case .planned, .unknown: .neutral
        case .inProgress: .accent
        case .completed: .success
        case .toFinish, .cancelled, .noShow: .warning
        }
    }

    /// Full badge, for the head of a lesson screen.
    var badge: DrivyStatusBadge { DrivyStatusBadge(title: title, symbol: symbol, tone: tone) }

    /// What a lesson screen flags: a lesson left without outcome, cancelled, missed,
    /// or whose state the app cannot read.
    var isUnusual: Bool { self == .toFinish || self == .cancelled || self == .noShow || self == .unknown }

    /// One rule for every lesson row (agenda, Aujourd’hui, dossier): a badge only
    /// for the unusual. A planned, running or finished lesson stays quiet.
    var rowBadge: DrivyStatusBadge? { isUnusual ? badge : nil }
}

extension SchoolLesson {
    var drivyState: DrivyLessonState { DrivyLessonState(status: status, start: startsAt, end: endsAt) }
}

/// Report state in the words of the driving school: kept for the instructor,
/// visible to the learner, or an earlier report. Same lock shapes as
/// DrivyPrivacyMark; neutral tone, because keeping a note is not an anomaly.
enum DrivyReportState {
    case privateDraft, shared, historical

    var title: String {
        switch self {
        case .privateDraft: "Pour moi"
        case .shared: "Visible par l’élève"
        case .historical: "Bilan précédent"
        }
    }

    var symbol: String {
        switch self {
        case .privateDraft: "lock.fill"
        case .shared: "lock.open"
        case .historical: "clock.arrow.circlepath"
        }
    }

    var tone: DrivyTone { .neutral }

    var badge: DrivyStatusBadge { DrivyStatusBadge(title: title, symbol: symbol, tone: tone) }
}

/// Lesson row used by the agenda, the dossier lessons and the report lists:
/// time column, name, meta lines, state badge, chevron. Switches to a single
/// column at accessibility text sizes so nothing is truncated.
struct DrivyLessonRow: View {
    let start: String
    var end: String? = nil
    let title: String
    var details: [String] = []
    var badge: DrivyStatusBadge? = nil
    var showsChevron = true
    var isSecondary = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text(end.map { "\(start) – \($0)" } ?? start)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(isSecondary ? DrivyTheme.muted : DrivyTheme.text)
                    summary
                    if let badge { badge }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: DrivySpacing.m) {
                    DrivyTimeColumn(start: start, end: end)
                        .fixedSize(horizontal: true, vertical: false)
                    // Compact width: the badge sits under the summary so the lines
                    // are not cut before « · »; the separator starts on the text column.
                    if sizeClass == .compact {
                        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                            summary
                            if let badge { badge }
                        }
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    } else {
                        summary
                            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                        if let badge { badge }
                    }
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DrivyTheme.muted)
                            .padding(.top, DrivySpacing.xxs)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, DrivySpacing.m)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title)
                .font(isSecondary ? .body : .headline)
                .foregroundStyle(isSecondary ? DrivyTheme.muted : DrivyTheme.text)
            ForEach(Array(details.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Label / value line of a lesson screen (date, time, meeting point, price).
struct DrivyLessonFactRow: View {
    let title: String
    let value: String
    var monospaced = false

    // One label/value anatomy for the whole app.
    var body: some View {
        DrivyKeyValueRow(title: title, value: value, numeric: monospaced)
    }
}

/// Body of a lesson report, identical in the preview and in the published view:
/// the next step leads, then the work done and what to remember.
struct DrivyReportBody: View {
    let nextStep: String
    let workedOn: String
    let observationText: String
    /// Inside a grouped form row: tighter spacing and row-sized titles.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? DrivySpacing.s : DrivySpacing.m) {
            if !nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text("Prochaine étape")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                Text(nextStep)
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            }
            if !workedOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { passage("Travail réalisé", workedOn) }
            if !observationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { passage("À retenir", observationText) }
            if [nextStep, workedOn, observationText].allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Text("Aucun texte ajouté.").foregroundStyle(DrivyTheme.muted)
            }
        }
        .padding(.vertical, compact ? DrivySpacing.xs : 0)
    }

    private func passage(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(title)
                .font(compact ? .headline : .drivySection)
                .foregroundStyle(DrivyTheme.text)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.body)
                .foregroundStyle(DrivyTheme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One competency with its observed level, context and date. Used in reports
/// and in the learning path; there is never a global score.
struct DrivyCompetencyNote: View {
    let label: String
    let level: String
    /// Neutral by default: the accent is reserved for actions.
    var tone: DrivyTone = .neutral
    var context: String? = nil
    var date: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(label)
                .font(.headline)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(level).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            if let context, !context.isEmpty {
                Text(context)
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date {
                Text(date).font(.caption).foregroundStyle(DrivyTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Même lecture compacte dans la leçon et la liste des observations, sans répéter le statut.
struct DrivyObservationSummary: View {
    let observation: SchoolObservation
    var competency: String? = nil
    var detail: String? = nil
    private var status: SchoolObservationStatus? { SchoolLessonHubRules.status(of: observation) }
    private var color: Color {
        switch status { case .positive: DrivyTheme.success; case .attention: DrivyTheme.warning;
        case .toWorkOn: DrivyTheme.danger; case nil: DrivyTheme.muted }
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.s) {
            Image(systemName: status?.symbol ?? (observation.isMarker ? "bookmark" : "text.bubble"))
                .font(.caption.weight(.semibold)).foregroundStyle(color).frame(width: 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(observation.text).font(.subheadline.weight(.medium)).foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                let metadata = [status?.label == observation.text ? nil : status?.label, competency, detail]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !metadata.isEmpty {
                    Text(metadata).font(.caption).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Trois points communs au bilan et à la progression ; zéro point rempli signifie aucune évaluation.
struct DrivyCompetencyMeter: View {
    let level: String
    static func rank(_ level: String) -> Int {
        switch level { case "DISCOVERING": 1; case "GUIDED": 2; case "INDEPENDENT": 3; default: 0 }
    }
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { step in
                Circle().fill(step <= Self.rank(level) ? DrivyTheme.accent : DrivyTheme.border)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bottom bar holding the validation action of a form or sheet, above the
/// keyboard and the home indicator. Same margins and hairline everywhere; its
/// column matches the content above it (a Form by default, pass the page column).
struct DrivyStickyActionBar<Content: View>: View {
    var maxWidth: CGFloat = DrivyLayout.formColumn
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) { content }
            .padding(.horizontal, DrivySpacing.l)
            .padding(.vertical, DrivySpacing.s)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .background(DrivyTheme.surface)
            .overlay(alignment: .top) { Divider().overlay(DrivyTheme.border) }
    }
}

/// Privacy of a lesson item: closed lock = kept for the instructor (« Pour moi »),
/// open lock = visible to the learner. The symbol shape changes, not only its
/// color; the tone stays muted because keeping a note private is not an anomaly.
/// Alone it speaks its state; inside a labelled control, hide it from VoiceOver.
struct DrivyPrivacyMark: View {
    let isPrivate: Bool

    var body: some View {
        Image(systemName: isPrivate ? "lock.fill" : "lock.open")
            .foregroundStyle(DrivyTheme.muted)
            .accessibilityLabel(isPrivate ? "Pour moi" : "Visible par l’élève")
    }
}

/// Short line above a bottom action: why it is disabled, or what failed.
/// Only a failure carries a symbol (symbol, text and color); a plain note is text alone.
struct DrivyActionNote: View {
    let text: String
    var isError = false

    var body: some View {
        Group {
            if isError {
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
            } else {
                Text(text)
            }
        }
        .font(.footnote)
        .foregroundStyle(isError ? DrivyTheme.danger : DrivyTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
