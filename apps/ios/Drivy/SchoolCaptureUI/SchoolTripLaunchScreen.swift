import SwiftUI

/// Départ d’un trajet : le symbole Drivy seul, sur fond uni, pendant que la leçon, la localisation et
/// l’appareil sont vérifiés. La séquence se joue une fois depuis `start` ; si la préparation dure plus
/// longtemps, le symbole reste et l’anneau respire à peine. Aucun texte visible : l’étape se lit avec VoiceOver.
struct SchoolTripLaunchScreen: View {
    let start: Date
    /// Étape en cours de la préparation, annoncée seulement aux technologies d’assistance.
    var step: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea()
            DrivyLaunchMark(choreography: .join, start: start, waits: true)
                .frame(width: sizeClass == .regular ? 220 : 168, height: sizeClass == .regular ? 220 : 168)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Démarrage du trajet")
        .accessibilityValue(step ?? "")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("capture-quick-start-progress")
    }
}
