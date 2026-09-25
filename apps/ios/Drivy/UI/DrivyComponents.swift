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
struct DrivyStatusBadge: View {
    let title: String
    var symbol: String? = nil
    var tone: DrivyTone = .neutral

    var body: some View {
        HStack(spacing: DrivySpacing.xxs) {
            if let symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
            Text(title).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, DrivySpacing.xs)
        .padding(.vertical, DrivySpacing.xxs)
        .background(tone.background, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Small live-state line with a dot, as on the session card (« GPS actif »).
struct DrivyStatusDot: View {
    let title: String
    var tone: DrivyTone = .neutral

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tone.foreground).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tone.foreground)
        .accessibilityElement(children: .combine)
    }
}

/// Section title with an optional trailing text action (« Ensuite · Tout voir »).
struct DrivySectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DrivySpacing.xs)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(minHeight: 44)
            }
        }
    }
}

/// Initials in a neutral circle. Never a photo placeholder or a fake logo.
struct DrivyAvatar: View {
    let name: String
    var size: CGFloat = 44
    var isSelected = false

    var body: some View {
        Text(DrivyAvatar.initials(name))
            .font(size > 52 ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
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
struct DrivyNavigationRow: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var badge: DrivyStatusBadge? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.m) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(DrivyTheme.muted)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DrivySpacing.xs)
                if let badge { badge }
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
                ForEach(rows.indices, id: \.self) { index in
                    rows[index]
                    if index < rows.count - 1 { Divider().overlay(DrivyTheme.border) }
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
struct DrivyEmptyState: View {
    let title: String
    let message: String
    var symbol: String = "tray"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: DrivySpacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(DrivyTheme.muted)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                Text(title).font(.headline).foregroundStyle(DrivyTheme.text)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DrivyTheme.accent)
                        .frame(minHeight: 44)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DrivySpacing.s)
        .accessibilityElement(children: .contain)
    }
}

/// Elevated card used for the one dominant decision of a screen
/// (next session, current lesson). Hairline border, no decorative shadow.
struct DrivyCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.canvas, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous)
                    .strokeBorder(DrivyTheme.border, lineWidth: 0.5)
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
