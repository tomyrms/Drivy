import SwiftUI

// Shared anatomy of the Cartographie native direction (DESIGN/02-composants.md).
// Screens compose these pieces instead of re-deriving paddings, radii and tones.

/// Semantic tone of a status. A status always pairs a symbol, a text and a color.
enum DrivyTone {
    case neutral, accent, success, warning, danger

    var foreground: Color {
        switch self {
        case .neutral: DrivyTheme.muted
        case .accent: DrivyTheme.accent
        case .success: DrivyTheme.success
        case .warning: DrivyTheme.warning
        case .danger: DrivyTheme.danger
        }
    }

    var background: Color {
        switch self {
        case .neutral: DrivyTheme.surfaceMuted
        case .accent: DrivyTheme.accentSoft
        case .success: DrivyTheme.successSurface
        case .warning: DrivyTheme.warningSurface
        case .danger: DrivyTheme.dangerSurface
        }
    }
}

/// Compact status pill: « En cours », « Partagé », « Profil à compléter ».
/// On one line it keeps its natural width so neighbours compress first; at
/// accessibility text sizes it wraps instead of overflowing, and its capsule
/// becomes a field-radius rectangle so a two-line pill keeps a readable shape.
struct DrivyStatusBadge: View {
    let title: String
    var symbol: String? = nil
    var tone: DrivyTone = .neutral
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let wraps = typeSize.isAccessibilitySize
        HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xxs) {
            if let symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
            Text(title)
                .lineLimit(wraps ? nil : 1)
                .multilineTextAlignment(.leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, DrivySpacing.xs)
        .padding(.vertical, DrivySpacing.xxs)
        .background(tone.background, in: wraps
            ? AnyShape(RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
            : AnyShape(Capsule()))
        .fixedSize(horizontal: !wraps, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Small live-state line with a dot, as on the session card (« GPS actif »).
/// The dot scales with the caption text so it stays proportionate.
struct DrivyStatusDot: View {
    let title: String
    var tone: DrivyTone = .neutral
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 6

    init(title: String, tone: DrivyTone = .neutral) {
        self.title = title
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: DrivySpacing.xs) {
            Circle().fill(tone.foreground).frame(width: dotSize, height: dotSize).accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tone.foreground)
        .accessibilityElement(children: .combine)
    }
}

/// Section title with an optional trailing text action (« Ensuite · Tout voir »).
/// At accessibility text sizes the action moves under the title. The action's
/// whole 44 pt frame is tappable, not only its glyphs.
struct DrivySectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.xs))
        layout {
            Text(title)
                .font(.drivySection)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !stacked { Spacer(minLength: 0) }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(DrivyTheme.accent)
            }
        }
    }
}

/// Initials in a neutral circle. Never a photo placeholder or a fake logo.
/// The circle keeps its size; very large text sizes shrink the initials to fit.
struct DrivyAvatar: View {
    let name: String
    var size: CGFloat = 44
    var isSelected = false

    var body: some View {
        Text(DrivyAvatar.initials(name))
            .font(size > 52 ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(DrivySpacing.xxs)
            .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.text)
            .frame(width: size, height: size)
            .background(isSelected ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Circle())
            .accessibilityHidden(true)
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).prefix(2)
        let letters = parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return letters.isEmpty ? "?" : letters
    }
}

/// Navigation row used for settings, school actions and dossier sections:
/// leading symbol, title, optional detail, chevron. Full-width hit area.
/// At accessibility text sizes the badge moves under the text and the symbol
/// aligns to the first line, so nothing is truncated or pushed off screen.
/// VoiceOver reads one element: title, detail, badge, as a button.
struct DrivyNavigationRow: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var badge: DrivyStatusBadge? = nil
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var symbolWidth: CGFloat = 28

    init(
        title: String,
        detail: String? = nil,
        symbol: String? = nil,
        badge: DrivyStatusBadge? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.badge = badge
        self.action = action
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        Button(action: action) {
            HStack(alignment: stacked ? .firstTextBaseline : .center, spacing: DrivySpacing.m) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: symbolWidth)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                    if stacked, let badge { badge.padding(.top, DrivySpacing.xxs) }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DrivySpacing.xs)
                if !stacked, let badge { badge }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DrivySpacing.m)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DrivyRowButtonStyle())
    }
}

/// Rows highlight while pressed without drawing a card around every item.
struct DrivyRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
                    .fill(DrivyTheme.surfaceMuted)
                    .padding(.horizontal, -DrivySpacing.xs)
                    .opacity(configuration.isPressed ? 1 : 0)
            }
    }
}

/// A list of rows separated by hairlines, under an optional section header.
struct DrivyRowGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                DrivySectionHeader(title: title).padding(.bottom, DrivySpacing.xxs)
            }
            Group(subviews: content) { rows in
                let lastID = rows.last?.id
                ForEach(rows) { row in
                    row
                    if row.id != lastID { Divider().overlay(DrivyTheme.border) }
                }
            }
        }
    }
}

/// Start/end time column for lesson rows (tabular, aligned).
struct DrivyTimeColumn: View {
    let start: String
    let end: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(start).font(.headline.monospacedDigit()).foregroundStyle(DrivyTheme.text)
            if let end {
                Text(end).font(.caption.monospacedDigit()).foregroundStyle(DrivyTheme.muted)
            }
        }
        .frame(minWidth: 52, alignment: .leading)
    }
}

/// Empty state that always proposes one clear next action when one exists.
/// Use inside a section; a whole empty screen keeps ContentUnavailableView.
/// At accessibility text sizes the symbol sits above the text.
struct DrivyEmptyState: View {
    let title: String
    let message: String
    var symbol: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: DrivySpacing.m))
        layout {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(DrivyTheme.muted)
                .frame(minWidth: 32, alignment: stacked ? .leading : .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DrivyTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DrivySpacing.s)
        .accessibilityElement(children: .contain)
    }
}

/// Elevated card used for the one dominant decision of a screen
/// (next session, current lesson). Hairline border, no decorative shadow.
/// Corners are concentric: card radius = inner content radius + padding.
struct DrivyCard<Content: View>: View {
    var padding: CGFloat = DrivySpacing.m
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + padding))
    }
}

/// Shared surface of DrivyCard and DrivyPanel: canvas fill and hairline.
/// Increase Contrast swaps the faint hairline for the control border so the
/// block edge stays visible on a white page.
struct DrivyGroupedSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let increased = contrast == .increased
        return content
            .background(DrivyTheme.canvas, in: shape)
            .overlay {
                shape.strokeBorder(increased ? DrivyTheme.controlBorder : DrivyTheme.border,
                                   lineWidth: increased ? 1 : 0.5)
            }
    }
}

/// Screen header shown under the navigation bar: context line (school) and date.
struct DrivyContextHeader: View {
    let context: String?
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            if let context, !context.isEmpty {
                Text(context).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.muted)
            }
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Floating control over the map: Liquid Glass is reserved for chrome on top
    /// of the map (tokens materialPolicy), never for reading surfaces.
    func drivyMapControl<S: Shape>(in shape: S) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }
}

extension String {
    /// « lundi 21 septembre » → « Lundi 21 septembre », without title-casing every word.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Schematic route line from the mockups: a stepped path with start and end
/// dots. Illustrative only, never a recorded position. Hidden from VoiceOver.
struct DrivyRouteGlyph: View {
    var lineWidth: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let points = [
                CGPoint(x: w * 0.06, y: h * 0.86),
                CGPoint(x: w * 0.06, y: h * 0.62),
                CGPoint(x: w * 0.46, y: h * 0.62),
                CGPoint(x: w * 0.46, y: h * 0.18),
                CGPoint(x: w * 0.94, y: h * 0.18),
            ]
            var path = Path()
            path.addLines(points)
            let dotRadius = lineWidth + 2
            context.stroke(path, with: .color(DrivyTheme.routeHalo), style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(DrivyTheme.route), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            for point in [points[0], points[points.count - 1]] {
                let dot = Path(ellipseIn: CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                context.fill(dot, with: .color(DrivyTheme.routeHalo))
                context.stroke(dot, with: .color(DrivyTheme.route), lineWidth: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Inline feedback next to where the action happened (success, warning, error).
/// Symbol + text + tone, never color alone.
struct DrivyInlineMessage: View {
    let text: String
    var tone: DrivyTone = .success

    private var symbol: String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .accent, .neutral: "info.circle.fill"
        }
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(tone.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(DrivySpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.background, in: RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// The single selection pattern of the app: a card that fills with the soft
/// accent and gains an accent border when selected, with press feedback.
/// Pair it with a trailing DrivySelectionMark so selection never relies on
/// color alone; VoiceOver hears the Selected trait from the style itself.
struct DrivySelectionCardStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
        let idleBorder = contrast == .increased ? DrivyTheme.controlBorder : DrivyTheme.border
        return configuration.label
            .padding(DrivySpacing.m)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(isSelected ? DrivyTheme.accentSoft : DrivyTheme.canvas, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? DrivyTheme.accent : idleBorder,
                                   lineWidth: isSelected ? 1.5 : (contrast == .increased ? 1 : 0.5))
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
            .animation(DrivyMotion.feedback(reduceMotion), value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Trailing selection mark shared by every selection card.
struct DrivySelectionMark: View {
    let isSelected: Bool
    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.controlBorder)
            .accessibilityHidden(true)
    }
}

/// Retry action inside error notices: outlined in the danger tone, 44 pt.
struct DrivyRetryButton: View {
    var title = "Réessayer"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, DrivySpacing.s)
                .frame(minHeight: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
                        .strokeBorder(DrivyTheme.danger, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(DrivyTheme.danger)
    }
}

/// Label and value read together: « Permis · B », « Durée · 1 h 30 ».
/// Side by side at regular text sizes, stacked at accessibility sizes; the
/// value wraps and is never truncated. Set `numeric` for times, prices and
/// counts (tabular digits). VoiceOver reads « label, value » as one element.
struct DrivyKeyValueRow: View {
    let title: String
    let value: String
    var symbol: String? = nil
    var numeric = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DrivySpacing.m))
        layout {
            Group {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .font(.subheadline)
            .foregroundStyle(DrivyTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            if !stacked { Spacer(minLength: DrivySpacing.xs) }
            Text(value)
                .font(numeric ? Font.body.monospacedDigit() : Font.body)
                .foregroundStyle(DrivyTheme.text)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DrivySpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// Named loading state: a spinner never stands alone, the text says which
/// operation is running (« Chargement de l’agenda… »). Inline in a section;
/// a full-screen wait keeps a centered ProgressView with the same text.
struct DrivyLoadingState: View {
    let title: String

    var body: some View {
        HStack(spacing: DrivySpacing.s) {
            ProgressView()
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

extension View {
    /// Content column of every reading page: page margins (wider on regular
    /// width), readable width, centered on iPad.
    func drivyPageContent(maxWidth: CGFloat = 720) -> some View {
        modifier(DrivyPageContent(maxWidth: maxWidth))
    }
}

private struct DrivyPageContent: ViewModifier {
    let maxWidth: CGFloat
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DrivySpacing.page(sizeClass))
            .padding(.vertical, DrivySpacing.m)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}
