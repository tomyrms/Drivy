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

    var color: Color { tone.foreground }
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

/// Large tactile tile for the reporting bubble: immediate spring feedback,
/// removed under Reduce Motion. Selection itself is announced by haptics.
struct DrivyTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

/// A geographic overview is only a map camera, never a recorded location.
enum JourneyMapRegion {
    static let overview = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.8, longitude: 8.2),
        span: MKCoordinateSpan(latitudeDelta: 2.7, longitudeDelta: 4.5))
}
