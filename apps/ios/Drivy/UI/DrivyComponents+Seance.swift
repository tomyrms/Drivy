import SwiftUI

// Shared anatomy of the map screens (DESIGN/LECON.html): an opaque header and
// an opaque dock posed on the map, Liquid Glass only for the map commands.
// The personal journey (trajet en cours, replay) and the school GPS use these
// same pieces so headers, docks, GPS states and stop commands read identically.

/// State line under the title of a map header: symbol + text + tone, never color alone.
struct DrivyMapStatus {
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
}

extension View {
    /// Opaque panel posed on the map (header, dock). The shadow only expresses the
    /// superposition; outside the map (iPad sidebar, large text) a hairline replaces it.
    func drivyMapPanel(floating: Bool = true) -> some View {
        modifier(DrivyMapPanelModifier(floating: floating))
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
            .shadow(color: .black.opacity(floating ? 0.10 : 0), radius: 16, y: 4)
    }
}

/// Leading command of a map header: close (the journey continues) or back.
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

/// Compact context on top of the map: leading command, title, state line,
/// then trailing content (elapsed time, stop, options). Stacks vertically
/// in accessibility text sizes so nothing is truncated.
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
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: DrivySpacing.xs) {
            Button(action: leading.action) {
                Image(systemName: leading.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(leading.isDisabled ? DrivyTheme.disabledText : DrivyTheme.text)
                    .frame(width: 44, height: 44)
                    .background(DrivyTheme.surfaceMuted, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(leading.isDisabled)
            .accessibilityLabel(leading.label)
            .accessibilityHint(leading.hint ?? "")
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.s))
                : AnyLayout(HStackLayout(spacing: DrivySpacing.xs))
            layout {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    DrivyMapStatusLabel(status: status)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
        }
        .padding(.vertical, DrivySpacing.xs)
        .padding(.leading, DrivySpacing.xs)
        .padding(.trailing, DrivySpacing.s)
        .foregroundStyle(DrivyTheme.text)
        .drivyMapPanel(floating: floating)
    }
}

extension DrivyMapHeader where Trailing == EmptyView {
    init(title: String, status: DrivyMapStatus, leading: DrivyMapHeaderAction, floating: Bool = true) {
        self.init(title: title, status: status, leading: leading, floating: floating) { EmptyView() }
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

/// Critical stop command in the map header: 48 pt, danger tone, always confirmed by the caller.
struct DrivyMapStopButton: View {
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? DrivyTheme.danger : DrivyTheme.disabledText)
                .frame(width: 48, height: 48)
                .background(isEnabled ? DrivyTheme.dangerSurface : DrivyTheme.disabledSurface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

/// Bottom dock posed on the map: one opaque panel holding the state, the
/// observations link and the commands. The dominant action goes last.
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

/// Follow / show-whole-route commands floating on the map, in Liquid Glass,
/// grouped so the two circles blend. Identical on every map screen.
struct DrivyMapControls: View {
    @Binding var followsPosition: Bool
    var followLabel = "Suivre la dernière position enregistrée"
    var canFollow = true
    let showWholeRoute: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: DrivySpacing.xs) {
            HStack(spacing: DrivySpacing.xs) {
                Button { followsPosition.toggle() } label: {
                    Image(systemName: followsPosition ? "location.fill" : "location")
                        .font(.title3)
                        .foregroundStyle(followsPosition ? DrivyTheme.accent : canFollow ? DrivyTheme.text : DrivyTheme.disabledText)
                        .frame(width: 48, height: 48)
                        .drivyMapControl(in: Circle())
                }
                .disabled(!canFollow && !followsPosition)
                .accessibilityLabel(followsPosition ? "Arrêter le suivi de position" : followLabel)
                .accessibilityAddTraits(followsPosition ? [.isSelected] : [])
                Button(action: showWholeRoute) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .foregroundStyle(DrivyTheme.text)
                        .frame(width: 48, height: 48)
                        .drivyMapControl(in: Circle())
                }
                .accessibilityLabel("Voir tout le trajet")
            }
        }
        .buttonStyle(.plain)
    }
}

/// Replaces the map when there is no position to show: never a broken map,
/// never an invented location.
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

/// Map screen gutters, shared by the personal journey, the replay and the school GPS.
enum DrivyMapLayout {
    /// Width from which the dock moves into a sidebar next to the map (iPad).
    static let sidebarBreakpoint: CGFloat = 760
    static let sidebarWidth: CGFloat = 360
    /// Height of the inline map in accessibility text sizes.
    static let accessibleMapHeight: CGFloat = 230
    /// Readable column in accessibility text sizes.
    static let accessibleMaxWidth: CGFloat = 680
}
