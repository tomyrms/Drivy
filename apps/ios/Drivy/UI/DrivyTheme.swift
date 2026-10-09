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
    /// Decorative continuation only; stations and labels carry the information.
    static let rail = adaptive(0xC3CDD9, 0x3A4757)
    static let disabledText = adaptive(0x5D6A7C, 0xB0BCCC)
    static let disabledSurface = adaptive(0xE8EDF3, 0x222E3E)
    static let route = adaptive(0x245BD6, 0x91B5FF)
    static let routeHalo = adaptive(0xFFFFFF, 0x10151C)
    /// Shadow tint: a deep blue-grey, never pure black, so shadows stay soft on every surface.
    static let shadow = adaptive(0x18212B, 0x05080C)

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

/// Typographic roles. Every screen uses these roles instead of picking a size:
/// screen title (in-content name or date), title (sheet or card lead),
/// section, then the system headline / subheadline / caption for rows.
extension Font {
    static let drivyScreenTitle = Font.largeTitle.weight(.bold)
    static let drivyTitle = Font.title2.weight(.bold)
    static let drivySection = Font.title3.weight(.semibold)
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

/// Column widths and thresholds shared by several screens. A width repeated in
/// two screens is declared here once; map screens keep theirs in DrivyMapLayout.
enum DrivyLayout {
    /// Reading page column (`drivyPageContent` default).
    static let readingColumn: CGFloat = 720
    /// Native Form or List column on iPad, and the bottom action bar under it.
    static let formColumn: CGFloat = 820
    /// Short single-purpose page: sign-in, app lock, session recovery.
    static let narrowColumn: CGFloat = 600
    /// Code entry, created code, reporting sheet.
    static let compactColumn: CGFloat = 560
    /// Master list of a NavigationSplitView (learners, invitations); the detail takes the rest.
    static let splitListMinWidth: CGFloat = 280
    static let splitListIdealWidth: CGFloat = 320
    static let splitListMaxWidth: CGFloat = 360
}

/// Pressed scale of every button, tile and selection card: one feedback for the app.
enum DrivyPress {
    static let scale: CGFloat = 0.96
}

/// Size of a full-width button. `field` is the in-car variant (« Signaler »):
/// larger text and target, read and hit at arm’s length while driving.
enum DrivyButtonSize {
    case regular, field

    var font: Font { self == .field ? .title3.weight(.bold) : .body.weight(.semibold) }
    var minHeight: CGFloat { self == .field ? 64 : 52 }
}

/// Elevation of a surface laid over another (map panel, floating thumb): two soft
/// layers, one tight for the contact edge and one wide for the lift. Colors come from
/// `DrivyTheme.shadow`; outside the map a hairline replaces the shadow.
enum DrivyElevation {
    static let contactOpacity = 0.10
    static let liftOpacity = 0.12
}

extension View {
    /// Soft two-layer shadow from the theme tint. `isOn` false keeps the layout identical without shadow.
    func drivyShadow(_ isOn: Bool = true, radius: CGFloat = 18, y: CGFloat = 4) -> some View {
        shadow(color: DrivyTheme.shadow.opacity(isOn ? DrivyElevation.contactOpacity : 0), radius: 1, y: 0.5)
            .shadow(color: DrivyTheme.shadow.opacity(isOn ? DrivyElevation.liftOpacity : 0), radius: radius, y: y)
    }
}

/// Custom motion only; system transitions are never overridden.
enum DrivyMotion {
    static func trace(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.35) }
    static func settle(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }
    /// Press feedback reacts to the finger: a spring without bounce, interruptible.
    static func press(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(duration: 0.18, bounce: 0) }
    /// System-initiated feedback (state change): short ease-out.
    static func feedback(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.12) }
    static func context(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .snappy(duration: 0.18) }
}

/// The single dominant action of a view. Pressed state is immediate; the
/// small scale is feedback only and disappears under Reduce Motion.
struct DrivyPrimaryButtonStyle: ButtonStyle {
    var size: DrivyButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: size.minHeight)
            .padding(.horizontal, DrivySpacing.m)
            .foregroundStyle(isEnabled ? DrivyTheme.onAccent : DrivyTheme.disabledText)
            .background(
                isEnabled
                    ? (configuration.isPressed ? DrivyTheme.accentPressed : DrivyTheme.accent)
                    : DrivyTheme.disabledSurface,
                in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? DrivyPress.scale : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

/// Companion action next to a primary button. Disabled uses the disabled
/// surface so it never looks tappable; Increase Contrast adds a control border
/// because the muted fill alone barely separates from a white page.
struct DrivySecondaryButtonStyle: ButtonStyle {
    var size: DrivyButtonSize = .regular
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
        return configuration.label
            .font(size.font)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: size.minHeight)
            .padding(.horizontal, DrivySpacing.m)
            .foregroundStyle(isEnabled ? DrivyTheme.accent : DrivyTheme.disabledText)
            .background(
                isEnabled
                    ? (configuration.isPressed ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted)
                    : DrivyTheme.disabledSurface,
                in: shape
            )
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(isEnabled ? DrivyTheme.accent : DrivyTheme.controlBorder, lineWidth: 1)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? DrivyPress.scale : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

/// Grouped block on a reading page (white surface): light fill and hairline,
/// same anatomy as DrivyCard so blocks read identically on every screen.
struct DrivyPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DrivySpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(DrivyGroupedSurface(cornerRadius: DrivyRadius.content + DrivySpacing.m))
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
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Label("Enregistrement à vérifier", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let retry { DrivyRetryButton(action: retry) }
        }
        .foregroundStyle(DrivyTheme.danger)
        .padding(DrivySpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.dangerSurface, in: RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DrivyRadius.content, style: .continuous)
                .strokeBorder(DrivyTheme.danger.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
    }
}
