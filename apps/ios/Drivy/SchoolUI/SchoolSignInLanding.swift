import SwiftUI

/// Présentation de connexion ; l'identité et l'autorisation restent dans la racine.
/// Les quatre états (prêt, connexion en cours, échec, non configuré) gardent la même
/// charpente : la trace sur son aplat de marque, la promesse, puis au plus un message
/// au-dessus des actions. L'ensemble est centré dans l'espace au-dessus des boutons.
struct SchoolSignInLanding: View {
    let isConfigured: Bool
    let isWorking: Bool
    let errorMessage: String?
    let canPresent: Bool
    let signIn: () -> Void
    let joinWithCode: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var glyphHeight: CGFloat = 148

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                    hero
                    Text("Tes leçons, tes trajets, ton école.")
                        .font(.drivyScreenTitle)
                        .lineSpacing(DrivySpacing.xxs)
                        .foregroundStyle(DrivyTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !isConfigured {
                        DrivyInlineMessage(text: "La connexion n’est pas activée dans cette version.", tone: .neutral)
                            .accessibilityIdentifier("school-not-configured")
                    } else if let errorMessage, !isWorking {
                        SchoolErrorNotice(message: errorMessage)
                    }
                }
                // Centre optique : l’ensemble se tient un peu au-dessus du milieu, loin des boutons.
                .padding(.bottom, DrivySpacing.xxl)
                .drivyPageContent(maxWidth: DrivyLayout.narrowColumn)
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(DrivyTheme.surface)
        // Un seul grand titre : la promesse. « Drivy » reste un titre de barre discret.
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isConfigured {
                DrivyStickyActionBar {
                    Button(action: signIn) {
                        DrivyBusyLabel(title: "Se connecter", busyTitle: "Connexion…", isBusy: isWorking)
                    }
                    .buttonStyle(DrivyPrimaryButtonStyle())
                    .accessibilityIdentifier("school-sign-in")
                    Button(action: joinWithCode) { Label("J’ai un code", systemImage: "number") }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .accessibilityIdentifier("school-sign-in-with-code")
                }
                .disabled(isWorking || !canPresent)
            }
        }
    }

    /// Aplat de marque doux, trace au centre : le trajet est l'image de l'app. Profondeur par filet, sans ombre ni dégradé.
    private var hero: some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.mapPanel, style: .continuous)
        return DrivyRouteGlyph()
            .frame(height: glyphHeight)
            .padding(.vertical, DrivySpacing.xl)
            .padding(.horizontal, DrivySpacing.l)
            .frame(maxWidth: .infinity)
            .background(DrivyTheme.accentSoft, in: shape)
            .overlay { shape.strokeBorder(DrivyTheme.border, lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}
