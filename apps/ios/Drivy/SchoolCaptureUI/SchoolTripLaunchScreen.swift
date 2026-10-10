import SwiftUI

/// Départ d’un trajet : le symbole Drivy seul, sur fond uni, pendant que la leçon, la localisation et
/// l’appareil sont vérifiés. La séquence se joue une fois depuis `start` ; si la préparation dure plus
/// longtemps, le symbole reste et l’anneau respire à peine. Aucun texte visible : l’étape se lit avec VoiceOver.
struct SchoolTripLaunchScreen: View {
    let start: Date
    /// Étape en cours de la préparation, annoncée seulement aux technologies d’assistance.
    var step: String? = nil
    /// Le rideau se lève : le symbole se retire avant le fond.
    var isLeaving = false
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack {
            // Fond de l’app (`canvas`), pas un noir ou un blanc pur : le rideau se confond avec l’écran qu’il découvre.
            DrivyTheme.canvas.ignoresSafeArea()
            DrivyLaunchMarkLayer(start: start, waits: true)
                .frame(width: sizeClass == .regular ? 220 : 168, height: sizeClass == .regular ? 220 : 168)
                .scaleEffect(reduceMotion ? 1 : (isLeaving ? 1.1 : (entered ? 1 : 0.92)))
                .opacity(isLeaving || !entered ? 0 : 1)
                .animation(isLeaving ? .easeIn(duration: 0.24) : .easeOut(duration: 0.3), value: isLeaving)
                .animation(.easeOut(duration: 0.3), value: entered)
        }
        .onAppear { entered = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Démarrage du trajet")
        .accessibilityValue(step ?? "")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("capture-quick-start-progress")
    }
}
