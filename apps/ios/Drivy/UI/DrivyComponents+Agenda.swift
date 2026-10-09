import SwiftUI

// Shared anatomy of the agenda, the training dossier and the lesson report:
// one lesson row, one wording per lesson or report state, one report body.
// Presentation only: states are derived from values the server already returned.

/// Lesson state as shown to people. Same wording everywhere.
enum DrivyLessonState {
    case planned, waiting, inProgress, toFinish, completed, cancelled, noShow, unknown

    init(status: String, start: Date?, end: Date?, actualStart: Date? = nil, now: Date = Date()) {
        switch status {
        case "PLANNED":
            if actualStart != nil { self = end.map { $0 <= now } == true ? .toFinish : .inProgress }
            else if let start, start <= now { self = .waiting }
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
        case .waiting: "En attente"
        case .inProgress: "En cours"
        case .toFinish: "À terminer"
        case .completed: "Terminée"
        case .cancelled: "Annulée"
        case .noShow: "Absence"
        case .unknown: "À vérifier"
        }
    }

    /// What a lesson screen flags: a lesson left without outcome, cancelled, missed,
    /// or whose state the app cannot read.
    var isUnusual: Bool { self == .waiting || self == .toFinish || self == .cancelled || self == .noShow || self == .unknown }

    /// A lesson that will not be driven (cancelled, missed): its row steps back
    /// instead of competing with the lessons still to come.
    var isClosed: Bool { self == .cancelled || self == .noShow }

    /// One rule for every lesson row (agenda, Aujourd’hui, dossier): one word of
    /// plain text, only for the unusual, never a capsule. A planned, running or
    /// finished lesson stays silent. Weight and ink carry the emphasis: a lesson
    /// to finish calls for an action (warning ink); a cancelled or missed one is
    /// a closed fact (muted ink, struck times for a cancellation).
    var rowNote: DrivyRowNote? {
        switch self {
        case .waiting, .toFinish: return DrivyRowNote(text: title, tone: .warning)
        case .cancelled, .noShow, .unknown: return DrivyRowNote(text: title, tone: .neutral)
        case .planned, .inProgress, .completed: return nil
        }
    }
}

/// The one word a row says about its subject (« Annulée », « À terminer », « Partiel »):
/// semibold text in the tone's ink, placed at the head of the detail line. No capsule,
/// no symbol; the word itself is what VoiceOver reads inside the combined row.
struct DrivyRowNote: Equatable {
    let text: String
    var tone: DrivyTone = .neutral

    /// The accent stays reserved for actions: an accent note reads in the main ink.
    var color: Color { tone == .accent ? DrivyTheme.text : tone.foreground }
}

/// A row note on a line of its own, for screens that stack it instead of using a row.
struct DrivyRowNoteText: View {
    let note: DrivyRowNote

    var body: some View {
        Text(note.text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(note.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension SchoolLesson {
    var drivyState: DrivyLessonState { drivyState(now: Date()) }
}

/// What a past lesson holds for its reader: a shared report, a trip that can be replayed.
/// Said in words on the last detail line of a lesson row (« Bilan · Trajet »), never as glyphs.
struct DrivyLessonContents: OptionSet, Sendable, Equatable {
    let rawValue: Int
    static let report = DrivyLessonContents(rawValue: 1 << 0)
    static let trip = DrivyLessonContents(rawValue: 1 << 1)

    /// The line a row shows, in a fixed order; `nil` when the lesson holds neither.
    var label: String? {
        var words: [String] = []
        if contains(.report) { words.append("Bilan") }
        if contains(.trip) { words.append("Trajet") }
        return words.isEmpty ? nil : words.joined(separator: " · ")
    }
}

extension SchoolLesson {
    /// Shared report; reconstructed trip (same criteria as `SchoolTripsWorkspace.isReplayable`).
    /// A report kept « Pour moi » is not marked, even for its author.
    var drivyContents: DrivyLessonContents {
        var contents: DrivyLessonContents = []
        if status == "COMPLETED", currentPublishedRevisionId != nil { contents.insert(.report) }
        if let capture = captureSummary, capture.hasCapture,
           capture.publicationState == SchoolCaptureSession.PublicationState.privateCapture.rawValue,
           let sync = capture.syncState,
           sync == SchoolCaptureSession.SyncState.synced.rawValue || sync == SchoolCaptureSession.SyncState.partial.rawValue {
            contents.insert(.trip)
        }
        return contents
    }
}

/// Lesson row used by the agenda, the dossier lessons and the report lists:
/// time column, name, meta lines, chevron. An unusual state is one word of plain
/// text at the head of the detail line (`state:` for a lesson, `note:` for any
/// other subject), never a capsule. A cancelled or missed lesson steps back: its
/// times and name take the muted ink, and a cancellation strikes its times.
/// Switches to a single column at accessibility text sizes so nothing is truncated.
struct DrivyLessonRow: View {
    let start: String
    var end: String? = nil
    let title: String
    var details: [String] = []
    var state: DrivyLessonState? = nil
    var note: DrivyRowNote? = nil
    /// Last detail line (« Bilan · Trajet »); no line when empty.
    var contents: DrivyLessonContents = []
    var showsChevron = true
    var isSecondary = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var rowNote: DrivyRowNote? { note ?? state?.rowNote }
    private var isClosed: Bool { state?.isClosed ?? false }
    private var strikesTimes: Bool { state == .cancelled }
    private var timeInk: Color { isSecondary || isClosed ? DrivyTheme.muted : DrivyTheme.text }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                    Text(end.map { "\(start) – \($0)" } ?? start)
                        .font(.headline.monospacedDigit())
                        .strikethrough(strikesTimes)
                        .foregroundStyle(timeInk)
                    summary
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: DrivySpacing.m) {
                    timeColumn
                        .fixedSize(horizontal: true, vertical: false)
                    summary
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
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

    /// Same metrics as `DrivyTimeColumn`, with the closed-lesson ink and the struck times.
    private var timeColumn: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(start)
                .font(.headline.monospacedDigit())
                .strikethrough(strikesTimes)
                .foregroundStyle(isClosed ? DrivyTheme.muted : DrivyTheme.text)
            if let end {
                Text(end)
                    .font(.caption.monospacedDigit())
                    .strikethrough(strikesTimes)
                    .foregroundStyle(DrivyTheme.muted)
            }
        }
        .frame(minWidth: 52, alignment: .leading)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title)
                .font(isSecondary ? .body : .headline)
                .foregroundStyle(isSecondary || isClosed ? DrivyTheme.muted : DrivyTheme.text)
            ForEach(Array(detailLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The detail lines, the state word leading the first one (« Annulée · Lausanne »).
    /// The word carries its own weight and ink; the rest of the line stays muted.
    /// What the lesson holds closes the list; VoiceOver reads it with the combined row.
    private var detailLines: [AttributedString] {
        var lines = details
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { AttributedString($0) }
        if let rowNote {
            var word = AttributedString(rowNote.text)
            word.font = Font.subheadline.weight(.semibold)
            word.foregroundColor = rowNote.color
            if lines.isEmpty { lines = [word] }
            else { lines[0] = word + AttributedString(" · ") + lines[0] }
        }
        // Always a line of its own, after the state word and the details.
        if let label = contents.label { lines.append(AttributedString(label)) }
        return lines
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
