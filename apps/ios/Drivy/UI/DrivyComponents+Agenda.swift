import SwiftUI

// Shared anatomy of the agenda, the training dossier and the lesson report:
// one lesson row, one wording per lesson or report state, one report body.
// Presentation only: states are derived from values the server already returned.

/// Lesson state as shown to people. Same title, symbol and tone everywhere.
enum DrivyLessonState {
    case planned, inProgress, completed, cancelled, noShow, unknown

    init(status: String, start: Date?, end: Date?, now: Date = Date()) {
        switch status {
        case "PLANNED":
            if let start, let end, start <= now, now < end { self = .inProgress } else { self = .planned }
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
        case .cancelled, .noShow: .warning
        }
    }

    /// Full badge, for the head of a lesson screen.
    var badge: DrivyStatusBadge { DrivyStatusBadge(title: title, symbol: symbol, tone: tone) }

    /// Rows stay quiet for the normal case: a planned lesson carries no badge.
    var rowBadge: DrivyStatusBadge? { self == .planned ? nil : badge }
}

extension SchoolLesson {
    var drivyState: DrivyLessonState { DrivyLessonState(status: status, start: startsAt, end: endsAt) }
}

/// Report state: private draft, shared with the learner, or kept in history.
/// Private always carries the lock; shared always names the learner as reader.
enum DrivyReportState {
    case privateDraft, shared, historical

    var title: String {
        switch self {
        case .privateDraft: "Brouillon privé"
        case .shared: "Partagé"
        case .historical: "Version historique"
        }
    }

    var symbol: String {
        switch self {
        case .privateDraft: "lock.fill"
        case .shared: "person.2.fill"
        case .historical: "clock.arrow.circlepath"
        }
    }

    var tone: DrivyTone {
        switch self {
        case .privateDraft, .historical: .neutral
        case .shared: .success
        }
    }

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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text(end.map { "\(start) – \($0)" } ?? start)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(DrivyTheme.text)
                    summary
                    if let badge { badge }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: DrivySpacing.m) {
                    DrivyTimeColumn(start: start, end: end)
                        .fixedSize(horizontal: true, vertical: false)
                    summary
                    if let badge { badge }
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
                .font(.headline)
                .foregroundStyle(DrivyTheme.text)
            ForEach(Array(details.enumerated()), id: \.offset) { _, line in
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
        VStack(alignment: .leading, spacing: compact ? DrivySpacing.m : DrivySpacing.l) {
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Label("Prochaine étape", systemImage: "arrow.forward.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                Text(nextStep)
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DrivySpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.accentSoft, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            .accessibilityElement(children: .combine)
            passage("Travail réalisé", workedOn)
            passage("À retenir", observationText)
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
    var tone: DrivyTone = .accent
    var context: String? = nil
    var date: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(label)
                .font(.headline)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            DrivyStatusBadge(title: level, tone: tone)
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

/// Bottom bar holding the validation action of a form or sheet, above the
/// keyboard and the home indicator. Same margins and hairline everywhere.
struct DrivyStickyActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) { content }
            .padding(.horizontal, DrivySpacing.l)
            .padding(.vertical, DrivySpacing.s)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .background(DrivyTheme.surface)
            .overlay(alignment: .top) { Divider().overlay(DrivyTheme.border) }
    }
}

/// Short line above a bottom action: why it is disabled, or what failed.
struct DrivyActionNote: View {
    let text: String
    var isError = false

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(isError ? DrivyTheme.danger : DrivyTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
