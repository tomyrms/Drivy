import SwiftUI
import UIKit

/// Semantic colors from the approved Cartographie native direction.
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
    static let warning = adaptive(0x7A4D00, 0xF2CB83)
    static let danger = adaptive(0xB02B37, 0xFFADB4)
    static let dangerSurface = adaptive(0xFDECEF, 0x40252D)
    static let border = adaptive(0xD9E0E9, 0x34445A)

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

struct DrivyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(isEnabled ? DrivyTheme.onAccent : DrivyTheme.muted)
            .background(
                isEnabled
                    ? (configuration.isPressed ? DrivyTheme.accentPressed : DrivyTheme.accent)
                    : DrivyTheme.surfaceMuted,
                in: RoundedRectangle(cornerRadius: 16)
            )
    }
}

struct DrivySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(DrivyTheme.accent)
            .background(
                configuration.isPressed ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted,
                in: RoundedRectangle(cornerRadius: 16)
            )
    }
}

struct DrivyPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrivyTheme.surface, in: RoundedRectangle(cornerRadius: 20))
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
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .foregroundStyle(DrivyTheme.danger)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DrivyTheme.dangerSurface, in: RoundedRectangle(cornerRadius: 16))
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
