import SwiftUI

/// Original vector assets selected from five studies per theme. The control owns
/// its label; the same template adapts to light, dark and increased contrast.
struct SchoolObservationEmblem: View {
    let theme: SchoolLiveObservationTheme
    var size: CGFloat = 40

    private var asset: String {
        switch theme.title {
        case "Priorité à droite": return "right-priority"
        case "Signalisation": return "signage"
        case "Céder le passage": return "give-way"
        case "Stationnement": return "manoeuvres"
        case "Giratoire", "Giratoires": return "intersections"
        case "Autoroute", "Autoroutes": return "motorway"
        case "Vitesse", "Adaptation de la vitesse": return "speed"
        case "Observation", "Observation et contrôles": return "observation"
        case "Anticipation": return "anticipation"
        default:
            switch theme.competency.key {
            case "observation": return "observation"
            case "priorites": return "right-priority"
            case "intersections": return "intersections"
            case "vitesse": return "speed"
            case "placement": return "placement"
            case "manoeuvres", "parking": return "manoeuvres"
            case "autoroute", "motorway": return "motorway"
            case "anticipation": return "anticipation"
            default: return "vehicle"
            }
        }
    }

    var body: some View {
        Image("Observation-\(asset)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(DrivyTheme.accent)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct SchoolMarkerEmblem: View {
    var size: CGFloat = 40
    var body: some View {
        Image("Observation-marker")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(DrivyTheme.muted)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
