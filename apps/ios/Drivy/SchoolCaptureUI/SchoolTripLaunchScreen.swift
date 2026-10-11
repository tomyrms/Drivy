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
    /// Avancement du départ, de 0 à 1 ; `nil` : pas de barre.
    var progress: Double? = nil
    var progressDuration = 0.5
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var markSize: CGFloat { sizeClass == .regular ? 220 : 168 }
    private var barWidth: CGFloat { sizeClass == .regular ? 160 : 124 }

    var body: some View {
        ZStack {
            // Fond de l’app (`canvas`), pas un noir ou un blanc pur : le rideau se confond avec l’écran qu’il découvre.
            DrivyTheme.canvas.ignoresSafeArea()
            DrivyLaunchMarkLayer(start: start, waits: true)
                .frame(width: markSize, height: markSize)
                .scaleEffect(reduceMotion ? 1 : (isLeaving ? 1.1 : (entered ? 1 : 0.92)))
                .opacity(isLeaving || !entered ? 0 : 1)
                .animation(isLeaving ? .easeIn(duration: 0.24) : .easeOut(duration: 0.3), value: isLeaving)
                .animation(.easeOut(duration: 0.3), value: entered)
            if let progress {
                // Une ligne fine sous le symbole, sans chiffre ni texte : l’étape se lit avec VoiceOver.
                Capsule().fill(DrivyTheme.surfaceMuted)
                    .frame(width: barWidth, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(DrivyTheme.accent)
                            .frame(width: barWidth * min(1, max(0, progress)), height: 3)
                            .animation(.easeOut(duration: progressDuration), value: progress)
                    }
                    .offset(y: markSize / 2 + 40)
                    .opacity(isLeaving || !entered ? 0 : 1)
                    .animation(isLeaving ? .easeIn(duration: 0.24) : .easeOut(duration: 0.3), value: isLeaving)
                    .animation(.easeOut(duration: 0.3), value: entered)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { entered = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Démarrage du trajet")
        .accessibilityValue(step ?? "")
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("capture-quick-start-progress")
    }
}
