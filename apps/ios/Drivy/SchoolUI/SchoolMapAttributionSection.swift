import SwiftUI

/// Attribution for OSRM's road data, separate from MapKit's own map attribution.
/// The public link is fixed and carries no school, capture or location information.
struct SchoolMapAttributionSection: View {
    static let copyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!

    var body: some View {
        Section {
            Link("© contributeurs OpenStreetMap", destination: Self.copyrightURL)
                .foregroundStyle(DrivyTheme.text)
                .accessibilityIdentifier("openstreetmap-attribution")
        } header: {
            Text("Recalage routier").drivyFormSectionHeader()
        }
        .drivyFormRows()
    }
}
