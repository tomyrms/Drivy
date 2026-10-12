import MapKit
import SwiftUI

extension ObservationStatus {
    var symbol: String {
        switch self {
        case .attention: "exclamationmark"
        case .toWorkOn: "xmark"
        case .positive: "checkmark"
        }
    }

    var color: Color { tone.signal }
    var surface: Color { tone.background }

    /// Status tone: always paired with the status symbol and label.
    var tone: DrivyTone {
        switch self {
        case .attention: .warning
        case .toWorkOn: .danger
        case .positive: .success
        }
    }
}

/// Large tactile tile for the reporting bubble: immediate spring feedback.
/// Under Reduce Motion the scale is replaced by a dimming, so the press is still
/// seen. Selection itself is announced by haptics.
struct DrivyTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && reduceMotion ? DrivyPress.reducedMotionOpacity : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? DrivyPress.scale : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}
