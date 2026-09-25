import SwiftUI

// Shared anatomy of the journey screens (trajet en cours, fin de trajet, replay)
// for the personal journey and the school GPS:
// - an opaque top bar (leave, elapsed time readable at a glance, real GPS state, stop);
// - the map, or an honest placeholder when no position exists;
// - an opaque bottom bar holding the single dominant gesture (Signaler, Lecture);
// - Liquid Glass only for the few commands floating on the map.

/// State line of a map screen: symbol + text + tone, never color alone.
struct DrivyMapStatus: Equatable {
    let title: String
    let symbol: String
    var tone: DrivyTone = .neutral
}

extension GPSStatus {
    /// Same vocabulary as the school GPS: « GPS actif », « En attente de position »…
    /// A refusal or an interruption is a warning, never a red alert.
    var mapStatus: DrivyMapStatus {
        switch self {
        case .inactive: DrivyMapStatus(title: label, symbol: "location.slash")
        case .requestingPermission: DrivyMapStatus(title: label, symbol: "location")
        case .waitingForPosition: DrivyMapStatus(title: label, symbol: "location")
        case .recording: DrivyMapStatus(title: label, symbol: "location.fill", tone: .accent)
        case .denied: DrivyMapStatus(title: label, symbol: "location.slash", tone: .warning)
        case .interrupted: DrivyMapStatus(title: label, symbol: "exclamationmark.triangle", tone: .warning)
        }
    }
}

enum DrivySeanceText {
    /// « 1 observation », « 3 observations ».
    static func observations(_ count: Int) -> String {
        "\(count) observation\(count == 1 ? "" : "s")"
    }

    /// Spoken and matched label of the private observations entry (E23): « Observations privées (3) ».
    static func privateObservations(_ count: Int) -> String {
        "Observations privées (\(count))"
    }

    /// Human duration for summaries: « moins d’une minute », « 42 min », « 1 h 05 ».
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 1 { return "moins d’une minute" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }
}

extension DrivingSession {
    /// Length of the recorded timeline, never negative, at least one second so a
    /// timeline can always be drawn. An open session is measured until `now`.
    func recordedDuration(now: Date = Date()) -> TimeInterval {
        let end: Date
        if state == .active {
            end = now
        } else {
            end = endedAt ?? points.last?.timestamp ?? observations.last?.observedAt ?? startedAt
        }
        return max(1, end.timeIntervalSince(startedAt))
    }

    /// Title used in lists and headers when the journey has no explicit title.
    var displayTitle: String {
        if let title { return title }
        let day = startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CH")))
        return "Trajet du \(day)"
    }
}

/// What a journey contains, for the end summary, the home card and the history rows.
/// Counts only: no score, no grade, no driving quality derived from GPS.
struct JourneyStats: Equatable, Sendable {
    let duration: TimeInterval
    let observationCount: Int
    let locatedCount: Int
    let pointCount: Int
    let hasSummary: Bool
    private let counts: [ObservationStatus: Int]

    init(session: DrivingSession, now: Date = Date()) {
        duration = session.recordedDuration(now: now)
        observationCount = session.observations.count
        pointCount = session.points.count
        let pointIDs = Set(session.points.map(\.id))
        locatedCount = session.observations.filter { observation in
            guard let anchor = observation.anchorPointID else { return false }
            return pointIDs.contains(anchor)
        }.count
        hasSummary = !session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        counts = Dictionary(grouping: session.observations, by: \.status).mapValues(\.count)
    }

    func count(_ status: ObservationStatus) -> Int { counts[status] ?? 0 }
    var unlocatedCount: Int { observationCount - locatedCount }
}

extension View {
    /// Opaque panel posed on the map (bars, dock, banners). The shadow only expresses
    /// the superposition; outside the map (iPad sidebar, large text) a hairline replaces it.
    func drivyMapPanel(floating: Bool = true) -> some View {
        modifier(DrivyMapPanelModifier(floating: floating))
    }

    /// Floating command on a map: Liquid Glass tinted with the surface so the symbol
    /// stays legible over water, parks or satellite imagery. Reduce Transparency
    /// makes the system glass opaque.
    func drivyLegibleMapControl<S: Shape>(in shape: S) -> some View {
        glassEffect(.regular.tint(DrivyTheme.surface.opacity(0.78)).interactive(), in: shape)
    }
}

private struct DrivyMapPanelModifier: ViewModifier {
    let floating: Bool

    func body(content: Content) -> some View {
        content
            .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
            .overlay {
                if !floating {
                    RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous)
                        .strokeBorder(DrivyTheme.border, lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(floating ? 0.12 : 0), radius: 18, y: 4)
    }
}

/// Leading command of a map bar: close (the journey continues) or back.
struct DrivyMapHeaderAction {
    let symbol: String
    let label: String
    var hint: String? = nil
    var isDisabled = false
    let action: () -> Void

    static func close(label: String, hint: String? = nil, isDisabled: Bool = false, action: @escaping () -> Void) -> Self {
        DrivyMapHeaderAction(symbol: "xmark", label: label, hint: hint, isDisabled: isDisabled, action: action)
    }

    static func back(label: String, action: @escaping () -> Void) -> Self {
        DrivyMapHeaderAction(symbol: "chevron.left", label: label, action: action)
    }
}

/// Round 48 pt leading button shared by every map bar.
private struct DrivyMapLeadingButton: View {
    let action: DrivyMapHeaderAction

    var body: some View {
        Button(action: action.action) {
            Image(systemName: action.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(action.isDisabled ? DrivyTheme.disabledText : DrivyTheme.text)
                .frame(width: 48, height: 48)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(action.isDisabled)
        .accessibilityLabel(action.label)
        .accessibilityHint(action.hint ?? "")
    }
}

/// Reading header of a map screen (replay): leading command, title, state line,
/// then trailing content (bilan, options). Stacks in accessibility text sizes.
struct DrivyMapHeader<Trailing: View>: View {
    private let title: String
    private let status: DrivyMapStatus
    private let leading: DrivyMapHeaderAction
    private let floating: Bool
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, status: DrivyMapStatus, leading: DrivyMapHeaderAction, floating: Bool = true,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.status = status
        self.leading = leading
        self.floating = floating
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    HStack(spacing: DrivySpacing.xs) {
                        DrivyMapLeadingButton(action: leading)
                        Spacer(minLength: 0)
                        trailing
                    }
                    titleBlock
                }
            } else {
                HStack(alignment: .center, spacing: DrivySpacing.s) {
                    DrivyMapLeadingButton(action: leading)
                    titleBlock
                    trailing
                }
            }
        }
        .padding(.vertical, DrivySpacing.xs)
        .padding(.leading, DrivySpacing.xs)
        .padding(.trailing, DrivySpacing.s)
        .foregroundStyle(DrivyTheme.text)
        .drivyMapPanel(floating: floating)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            DrivyMapStatusLabel(status: status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DrivyMapHeader where Trailing == EmptyView {
    init(title: String, status: DrivyMapStatus, leading: DrivyMapHeaderAction, floating: Bool = true) {
        self.init(title: title, status: status, leading: leading, floating: floating) { EmptyView() }
    }
}

/// Top bar of a journey being recorded (personal or school). The elapsed time is
/// the largest text so it reads in one glance from the driving position; the GPS
/// state sits right under it; the stop command stays top right, far from Signaler.
struct DrivyLiveTopBar<Trailing: View>: View {
    private let context: String?
    private let elapsed: String?
    private let elapsedLabel: String
    private let status: DrivyMapStatus
    private let leading: DrivyMapHeaderAction
    private let floating: Bool
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(context: String? = nil, elapsed: String?, elapsedLabel: String = "Durée du trajet",
         status: DrivyMapStatus, leading: DrivyMapHeaderAction, floating: Bool = true,
         @ViewBuilder trailing: () -> Trailing) {
        self.context = context
        self.elapsed = elapsed
        self.elapsedLabel = elapsedLabel
        self.status = status
        self.leading = leading
        self.floating = floating
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    HStack(spacing: DrivySpacing.xs) {
                        DrivyMapLeadingButton(action: leading)
                        Spacer(minLength: 0)
                        trailing
                    }
                    information
                }
            } else {
                HStack(alignment: .center, spacing: DrivySpacing.s) {
                    DrivyMapLeadingButton(action: leading)
                    information
                    trailing
                }
            }
        }
        .padding(.vertical, DrivySpacing.xs)
        .padding(.leading, DrivySpacing.xs)
        .padding(.trailing, DrivySpacing.xs)
        .foregroundStyle(DrivyTheme.text)
        .drivyMapPanel(floating: floating)
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let context {
                Text(context)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let elapsed {
                Text(elapsed)
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(DrivyTheme.text)
                    .lineLimit(1)
                    .accessibilityLabel(elapsedLabel)
                    .accessibilityValue(elapsed)
            }
            DrivyMapStatusLabel(status: status, font: .subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension DrivyLiveTopBar where Trailing == EmptyView {
    init(context: String? = nil, elapsed: String?, elapsedLabel: String = "Durée du trajet",
         status: DrivyMapStatus, leading: DrivyMapHeaderAction, floating: Bool = true) {
        self.init(context: context, elapsed: elapsed, elapsedLabel: elapsedLabel, status: status,
                  leading: leading, floating: floating) { EmptyView() }
    }
}

struct DrivyMapStatusLabel: View {
    let status: DrivyMapStatus
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(font)
            .foregroundStyle(status.tone.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

/// Elapsed time of a journey: tabular digits, readable at a glance while moving.
struct DrivyElapsedTime: View {
    let text: String
    let accessibilityTitle: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(DrivyTheme.text)
            .lineLimit(1)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(text)
    }
}

/// Critical stop command of a map bar: 52 pt capsule with a word, danger tone,
/// always confirmed by the caller. Icon only in accessibility sizes where the bar stacks.
struct DrivyMapStopButton: View {
    let label: String
    var title = "Arrêter"
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xs) {
                Image(systemName: "stop.fill").accessibilityHidden(true)
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? DrivyTheme.danger : DrivyTheme.disabledText)
            .padding(.horizontal, DrivySpacing.m)
            .frame(minWidth: 52, minHeight: 52)
            .background(isEnabled ? DrivyTheme.dangerSurface : DrivyTheme.disabledSurface, in: Capsule())
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(DrivyTileButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// The dominant gesture while driving: one large capsule, 64 pt tall, always outside
/// any scrolling container. It freezes the instant; nothing is saved before the
/// status is chosen in the reporting bubble.
struct DrivyReportButton: View {
    var title = "Signaler"
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xs) {
                Image(systemName: "plus.bubble.fill").accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }
            .font(.title3.weight(.bold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, DrivySpacing.m)
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(isEnabled ? DrivyTheme.onAccent : DrivyTheme.disabledText)
            .background(isEnabled ? DrivyTheme.accent : DrivyTheme.disabledSurface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(DrivyTileButtonStyle())
        .disabled(!isEnabled)
    }
}

/// Opaque round or capsule command of the bottom bar (observations, recentrer).
struct DrivyBarButton: View {
    let symbol: String
    var text: String? = nil
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xxs) {
                Image(systemName: symbol).accessibilityHidden(true)
                if let text { Text(text).monospacedDigit() }
            }
            .font(.headline)
            .foregroundStyle(isActive ? DrivyTheme.accent : DrivyTheme.text)
            .padding(.horizontal, text == nil ? 0 : DrivySpacing.s)
            .frame(minWidth: 56, minHeight: 56)
            .background(isActive ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Capsule())
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(DrivyTileButtonStyle())
    }
}

/// Bottom dock posed on the map: one opaque panel. The dominant action goes last.
struct DrivyMapDock<Content: View>: View {
    var floating = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) { content }
            .padding(DrivySpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(DrivyTheme.text)
            .drivyMapPanel(floating: floating)
    }
}

/// Short confirmation after a durable write, with an immediate « Annuler » when the
/// storage can really erase the observation. Shown only after the write succeeded.
struct DrivyUndoBanner: View {
    let title: String
    let detail: String
    let symbol: String
    var tone: DrivyTone = .success
    var undoTitle = "Annuler"
    var isUndoing = false
    let undo: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DrivySpacing.s))
        layout {
            HStack(alignment: .center, spacing: DrivySpacing.s) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tone.foreground)
                    .frame(width: 36, height: 36)
                    .background(tone.background, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                    Text(detail).font(.caption).foregroundStyle(DrivyTheme.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if let undo {
                Button(action: undo) {
                    HStack(spacing: DrivySpacing.xxs) {
                        if isUndoing { ProgressView().accessibilityHidden(true) }
                        Text(undoTitle)
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                    .padding(.horizontal, DrivySpacing.m)
                    .frame(minHeight: 48)
                    .background(DrivyTheme.accentSoft, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(DrivyTileButtonStyle())
                .disabled(isUndoing)
                .accessibilityLabel("Annuler cette observation")
                .accessibilityIdentifier("undo-observation")
            }
        }
        .padding(.vertical, DrivySpacing.s)
        .padding(.horizontal, DrivySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .drivyMapPanel()
    }
}

/// Follow / show-whole-route commands floating on the map. Tinted Liquid Glass so
/// they stay legible over any background; grouped so the two circles blend.
struct DrivyMapControls: View {
    @Binding var followsPosition: Bool
    var followLabel = "Suivre la dernière position enregistrée"
    var canFollow = true
    var axis: Axis = .vertical
    let showWholeRoute: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: DrivySpacing.xs) {
            let layout = axis == .vertical
                ? AnyLayout(VStackLayout(spacing: DrivySpacing.xs))
                : AnyLayout(HStackLayout(spacing: DrivySpacing.xs))
            layout {
                Button { followsPosition.toggle() } label: {
                    Image(systemName: followsPosition ? "location.fill" : "location")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(followsPosition ? DrivyTheme.accent : canFollow ? DrivyTheme.text : DrivyTheme.disabledText)
                        .frame(width: 48, height: 48)
                        .drivyLegibleMapControl(in: Circle())
                }
                .disabled(!canFollow && !followsPosition)
                .accessibilityLabel(followsPosition ? "Arrêter le suivi de position" : followLabel)
                .accessibilityAddTraits(followsPosition ? [.isSelected] : [])
                Button(action: showWholeRoute) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DrivyTheme.text)
                        .frame(width: 48, height: 48)
                        .drivyLegibleMapControl(in: Circle())
                }
                .accessibilityLabel("Voir tout le trajet")
            }
        }
        .buttonStyle(.plain)
    }
}

/// Replaces the map when there is no position to show: never a broken map,
/// never an invented location, never a whole-country overview.
struct DrivyMapPlaceholder: View {
    let title: String
    let message: String
    var symbol = "location.slash"

    var body: some View {
        VStack(spacing: DrivySpacing.s) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(DrivyTheme.muted)
                .frame(width: 72, height: 72)
                .background(DrivyTheme.surfaceMuted, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.drivyTitle)
                .foregroundStyle(DrivyTheme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.body)
                .foregroundStyle(DrivyTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420)
        .padding(DrivySpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.canvas)
        .accessibilityElement(children: .combine)
    }
}

/// Secondary command with a destructive meaning (« Arrêter le GPS »): same
/// geometry as the primary and secondary styles, danger tone.
struct DrivyDangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, DrivySpacing.m)
            .foregroundStyle(isEnabled ? DrivyTheme.danger : DrivyTheme.disabledText)
            .background(
                isEnabled ? DrivyTheme.dangerSurface : DrivyTheme.disabledSurface,
                in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Replay timeline

/// One observation on a replay timeline: status symbol and tone, spoken label.
struct DrivyTimelineMark: Identifiable, Equatable {
    let id: UUID
    let offset: TimeInterval
    let symbol: String
    let tone: DrivyTone
    let label: String
}

/// Replay scrubber: follows recorded time (not distance), draws interruptions as
/// dotted stretches without position, and puts each observation on its own
/// tappable pin above the track. VoiceOver reads one adjustable element.
struct DrivyReplayScrubber: View {
    @Binding var offset: TimeInterval
    let duration: TimeInterval
    let marks: [DrivyTimelineMark]
    let gaps: [ClosedRange<TimeInterval>]
    let selectedMarkID: UUID?
    let valueDescription: String
    var onScrubStart: () -> Void = {}
    let onSelectMark: (UUID) -> Void
    @State private var isDragging = false

    private let inset: CGFloat = 14
    private let pinArea: CGFloat = 34
    private let trackArea: CGFloat = 36

    var body: some View {
        VStack(spacing: DrivySpacing.xxs) {
            GeometryReader { geometry in
                let usable = max(1, geometry.size.width - inset * 2)
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        ForEach(marks) { mark in
                            pin(mark)
                                .position(x: inset + CGFloat(progress(mark.offset)) * usable, y: pinArea / 2)
                        }
                    }
                    .frame(width: geometry.size.width, height: pinArea)
                    ZStack(alignment: .topLeading) {
                        track(usable: usable)
                            .frame(width: geometry.size.width, height: trackArea)
                        thumb
                            .position(x: inset + CGFloat(progress(offset)) * usable, y: trackArea / 2)
                            .allowsHitTesting(false)
                    }
                    .frame(width: geometry.size.width, height: trackArea)
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(usable: usable))
                }
            }
            .frame(height: pinArea + trackArea)
            HStack(alignment: .firstTextBaseline) {
                Text(Self.clock(offset))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DrivyTheme.text)
                Spacer(minLength: DrivySpacing.xs)
                Text(Self.clock(duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(DrivyTheme.muted)
            }
            .padding(.horizontal, DrivySpacing.xxs)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Instant du trajet")
        .accessibilityValue(valueDescription)
        .accessibilityAdjustableAction { direction in
            let step = max(5, duration / 20)
            switch direction {
            case .increment: offset = min(duration, offset + step)
            case .decrement: offset = max(0, offset - step)
            @unknown default: break
            }
        }
    }

    private func progress(_ value: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, value / duration))
    }

    private func track(usable: CGFloat) -> some View {
        let played = progress(offset)
        let gapRanges = gaps.map { (progress($0.lowerBound), progress($0.upperBound)) }
        let ticks = marks.map { (progress($0.offset), $0.tone.foreground) }
        let leading = inset
        return Canvas { context, size in
            let y = size.height / 2
            func x(_ value: Double) -> CGFloat { leading + CGFloat(value) * usable }
            // Solid pieces between gaps, dotted pieces inside gaps.
            var pieces: [(Double, Double, Bool)] = []
            var cursor = 0.0
            for (low, high) in gapRanges.sorted(by: { $0.0 < $1.0 }) where high > cursor {
                let start = max(low, cursor)
                if start > cursor { pieces.append((cursor, start, false)) }
                pieces.append((start, high, true))
                cursor = high
            }
            if cursor < 1 { pieces.append((cursor, 1, false)) }
            for (low, high, isGap) in pieces where high > low {
                for (from, to, isPlayed) in [(low, min(high, played), true), (max(low, played), high, false)] where to > from {
                    var path = Path()
                    path.move(to: CGPoint(x: x(from), y: y))
                    path.addLine(to: CGPoint(x: x(to), y: y))
                    let style = isGap
                        ? StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 5])
                        : StrokeStyle(lineWidth: 6, lineCap: .round)
                    let color = isPlayed ? DrivyTheme.accent : (isGap ? DrivyTheme.muted : DrivyTheme.controlBorder.opacity(0.45))
                    context.stroke(path, with: .color(color), style: style)
                }
            }
            // Thin ticks under each pin tie the observation to its instant.
            for (position, color) in ticks {
                let px = x(position)
                let tick = Path(roundedRect: CGRect(x: px - 1, y: 0, width: 2, height: max(0, y - 4)), cornerRadius: 1)
                context.fill(tick, with: .color(color.opacity(0.6)))
            }
        }
    }

    private func pin(_ mark: DrivyTimelineMark) -> some View {
        let selected = mark.id == selectedMarkID
        return Button { onSelectMark(mark.id) } label: {
            Image(systemName: mark.symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(selected ? DrivyTheme.onAccent : mark.tone.foreground)
                .frame(width: selected ? 28 : 22, height: selected ? 28 : 22)
                .background(selected ? DrivyTheme.accent : mark.tone.background, in: Circle())
                .overlay(Circle().strokeBorder(selected ? DrivyTheme.accent : mark.tone.foreground, lineWidth: 1.5))
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .frame(width: 44, height: pinArea)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private var thumb: some View {
        Circle()
            .fill(DrivyTheme.surface)
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(DrivyTheme.accent, lineWidth: 4))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }

    private func scrubGesture(usable: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onScrubStart()
                }
                let fraction = min(1, max(0, (value.location.x - inset) / usable))
                offset = Double(fraction) * duration
            }
            .onEnded { _ in isDragging = false }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return value >= 3_600
            ? String(format: "%d:%02d:%02d", value / 3_600, (value % 3_600) / 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }
}

/// Transport row of a replay: speed, previous observation, play/pause, next
/// observation, list. Every button keeps a visible 48 pt shape, even disabled.
struct DrivyReplayTransport: View {
    let isPlaying: Bool
    let speed: Int
    let canGoBack: Bool
    let canGoForward: Bool
    let togglePlay: () -> Void
    let cycleSpeed: () -> Void
    let previous: () -> Void
    let next: () -> Void
    var openList: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DrivySpacing.xs) {
            Button(action: cycleSpeed) {
                Text("×\(speed)")
                    .font(.headline.monospacedDigit())
                    .frame(width: 52, height: 48)
                    .background(DrivyTheme.surfaceMuted, in: Capsule())
                    .contentShape(Capsule())
            }
            .accessibilityLabel("Vitesse de lecture")
            .accessibilityValue("\(speed) fois")
            .accessibilityHint("Change la vitesse : une, deux ou quatre fois")
            .accessibilityIdentifier("replay-speed")
            Spacer(minLength: 0)
            roundButton("backward.end.fill", label: "Observation précédente", isEnabled: canGoBack, action: previous)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityIdentifier("replay-previous")
            Button(action: togglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(DrivyTheme.onAccent)
                    .frame(width: 64, height: 64)
                    .background(DrivyTheme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel(isPlaying ? "Mettre le replay en pause" : "Lire le replay")
            .accessibilityIdentifier("replay-play")
            .keyboardShortcut(.space, modifiers: [])
            roundButton("forward.end.fill", label: "Observation suivante", isEnabled: canGoForward, action: next)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityIdentifier("replay-next")
            Spacer(minLength: 0)
            if let openList {
                Button(action: openList) {
                    Image(systemName: "list.bullet")
                        .font(.headline)
                        .frame(width: 52, height: 48)
                        .background(DrivyTheme.surfaceMuted, in: Capsule())
                        .contentShape(Capsule())
                }
                .accessibilityLabel("Toutes les observations")
                .accessibilityIdentifier("replay-list")
            } else {
                Spacer().frame(width: 52, height: 48)
            }
        }
        .buttonStyle(DrivyTileButtonStyle())
        .foregroundStyle(DrivyTheme.text)
    }

    private func roundButton(_ symbol: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(isEnabled ? DrivyTheme.text : DrivyTheme.disabledText)
                .frame(width: 52, height: 52)
                .background(isEnabled ? DrivyTheme.surfaceMuted : DrivyTheme.disabledSurface, in: Circle())
                .overlay { if !isEnabled { Circle().strokeBorder(DrivyTheme.border, lineWidth: 1) } }
                .contentShape(Circle())
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// Map screen gutters, shared by the personal journey, the replay and the school GPS.
enum DrivyMapLayout {
    /// Width from which the controls move into a sidebar next to the map (iPad, Split View).
    static let sidebarBreakpoint: CGFloat = 760
    static let sidebarWidth: CGFloat = 380
    /// Height of the inline map in accessibility text sizes.
    static let accessibleMapHeight: CGFloat = 230
    /// Readable column in accessibility text sizes.
    static let accessibleMaxWidth: CGFloat = 680
    /// Height of a non-interactive route preview (home, end of journey).
    static let previewHeight: CGFloat = 176
}
