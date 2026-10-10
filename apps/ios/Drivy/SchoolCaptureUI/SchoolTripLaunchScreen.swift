import SwiftUI

/// Départ d’un trajet : pendant que la leçon, la localisation et l’appareil sont vérifiés, tout l’écran porte
/// la marque. La trace se dessine en boucle vers son repère ; l’étape en cours se lit dessous.
/// Sans mouvement (Réduire les animations), la marque reste fixe et un indicateur système dit l’attente.
struct SchoolTripLaunchScreen: View {
    /// Étapes du départ, dans l’ordre où la préparation les annonce.
    static let steps = ["Vérification de la leçon…", "Localisation…", "Mesure GPS…", "Vérification de l’appareil…", "Démarrage du trajet…"]

    let step: String
    var learnerName: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var pulsing = false

    private var reached: Int { Self.steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(spacing: DrivySpacing.xl) {
            Spacer(minLength: DrivySpacing.l)
            mark
            VStack(spacing: DrivySpacing.s) {
                if let learnerName {
                    Text(learnerName)
                        .font(.subheadline)
                        .foregroundStyle(DrivyTheme.muted)
                        .lineLimit(1)
                }
                Text(step)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DrivyTheme.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: step)
                progress
                if reduceMotion { ProgressView().padding(.top, DrivySpacing.xs).accessibilityHidden(true) }
            }
            .padding(.horizontal, DrivySpacing.l)
            Spacer(minLength: DrivySpacing.l)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DrivyTheme.canvas.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(learnerName.map { "Départ du trajet avec \($0)" } ?? "Départ du trajet")
        .accessibilityValue(step)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("capture-quick-start-progress")
        .onAppear {
            guard !reduceMotion else { drawn = true; return }
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { drawn = true }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true }
        }
    }

    /// La trace se dessine du haut vers son repère, qui répond par une onde : le geste de la marque, en boucle.
    private var mark: some View {
        ZStack {
            Circle()
                .fill(DrivyTheme.accentSoft)
                .frame(width: 208, height: 208)
            if !reduceMotion {
                Circle()
                    .strokeBorder(DrivyTheme.accent, lineWidth: 2)
                    .frame(width: 208, height: 208)
                    .scaleEffect(pulsing ? 1.28 : 1)
                    .opacity(pulsing ? 0 : 0.35)
            }
            Image("DrivyBrandTrace")
                .resizable()
                .scaledToFit()
                .mask(alignment: .top) { Rectangle().scaleEffect(y: drawn ? 1 : 0.18, anchor: .top) }
                .frame(width: 128, height: 128)
            Image("DrivyBrandMarker")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .scaleEffect(reduceMotion || drawn ? 1 : 0.94)
        }
        .accessibilityHidden(true)
    }

    /// Cinq stations sur la trace : celles déjà franchies sont pleines.
    private var progress: some View {
        HStack(spacing: DrivySpacing.xs) {
            ForEach(Self.steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= reached ? DrivyTheme.accent : DrivyTheme.controlBorder.opacity(0.35))
                    .frame(width: index == reached ? 28 : 12, height: 4)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: reached)
        .padding(.top, DrivySpacing.xs)
        .accessibilityHidden(true)
    }
}
