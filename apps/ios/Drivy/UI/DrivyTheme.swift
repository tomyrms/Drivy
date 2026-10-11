import SwiftUI
import UIKit

/// Semantic colors of the native client. Light values are the approved Cartographie native
/// direction (tokens 3.8) and never change here. Dark values are « Soft Charcoal »: a neutral
/// anthracite where a block is lighter than the page it sits on, never an inverted light theme.
/// Never recompute a palette per screen; decisions are in docs/implementation/dark-soft-charcoal-20261011.md.
enum DrivyTheme {
    // Pages: the darkest level. A sheet or popover is one step lighter (system elevated level).
    /// Background of grouped forms and lists.
    static let canvas = adaptive(0xF7F8FA, 0x17191C, elevated: 0x1D1F23)
    /// Background of reading pages.
    static let surface = adaptive(0xFFFFFF, 0x17191C, elevated: 0x1D1F23)

    // Blocks: one step above the page.
    /// Fill of DrivyCard, DrivyPanel, selection cards and grouped rows.
    static let surfaceCard = adaptive(0xF7F8FA, 0x272A2E, elevated: 0x2A2D31)
    /// Block laid over a page or over the map: map panel, banner, marker, thumb.
    static let surfaceRaised = adaptive(0xFFFFFF, 0x272A2E, elevated: 0x2A2D31)
    /// Interactive or neutral fill: secondary button, neutral pill, avatar, pressed row.
    static let surfaceMuted = adaptive(0xEEF2F7, 0x34383D, elevated: 0x373B40)

    static let text = adaptive(0x18212B, 0xF4F5F6)
    static let muted = adaptive(0x536174, 0xA1A5AD, darkHighContrast: 0xC2C6CD)
    /// Decorative glyphs only (chevrons): never the sole carrier of an information.
    static let textTertiary = adaptive(0x536174, 0x8E939C, darkHighContrast: 0xA1A5AD)
    /// Chevron of a row inside a native grouped list: the system's own, so a Drivy row and a NavigationLink
    /// sitting in the same section show the same glyph in both appearances.
    static let listChevron = Color(uiColor: .tertiaryLabel)

    /// Accent as ink: links, symbols, selection outline, system tint.
    static let accent = adaptive(0x245BD6, 0x86ABF8, darkHighContrast: 0xA8C3FB)
    /// Accent as a filled control carrying `onAccent` (primary button, selected day).
    static let accentFill = adaptive(0x245BD6, 0x3D70E2)
    static let accentPressed = adaptive(0x1947AD, 0x325FC4)
    static let onAccent = adaptive(0xFFFFFF, 0xFFFFFF)
    static let accentSoft = adaptive(0xEAF0FE, 0x2F3B54)

    static let success = adaptive(0x17633D, 0x7CCFA0)
    static let successSurface = adaptive(0xE9F5EE, 0x2B423B)
    static let warning = adaptive(0x7A4D00, 0xE5BE7A)
    static let warningSurface = adaptive(0xFFF3D6, 0x453E30)
    static let danger = adaptive(0xB02B37, 0xFF9DA3)
    static let dangerSurface = adaptive(0xFDECEF, 0x473338)

    static let border = adaptive(0xD9E0E9, 0x3A3E44, darkHighContrast: 0x5C616A)
    static let controlBorder = adaptive(0x78869A, 0x82878F, darkHighContrast: 0xA1A5AD)
    /// Decorative continuation only; stations and labels carry the information.
    static let rail = adaptive(0xC3CDD9, 0x454A51)
    static let disabledText = adaptive(0x5D6A7C, 0x7A7F87)
    static let disabledSurface = adaptive(0xE8EDF3, 0x303338)

    /// Measured trace on the map: the reference blue of the dark theme, on a page-colored halo.
    static let route = adaptive(0x245BD6, 0x4D80EB)
    static let routeHalo = adaptive(0xFFFFFF, 0x17191C)
    /// Shadow tint: a deep blue-grey in light, black in dark where only a strong shadow reads.
    static let shadow = adaptive(0x18212B, 0x000000)
    /// Veil behind a palette opened over the map. Light keeps the shadow tint at 16 %.
    static let scrim = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0, alpha: 0.45)
            : UIColor(red: 0x18 / 255, green: 0x21 / 255, blue: 0x2B / 255, alpha: 0.16)
    })

    /// The light value never depends on elevation or contrast: only the dark appearance has variants.
    private static func adaptive(_ light: UInt32, _ dark: UInt32, elevated: UInt32? = nil,
                                 darkHighContrast: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            var value = light
            if traits.userInterfaceStyle == .dark {
                value = dark
                if let elevated, traits.userInterfaceLevel == .elevated { value = elevated }
                if let darkHighContrast, traits.accessibilityContrast == .high { value = darkHighContrast }
            }
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
    /// A block of rows laid on the canvas outside a native List: the rounding of the system's grouped sections.
    static let groupedBlock: CGFloat = 26
}

/// Column widths and thresholds shared by several screens. A width repeated in
/// two screens is declared here once; map screens keep theirs in DrivyMapLayout.
enum DrivyLayout {
    /// Smallest hit target of any control (HIG); primary and critical actions use DrivyButtonSize instead.
    static let tapTarget: CGFloat = 44
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
    /// Under Reduce Motion, a style whose only feedback is the scale dims instead.
    static let reducedMotionOpacity: Double = 0.6
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
/// `DrivyTheme.shadow`; outside the map a hairline replaces the shadow. On a dark map a
/// soft shadow disappears, so the dark appearance uses stronger layers.
enum DrivyElevation {
    static let contactOpacity = 0.10
    static let liftOpacity = 0.12
    static let darkContactOpacity = 0.45
    static let darkLiftOpacity = 0.38
}

extension View {
    /// Soft two-layer shadow from the theme tint. `isOn` false keeps the layout identical without shadow.
    func drivyShadow(_ isOn: Bool = true, radius: CGFloat = 18, y: CGFloat = 4) -> some View {
        modifier(DrivyShadowModifier(isOn: isOn, radius: radius, y: y))
    }
}

private struct DrivyShadowModifier: ViewModifier {
    let isOn: Bool
    let radius: CGFloat
    let y: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let contact = dark ? DrivyElevation.darkContactOpacity : DrivyElevation.contactOpacity
        let lift = dark ? DrivyElevation.darkLiftOpacity : DrivyElevation.liftOpacity
        return content
            .shadow(color: DrivyTheme.shadow.opacity(isOn ? contact : 0), radius: 1, y: 0.5)
            .shadow(color: DrivyTheme.shadow.opacity(isOn ? lift : 0), radius: radius, y: y)
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
    /// Passage d’une étape à la suivante dans une même feuille : ressort court, à peine rebondi. Sous Réduire
    /// les animations, un fondu bref seulement (les transitions d’étape deviennent elles aussi des fondus).
    static func step(_ reduceMotion: Bool) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.38, bounce: 0.12) }
    /// Contenu qui arrive après une lecture (accord, formation) : il se pose sans pousser brutalement le reste.
    static func reveal(_ reduceMotion: Bool) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3) }
    /// Ouverture et fermeture d’un panneau posé sur l’écran (palette de signalement) : vif, sans rebond. Sous
    /// Réduire les animations, la transition du panneau devient un fondu, jamais une apparition sèche.
    static func present(_ reduceMotion: Bool) -> Animation { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.24, extraBounce: 0) }
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
                    ? (configuration.isPressed ? DrivyTheme.accentPressed : DrivyTheme.accentFill)
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

/// Action written as text next to what it concerns (« Planifier une leçon », « Modifier les informations »,
/// « Effacer la recherche »): accent ink, subheadline semibold, a 44 pt target across its whole frame. It is the
/// one look of a secondary action outside the bottom bar; pressed, it dims briefly like a system text button.
struct DrivyTextActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.leading)
            .foregroundStyle(isEnabled ? DrivyTheme.accent : DrivyTheme.disabledText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: DrivyLayout.tapTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? DrivyPress.reducedMotionOpacity : 1)
            .animation(DrivyMotion.feedback(reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DrivyTextActionStyle {
    /// `.buttonStyle(.drivyText)`: see DrivyTextActionStyle.
    static var drivyText: DrivyTextActionStyle { DrivyTextActionStyle() }
}
