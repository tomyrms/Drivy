import SwiftUI
import UIKit

/// Semantic colors from the approved Cartographie native direction.
/// Values mirror `annexes/tokens-proposition.json` (tokens 3.8); never recompute a palette per screen.
enum DrivyTheme {
    static let canvas = adaptive(0xF7F8FA, 0x10151C)
    static let surface = adaptive(0xFFFFFF, 0x19222E)
    static let surfaceMuted = adaptive(0xEEF2F7, 0x222E3E)
    static let text = adaptive(0x18212B, 0xF2F5FA)
    static let muted = adaptive(0x536174, 0xB0BCCC)
    static let accent = adaptive(0x245BD6, 0x91B5FF)
    static let accentPressed = adaptive(0x1947AD, 0xB4CCFF)
    static let onAccent = adaptive(0xFFFFFF, 0x10264D)
    static let accentSoft = adaptive(0xEAF0FE, 0x233859)
    static let success = adaptive(0x17633D, 0x98DBB4)
    static let successSurface = adaptive(0xE9F5EE, 0x18372A)
    static let warning = adaptive(0x7A4D00, 0xF2CB83)
    static let warningSurface = adaptive(0xFFF3D6, 0x382D19)
    static let danger = adaptive(0xB02B37, 0xFFADB4)
    static let dangerSurface = adaptive(0xFDECEF, 0x40252D)
    static let border = adaptive(0xD9E0E9, 0x34445A)
    static let controlBorder = adaptive(0x78869A, 0x71849D)
    static let disabledText = adaptive(0x5D6A7C, 0xB0BCCC)
    static let disabledSurface = adaptive(0xE8EDF3, 0x222E3E)
    static let route = adaptive(0x245BD6, 0x91B5FF)
    static let routeHalo = adaptive(0xFFFFFF, 0x10151C)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

/// Spacing scale from tokens 3.8: 4, 8, 12, 16, 24, 32, 48 points.
enum DrivySpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    /// Horizontal page margin: compact iPhone, then regular width.
    static func page(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .regular ? xl : l }
}

/// Corner radii from tokens 3.8. System controls keep their own geometry.
enum DrivyRadius {
    static let field: CGFloat = 12
    static let content: CGFloat = 16
    static let mapPanel: CGFloat = 24
}

/// Custom motion only; system transitions are never overridden.
enum DrivyMotion {
    /// Press feedback reacts to the finger: a spring without bounce, interruptible.
    static func press(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(duration: 0.18, bounce: 0) }
    /// System-initiated feedback (state change): short ease-out.
    static func feedback(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.12) }
    static func context(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .snappy(duration: 0.18) }
}

/// The single dominant action of a view. Pressed state is immediate; the
/// small scale is feedback only and disappears under Reduce Motion.
struct DrivyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, DrivySpacing.m)
            .foregroundStyle(isEnabled ? DrivyTheme.onAccent : DrivyTheme.disabledText)
            .background(
                isEnabled
                    ? (configuration.isPressed ? DrivyTheme.accentPressed : DrivyTheme.accent)
                    : DrivyTheme.disabledSurface,
                in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

struct DrivySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, DrivySpacing.m)
            .foregroundStyle(isEnabled ? DrivyTheme.accent : DrivyTheme.disabledText)
            .background(
                configuration.isPressed ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted,
                in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

/// Opaque reading surface for forms, contacts and amounts.
struct DrivyPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous))
    }
}

struct StorageCaption: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(DrivyTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

struct InlineErrorView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enregistrement à vérifier", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.subheadline)
            if let retry {
                Button("Réessayer", action: retry)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
                            .stroke(DrivyTheme.danger, lineWidth: 1)
                    }
            }
        }
        .foregroundStyle(DrivyTheme.danger)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.dangerSurface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

extension Date {
    func sessionElapsed(since start: Date) -> String {
        let seconds = max(0, Int(timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%02d:%02d", minutes, seconds % 60)
    }
}
